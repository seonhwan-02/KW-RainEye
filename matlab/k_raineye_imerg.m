%% K-RainEye 실제 강수자료 분석 (GPM IMERG Final V07, 2023 장마 시즌 6~9월)
% 모의 1(큐잉 표적지향 이득)을 합성 강수 세포 대신 실제 IMERG 30분 강수장으로 다시 계산한다.
% 실행하면 out/imerg_gain_2023 폴더에 결과가 모두 저장된다.
%   summary.txt          사람이 읽는 요약 (가정·표·비교)
%   key_imerg_gain.json  핵심 숫자 (보고서·제안서 자동 반영용)
%   modes.csv/.xlsx      관측창 × 관측 방식별 시즌 합계와 배수
%   passes.csv/.xlsx     통과 하나하나의 결과
%   results.mat          모든 배열과 매개변수
%   run_info.txt         실행 시각, MATLAB 버전, 자료 출처, 매개변수
%   fig*.png             그림
% 그리고 out/run_log.csv에 실행 기록이 한 줄씩 쌓인다.
%
% 가정 (제안서에 그대로 밝힐 것)
%   - 진실(truth): IMERG 30분 강수강도. 10 km 칸 평균이라 우량계의 국지 최대보다 낮게 나온다.
%   - 큐(cue): 천리안2A·KIM이 큐 시각에 본 장면을 같은 시각의 IMERG 장면으로 대신한다.
%     탐지확률 0.72(cold 0.9·warm 0.6를 6:4로 섞은 값), 위치오차 3 km. 실제 천리안 강우 산출물보다 낙관적일 수 있다.
%   - 표적: 큐 장면의 국지 최대점(3×3 이웃) 중 1 mm/h 이상. 10 mm/h 이상이면 호우급(우선순위 높음).
%   - 나우캐스트: 큐 시각 직전 두 장면(30분 간격)의 상호상관으로 구한 영역 이동 벡터로 표적을 옮긴다.
%     속도오차 2 m/s. 위치고정(persist)은 옮기지 않는다.
%   - 궤도·지향·스케줄러는 k_raineye_analysis.m과 같다 (550 km, 경사 45°, J2 원궤도, 롤만 사용).
%   - 프로파일 = 빔이 풋프린트 길이(1.5 s)만큼 지나간 한 번의 관측. 호우 프로파일 = 그 칸이 10 mm/h 이상.

clear; close all;
here = fileparts(mfilename('fullpath'));
if isempty(here), here = pwd; end
runName = 'imerg_gain_2023';
outDir  = fullfile(here, 'out', runName);
if ~exist(outDir, 'dir'), mkdir(outDir); end
set(groot, 'defaultAxesFontName', 'Malgun Gothic', 'defaultTextFontName', 'Malgun Gothic');
tRun = datetime('now');
tic;

%% 1. 자료 읽기 (처음 한 번만 nc4 5,856개를 읽어 캐시 .mat를 만든다)
D.root   = fullfile(getenv('USERPROFILE'), 'Desktop', 'K-RainEye_IMERG');
D.months = {'202306', '202307', '202308', '202309'};
D.t0     = datetime(2023, 6, 1, 'TimeZone', 'UTC');
D.cache  = fullfile(D.root, 'cache_2023_JJAS.mat');
[Pr, lat, lon, tSlot] = loadImerg(D);
nT = size(Pr, 3);
tS = seconds(tSlot - D.t0);                      % 각 30분 칸의 시작 [s]
assert(tS(1) == 0 && all(diff(tS) == 1800), '30분 간격이 끊긴 구간이 있다');
fprintf('IMERG %d칸 × %d칸 × %d시각 읽음 (%.0f s)\n', numel(lat), numel(lon), nT, toc);

%% 2. 매개변수
C = struct('Re', 6378.137, 'mu', 398600.4418, 'J2', 1.08262668e-3, 'we', 7.2921159e-5);
O.h      = 550;
O.inc    = 45;
O.days   = nT * 1800 / 86400;                    % 122일
O.dt     = 10;
O.nPhase = 8;

W = struct('name', {"서해~동해 전체", "상류(기존 관측창)"}, ...
           'lat',  {[28.5 39.5], [28 38]}, 'lon', {[119.5 131.5], [119 127]});
nW = numel(W);

R0 = struct('h', O.h, 'fpHalf', 5.4, 'reachQ', 29, 'reachU', 97, 'profDt', 1.5, 'prePoint', 120);
Rs = {setfield(setfield(setfield(R0, 'slewRate', 1.5), 'settle', 4), 'dwell', 3), ...   % 1: 현실 목표안
      setfield(setfield(setfield(R0, 'slewRate', 1.0), 'settle', 8), 'dwell', 6)};      % 2: 이전 기준안
RsName = ["정착 4 s·응시 3 s·1.5°/s", "정착 8 s·응시 6 s·1°/s"];

Q.thrRain  = 1;                                  % 강수 [mm/h]
Q.thrHeavy = 10;                                 % 호우급 [mm/h]
Q.pDet     = 0.72;
Q.posSd    = 3;                                  % [km]
Q.velSd    = 2 / 1000;                           % [km/s]
Q.maxShift = 6;                                  % 이동 벡터 탐색 범위 [칸/30분] (약 33 m/s)
Q.reachQ   = R0.reachQ;

mk = @(name, kind, reach, L, ho, rk) struct('name', string(name), 'kind', string(kind), ...
    'reach', reach, 'L', L, 'heavyOnly', ho, 'rk', rk);
modes = mk("천저 고정", "nadir", 0, 0, false, 1);
modes(end+1) = mk("완벽 정보(상한, ±3°)", "oracle", R0.reachQ, 0, false, 1);
Ls = [10 15 20 30];
for L = Ls
    modes(end+1) = mk(sprintf("큐잉 ±3° 위치고정 %d분", L), "persist", R0.reachQ, L, false, 1); %#ok<SAGROW>
    modes(end+1) = mk(sprintf("큐잉 ±3° 나우캐스트 %d분", L), "nowcast", R0.reachQ, L, false, 1); %#ok<SAGROW>
