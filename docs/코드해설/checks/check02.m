%% 02_check.m — 02번 해설(dp/dp_step1_train.m)의 코드 검토 지적을 확인하는 스크립트
% 실행: MATLAB에서 이 파일을 그냥 실행 (그림 없음, 1분 안에 끝남)
% 출력: 지적마다 한 줄  CHECK n: PASS/FAIL - 설명
%   PASS = 코드가 의도대로 동작함(지적은 오해 또는 영향 없음), FAIL = 지적이 맞음
% 실제 자료는 CHECK 8에서만 L.loadSeason(2023,'final') (캐시 cache_2023_JJAS.mat) 을 쓴다.

root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(fullfile(root, 'dp'));
L  = kre_lib();
P0 = L.params();
outDir = fullfile(root, 'out', 'dp_step1_train');
srcFile = fullfile(root, 'dp', 'dp_step1_train.m');

% 가짜 오차를 모두 끈 매개변수 (pDet=1 → 호우 핵을 다 알아봄, 위치·속도 오차 0)
Pc = P0;  Pc.pDet = 1;  Pc.posSd = 0;  Pc.velSd = 0;
% 20×20 칸(0.1°), 위도 33.05~34.95, 경도 125.05~126.95
latF = (33.05:0.1:34.95)';  lonF = (125.05:0.1:126.95)';
iHeavy = find(P0.edges == 20);            % 20 mm/h 가 들어가는 구간 번호 (20~30 → 10번째)

%% CHECK 1: 학습(2023)과 검증(2024/2025) 자료가 섞이나 — 파일 본문에서 loadSeason 호출 연도만 본다
txt = fileread(srcFile);
yrs = regexp(txt, 'loadSeason\((\d{4})', 'tokens');
yrs = cellfun(@(c) str2double(c{1}), yrs);
seeds = regexp(txt, 'calibrate\([^)]*,\s*(\d{4})\)', 'tokens');
seeds = cellfun(@(c) str2double(c{1}), seeds);
ok1 = numel(yrs) == 1 && all(yrs == 2023) && all(seeds == 2023);
say(1, ok1, sprintf('loadSeason 호출 연도 = %s, calibrate 시드 = %s (2023만 쓴다, 2024/2025는 3·4단계에서만 읽음)', ...
    mat2str(yrs), mat2str(seeds)));

%% CHECK 2: 미래 정보 누수 — 큐 장면 k의 비를 '같은 장면'으로 채점하면 안 되고, k+lag 장면으로 채점해야 한다
D = fakeSeason(5, latF, lonF);
D.Pr(8:11, 8:11, 3) = 20;                 % 3번 장면에만 20 mm/h 덩어리 16칸
c2 = L.calibrate(D, Pc, 'nowcast', 2023);
% 기대: 큐=3번 장면(덩어리, 10번 구간) → 진실 4·5번 장면(비 없음) → 호우 확률 0
%       큐=2번 장면(비 없음, 1번 구간) → 진실 3번 장면에 호우 16칸 → nH(1,1)=16
nH11 = c2.pHeavy(1, 1) * c2.count(1, 1);
ok2 = c2.count(iHeavy, 1) == 16 && c2.pHeavy(iHeavy, 1) == 0 && c2.pHeavy(iHeavy, 2) == 0 && abs(nH11 - 16) < 1e-9;
say(2, ok2, sprintf('큐 덩어리 구간 count=%d, pHeavy(30분)=%.3f, pHeavy(60분)=%.3f (누수면 1.0), 다음 장면 호우는 1번 구간에 %.0f칸 (큐 장면 k → 진실 k+lag)', ...
    c2.count(iHeavy, 1), c2.pHeavy(iHeavy, 1), c2.pHeavy(iHeavy, 2), nH11));

%% CHECK 3: 이동 벡터의 방향·단위 — 동쪽으로 2칸 움직인 덩어리를 나우캐스트가 정확히 따라가나
D = fakeSeason(4, latF, lonF);
D.Pr(6:15, 5:8, 2) = 20;                  % 2번 장면: 5~8열
D.Pr(6:15, 7:10, 3) = 20;                 % 3번 장면: 7~10열 (동쪽으로 2칸 = 0.2°)
D.motion(2, :) = [2 * 0.1 * 111.32 * cosd(34) / 1800, 0];   % [동, 북] km/s
cN = L.calibrate(D, Pc, 'nowcast', 2023);
cP = L.calibrate(D, Pc, 'persist', 2023);
ok3 = cN.count(iHeavy, 1) == 40 && cN.pHeavy(iHeavy, 1) == 1 && abs(cP.pHeavy(iHeavy, 1) - 0.5) < 1e-12;
say(3, ok3, sprintf('나우캐스트 pHeavy=%.2f (count %d, 기대 1.00/40), 위치고정 pHeavy=%.2f (기대 0.50) — 부호가 반대면 나우캐스트가 0이 된다', ...
    cN.pHeavy(iHeavy, 1), cN.count(iHeavy, 1), cP.pHeavy(iHeavy, 1)));

