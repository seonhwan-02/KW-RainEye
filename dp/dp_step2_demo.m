%% DP 지향 계획 2단계: 통과 하나로 원리 보기
% 하는 일
%   ① 2023 장마 자료와 궤도 위상 1의 통과 목록을 만든다
%   ② 호우가 많이 지나간 통과 하나를 고른다
%   ③ (시각 × 빔각) 보상 표를 만든다: 1단계에서 학습한 표로 "이 순간 이 각도로 보면 호우일 확률"을 채운다
%   ④ 동적계획법(DP)으로 보상 합이 가장 큰 빔 경로를 찾는다
%   ⑤ 천저 고정 / 기존 방식(호우 표적) / DP / 완벽 정보 DP 를 실제 강수로 채점해 비교한다
% 먼저 1단계(dp_step1_train)를 돌려 ../out/dp_step1_train/calib_2023.mat 이 있어야 한다.
% 결과는 ../out/dp_step2_demo 폴더에 그림 2장과 summary.txt로 저장된다.

clear; close all;
here = fileparts(mfilename('fullpath'));
outDir = fullfile(here, '..', 'out', 'dp_step2_demo');
if ~exist(outDir, 'dir'), mkdir(outDir); end
set(groot, 'defaultAxesFontName', 'Malgun Gothic', 'defaultTextFontName', 'Malgun Gothic');

L = kre_lib();
P = L.params();
S = load(fullfile(here, '..', 'out', 'dp_step1_train', 'calib_2023.mat'));   % 1단계 학습 결과
calib = S.calibN;

%% ① 자료와 통과 목록
D = L.loadSeason(2023);                       % 처음이면 캐시를 만드느라 몇 분 걸린다
passes = L.orbitPasses(D, P, 1);              % 궤도 위상 1로 122일 전파
fprintf('2023 장마 시즌, 궤도 위상 1: 관측창 통과 %d회\n', numel(passes));

%% ② 호우가 많이 지나간 통과 고르기 (±10° 안에 호우 칸이 있던 표본 수 기준)
nh = cellfun(@(G) L.heavyInSwath(G, D, P), passes);
[~, ip] = max(nh);
G = passes{ip};
tPass = D.t0 + seconds(G.ts);  tPass.TimeZone = 'Asia/Seoul';
fprintf('고른 통과: %d번째, %s KST, 길이 %.0f초, 표본 %d개\n', ip, char(tPass, 'yyyy-MM-dd HH:mm'), ...
    G.tq(end) - G.tq(1), numel(G.tq));

%% ③ 보상 표: 큐(15분 전 장면) + 나우캐스트로 예측한 것, 그리고 정답(실제 강수)
rs = RandStream('mt19937ar', 'Seed', 1);
[Rw, th, info] = L.rewardGrid(G, D, P, 'nowcast', rs, calib);
RwTrue = L.rewardGrid(G, D, P, 'oracle', []);
fprintf('보상 표 크기: 표본 %d × 빔각 %d (%.0f°~%.0f°, %g° 간격)\n', size(Rw, 1), size(Rw, 2), th(1), th(end), P.stepDeg);
fprintf('큐 시각: 통과 %d분 전, 그 장면의 이동 벡터 (동 %.1f, 북 %.1f) m/s\n', P.cueL, info.v * 1000);

%% ④ 동적계획법으로 최적 경로 찾기
planDP  = L.dpPlan(Rw, th, P);                % 예측 보상으로 계획 (실제 운용과 같은 조건)
planOr  = L.dpPlan(RwTrue, th, P);            % 정답 보상으로 계획 (상한)
planGr  = L.greedyPlan(G, D, P, 'nowcast', RandStream('mt19937ar', 'Seed', 1));
planNad = struct('cb', zeros(size(G.tq)), 'valid', true(size(G.tq)), 'th', zeros(size(G.tq)));

%% ⑤ 실제 강수로 채점
names = ["천저 고정", "기존 방식(호우 표적)", "DP(나우캐스트)", "DP(완벽 정보, 상한)"];
plans = {planNad, planGr, planDP, planOr};
E = cellfun(@(pl) L.evaluate(G, D, P, pl), plans);
fprintf('\n%-22s %8s %8s %8s %8s\n', '방식', '호우', '강수', '호우세포', '관측표본');
for k = 1:numel(E)
    fprintf('%-22s %8d %8d %8d %8d\n', names(k), E(k).heavy, E(k).rain, E(k).cells, E(k).valid);
end

