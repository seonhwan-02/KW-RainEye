%% 07_check.m : dp_step5_sensitivity.m 검토 확인 (그림 없음, 60초 안에 끝남)
% 07_dp_step5_sensitivity.md 5절의 지적 1~8을 하나씩 확인한다.
%   PASS = 코드가 의도대로 동작함,  FAIL = 지적이 맞음 (또는 확인 중 오류)
% 저장된 결과(out/dp_step5_sensitivity, out/dp_step4_realistic)를 읽거나,
% 작은 가짜 보상 격자·가짜 시즌으로 kre_lib의 dpPlan·calibrate만 짧게 돌린다. 시즌 재계산은 하지 않는다.
% (러너에서 실행: clear 생략)
root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(fullfile(root, 'dp'));
L  = kre_lib();
P0 = L.params();  P0.pDet = 1;  P0.posSd = 0;  P0.velSd = 0;     % 5단계 줄 26~27과 같게
out5 = fullfile(root, 'out', 'dp_step5_sensitivity');
out4 = fullfile(root, 'out', 'dp_step4_realistic');
S5 = load(fullfile(out5, 'results.mat'), 'years', 'cs', 'gain', 'ci', 'dayH', 'dayN', 'P0', 'rel');
cs = S5.cs;  nC = numel(cs);
S4 = load(fullfile(out4, 'calib_early_2023.mat'), 'calibE', 'Pe');          % 4단계 학습 표와 Pe
T4 = readtable(fullfile(out4, 'methods.csv'), 'Encoding', 'UTF-8', 'TextType', 'string');
r4 = contains(T4.method, "나우캐스트") & contains(T4.method, "Early") & ~contains(T4.method, "가짜");

