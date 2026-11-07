%% 03_check.m — 03번 해설(dp_step2_demo.m) 5절 지적 확인 스크립트
% 그림 없음, 60초 안에 끝남. 실제 IMERG 자료는 캐시 파일의 lat/lon 크기만 읽는다(Pr는 읽지 않음).
% 출력 한 줄 = 지적 하나:  CHECK n: PASS/FAIL - 설명
%   PASS = 코드가 의도대로 동작함(지적이 오해이거나 영향 없음), FAIL = 지적이 맞음(개선 제안도 포함)
root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(fullfile(root, 'dp'));
L = kre_lib();
P = L.params();
th = -P.maxDeg:P.stepDeg:P.maxDeg;
nj = numel(th);

%% CHECK 1: dpPlan 경로가 기동 한계(1.5°/s + 정착 4 s, ±10°, 1° 격자)를 지키는가 — 가짜 보상 표 3종
ok = true;  why = '';
rs = RandStream('mt19937ar', 'Seed', 3);
nq = 127;                                                   % 시연 통과와 같은 표본 수
for trial = 1:3
    switch trial
        case 1                                              % 무작위 표
            Rw = rand(rs, nq, nj);
        case 2                                              % +10°에서 -10°로 '즉시 점프'하고 싶게 만든 표
            Rw = zeros(nq, nj);  Rw(1:10, th == 10) = 1;  Rw(12:nq, th == -10) = 1;
        case 3                                              % 한 줄에 약한 보상, 가운데 짧은 구간에만 큰 보상
            Rw = zeros(nq, nj);  Rw(:, th == 7) = 0.3;  Rw(40:60, th == -3) = 1;
    end
    pl = L.dpPlan(Rw, th, P);
    v = find(pl.valid);  v = v(:);
    if any(abs(pl.th(v)) > P.maxDeg + 1e-9) || any(abs(pl.th(v) / P.stepDeg - round(pl.th(v) / P.stepDeg)) > 1e-9)
        ok = false;  why = sprintf('trial %d: 각도 범위/격자 위반', trial);
    end
    for k = 2:numel(v)
        q1 = v(k - 1);  q2 = v(k);
        d = abs(pl.th(q2) - pl.th(q1));  gap = q2 - q1 - 1;  % gap = 관측 못 한 표본 수
        if d == 0 && gap ~= 0
            ok = false;  why = sprintf('trial %d: 같은 각도인데 빈틈 %d', trial, gap);
        elseif d > 0
            need = ceil((d / P.slewRate + P.settle) / P.profDt);
            if gap < need
                ok = false;  why = sprintf('trial %d: q%d→q%d %g° 이동, 빈틈 %d < 필요 %d', trial, q1, q2, d, gap, need);
            end
        end
    end
    jv = arrayfun(@(q) find(abs(th - pl.th(q)) < 1e-9, 1), v);
    s = sum(Rw(sub2ind(size(Rw), v, jv)));
    if abs(s - pl.score) > 1e-3, ok = false;  why = sprintf('trial %d: score %.4f ≠ 경로 합 %.4f', trial, pl.score, s); end
    if trial == 2 && gapBetween(pl, 10, -10) >= 0 && gapBetween(pl, 10, -10) < 12   % -1이면 그 이동 자체가 없었다는 뜻(위반 아님)
        ok = false;  why = sprintf('trial 2: +10→-10 이동의 빈틈 %d < 12표본(18 s)', gapBetween(pl, 10, -10));
    end
end
if ok, fprintf('CHECK 1: PASS - dpPlan 경로가 ±10°·1° 격자 안에 있고, 각도 바꿀 때마다 ceil((Δθ/1.5+4)/1.5) 표본을 비우며, score = 경로 보상 합\n');
else,  fprintf('CHECK 1: FAIL - %s\n', why); end

