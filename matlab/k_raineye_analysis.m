%% K-RainEye 분석 파일 (모의 1~3)
% 제안서의 계산 근거를 한 파일에서 만든다. 실행하면 out 폴더에 그림 7장, summary.txt,
% key_results.json, results.mat가 생긴다.
%
%   모의 1 (1~7절)  궤도 커버리지와 큐잉 표적화 이득  → 제안서 4.7, 5.3
%   모의 2 (8~9절)  감도 예산과 Ka 강우 감쇠·관측 깊이 → 제안서 4.3, 4.4
%   모의 3 (10~11절) PRF 타이밍과 펄스압축 거리 부엽   → 제안서 4.5
%   모의 1-b (13절)  지향 민첩성·큐 지연 민감도        → 제안서 3.3 요구사항, 5.3
%   모의 3-b (14절)  비선형 처프(NLFM) 설계·펄스/안테나 절충 → 제안서 4.5
%
% 모의 1 가정 (제안서에 그대로 밝힐 것)
%   - 궤도: 원궤도, J2 영년 섭동만 반영, 구형 지구
%   - 강수: 합성 세포 모델(반경·수명 로그정규, 일정 속도 이동). 실제 관측 자료가 아니다.
%     GPM IMERG 30분 자료로 바꾸면 신뢰도가 크게 오른다(다음 단계).
%   - 큐: 천리안 탐지확률 cold형 0.9, warm형 0.6(적외선으로 약하게 보이므로 낮춤),
%     위치오차 3 km, 기준 지연 30분, 나우캐스트 속도오차 2 m/s
%   - 지향: 롤만 사용, 1°/s, 정착 8 s, 표적당 응시 6 s, 응시 후 다음 기동까지 그 각도 유지
%   - 정량 관측은 오프셋 ±3°(지상 ±29 km) 이내만 인정
%
% 필요 기능: MATLAB 기본 + Phased Array System Toolbox(모의 3 펄스압축).
% Satellite Communications Toolbox가 있으면 궤도 교차검증을 추가한다.

clear; close all;
rng(2026, 'twister');
here = fileparts(mfilename('fullpath'));
if isempty(here), here = pwd; end
outDir = fullfile(here, 'out');
if ~exist(outDir, 'dir'), mkdir(outDir); end
set(groot, 'defaultAxesFontName', 'Malgun Gothic', 'defaultTextFontName', 'Malgun Gothic');

%% 1. 매개변수
C = struct('Re', 6378.137, 'mu', 398600.4418, 'J2', 1.08262668e-3, 'we', 7.2921159e-5);

O.h      = 550;                                  % 고도 [km]
O.days   = 120;                                  % 6~9월 장마·태풍 시즌
O.t0     = datetime(2026, 6, 1, 0, 0, 0, 'TimeZone', 'UTC');
O.dt     = 10;                                   % 궤도 샘플 간격 [s]
O.nPhase = 8;                                    % 초기 궤도 위상 조합 수(결과는 평균)
O.inc    = [45, ssoInclination(C, 550)];         % [deg]
O.name   = ["경사 45°", "태양동기"];

W.lat = [28 38];                                 % 관측창 [deg]
W.lon = [119 127];

R.h        = O.h;
R.fpHalf   = 5.4;                                % 풋프린트 반폭 [km] (10.8 km)
R.reachQ   = 29;                                 % 정량 관측 오프셋 한계 ±3° [km]
R.reachU   = 97;                                 % 상층·접근 오프셋 한계 ±10° [km]
R.slewRate = 1.0;                                % [deg/s]
R.settle   = 8;                                  % [s]
R.dwell    = 6;                                  % 표적당 응시 [s]
R.profDt   = 1.5;                                % 프로파일 1개 = 풋프린트 길이 통과 시간 [s]
R.prePoint = 120;                                % 관측창 진입 전 미리 기동할 수 있는 시간 [s]

S.pRain  = 0.08;                                 % 관측창 면적·시간 중 강수 비율(가정)
S.rMed   = 8;   S.rSig = 0.6;  S.rLim = [3 40];  % 세포 반경 [km]
S.lMed   = 60;  S.lSig = 0.5;  S.lLim = [15 300];% 세포 수명 [min]
S.vMean  = [8 4] / 1000;                         % 이동속도 동·북 [km/s]
S.vSd    = 3 / 1000;
S.fHeavy = 0.3;                                  % 호우급 세포 비율(가정)
S.fWarm  = 0.6;                                  % warm형 세포 비율(가정)
S.margin = 150;                                  % 관측창 밖 생성 여유 [km]

Q.latency  = [0 10 20 30 45 60];                 % 큐 지연 [min]
Q.Lbase    = 30;
Q.pDetCold = 0.9;
Q.pDetWarm = 0.6;
Q.posSd    = 3;                                  % 큐 위치오차 [km]
Q.velSd    = 2 / 1000;                           % 나우캐스트 속도오차 [km/s]

mkMode = @(name, kind, reach, L, ho) struct('name', string(name), 'kind', string(kind), 'reach', reach, 'L', L, 'heavyOnly', ho);
modes = mkMode("천저 고정", "nadir", 0, 0, false);
modes(end+1) = mkMode("완벽 정보(상한, ±3°)", "oracle", R.reachQ, 0, false);
for L = Q.latency
    modes(end+1) = mkMode(sprintf("큐잉 ±3° 위치고정 %d분", L), "persist", R.reachQ, L, false); %#ok<SAGROW>
    modes(end+1) = mkMode(sprintf("큐잉 ±3° 나우캐스트 %d분", L), "nowcast", R.reachQ, L, false); %#ok<SAGROW>
end
modes(end+1) = mkMode(sprintf("큐잉 ±10° 나우캐스트 %d분", Q.Lbase), "nowcast", R.reachU, Q.Lbase, false);
nM = numel(modes);
mName = string({modes.name});

%% 2. 합성 강수 세포 목록
T = O.days * 86400;
latExt = W.lat + [-1 1] * S.margin / 110.57;
lonExt = W.lon + [-1 1] * S.margin / (111.32 * cosd(W.lat(2)));
Aext  = C.Re^2 * deg2rad(diff(lonExt)) * (sind(latExt(2)) - sind(latExt(1)));
Earea = pi * S.rMed^2 * exp(2 * S.rSig^2);
Elife = S.lMed * 60 * exp(S.lSig^2 / 2);
nCell = round(S.pRain * Aext * T / (Earea * Elife));
cel = makeCells(nCell, T, latExt, lonExt, S, Q);
fprintf('합성 강수 세포 %d개 생성\n', nCell);

%% 3. 궤도 전파와 통과별 관측 모의
jd0   = juliandate(O.t0);
gmst0 = deg2rad(mod(280.46061837 + 360.98564736629 * (jd0 - 2451545), 360));
nOrb  = numel(O.inc);
phs   = RandStream('mt19937ar', 'Seed', 7);
phases = [rand(phs, O.nPhase, 1), rand(phs, O.nPhase, 1)] * 2 * pi;   % [RAAN0, u0]

orbStat  = zeros(nOrb, O.nPhase, 3);     % [체류 분/일, 통과 수, 평균 통과 s]
out      = zeros(nOrb, O.nPhase, nM, 6); % [세포, 호우세포, warm세포, 프로파일, 정량프로파일, 표적수]
dayTrack = cell(nOrb, 1);
passes   = cell(nOrb, O.nPhase);         % 통과별 기하 (민감도 분석에서 재사용)

