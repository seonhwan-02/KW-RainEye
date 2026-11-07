%% 01_check.m — 01_kre_lib.md 5절(코드 검토) 지적 확인용
% 실행: MATLAB에서 이 파일을 열고 F5 (dp 폴더가 자동으로 path에 들어간다). 그림은 그리지 않는다.
% 결과 한 줄 형식: CHECK n: PASS/FAIL - 설명
%   PASS = 코드가 의도대로 동작함 (지적이 오해이거나 버그가 없음)
%   FAIL = 지적이 맞음 (또는 실행 오류로 확인하지 못함 — 설명에 적힘)
% 1~9 중 2·4번만 실제 2023 자료(캐시)를 읽고, 나머지는 작은 가짜 자료로 확인한다.
root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(fullfile(root, 'dp'));
L = kre_lib();  P0 = L.params();
tAll = tic;

% ---- 공용 가짜 자료: 실제와 같은 0.1° 격자(북위 28~40°, 동경 119~132°), 30분 칸 96개(2일), 비 없음 ----
lat = (28.05:0.1:39.95)';  lon = (119.05:0.1:131.95)';  nT = 96;
D0 = struct('Pr', zeros(numel(lat), numel(lon), nT, 'single'), 'lat', lat, 'lon', lon, 'nT', nT, ...
    't0', datetime(2023, 6, 1, 'TimeZone', 'UTC'), 'year', 2023, 'src', 'final', ...
    'kmLat', 110.57 * 0.1, 'kmLon', 111.32 * 0.1 * cosd(mean(lat)), 'motion', zeros(nT, 2));
