%% 06_check.m — dp_step4b_upstream.m 코드 검토(06번 문서 5절) 확인용
% 그림 없음, 전체 시즌 재계산 없음, 1분 안에 끝남.
% 저장된 결과(out/dp_step4b_upstream, out/dp_step4_realistic)와 코드 본문을 읽어 비교한다.
% PASS = 코드가 의도대로 동작함, FAIL = 지적이 맞음(고치거나 적어 두어야 함), ERROR = 확인 자체가 실패
% CHECK 번호 = 06번 문서 5절 표의 지적 번호

root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(fullfile(root, 'dp'));
d4b = fullfile(root, 'out', 'dp_step4b_upstream');
d4  = fullfile(root, 'out', 'dp_step4_realistic');
R  = load(fullfile(d4b, 'results.mat'));                                   % years methods tot dayH mTot gain ci nPass P Pe
R4 = load(fullfile(d4, 'results.mat'), 'nPass', 'P', 'gain', 'methods', 'ci');
L  = kre_lib();
P  = R.P;
fprintf('06_check: dp_step4b_upstream.m (결과 %s)\n', d4b);

%% CHECK 1: 학습표는 관측창과 무관한가 — kre_lib.m에서 winLat/winLon을 읽는 함수 찾기
try
    txt = fileread(fullfile(root, 'dp', 'kre_lib.m'), 'Encoding', 'UTF-8');
    st  = regexp(txt, '^function\s', 'start', 'lineanchors');
    nm  = regexp(txt, '^function\s+(?:[^=\n]*=\s*)?(\w+)\s*\(', 'tokens', 'lineanchors');
    assert(numel(nm) == numel(st), '함수 머리 줄 개수가 안 맞음');
    nm  = cellfun(@(c) c{1}, nm, 'UniformOutput', false);
    st(end + 1) = numel(txt) + 1;
    users = {};
    for k = 1:numel(nm)
        blk = txt(st(k):st(k + 1) - 1);
        if contains(blk, 'winLat') || contains(blk, 'winLon'), users{end + 1} = nm{k}; end %#ok<SAGROW>
    end
    S = load(fullfile(d4, 'calib_early_2023.mat'), 'calibE', 'P');
    ok = isequal(sort(users), sort({'defaultParams', 'orbitPasses'}));
    fprintf('CHECK 1: %s - winLat/winLon을 읽는 함수 = {%s}; calibrate는 창을 안 봄 → 표 재사용은 창과 무관 (표를 만든 P.winLat = [%g %g], 표본 수 %.3g칸)\n', ...
        pf(ok), strjoin(users, ', '), S.P.winLat, sum(S.calibE.count(:, 1)));
catch e, fprintf('CHECK 1: ERROR - %s\n', e.message); end

%% CHECK 2: 관측창 경계의 순서(위도/경도, 남<북, 서<동)와 step4 창과의 관계
try
    ok = isequal(P.winLat, [28 38]) && isequal(P.winLon, [119 127]) ...
        && P.winLat(1) < P.winLat(2) && P.winLon(1) < P.winLon(2) ...
        && all(abs(P.winLat) <= 90) && all(P.winLon >= 100 & P.winLon <= 140) ...   % 한반도 부근 경도라야 함
        && isequal(R.Pe.winLat, P.winLat) && isequal(R.Pe.winLon, P.winLon);         % Pe도 새 창
    sub = P.winLat(1) >= R4.P.winLat(1) && P.winLat(2) <= R4.P.winLat(2) ...
        && P.winLon(1) >= R4.P.winLon(1) && P.winLon(2) <= R4.P.winLon(2);
    area4b = diff(P.winLat) * diff(P.winLon);  area4 = diff(R4.P.winLat) * diff(R4.P.winLon);
    fprintf('CHECK 2: %s - winLat=[%g %g] winLon=[%g %g] 순서 정상, Pe도 같은 창; step4 창 [%g %g]x[%g %g]의 부분집합인가: %s (넓이 %g vs %g deg^2)\n', ...
        pf(ok), P.winLat, P.winLon, R4.P.winLat, R4.P.winLon, pick(sub, '예', '아니오(서·남쪽 0.5° 더 나감)'), area4b, area4);
