%% DP 지향 계획 3단계: 시즌 전체로 성능 확인 — 2023(학습한 해)과 2024(처음 보는 해)
% 비교하는 방식 (모두 같은 궤도·같은 큐 오차·같은 실제 강수로 채점)
%   천저 고정               : 기울이지 않는다 (기준 1.00)
%   기존 방식(호우 표적)    : 큐에서 10 mm/h 이상인 국지 최대점을 하나씩 찍는 스케줄러
%   DP(위치고정)            : 큐 장면을 움직이지 않고 동적계획법
%   DP(나우캐스트)          : 큐 장면을 이동 벡터로 옮겨 동적계획법  ← 제안 방식
%   DP(완벽 정보, 상한)     : 실제 강수를 미리 안다고 치고 동적계획법 (기동 제약 안에서의 최대)
%   이론 상한               : 기동 제약도 없다고 칠 때 (±10° 안에 호우가 있던 표본 수)
% 검증 원칙: 학습 표(1단계)는 2023으로만 만들었고, 2024에는 그대로 적용한다.
% 함께 내는 것: 각도대별(0~3°, 3~6°, 6~10°) 호우 표본, 날짜 단위 부트스트랩 95% 신뢰구간
% 먼저 1단계(dp_step1_train)를 돌려 ../out/dp_step1_train/calib_2023.mat 이 있어야 한다.
% 처음 2024를 읽을 때 캐시·이동 벡터를 만드느라 몇 분 더 걸린다. 전체 약 10~20분.
% 결과: ../out/dp_step3_validate 에 summary.txt, key_dp.json, methods.csv, passes.csv, results.mat, 그림, run_info.txt
%       ../out/run_log.csv 에 한 줄 추가

clear; close all;
here = fileparts(mfilename('fullpath'));
outDir = fullfile(here, '..', 'out', 'dp_step3_validate');
if ~exist(outDir, 'dir'), mkdir(outDir); end
set(groot, 'defaultAxesFontName', 'Malgun Gothic', 'defaultTextFontName', 'Malgun Gothic');
tRun = datetime('now');
tic;

L = kre_lib();
P = L.params();
S = load(fullfile(here, '..', 'out', 'dp_step1_train', 'calib_2023.mat'));
calibN = S.calibN;  calibP = S.calibP;

years   = [2023 2024];
methods = ["천저 고정", "기존 방식(호우 표적)", "DP(위치고정)", "DP(나우캐스트)", "DP(완벽 정보, 상한)"];
mets    = ["호우 프로파일", "강수 프로파일", "호우 세포", "±3° 안 호우", "관측 표본", "전체 표본"];
nY = numel(years);  nM = numel(methods);  nK = numel(mets);
nDay  = 122;
tot   = zeros(nY, P.nPhase, nM, nK);            % 시즌 합계
band  = zeros(nY, nM, 3);                       % 각도대별 호우 표본 (위상 합)
dayH  = zeros(nY, nDay, nM);                    % 날짜별 호우 표본 (위상 합) → 부트스트랩용
ubTot = zeros(nY, P.nPhase);                    % 이론 상한
nPass = zeros(nY, P.nPhase);
nMove = zeros(nY, P.nPhase, 2);                 % 시즌 기동 횟수: [기존 방식 표적 수, DP(나우캐스트) 각도 변경 수]
rows  = {};

%% 시즌 반복
for iy = 1:nY
    D = L.loadSeason(years(iy));
    for ip = 1:P.nPhase
        passes = L.orbitPasses(D, P, ip);
        nPass(iy, ip) = numel(passes);
        for kp = 1:numel(passes)
            G = passes{kp};
            seed = years(iy) * 1e5 + ip * 1e4 + kp;          % 방식마다 같은 씨앗 → 같은 큐 오차
            plans = cell(1, nM);
            plans{1} = struct('cb', zeros(size(G.tq)), 'valid', true(size(G.tq)));
            plans{2} = L.greedyPlan(G, D, P, 'nowcast', RandStream('mt19937ar', 'Seed', seed));
            [Rw, th] = L.rewardGrid(G, D, P, 'persist', RandStream('mt19937ar', 'Seed', seed), calibP);
            plans{3} = L.dpPlan(Rw, th, P);
            [Rw, th] = L.rewardGrid(G, D, P, 'nowcast', RandStream('mt19937ar', 'Seed', seed), calibN);
            plans{4} = L.dpPlan(Rw, th, P);
            [Rw, th] = L.rewardGrid(G, D, P, 'oracle', [], []);
            plans{5} = L.dpPlan(Rw, th, P);
            r = zeros(nM, nK);
            iday = min(floor(G.ts / 86400) + 1, nDay);
            for m = 1:nM
                E = L.evaluate(G, D, P, plans{m});
                r(m, :) = [E.heavy, E.rain, E.cells, E.heavyNear, E.valid, E.n];
                band(iy, m, :) = band(iy, m, :) + reshape(E.heavyBand, [1 1 3]);
                dayH(iy, iday, m) = dayH(iy, iday, m) + E.heavy;
            end
            ub = L.heavyInSwath(G, D, P);
            nMove(iy, ip, :) = nMove(iy, ip, :) + reshape([plans{2}.nTargets, plans{4}.nMoves], [1 1 2]);
            tot(iy, ip, :, :) = tot(iy, ip, :, :) + reshape(r, [1 1 nM nK]);
            ubTot(iy, ip) = ubTot(iy, ip) + ub;
            tp = D.t0 + seconds(G.ts);
            rows(end + 1, :) = {years(iy), ip, kp, char(tp, 'yyyy-MM-dd HH:mm'), ub, r(1, 1), r(2, 1), r(3, 1), r(4, 1), r(5, 1)}; %#ok<SAGROW>
        end
        fprintf('%d년 궤도 위상 %d/%d 완료 (%.0f s)\n', years(iy), ip, P.nPhase, toc);
    end