D0.tSlot = D0.t0 + seconds((0:nT - 1)' * 1800);
% 가짜 학습 표: 큐 강도 구간이 높을수록 확률이 커지는 단순한 표 (행 11개 = 구간, 열 2개 = 30분/60분 앞)
calib0 = struct('edges', P0.edges, 'lags', P0.lags, 'pHeavy', repmat(linspace(0, 1, 11)', 1, 2), ...
    'pRain', repmat(linspace(0, 1, 11)', 1, 2));
% 5번째 칸(7200~9000초)에만 호우 덩어리가 있는 자료 (북위 30.45~31.95°, 동경 124.95~126.45°)
D1 = D0;  D1.Pr(25:40, 60:75, 5) = 20;  D1.motion(5, :) = [0.01 0.005];
seed = @(s) RandStream('mt19937ar', 'Seed', s);

%% CHECK 1 — 큐가 미래 장면을 보는가 (cueSlot/cueScene/rewardGrid)
try
    ts = 5 * 1800 + 1000;                                      % 6번째 칸이 시작하고 1000초 뒤에 통과 시작
    G = fakePass(ts, 120, 31, 126, nT);
    [~, ~, info] = L.rewardGrid(G, D1, P0, 'nowcast', seed(1), calib0);
    kc = info.kc;  tCue = ts - P0.cueL * 60;                   % 큐 시각 = 통과 15분 전
    okSlot = kc * 1800 <= tCue && (kc + 1) * 1800 > tCue;      % kc칸은 큐 시각 전에 끝났고, 다음 칸은 아직 안 끝남
    % 경계: 큐 시각이 칸의 끝과 정확히 같으면 그 칸(5), 1초 모자라면 앞 칸(4)
    [~, ~, iA] = L.rewardGrid(fakePass(5 * 1800 + 900, 120, 31, 126, nT), D1, P0, 'nowcast', seed(1), calib0);
    [~, ~, iB] = L.rewardGrid(fakePass(5 * 1800 + 899, 120, 31, 126, nT), D1, P0, 'nowcast', seed(1), calib0);
    okEdge = iA.kc == 5 && iB.kc == 4;
    % kc 뒤의 장면과 이동 벡터를 전부 바꿔도 보상 표가 그대로인가 (같은 씨앗)
    Rw1 = L.rewardGrid(G, D1, P0, 'nowcast', seed(1), calib0);
    D2 = D1;  D2.Pr(:, :, kc + 1:end) = 30;  D2.motion(kc + 1:end, :) = 0.05;
    Rw2 = L.rewardGrid(G, D2, P0, 'nowcast', seed(1), calib0);
    D3 = D1;  D3.Pr(:, :, kc) = 0;                             % 반대로 kc 장면을 지우면 달라져야 한다
    Rw3 = L.rewardGrid(G, D3, P0, 'nowcast', seed(1), calib0);
    okLeak = isequal(Rw1, Rw2) && ~isequal(Rw1, Rw3) && any(Rw1(:) > 0);
    report(1, okSlot && okEdge && okLeak, sprintf(['통과 시작 %d초, 큐 시각 %d초 → 쓴 칸 kc=%d (%d~%d초, 큐 시각 전에 끝남). ' ...
        'kc 뒤 장면·이동 벡터를 바꿔도 보상 표 동일 → 미래 정보 누수 없음'], ts, tCue, kc, (kc - 1) * 1800, kc * 1800), ...
        sprintf('큐 칸 선택 또는 미래 장면 의존이 발견됨 (okSlot=%d okEdge=%d okLeak=%d)', okSlot, okEdge, okLeak));
catch ME
    report(1, false, '', ['실행 오류로 확인 못 함: ' ME.message]);
end

%% CHECK 3 — 이동 벡터 [동, 북] km/s 부호·단위와 나우캐스트 이동 방향 (가짜 자료)
try
    P3 = P0;  P3.pDet = 1;  P3.posSd = 0;  P3.velSd = 0;       % 무작위 오차 끔
    ts = 5 * 1800 + 1000;  G = fakePass(ts, 30, 31, 126.05, nT);   % 북쪽으로 가는 통과, 천저 = 동경 126.05°(칸 중심)
    D4 = D0;  D4.Pr(lat > 30.5 & lat < 34, abs(lon - 126.05) < 1e-6, 5) = 20;   % 천저 바로 밑 폭 1칸(0.1°)의 남북 띠
    D4.motion(5, :) = [0.02 0];                                % 동쪽으로 20 m/s
    tRef = (5 - 0.5) * 1800;  dt = G.tq(1) - tRef;             % 큐 장면 가운데 시각 → 첫 표본까지 1900초
    thExp = round(atand(-0.02 * dt / P0.h));                   % 38 km 동쪽 = 빔각 약 -4° (+ 가 서쪽이므로 음수)
    [RwN, th] = L.rewardGrid(G, D4, P3, 'nowcast', seed(1), calib0);
    [~, jN] = max(RwN(1, :));
    RwP = L.rewardGrid(G, D4, P3, 'persist', seed(1), calib0);
    [~, jP] = max(RwP(1, :));
    ok = th(jN) == thExp && th(jP) == 0 && nnz(RwN(1, :) > 0) == 1;
    report(3, ok, sprintf(['동쪽 20 m/s × %d초 = %.0f km → 나우캐스트 최대 보상 빔각 %d° (예상 %d°), 위치고정은 0°. ' ...
        'km/s·초·km/도 단위와 [동, 북] 부호가 맞음'], dt, 0.02 * dt, th(jN), thExp), ...
        sprintf('나우캐스트 최대 보상이 %d°에 나옴 (예상 %d°), 위치고정 %d° (예상 0°)', th(jN), thExp, th(jP)));
catch ME
    report(3, false, '', ['실행 오류로 확인 못 함: ' ME.message]);
end

%% CHECK 5 — dpPlan: 기동 중 놓치는 표본 수와 최적성 (모든 경로를 다 세어 본 값과 비교)
try
    % (a) 0° → 1° 기동: 1/1.5 + 4 = 4.67초 → ceil(4.67/1.5) = 4 표본을 건너뛴다
    th = -P0.maxDeg:P0.stepDeg:P0.maxDeg;  j0 = find(th == 0);  j1 = find(th == 1);
    Rw = zeros(12, numel(th));  Rw(1:3, j0) = 1;  Rw(8:12, j1) = 1;
    plan = L.dpPlan(Rw, th, P0);
    mExp = ceil((1 / P0.slewRate + P0.settle) / P0.profDt);
    okM = mExp == 4 && isequal(find(isnan(plan.th))', 4:7) && abs(plan.score - 8) < 1e-3 && plan.nMoves == 1;
    % (b) 작은 표(표본 8 × 빔각 3)에서 가능한 경로 4^8개를 모두 세어 본 최댓값 = DP 점수인가
    Pb = P0;  Pb.settle = 1;  thb = [-1 0 1];  nq = 8;  nj = 3;
    dth = abs(thb(:) - thb(:)');  mb = ceil((dth / Pb.slewRate + Pb.settle) / Pb.profDt);  mb(dth == 0) = 0;
    rs = seed(3);  okBF = true;  gap = 0;
    for trial = 1:2
        Rwb = rand(rs, nq, nj);
        pl = L.dpPlan(Rwb, thb, Pb);
        sq = zeros(1, nq);  v = find(pl.valid)';
        for q = v, sq(q) = find(thb == pl.th(q)); end
        own = sum(Rwb(sub2ind([nq nj], v, sq(v))));            % DP가 낸 경로를 직접 다시 채점
        best = bruteForce(Rwb, mb);
        gap = max(gap, abs(best - pl.score));
        okBF = okBF && feasible(sq, mb) && abs(own - pl.score) < 1e-3 && abs(best - pl.score) < 1e-3;
    end
    report(5, okM && okBF, sprintf(['1° 기동 시 놓치는 표본 %d개(= 6초 ≥ 4.67초, 표본 하나가 1.5초 관측이므로 맞음), ' ...
        '점수 8.000 재현. 4^8개 경로 전수 조사 최댓값과 DP 점수 차이 %.1e → 최적'], mExp, gap), ...
        sprintf('놓치는 표본 수 또는 최적성 불일치 (okM=%d okBF=%d, 차이 %.3g)', okM, okBF, gap));
catch ME
    report(5, false, '', ['실행 오류로 확인 못 함: ' ME.message]);
end

%% CHECK 6 — rewardGrid의 학습 표 열 선택이 P.lags = 1:n 을 가정하는가
try
    ts = 5 * 1800 + 100;  G = fakePass(ts, 30, 31, 126, nT);   % 큐 시각 8200초 → kc=4, 관측 칸 6 → 2칸(60분) 앞
    D6 = D0;  D6.Pr(:, :, 4) = 20;                             % 큐 장면 전체 20 mm/h
    P6 = P0;  P6.pDet = 1;  P6.posSd = 0;  P6.velSd = 0;
    cA = calib0;  cA.pHeavy = [zeros(11, 1) ones(11, 1)];  cA.pRain = zeros(11, 2);   % 30분 열 = 0, 60분 열 = 1
    [RwA, ~, iA] = L.rewardGrid(G, D6, P6, 'nowcast', seed(1), cA);
    okDefault = iA.kc == 4 && all(G.kq == 6) && all(abs(RwA(:) - 1) < 1e-9);          % 60분 열을 골랐나
    P6b = P6;  P6b.lags = [2 3];                               % 1부터 연속이 아닌 lags
    cB = cA;  cB.lags = [2 3];  cB.pHeavy = [ones(11, 1) zeros(11, 1)];               % 이제 1열이 '2칸 앞'
    RwB = L.rewardGrid(G, D6, P6b, 'nowcast', seed(1), cB);
    okNonContig = all(abs(RwB(:) - 1) < 1e-9);
    report(6, okDefault && okNonContig, '기본 lags=[1 2]와 [2 3] 모두에서 바른 열을 고름', ...
        sprintf(['기본 lags=[1 2]에서는 바른 열(60분)을 고름(%d)이지만, lags=[2 3]처럼 1부터 연속이 아니면 틀린 열을 고름(%d). ' ...
        '지적 맞음 — 개선 제안: 현재 모든 스크립트는 1:n만 쓰므로 결과에는 영향 없음'], okDefault, okNonContig));
catch ME
    report(6, false, '', ['실행 오류로 확인 못 함: ' ME.message]);
end

%% CHECK 7 — 난수 시드 재현성 (rewardGrid·calibrate·orbitPasses)
try
    G = fakePass(5 * 1800 + 1000, 120, 31, 126, nT);
    P7 = P0;  P7.posSd = 30;                                   % 위치오차를 크게 해 씨앗이 다르면 반드시 달라지게
    Rw1 = L.rewardGrid(G, D1, P7, 'nowcast', seed(11), calib0);
    Rw2 = L.rewardGrid(G, D1, P7, 'nowcast', seed(11), calib0);
    Rw3 = L.rewardGrid(G, D1, P7, 'nowcast', seed(12), calib0);
    okRw = isequal(Rw1, Rw2) && ~isequal(Rw1, Rw3);
    [pa, pha] = L.orbitPasses(D0, P0, 1);  [pb, phb] = L.orbitPasses(D0, P0, 1);
    okOrb = isequal(pha, phb) && numel(pa) == numel(pb) && numel(pa) > 0 && ...
        isequal(cellfun(@(g) g.ts, pa), cellfun(@(g) g.ts, pb));
    Dc = smallSeason(seed(5));
    c1 = L.calibrate(Dc, P0, 'nowcast', 5);  c2 = L.calibrate(Dc, P0, 'nowcast', 5);
    okCal = isequal(c1.pHeavy, c2.pHeavy) && isequal(c1.count, c2.count);
    report(7, okRw && okOrb && okCal, sprintf(['같은 씨앗 → 보상 표·학습 표 동일, 다른 씨앗 → 보상 표 다름; ' ...
        'orbitPasses는 안에서 씨앗 7을 고정해 두 번 불러도 같은 위상·같은 통과 %d회'], numel(pa)), ...
        sprintf('재현성 깨짐 (okRw=%d okOrb=%d okCal=%d)', okRw, okOrb, okCal));
catch ME
    report(7, false, '', ['실행 오류로 확인 못 함: ' ME.message]);
end

%% CHECK 8 — 경계: ±10° 포함, 자료 밖 빔(NaN) 처리, 큐가 없는 시즌 첫 45분
try
    Ge = fakePass(5 * 1800 + 1000, 120, 31, 119.55, nT);       % 서쪽(+) 빔은 자료 영역(동경 119.05° 이상) 밖으로 나간다
    [Rw, th] = L.rewardGrid(Ge, D1, P0, 'nowcast', seed(1), calib0);
    Ro = L.rewardGrid(Ge, D1, P0, 'oracle', [], []);
    okTh = th(1) == -10 && th(end) == 10 && numel(th) == 21;
    okNaN = all(isfinite(Rw(:))) && all(isfinite(Ro(:))) && isfinite(L.heavyInSwath(Ge, D1, P0));
    Gn = fakePass(1800 + 900, 120, 31, 126, nT);               % 큐 시각 1800초 → kc=1 < 2 → 큐 없음
    [Rn, thn, in] = L.rewardGrid(Gn, D1, P0, 'nowcast', seed(1), calib0);
    pn = L.dpPlan(Rn, thn, P0);  gn = L.greedyPlan(Gn, D1, P0, 'nowcast', seed(1));
    okNoCue = isnan(in.kc) && all(Rn(:) == 0) && all(pn.th == 0) && all(pn.valid) && gn.nTargets == 0;
    report(8, okTh && okNaN && okNoCue, ['빔각 -10~10° 21개 포함, 자료 밖 빔은 NaN→0으로 보상 표에 NaN 없음, ' ...
        '큐 없는 통과(kc<2)는 보상 0 → DP 천저 유지·기존 방식 표적 0'], ...
        sprintf('경계 처리 문제 (okTh=%d okNaN=%d okNoCue=%d)', okTh, okNaN, okNoCue));
catch ME
    report(8, false, '', ['실행 오류로 확인 못 함: ' ME.message]);
end

%% CHECK 9 — calibrate: 장면 범위(k = 2 ~ nT-2)와 표 값
try
    Dc = smallSeason(seed(5));  Dc.Pr(:) = 0;  Dc.Pr(1:10, :, :) = 20;   % 남쪽 절반 20 mm/h(호우), 북쪽 절반 0, 모든 칸 같음
    Pc = P0;  Pc.pDet = 1;  Pc.posSd = 0;  Pc.velSd = 0;
    c = L.calibrate(Dc, Pc, 'nowcast', 1);
    nScene = Dc.nT - 1 - max(Pc.lags);                         % k = 2..nT-2 → 9장면
    nCell = numel(Dc.lat) * numel(Dc.lon);                     % 400칸
    b20 = discretize(20, Pc.edges);  b0 = discretize(0, Pc.edges);   % 20 → '20~30' 구간, 0 → '0~0.5' 구간
    okCnt = all(sum(c.count, 1) == nScene * nCell) && all(c.count(b20, :) == nScene * nCell / 2) && all(c.count(b0, :) == nScene * nCell / 2);
    okP = all(c.pHeavy(b20, :) == 1) && all(c.pHeavy(b0, :) == 0) && all(c.pRain(b20, :) == 1) && all(c.pRain(b0, :) == 0);
    report(9, okCnt && okP, sprintf(['칸 수 합 = %d장면 × %d칸 (첫 칸은 이동 벡터가 없어 빼고, 끝 %d칸은 60분 뒤 진실이 없어 뺌), ' ...
        '20 mm/h 구간 호우 확률 1, 0 구간 0 → 인덱스 범위·표 계산 맞음'], nScene, nCell, max(Pc.lags)), ...
        sprintf('calibrate 칸 수 또는 확률 불일치 (okCnt=%d okP=%d)', okCnt, okP));
catch ME
    report(9, false, '', ['실행 오류로 확인 못 함: ' ME.message]);
end

%% CHECK 2 — 실제 2023 자료: 시간축 규약(첫 칸 = 6/1 00:00 UTC, 30분 간격, 5856칸)과 격자 방향
try
    D23 = L.loadSeason(2023, 'final');
    dt1 = seconds(D23.tSlot(1) - D23.t0);
    okT = D23.nT == 5856 && dt1 == 0 && all(diff(seconds(D23.tSlot - D23.t0)) == 1800);
    kk = [1 100 5856];  okK = all(floor(seconds(D23.tSlot(kk) - D23.t0)' / 1800) + 1 == kk);   % k번째 칸 ↔ floor(t/1800)+1
    dLat = D23.lat(2) - D23.lat(1);  dLon = D23.lon(2) - D23.lon(1);
    okG = dLat > 0 && dLon > 0 && abs(dLat - 0.1) < 1e-4 && abs(dLon - 0.1) < 1e-4;     % 오름차순 0.1° (estMotion의 '북 = 행 증가' 가정)
    okSz = isequal(size(D23.Pr), [numel(D23.lat) numel(D23.lon) D23.nT]) && ~any(isnan(D23.Pr(:))) && all(D23.Pr(:) >= 0);
    report(2, okT && okK && okG && okSz, sprintf(['2023 자료 %d×%d칸 × %d장면, 첫 칸 시작 = t0 + %d초, 30분 간격 끊김 없음, ' ...
        '칸 번호 = floor(t/1800)+1 규약 일치, 위도·경도 오름차순 0.1°, NaN·음수 없음'], ...
        numel(D23.lat), numel(D23.lon), D23.nT, dt1), ...
        sprintf('시간축/격자 규약 불일치 (okT=%d okK=%d okG=%d okSz=%d)', okT, okK, okG, okSz));
catch ME
    report(2, false, '', ['실행 오류로 확인 못 함: ' ME.message]);
    D23 = [];
end

%% CHECK 4 — 실제 2023 이동 벡터의 부호가 기후(장마 강수대는 동진)와 맞는가
try
    if isempty(D23), error('CHECK 2에서 자료를 못 읽었다'); end
    mv = D23.motion;  nz = any(mv ~= 0, 2);                    % 0 = 비가 적어 못 구한 장면
    mE = mean(mv(nz, 1)) * 1000;  mN = mean(mv(nz, 2)) * 1000;   % m/s
    spd = median(hypot(mv(nz, 1), mv(nz, 2))) * 1000;
    ok = mE > 0 && spd > 1 && spd < 30;
    report(4, ok, sprintf(['이동 벡터 구한 장면 %d개, 평균 [동 %.1f, 북 %.1f] m/s, 속도 중앙값 %.1f m/s → ' ...
        '동쪽 성분 양수(강수대 동진)·수 m/s~수십 m/s 범위로 부호·단위(km/s) 규약이 맞음'], nnz(nz), mE, mN, spd), ...
        sprintf('동쪽 성분 평균 %.1f m/s, 속도 중앙값 %.1f m/s → 부호 또는 단위를 다시 봐야 함', mE, spd));
catch ME
    report(4, false, '', ['실행 오류로 확인 못 함: ' ME.message]);
end

fprintf('총 %.0f초\n', toc(tAll));

%% ===================== 보조 함수 =====================
function report(n, ok, msgPass, msgFail)
if ok, fprintf('CHECK %d: %s - %s\n', n, 'PASS', msgPass);
else,  fprintf('CHECK %d: %s - %s\n', n, 'FAIL', msgFail); end
end

function G = fakePass(ts, dur, lat0, lon0, nT)
% 북쪽으로 똑바로 가는 가짜 통과 (경도 lon0 고정, 7.6 km/s). kre_lib의 passSetup/passGeometry가 만드는 필드와 같은 모양
tq = (ts:1.5:ts + dur)';
la = lat0 + 7.6 / 110.57 * (tq - ts);  lo = lon0 * ones(size(tq));
Pg.latm = mean(la);  Pg.lonm = lon0;  Pg.kx = 111.32 * cosd(Pg.latm);  Pg.ky = 110.57;
x = (lo - Pg.lonm) * Pg.kx;  y = (la - Pg.latm) * Pg.ky;
n = numel(tq);  idx = unique([1:5:n, n]);  m = numel(idx) - 1;
Pg.t1 = tq(idx(1:m));  Pg.t2 = tq(idx(2:m + 1));
p1 = [x(idx(1:m)), y(idx(1:m))];  p2 = [x(idx(2:m + 1)), y(idx(2:m + 1))];
Lseg = sqrt(sum((p2 - p1).^2, 2));
Pg.u = (p2 - p1) ./ Lseg;  Pg.nrm = [-Pg.u(:, 2), Pg.u(:, 1)];
Pg.V = Lseg ./ (Pg.t2 - Pg.t1);  Pg.p1 = p1;  Pg.ts = tq(1);  Pg.te = tq(end);
G.Pg = Pg;  G.ts = ts;  G.tq = tq;  G.xq = x;  G.yq = y;
G.nq = repmat([-1 0], n, 1);                                  % 진행 방향(북)의 왼쪽 = 서쪽 → 빔 오프셋 + 는 서쪽
G.kq = min(max(floor(tq / 1800) + 1, 1), nT);
end

function D = smallSeason(rs)
% 20×20칸, 30분 칸 12개의 작은 가짜 시즌 (calibrate 확인용)
lat = (30.05:0.1:31.95)';  lon = (125.05:0.1:126.95)';  nT = 12;
D = struct('Pr', single(30 * rand(rs, 20, 20, nT).^3), 'lat', lat, 'lon', lon, 'nT', nT, ...
    't0', datetime(2023, 6, 1, 'TimeZone', 'UTC'), 'year', 2023, 'src', 'final', ...
    'kmLat', 110.57 * 0.1, 'kmLon', 111.32 * 0.1 * cosd(mean(lat)), 'motion', zeros(nT, 2));
D.tSlot = D.t0 + seconds((0:nT - 1)' * 1800);
end

function ok = feasible(seq, m)
% seq(q) = 0(기동 중) 또는 빔각 번호. 각도가 바뀌면 그 사이 빈 표본이 m(이전, 다음) 개 이상이어야 한다
obs = find(seq > 0);  ok = true;
for a = 1:numel(obs) - 1
    q1 = obs(a);  q2 = obs(a + 1);
    if seq(q1) ~= seq(q2) && q2 - q1 - 1 < m(seq(q1), seq(q2)), ok = false; return; end
end
end

function best = bruteForce(Rw, m)
% 가능한 모든 경로 (nj+1)^nq 개를 다 세어 본 최고 점수 (보상이 0 이상이면 DP 최적값과 같아야 한다)
[nq, nj] = size(Rw);  best = -inf;  base = nj + 1;
pw = base.^(0:nq - 1);
for s = 0:base^nq - 1
    seq = mod(floor(s ./ pw), base);
    if feasible(seq, m)
        obs = find(seq > 0);
        best = max(best, sum(Rw(sub2ind([nq nj], obs, seq(obs)))));
    end
end
end