end
modes(end+1) = mk("나우캐스트 15분·호우급만", "nowcast", R0.reachQ, 15, true, 1);
modes(end+1) = mk("나우캐스트 15분·±10°", "nowcast", R0.reachU, 15, false, 1);
modes(end+1) = mk("이전 기준안 나우캐스트 30분", "nowcast", R0.reachQ, 30, false, 2);
nM = numel(modes);
mName = string({modes.name});
metName = ["강수 프로파일", "호우 프로파일", "호우 정량 프로파일", "호우 세포", "표적 수", "유효 관측"];

%% 3. 이동 벡터 (나우캐스트용, 처음 한 번만 계산해 캐시)
mfile = fullfile(D.root, 'motion_2023_JJAS.mat');
kmLat = 110.57 * 0.1;
kmLon = 111.32 * 0.1 * cosd(mean(lat));
if exist(mfile, 'file')
    S = load(mfile);  motion = S.motion;
else
    motion = nan(nT, 2);
    for k = 2:nT
        motion(k, :) = estMotion(Pr(:, :, k - 1), Pr(:, :, k), Q.maxShift, kmLat, kmLon);
    end
    save(mfile, 'motion', 'kmLat', 'kmLon');
end
motion(isnan(motion)) = 0;                        % 비가 거의 없는 장면은 이동 0(위치고정과 같음)
spd = vecnorm(motion, 2, 2) * 1000;
dirTo = mod(atan2d(motion(:, 1), motion(:, 2)), 360);   % 이동해 가는 방위 (북 0°, 동 90°)
fprintf('이동 벡터 준비 (%.0f s): 속도 중앙값 %.1f m/s\n', toc, median(spd(spd > 0)));

%% 4. 궤도 전파와 통과별 평가
jd0   = juliandate(D.t0);
gmst0 = deg2rad(mod(280.46061837 + 360.98564736629 * (jd0 - 2451545), 360));
phs   = RandStream('mt19937ar', 'Seed', 7);
phases = [rand(phs, O.nPhase, 1), rand(phs, O.nPhase, 1)] * 2 * pi;

res    = zeros(nW, O.nPhase, nM, 6);
nPass  = zeros(nW, O.nPhase);
ubHeavy = zeros(nW, O.nPhase);                    % 이론 상한: 통과 중 ±3° 안에 호우 칸이 있었던 표본 수
pRows  = {};
iNad = 1;  iOr = 2;
iN10 = find(mName == "큐잉 ±3° 나우캐스트 10분");
iN15 = find(mName == "큐잉 ±3° 나우캐스트 15분");
for ip = 1:O.nPhase
    [t, la, lo] = propagate(C, O.h, O.inc, phases(ip, 1), phases(ip, 2), gmst0, O.days, O.dt);
    for iw = 1:nW
        inWin = la >= W(iw).lat(1) & la <= W(iw).lat(2) & lo >= W(iw).lon(1) & lo <= W(iw).lon(2);
        dIn = diff([false; inWin; false]);
        st = find(dIn == 1);  en = find(dIn == -1) - 1;
        for kp = 1:numel(st)
            G = passSetup(t, la, lo, st(kp), en(kp), R0.profDt, nT);
            if isempty(G), continue; end
            nPass(iw, ip) = nPass(iw, ip) + 1;
            ub = upperBound(G, Pr, lat, lon, Q);
            ubHeavy(iw, ip) = ubHeavy(iw, ip) + ub;
            mrow = zeros(nM, 6);
            for im = 1:nM
                rs = RandStream('mt19937ar', 'Seed', ip * 1e6 + iw * 1e5 + kp * 100 + im);
                mrow(im, :) = evalPass(G, modes(im), Rs{modes(im).rk}, Q, Pr, lat, lon, motion, rs);
            end
            res(iw, ip, :, :) = res(iw, ip, :, :) + reshape(mrow, [1 1 nM 6]);
            pRows(end + 1, :) = {char(W(iw).name), ip, kp, D.t0 + seconds(G.ts), G.tq(end) - G.tq(1), ...
                numel(G.tq), ub, mrow(iNad, 2), mrow(iOr, 2), mrow(iN10, 2), mrow(iN15, 2), ...
                mrow(iNad, 4), mrow(iN15, 4), mrow(iN15, 5)}; %#ok<SAGROW>
        end
    end
    fprintf('위상 %d/%d 완료 (%.0f s)\n', ip, O.nPhase, toc);
end

%% 5. 집계
mRes  = reshape(mean(res, 2), [nW, nM, 6]);       % 위상 평균 시즌 합계
gain  = mRes ./ mRes(:, iNad, :);                 % 천저 고정 대비 배수
mPass = mean(nPass, 2);
mUb   = mean(ubHeavy, 2);
passT = cell2table(pRows, 'VariableNames', {'window', 'phase', 'pass', 'startUTC', 'durationS', ...
    'samples', 'heavyReachableSamples', 'heavyProfNadir', 'heavyProfOracle', 'heavyProfNowcast10', ...
    'heavyProfNowcast15', 'heavyCellsNadir', 'heavyCellsNowcast15', 'targetsNowcast15'});