tic;
for io = 1:nOrb
    for ip = 1:O.nPhase
        [t, lat, lon] = propagate(C, O.h, O.inc(io), phases(ip, 1), phases(ip, 2), gmst0, O.days, O.dt);
        if ip == 1
            k1d = t < 86400;
            dayTrack{io} = [lat(k1d), lon(k1d)];
        end
        inWin = lat >= W.lat(1) & lat <= W.lat(2) & lon >= W.lon(1) & lon <= W.lon(2);
        dIn = diff([false; inWin; false]);
        st = find(dIn == 1);
        en = find(dIn == -1) - 1;
        orbStat(io, ip, :) = [sum(inWin) * O.dt / 60 / O.days, numel(st), mean((en - st + 1) * O.dt)];
        plist = {};
        for kp = 1:numel(st)
            k1 = max(st(kp) - 1, 1);
            k2 = min(en(kp) + 1, numel(t));
            if k2 - k1 < 1, continue; end
            plist{end + 1} = passGeometry(t(k1:k2), lat(k1:k2), lon(k1:k2)); %#ok<SAGROW>
        end
        passes{io, ip} = plist;
    end
    out(io, :, :, :) = reshape(evalModes(cel, passes(io, :), modes, R, W, S), [1, O.nPhase, nM, 6]);
    fprintf('%s 완료 (%.0f s)\n', O.name(io), toc);
end

%% 4. 집계
mStat = squeeze(mean(orbStat, 2));               % nOrb x 3
mOut  = reshape(mean(out, 2), [nOrb, nM, 6]);    % nOrb x nM x 6
gain  = mOut ./ mOut(:, 1, :);                   % 천저 고정 대비 배수
iOr   = find(mName == "완벽 정보(상한, ±3°)");
iP30  = find(mName == sprintf("큐잉 ±3° 위치고정 %d분", Q.Lbase));
iN30  = find(mName == sprintf("큐잉 ±3° 나우캐스트 %d분", Q.Lbase));
iU30  = find(mName == sprintf("큐잉 ±10° 나우캐스트 %d분", Q.Lbase));
iPL   = arrayfun(@(L) find(mName == sprintf("큐잉 ±3° 위치고정 %d분", L)), Q.latency);
iNL   = arrayfun(@(L) find(mName == sprintf("큐잉 ±3° 나우캐스트 %d분", L)), Q.latency);
spread = @(io, im, k) [min(out(io, :, im, k)), max(out(io, :, im, k))];

%% 5. 그림
% 그림 1: 하루 지상 궤적
f1 = figure('Visible', 'off', 'Position', [100 100 900 650]);
try
    gx = geoaxes(f1);
    geobasemap(gx, 'darkwater');
    hold(gx, 'on');
    cols = [0.06 0.49 0.42; 0.76 0.25 0.18];
    for io = 1:nOrb
        geoplot(gx, dayTrack{io}(:, 1), dayTrack{io}(:, 2), '.', 'Color', cols(io, :), 'MarkerSize', 5);
    end
    geoplot(gx, W.lat([1 1 2 2 1]), W.lon([1 2 2 1 1]), '-', 'Color', [1 0.8 0.2], 'LineWidth', 2);
    geolimits(gx, [18 48], [108 138]);
    legend(gx, [O.name + " (1일)", "관측창"], 'Location', 'southoutside', 'Orientation', 'horizontal');
    title(gx, '하루 지상 궤적과 장마 관측창');
catch
    ax = axes(f1); hold(ax, 'on');
    for io = 1:nOrb
        plot(ax, dayTrack{io}(:, 2), dayTrack{io}(:, 1), '.', 'MarkerSize', 5);
    end
    plot(ax, W.lon([1 2 2 1 1]), W.lat([1 1 2 2 1]), 'k-', 'LineWidth', 2);
    xlim(ax, [108 138]); ylim(ax, [18 48]); grid(ax, 'on');
    xlabel(ax, '경도 [°]'); ylabel(ax, '위도 [°]');
    legend(ax, [O.name + " (1일)", "관측창"], 'Location', 'southoutside', 'Orientation', 'horizontal');
    title(ax, '하루 지상 궤적과 장마 관측창');
end
exportgraphics(f1, fullfile(outDir, 'fig1_ground_track.png'), 'Resolution', 150);

% 그림 2: 궤도 비교
f2 = figure('Visible', 'off', 'Position', [100 100 900 360]);
tl = tiledlayout(f2, 1, 3, 'TileSpacing', 'compact');
lbl = ["관측창 체류 [분/일]", "시즌 통과 횟수 [회]", "시즌 천저 관측 세포 [개]"];
vals = [mStat(:, 1), mStat(:, 2), squeeze(mOut(:, 1, 1))];
for k = 1:3
    ax = nexttile(tl);
    b = bar(ax, categorical(O.name, O.name), vals(:, k), 0.6);
    b.FaceColor = 'flat'; b.CData = [0.06 0.49 0.42; 0.6 0.6 0.6];
    title(ax, lbl(k)); grid(ax, 'on');
    text(ax, 1:nOrb, vals(:, k), compose('%.1f', vals(:, k)), 'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom');
    ylim(ax, [0 max(vals(:, k)) * 1.18]);   % 2026-11-03: 값 라벨이 소제목을 침범하지 않게 머리 공간 확보
end
title(tl, sprintf('550 km 궤도 비교 (장마철 %d일, 위상 %d개 평균)', O.days, O.nPhase));
exportgraphics(f2, fullfile(outDir, 'fig2_orbit_compare.png'), 'Resolution', 150);