catch e, fprintf('CHECK 2: ERROR - %s\n', e.message); end

%% CHECK 3: 궤도 통과 선정이 새 창을 쓰는가 — 2024년 위상 1 통과를 다시 만들어 결과 파일과 비교
try
    iy = find(R.years == 2024, 1);  ip = 1;
    D = struct('t0', datetime(R.years(iy), 6, 1, 'TimeZone', 'UTC'), 'nT', 122 * 48);
    passes = L.orbitPasses(D, P, ip);
    nAll = 0;  nIn = 0;  nEdge = 0;
    reachLat = P.h * tand(P.maxDeg) / 110.57;                       % 빔 도달 거리 [deg 위도]
    reachLon = P.h * tand(P.maxDeg) / (111.32 * cosd(mean(P.winLat)));
    for k = 1:numel(passes)
        G = passes{k};
        la = G.Pg.latm + G.yq / G.Pg.ky;  lo = G.Pg.lonm + G.xq / G.Pg.kx;   % 직하점 위경도
        nAll = nAll + numel(la);
        nIn  = nIn + nnz(la >= P.winLat(1) - 0.02 & la <= P.winLat(2) + 0.02 & lo >= P.winLon(1) - 0.02 & lo <= P.winLon(2) + 0.02);
        nEdge = nEdge + nnz(la < P.winLat(1) + reachLat | lo < P.winLon(1) + reachLon);   % 서·남 가장자리(CHECK 6에서 씀)
    end
    ok = numel(passes) == R.nPass(iy, ip) && nIn == nAll;
    fprintf('CHECK 3: %s - 2024년 위상 1 통과 %d회 (결과 파일 nPass %d, step4 평균 %.0f회), 직하점 표본 %d/%d개가 창 안\n', ...
        pf(ok), numel(passes), R.nPass(iy, ip), mean(R4.nPass(iy, :)), nIn, nAll);
catch e, fprintf('CHECK 3: ERROR - %s\n', e.message);  nEdge = NaN;  nAll = NaN; end

%% CHECK 4: 방식 인덱스 ↔ methods.csv 행 ↔ run_log 숫자
try
    T = readtable(fullfile(d4b, 'methods.csv'), 'Encoding', 'UTF-8', 'TextType', 'string');
    ok = height(T) == numel(R.years) * numel(R.methods);
    for iy = 1:numel(R.years)
        for m = 1:numel(R.methods)
            row = T.year == R.years(iy) & T.method == R.methods(m);
            ok = ok && nnz(row) == 1 && abs(T.gainHeavy(row) - R.gain(iy, m, 1)) < 1e-9 ...
                && abs(T.heavyProf(row) - R.mTot(iy, m, 1)) < 1e-9 && abs(T.heavyCells(row) - R.mTot(iy, m, 3)) < 1e-9 ...
                && abs(T.ci95Low(row) - R.ci(iy, m, 1)) < 1e-9 && abs(T.ci95High(row) - R.ci(iy, m, 2)) < 1e-9 ...
                && abs(T.gainCells(row) - R.gain(iy, m, 3)) < 1e-9;
        end
    end
    iE = find(R.methods == "DP 나우캐스트(Early 큐)");  iF = find(R.methods == "DP 나우캐스트(Final 큐, 3단계)");
    iG = find(R.methods == "기존 방식(Early 큐)");       iO = find(R.methods == "DP 완벽 정보(상한)");
    ok = ok && isequal([iG iE iF iO], [2 3 4 5]) ...                                   % 코드의 iMain = 3, Final = 4, 기존 = 2
        && all(R.gain(:, iO, 1) >= max(R.gain(:, 1:4, 1), [], 2)) ...                 % 상한이 가장 큼
        && all(R.gain(:, iF, 1) >= R.gain(:, iE, 1));                                  % 정밀 큐 ≥ 거친 큐
    msg = '';
    lg = fileread(fullfile(root, 'out', 'run_log.csv'), 'Encoding', 'UTF-8');
    ln = regexp(lg, '[^\n]*dp_step4b_upstream[^\n]*', 'match');
    if ~isempty(ln)
        v = str2double(regexp(ln{end}, '\d+\.\d+', 'match'));                        % Early 3개, Final 3개, 기존 3개
        want = [R.gain(:, iE, 1); R.gain(:, iF, 1); R.gain(:, iG, 1)]';
        okLog = numel(v) >= 9 && all(abs(v(1:9) - want) < 0.006);
        ok = ok && okLog;
        msg = sprintf('; run_log 숫자 9개 일치: %s', pick(okLog, '예', '아니오'));
    end
    fprintf('CHECK 4: %s - csv %d행이 results.mat과 일치, 열 순서 [기존 Early Final 상한] = [%d %d %d %d]%s (Early 큐 DP %.2f/%.2f/%.2f배)\n', ...
        pf(ok), height(T), iG, iE, iF, iO, msg, R.gain(:, iE, 1));