fracReach = arrayfun(@(iw) mean(passT.heavyReachableSamples(strcmp(passT.window, W(iw).name)) > 0), 1:nW);
gainSpread = zeros(nW, nM, 2);                    % 위상별 호우 프로파일 배수의 최소·최대
for iw = 1:nW
    g = squeeze(res(iw, :, :, 2)) ./ squeeze(res(iw, :, iNad, 2))';
    gainSpread(iw, :, :) = reshape([min(g, [], 1); max(g, [], 1)]', [1 nM 2]);
end

%% 6. 이전 합성 세포 모의와 비교할 값 (out/results.mat, out/key_sensitivity.json이 있으면)
syn = struct('L', [], 'heavyGain', [], 'planL', [], 'planHeavy', []);
fRes = fullfile(here, 'out', 'results.mat');
if exist(fRes, 'file')
    S = load(fRes, 'gain', 'mName', 'Q');
    for L = S.Q.latency
        j = find(S.mName == sprintf("큐잉 ±3° 나우캐스트 %d분", L));
        if ~isempty(j), syn.L(end+1) = L; syn.heavyGain(end+1) = S.gain(1, j, 2); end
    end
end
fSen = fullfile(here, 'out', 'key_sensitivity.json');
if exist(fSen, 'file')
    ks = jsondecode(fileread(fSen));
    for L = [10 15]
        j = find(strcmp(ks.label, sprintf('현실 목표안: 정착 4 s·응시 3 s·1.5°/s·%d분·전체', L)));
        if ~isempty(j), syn.planL(end+1) = L; syn.planHeavy(end+1) = ks.gainHeavy(j); end
    end
end

%% 7. 그림
cols = [0.06 0.49 0.42; 0.76 0.25 0.18];
% 그림 A: 큐 지연에 따른 호우 프로파일 배수
fA = figure('Visible', 'off', 'Position', [100 100 820 450]);
ax = axes(fA); hold(ax, 'on'); grid(ax, 'on');
for iw = 1:nW
    iNL = arrayfun(@(L) find(mName == sprintf("큐잉 ±3° 나우캐스트 %d분", L)), Ls);
    iPL = arrayfun(@(L) find(mName == sprintf("큐잉 ±3° 위치고정 %d분", L)), Ls);
    plot(ax, Ls, squeeze(gain(iw, iNL, 2)), '-o', 'Color', cols(iw, :), 'LineWidth', 1.8, ...
        'DisplayName', "실측 · 나우캐스트 · " + W(iw).name);
    plot(ax, Ls, squeeze(gain(iw, iPL, 2)), '--s', 'Color', cols(iw, :), 'LineWidth', 1.1, ...
        'DisplayName', "실측 · 위치고정 · " + W(iw).name);
    yline(ax, gain(iw, iOr, 2), ':', "완벽 정보 상한 (" + W(iw).name + ")", 'Color', cols(iw, :), ...
        'LineWidth', 1.1, 'HandleVisibility', 'off', 'LabelHorizontalAlignment', 'left');
end
if ~isempty(syn.planL)
    plot(ax, syn.planL, syn.planHeavy, 'kd', 'MarkerFaceColor', [0.85 0.85 0.85], 'MarkerSize', 8, ...
        'DisplayName', '합성 세포 모의 (현실 목표안)');
end
yline(ax, 1, '-', '천저 고정', 'Color', [0.5 0.5 0.5], 'HandleVisibility', 'off');
xlabel(ax, '큐 지연 [분]'); ylabel(ax, '호우 프로파일 수, 천저 고정 대비 배수');
title(ax, '실제 2023 장마 강수장에서 큐 지연에 따른 표적지향 이득 (경사 45°, 현실 목표안)');
legend(ax, 'Location', 'eastoutside');
exportgraphics(fA, fullfile(outDir, 'figA_latency_gain_real.png'), 'Resolution', 150);

% 그림 B: 주요 방식별 배수 (지표 3종)
sel = [iOr, iN10, iN15, find(mName == "나우캐스트 15분·호우급만"), find(mName == "나우캐스트 15분·±10°"), ...
       find(mName == "이전 기준안 나우캐스트 30분")];
fB = figure('Visible', 'off', 'Position', [100 100 1150 470]);
tl = tiledlayout(fB, 1, nW, 'TileSpacing', 'compact');
for iw = 1:nW
    ax = nexttile(tl);
    Y = squeeze(gain(iw, sel, [1 2 4]));
    b = bar(ax, categorical(mName(sel), mName(sel)), Y, 'grouped');
    yline(ax, 1, '-', 'Color', [0.4 0.4 0.4], 'HandleVisibility', 'off');
    grid(ax, 'on'); ylabel(ax, '천저 고정 대비 배수');
    title(ax, sprintf('%s (시즌 통과 %.0f회)', W(iw).name, mPass(iw)));
    for k = 1:numel(b)
        text(ax, b(k).XEndPoints, b(k).YEndPoints, compose('%.2f', b(k).YData), ...
            'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', 'FontSize', 7);
    end
    if iw == nW, legend(ax, ["강수 프로파일", "호우 프로파일", "호우 세포"], 'Location', 'northeast'); end
end
title(tl, '실제 IMERG 강수장 기준 관측 방식별 이득 (2023년 6~9월, 위상 8개 평균)');
exportgraphics(fB, fullfile(outDir, 'figB_mode_gain_real.png'), 'Resolution', 150);

% 그림 C: 예시 통과 (전체 관측창, 나우캐스트 15분에서 천저 대비 호우 프로파일이 가장 많이 늘어난 통과)
pw = passT(strcmp(passT.window, W(1).name), :);
[~, ib] = max(pw.heavyProfNowcast15 - pw.heavyProfNadir);
ipE = pw.phase(ib);  kpE = pw.pass(ib);
[t, la, lo] = propagate(C, O.h, O.inc, phases(ipE, 1), phases(ipE, 2), gmst0, O.days, O.dt);
inWin = la >= W(1).lat(1) & la <= W(1).lat(2) & lo >= W(1).lon(1) & lo <= W(1).lon(2);
dIn = diff([false; inWin; false]);  st = find(dIn == 1);  en = find(dIn == -1) - 1;
G = passSetup(t, la, lo, st(kpE), en(kpE), R0.profDt, nT);
rs = RandStream('mt19937ar', 'Seed', ipE * 1e6 + 1e5 + kpE * 100 + iN15);
[mE, trN] = evalPass(G, modes(iN15), Rs{1}, Q, Pr, lat, lon, motion, rs);
[mD, trD] = evalPass(G, modes(iNad), Rs{1}, Q, Pr, lat, lon, motion, rs);
kE = G.kq(round(end / 2));
fC = figure('Visible', 'off', 'Position', [100 100 900 700]);
ax = axes(fC); hold(ax, 'on');
imagesc(ax, lon, lat, Pr(:, :, kE), 'AlphaData', Pr(:, :, kE) > 0.1);
axis(ax, 'xy'); axis(ax, 'image');
colormap(ax, turbo(256)); clim(ax, [0 30]);
cb = colorbar(ax); cb.Label.String = '강수강도 [mm/h]';
plot(ax, trD.blon, trD.blat, 'k-', 'LineWidth', 1, 'DisplayName', '천저 궤적');
v = trN.valid & ~isnan(trN.val);
scatter(ax, trN.blon(v), trN.blat(v), 14, 'w', 'filled', 'MarkerEdgeColor', 'k', 'DisplayName', '표적지향 빔 위치');
hh = v & trN.val >= Q.thrHeavy;
scatter(ax, trN.blon(hh), trN.blat(hh), 40, 'm', 'LineWidth', 1.5, 'DisplayName', '호우 칸 관측');
xlim(ax, [min(trD.blon) - 1.5, max(trD.blon) + 1.5]); ylim(ax, [min(trD.blat) - 0.5, max(trD.blat) + 0.5]);
xlabel(ax, '경도 [°E]'); ylabel(ax, '위도 [°N]');
tE = D.t0 + seconds(G.ts);  tE.TimeZone = 'Asia/Seoul';
title(ax, sprintf('예시 통과 %s KST: 호우 프로파일 천저 %d개 → 표적지향 %d개', ...
    char(tE, 'yyyy-MM-dd HH:mm'), mD(2), mE(2)));
legend(ax, 'Location', 'southoutside', 'Orientation', 'horizontal');
exportgraphics(fC, fullfile(outDir, 'figC_example_pass.png'), 'Resolution', 150);

%% 7-b. 진단: 겨냥한 곳에 실제로 비가 있었나 (위상 1, 전체 관측창)
% 기하(부호·시각) 오류가 없다면 완벽 정보 방식의 응시 표본은 대부분 강수 칸이어야 하고,
% 빔을 궤적 반대편으로 뒤집은 '거울' 위치보다 확실히 높아야 한다.
dgModes = [iOr, find(mName == "큐잉 ±3° 위치고정 15분"), iN15];
dg  = zeros(numel(dgModes), 7);   % [표적, 응시표본, 응시 강수, 응시 호우, 거울 강수, 거울 호우, 유효표본]
dgN = zeros(numel(dgModes), 1);
nad = zeros(1, 3);                % [표본, 강수, 호우]
[t, la, lo] = propagate(C, O.h, O.inc, phases(1, 1), phases(1, 2), gmst0, O.days, O.dt);
inWin = la >= W(1).lat(1) & la <= W(1).lat(2) & lo >= W(1).lon(1) & lo <= W(1).lon(2);
dIn = diff([false; inWin; false]);  st = find(dIn == 1);  en = find(dIn == -1) - 1;
for kp = 1:numel(st)
    G = passSetup(t, la, lo, st(kp), en(kp), R0.profDt, nT);
    if isempty(G), continue; end
    [~, trD] = evalPass(G, modes(iNad), Rs{1}, Q, Pr, lat, lon, motion, RandStream('mt19937ar', 'Seed', 1));
    nad = nad + [numel(G.tq), sum(trD.val >= Q.thrRain), sum(trD.val >= Q.thrHeavy)];
    for a = 1:numel(dgModes)
        im = dgModes(a);  Rm = Rs{modes(im).rk};
        rs = RandStream('mt19937ar', 'Seed', 1 * 1e6 + 1 * 1e5 + kp * 100 + im);   % 본 계산과 같은 난수
        [~, tr] = evalPass(G, modes(im), Rm, Q, Pr, lat, lon, motion, rs);
        inDw = false(size(G.tq));
        for k = 1:size(tr.acc, 1)
            inDw = inDw | abs(G.tq - tr.acc(k, 1)) <= Rm.dwell / 2;
        end
        inDw = inDw & tr.valid;
        mx = G.xq - tr.cb .* G.nq(:, 1);  my = G.yq - tr.cb .* G.nq(:, 2);
        valM = sampleField(Pr, lat, lon, G.Pg.latm + my / G.Pg.ky, G.Pg.lonm + mx / G.Pg.kx, G.kq);
        dg(a, :) = dg(a, :) + [size(tr.acc, 1), sum(inDw), sum(tr.val(inDw) >= Q.thrRain), ...
            sum(tr.val(inDw) >= Q.thrHeavy), sum(valM(inDw) >= Q.thrRain), sum(valM(inDw) >= Q.thrHeavy), sum(tr.valid)];
        dgN(a) = dgN(a) + numel(G.tq);
    end
end
fid = fopen(fullfile(outDir, 'diag_targets.txt'), 'w', 'n', 'UTF-8');
fprintf(fid, '진단: 응시 표본에 실제로 비가 있었나 (위상 1, %s, 통과 %d회)\n', W(1).name, numel(st));
fprintf(fid, '  천저 고정: 전체 표본 중 강수 %.1f%%, 호우 %.2f%%\n', 100 * nad(2) / nad(1), 100 * nad(3) / nad(1));
fprintf(fid, '  %-28s %6s %8s %10s %10s %10s %10s %10s\n', '방식', '표적', '응시표본', '응시강수%', '응시호우%', '거울강수%', '거울호우%', '유효표본%');
for a = 1:numel(dgModes)
    fprintf(fid, '  %-28s %6d %8d %10.1f %10.2f %10.1f %10.2f %10.1f\n', mName(dgModes(a)), dg(a, 1), dg(a, 2), ...
        100 * dg(a, 3) / dg(a, 2), 100 * dg(a, 4) / dg(a, 2), 100 * dg(a, 5) / dg(a, 2), 100 * dg(a, 6) / dg(a, 2), ...
        100 * dg(a, 7) / dgN(a));
end
fclose(fid);
diagT = struct('modes', mName(dgModes), 'targets', dg(:, 1)', 'dwellSamples', dg(:, 2)', ...
    'dwellRainPct', 100 * dg(:, 3)' ./ dg(:, 2)', 'dwellHeavyPct', 100 * dg(:, 4)' ./ dg(:, 2)', ...
    'mirrorRainPct', 100 * dg(:, 5)' ./ dg(:, 2)', 'mirrorHeavyPct', 100 * dg(:, 6)' ./ dg(:, 2)', ...
    'validPct', 100 * dg(:, 7)' ./ dgN', 'nadirRainPct', 100 * nad(2) / nad(1), 'nadirHeavyPct', 100 * nad(3) / nad(1));
fprintf('진단 완료 (%.0f s)\n', toc);

%% 8. 저장
fid = fopen(fullfile(outDir, 'summary.txt'), 'w', 'n', 'UTF-8');
pr = @(varargin) fprintf(fid, varargin{:});
pr('K-RainEye 실제 강수자료 표적지향 이득 (%s 실행)\n', string(tRun));
pr('자료: GPM IMERG Final V07 30분, 2023-06-01 ~ 2023-09-30, %d시각, 북위 %.2f~%.2f° · 동경 %.2f~%.2f°\n', ...
    nT, lat(1), lat(end), lon(1), lon(end));
pr('궤도: %d km, 경사 %d°, %.0f일, 초기 위상 %d개 평균 (괄호는 위상별 최소~최대)\n\n', O.h, O.inc, O.days, O.nPhase);
for iw = 1:nW
    pr('[%s] 북위 %g~%g° · 동경 %g~%g°\n', W(iw).name, W(iw).lat, W(iw).lon);
    pr('  시즌 통과 %.0f회 (%d~%d), 통과 중 ±3° 안에 호우 칸이 있었던 통과 %.0f%%\n', mPass(iw), ...
        min(nPass(iw, :)), max(nPass(iw, :)), 100 * fracReach(iw));
    pr('  이론 상한(±3° 안 호우 칸을 매 순간 볼 수 있다면) 호우 표본 %.0f개 = 천저의 %.2f배\n', ...
        mUb(iw), mUb(iw) / mRes(iw, iNad, 2));
    pr('  %-34s %9s %9s %11s %8s %8s | %s\n', '방식', '강수프로파일', '호우프로파일', '호우정량', '호우세포', '표적수', ...
        '배수(강수/호우/세포) [호우 위상범위]');
    for im = 1:nM
        pr('  %-34s %9.0f %9.0f %11.0f %8.1f %8.0f | %.2f / %.2f / %.2f [%.2f~%.2f]\n', mName(im), ...
            mRes(iw, im, 1), mRes(iw, im, 2), mRes(iw, im, 3), mRes(iw, im, 4), mRes(iw, im, 5), ...
            gain(iw, im, 1), gain(iw, im, 2), gain(iw, im, 4), gainSpread(iw, im, 1), gainSpread(iw, im, 2));
    end
    pr('\n');
end
pr('[합성 세포 모의와 비교] (호우급 배수)\n');
for k = 1:numel(syn.planL)
    j = find(mName == sprintf("큐잉 ±3° 나우캐스트 %d분", syn.planL(k)));
    pr('  현실 목표안 %d분: 합성 %.2f배 → 실측 %.2f배(전체 관측창) / %.2f배(상류 관측창)\n', ...
        syn.planL(k), syn.planHeavy(k), gain(1, j, 2), gain(2, j, 2));
end
pr('\n[나우캐스트 이동 벡터] 장면 %d개, 속도 중앙값 %.1f m/s (하위 25%% %.1f, 상위 25%% %.1f), 이동 방위 중앙값 %.0f°\n', ...
    nnz(spd > 0), median(spd(spd > 0)), prctile(spd(spd > 0), 25), prctile(spd(spd > 0), 75), median(dirTo(spd > 0)));
pr('\n[가정]\n');
pr('  진실: IMERG 30분 강수강도(10 km 칸 평균). 호우급 %g mm/h 이상, 강수 %g mm/h 이상\n', Q.thrHeavy, Q.thrRain);
pr('  큐: 같은 시각 IMERG 장면으로 대신, 탐지확률 %.2f, 위치오차 %g km, 속도오차 %g m/s\n', Q.pDet, Q.posSd, Q.velSd * 1000);
pr('  지향: %s(이전 기준안은 %s), 정량 관측 ±%g km(±3°), 풋프린트 %.1f km\n', RsName(1), RsName(2), R0.reachQ, 2 * R0.fpHalf);
pr('  호우 세포 = 같은 30분 장면에서 10 mm/h 이상 칸이 8방향으로 이어진 덩어리\n');
fclose(fid);

mt = table();
for iw = 1:nW
    for im = 1:nM
        mt = [mt; table(W(iw).name, mName(im), modes(im).kind, modes(im).L, string(RsName(modes(im).rk)), ...
            mRes(iw, im, 1), mRes(iw, im, 2), mRes(iw, im, 3), mRes(iw, im, 4), mRes(iw, im, 5), ...
            gain(iw, im, 1), gain(iw, im, 2), gain(iw, im, 3), gain(iw, im, 4), gainSpread(iw, im, 1), gainSpread(iw, im, 2), ...
            'VariableNames', {'window', 'mode', 'kind', 'cueLatencyMin', 'agility', 'rainProf', 'heavyProf', ...
            'heavyQuantProf', 'heavyCells', 'targets', 'gainRain', 'gainHeavy', 'gainHeavyQuant', 'gainCells', ...
            'gainHeavyMinPhase', 'gainHeavyMaxPhase'})]; %#ok<AGROW>
    end
end
writetable(mt, fullfile(outDir, 'modes.csv'), 'Encoding', 'UTF-8');
writetable(passT, fullfile(outDir, 'passes.csv'), 'Encoding', 'UTF-8');
try
    writetable(mt, fullfile(outDir, 'results.xlsx'), 'Sheet', 'modes');
    writetable(passT, fullfile(outDir, 'results.xlsx'), 'Sheet', 'passes');
catch ME
    warning('xlsx 저장 실패: %s', ME.message);
end

key = struct('run', runName, 'time', string(tRun), 'data', 'GPM IMERG Final V07 HH, 2023-06-01~09-30', ...
    'windows', [W.name], 'modes', mName, 'metrics', metName, 'passesPerSeason', mPass', ...
    'fracPassesHeavyReachable', fracReach, 'upperBoundHeavyGain', (mUb ./ mRes(:, iNad, 2))', ...
    'totals', mRes, 'gain', gain, 'gainHeavyPhaseMin', gainSpread(:, :, 1), 'gainHeavyPhaseMax', gainSpread(:, :, 2), ...
    'synthetic', syn, 'diag', diagT, 'motionMedianMs', median(spd(spd > 0)), 'params', struct('Q', Q, 'R', {Rs}, 'O', O));
fidj = fopen(fullfile(outDir, 'key_imerg_gain.json'), 'w', 'n', 'UTF-8');
fprintf(fidj, '%s', jsonencode(key, 'PrettyPrint', true));
fclose(fidj);

save(fullfile(outDir, 'results.mat'), 'W', 'modes', 'mName', 'metName', 'res', 'mRes', 'gain', 'gainSpread', ...
    'nPass', 'ubHeavy', 'passT', 'Q', 'Rs', 'RsName', 'O', 'syn', 'motion', 'phases');

fid = fopen(fullfile(outDir, 'run_info.txt'), 'w', 'n', 'UTF-8');
fprintf(fid, '실행: %s (소요 %.0f s)\n스크립트: %s\nMATLAB: %s\n', string(tRun), toc, mfilename('fullpath'), version);
fprintf(fid, '자료 폴더: %s (캐시 %s)\n', D.root, D.cache);
fprintf(fid, '매개변수 Q: %s\n', jsonencode(Q));
fprintf(fid, '현실 목표안 R: %s\n이전 기준안 R: %s\n', jsonencode(Rs{1}), jsonencode(Rs{2}));
fclose(fid);

logRun(fullfile(here, 'out', 'run_log.csv'), tRun, mfilename, outDir, ...
    sprintf('전체창 나우캐스트15분 호우 %.2f배, 상류창 %.2f배, 완벽정보 %.2f/%.2f배', ...
    gain(1, iN15, 2), gain(2, iN15, 2), gain(1, iOr, 2), gain(2, iOr, 2)));
fprintf('완료 (%.0f s): %s\n', toc, outDir);

%% ===== 로컬 함수 =====
function [Pr, lat, lon, tSlot] = loadImerg(D)
% 달별 폴더의 nc4를 모두 읽는다. 같은 시각이 두 번 받아졌으면 하나만 쓴다. 결과는 캐시로 저장한다.
if exist(D.cache, 'file')
    S = load(D.cache);
    if isequal(S.months, D.months)
        Pr = S.Pr; lat = S.lat; lon = S.lon; tSlot = S.tSlot; return;
    end
end
Pr = []; lat = []; lon = []; tSlot = NaT(0, 1, 'TimeZone', 'UTC');
for m = D.months
    d = dir(fullfile(D.root, m{1}, '*.nc4'));
    key = regexp({d.name}, '\.(\d{8})-S(\d{6})', 'tokens', 'once');
    key = cellfun(@(c) [c{1} c{2}], key, 'UniformOutput', false);
    [~, ord] = unique(key);
    d = d(ord);
    if isempty(lat)
        f1 = fullfile(d(1).folder, d(1).name);
        lat = double(ncread(f1, '/Grid/lat'));  lon = double(ncread(f1, '/Grid/lon'));
    end
    Pm = zeros(numel(lat), numel(lon), numel(d), 'single');
    tm = NaT(numel(d), 1, 'TimeZone', 'UTC');
    for k = 1:numel(d)
        f = fullfile(d(k).folder, d(k).name);
        Pm(:, :, k) = ncread(f, '/Grid/precipitation');
        tm(k) = datetime(1980, 1, 6, 'TimeZone', 'UTC') + seconds(double(ncread(f, '/Grid/time')));
    end
    Pr = cat(3, Pr, Pm);  tSlot = [tSlot; tm]; %#ok<AGROW>
end
Pr(isnan(Pr)) = 0;
months = D.months;
save(D.cache, 'Pr', 'lat', 'lon', 'tSlot', 'months', '-v7.3');
end

function v = estMotion(A, B, maxS, kmLat, kmLon)
% 두 장면(30분 간격)의 정규화 상호상관이 가장 큰 이동량 → 이동 벡터 [동, 북] [km/s]
A = log1p(double(A));  B = log1p(double(B));
if nnz(A > log1p(1)) < 30 || nnz(B > log1p(1)) < 30, v = [NaN NaN]; return; end
[n1, n2] = size(A);
Sc = -inf(2 * maxS + 1);
for di = -maxS:maxS
    for dj = -maxS:maxS
        ia = max(1, 1 - di):min(n1, n1 - di);
        ja = max(1, 1 - dj):min(n2, n2 - dj);
        a = A(ia, ja);  b = B(ia + di, ja + dj);
        Sc(di + maxS + 1, dj + maxS + 1) = sum(a .* b, 'all') / sqrt(sum(a.^2, 'all') * sum(b.^2, 'all') + eps);
    end
end
[~, m] = max(Sc(:));
[r, c] = ind2sub(size(Sc), m);
dr = 0; dc = 0;
if r > 1 && r < size(Sc, 1), dr = parab(Sc(r - 1, c), Sc(r, c), Sc(r + 1, c)); end
if c > 1 && c < size(Sc, 2), dc = parab(Sc(r, c - 1), Sc(r, c), Sc(r, c + 1)); end
di = r - maxS - 1 + dr;  dj = c - maxS - 1 + dc;
v = [dj * kmLon, di * kmLat] / 1800;
end

function d = parab(ym, y0, yp)
den = ym - 2 * y0 + yp;
if den >= 0, d = 0; else, d = 0.5 * (ym - yp) / den; end
end

function G = passSetup(t, la, lo, s, e, profDt, nT)
% 통과 하나: 스케줄러용 기하(10 s 표본)와 관측 표본(1.5 s 간격) 위치·진행 방향
k1 = max(s - 1, 1);  k2 = min(e + 1, numel(t));
G = [];
if e - s < 2, return; end
G.Pg = passGeometry(t(k1:k2), la(k1:k2), lo(k1:k2));
G.ts = t(s);
G.tq = (t(s):profDt:t(e))';
laq = interp1(t(k1:k2), la(k1:k2), G.tq);
loq = interp1(t(k1:k2), lo(k1:k2), G.tq);
G.xq = (loq - G.Pg.lonm) * G.Pg.kx;
G.yq = (laq - G.Pg.latm) * G.Pg.ky;
u = [gradient(G.xq), gradient(G.yq)];
u = u ./ vecnorm(u, 2, 2);
G.nq = [-u(:, 2), u(:, 1)];                      % passGeometry의 P.nrm과 같은 방향(궤적 왼쪽 +)
G.kq = min(max(floor(G.tq / 1800) + 1, 1), nT);
end

function [met, tr] = evalPass(G, md, R, Q, Pr, lat, lon, motion, rs)
% 한 통과에서 관측 방식 하나를 평가: [강수, 호우, 호우정량, 호우세포, 표적수, 유효표본]
if md.kind == "nadir"
    acc = zeros(0, 2);
else
    acc = planTargets(G, md, R, Q, Pr, lat, lon, motion, rs);
end
[cb, valid] = beamAt(acc, G.tq, R);
bx = G.xq + cb .* G.nq(:, 1);
by = G.yq + cb .* G.nq(:, 2);
blat = G.Pg.latm + by / G.Pg.ky;
blon = G.Pg.lonm + bx / G.Pg.kx;
[val, ii, jj] = sampleField(Pr, lat, lon, blat, blon, G.kq);
val(~valid) = NaN;
rain  = val >= Q.thrRain;
heavy = val >= Q.thrHeavy;
quant = heavy & abs(cb) <= Q.reachQ + 1e-6;
nCell = countCells(Pr, Q.thrHeavy, ii(heavy), jj(heavy), G.kq(heavy));
met = [sum(rain), sum(heavy), sum(quant), nCell, size(acc, 1), sum(valid)];
tr = struct('blat', blat, 'blon', blon, 'val', val, 'cb', cb, 'valid', valid, 'acc', acc);
end

function acc = planTargets(G, md, R, Q, Pr, lat, lon, motion, rs)
% 큐 장면에서 표적 후보(국지 최대점)를 뽑아 통과 시각으로 옮기고 스케줄러로 고른다
nT = size(Pr, 3);
if md.kind == "oracle"
    tCue = G.ts;
else
    tCue = G.ts - md.L * 60;
end
kc = min(max(floor(tCue / 1800) + 1, 2), nT);
F  = double(Pr(:, :, kc));
idx = find(localMax(F) & F >= Q.thrRain);
[ii, jj] = ind2sub(size(F), idx);
val = F(idx);
n = numel(idx);
ex = zeros(n, 1);  ey = zeros(n, 1);
v = motion(kc, :);
if md.kind ~= "oracle"
    keep = rand(rs, n, 1) < Q.pDet;
    ex = Q.posSd * randn(rs, n, 1);  ey = Q.posSd * randn(rs, n, 1);
    v = v + Q.velSd * randn(rs, 1, 2);
    ii = ii(keep); jj = jj(keep); val = val(keep); ex = ex(keep); ey = ey(keep);
end
if md.kind == "persist", v = [0 0]; end
P  = G.Pg;
x0 = (lon(jj) - P.lonm) * P.kx + ex;
y0 = (lat(ii) - P.latm) * P.ky + ey;
[tc, cc] = crossTimes(P, x0, y0, v(1) * ones(size(x0)), v(2) * ones(size(x0)), tCue);
pri  = 1 + double(val >= Q.thrHeavy);
cand = ~isnan(tc) & abs(cc) <= md.reach;
if md.heavyOnly, cand = cand & pri == 2; end
acc = schedule([tc(cand), cc(cand), pri(cand)], G.ts, R);
end

function ub = upperBound(G, Pr, lat, lon, Q)
% 이론 상한: 매 표본 시각에 ±3° 안 어딘가에 호우 칸이 있으면 1 (기동 제약 없음)
offs = -Q.reachQ:2:Q.reachQ;
bx = G.xq + G.nq(:, 1) * offs;
by = G.yq + G.nq(:, 2) * offs;
blat = G.Pg.latm + by / G.Pg.ky;
blon = G.Pg.lonm + bx / G.Pg.kx;
val = sampleField(Pr, lat, lon, blat, blon, repmat(G.kq, 1, numel(offs)));
ub = sum(any(val >= Q.thrHeavy, 2));
end

function [val, ii, jj] = sampleField(Pr, lat, lon, blat, blon, kq)
% 가장 가까운 0.1° 칸의 값 (자료 영역 밖이면 NaN)
[n1, n2, ~] = size(Pr);
ii = round((blat - lat(1)) / (lat(2) - lat(1))) + 1;
jj = round((blon - lon(1)) / (lon(2) - lon(1))) + 1;
in = ii >= 1 & ii <= n1 & jj >= 1 & jj <= n2 & ~isnan(ii) & ~isnan(jj);
val = nan(size(blat));
val(in) = Pr(sub2ind(size(Pr), ii(in), jj(in), kq(in)));
ii(~in) = 0;  jj(~in) = 0;
end

function n = countCells(Pr, thr, ii, jj, kq)
% 관측한 호우 칸들이 몇 개의 서로 다른 호우 세포(같은 장면의 연결 덩어리)에 속하는가
n = 0;
for k = unique(kq(:))'
    s = kq == k;
    Lb = labelMask(Pr(:, :, k) >= thr);
    lab = Lb(sub2ind(size(Lb), ii(s), jj(s)));
    n = n + numel(unique(lab(lab > 0)));
end
end

function L = labelMask(M)
% 8방향 연결 덩어리 번호 매기기 (Image Processing Toolbox 없이)
[n1, n2] = size(M);
L = zeros(n1, n2);
lab = 0;
for s = find(M)'
    if L(s) ~= 0, continue; end
    lab = lab + 1;  L(s) = lab;  stack = s;
    while ~isempty(stack)
        p = stack(end);  stack(end) = [];
        [i, j] = ind2sub([n1 n2], p);
        for di = -1:1
            for dj = -1:1
                a = i + di;  b = j + dj;
                if a >= 1 && a <= n1 && b >= 1 && b <= n2 && M(a, b) && L(a, b) == 0
                    L(a, b) = lab;  stack(end + 1) = a + (b - 1) * n1; %#ok<AGROW>
                end
            end
        end
    end
end
end

function M = localMax(F)
% 3×3 이웃에서 가장 큰 칸
Fp = -inf(size(F) + 2);
Fp(2:end - 1, 2:end - 1) = F;
M = true(size(F));
for di = -1:1
    for dj = -1:1
        if di == 0 && dj == 0, continue; end
        M = M & F >= Fp((2:end - 1) + di, (2:end - 1) + dj);
    end
end
end

function logRun(file, tRun, script, outDir, note)
% 실행 기록 한 줄 추가 (처음이면 엑셀에서 한글이 깨지지 않게 BOM과 머리글을 쓴다)
isNew = ~exist(file, 'file');
fid = fopen(file, 'a', 'n', 'UTF-8');
if isNew
    fwrite(fid, [239 187 191]);
    fprintf(fid, 'time,script,outDir,note\n');
end
fprintf(fid, '%s,%s,%s,"%s"\n', string(tRun, 'yyyy-MM-dd HH:mm:ss'), script, outDir, note);
fclose(fid);
end

% ---- 아래는 k_raineye_analysis.m과 같은 함수 ----
function [t, lat, lon] = propagate(C, h, incDeg, raan0, u0, gmst0, nDays, dt)
% 원궤도 J2 영년 섭동 전파 → 구형 지구 위·경도
a = C.Re + h;
n = sqrt(C.mu / a^3);
i = deg2rad(incDeg);
k = C.J2 * (C.Re / a)^2;
raanDot = -1.5 * n * k * cos(i);
uDot    = n * (1 + 1.5 * k * (4 * cos(i)^2 - 1));
t = (0:dt:nDays * 86400 - dt)';
raan = raan0 + raanDot * t;
u    = u0 + uDot * t;
x = cos(raan) .* cos(u) - sin(raan) .* sin(u) * cos(i);
y = sin(raan) .* cos(u) + cos(raan) .* sin(u) * cos(i);
z = sin(u) * sin(i);
th = gmst0 + C.we * t;
xe =  cos(th) .* x + sin(th) .* y;
ye = -sin(th) .* x + cos(th) .* y;
lat = asind(z);
lon = atan2d(ye, xe);
end

function P = passGeometry(t, lat, lon)
% 통과 하나를 국소 평면(km)으로 바꾸고 약 50초 단위 직선 구간으로 나눈다
P.latm = mean(lat);  P.lonm = mean(lon);
P.kx = 111.32 * cosd(P.latm);  P.ky = 110.57;
x = (lon - P.lonm) * P.kx;
y = (lat - P.latm) * P.ky;
n = numel(t);
idx = unique([1:5:n, n]);
m = numel(idx) - 1;
P.t1 = t(idx(1:m));  P.t2 = t(idx(2:m + 1));
p1 = [x(idx(1:m)), y(idx(1:m))];
p2 = [x(idx(2:m + 1)), y(idx(2:m + 1))];
Lseg = sqrt(sum((p2 - p1).^2, 2));
P.u   = (p2 - p1) ./ Lseg;
P.nrm = [-P.u(:, 2), P.u(:, 1)];
P.V   = Lseg ./ (P.t2 - P.t1);
P.p1  = p1;
P.ts  = t(1);  P.te = t(end);
end

function [tc, cc, latS, lonS] = crossTimes(P, x0, y0, vx, vy, tref)
% 세포가 위성의 진행 방향 위치를 지나는 시각과, 그때의 궤적 직교 거리(km)
n = numel(x0);
tc = nan(n, 1); cc = nan(n, 1); xs = nan(n, 1); ys = nan(n, 1);
m = numel(P.t1);
for j = 1:m
    dtj = P.t1(j) - tref;
    qx = x0 + vx .* dtj - P.p1(j, 1);
    qy = y0 + vy .* dtj - P.p1(j, 2);
    a0 = qx * P.u(j, 1) + qy * P.u(j, 2);
    c0 = qx * P.nrm(j, 1) + qy * P.nrm(j, 2);
    va = vx * P.u(j, 1) + vy * P.u(j, 2);
    vc = vx * P.nrm(j, 1) + vy * P.nrm(j, 2);
    tau = a0 ./ (P.V(j) - va);
    dur = P.t2(j) - P.t1(j);
    if j < m, s = tau >= 0 & tau < dur; else, s = tau >= 0 & tau <= dur; end
    s = s & isnan(tc);
    tc(s) = P.t1(j) + tau(s);
    cc(s) = c0(s) + vc(s) .* tau(s);
    xs(s) = P.p1(j, 1) + P.V(j) * tau(s) * P.u(j, 1);
    ys(s) = P.p1(j, 2) + P.V(j) * tau(s) * P.u(j, 2);
end
latS = P.latm + ys / P.ky;
lonS = P.lonm + xs / P.kx;
end

function acc = schedule(cand, ts, R)
% 우선순위(호우급 먼저) → 시각 순으로 넣되, 앞뒤 표적과 기동 시간이 맞는 것만 채택
acc = zeros(0, 2);
if isempty(cand), return; end
[~, ord] = sortrows([-cand(:, 3), cand(:, 1)]);
for k = ord'
    tj = cand(k, 1);  cj = cand(k, 2);
    pos = sum(acc(:, 1) < tj);
    if pos == 0
        prevEnd = ts - R.prePoint;  prevC = 0;
    else
        prevEnd = acc(pos, 1) + R.dwell / 2;  prevC = acc(pos, 2);
    end
    okk = (tj - R.dwell / 2) - prevEnd >= slewTime(prevC, cj, R);
    if okk && pos < size(acc, 1)
        okk = (acc(pos + 1, 1) - R.dwell / 2) - (tj + R.dwell / 2) >= slewTime(cj, acc(pos + 1, 2), R);
    end
    if okk
        acc = [acc(1:pos, :); tj, cj; acc(pos + 1:end, :)];
    end
end
end

function s = slewTime(c1, c2, R)
dphi = abs(atand(c2 / R.h) - atand(c1 / R.h));
if dphi < 0.05, s = 0; else, s = dphi / R.slewRate + R.settle; end
end

function [cb, valid] = beamAt(acc, tq, R)
% 시각 tq에서 빔의 궤적 직교 오프셋(km)과 관측 유효 여부(기동·정착 중이면 무효)
cb = zeros(size(tq));  valid = true(size(tq));
if isempty(acc) || isempty(tq), return; end
m = size(acc, 1);
cPrev = [0; acc(1:m - 1, 2)];
se = acc(:, 1) - R.dwell / 2;
sl = arrayfun(@(k) slewTime(cPrev(k), acc(k, 2), R), (1:m)');
ss = se - sl;
for q = 1:numel(tq)
    k = find(ss <= tq(q), 1, 'last');
    if isempty(k), continue; end
    if tq(q) < se(k)
        valid(q) = false;
    else
        cb(q) = acc(k, 2);
    end
end
end
