%% 05_check.m — dp_step4_realistic.m 코드 검토(05번 문서 5절) 확인 스크립트
% 60초 안에 끝나고 그림을 만들지 않는다. 지적마다 한 줄 CHECK n: PASS/FAIL.
%   PASS = 코드가 의도대로 동작함(지적이 오해이거나 개선 제안 수준), FAIL = 지적이 맞음(진짜 버그).
% 쓰는 것: out/dp_step4_realistic/results.mat, methods.csv, out/run_log.csv,
%          캐시 cache_2023_JJAS.mat / cache_early_2023_JJAS.mat (loadSeason 2023만, 재계산 없음), 작은 가짜 자료
root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(fullfile(root, 'dp'));
L = kre_lib();
P = L.params();
Pe = P;  Pe.pDet = 1;  Pe.posSd = 0;  Pe.velSd = 0;
outDir = fullfile(root, 'out', 'dp_step4_realistic');
R = load(fullfile(outDir, 'results.mat'));
iMain = 4;  iFin = 6;  iOr = 7;  nDay = 122;
nY = numel(R.years);  nM = numel(R.methods);

%% CHECK 1: Early 큐가 큐 시각 뒤(미래) 장면을 보지 않는가 — 가짜 자료로 rewardGrid 직접 호출
try
    ok = true;  msg = '';
    nT = 12;
    lat = (31:0.1:35)';  lon = (123:0.1:127)';
    calib = struct('pHeavy', repmat((0:10)' / 10, 1, 2), 'pRain', repmat((0:10)' / 10, 1, 2));
    calib.pHeavy(1, :) = 0;  calib.pRain(1, :) = 0;            % 0 mm/h 구간은 보상 0
    tsList = 900 + [0 1 899 900 901 1799 1800 1801] + 1800 * 5;  % 칸 경계 앞뒤를 두루 시험
    for ts = tsList
        tCue = ts - Pe.cueL * 60;
        kLeak = floor(tCue / 1800) + 1;                           % 큐 시각을 '포함'하는 칸 (아직 안 끝남)
        D = fakeD(lat, lon, nT);
        D.cuePr(:, :, kLeak:end) = 20;                            % 큐 시각 이후 칸에만 호우
        G = fakeG(ts, nT);
        [Rw, ~, info] = L.rewardGrid(G, D, Pe, 'nowcast', RandStream('mt19937ar', 'Seed', 1), calib);
        kc = info.kc;
        if ~(kc * 1800 <= tCue && (kc + 1) * 1800 > tCue), ok = false; msg = sprintf('kc=%d가 큐 시각 전 마지막 칸이 아님(ts=%g)', kc, ts); break; end
        if min(G.kq) - kc < 1, ok = false; msg = 'kq-kc<1 (lag 0)'; break; end
        if any(Rw(:) ~= 0), ok = false; msg = sprintf('미래 칸의 호우가 보상에 새어 들어옴(ts=%g)', ts); break; end
        D.cuePr(:, :, kc) = 20;                                   % 검사 유효성: kc 칸에 비를 넣으면 보상이 생겨야 함
        [Rw2, ~, ~] = L.rewardGrid(G, D, Pe, 'nowcast', RandStream('mt19937ar', 'Seed', 1), calib);
        if ~any(Rw2(:) > 0), ok = false; msg = '큐 칸의 호우가 보상에 반영되지 않음(검사 무효)'; break; end
    end
    if ok, msg = sprintf('큐 칸 = 큐 시각 전에 끝난 마지막 30분 칸, 그 뒤 칸의 호우는 보상 0 (ts %d가지)', numel(tsList)); end
    fprintf('CHECK %d: %s - %s\n', 1, pf(ok), msg);
catch ME
    fprintf('CHECK %d: %s - %s\n', 1, 'FAIL', ['확인 중 오류: ' ME.message]);
end

%% CHECK 2: attachCue의 정렬 assert — 실제 2023 캐시는 통과, 어긋난 가짜 자료는 멈추는가
try
    Df = L.loadSeason(2023, 'final');
    De = L.loadSeason(2023, 'early');
    DfE = L.attachCue(Df, De);                                   % 4개 assert가 모두 통과해야 함
    okReal = isequal(size(DfE.cuePr), size(Df.Pr)) && strcmp(DfE.cueSrc, 'early') && Df.nT == nDay * 48;
    t = datetime(2023, 6, 1, 'TimeZone', 'UTC') + minutes(30) * (0:2)';
    A = struct('Pr', zeros(2, 2, 3, 'single'), 'lat', [1; 2], 'lon', [1; 2], 'tSlot', t, 'src', 'final', 'motion', zeros(3, 2));
    B = A;  B.src = 'early';
    B1 = B;  B1.tSlot = B1.tSlot + minutes(30);                   % 시각 어긋남
    B2 = B;  B2.src = 'final';                                    % 같은 출처
    B3 = B;  B3.Pr = zeros(2, 2, 4, 'single');                    % 칸 수 다름
    stopped = [caught(@() L.attachCue(A, B1)), caught(@() L.attachCue(A, B2)), caught(@() L.attachCue(A, B3))];
    passed = ~caught(@() L.attachCue(A, B));
    ok = okReal && all(stopped) && passed;
    fprintf('CHECK %d: %s - %s\n', 2, pf(ok), sprintf('2023 Final·Early 캐시 정렬 통과(nT=%d), 시각/출처/칸수 어긋난 가짜 자료는 assert로 멈춤 [%d/3]; 줄 64 중복 호출은 결과 영향 없음', Df.nT, nnz(stopped)));