%% CHECK 4: 난수 시드 — 같은 시드면 같은 표, nowcast/persist가 같은 난수열을 쓰나, 다른 시드면 달라지나
rs = RandStream('mt19937ar', 'Seed', 1);
D = fakeSeason(8, latF, lonF);
D.Pr = single(40 * rand(rs, 20, 20, 8).^4);   % 0~40 mm/h 사이 울퉁불퉁한 비 (호우 핵 여러 개)
a1 = L.calibrate(D, P0, 'nowcast', 2023);
a2 = L.calibrate(D, P0, 'nowcast', 2023);
P1 = P0;  P1.velSd = 0;                   % 속도오차를 끄면 (motion=0이므로) nowcast와 persist는 완전히 같아야 한다
b1 = L.calibrate(D, P1, 'nowcast', 2023);
b2 = L.calibrate(D, P1, 'persist', 2023);
a3 = L.calibrate(D, P0, 'nowcast', 7);
diffSeed = ~isequal(a1.count, a3.count) || ~isequal(a1.pHeavy, a3.pHeavy);
ok4 = isequal(a1.pHeavy, a2.pHeavy) && isequal(a1.count, a2.count) && isequal(b1.pHeavy, b2.pHeavy) ...
    && isequal(b1.count, b2.count) && diffSeed;
say(4, ok4, sprintf('같은 시드 재현 %d, nowcast=persist(속도오차 0) %d, 다른 시드(7)는 다름 %d', ...
    isequal(a1.count, a2.count), isequal(b1.count, b2.count), diffSeed));

%% CHECK 5: 경계 조건 — 구간 끝값(0, 0.5, 10, 30, 매우 큰 값)이 어느 칸에 들어가나, 빈 구간은 NaN이 아닌 0인가
vals = [0 0.4999 0.5 1 9.999 10 30 1e4];
bins = discretize(vals, P0.edges);
expB = [1 1 2 3 7 8 11 11];
lo = P0.edges(1:end - 1);  hi = P0.edges(2:end);
lbl = compose('%g~%g', lo', hi');  lbl{end} = sprintf('%g 이상', lo(end));
okLbl = numel(lbl) == 11 && strcmp(lbl{2}, '0.5~1') && strcmp(lbl{end}, '30 이상');
D = fakeSeason(5, latF, lonF);
D.Pr(8:11, 8:11, 2) = 12;                 % 10~15 구간만 채움 → 15~20 구간(9번)은 비어 있음
c5 = L.calibrate(D, Pc, 'nowcast', 2023);
okEmpty = all(c5.count(9, :) == 0) && all(c5.pHeavy(9, :) == 0) && ~any(isnan(c5.pHeavy(:)));
ok5 = isequal(bins, expB) && okLbl && okEmpty;
say(5, ok5, sprintf('구간 번호 %s (기대 %s), 이름표 11개·끝 "%s", 빈 구간 확률 = 0 (NaN 아님) %d', ...
    mat2str(bins), mat2str(expB), lbl{end}, okEmpty));

%% CHECK 6: 반복 범위 k = 2 : nT - max(lags) — 마지막 장면까지 진실로 쓰이고 인덱스가 넘치지 않나
D = fakeSeason(6, latF, lonF);
D.Pr(8:11, 8:11, 6) = 20;                 % 맨 끝(6번) 장면에만 호우 16칸
try
    c6 = L.calibrate(D, Pc, 'nowcast', 2023);
    nH12 = c6.pHeavy(1, 2) * c6.count(1, 2);   % k=4, lag 2 → 진실 6번 장면
    nH11 = c6.pHeavy(1, 1) * c6.count(1, 1);   % lag 1로 6번 장면을 보려면 k=5가 필요한데 반복은 k=4까지
    ok6 = abs(nH12 - 16) < 1e-9 && nH11 == 0;
    say(6, ok6, sprintf('오류 없음, 60분 표에 끝 장면 호우 %.0f칸 반영(기대 16), 30분 표는 %.0f칸(k=nT-1 쌍 하나는 안 씀, 5,853쌍 중 1쌍)', nH12, nH11));
catch ME
    say(6, false, ['인덱스 오류: ' ME.message]);
end