%% 그림 1: 보상 표 위의 경로 (가로 = 시간, 세로 = 빔각)
tt = G.tq - G.tq(1);
f1 = figure('Position', [80 80 1100 560], 'Color', 'w');
tl = tiledlayout(f1, 2, 1, 'TileSpacing', 'compact');
ax = nexttile(tl);
imagesc(ax, tt, th, Rw');  axis(ax, 'xy');  colormap(ax, flipud(gray));  hold(ax, 'on');
cb = colorbar(ax);  cb.Label.String = '예측 보상 (호우 확률)';
plot(ax, tt, planDP.th, 'r-', 'LineWidth', 2, 'DisplayName', 'DP 경로');
plot(ax, tt, planGr.th, 'b.', 'MarkerSize', 10, 'DisplayName', '기존 방식(호우 표적)');
yline(ax, 0, 'k--', 'DisplayName', '천저');
ylabel(ax, '빔각 [°]');  title(ax, sprintf('예측 보상 표(큐 %d분 전)와 DP가 고른 경로', P.cueL));
legend(ax, 'Location', 'eastoutside');
ax = nexttile(tl);
imagesc(ax, tt, th, RwTrue');  axis(ax, 'xy');  colormap(ax, flipud(gray));  hold(ax, 'on');
cb = colorbar(ax);  cb.Label.String = '보상 (실제)';
plot(ax, tt, planDP.th, 'r-', 'LineWidth', 2, 'DisplayName', 'DP(예측) 경로');
plot(ax, tt, planOr.th, 'g-', 'LineWidth', 1.5, 'DisplayName', 'DP(완벽 정보)');
yline(ax, 0, 'k--', 'DisplayName', '천저');
xlabel(ax, '통과 시작부터 시간 [s]');  ylabel(ax, '빔각 [°]');
title(ax, '실제 강수로 만든 보상 표: 검은 칸이 실제 호우');
legend(ax, 'Location', 'eastoutside');
exportgraphics(f1, fullfile(outDir, 'fig1_reward_path.png'), 'Resolution', 140);

%% 그림 2: 지도 위의 빔 위치
kMid = G.kq(round(end / 2));
f2 = figure('Position', [120 60 900 760], 'Color', 'w');
ax = axes(f2);  hold(ax, 'on');
imagesc(ax, D.lon, D.lat, D.Pr(:, :, kMid), 'AlphaData', D.Pr(:, :, kMid) > 0.1);
axis(ax, 'xy');  axis(ax, 'image');  colormap(ax, turbo(256));  clim(ax, [0 30]);
cb = colorbar(ax);  cb.Label.String = '강수강도 [mm/h]';
plot(ax, E(1).blon, E(1).blat, 'k-', 'LineWidth', 1, 'DisplayName', '천저 궤적');
v = plans{3}.valid;
plot(ax, E(3).blon(v), E(3).blat(v), 'w.', 'MarkerSize', 12, 'DisplayName', 'DP 빔 위치');
hh = E(3).val >= P.thrHeavy;
plot(ax, E(3).blon(hh), E(3).blat(hh), 'mo', 'MarkerSize', 7, 'LineWidth', 1.5, 'DisplayName', 'DP가 본 호우 칸');
xlim(ax, [min(E(1).blon) - 1.5, max(E(1).blon) + 1.5]);  ylim(ax, [min(E(1).blat) - 0.5, max(E(1).blat) + 0.5]);
xlabel(ax, '경도 [°E]');  ylabel(ax, '위도 [°N]');
title(ax, sprintf('%s KST 통과: 호우 프로파일 천저 %d개 → DP %d개', char(tPass, 'MM-dd HH:mm'), E(1).heavy, E(3).heavy));
legend(ax, 'Location', 'southoutside', 'Orientation', 'horizontal');
exportgraphics(f2, fullfile(outDir, 'fig2_map.png'), 'Resolution', 140);

%% 저장
fid = fopen(fullfile(outDir, 'summary.txt'), 'w', 'n', 'UTF-8');
fprintf(fid, 'DP 2단계 (%s 실행): 2023 궤도 위상 1의 %d번째 통과, %s KST\n', string(datetime('now')), ip, char(tPass, 'yyyy-MM-dd HH:mm'));
fprintf(fid, '매개변수: ±%g°, 격자 %g°, 기동 %g°/s, 정착 %g s, 큐 지연 %g분, alpha %g, blur %g\n', ...
    P.maxDeg, P.stepDeg, P.slewRate, P.settle, P.cueL, P.alpha, P.blur);
fprintf(fid, '%-22s %8s %8s %8s %8s\n', '방식', '호우', '강수', '호우세포', '관측표본');
for k = 1:numel(E)
    fprintf(fid, '%-22s %8d %8d %8d %8d\n', names(k), E(k).heavy, E(k).rain, E(k).cells, E(k).valid);
end
fclose(fid);
fprintf('\n저장: %s\n', outDir);
