%% DP 지향 계획 1단계: 2023 자료로 "큐가 보여 준 강도 → 실제 호우 확률" 표 학습
% 왜 필요한가
%   위성은 큐 장면(천리안·KIM)만 보고 어디를 볼지 정해야 한다. 그런데 비는 30분 사이에도
%   세졌다 약해졌다 한다. 그래서 "큐에서 7 mm/h로 보인 곳이 실제로 호우일 확률" 같은 숫자가 필요하다.
%   이 표를 2023 장마 자료 전체(5,856장면 × 15,600칸)로 센다. 이것이 DP가 쓰는 '보상'이 된다.
% 큐 장면의 나이
%   큐 지연이 15분이면, 큐가 쓸 수 있는 IMERG 장면은 큐 시각 전에 끝난 30분 칸이다.
%   그래서 관측 시각보다 1칸(30분) 또는 2칸(60분) 앞선 장면이다. 표를 나이별로 따로 만든다.
% 검증 원칙: 이 표는 2023으로만 만들고, 3단계에서 2024에 그대로 적용해 성능을 확인한다.
% 결과: ../out/dp_step1_train 에 calib_2023.mat, summary.txt, key_calib.json, 그림 1장

clear; close all;
here = fileparts(mfilename('fullpath'));
outDir = fullfile(here, '..', 'out', 'dp_step1_train');
if ~exist(outDir, 'dir'), mkdir(outDir); end
set(groot, 'defaultAxesFontName', 'Malgun Gothic', 'defaultTextFontName', 'Malgun Gothic');

L = kre_lib();
P = L.params();
D = L.loadSeason(2023);

%% 학습: 나우캐스트(이동 반영)와 위치고정(이동 무시) 두 가지
tic;
calibN = L.calibrate(D, P, 'nowcast', 2023);
calibP = L.calibrate(D, P, 'persist', 2023);
fprintf('학습 완료 (%.0f s)\n', toc);

%% 표 출력 (열: 큐 장면이 30분 앞 / 60분 앞)
lo = P.edges(1:end - 1);  hi = P.edges(2:end);
lbl = compose('%g~%g', lo', hi');  lbl{end} = sprintf('%g 이상', lo(end));
fprintf('\n큐 강도 [mm/h] |   칸 수(30분) | 실제 호우 확률: 나우캐스트 30분 / 60분 | 위치고정 30분 / 60분\n');
for b = 1:numel(lo)
    fprintf('%-14s | %13d | %14.1f%% / %5.1f%%            | %6.1f%% / %5.1f%%\n', lbl{b}, calibN.count(b, 1), ...
        100 * calibN.pHeavy(b, 1), 100 * calibN.pHeavy(b, 2), 100 * calibP.pHeavy(b, 1), 100 * calibP.pHeavy(b, 2));
end

%% 그림
f = figure('Position', [100 100 900 420], 'Color', 'w');
ax = axes(f);  hold(ax, 'on');  grid(ax, 'on');
x = 1:numel(lo);
plot(ax, x, 100 * calibN.pHeavy(:, 1), '-o', 'LineWidth', 2, 'DisplayName', '호우 확률 · 나우캐스트 · 30분 앞 장면');
plot(ax, x, 100 * calibN.pHeavy(:, 2), '-s', 'LineWidth', 2, 'DisplayName', '호우 확률 · 나우캐스트 · 60분 앞 장면');
plot(ax, x, 100 * calibP.pHeavy(:, 1), '--o', 'LineWidth', 1.2, 'DisplayName', '호우 확률 · 위치고정 · 30분 앞 장면');
plot(ax, x, 100 * calibN.pRain(:, 1), ':^', 'LineWidth', 1.2, 'DisplayName', '강수 확률 · 나우캐스트 · 30분 앞 장면');
set(ax, 'XTick', x, 'XTickLabel', lbl);  xtickangle(ax, 30);
xlabel(ax, '큐 장면에서 보인 강도 [mm/h]');  ylabel(ax, '그 뒤 실제로 그랬던 비율 [%]');
title(ax, '2023 장마 학습 결과: 큐가 보여 준 강도와 실제 호우·강수의 관계');
legend(ax, 'Location', 'northwest');
exportgraphics(f, fullfile(outDir, 'fig_calibration.png'), 'Resolution', 140);

%% 저장
save(fullfile(outDir, 'calib_2023.mat'), 'calibN', 'calibP', 'P');
fid = fopen(fullfile(outDir, 'summary.txt'), 'w', 'n', 'UTF-8');
fprintf(fid, 'DP 1단계 학습 (%s 실행): 2023 IMERG, 장면 %d개, 장면 나이 30분·60분\n', string(datetime('now')), D.nT);
fprintf(fid, '큐 한계: 호우 핵 인식 %.2f(못 알아보면 %.1f~%.1f배로 약하게 보임), 위치오차 %g km, 속도오차 %g m/s\n', ...
    P.pDet, P.weakFac, P.posSd, P.velSd * 1000);
fprintf(fid, '큐 강도 [mm/h], 칸 수(30분), 호우%% 나우캐스트 30분, 60분, 호우%% 위치고정 30분, 60분, 강수%% 나우캐스트 30분\n');
for b = 1:numel(lo)
    fprintf(fid, '%s, %d, %.2f, %.2f, %.2f, %.2f, %.2f\n', lbl{b}, calibN.count(b, 1), 100 * calibN.pHeavy(b, 1), ...
        100 * calibN.pHeavy(b, 2), 100 * calibP.pHeavy(b, 1), 100 * calibP.pHeavy(b, 2), 100 * calibN.pRain(b, 1));
end
fclose(fid);
fid = fopen(fullfile(outDir, 'key_calib.json'), 'w', 'n', 'UTF-8');
fprintf(fid, '%s', jsonencode(struct('edges', P.edges(1:end - 1), 'lagsMin', 30 * P.lags, 'count', calibN.count, ...
    'pHeavyNowcast', calibN.pHeavy, 'pHeavyPersist', calibP.pHeavy, 'pRainNowcast', calibN.pRain), 'PrettyPrint', true));
fclose(fid);
fprintf('\n저장: %s\n', outDir);