end

%% 집계: 궤도 위상 8개 평균, 천저 대비 배수, 위상별 범위
mTot = squeeze(mean(tot, 2));                    % nY × nM × nK
gain = mTot ./ mTot(:, 1, :);
gH   = squeeze(tot(:, :, :, 1)) ./ squeeze(tot(:, :, 1, 1));   % nY × nPhase × nM (호우 배수)
gMin = squeeze(min(gH, [], 2));  gMax = squeeze(max(gH, [], 2));
ub   = mean(ubTot, 2);
fracOr = squeeze(mTot(:, 4, 1)) ./ squeeze(mTot(:, 5, 1));      % DP(나우캐스트)가 상한의 몇 %
movePerPass = squeeze(sum(nMove, 2)) ./ sum(nPass, 2);         % 통과당 기동 횟수 [기존, DP]
bandGain = band ./ band(:, 1, 1);                % 각도대별 호우 표본, 천저(0~3°) 전체 대비

% 날짜 단위 부트스트랩: 날짜를 복원추출해 '방식 합 ÷ 천저 합'을 2000번 다시 계산
rsB = RandStream('mt19937ar', 'Seed', 7);
ci = zeros(nY, nM, 2);
for iy = 1:nY
    X = squeeze(dayH(iy, :, :));                 % nDay × nM
    bs = zeros(2000, nM);
    for b = 1:2000
        pick = randi(rsB, nDay, nDay, 1);
        s = sum(X(pick, :), 1);
        bs(b, :) = s / s(1);
    end
    ci(iy, :, :) = reshape(prctile(bs, [2.5 97.5])', [1 nM 2]);
end

%% 화면 출력
for iy = 1:nY
    fprintf('\n[%d 장마, 시즌 통과 %.0f회, 위상 8개 평균]%s\n', years(iy), mean(nPass(iy, :)), ...
        ifelse(years(iy) == 2023, ' ← 학습한 해', ' ← 처음 보는 해(검증)'));
    fprintf('  %-22s %7s %7s %7s | %s\n', '방식', '호우', '강수', '호우세포', '호우 배수 (95% 신뢰구간) [위상 범위]  세포 배수');
    for m = 1:nM
        fprintf('  %-22s %7.0f %7.0f %7.1f | %.2f (%.2f~%.2f) [%.2f~%.2f]  %.2f\n', methods(m), mTot(iy, m, 1), ...
            mTot(iy, m, 2), mTot(iy, m, 3), gain(iy, m, 1), ci(iy, m, 1), ci(iy, m, 2), gMin(iy, m), gMax(iy, m), gain(iy, m, 3));
    end
    fprintf('  각도대별 호우 표본 (천저 전체 = 1): DP(나우캐스트) 0~3° %.2f, 3~6° %.2f, 6~10° %.2f\n', bandGain(iy, 4, :));
    fprintf('  이론 상한(기동 제약 없음): 천저의 %.2f배 | DP(나우캐스트)는 완벽 정보 DP의 %.0f%%\n', ...
        ub(iy) / mTot(iy, 1, 1), 100 * fracOr(iy));
    fprintf('  통과당 기동 횟수: 기존 방식 %.1f회, DP(나우캐스트) %.1f회\n', movePerPass(iy, 1), movePerPass(iy, 2));
end

%% 그림 1: 해별·방식별 호우 프로파일 배수 (오차 막대 = 95% 신뢰구간)
f = figure('Position', [100 100 1000 460], 'Color', 'w');
ax = axes(f);  hold(ax, 'on');  grid(ax, 'on');
Y = gain(:, 2:end, 1)';                          % (방식-천저) × 해
b = bar(ax, categorical(methods(2:end), methods(2:end)), Y, 'grouped');
for iy = 1:nY
    errorbar(ax, b(iy).XEndPoints, b(iy).YEndPoints, b(iy).YEndPoints - squeeze(ci(iy, 2:end, 1)), ...
        squeeze(ci(iy, 2:end, 2)) - b(iy).YEndPoints, 'k.', 'HandleVisibility', 'off');
    text(ax, b(iy).XEndPoints, b(iy).YEndPoints, compose('%.2f', b(iy).YData), ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', 'FontSize', 8);
end
yline(ax, 1, '-', '천저 고정', 'Color', [0.4 0.4 0.4], 'HandleVisibility', 'off');
ylabel(ax, '호우 프로파일 수, 천저 고정 대비 배수');
legend(ax, string(years) + [" (학습)", " (검증)"], 'Location', 'northwest');
title(ax, sprintf('지향 계획 방식별 표적화 이득 (±%d°, 큐 지연 %d분, 정착 %g s, 막대 = 95%% 신뢰구간)', P.maxDeg, P.cueL, P.settle));
exportgraphics(f, fullfile(outDir, 'fig_dp_gain.png'), 'Resolution', 150);

%% 그림 2: 각도대별로 나눈 호우 표본 (어느 각도에서 이득이 나오나)
f2 = figure('Position', [100 100 900 420], 'Color', 'w');
tl = tiledlayout(f2, 1, nY, 'TileSpacing', 'compact');
for iy = 1:nY
    ax = nexttile(tl);
    bar(ax, categorical(methods, methods), squeeze(band(iy, :, :)) / P.nPhase, 'stacked');
    grid(ax, 'on');  ylabel(ax, '시즌 호우 표본 (위상 평균)');  title(ax, sprintf('%d', years(iy)));
    if iy == nY, legend(ax, ["0~3°", "3~6°", "6~10°"], 'Location', 'northwest'); end
end
title(tl, '빔각대별 호우 표본: ±3° 안은 지표까지 정량, 그 밖은 하층 일부가 해면 반사에 가려짐');
exportgraphics(f2, fullfile(outDir, 'fig_dp_bands.png'), 'Resolution', 150);

%% 저장
fid = fopen(fullfile(outDir, 'summary.txt'), 'w', 'n', 'UTF-8');
fprintf(fid, 'DP 3단계 시즌 결과 (%s 실행, %.0f s)\n', string(tRun), toc);
fprintf(fid, '조건: 550 km·경사 45°, 관측창 북위 %g~%g°·동경 %g~%g°, ±%g°(격자 %g°), 기동 %g°/s, 정착 %g s, 큐 지연 %g분\n', ...
    P.winLat, P.winLon, P.maxDeg, P.stepDeg, P.slewRate, P.settle, P.cueL);
fprintf(fid, '큐: 큐 시각 전에 끝난 IMERG 30분 칸(관측보다 30~60분 앞선 장면), 호우 핵 인식 %.2f(못 알아보면 %.1f~%.1f배), 위치오차 %g km, 속도오차 %g m/s\n', ...
    P.pDet, P.weakFac, P.posSd, P.velSd * 1000);
fprintf(fid, '기존 방식 표적 기준 %g mm/h 이상, DP 보상 alpha %g, 학습 표 2023 (2024에 그대로 적용)\n', P.greedyThr, P.alpha);
fprintf(fid, '한계: 큐와 진실이 모두 IMERG Final(앞뒤 시간 보간 자료)이고 큐 오차 모델이 이상적이라 실제 운용보다 낙관적일 수 있다\n');
for iy = 1:nY
    fprintf(fid, '\n[%d, 시즌 통과 %.0f회]\n', years(iy), mean(nPass(iy, :)));
    fprintf(fid, '  방식, 호우, 강수, 호우세포, ±3°안호우, 관측표본, 호우배수, 95%%CI하한, 95%%CI상한, 위상최소, 위상최대, 세포배수\n');
    for m = 1:nM
        fprintf(fid, '  %s, %.1f, %.1f, %.1f, %.1f, %.1f, %.3f, %.3f, %.3f, %.3f, %.3f, %.3f\n', methods(m), mTot(iy, m, 1:5), ...
            gain(iy, m, 1), ci(iy, m, 1), ci(iy, m, 2), gMin(iy, m), gMax(iy, m), gain(iy, m, 3));
    end
    fprintf(fid, '  각도대별 호우 표본(천저 전체 = 1), DP(나우캐스트): 0~3° %.3f, 3~6° %.3f, 6~10° %.3f\n', bandGain(iy, 4, :));
    fprintf(fid, '  이론 상한 천저의 %.2f배, DP(나우캐스트)/완벽정보 DP = %.1f%%\n', ub(iy) / mTot(iy, 1, 1), 100 * fracOr(iy));
    fprintf(fid, '  통과당 기동 횟수: 기존 방식 %.2f, DP(나우캐스트) %.2f\n', movePerPass(iy, 1), movePerPass(iy, 2));
end
fclose(fid);

mt = table();
for iy = 1:nY
    for m = 1:nM
        mt = [mt; table(years(iy), methods(m), mTot(iy, m, 1), mTot(iy, m, 2), mTot(iy, m, 3), mTot(iy, m, 4), ...
            gain(iy, m, 1), ci(iy, m, 1), ci(iy, m, 2), gMin(iy, m), gMax(iy, m), gain(iy, m, 3), ...
            band(iy, m, 1) / P.nPhase, band(iy, m, 2) / P.nPhase, band(iy, m, 3) / P.nPhase, ...
            'VariableNames', {'year', 'method', 'heavyProf', 'rainProf', 'heavyCells', 'heavyWithin3deg', 'gainHeavy', ...
            'ci95Low', 'ci95High', 'gainHeavyMinPhase', 'gainHeavyMaxPhase', 'gainCells', 'heavy0to3deg', 'heavy3to6deg', 'heavy6to10deg'})]; %#ok<AGROW>
    end
end
writetable(mt, fullfile(outDir, 'methods.csv'), 'Encoding', 'UTF-8');
pt = cell2table(rows, 'VariableNames', {'year', 'phase', 'pass', 'startUTC', 'upperBoundHeavy', 'heavyNadir', ...
    'heavyGreedy', 'heavyDPpersist', 'heavyDPnowcast', 'heavyDPoracle'});
writetable(pt, fullfile(outDir, 'passes.csv'), 'Encoding', 'UTF-8');
key = struct('years', years, 'methods', methods, 'metrics', mets, 'passesPerSeason', mean(nPass, 2)', ...
    'meanTotals', mTot, 'gain', gain, 'ci95', ci, 'gainHeavyPhaseMin', gMin, 'gainHeavyPhaseMax', gMax, ...
    'heavyByBand', band / P.nPhase, 'upperBoundGain', (ub ./ mTot(:, 1, 1))', 'dpNowcastOverOracle', fracOr', ...
    'movesPerPassGreedyDP', movePerPass, 'params', rmfield(P, 'C'));
fid = fopen(fullfile(outDir, 'key_dp.json'), 'w', 'n', 'UTF-8');
fprintf(fid, '%s', jsonencode(key, 'PrettyPrint', true));
fclose(fid);
save(fullfile(outDir, 'results.mat'), 'years', 'methods', 'mets', 'tot', 'band', 'dayH', 'ci', 'ubTot', 'nPass', 'nMove', ...
    'mTot', 'gain', 'gMin', 'gMax', 'P', 'pt');
fid = fopen(fullfile(outDir, 'run_info.txt'), 'w', 'n', 'UTF-8');
fprintf(fid, '실행: %s (소요 %.0f s)\n스크립트: %s\nMATLAB: %s\n매개변수: %s\n', string(tRun), toc, ...
    mfilename('fullpath'), version, jsonencode(rmfield(P, 'C')));
fclose(fid);
logRun(fullfile(here, '..', 'out', 'run_log.csv'), tRun, mfilename, outDir, sprintf( ...
    'DP나우캐스트 호우 %.2f배(2023, CI %.2f~%.2f)/%.2f배(2024, CI %.2f~%.2f), 기존방식 %.2f/%.2f배, 완벽정보DP %.2f/%.2f배', ...
    gain(1, 4, 1), ci(1, 4, 1), ci(1, 4, 2), gain(2, 4, 1), ci(2, 4, 1), ci(2, 4, 2), gain(1, 2, 1), gain(2, 2, 1), ...
    gain(1, 5, 1), gain(2, 5, 1)));
fprintf('\n저장: %s (%.0f s)\n', outDir, toc);

function v = ifelse(c, a, b)
if c, v = a; else, v = b; end
end

function logRun(file, tRun, script, outDir, note)
isNew = ~exist(file, 'file');
fid = fopen(file, 'a', 'n', 'UTF-8');
if isNew, fwrite(fid, [239 187 191]); fprintf(fid, 'time,script,outDir,note\n'); end
fprintf(fid, '%s,%s,%s,"%s"\n', string(tRun, 'yyyy-MM-dd HH:mm:ss'), script, outDir, note);
fclose(fid);
end