%% CHECK 2: 보상 표 축 순서(행=표본 시각, 열=빔각)와 + 각도 = 진행 방향 왼쪽 — 가짜 통과·가짜 강수장
D = struct();
D.lat = (30:0.1:34)';  D.lon = (123:0.1:127)';
D.Pr = zeros(numel(D.lat), numel(D.lon), 2, 'single');
D.Pr(:, abs(D.lon - 124.5) < 1e-6, :) = 20;                 % 동경 124.5° 세로줄 전체가 호우 20 mm/h
D.nT = 2;  D.motion = zeros(2, 2);
G = struct();
G.Pg = struct('latm', 32, 'lonm', 125, 'kx', 111.32 * cosd(32), 'ky', 110.57);
G.tq = (0:P.profDt:60)';  nqs = numel(G.tq);
G.xq = zeros(nqs, 1);  G.yq = linspace(-100, 100, nqs)';    % 동경 125°를 따라 북쪽으로 진행
G.nq = repmat([-1 0], nqs, 1);                              % 북진의 왼쪽 = 서쪽 (빔각 + 방향)
G.kq = ones(nqs, 1);  G.ts = 0;
[Rw, th2] = L.rewardGrid(G, D, P, 'oracle', []);
% 124.5°는 궤적(125°)에서 서쪽 0.5° = 47.2 km → 빔각 atand(47.2/550) = 4.9° → 격자 +5° 열만 호우여야 한다
col5 = Rw(:, th2 == 5);  colm5 = Rw(:, th2 == -5);
ok = isequal(size(Rw), [nqs nj]) && all(abs(col5 - (1 + P.alpha)) < 1e-9) && all(colm5 == 0) ...
     && nnz(Rw) == nqs && isequal(size(Rw'), [nj nqs]);
if ok, fprintf('CHECK 2: PASS - Rw 크기 [표본 %d × 빔각 %d], 서쪽 호우가 +5° 열에만 1.05로 들어감 → imagesc(tt, th, Rw'')의 가로=시간·세로=빔각 맞음\n', nqs, nj);
else,  fprintf('CHECK 2: FAIL - size(Rw)=[%d %d], +5°열 최소 %.3f, -5°열 최대 %.3f\n', size(Rw, 1), size(Rw, 2), min(col5), max(colm5)); end

%% CHECK 3: 지도의 imagesc(D.lon, D.lat, D.Pr) — Pr가 (위도 × 경도) 순서인가 (캐시 파일의 크기만 읽음)
cache = fullfile(getenv('USERPROFILE'), 'Desktop', 'K-RainEye_IMERG', 'cache_2023_JJAS.mat');
if exist(cache, 'file')
    m = matfile(cache);
    sz = size(m, 'Pr');  lat = m.lat;  lon = m.lon;
    ok = sz(1) == numel(lat) && sz(2) == numel(lon) ...
         && all(diff(lat) > 0) && all(diff(lon) > 0) && abs(lat(2) - lat(1) - 0.1) < 1e-3 && abs(lon(2) - lon(1) - 0.1) < 1e-3;
    note = '';  if numel(lat) == numel(lon), note = ' (위경도 개수가 같아 순서 자체는 구분 못 함)'; end
    if ok, fprintf('CHECK 3: PASS - Pr 크기 [%d %d %d] = [위도 %d × 경도 %d × 시각], 위경도 모두 0.1° 오름차순 → imagesc(lon, lat, Pr)·axis xy 맞음%s\n', sz(1), sz(2), sz(3), numel(lat), numel(lon), note);
    else,  fprintf('CHECK 3: FAIL - Pr 크기 [%d %d %d], lat %d개(%s, 오름차순 %d, 첫 간격 %.4f), lon %d개(오름차순 %d, 첫 간격 %.4f)\n', sz(1), sz(2), sz(3), numel(lat), class(lat), all(diff(lat) > 0), lat(2) - lat(1), numel(lon), all(diff(lon) > 0), lon(2) - lon(1)); end
else
    fprintf('CHECK 3: FAIL - 캐시 파일이 없어 확인 못 함: %s\n', cache);
end

%% CHECK 4: 그림 1 색막대 라벨 '예측 보상 (호우 확률)' — 실제 값은 P(호우) + 0.05·P(강수)라 확률보다 조금 크다 (개선 제안)
calibFile = fullfile(root, 'out', 'dp_step1_train', 'calib_2023.mat');
if exist(calibFile, 'file')
    S = load(calibFile, 'calibN');  c = S.calibN;
    extra = max(c.pHeavy(:) + P.alpha * c.pRain(:)) - max(c.pHeavy(:));
    orMax = max(Rw(:));                                     % CHECK 2의 정답(oracle) 표 최대
    labelIsProb = extra < 1e-9 && orMax <= 1;
    if labelIsProb, fprintf('CHECK 4: PASS - 보상 최대값이 호우 확률 최대값과 같아 라벨이 정확함\n');
    else, fprintf('CHECK 4: FAIL - 예측 보상 최대 %.3f(호우 확률 최대 %.3f + 강수항 %.3f), 정답 표 최대 %.2f > 1 → 라벨은 근사 (개선 제안)\n', ...
            max(c.pHeavy(:)) + extra, max(c.pHeavy(:)), extra, orMax); end
else
    fprintf('CHECK 4: FAIL - calib_2023.mat이 없어 확인 못 함 (정답 표 최대 %.2f > 1인 것은 확인)\n', max(Rw(:)));
end

%% CHECK 5: 그림 2의 DP 빔 위치 점이 흰색('w.')인데 그림 바탕도 흰색('Color','w') → 비 없는 곳의 점이 안 보임 (개선 제안)
src = fullfile(root, 'dp', 'dp_step2_demo.m');
fid = fopen(src, 'r', 'n', 'UTF-8');  txt = fread(fid, '*char')';  fclose(fid);
whiteBg  = ~isempty(regexp(txt, 'f2 = figure\([^\n]*''Color'',\s*''w''', 'once'));
whiteDot = ~isempty(regexp(txt, 'E\(3\)\.blon\(v\),\s*E\(3\)\.blat\(v\),\s*''w\.''', 'once'));
if whiteBg && whiteDot, fprintf('CHECK 5: FAIL - 지도 바탕색과 DP 빔 점 색이 둘 다 흰색 → 강수 0.1 mm/h 이하(투명) 위의 점과 범례 기호가 안 보임 (개선 제안)\n');
else, fprintf('CHECK 5: PASS - 바탕(흰색 %d)과 점(흰색 %d) 색이 다름\n', whiteBg, whiteDot); end

%% CHECK 6: 큐 장면의 무작위 오차가 고정 시드라 rewardGrid(줄 36~37)와 greedyPlan(줄 45)이 같은 큐 장면을 보는가
%   (cueScene은 kre_lib 밖으로 안 나오므로, 그것을 부르는 rewardGrid 'nowcast'를 같은 시드로 두 번 불러 비교)
if exist(calibFile, 'file')
    Gc = G;  Gc.ts = 5400;                                  % 큐 시각 4500 s → 큐 장면 = 2번째 30분 칸 (kc = 2)
    [R1, ~, i1] = L.rewardGrid(Gc, D, P, 'nowcast', RandStream('mt19937ar', 'Seed', 1), c);
    [R2, ~, i2] = L.rewardGrid(Gc, D, P, 'nowcast', RandStream('mt19937ar', 'Seed', 1), c);
    [~,  ~, i3] = L.rewardGrid(Gc, D, P, 'nowcast', RandStream('mt19937ar', 'Seed', 2), c);
    same  = isequal(R1, R2) && isequal(i1.e, i2.e) && isequal(i1.v, i2.v) && isequal(i1.cueVal, i2.cueVal);
    diff2 = ~(isequal(i1.e, i3.e) && isequal(i1.v, i3.v));  % 시드가 다르면 달라야 정상
    if same && diff2, fprintf('CHECK 6: PASS - Seed 1 두 스트림의 큐 장면(위치오차 e, 속도 v, 큐 강도)과 보상 표가 완전히 같고 Seed 2와는 다름 → 재현 가능·공정 비교\n');
    else, fprintf('CHECK 6: FAIL - 같은 시드 동일 %d, 다른 시드 상이 %d\n', same, diff2); end
else
    fprintf('CHECK 6: FAIL - calib_2023.mat이 없어 확인 못 함\n');
end

%% CHECK 7: 그림 2 배경은 통과 가운데 표본의 30분 장면 하나(kMid) — 이번 통과(summary.txt)가 30분 칸 하나에 드는가
sumFile = fullfile(root, 'out', 'dp_step2_demo', 'summary.txt');
if exist(sumFile, 'file')
    fid = fopen(sumFile, 'r', 'n', 'UTF-8');  st = fread(fid, '*char')';  fclose(fid);
    tok = regexp(st, '(\d{4}-\d{2}-\d{2} \d{2}:\d{2}) KST', 'tokens', 'once');
    nad = regexp(st, '천저 고정\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)', 'tokens', 'once');
    tKST = datetime(tok{1}, 'InputFormat', 'yyyy-MM-dd HH:mm', 'TimeZone', 'Asia/Seoul');
    t0 = datetime(2023, 6, 1, 'TimeZone', 'UTC');
    s0 = seconds(tKST - t0);                                % 통과 시작(분 단위로 잘림)
    nSamp = str2double(nad{4});  lenS = (nSamp - 1) * P.profDt;
    k1 = floor(s0 / 1800) + 1;  k2 = floor((s0 + 59 + lenS) / 1800) + 1;   % 초 단위는 최악(59 s)으로
    if k1 == k2, fprintf('CHECK 7: PASS - %s KST 시작, 표본 %d개 = %.0f s 통과가 30분 칸 %d 하나에 들어 배경 장면 = 채점 장면\n', tok{1}, nSamp, lenS, k1);
    else, fprintf('CHECK 7: FAIL - 통과가 30분 칸 %d와 %d에 걸쳐 배경 장면과 채점 장면이 다를 수 있음\n', k1, k2); end
else
    fprintf('CHECK 7: FAIL - summary.txt가 없어 확인 못 함\n');
end

%% CHECK 8: summary.txt의 매개변수 줄이 지금의 kre_lib params와 같은가 (하드코딩 어긋남 확인)
if exist(sumFile, 'file')
    ln = regexp(st, '매개변수:[^\n]*', 'match', 'once');
    num = str2double(regexp(ln, '[-+]?\d*\.?\d+', 'match'));
    want = [P.maxDeg, P.stepDeg, P.slewRate, P.settle, P.cueL, P.alpha, P.blur];
    if numel(num) == numel(want) && all(abs(num - want) < 1e-9)
        fprintf('CHECK 8: PASS - summary 매개변수(±%g°, %g°, %g°/s, %g s, %g분, alpha %g, blur %g) = L.params()\n', want);
    else
        fprintf('CHECK 8: FAIL - summary 숫자 [%s] ≠ params [%s]\n', num2str(num), num2str(want));
    end
else
    fprintf('CHECK 8: FAIL - summary.txt가 없어 확인 못 함\n');
end

%% 보조 함수
function g = gapBetween(pl, a, b)
% 각도 a에서 b로 처음 옮길 때 비운 표본 수 (없으면 -1)
g = -1;
v = find(pl.valid);
for k = 2:numel(v)
    if pl.th(v(k - 1)) == a && pl.th(v(k)) == b, g = v(k) - v(k - 1) - 1;  return; end
end
end