catch ME
    fprintf('CHECK %d: %s - %s\n', 2, 'FAIL', ['확인 중 오류: ' ME.message]);
    Df = [];  De = [];
end

%% CHECK 3: 2023 Early(재처리본)가 2024·2025(실시간본)보다 Final을 더 잘 맞히는가 (코드 주석의 경고가 사실인지)
try
    cd23 = R.agree(1).coreDet;  cd24 = R.agree(2).coreDet;  cd25 = R.agree(3).coreDet;
    ok = cd23 > cd24 && cd23 > cd25;
    fprintf('CHECK %d: %s - %s\n', 3, pf(ok), sprintf('호우 핵 인식 2023 %.3f > 2024 %.3f, 2025 %.3f → 재처리본 경고가 사실(코드는 문구로만 처리, 개선 제안: 2024 학습→2025 검증 교차 확인)', cd23, cd24, cd25));
catch ME
    fprintf('CHECK %d: %s - %s\n', 3, 'FAIL', ['확인 중 오류: ' ME.message]);
end

%% CHECK 4: 부트스트랩(날짜·5일 묶음) 재계산이 저장값과 같고, 묶음 인덱스가 1~122 안에서 5일씩 이어지는가
try
    dayH = R.dayH;
    rsB = RandStream('mt19937ar', 'Seed', 7);
    ci2 = zeros(nY, nM, 2);  ciRatio2 = zeros(nY, 2);
    for iy = 1:nY
        X = squeeze(dayH(iy, :, :));
        bs = zeros(2000, nM);  br = zeros(2000, 1);
        for b = 1:2000
            pick = randi(rsB, nDay, nDay, 1);
            s = sum(X(pick, :), 1);
            bs(b, :) = s / s(1);  br(b) = s(iMain) / s(iFin);
        end
        ci2(iy, :, :) = reshape(prctile(bs, [2.5 97.5])', [1 nM 2]);
        ciRatio2(iy, :) = prctile(br, [2.5 97.5]);
    end
    blk = 5;  ciBlk2 = zeros(nY, 2);  ciRatioBlk2 = zeros(nY, 2);  idxOk = true;
    for iy = 1:nY
        rsBB = RandStream('mt19937ar', 'Seed', 100 + R.years(iy));
        X = squeeze(dayH(iy, :, :));
        bg = zeros(2000, 1);  br = zeros(2000, 1);
        for b = 1:2000
            st = randi(rsBB, nDay - blk + 1, ceil(nDay / blk), 1);
            pick = reshape((st + (0:blk - 1))', [], 1);
            pick = pick(1:nDay);
            if any(pick < 1 | pick > nDay), idxOk = false; end
            blkMat = reshape(pick(1:blk * floor(nDay / blk)), blk, []);   % 온전한 묶음 24개 (열 = 묶음)
            if any(diff(blkMat, 1, 1) ~= 1, 'all'), idxOk = false; end      % 묶음 안 5일이 연속인가
            if any(blkMat(1, :) < 1 | blkMat(1, :) > nDay - blk + 1), idxOk = false; end
            s = sum(X(pick, :), 1);
            bg(b) = s(iMain) / s(1);  br(b) = s(iMain) / s(iFin);
        end
        ciBlk2(iy, :) = prctile(bg, [2.5 97.5]);
        ciRatioBlk2(iy, :) = prctile(br, [2.5 97.5]);
    end
    d = max([max(abs(ci2(:) - R.ci(:))), max(abs(ciRatio2(:) - R.ciRatio(:))), ...
             max(abs(ciBlk2(:) - R.ciBlk(:))), max(abs(ciRatioBlk2(:) - R.ciRatioBlk(:)))]);
    ok = idxOk && d < 1e-9;
    fprintf('CHECK %d: %s - %s\n', 4, pf(ok), sprintf('묶음 인덱스 1~%d·5일 연속 %s, 재계산 CI와 저장값 최대 차 %.1e (DP Early 2024 묶음 CI %.3f~%.3f)', nDay, yn(idxOk), d, ciBlk2(2, :)));
catch ME
    fprintf('CHECK %d: %s - %s\n', 4, 'FAIL', ['확인 중 오류: ' ME.message]);
end

%% CHECK 5: 방식 인덱스(iMain·iFin·iOr)와 이름, results.mat의 gain, methods.csv 행 순서·열 일치
try
    nameOk = contains(R.methods(iMain), 'Early') && contains(R.methods(iMain), '나우캐스트') && ~contains(R.methods(iMain), '가짜') ...
          && contains(R.methods(iFin), 'Final') && contains(R.methods(iOr), '상한');
    mTot2 = squeeze(mean(R.tot, 2));
    gain2 = mTot2 ./ mTot2(:, 1, :);
    gainOk = max(abs(gain2(:) - R.gain(:))) < 1e-9;
    csv = fullfile(outDir, 'methods.csv');
    try, T = readtable(csv, 'Encoding', 'UTF-8');  catch, T = readtable(csv);  end
    csvGain = reshape(T.gainHeavy, nM, nY)';                      % 행 순서: 연도 바깥, 방식 안쪽
    csvOk = height(T) == nY * nM && max(abs(csvGain - squeeze(R.gain(:, :, 1))), [], 'all') < 1e-9 ...
         && max(abs(T.heavy0to3deg + T.heavy3to6deg + T.heavy6to10deg - T.heavyProf)) < 1e-9 ...
         && max(abs(T.heavyWithin3deg - T.heavy0to3deg)) < 1e-9;
    ok = nameOk && gainOk && csvOk;
    fprintf('CHECK %d: %s - %s\n', 5, pf(ok), sprintf('methods(4/6/7)=Early 나우캐스트/Final/상한 %s, tot→gain 재계산 %s, csv 21행 gainHeavy·각도대 합=heavyProf %s (2024 대표 %.3f, Final %.3f, 상한 %.3f); 줄 280의 숫자 5는 개선 제안', ...
        yn(nameOk), yn(gainOk), yn(csvOk), R.gain(2, iMain, 1), R.gain(2, iFin, 1), R.gain(2, iOr, 1)));
catch ME
    fprintf('CHECK %d: %s - %s\n', 5, 'FAIL', ['확인 중 오류: ' ME.message]);
end

%% CHECK 6: Pe(pDet=1, posSd=0, velSd=0)가 가짜 오차를 정말 끄는가 — 씨앗을 바꿔도 보상 표가 같은지
try
    peOk = R.Pe.pDet == 1 && R.Pe.posSd == 0 && R.Pe.velSd == 0 && R.P.pDet == 0.72;
    nT = 12;  lat = (31:0.1:35)';  lon = (123:0.1:127)';
    calib = struct('pHeavy', repmat((0:10)' / 10, 1, 2), 'pRain', repmat((0:10)' / 10, 1, 2));
    ts = 1800 * 6 + 1000;
    G = fakeG(ts, nT);
    tCue = ts - P.cueL * 60;  kc = floor(tCue / 1800);
    D = fakeD(lat, lon, nT);
    D.cuePr(16:26, 16:26, kc) = 25;                               % 가운데 호우 덩어리 하나 (국지 최대 포함)
    D.cuePr(19:23, 19:23, kc) = 40;
    D.cuePr(:, :, kc) = D.cuePr(:, :, kc) + 2;                     % 주변 약한 비
    nSeed = 20;  RwE = cell(1, nSeed);  RwP = cell(1, nSeed);
    for s = 1:nSeed
        RwE{s} = L.rewardGrid(G, D, Pe, 'nowcast', RandStream('mt19937ar', 'Seed', s), calib);
        RwP{s} = L.rewardGrid(G, D, P,  'nowcast', RandStream('mt19937ar', 'Seed', s), calib);
    end
    sameE = all(cellfun(@(x) isequal(x, RwE{1}), RwE));
    diffP = ~all(cellfun(@(x) isequal(x, RwP{1}), RwP));
    ok = peOk && sameE && diffP;
    fprintf('CHECK %d: %s - %s\n', 6, pf(ok), sprintf('results.mat의 Pe 값 %s, Pe는 씨앗 %d개 모두 같은 보상 표 %s, P는 씨앗에 따라 달라짐 %s', yn(peOk), nSeed, yn(sameE), yn(diffP)));
catch ME
    fprintf('CHECK %d: %s - %s\n', 6, 'FAIL', ['확인 중 오류: ' ME.message]);
end

%% CHECK 7: NaN·음수 강수 처리 — 캐시에 NaN·음수가 없고, 자료 밖을 겨냥하면 NaN(세지 않음)
try
    if isempty(Df), Df = L.loadSeason(2023, 'final'); end
    if isempty(De), De = L.loadSeason(2023, 'early'); end
    nanF = nnz(isnan(Df.Pr));  nanE = nnz(isnan(De.Pr));
    minF = min(Df.Pr, [], 'all');  minE = min(De.Pr, [], 'all');
    outside = L.sampleField(Df.Pr, Df.lat, Df.lon, 50, 200, 1);   % 자료 영역 밖 위경도
    inside = L.sampleField(Df.Pr, Df.lat, Df.lon, Df.lat(5), Df.lon(5), 1);
    ok = nanF == 0 && nanE == 0 && minF >= 0 && minE >= 0 && isnan(outside) && ~isnan(inside);
    fprintf('CHECK %d: %s - %s\n', 7, pf(ok), sprintf('2023 캐시 NaN %d/%d개, 최소값 %.3g/%.3g (Final/Early), 영역 밖 표본 NaN %s → 보상 0·채점 제외', nanF, nanE, minF, minE, yn(isnan(outside))));
catch ME
    fprintf('CHECK %d: %s - %s\n', 7, 'FAIL', ['확인 중 오류: ' ME.message]);
end
clear Df De DfE

%% CHECK 8: run_log.csv의 마지막 dp_step4_realistic 줄이 results.mat의 배수·CI와 같은가
try
    f = fullfile(root, 'out', 'run_log.csv');
    fid = fopen(f, 'r', 'n', 'UTF-8');  txt = fread(fid, '*char')';  fclose(fid);
    lines = regexp(txt, '\r?\n', 'split');
    hit = lines(contains(lines, ',dp_step4_realistic,'));
    if isempty(hit), error('run_log.csv에 dp_step4_realistic 줄이 없다'); end
    last = hit{end};
    tok = regexp(last, '(\d+\.\d+)배\((\d{4}), CI (\d+\.\d+)~(\d+\.\d+)\)', 'tokens');
    ok = numel(tok) == nY && startsWith(last, '20') && contains(last, '"');
    for iy = 1:nY
        want = [sprintf('%.2f', R.gain(iy, iMain, 1)), sprintf('%d', R.years(iy)), sprintf('%.2f', R.ci(iy, iMain, 1)), sprintf('%.2f', R.ci(iy, iMain, 2))];
        got  = [tok{iy}{1}, tok{iy}{2}, tok{iy}{3}, tok{iy}{4}];
        ok = ok && strcmp(want, got);
    end
    fprintf('CHECK %d: %s - %s\n', 8, pf(ok), sprintf('마지막 줄의 %s배/CI가 results.mat gain(:,4,1)·ci와 일치, 메모는 큰따옴표로 감쌈', strjoin(cellfun(@(c) c{1}, tok, 'UniformOutput', false), '/')));
catch ME
    fprintf('CHECK %d: %s - %s\n', 8, 'FAIL', ['확인 중 오류: ' ME.message]);
end

%% ---------- 보조 함수 ----------
function s = pf(ok)
if ok, s = 'PASS'; else, s = 'FAIL'; end
end

function s = yn(ok)
if ok, s = '예'; else, s = '아니오'; end
end

function c = caught(fn)
% fn을 실행해 오류가 나면 true (assert가 멈추는지 보기)
try, fn();  c = false;  catch, c = true;  end
end

function D = fakeD(lat, lon, nT)
% rewardGrid가 쓰는 필드만 가진 작은 가짜 자료 (큐 = cuePr, 진실 = Pr, 이동 없음)
D.Pr = zeros(numel(lat), numel(lon), nT, 'single');
D.cuePr = zeros(numel(lat), numel(lon), nT, 'single');
D.lat = lat;  D.lon = lon;  D.nT = nT;
D.motion = zeros(nT, 2);  D.cueMotion = zeros(nT, 2);
D.src = 'final';  D.cueSrc = 'early';  D.year = 2023;
D.t0 = datetime(2023, 6, 1, 'TimeZone', 'UTC');
end

function G = fakeG(ts, nT)
% 통과 하나의 가짜 기하: 북위 33°·동경 125° 중심, 남→북으로 40개 표본(1.5 s 간격), 빔은 동서 방향
n = 40;
G.ts = ts;
G.tq = ts + (0:n - 1)' * 1.5;
G.xq = zeros(n, 1);
G.yq = linspace(-20, 20, n)';
G.nq = repmat([1 0], n, 1);
G.kq = min(max(floor(G.tq / 1800) + 1, 1), nT);
G.Pg = struct('latm', 33, 'lonm', 125, 'kx', 111.32 * cosd(33), 'ky', 110.57);
end