%% CHECK 7: 저장된 결과 ↔ 현재 매개변수 ↔ json ↔ 주석의 하드코딩 숫자(5,856장면 × 15,600칸)
files = {'calib_2023.mat', 'key_calib.json', 'summary.txt', 'fig_calibration.png'};
haveF = cellfun(@(f) exist(fullfile(outDir, f), 'file') == 2, files);
msg7 = sprintf('결과 파일 %d/4 있음', sum(haveF));
ok7 = all(haveF);
if haveF(1) && haveF(2)
    S = load(fullfile(outDir, 'calib_2023.mat'));
    J = jsondecode(fileread(fullfile(outDir, 'key_calib.json')));
    sameP = isequal(S.P.edges, P0.edges) && isequal(S.P.lags, P0.lags) && S.P.pDet == P0.pDet ...
        && S.P.posSd == P0.posSd && S.P.velSd == P0.velSd && S.P.cueL == P0.cueL;
    sameJ = max(abs(J.pHeavyNowcast(:) - S.calibN.pHeavy(:))) < 1e-9 && isequal(J.count, S.calibN.count) ...
        && isequal(J.lagsMin(:)', 30 * P0.lags) && isequal(J.edges(:)', P0.edges(1:end - 1)) ...
        && size(J.pHeavyNowcast, 1) == numel(J.edges);
    okMode = strcmp(S.calibN.mode, 'nowcast') && strcmp(S.calibP.mode, 'persist') && S.calibN.year == 2023;
    ok7 = ok7 && sameP && sameJ && okMode && min(S.calibN.count(:)) > 0;
    msg7 = sprintf('%s, 저장된 P = 현재 params %d, json = mat %d, mode/year %d, 최소 칸 수 %d', ...
        msg7, sameP, sameJ, okMode, min(S.calibN.count(:)));
end
imergRoot = fullfile(getenv('USERPROFILE'), 'Desktop', 'K-RainEye_IMERG');
haveCache = exist(fullfile(imergRoot, 'cache_2023_JJAS.mat'), 'file') == 2 && exist(fullfile(imergRoot, 'motion_2023_JJAS.mat'), 'file') == 2;
if haveCache && haveF(3)
    D23 = L.loadSeason(2023, 'final');
    nCell = size(D23.Pr, 1) * size(D23.Pr, 2);
    tok = regexp(fileread(fullfile(outDir, 'summary.txt'), 'Encoding', 'UTF-8'), 'IMERG,\D*(\d+)', 'tokens', 'once');
    if isempty(tok), nTsum = NaN; else, nTsum = str2double(tok{1}); end
    okDim = size(D23.Pr, 1) == numel(D23.lat) && size(D23.Pr, 2) == numel(D23.lon);
    okN = D23.nT == 5856 && nCell == 15600 && nTsum == D23.nT;
    okSum = true;
    if exist('S', 'var'), okSum = all(sum(S.calibN.count, 1) <= (D23.nT - 1 - max(P0.lags)) * nCell); end
    ok7 = ok7 && okDim && okN && okSum;
    msg7 = sprintf('%s, 실제 자료 장면 %d개 × %d칸(위도 %d × 경도 %d, %.1f~%.1fN %.1f~%.1fE), summary 장면 %d, Pr 차원=위도×경도 %d, 칸 수 합 ≤ 상한 %d', ...
        msg7, D23.nT, nCell, numel(D23.lat), numel(D23.lon), min(D23.lat), max(D23.lat), min(D23.lon), max(D23.lon), nTsum, okDim, okSum);
    clear D23
else
    msg7 = [msg7 ', (캐시 없음 → 실제 자료 비교 생략)'];
end
say(7, ok7, msg7);

%% CHECK 8: run_log.csv 기록 — 3·4·4b·5단계는 한 줄씩 남기는데 1단계는 남기나 (개선 제안: FAIL = 지적이 맞음)
logFile = fullfile(root, 'out', 'run_log.csv');
hasRow = false;
if exist(logFile, 'file') == 2
    hasRow = ~isempty(regexp(fileread(logFile), 'dp_step1_train', 'once'));
end
inCode = ~isempty(regexp(txt, 'run_log', 'once'));
say(8, hasRow || inCode, sprintf('run_log.csv에 dp_step1_train 행 %d, 코드에 run_log 언급 %d (없으면 지적대로 — 결과 4개 파일 저장 자체는 CHECK 7)', hasRow, inCode));

%% ---------- 도우미 ----------
function say(n, ok, msg)
if ok, s = 'PASS'; else, s = 'FAIL'; end
fprintf('CHECK %d: %s - %s\n', n, s, msg);
end

function D = fakeSeason(nT, lat, lon)
% calibrate가 쓰는 필드만 갖춘 작은 가짜 시즌 (비 없음, 이동 0)
D.lat = lat(:);  D.lon = lon(:);
D.Pr  = zeros(numel(lat), numel(lon), nT, 'single');
D.nT  = nT;  D.year = 2023;  D.src = 'fake';
D.t0  = datetime(2023, 6, 1, 'TimeZone', 'UTC');
D.tSlot = D.t0 + seconds(1800 * (0:nT - 1))';
D.kmLat = 110.57 * 0.1;  D.kmLon = 111.32 * 0.1 * cosd(mean(lat));
D.motion = zeros(nT, 2);
end