catch e, fprintf('CHECK 4: ERROR - %s\n', e.message); end

%% CHECK 5: 부트스트랩 씨앗 — 저장된 ci가 '300+연도'로 재현되는가, step4 규칙(씨앗 7 공유)이면 얼마나 달라지나
try
    nY = numel(R.years);  nM = numel(R.methods);  nDay = size(R.dayH, 2);
    ciRe = zeros(nY, nM, 2);  ci7 = zeros(nY, nM, 2);
    rsB = RandStream('mt19937ar', 'Seed', 7);                         % step4의 날짜 부트스트랩 규칙
    for iy = 1:nY
        rs = RandStream('mt19937ar', 'Seed', 300 + R.years(iy));     % step4b의 규칙
        X = squeeze(R.dayH(iy, :, :));
        bs = zeros(2000, nM);  b7 = zeros(2000, nM);
        for b = 1:2000
            s = sum(X(randi(rs, nDay, nDay, 1), :), 1);   bs(b, :) = s / s(1);
            s = sum(X(randi(rsB, nDay, nDay, 1), :), 1);  b7(b, :) = s / s(1);
        end
        ciRe(iy, :, :) = reshape(prctile(bs, [2.5 97.5])', [1 nM 2]);
        ci7(iy, :, :)  = reshape(prctile(b7, [2.5 97.5])', [1 nM 2]);
    end
    dRe = max(abs(ciRe(:) - R.ci(:)));  d7 = max(abs(ci7(:) - R.ci(:)));
    okDay = nDay == 122 && nDay == days(datetime(2024, 10, 1) - datetime(2024, 6, 1));
    ok = dRe < 1e-9 && okDay;
    fprintf('CHECK 5: %s - 씨앗 300+연도로 저장된 CI 재현(최대 차 %.1e, nDay=%d); step4 규칙(씨앗 7 공유)으로 바꾸면 CI 끝값 최대 %.3f 변동 = 몬테카를로 잡음 (결과 해석 불변)\n', ...
        pf(ok), dRe, nDay, d7);
catch e, fprintf('CHECK 5: ERROR - %s\n', e.message); end

%% CHECK 6: 관측창 서·남 경계와 자료 상자 경계의 여유 — 빔 도달 거리보다 작으면 지적이 맞음(FAIL, 보수적 과소)
try
    latR = [];  lonR = [];  srcTxt = '';
    cache = fullfile(getenv('USERPROFILE'), 'Desktop', 'K-RainEye_IMERG', sprintf('cache_%d_JJAS.mat', 2024));
    if exist(cache, 'file')
        S = load(cache, 'lat', 'lon');                                 % v7.3 부분 읽기 (Pr은 안 읽음)
        latR = [min(S.lat) max(S.lat)] + [-0.05 0.05];  lonR = [min(S.lon) max(S.lon)] + [-0.05 0.05];   % 칸 중심 → 칸 끝
        srcTxt = 'cache_2024_JJAS.mat';
    else
        hd = fileread(fullfile(root, 'imerg', 'harmony_download.py'), 'Encoding', 'UTF-8');
        b = str2double(regexp(hd, 'BBox\((\d+),\s*(\d+),\s*(\d+),\s*(\d+)\)', 'tokens', 'once'));
        if numel(b) == 4, lonR = [b(1) b(3)];  latR = [b(2) b(4)];  srcTxt = 'harmony_download.py BOX'; end
    end
    if isempty(latR), error('자료 범위를 알 수 없음 (캐시도 BOX도 없음)'); end
    reachLat = P.h * tand(P.maxDeg) / 110.57;
    reachLon = P.h * tand(P.maxDeg) / (111.32 * cosd(mean(P.winLat)));
    margin = [P.winLat(1) - latR(1), latR(2) - P.winLat(2), P.winLon(1) - lonR(1), lonR(2) - P.winLon(2)];   % 남 북 서 동
    need   = [reachLat, reachLat, reachLon, reachLon];
    short  = margin < need - 1e-9;
    sides  = {'남', '북', '서', '동'};
    ok = ~any(short);                                                  % 여유가 충분하면 PASS, 모자라면 FAIL(= 지적이 맞음)
    m4 = [R4.P.winLat(1) - latR(1), R4.P.winLon(1) - lonR(1)];
    fprintf('CHECK 6: %s - 자료 상자(%s) 위도 %g~%g 경도 %g~%g; 창까지 여유 남/북/서/동 = %g/%g/%g/%g°, 빔 도달 약 %.2f°(위도)·%.2f°(경도) → 모자란 쪽: %s; 직하점 표본 중 서·남 가장자리(도달 거리 안) 비율 %.1f%% (위상 1); step4 창 여유 남 %g°·서 %g°도 모자람. 영향은 DP·상한을 줄이는 쪽(보수적)\n', ...
        pf(ok), srcTxt, latR, lonR, margin, reachLat, reachLon, pick(any(short), strjoin(sides(short), ','), '없음'), 100 * nEdge / nAll, m4);
catch e, fprintf('CHECK 6: ERROR - %s\n', e.message); end

%% CHECK 7: 글자로 박힌 상수('위상 8개', '28~38N 119~127E')가 지금의 P와 일치하는가
try
    src = fileread(fullfile(root, 'dp', 'dp_step4b_upstream.m'), 'Encoding', 'UTF-8');
    s1 = sprintf('%g~%gN %g~%gE', P.winLat, P.winLon);
    s2 = sprintf('위상 %d개', P.nPhase);
    ok = contains(src, s1) && contains(src, s2) && contains(src, 'P.winLat = [28 38];  P.winLon = [119 127];');
    fprintf('CHECK 7: %s - 코드 본문에 ''%s''와 ''%s''가 글자로 있고 지금 P와 일치 (P를 바꾸면 run_log·화면 문구가 어긋남 → sprintf로 바꾸길 권함)\n', pf(ok), s1, s2);
catch e, fprintf('CHECK 7: ERROR - %s\n', e.message); end

%% INFO: 날짜별 합(dayH)과 위상별 합(tot)이 맞물리는가 (부트스트랩의 분자·분모가 같은 수를 센다)
try
    dSum = max(abs(squeeze(sum(R.dayH, 2)) - squeeze(sum(R.tot(:, :, :, 1), 2))), [], 'all');
    fprintf('INFO   : dayH 날짜 합 vs tot 위상 합 최대 차 %.1e (0이어야 함); 통과/시즌 %.0f/%.0f/%.0f회; Early÷Final 배수 비 %.2f/%.2f/%.2f\n', ...
        dSum, mean(R.nPass, 2), R.gain(:, 3, 1) ./ R.gain(:, 4, 1));
catch e, fprintf('INFO   : ERROR - %s\n', e.message); end

function s = pf(ok)
if ok, s = 'PASS'; else, s = 'FAIL'; end
end
function s = pick(c, a, b)
if c, s = a; else, s = b; end
end