%% CHECK 1: 조건마다 바꾸려는 매개변수만 바뀌고 나머지는 기준과 같은가 + 기준 조건 = 4단계 결과
try
    expS = [4 2 8 4 4 4 4 4];  expL = [15 15 15 30 45 15 15 15];
    expR = [1.5 1.5 1.5 1.5 1.5 1 1.5 1.5];  expM = [10 10 10 10 10 10 3 5];
    okList = isequal([cs.settle], expS) && isequal([cs.cueL], expL) && ...
             isequal([cs.slewRate], expR) && isequal([cs.maxDeg], expM);
    okCopy = true;
    for c = 1:nC                                   % 5단계 줄 72~73을 그대로 흉내 내어 복사본 검사
        Pc = P0;  Pc.settle = cs(c).settle;  Pc.cueL = cs(c).cueL;  Pc.slewRate = cs(c).slewRate;  Pc.maxDeg = cs(c).maxDeg;
        if cs(c).cueL ~= 15, Pc.lags = 1:4; end
        fn = fieldnames(P0);
        for k = 1:numel(fn)
            f = fn{k};
            if any(strcmp(f, {'settle', 'cueL', 'slewRate', 'maxDeg', 'lags'})), continue; end
            okCopy = okCopy && isequaln(Pc.(f), P0.(f));
        end
        okCopy = okCopy && isequal(Pc.lags, P0.lags) == (cs(c).cueL == 15);   % lags는 큐 지연이 다를 때만 바뀐다
    end
    okBase = isequaln(rmfield(S5.P0, 'C'), rmfield(P0, 'C'));      % 저장된 P0 = params + pDet 1/posSd 0/velSd 0
    okPe = isequaln(rmfield(S4.Pe, 'C'), rmfield(P0, 'C'));         % 4단계 Pe와 5단계 P0가 같다
    g4 = zeros(1, 3);
    for iy = 1:3, g4(iy) = T4.gainHeavy(r4 & T4.year == S5.years(iy)); end
    dBase = max(abs(S5.gain(:, 1)' - g4));
    ok = okList && okCopy && okBase && okPe && dBase < 1e-9;
    fprintf('CHECK 1: %s - 조건표 %d, 복사본(다른 필드 동일) %d, P0=Pe %d, 기준 배수-4단계 차이 %.1e (2023/24/25 = %.4f/%.4f/%.4f)\n', ...
        tf(ok), okList, okCopy, okBase && okPe, dBase, S5.gain(1, 1), S5.gain(2, 1), S5.gain(3, 1));
catch ME
    fprintf('CHECK 1: FAIL - 확인 중 오류: %s\n', ME.message);
end

%% CHECK 2: 큐 지연 15·30·45분에서 '관측 칸 - 큐 칸'(lag)이 학습 표의 열 안에 드는가
try
    % kre_lib의 cueSlot(줄 265~273)·passSetup(줄 216)·rewardGrid(줄 254)을 세 줄로 옮긴 것
    lagSet = cell(1, 3);  leadMin = zeros(3, 2);  cueLs = [15 30 45];
    tsAll = (2 * 1800):10:(4 * 1800 - 1);              % 통과 시작 시각을 두 칸에 걸쳐 10초씩 훑는다
    for i = 1:3
        lags = [];  leads = [];
        for ts = tsAll
            tq = (ts:P0.profDt:ts + 300)';                % 통과 길이 5분 (실제 통과는 3~4분)
            kc = floor((ts - cueLs(i) * 60) / 1800);     % 큐 시각 전에 끝난 마지막 30분 칸
            kq = floor(tq / 1800) + 1;                   % 각 표본이 속한 칸
            lags  = [lags; unique(kq - kc)]; %#ok<AGROW>
            leads = [leads; (tq - (kc - 0.5) * 1800) / 60]; %#ok<AGROW>
        end
        lagSet{i} = unique(lags)';  leadMin(i, :) = [min(leads) max(leads)];
    end
    ok15 = all(ismember(lagSet{1}, P0.lags));            % 기준: 표 열 [1 2] 안
    ok30 = all(ismember(lagSet{2}, 1:4)) && all(ismember(lagSet{3}, 1:4));   % 재학습 표 열 1:4 안
    Pc = P0;  Pc.lags = 1:4;
    Dk = fakeSeason(12);
    cal4 = L.calibrate(Dk, Pc, 'nowcast', 2023);        % 가짜 시즌으로 표 모양만 확인
    okCal = isequal(cal4.lags, 1:4) && isequal(size(cal4.pHeavy), [numel(P0.edges) - 1, 4]) ...
            && isequal(S4.calibE.lags, P0.lags) && size(S4.calibE.pHeavy, 2) == numel(P0.lags);
    ok = ok15 && ok30 && okCal;
    fprintf('CHECK 2: %s - lag 집합 15분 {%s}, 30분 {%s}, 45분 {%s}; 실제 앞섬 15분 %.0f~%.0f분, 30분 %.0f~%.0f분, 45분 %.0f~%.0f분; 표 열 수 기준 %d·재학습 %d\n', ...
        tf(ok), num2str(lagSet{1}), num2str(lagSet{2}), num2str(lagSet{3}), leadMin(1, :), leadMin(2, :), leadMin(3, :), ...
        size(S4.calibE.pHeavy, 2), size(cal4.pHeavy, 2));
catch ME
    fprintf('CHECK 2: FAIL - 확인 중 오류: %s\n', ME.message);
end

%% CHECK 3: 지향 ±3°·±5°에서 각도 격자와 기동 한계가 함께 줄어드는가 (가짜 보상 격자)
try
    ok = true;  msg = '';
    for md = [3 5 10]
        Pc = P0;  Pc.maxDeg = md;
        [Rw, th] = fakeReward(Pc);
        plan = L.dpPlan(Rw, th, Pc);
        mExp = ceil((md / Pc.slewRate + Pc.settle) / Pc.profDt);     % 0° → +md° 한 번 기동에 놓치는 표본 수
        okc = numel(th) == 2 * md + 1 && max(abs(plan.th(plan.valid))) <= md + 1e-9 ...
              && plan.nMoves == 1 && nnz(~plan.valid) == mExp && max(plan.th(plan.valid)) == md;
        ok = ok && okc;
        msg = [msg sprintf('±%d°: 격자 %d개, 최대 |각| %g, 놓친 표본 %d(예상 %d); ', md, numel(th), max(abs(plan.th(plan.valid))), nnz(~plan.valid), mExp)]; %#ok<AGROW>
    end
    fprintf('CHECK 3: %s - %s\n', tf(ok), msg);
catch ME
    fprintf('CHECK 3: FAIL - 확인 중 오류: %s\n', ME.message);
end

%% CHECK 4: 정착 시간[초]·기동 속도[°/s]가 놓치는 표본 수(1.5초 단위)로 바르게 환산되는가
try
    ok = true;  msg = '';
    conds = [2 1.5; 4 1.5; 8 1.5; 4 1];                  % [정착 s, 기동 deg/s]
    for i = 1:size(conds, 1)
        Pc = P0;  Pc.settle = conds(i, 1);  Pc.slewRate = conds(i, 2);
        [Rw, th] = fakeReward(Pc);
        plan = L.dpPlan(Rw, th, Pc);
        tMove = 10 / Pc.slewRate + Pc.settle;             % 0° → 10° 기동+정착 [s]
        mExp = ceil(tMove / Pc.profDt);
        okc = plan.nMoves == 1 && nnz(~plan.valid) == mExp;
        ok = ok && okc;
        msg = [msg sprintf('정착 %g s·%g°/s: %.2f s → %d표본(예상 %d); ', Pc.settle, Pc.slewRate, tMove, nnz(~plan.valid), mExp)]; %#ok<AGROW>
    end
    fprintf('CHECK 4: %s - %s\n', tf(ok), msg);
catch ME
    fprintf('CHECK 4: FAIL - 확인 중 오류: %s\n', ME.message);
end

%% CHECK 5: cases.csv·key_sensitivity.json·results.mat의 경우 이름·값 정렬이 서로 맞는가
try
    T = readtable(fullfile(out5, 'cases.csv'), 'Encoding', 'UTF-8', 'TextType', 'string', 'VariableNamingRule', 'preserve');   % 'case' 열 이름 보존
    J = jsondecode(fileread(fullfile(out5, 'key_sensitivity.json')));
    okN = height(T) == nC * 3;
    okOrder = true;  okRel = true;  okCI = true;  okJ = true;
    for c = 1:nC
        for iy = 1:3
            r = (c - 1) * 3 + iy;                        % 줄 144~151: 조건이 바깥, 해가 안쪽
            okOrder = okOrder && strcmp(T.("case")(r), string(cs(c).name)) && T.year(r) == S5.years(iy) ...
                      && T.settle_s(r) == cs(c).settle && T.cueLatency_min(r) == cs(c).cueL ...
                      && T.slewRate_degps(r) == cs(c).slewRate && T.maxDeg(r) == cs(c).maxDeg ...
                      && abs(T.gainHeavy(r) - S5.gain(iy, c)) < 1e-9;
            base = T.gainHeavy((iy));                    % 같은 해의 기준 조건 행 (c = 1)
            okRel = okRel && abs(T.relToBaseline(r) - T.gainHeavy(r) / base) < 1e-9;
            okCI  = okCI && T.ci95Low(r) <= T.gainHeavy(r) && T.gainHeavy(r) <= T.ci95High(r);
            okJ   = okJ && abs(J.gain(iy, c) - S5.gain(iy, c)) < 1e-9 && strcmp(J.cases(c).name, cs(c).name);
        end
    end
    ok = okN && okOrder && okRel && okCI && okJ;
    fprintf('CHECK 5: %s - 행 수 %d(=%d×3) %d, 이름·해·매개변수·배수 정렬 %d, 기준대비=배수/기준 %d, CI가 배수를 품음 %d, json 일치 %d\n', ...
        tf(ok), height(T), nC, okN, okOrder, okRel, okCI, okJ);
catch ME
    fprintf('CHECK 5: FAIL - 확인 중 오류: %s\n', ME.message);
end

%% CHECK 6: 씨앗이 조건마다 같고, 가짜 오차를 껐으므로(pDet 1·posSd 0·velSd 0) 씨앗이 결과에 영향을 주지 않는가
try
    okOff = S5.P0.pDet == 1 && S5.P0.posSd == 0 && S5.P0.velSd == 0;
    Dk = fakeSeason(12);
    Pc = P0;  Pc.lags = 1:4;
    cA = L.calibrate(Dk, Pc, 'nowcast', 1);
    cB = L.calibrate(Dk, Pc, 'nowcast', 2);
    okSame = isequal(cA.pHeavy, cB.pHeavy) && isequal(cA.pRain, cB.pRain) && isequal(cA.count, cB.count);
    Pd = L.params();  Pd.lags = 1:4;                     % 비교용: 가짜 오차를 켜면 씨앗에 따라 표가 달라진다
    dA = L.calibrate(Dk, Pd, 'nowcast', 1);
    dB = L.calibrate(Dk, Pd, 'nowcast', 2);
    diffOn = ~isequal(dA.count, dB.count);
    seedMax = 2025 * 1e5 + P0.nPhase * 1e4 + 9999;       % 줄 66 씨앗의 최댓값 (RandStream 씨앗 상한 2^32-1)
    ok = okOff && okSame && seedMax < 2^32;
    fprintf('CHECK 6: %s - 가짜 오차 꺼짐 %d, 씨앗 1·2 학습 표 동일 %d (오차 켜면 달라짐 %d), 씨앗 최댓값 %.0f < 2^32\n', ...
        tf(ok), okOff, okSame, diffOn, seedMax);
catch ME
    fprintf('CHECK 6: FAIL - 확인 중 오류: %s\n', ME.message);
end

%% CHECK 7: summary.txt의 조건 이름에 쉼표가 들어 있어 ', '로 나누면 열이 어긋나는가 (개선 제안)
try
    txt = fileread(fullfile(out5, 'summary.txt'));
    lines = strsplit(txt, newline);
    hdr = lines{4};  row = lines{5};                     % 4번째 줄 = 머리글, 5번째 줄 = 기준 조건
    nH = numel(strsplit(hdr, ', '));  nR = numel(strsplit(row, ', '));
    ok = nH == nR;                                       % 같으면 코드가 의도대로, 다르면 지적이 맞음
    fprintf('CHECK 7: %s - 머리글 %d열, 기준 조건 행 %d열 (이름 안 쉼표 때문에 %d열 어긋남; cases.csv는 따옴표로 보호됨)\n', ...
        tf(ok), nH, nR, nR - nH);
catch ME
    fprintf('CHECK 7: FAIL - 확인 중 오류: %s\n', ME.message);
end

%% CHECK 8: 신뢰구간이 저장된 dayH·dayN과 씨앗 200+해로 재현되는가 (4단계와 CI가 다른 이유 = 씨앗만 다름)
try
    nDay = size(S5.dayH, 2);
    okRep = true;  dMax = 0;
    for iy = 1:3
        rs = RandStream('mt19937ar', 'Seed', 200 + S5.years(iy));
        bs = zeros(2000, nC);
        for b = 1:2000
            pick = randi(rs, nDay, nDay, 1);
            bs(b, :) = sum(squeeze(S5.dayH(iy, pick, :)), 1) / sum(S5.dayN(iy, pick));
        end
        ciRe = reshape(prctile(bs, [2.5 97.5])', [1 nC 2]);
        dMax = max(dMax, max(abs(ciRe(:) - reshape(S5.ci(iy, :, :), [], 1))));
    end
    okRep = dMax < 1e-9;
    ci4 = [T4.ci95Low(r4 & T4.year == 2023), T4.ci95High(r4 & T4.year == 2023)];
    ci5 = squeeze(S5.ci(1, 1, :))';
    gSame = abs(T4.gainHeavy(r4 & T4.year == 2023) - S5.gain(1, 1)) < 1e-9;
    ok = okRep && gSame;
    fprintf('CHECK 8: %s - CI 재현 오차 %.1e; 2023 기준 배수는 4단계와 같고(%d) CI만 다름: 4단계 %.3f~%.3f(씨앗 7 공용) vs 5단계 %.3f~%.3f(씨앗 2223)\n', ...
        tf(ok), dMax, gSame, ci4, ci5);
catch ME
    fprintf('CHECK 8: FAIL - 확인 중 오류: %s\n', ME.message);
end

%% ---------- 보조 함수 ----------
function s = tf(ok)
if ok, s = 'PASS'; else, s = 'FAIL'; end
end

function [Rw, th] = fakeReward(P)
% 가짜 보상 격자: 앞 30표본은 0°에만, 뒤 30표본은 +maxDeg에만 점수 1 → DP는 가운데서 한 번만 기동해야 한다
th = -P.maxDeg:P.stepDeg:P.maxDeg;
nq = 60;
Rw = zeros(nq, numel(th));
Rw(1:30, th == 0) = 1;
Rw(31:nq, th == P.maxDeg) = 1;
end

function D = fakeSeason(nT)
% 가짜 시즌: 20×20 칸, nT개의 30분 장면, 이동 벡터 0 (calibrate의 표 모양·씨앗 영향만 본다)
rs = RandStream('mt19937ar', 'Seed', 11);
D.lat = (30:0.1:31.9)';  D.lon = (120:0.1:121.9)';
D.Pr  = 25 * rand(rs, 20, 20, nT) .* (rand(rs, 20, 20, nT) > 0.6);
D.nT  = nT;  D.motion = zeros(nT, 2);  D.year = 2023;
end