% 그림 3: 모드별 시즌 관측 세포 수 (경사 45°)
sel = [1, iP30, iN30, iOr, iU30];
f3 = figure('Visible', 'off', 'Position', [100 100 950 420]);
ax = axes(f3);
Y = squeeze(mOut(1, sel, 1:3));
b = bar(ax, categorical(mName(sel), mName(sel)), Y, 'grouped');
legend(ax, ["전체 강수 세포", "호우급 세포", "warm형 세포"], 'Location', 'northwest');
ylabel(ax, '시즌당 관측한 세포 수 [개]'); grid(ax, 'on');
title(ax, sprintf('관측 방식별 강수 세포 포착 (경사 45°, 지연 %d분 기준)', Q.Lbase));
for k = 1:numel(b)
    text(ax, b(k).XEndPoints, b(k).YEndPoints, compose('%.0f', b(k).YData), ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', 'FontSize', 8);
end
exportgraphics(f3, fullfile(outDir, 'fig3_mode_hits.png'), 'Resolution', 150);

% 그림 4: 큐 지연에 따른 표적화 이득
f4 = figure('Visible', 'off', 'Position', [100 100 760 420]);
ax = axes(f4); hold(ax, 'on'); grid(ax, 'on');
plot(ax, Q.latency, squeeze(gain(1, iNL, 1)), '-o', 'LineWidth', 1.8, 'DisplayName', '나우캐스트 보정: 전체 세포');
plot(ax, Q.latency, squeeze(gain(1, iNL, 2)), '-s', 'LineWidth', 1.8, 'DisplayName', '나우캐스트 보정: 호우급');
plot(ax, Q.latency, squeeze(gain(1, iPL, 1)), '--o', 'LineWidth', 1.2, 'DisplayName', '위치고정: 전체 세포');
plot(ax, Q.latency, squeeze(gain(1, iPL, 2)), '--s', 'LineWidth', 1.2, 'DisplayName', '위치고정: 호우급');
yline(ax, gain(1, iOr, 1), ':', '완벽 정보 상한(전체)', 'LineWidth', 1.2, 'HandleVisibility', 'off');
yline(ax, 1, '-', '천저 고정', 'Color', [0.5 0.5 0.5], 'HandleVisibility', 'off');
xlabel(ax, '큐 지연 [분]'); ylabel(ax, '천저 고정 대비 배수');
title(ax, '큐 지연에 따른 표적화 이득 (경사 45°, 정량 관측 ±3°)');
legend(ax, 'Location', 'northeast');
exportgraphics(f4, fullfile(outDir, 'fig4_latency_gain.png'), 'Resolution', 150);

%% 6. 궤도 교차검증 (Satellite Communications Toolbox가 있을 때)
xcheck = "Satellite Communications Toolbox 없음: 교차검증 생략";
if exist('satelliteScenario', 'file')
    try
        nd = 3;
        sc  = satelliteScenario(O.t0, O.t0 + days(nd), O.dt);
        sat = satellite(sc, (C.Re + O.h) * 1e3, 0, 45, rad2deg(phases(1, 1)), 0, ...
                        rad2deg(phases(1, 2)), 'OrbitPropagator', 'sgp4');
        pos = states(sat, 'CoordinateFrame', 'ecef');
        rr  = vecnorm(pos, 2, 1);
        latX = asind(pos(3, :) ./ rr);  lonX = atan2d(pos(2, :), pos(1, :));
        dwX = sum(latX >= W.lat(1) & latX <= W.lat(2) & lonX >= W.lon(1) & lonX <= W.lon(2)) * O.dt / 60 / nd;
        [~, latJ, lonJ] = propagate(C, O.h, 45, phases(1, 1), phases(1, 2), gmst0, nd, O.dt);
        dwJ = sum(latJ >= W.lat(1) & latJ <= W.lat(2) & lonJ >= W.lon(1) & lonJ <= W.lon(2)) * O.dt / 60 / nd;
        xcheck = sprintf("경사 45°, %d일 관측창 체류: SGP4(satelliteScenario) %.2f 분/일 vs 본 모델(J2) %.2f 분/일", nd, dwX, dwJ);
    catch ME
        xcheck = "교차검증 실패: " + string(ME.message);
    end
end

%% 7. 요약 저장
fid = fopen(fullfile(outDir, 'summary.txt'), 'w', 'n', 'UTF-8');
pr = @(varargin) fprintf(fid, varargin{:});
pr('K-RainEye 모의 1 결과 요약 (%s 실행)\n\n', string(datetime('now')));
pr('[궤도 비교] 고도 %d km, 장마철 %d일, 초기 위상 %d개 평균 (괄호는 위상별 최소~최대)\n', O.h, O.days, O.nPhase);
for io = 1:nOrb
    pr('  %s (경사 %.1f°): 관측창 체류 %.2f 분/일 (%.2f~%.2f), 통과 %.0f회/시즌 (%.0f~%.0f), 평균 통과 %.0f s\n', ...
        O.name(io), O.inc(io), mStat(io, 1), min(orbStat(io, :, 1)), max(orbStat(io, :, 1)), ...
        mStat(io, 2), min(orbStat(io, :, 2)), max(orbStat(io, :, 2)), mStat(io, 3));
end
pr('  체류 비 %.2f배, 통과 비 %.2f배, 천저 관측 세포 비 %.2f배 (경사 45° / 태양동기)\n\n', ...
    mStat(1, 1) / mStat(2, 1), mStat(1, 2) / mStat(2, 2), mOut(1, 1, 1) / mOut(2, 1, 1));
for io = 1:nOrb
    pr('[관측 방식별 시즌 합계: %s]\n', O.name(io));
    pr('  %-28s %8s %8s %8s %10s %10s %7s | 배수(세포/호우/프로파일)\n', '방식', '세포', '호우급', 'warm형', '프로파일', '정량프로파일', '표적수');
    for im = 1:nM
        pr('  %-28s %8.1f %8.1f %8.1f %10.0f %10.0f %7.0f | %.2f / %.2f / %.2f\n', mName(im), ...
            mOut(io, im, 1), mOut(io, im, 2), mOut(io, im, 3), mOut(io, im, 4), mOut(io, im, 5), mOut(io, im, 6), ...
            gain(io, im, 1), gain(io, im, 2), gain(io, im, 4));
    end
    r1 = spread(io, 1, 1); r2 = spread(io, iN30, 1);
    pr('  위상별 범위: 천저 고정 세포 %.0f~%.0f, 나우캐스트 %d분 세포 %.0f~%.0f\n\n', r1(1), r1(2), Q.Lbase, r2(1), r2(2));
end
pr('[교차검증] %s\n\n', xcheck);
pr('[가정]\n');
pr('  강수 비율 %.2f, 세포 반경 중앙값 %g km, 수명 중앙값 %g분, 이동 (%g, %g) m/s, 호우급 %.0f%%, warm형 %.0f%%\n', ...
    S.pRain, S.rMed, S.lMed, S.vMean * 1000, S.fHeavy * 100, S.fWarm * 100);
pr('  천리안 탐지확률 cold %.1f / warm %.1f, 위치오차 %g km, 나우캐스트 속도오차 %g m/s\n', ...
    Q.pDetCold, Q.pDetWarm, Q.posSd, Q.velSd * 1000);
pr('  롤 기동 %g°/s, 정착 %g s, 응시 %g s, 정량 관측 ±%g km(±3°), 풋프린트 %.1f km\n', ...
    R.slewRate, R.settle, R.dwell, R.reachQ, 2 * R.fpHalf);
pr('  강수 세포는 합성 모델이다. 실제 자료(GPM IMERG)로 교체 예정.\n');
fclose(fid);

save(fullfile(outDir, 'results.mat'), 'O', 'W', 'R', 'S', 'Q', 'mName', 'orbStat', 'out', 'mStat', 'mOut', 'gain', 'xcheck');
fprintf('완료: %s\n', outDir);

%% 8. 모의 2: 감도 예산
% 기준점: RainCube 궤도 실측 11.0 dBZ @400 km (JPL 2022 성능표). 보수 기준 13 dBZ (eoPortal·WMO 표기).
% 같은 송신 전력·펄스폭·안테나를 쓰므로 감도는 다음 비율로만 바뀐다고 본다(250 m 출력 구간 기준).
%   거리²: +20log10(R/R0)
%   PRF(독립 표본 수, 펄스 간 상관 없음): -5log10(PRF/PRF0)
%   적분 시간: -5log10(T/T0)
%   대역(250 m 출력 구간 안의 독립 거리 표본): +5log10(B/B0)
%   안테나: -(2ΔG + 20log10(θ/θ0))
c0   = 299792458;
fRad = 35.75e9;
lam  = c0 / fRad;
Vg   = C.Re * sqrt(C.mu / (C.Re + O.h)^3);           % 지상 궤적 속도 [km/s]
fpKm = 2 * O.h * tand(1.13 / 2);                      % 풋프린트 [km]
Tfp  = fpKm / Vg;                                     % 풋프린트 통과 시간 [s]

Ref.R   = 400;
Ref.PRF = 1 / 1660e-6;                                % RainCube PRI 1660 µs (eoPortal, 2차 자료)
Ref.B   = 2.5e6;                                      % RainCube 처프 대역 (eoPortal, 2차 자료)
Ref.Zs  = [11.0 13.0];
Ref.Ts  = [0.28, 7.9 / (C.Re * sqrt(C.mu / (C.Re + 400)^3))];   % 기준 적분시간 가정 [짧음, 풋프린트 통과]

ant.name = ["0.5 m", "1 m"];
ant.bw   = [1.13, 70 * lam / 1.0];                    % 빔폭 [deg]
ant.G    = [42.6, 49.2];                              % 이득 [dBi] (RainCube 실측, Tendeg 1 m 공개값)
ant.dG   = 2 * (ant.G - ant.G(1)) + 20 * log10(ant.bw / ant.bw(1));
PRFk = [1500 1800];
Bnew = 1.2e6;

sens = zeros(0, 6);                                   % [Zref, Tref, PRF, 대역보정, 안테나, Zmin]
for zr = Ref.Zs
    for tr = Ref.Ts
        for pf = PRFk
            for ub = [1 0]
                for ia = 1:2
                    d = 20 * log10(O.h / Ref.R) - 5 * log10(pf / Ref.PRF) - 5 * log10(Tfp / tr) - ant.dG(ia);
                    if ub, d = d + 5 * log10(Bnew / Ref.B); end
                    sens(end + 1, :) = [zr, tr, pf, ub, ia, zr + d]; %#ok<SAGROW>
                end
            end
        end
    end
end
isCentral = sens(:, 1) == 11 & abs(sens(:, 2) - Ref.Ts(2)) < 1e-9 & sens(:, 3) == 1800 & sens(:, 4) == 1 & sens(:, 5) == 1;
Zc = sens(isCentral, 6);
s05 = sens(sens(:, 5) == 1, 6);  s10 = sens(sens(:, 5) == 2, 6);
fprintf('감도 중심값 %.1f dBZ (0.5 m 범위 %.1f~%.1f, 1 m 범위 %.1f~%.1f)\n', Zc, min(s05), max(s05), min(s10), max(s10));

%% 9. 모의 2: Ka 강우 감쇠와 관측 깊이
% ITU-R P.838-3 계수(35.75 GHz, 연직 경로) 사용. MATLAB rainpl은 지상 링크용 경로길이 보정
% (ITU-R P.530)이 들어가 1 km 짧은 경로에서 감쇠를 크게 주므로 비교용으로만 기록한다.
kR = 0.3452;  aR = 0.8851;
Rr = [5 10 20 30 50];
gam = kR * Rr.^aR;                                    % 비감쇠 [dB/km, 단방향]
gamPL = nan(size(Rr));
if exist('rainpl', 'file')
    for k = 1:numel(Rr), gamPL(k) = rainpl(1000, fRad, Rr(k), 90); end
end
Hr  = 4.5;                                            % 액상층 두께 [km]
PIA = 2 * gam * Hr;                                   % 왕복 경로적분감쇠 [dB]
hg  = (0:0.05:Hr)';
Ztrue  = 10 * log10(200 * Rr.^1.6);                   % Marshall-Palmer (Ka 비레일리 효과 미반영)
lowest = zeros(size(Rr));
Zm = zeros(numel(hg), numel(Rr));
for k = 1:numel(Rr)
    Zm(:, k) = Ztrue(k) - 2 * gam(k) * (Hr - hg);
    vis = Zm(:, k) >= Zc;
    if any(vis), lowest(k) = hg(find(vis, 1)); else, lowest(k) = Hr; end
end

f5 = figure('Visible', 'off', 'Position', [100 100 900 420]);
tl5 = tiledlayout(f5, 1, 2, 'TileSpacing', 'compact');
ax = nexttile(tl5); hold(ax, 'on'); grid(ax, 'on');
for k = 1:numel(Rr)
    plot(ax, Zm(:, k), hg, 'LineWidth', 1.6, 'DisplayName', sprintf('%g mm/h', Rr(k)));
end
xline(ax, Zc, '--k', sprintf('감도 %.1f dBZ', Zc), 'LabelVerticalAlignment', 'bottom', 'HandleVisibility', 'off');
xlabel(ax, '위성에서 측정되는 반사도 [dBZ]'); ylabel(ax, '고도 [km]');
title(ax, '감쇠 후 겉보기 반사도 (액상층 4.5 km)');
legend(ax, 'Location', 'southwest'); xlim(ax, [-40 60]);
ax = nexttile(tl5); hold(ax, 'on'); grid(ax, 'on');
bar(ax, categorical(compose('%g mm/h', Rr), compose('%g mm/h', Rr)), PIA, 0.6, 'FaceColor', [0.06 0.49 0.42]);
yregion(ax, 42, 49, 'FaceColor', [0.76 0.25 0.18], 'FaceAlpha', 0.15);
text(ax, 0.55, 107, '해면 기준 측정 한계(가정 42~49 dB, 분홍 띠)', 'FontSize', 9, 'Color', [0.6 0.2 0.15]);   % 2026-11-03: 막대 침범 피해 위로 이동
text(ax, 1:numel(Rr), PIA, compose('%.0f dB', PIA), 'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom');
ylim(ax, [0 112]);
ylabel(ax, '왕복 경로적분감쇠 PIA [dB]'); title(ax, '강우율별 왕복 감쇠 (35.75 GHz)');
exportgraphics(f5, fullfile(outDir, 'fig5_attenuation.png'), 'Resolution', 150);

%% 10. 모의 3: PRF 타이밍 (펄스 송신과 수신 창이 겹치지 않는가)
tau   = 166e-6;  guard = 10e-6;
Htop  = 20;  Hbot = -3;                               % 수신 창: 고도 20 km ~ 지표 아래 3 km(거울상)
PRFs  = 1000:5:2400;
angs  = 0:0.25:10;
feas  = false(numel(angs), numel(PRFs));
for ia = 1:numel(angs)
    Rs  = slantRange(C.Re, O.h, angs(ia));
    inc = asind((C.Re + O.h) / C.Re * sind(angs(ia)));
    t1  = 2 * (Rs - Htop / cosd(inc)) * 1e3 / c0;
    t2  = 2 * (Rs - Hbot / cosd(inc)) * 1e3 / c0 + tau;
    w   = t2 - t1;
    for ip = 1:numel(PRFs)
        PRI = 1 / PRFs(ip);
        ph  = mod(t1, PRI);
        feas(ia, ip) = (w + tau + guard <= PRI) && (ph >= tau + guard) && (ph + w <= PRI);
    end
end
winNadir = (2 * (Htop - Hbot) * 1e3 / c0 + tau) * 1e6;                 % [µs]
needPRI  = winNadir + (tau + guard) * 1e6;                               % [µs]
prfMaxTheory = 1e6 / needPRI;                                            % [Hz]
bandIdx = PRFs >= 1500 & PRFs <= 1800;
coverBand = mean(any(feas(:, bandIdx), 2));                             % 가변 PRF로 각도 전 구간 가능 비율
fixedFrac = @(f) mean(feas(:, PRFs == f));
f7 = figure('Visible', 'off', 'Position', [100 100 820 420]);
ax = axes(f7);
imagesc(ax, PRFs / 1e3, angs, double(feas)); axis(ax, 'xy');
colormap(ax, [0.93 0.88 0.86; 0.06 0.49 0.42]);
xline(ax, [1.5 1.8 2.1], '--k', {'1.5', '1.8', '2.1 kHz'});
xlabel(ax, 'PRF [kHz]'); ylabel(ax, '롤 오프셋 [deg]');
title(ax, sprintf('PRF 타이밍 가능 영역(초록): 펄스 %d µs, 수신 창 %g~%g km', round(tau * 1e6), Hbot, Htop));
exportgraphics(f7, fullfile(outDir, 'fig6_prf_timing.png'), 'Resolution', 150);

%% 11. 모의 3: 펄스압축 거리 부엽
fs   = 8e6;
Bs   = [0.6e6, 1.2e6];
wins = ["None", "Hann", "Taylor"];
pcm  = zeros(numel(Bs), numel(wins), 3);              % [-3 dB 해상도 m, 첨두 부엽 dB, 1 km 밖 최대 부엽 dB]
prof = cell(numel(Bs), numel(wins));
for ib = 1:numel(Bs)
    wav = phased.LinearFMWaveform('SampleRate', fs, 'PulseWidth', tau, 'PRF', 1600, ...
        'SweepBandwidth', Bs(ib), 'SweepInterval', 'Symmetric', 'NumPulses', 1);
    x = wav();
    coef = getMatchedFilter(wav);
    for iw = 1:numel(wins)
        if wins(iw) == "None"
            mf = phased.MatchedFilter('Coefficients', coef);
        elseif wins(iw) == "Taylor"
            mf = phased.MatchedFilter('Coefficients', coef, 'SpectrumWindow', 'Taylor', ...
                'SpectrumRange', [-Bs(ib) / 2, Bs(ib) / 2], 'SampleRate', fs, 'SidelobeAttenuation', 40, 'Nbar', 5);
        else
            mf = phased.MatchedFilter('Coefficients', coef, 'SpectrumWindow', 'Hann', ...
                'SpectrumRange', [-Bs(ib) / 2, Bs(ib) / 2], 'SampleRate', fs);
        end
        y = mf([x; zeros(numel(coef), 1)]);
        [res, psl, far, rgm, adb] = pcMetrics(abs(y), fs, c0);
        pcm(ib, iw, :) = [res, psl, far];
        prof{ib, iw} = [rgm, adb];
    end
end
f8 = figure('Visible', 'off', 'Position', [100 100 820 420]);
ax = axes(f8); hold(ax, 'on'); grid(ax, 'on');
plot(ax, prof{1, 3}(:, 1) / 1e3, prof{1, 3}(:, 2), 'LineWidth', 1.2, 'DisplayName', '0.6 MHz + Taylor');
plot(ax, prof{2, 2}(:, 1) / 1e3, prof{2, 2}(:, 2), 'LineWidth', 1.2, 'DisplayName', '1.2 MHz + Hann');
plot(ax, prof{2, 3}(:, 1) / 1e3, prof{2, 3}(:, 2), 'LineWidth', 1.6, 'DisplayName', '1.2 MHz + Taylor');
yline(ax, -60, '--', '요구 −60 dB(해면 대비)', 'Color', [0.76 0.25 0.18], 'HandleVisibility', 'off');
xlim(ax, [-3 3]); ylim(ax, [-90 3]);
xlabel(ax, '거리 [km]'); ylabel(ax, '정규화 출력 [dB]');
title(ax, '선형 처프 펄스압축 응답 (166 µs)');
legend(ax, 'Location', 'northeast');
exportgraphics(f8, fullfile(outDir, 'fig7_pulse_compression.png'), 'Resolution', 150);

%% 12. 모의 2·3 요약 추가
fid = fopen(fullfile(outDir, 'summary.txt'), 'a', 'n', 'UTF-8');
pr = @(varargin) fprintf(fid, varargin{:});
pr('\n[모의 2: 감도 예산] 550 km, 풋프린트 %.2f km, 통과 %.2f s 평균, PRF 1.5~1.8 kHz, 대역 1.2 MHz\n', fpKm, Tfp);
pr('  중심값(기준 11.0 dBZ, 기준 적분 %.2f s, PRF 1.8 kHz, 대역 보정 포함, 0.5 m): %.1f dBZ\n', Ref.Ts(2), Zc);
pr('  0.5 m 안테나 전체 범위: %.1f ~ %.1f dBZ / 1 m 안테나: %.1f ~ %.1f dBZ (이득 차 %.1f dB)\n', ...
    min(s05), max(s05), min(s10), max(s10), ant.dG(2));
pr('  목표 13 dBZ 충족 비율: 0.5 m %.0f%%, 1 m %.0f%% (가정 조합 %d개 중)\n', ...
    100 * mean(s05 <= 13), 100 * mean(s10 <= 13), numel(s05));
pr('\n[모의 2: Ka 강우 감쇠] ITU-R P.838-3 k=%.4f, α=%.4f (연직), 액상층 %.1f km\n', kR, aR, Hr);
for k = 1:numel(Rr)
    pr('  %4g mm/h: 비감쇠 %.2f dB/km (rainpl %.2f), 왕복 PIA %.1f dB, 참 반사도 %.1f dBZ, 관측 가능 최저 고도 %.2f km\n', ...
        Rr(k), gam(k), gamPL(k), PIA(k), Ztrue(k), lowest(k));
end
pr('  참고: rainpl은 지상 링크 경로길이 보정(ITU-R P.530)이 들어가 1 km 경로에서 값이 큼. 연직 위성 경로에는 쓰지 않음.\n');
pr('\n[모의 3: PRF 타이밍] 수신 창 %.0f µs + 송신·보호 %.0f µs → 필요 PRI %.0f µs, 이론 최대 PRF %.2f kHz\n', ...
    winNadir, (tau + guard) * 1e6, needPRI, prfMaxTheory / 1e3);
pr('  고정 PRF로 롤 0~10° 전 구간 중 가능한 각도 비율: 1.5 kHz %.0f%%, 1.8 kHz %.0f%%, 2.1 kHz %.0f%%\n', ...
    100 * fixedFrac(1500), 100 * fixedFrac(1800), 100 * fixedFrac(2100));
pr('  1.5~1.8 kHz 안에서 각도별로 PRF를 바꾸면 가능한 각도 비율: %.0f%%\n', 100 * coverBand);
pr('\n[모의 3: 펄스압축] 166 µs 선형 처프\n');
for ib = 1:numel(Bs)
    for iw = 1:numel(wins)
        pr('  대역 %.1f MHz, 창 %-6s: 해상도 %.0f m, 첨두 부엽 %.1f dB, 1 km 밖 최대 부엽 %.1f dB\n', ...
            Bs(ib) / 1e6, wins(iw), pcm(ib, iw, 1), pcm(ib, iw, 2), pcm(ib, iw, 3));
    end
end
fclose(fid);

key = struct();
key.orbit = struct('name', O.name, 'dwell', mStat(:, 1)', 'passes', mStat(:, 2)', 'passSec', mStat(:, 3)', 'xcheck', xcheck);
key.gain45 = struct('modes', mName, 'cells', squeeze(mOut(1, :, 1)), 'heavy', squeeze(mOut(1, :, 2)), ...
    'warm', squeeze(mOut(1, :, 3)), 'prof', squeeze(mOut(1, :, 4)), 'quant', squeeze(mOut(1, :, 5)), ...
    'gainCells', squeeze(gain(1, :, 1)), ...
    'gainHeavy', squeeze(gain(1, :, 2)), 'gainProf', squeeze(gain(1, :, 4)));
key.gainSSO = struct('cells', squeeze(mOut(2, :, 1)), 'gainCells', squeeze(gain(2, :, 1)), 'gainHeavy', squeeze(gain(2, :, 2)));
key.sens = struct('central', Zc, 'range05', [min(s05) max(s05)], 'range10', [min(s10) max(s10)], 'dG1m', ant.dG(2), ...
    'meet13_05', mean(s05 <= 13), 'meet13_10', mean(s10 <= 13), 'Tfp', Tfp, 'fp', fpKm);
key.rain = struct('R', Rr, 'gamma', gam, 'gammaRainpl', gamPL, 'PIA', PIA, 'Ztrue', Ztrue, 'lowest', lowest);
key.prf = struct('needPRI', needPRI, 'prfMax', prfMaxTheory, 'f15', fixedFrac(1500), 'f18', fixedFrac(1800), ...
    'f21', fixedFrac(2100), 'band', coverBand);
key.pc = struct('B', Bs, 'wins', wins, 'res', pcm(:, :, 1), 'psl', pcm(:, :, 2), 'far', pcm(:, :, 3));
fidj = fopen(fullfile(outDir, 'key_results.json'), 'w', 'n', 'UTF-8');
fprintf(fidj, '%s', jsonencode(key, 'PrettyPrint', true));
fclose(fidj);
fprintf('모의 2·3 완료\n');

%% 13. 모의 1-b: 지향 민첩성·큐 지연 민감도 (경사 45°)
% 기준안에서 한 가지씩 바꾸고, 마지막에 조합안을 본다. 천저 고정 대비 배수로 비교한다.
% 정착 2 s, 기동 2°/s는 전개 안테나가 달린 16U에는 공격적인 값이라 상한 확인용이다.
mkV = @(lbl, st, dw, sl, rc, L, ho) struct('label', string(lbl), 'settle', st, 'dwell', dw, 'slew', sl, 'reach', rc, 'L', L, 'ho', ho);
V = mkV("기준: 정착 8 s·응시 6 s·1°/s·±3°·30분", 8, 6, 1, R.reachQ, 30, false);
V(end+1) = mkV("정착 4 s", 4, 6, 1, R.reachQ, 30, false);
V(end+1) = mkV("정착 2 s", 2, 6, 1, R.reachQ, 30, false);
V(end+1) = mkV("응시 3 s", 8, 3, 1, R.reachQ, 30, false);
V(end+1) = mkV("기동 2°/s", 8, 6, 2, R.reachQ, 30, false);
V(end+1) = mkV("허용 ±5°", 8, 6, 1, 48, 30, false);
V(end+1) = mkV("호우급만 겨냥", 8, 6, 1, R.reachQ, 30, true);
V(end+1) = mkV("큐 지연 20분", 8, 6, 1, R.reachQ, 20, false);
V(end+1) = mkV("큐 지연 10분", 8, 6, 1, R.reachQ, 10, false);
V(end+1) = mkV("민첩(정착 2 s·응시 3 s·2°/s)", 2, 3, 2, R.reachQ, 30, false);
V(end+1) = mkV("민첩 + 10분", 2, 3, 2, R.reachQ, 10, false);
V(end+1) = mkV("민첩 + 10분 + 호우급만", 2, 3, 2, R.reachQ, 10, true);
V(end+1) = mkV("민첩 + 10분 + ±5°", 2, 3, 2, 48, 10, false);
V(end+1) = mkV("민첩 + 10분 + ±5° + 호우급만", 2, 3, 2, 48, 10, true);
V(end+1) = mkV("현실 목표안: 정착 4 s·응시 3 s·1.5°/s·15분·호우급만", 4, 3, 1.5, R.reachQ, 15, true);
V(end+1) = mkV("현실 목표안: 정착 4 s·응시 3 s·1.5°/s·15분·전체", 4, 3, 1.5, R.reachQ, 15, false);
V(end+1) = mkV("현실 목표안: 정착 4 s·응시 3 s·1.5°/s·10분·전체", 4, 3, 1.5, R.reachQ, 10, false);
nV = numel(V);
sv = zeros(nV, 5);                      % [세포 배수, 호우급 배수, 프로파일 배수, 정량프로파일 배수, 통과당 표적]
nadirRes = squeeze(mean(out(1, :, 1, :), 2));   % 천저 고정 합계(위상 평균), 6 x 1
nPass45  = mStat(1, 2);
tic;
for iv = 1:nV
    Rv = R;  Rv.settle = V(iv).settle;  Rv.dwell = V(iv).dwell;  Rv.slewRate = V(iv).slew;
    mv = mkMode(V(iv).label, "nowcast", V(iv).reach, V(iv).L, V(iv).ho);
    rv = squeeze(mean(evalModes(cel, passes(1, :), mv, Rv, W, S), 1));
    rv = rv(:);
    sv(iv, :) = [rv(1) / nadirRes(1), rv(2) / nadirRes(2), rv(4) / nadirRes(4), rv(5) / nadirRes(5), rv(6) / nPass45];
end
fprintf('민감도 %d개 완료 (%.0f s)\n', nV, toc);

f9 = figure('Visible', 'off', 'Position', [100 100 1000 600]);
ax = axes(f9);
bh = barh(ax, categorical(string({V.label}), string({V.label})), sv(:, [1 2 4]), 'grouped');
set(ax, 'YDir', 'reverse');  grid(ax, 'on');
xline(ax, 1, '-', 'Color', [0.4 0.4 0.4], 'LineWidth', 1.2, 'HandleVisibility', 'off');
legend(ax, ["전체 세포", "호우급 세포", "정량 프로파일"], 'Location', 'southeast');
xlabel(ax, '천저 고정 대비 배수 (세로선 1.0 = 천저 고정)');
title(ax, '지향 민첩성·큐 지연·운용 정책에 따른 표적화 이득 (경사 45°)');
for k = 1:numel(bh)
    text(ax, bh(k).YEndPoints + 0.02, bh(k).XEndPoints, compose('%.2f', bh(k).YData), 'FontSize', 7, 'VerticalAlignment', 'middle');
end
exportgraphics(f9, fullfile(outDir, 'fig8_agility_sensitivity.png'), 'Resolution', 150);

fid = fopen(fullfile(outDir, 'summary.txt'), 'a', 'n', 'UTF-8');
fprintf(fid, '\n[모의 1-b: 지향 민첩성·큐 지연 민감도] 경사 45°, 나우캐스트, 천저 고정 대비 배수\n');
fprintf(fid, '  %-52s %8s %8s %10s %12s %10s\n', '조건', '세포', '호우급', '프로파일', '정량프로파일', '통과당표적');
for iv = 1:nV
    fprintf(fid, '  %-52s %8.2f %8.2f %10.2f %12.2f %10.2f\n', V(iv).label, sv(iv, :));
end
fclose(fid);
ks = struct('label', string({V.label}), 'settle', [V.settle], 'dwell', [V.dwell], 'slew', [V.slew], ...
    'reach', [V.reach], 'L', [V.L], 'heavyOnly', [V.ho], 'gainCells', sv(:, 1)', 'gainHeavy', sv(:, 2)', ...
    'gainProf', sv(:, 3)', 'gainQuant', sv(:, 4)', 'targetsPerPass', sv(:, 5)');
fidj = fopen(fullfile(outDir, 'key_sensitivity.json'), 'w', 'n', 'UTF-8');
fprintf(fidj, '%s', jsonencode(ks, 'PrettyPrint', true));
fclose(fidj);

%% 14. 모의 3-b: 비선형 처프(NLFM) 설계와 거리 부엽 절충
% 문제: 해면 반사(천저 Ka σ0 약 10 dB)의 거리 부엽이 지표 근처의 약한 비를 덮는다.
% 설계 후보(송신은 모두 일정 진폭, 테이퍼는 펄스 앞뒤 가장자리만 성형):
%   1) LFM + 테일러 창   2) NLFM(정상위상법) + 정합 필터   3) LFM + 최소제곱 부정합 필터
%   4) NLFM + 부정합 필터   5) LFM(가장자리 20% 테이퍼) + 부정합 필터
% 평가: 도플러 0 성능과, 빔 안 도플러 퍼짐(양방향 빔 패턴 가중)을 넣은 '빔 평균' 성능.
% 요구 부엽: 해면 상당 반사도 - 그 구성의 감도 (해면 부엽이 감도선 아래로 내려가야 함)
fsN = 6e6;  BN = 1.2e6;
sig0 = 10;  dRb = 250;  K2 = 0.88;                           % 해면 σ0 [dB], 거리 구간 [m], |K|²
Zsurf = 10 * log10(10^(sig0 / 10) / dRb * lam^4 / (pi^5 * K2) * 1e18);   % 해면 상당 반사도 [dBZ]
cfg = struct('name', {"166 µs · 0.5 m", "166 µs · 1 m", "83 µs · 0.5 m", "83 µs · 1 m"}, ...
             'tau', {166e-6, 166e-6, 83e-6, 83e-6}, 'D', {0.5, 1.0, 0.5, 1.0});
