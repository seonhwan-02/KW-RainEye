%% 04_check.m — dp_step3_validate.m 코드 검토(04번 문서 5절) 확인용 스크립트
% - 60초 안에 끝나고 그림을 그리지 않는다. 전체 시즌 재계산은 하지 않는다.
% - 저장된 out/dp_step3_validate/results.mat, methods.csv, passes.csv 와
%   out/dp_step1_train/calib_2023.mat 를 읽어 비교하거나, 작은 가짜 입력으로 kre_lib 함수를 직접 부른다.
% - 한 줄 출력: CHECK n: PASS|FAIL - 설명
%   PASS = 코드가 의도대로 동작함,  FAIL = 지적이 맞음 (문서 5절의 판정과 함께 읽을 것)
% (러너에서 실행: clear 생략)
root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(fullfile(root, 'dp'));
L = kre_lib();  P = L.params();
outDir = fullfile(root, 'out', 'dp_step3_validate');
R  = load(fullfile(outDir, 'results.mat'), 'years', 'methods', 'tot', 'dayH', 'ci', 'gain', 'mTot', 'P', 'nPass');
MT = readtable(fullfile(outDir, 'methods.csv'), 'TextType', 'string', 'Encoding', 'UTF-8');
PT = readtable(fullfile(outDir, 'passes.csv'),  'TextType', 'string', 'Encoding', 'UTF-8');
nY = numel(R.years);  nM = numel(R.methods);  nDay = size(R.dayH, 2);  nK = size(R.tot, 4);
[D, mkG] = fakeScene(P);                         % 가짜 강수장과 통과(아래 보조 함수)
nb = numel(P.edges) - 1;
calibF = struct('pHeavy', repmat(linspace(0, 1, nb)', 1, numel(P.lags)), ...
                'pRain',  repmat(linspace(0, 1, nb)', 1, numel(P.lags)));

%% CHECK 1: 학습 연도와 검증 연도 분리 (줄 26~29, 54~57)
try
    S = load(fullfile(root, 'out', 'dp_step1_train', 'calib_2023.mat'));
    ok = S.calibN.year == 2023 && S.calibP.year == 2023 ...
        && strcmp(S.calibN.mode, 'nowcast') && strcmp(S.calibP.mode, 'persist') ...
        && isequal(S.P.edges, P.edges) && isequal(S.P.lags, P.lags) ...
        && S.P.pDet == P.pDet && isequal(S.P.weakFac, P.weakFac) ...
        && isequal(R.years, [2023 2024]) ...
        && numel(dir(fullfile(root, 'out', 'dp_step1_train', 'calib_*.mat'))) == 1;
    report(1, ok, '학습 표(calibN/calibP)는 2023 자료만으로, 3단계와 같은 매개변수(edges, lags, pDet)로 만들어졌고 2024는 검증에만 쓰임');
catch err
    report(1, false, ['실행 오류: ' err.message]);
end

%% CHECK 2: 큐가 관측 시각 뒤 장면을 보지 않는가 (kre_lib cueSlot/rewardGrid, 줄 54~57에서 호출)
try
    ok = true;  nTest = 0;
    for ts = [2800, 1800*2 + 905, 1800*2 + 1790, 1800*3 + 10, 1800*3 + 899, 1800*3 + 901, 1800*5 + 1500, 1800*7 + 450]
        G = mkG(ts);
        [Rw, ~, info] = L.rewardGrid(G, D, P, 'persist', RandStream('mt19937ar', 'Seed', 1), calibF);
        tCue = ts - P.cueL * 60;                         % 큐 시각 = 통과 시작 15분 전
        if isnan(info.kc)
            ok = ok && all(Rw(:) == 0) && tCue < 2 * 1800;          % 쓸 큐 장면이 없으면 보상 0(천저 유지)
        else
            ok = ok && info.kc * 1800 <= tCue ...                    % 큐 장면은 큐 시각 전에 '끝난' 칸
                    && (info.kc + 1) * 1800 > tCue ...               % 그중 가장 최근 칸
                    && min(G.kq) - info.kc >= 1 ...                  % 진실(채점) 칸은 항상 큐 칸보다 뒤
                    && max(G.kq) - info.kc <= numel(P.lags);         % 학습 표의 lag 범위(1~2칸) 안
        end
        nTest = nTest + 1;
    end
    report(2, ok, sprintf('통과 시작 시각 %d가지에서 큐 칸 끝 <= 큐 시각 < 진실 칸, lag 1~2칸 유지 (미래 누수 없음)', nTest));
catch err
    report(2, false, ['실행 오류: ' err.message]);
end

%% CHECK 3: 부트스트랩이 '일' 단위로 묶이고 시드 7로 재현되는가 (줄 61, 89~101)
try
    rsB = RandStream('mt19937ar', 'Seed', 7);
    ci2 = zeros(nY, nM, 2);
    for iy = 1:nY
        X = squeeze(R.dayH(iy, :, :));                   % nDay × nM
        bs = zeros(2000, nM);
        for b = 1:2000
            pick = randi(rsB, nDay, nDay, 1);
            s = sum(X(pick, :), 1);
            bs(b, :) = s / s(1);
        end
        ci2(iy, :, :) = reshape(prctile(bs, [2.5 97.5])', [1 nM 2]);
    end
    dCi = max(abs(ci2 - R.ci), [], 'all');
    dDay = max(abs(squeeze(sum(R.dayH, 2)) - squeeze(sum(R.tot(:, :, :, 1), 2))), [], 'all');
    ok = dCi < 1e-9 && dDay < 1e-9 && nDay == 122;
    report(3, ok, sprintf('날짜별 합(dayH) = 시즌 합(차 %.1e), 122일 복원추출 2000회를 시드 7로 다시 돌리면 저장된 CI와 일치(차 %.1e)', dDay, dCi));
catch err
    report(3, false, ['실행 오류: ' err.message]);
end

%% CHECK 4: 연도별 시드가 아니고 nY = 2·years = [2023 2024]가 박혀 있다 (줄 90~101, 80~83, 106, 131, 196~199)
try
    % (가) 시드 7 하나를 두 해가 이어 쓰므로, 2024만 따로 돌리면 CI가 달라진다
    rsB = RandStream('mt19937ar', 'Seed', 7);
    X = squeeze(R.dayH(2, :, :));  bs = zeros(2000, nM);
    for b = 1:2000, pick = randi(rsB, nDay, nDay, 1); s = sum(X(pick, :), 1); bs(b, :) = s / s(1); end
    dAlone = max(abs(prctile(bs, [2.5 97.5])' - squeeze(R.ci(2, :, :))), [], 'all');
    % (나) 한 해만 돌리면 줄 80~82의 squeeze가 차원을 바꿔 버린다
    totF  = R.tot(2, :, :, :);                           % 2024 한 해만 있는 것처럼
    mTotF = squeeze(mean(totF, 2));
    gainF = mTotF ./ mTotF(:, 1, :);
    oneYearOK = isequal(size(gainF), [1 nM nK]) && max(abs(gainF(1, :, 1) - R.gain(2, :, 1))) < 1e-9;
    try
        gHF = squeeze(totF(:, :, :, 1)) ./ squeeze(totF(:, :, 1, 1));
        oneYearOK = oneYearOK && isequal(size(gHF), [1 P.nPhase nM]);
    catch
        oneYearOK = false;
    end
    ok = dAlone < 1e-9 && oneYearOK;
    report(4, ok, sprintf('2024만 시드 7로 돌린 CI와 저장값 차 %.3f (0이면 연도별 독립), 한 해만 넣었을 때 집계 차원 정상 = %d  → FAIL이면 지적이 맞음(결과 수치에는 영향 없음)', dAlone, oneYearOK));
catch err
    report(4, false, ['실행 오류: ' err.message]);
end

%% CHECK 5: 이득 배수의 분모 = 천저 고정 (줄 81~82, 98)
try
    ok = true;
    for iy = 1:nY
        rowsY = find(MT.year == R.years(iy));
        hp = MT.heavyProf(rowsY);  gh = MT.gainHeavy(rowsY);
        nad = hp(1);                                     % 첫 줄 = methods(1) = 천저 고정
        ok = ok && max(abs(gh - hp / nad)) < 1e-9 && abs(nad - R.mTot(iy, 1, 1)) < 1e-9 && gh(1) == 1;
    end
    gainDay = squeeze(sum(R.dayH, 2)) ./ sum(R.dayH(:, :, 1), 2);          % 날짜 합 비율 = 점 추정치
    ok = ok && max(abs(gainDay - R.gain(:, :, 1)), [], 'all') < 1e-9;
    dpOverGreedy = MT.gainHeavy(MT.year == 2023);  dpOverGreedy = dpOverGreedy(4) / dpOverGreedy(2);
    report(5, ok, sprintf('methods.csv gainHeavy = heavyProf ÷ 천저 고정 heavyProf, 부트스트랩 점 추정치와도 일치 (참고: 2023 DP÷기존 방식 = %.2f배)', dpOverGreedy));
catch err
    report(5, false, ['실행 오류: ' err.message]);
end

%% CHECK 6: 방식 순서(plans{1..5}) ↔ methods.csv 줄 ↔ passes.csv 열 일치, 같은 씨앗 → 같은 큐 오차 (줄 30, 51~59, 73, 180~181)
try
    cols = {'heavyNadir', 'heavyGreedy', 'heavyDPpersist', 'heavyDPnowcast', 'heavyDPoracle'};
    ok = true;
    for iy = 1:nY
        py = PT.year == R.years(iy);
        fromPass = zeros(1, nM);
        for m = 1:nM, fromPass(m) = sum(PT.(cols{m})(py)) / R.P.nPhase; end
        ok = ok && max(abs(fromPass - reshape(MT.heavyProf(MT.year == R.years(iy)), 1, []))) < 1e-9 ...
                && max(abs(fromPass - reshape(R.mTot(iy, :, 1), 1, []))) < 1e-9;
    end
    ok = ok && all(PT.heavyDPoracle >= PT.heavyDPnowcast) && all(PT.upperBoundHeavy >= PT.heavyDPoracle);
    G = mkG(1800*4 + 300);
    [~, ~, iA] = L.rewardGrid(G, D, P, 'persist', RandStream('mt19937ar', 'Seed', 5), calibF);
    [~, ~, iB] = L.rewardGrid(G, D, P, 'nowcast', RandStream('mt19937ar', 'Seed', 5), calibF);
    ok = ok && isequal(iA.e, iB.e) && isequal(iA.kc, iB.kc);
    report(6, ok, sprintf('passes.csv 열 합÷%d = methods.csv heavyProf(방식 순서 일치), 통과마다 완벽정보 ≥ 나우캐스트, 이론상한 ≥ 완벽정보, 같은 씨앗이면 위치고정·나우캐스트 큐 오차 동일', R.P.nPhase));
catch err
    report(6, false, ['실행 오류: ' err.message]);
end

%% CHECK 7: 기동 횟수 정의 비대칭 — DP는 진입 전 미리 기울인 것을 세지 않음 (줄 69, kre_lib dpPlan 373 / greedyPlan 400)
try
    th = -P.maxDeg:P.stepDeg:P.maxDeg;  nq = 80;
    Rw = zeros(nq, numel(th));  Rw(:, th == 5) = 1;      % 통과 내내 +5°에만 비가 있는 보상 표
    plan = L.dpPlan(Rw, th, P);
    tilted = all(plan.th(plan.valid) == 5);              % 처음부터 5°로 기울인 채 들어옴
    ok = ~(tilted && plan.nMoves == 0);                  % 기울였는데 기동 0회로 세면 지적이 맞음
    report(7, ok, sprintf('+5°만 보상인 통과: DP 경로 전부 5°(=%d), nMoves = %d → 천저→5° 기동 1회가 빠짐 (기존 방식 nTargets는 첫 표적을 셈). 이득 수치에는 영향 없음', tilted, plan.nMoves));
catch err
    report(7, false, ['실행 오류: ' err.message]);
end

%% CHECK 8: NaN 처리 — 기동 중 표본·자료 영역 밖 표본은 세지 않음 (kre_lib evaluate 408~411, sampleField, heavyInSwath)
try
    G = mkG(1800*4 + 300);
    plan0 = struct('cb', zeros(size(G.tq)), 'valid', true(size(G.tq)));
    E0 = L.evaluate(G, D, P, plan0);
    plan1 = plan0;  plan1.valid(E0.val >= P.thrHeavy) = false;     % 호우를 본 표본을 모두 '기동 중'으로 바꾸면
    E1 = L.evaluate(G, D, P, plan1);
    Gout = G;  Gout.Pg.latm = 45;                                  % 통과를 자료 영역 밖(북위 45°)으로
    E2 = L.evaluate(Gout, D, P, plan0);
    ub2 = L.heavyInSwath(Gout, D, P);
    ok = E0.heavy > 0 && E1.heavy == 0 && E1.valid == E0.valid - E0.heavy ...
        && E2.heavy == 0 && E2.rain == 0 && all(isnan(E2.val)) && ub2 == 0;
    report(8, ok, sprintf('천저 호우 %d개 → 그 표본을 기동 중으로 두면 0개, 영역 밖 통과는 호우·강수 0·값 전부 NaN·이론 상한 0 (오류 없음)', E0.heavy));
catch err
    report(8, false, ['실행 오류: ' err.message]);
end

%% ===================== 보조 함수 =====================
function report(n, ok, msg)
if ok, s = 'PASS'; else, s = 'FAIL'; end
fprintf('CHECK %d: %s - %s\n', n, s, msg);
end

function [D, mkG] = fakeScene(P)
% 0.1° 격자 31×31, 30분 칸 12개짜리 가짜 강수장. 가운데(행·열 14~18)에 20 mm/h 호우 덩어리, 구석에 3 mm/h 약한 비
nT = 12;
D.lat = (30:0.1:33)';  D.lon = (125:0.1:128)';
D.Pr = zeros(numel(D.lat), numel(D.lon), nT, 'single');
D.Pr(14:18, 14:18, :) = 20;
D.Pr(5:7, 5:7, :) = 3;
D.nT = nT;  D.motion = zeros(nT, 2);  D.year = 0;  D.src = 'final';
D.t0 = datetime(2023, 6, 1, 'TimeZone', 'UTC');
D.kmLat = 110.57 * 0.1;  D.kmLon = 111.32 * 0.1 * cosd(31.5);
mkG = @(ts) makePass(ts, nT, P);
end

function G = makePass(ts, nT, P)
% 동경 126.5°를 따라 북쪽으로 120 s 동안 지나가는 통과 (국소 평면 x = 동, y = 북 [km])
G.Pg = struct('latm', 31.5, 'lonm', 126.5, 'kx', 111.32 * cosd(31.5), 'ky', 110.57);
G.ts = ts;
G.tq = (ts:P.profDt:ts + 120)';
nq = numel(G.tq);
G.xq = zeros(nq, 1);
G.yq = linspace(-60, 60, nq)';
G.nq = repmat([-1 0], nq, 1);                     % 진행 방향(북)의 왼쪽 = 서쪽 (빔 오프셋 +)
G.kq = min(max(floor(G.tq / 1800) + 1, 1), nT);
end