dsn = ["LFM + 테일러 창", "NLFM + 정합 필터", "LFM + 부정합 필터", "NLFM + 부정합 필터", "LFM 테이퍼 + 부정합 필터"];
nCf = numel(cfg);  nD = numel(dsn);
nlr = zeros(nCf, nD, 9);   % [해상도, 첨두부엽, 1km밖, SNR손실, 빔평균1km밖, 오염없는고도 m, 감도 dBZ, 요구부엽 dB, 여유 dB]
prof14 = cell(nCf, nD);
for ic = 1:nCf
    tauC = cfg(ic).tau;
    tC   = (0:1/fsN:tauC - 1/fsN)';
    Nc   = numel(tC);
    bwC  = 1.13 * 0.5 / cfg(ic).D;
    fdC  = 2 * 7.6e3 / lam * sind(bwC / 2);
    fg   = linspace(-BN / 2, BN / 2, 4001)';
    wTay = max(interp1(linspace(-BN / 2, BN / 2, 801)', taylorwin(801, 8, -60), fg), 1e-3);
    sLFM = exp(1j * 2 * pi * cumtrapz(tC, -BN / 2 + BN * tC / tauC));
    fiN  = interp1(tauC * cumtrapz(fg, wTay) / trapz(fg, wTay), fg, tC, 'pchip');
    sNL  = exp(1j * 2 * pi * cumtrapz(tC, fiN));
    sTp  = sLFM .* tukeywin(Nc, 0.2);
    if ic == 1, fiL14 = -BN / 2 + BN * tC / tauC; fiN14 = fiN; t14 = tC; end
    exclC = round(1.5 * fsN / BN);
    Mc    = round(1.5 * Nc);
    pairs = {sLFM, windowedMF(sLFM, fsN, BN, 40); sNL, conj(flipud(sNL)); ...
             sLFM, lsMismatch(sLFM, Mc, exclC, 1e-5); sNL, lsMismatch(sNL, Mc, exclC, 1e-5); ...
             sTp, lsMismatch(sTp, Mc, exclC, 1e-2)};
    dCfg = -10 * log10(tauC / 166e-6) - ant.dG(1 + (cfg(ic).D > 0.75));   % 감도 변화(기준 166 µs·0.5 m)
    for id = 1:nD
        s = pairs{id, 1};  h = pairs{id, 2};
        y = conv(s, h);
        [res, psl, far] = pcMetrics(abs(y), fsN, c0);
        loss = 10 * log10(norm(sLFM)^2 / (max(abs(y))^2 / norm(h)^2));   % 테이퍼 송신 에너지 손실 포함
        Zmin = Zc + dCfg + loss;
        need = -(Zsurf - Zmin);
        [farB, hClean, rg, pdb] = beamAvgFar(s, h, tC, fsN, c0, fdC, -need);
        nlr(ic, id, :) = [res, psl, far, loss, farB, hClean, Zmin, need, need - farB];
        prof14{ic, id} = [rg, pdb];
    end
end

f10 = figure('Visible', 'off', 'Position', [100 100 1050 430]);
tl10 = tiledlayout(f10, 1, 2, 'TileSpacing', 'compact');
ax = nexttile(tl10); hold(ax, 'on'); grid(ax, 'on');
plot(ax, t14 * 1e6, fiL14 / 1e6, 'LineWidth', 1.5, 'DisplayName', '선형 처프(LFM)');
plot(ax, t14 * 1e6, fiN14 / 1e6, 'LineWidth', 1.8, 'DisplayName', '비선형 처프(NLFM)');
xlabel(ax, '펄스 안 시간 [µs]'); ylabel(ax, '순간 주파수 [MHz]');
title(ax, '주파수를 훑는 방식 (166 µs, 1.2 MHz)'); legend(ax, 'Location', 'northwest');
ax = nexttile(tl10); hold(ax, 'on'); grid(ax, 'on');
for id = [1 2 3 5]
    plot(ax, prof14{2, id}(:, 1) / 1e3, prof14{2, id}(:, 2), 'LineWidth', 1.3, 'DisplayName', dsn(id));
end
yline(ax, nlr(2, 5, 8), '--', '요구(해면→감도)', 'Color', [0.76 0.25 0.18], 'HandleVisibility', 'off');
xlim(ax, [-4 4]); ylim(ax, [-90 3]);
xlabel(ax, '해면 첨두로부터 거리 [km]'); ylabel(ax, '빔 평균 정규화 출력 [dB]');
title(ax, '빔 안 도플러를 넣은 해면 응답 (166 µs, 1 m)'); legend(ax, 'Location', 'south');
exportgraphics(f10, fullfile(outDir, 'fig9_nlfm.png'), 'Resolution', 150);

f11 = figure('Visible', 'off', 'Position', [100 100 980 400]);
ax = axes(f11);
mg = squeeze(nlr(:, :, 9));
b11 = bar(ax, categorical(string({cfg.name}), string({cfg.name})), mg, 'grouped');
grid(ax, 'on'); yline(ax, 0, '-k', 'HandleVisibility', 'off');
ylabel(ax, '부엽 여유 [dB] (0 이상이면 해면 부엽이 감도선 아래)');
legend(ax, dsn, 'Location', 'northeastoutside');
title(ax, '구성별 해면 거리 부엽 여유 (빔 평균, 1 km 밖)');
for k = 1:numel(b11)
    text(ax, b11(k).XEndPoints, b11(k).YEndPoints, compose('%.0f', b11(k).YData), 'HorizontalAlignment', 'center', ...
        'VerticalAlignment', 'bottom', 'FontSize', 7);
end
exportgraphics(f11, fullfile(outDir, 'fig10_sidelobe_margin.png'), 'Resolution', 150);

fid = fopen(fullfile(outDir, 'summary.txt'), 'a', 'n', 'UTF-8');
fprintf(fid, '\n[모의 3-b: 비선형 처프 설계와 거리 부엽 절충] 대역 %.1f MHz, 해면 σ0 %d dB → 해면 상당 반사도 %.1f dBZ(%d m 구간)\n', ...
    BN / 1e6, sig0, Zsurf, dRb);
for ic = 1:nCf
    bwC = 1.13 * 0.5 / cfg(ic).D;  fdC = 2 * 7.6e3 / lam * sind(bwC / 2);
    fprintf(fid, '  [%s] 빔 가장자리 도플러 %.1f kHz\n', cfg(ic).name, fdC / 1e3);
    fprintf(fid, '    %-22s %7s %9s %9s %8s %11s %9s %9s %8s %12s\n', '조합', '해상도', '첨두부엽', '1km밖', 'SNR손실', '빔평균1km밖', '감도', '요구부엽', '여유', '오염없는고도');
    for id = 1:nD
        fprintf(fid, '    %-22s %5.0f m %7.1f dB %7.1f dB %6.2f dB %9.1f dB %6.1f dBZ %7.1f dB %+6.1f dB %10.2f km\n', dsn(id), ...
            nlr(ic, id, 1:5), nlr(ic, id, 7), nlr(ic, id, 8), nlr(ic, id, 9), nlr(ic, id, 6) / 1e3);
    end
end
fclose(fid);
kn = struct('cfg', string({cfg.name}), 'designs', dsn, 'Zsurf', Zsurf, 'res', squeeze(nlr(:, :, 1)), ...
    'psl', squeeze(nlr(:, :, 2)), 'far', squeeze(nlr(:, :, 3)), 'loss', squeeze(nlr(:, :, 4)), ...
    'farBeam', squeeze(nlr(:, :, 5)), 'cleanH', squeeze(nlr(:, :, 6)), 'Zmin', squeeze(nlr(:, :, 7)), ...
    'need', squeeze(nlr(:, :, 8)), 'margin', squeeze(nlr(:, :, 9)));
fidj = fopen(fullfile(outDir, 'key_nlfm.json'), 'w', 'n', 'UTF-8');
fprintf(fidj, '%s', jsonencode(kn, 'PrettyPrint', true));
fclose(fidj);
fprintf('NLFM 설계 완료\n');

%% ===== 로컬 함수 =====
function h = lsMismatch(s, M, excl, ld)
% 최소제곱 부정합 필터: 주엽(중심 ±excl 표본) 밖 출력 에너지를 최소화하고 중심 출력을 1로 고정
s = s(:);  N = numel(s);
S = convmtx(s, M);
c = round((N + M) / 2);
side = true(N + M - 1, 1);  side(c - excl:c + excl) = false;
A = S(side, :);
Rm = A' * A;
Rm = Rm + ld * real(trace(Rm)) / M * eye(M);
a = S(c, :).';
h = Rm \ conj(a);
h = h / (a.' * h);
end

function [farB, hClean, rg, pdb] = beamAvgFar(s, h, tN, fs, c0, fdHalf, dyn)
% 양방향 빔 패턴(가우시안)으로 가중한 도플러 평균 응답(해면처럼 빔 전체에 퍼진 표적)
% farB: 1 km 밖 최대 부엽 [dB], hClean: 응답이 -dyn dB 아래로 내려가는 첨두로부터의 거리 [m]
fdg = linspace(-1.6 * fdHalf, 1.6 * fdHalf, 33);
sig2 = (fdHalf / sqrt(2)) / sqrt(2 * log(2));
wt = exp(-fdg.^2 / (2 * sig2^2));
Pw = 0;
for k = 1:numel(fdg)
    y = conv(s(:) .* exp(1j * 2 * pi * fdg(k) * tN), h);
    Pw = Pw + wt(k) * abs(y).^2;
end
Pw = Pw / max(Pw);
[~, pk] = max(Pw);
rg  = ((1:numel(Pw))' - pk) / fs * c0 / 2;
pdb = 10 * log10(max(Pw, 1e-15));
farB = max(pdb(abs(rg) >= 1000));
over = abs(rg(pdb > -dyn));
hClean = max(over);
end

function h = windowedMF(s, fs, B, sll)
% 정합 필터에 테일러 창을 주파수 영역에서 곱한 수신 필터(임펄스 응답)
s = s(:);  N = numel(s);
L = 2^nextpow2(4 * N);
Sf = fft(s, L);
f = (0:L - 1)' * fs / L;  f(f >= fs / 2) = f(f >= fs / 2) - fs;
w = zeros(L, 1);
inb = abs(f) <= B / 2;
tw = taylorwin(1001, 5, -sll);
w(inb) = interp1(linspace(-B / 2, B / 2, 1001)', tw, f(inb));
h = ifft(conj(Sf) .* w);
P = 200;                                  % 창으로 퍼진 응답이 잘리지 않게 여유를 둠
h = circshift(h, N - 1 + P);
h = h(1:N + 2 * P);
end

function res = evalModes(cel, passRow, modes, R, W, S)
% 통과 목록과 관측 방식 목록을 받아 위상별·방식별 시즌 합계를 낸다
% res(위상, 방식, :) = [세포, 호우세포, warm세포, 프로파일, 정량프로파일, 표적수]
nP = numel(passRow);  nM = numel(modes);
res  = zeros(nP, nM, 6);
Lmax = max([modes.L]) * 60;
for ip = 1:nP
    tot = zeros(nM, 6);
    for kp = 1:numel(passRow{ip})
        P = passRow{ip}{kp};
        iLo = lowerBound(cel.tb, P.ts - S.lLim(2) * 60 - Lmax);
        iHi = lowerBound(cel.tb, P.te + 1e-6) - 1;
        if iHi < iLo, continue; end
        id = (iLo:iHi)';
        x0 = (cel.lon0(id) - P.lonm) * P.kx;
        y0 = (cel.lat0(id) - P.latm) * P.ky;
        tb = cel.tb(id);  td = cel.td(id);
        vx = cel.vx(id);  vy = cel.vy(id);
        % 실제 강수 세포가 위성 진행 방향 위치를 지나는 순간(방식과 무관)
        [tcT, ccT, latS, lonS] = crossTimes(P, x0, y0, vx, vy, tb);
        ok = ~isnan(tcT) & tcT >= tb & tcT <= td & ...
             latS >= W.lat(1) & latS <= W.lat(2) & lonS >= W.lon(1) & lonS <= W.lon(2);
        rx.t = tcT(ok);  rx.c = ccT(ok);  rx.r = cel.r(id(ok));
        rx.heavy = cel.heavy(id(ok));  rx.warm = cel.warm(id(ok));
        Vp = median(P.V);
        for im = 1:nM
            md = modes(im);
            if md.kind == "nadir"
                acc = zeros(0, 2);
            else
                if md.kind == "oracle"
                    tcue = P.ts;  useDet = true(numel(id), 1);
                    ex = 0; ey = 0; evx = 0; evy = 0;
                else
                    tcue = P.ts - md.L * 60;  useDet = cel.det(id);
                    ex = cel.ex(id); ey = cel.ey(id); evx = cel.evx(id); evy = cel.evy(id);
                end
                obs = useDet & tb <= tcue & td >= tcue;
                xo = x0 + vx .* (tcue - tb) + ex;
                yo = y0 + vy .* (tcue - tb) + ey;
                if md.kind == "persist"
                    vxh = zeros(numel(id), 1);  vyh = vxh;
                else
                    vxh = vx + evx;  vyh = vy + evy;
                end
                [tcH, ccH] = crossTimes(P, xo(obs), yo(obs), vxh(obs), vyh(obs), tcue);
                pr = 1 + double(cel.heavy(id(obs)));
                cand = ~isnan(tcH) & abs(ccH) <= md.reach;
                if md.heavyOnly, cand = cand & pr == 2; end
                acc = schedule([tcH(cand), ccH(cand), pr(cand)], P.ts, R);
            end
            [cb, valid] = beamAt(acc, rx.t, R);
            dd    = abs(rx.c - cb);
            hit   = valid & dd <= rx.r + R.fpHalf;
            prof  = 2 * sqrt(max(rx.r.^2 - dd.^2, 0)) / Vp / R.profDt .* valid;
            quant = abs(cb) <= R.reachQ + 1e-6;
            tot(im, :) = tot(im, :) + [sum(hit), sum(hit & rx.heavy), sum(hit & rx.warm), ...
                                       sum(prof), sum(prof .* quant), size(acc, 1)];
        end
    end
    res(ip, :, :) = reshape(tot, [1 nM 6]);
end
end

function inc = ssoInclination(C, h)
a = C.Re + h;
n = sqrt(C.mu / a^3);
k = C.J2 * (C.Re / a)^2;
raanDot = 2 * pi / (365.2422 * 86400);
inc = acosd(-raanDot / (1.5 * n * k));
end

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

function c = makeCells(n, T, latExt, lonExt, S, Q)
clip = @(x, lim) min(max(x, lim(1)), lim(2));
c.tb   = sort(rand(n, 1) * T);
c.td   = c.tb + clip(S.lMed * exp(S.lSig * randn(n, 1)), S.lLim) * 60;
s1 = sind(latExt(1)); s2 = sind(latExt(2));
c.lat0 = asind(s1 + (s2 - s1) * rand(n, 1));          % 면적 균등
c.lon0 = lonExt(1) + diff(lonExt) * rand(n, 1);
c.r    = clip(S.rMed * exp(S.rSig * randn(n, 1)), S.rLim);
c.vx   = S.vMean(1) + S.vSd * randn(n, 1);
c.vy   = S.vMean(2) + S.vSd * randn(n, 1);
c.heavy = rand(n, 1) < S.fHeavy;
c.warm  = rand(n, 1) < S.fWarm;
pDet    = Q.pDetCold * ~c.warm + Q.pDetWarm * c.warm;
c.det   = rand(n, 1) < pDet;
c.ex    = Q.posSd * randn(n, 1);
c.ey    = Q.posSd * randn(n, 1);
c.evx   = Q.velSd * randn(n, 1);
c.evy   = Q.velSd * randn(n, 1);
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

function i = lowerBound(a, v)
% 정렬된 a에서 a(i) >= v인 첫 번째 위치
lo = 1;  hi = numel(a) + 1;
while lo < hi
    mid = floor((lo + hi) / 2);
    if a(mid) < v, lo = mid + 1; else, hi = mid; end
end
i = lo;
end

function Rs = slantRange(Re, h, offDeg)
% 위성에서 오프나디르 각 offDeg로 본 지표까지의 경사거리 [km]
Rs = (Re + h) * cosd(offDeg) - sqrt(Re^2 - ((Re + h) * sind(offDeg))^2);
end

function [res, psl, far, rgm, adb] = pcMetrics(a, fs, c0)
% 펄스압축 출력의 -3 dB 거리해상도[m], 첨두 부엽[dB], 1 km 밖 최대 부엽[dB]
a = a(:) / max(a);
[~, pk] = max(a);
n = numel(a);
rgm = ((1:n)' - pk) / fs * c0 / 2;
adb = 20 * log10(max(a, 1e-12));
lo = pk; while lo > 1 && a(lo - 1) >= 1 / sqrt(2), lo = lo - 1; end
hi = pk; while hi < n && a(hi + 1) >= 1 / sqrt(2), hi = hi + 1; end
res = (hi - lo + 1) / fs * c0 / 2;
l0 = pk; while l0 > 1 && a(l0 - 1) < a(l0), l0 = l0 - 1; end
h0 = pk; while h0 < n && a(h0 + 1) < a(h0), h0 = h0 + 1; end
side = a; side(l0:h0) = 0;
psl = 20 * log10(max(side));
far = 20 * log10(max(a(abs(rgm) >= 1000)));
end
