%% DP 지향 계획 4단계: 큐를 IMERG Early(거친 빠른판)로 바꿔도 이득이 남나 — 2023 학습, 2024·2025 검증
% 왜 필요한가
%   3단계(dp_step3_validate)는 큐와 채점(진실)에 둘 다 IMERG Final을 썼다. Final은 앞뒤 시간 자료를 모두 쓰고
%   우량계로 보정한 정밀판이라, 큐가 실제 운용보다 정확했다(정답지를 조금 보고 시험 본 셈 → 낙관적).
%   여기서는 큐만 IMERG Early로 바꾼다. Early는 그 시각까지의 위성 자료만 쓰고 월별 우량계 보정 대신
%   기후 평균 보정만 해서, 운용 때 쓸 수 있는 실시간 위성 강수 추정에 가깝게 거칠다. 채점은 그대로 Final로 한다.
% 바꾸는 것 / 그대로 두는 것
%   바뀜  : 큐 장면(어디에 비가 있다고 알려 주는 지도)과 그 장면으로 구한 이동 벡터 → Early
%   그대로: 궤도, ±10°, 기동 1.5°/s, 정착 4 s, 큐 지연 15분(관측 30~60분 전 장면), DP, 채점(Final), 궤도 위상·씨앗
%   Early 자체에 실제 오차가 들어 있으므로 3단계의 '가짜 큐 오차'(호우 핵 인식 0.72, 위치 3 km, 속도 2 m/s)는 끈다.
%   비교용으로 Early에 가짜 오차까지 더한 경우(더 비관적)도 같이 낸다.
% 한계
%   Early는 실제로는 약 4시간 뒤에 나온다. 여기서는 '늦게 나오는 문제'가 아니라 '자료가 거친 문제'만 본다.
%   (운용 큐는 천리안 2A로 몇 분 안에 나온다.)
%   Early와 Final은 같은 위성 입력과 보정 방향을 일부 공유하므로, Final로 채점한 Early 큐 성능은
%   독립된 큐(천리안 2A 적외선)보다 좋게 나올 수 있다.
%   2023 Early는 2024-05에 다시 만든 재처리본, 2024·2025 Early는 약 4시간 뒤 만든 실시간본이다(파일 생성 시각 확인).
%   그래서 2023 → 2024·2025 차이에는 '처음 보는 해'와 '처리 계열 차이'가 섞인다.
% 검증 원칙: 학습 표는 2023으로만 만들고 2024·2025에 그대로 적용한다 (3단계와 같음).
% 먼저 1단계(dp_step1_train)를 돌려 ../out/dp_step1_train/calib_2023.mat 이 있어야 한다 (Final 큐 비교용).
% 처음 Early를 읽을 때 캐시·이동 벡터를 만드느라 해마다 몇 분 더 걸린다. 전체 약 15~25분.
% 결과: ../out/dp_step4_realistic 에 summary.txt, key_dp_early.json, methods.csv, results.mat, calib_early_2023.mat, 그림 3장, run_info.txt
%       ../out/run_log.csv 에 한 줄 추가

clear; close all;
here = fileparts(mfilename('fullpath'));
outDir = fullfile(here, '..', 'out', 'dp_step4_realistic');
if ~exist(outDir, 'dir'), mkdir(outDir); end
set(groot, 'defaultAxesFontName', 'Malgun Gothic', 'defaultTextFontName', 'Malgun Gothic');
tRun = datetime('now');
tic;

L = kre_lib();
P = L.params();                                  % 3단계와 같은 매개변수 (가짜 큐 오차 켜짐)
Pe = P;  Pe.pDet = 1;  Pe.posSd = 0;  Pe.velSd = 0;   % Early 큐: 가짜 오차 끔
S = load(fullfile(here, '..', 'out', 'dp_step1_train', 'calib_2023.mat'));
calibF = S.calibN;                               % Final 큐로 학습한 표 (3단계와 같은 것)

years   = [2023 2024 2025];                     % 2023 = 학습, 2024·2025 = 처음 보는 해(검증)
methods = ["천저 고정", "기존 방식(Early 큐)", "DP 위치고정(Early 큐)", "DP 나우캐스트(Early 큐)", ...
           "DP 나우캐스트(Early+가짜 오차)", "DP 나우캐스트(Final 큐, 3단계)", "DP 완벽 정보(상한)"];
iMain = 4;  iFin = 6;  iOr = 7;                  % 주 결과, 3단계 결과, 상한의 위치
mets    = ["호우 프로파일", "강수 프로파일", "호우 세포", "±3° 안 호우", "관측 표본", "전체 표본"];
nY = numel(years);  nM = numel(methods);  nK = numel(mets);
nDay  = 122;
tot   = zeros(nY, P.nPhase, nM, nK);
band  = zeros(nY, nM, 3);
dayH  = zeros(nY, nDay, nM);
nPass = zeros(nY, P.nPhase);
nMove = zeros(nY, P.nPhase);                    % DP 나우캐스트(Early 큐)의 각도 변경 수
agree = struct([]);

%% 1. 자료 읽기 + Early가 Final을 얼마나 맞히나 (같은 시각·같은 칸)
for iy = 1:nY
    Df = L.loadSeason(years(iy), 'final');
    De = L.loadSeason(years(iy), 'early');
    A = L.cueAgreement(Df, De, P);
    A.year = years(iy);
    agree = [agree, A]; %#ok<AGROW>
    fprintf('%d Early vs Final: 호우 칸 적중 %.0f%%, 헛경보 %.0f%% | 호우 핵 인식 %.0f%% (3단계 가짜 오차를 같은 기준으로 재면 %.0f%%) | 강수 칸 적중 %.0f%% | 강수량 비 %.2f\n', ...
        years(iy), 100 * A.podHeavy, 100 * A.farHeavy, 100 * A.coreDet, 100 * A.coreDetModel, 100 * A.podRain, A.bias);
    if iy == 1
        %% 2. 학습 (2023): "Early 큐에서 x mm/h로 보인 곳이 30·60분 뒤 Final에서 호우였던 비율"
        DfE = L.attachCue(Df, De);
        calibE  = L.calibrate(DfE, Pe, 'nowcast', 2023);   % 주 결과용
        calibEP = L.calibrate(DfE, Pe, 'persist', 2023);   % 위치고정용
        calibE2 = L.calibrate(DfE, P,  'nowcast', 2023);   % Early + 가짜 오차용
        save(fullfile(outDir, 'calib_early_2023.mat'), 'calibE', 'calibEP', 'calibE2', 'P', 'Pe');
        fprintf('학습 완료 (%.0f s)\n', toc);
        % 한 장면 예시용: 2023에서 Final 호우 칸이 가장 많았던 시각
        [~, kEx] = max(squeeze(sum(Df.Pr >= P.thrHeavy, [1 2])));
        ex = struct('F', Df.Pr(:, :, kEx), 'E', De.Pr(:, :, kEx), 't', Df.tSlot(kEx), 'lat', Df.lat, 'lon', Df.lon);
    end
    DfE = L.attachCue(Df, De);
    clear De;

    %% 3. 시즌 반복: 같은 궤도·같은 씨앗으로 7가지 방식을 채점 (진실 = Final)
    for ip = 1:P.nPhase
        passes = L.orbitPasses(Df, P, ip);
        nPass(iy, ip) = numel(passes);
        for kp = 1:numel(passes)
            G = passes{kp};
            seed = years(iy) * 1e5 + ip * 1e4 + kp;          % 3단계와 같은 씨앗
            plans = cell(1, nM);
            plans{1} = struct('cb', zeros(size(G.tq)), 'valid', true(size(G.tq)));
            plans{2} = L.greedyPlan(G, DfE, Pe, 'nowcast', RandStream('mt19937ar', 'Seed', seed));
            [Rw, th] = L.rewardGrid(G, DfE, Pe, 'persist', RandStream('mt19937ar', 'Seed', seed), calibEP);
            plans{3} = L.dpPlan(Rw, th, P);
            [Rw, th] = L.rewardGrid(G, DfE, Pe, 'nowcast', RandStream('mt19937ar', 'Seed', seed), calibE);
            plans{4} = L.dpPlan(Rw, th, P);
            [Rw, th] = L.rewardGrid(G, DfE, P, 'nowcast', RandStream('mt19937ar', 'Seed', seed), calibE2);
            plans{5} = L.dpPlan(Rw, th, P);
            [Rw, th] = L.rewardGrid(G, Df, P, 'nowcast', RandStream('mt19937ar', 'Seed', seed), calibF);
            plans{6} = L.dpPlan(Rw, th, P);
            [Rw, th] = L.rewardGrid(G, Df, P, 'oracle', [], []);
            plans{7} = L.dpPlan(Rw, th, P);
            r = zeros(nM, nK);
            iday = min(floor(G.ts / 86400) + 1, nDay);
            for m = 1:nM
                E = L.evaluate(G, Df, P, plans{m});
                r(m, :) = [E.heavy, E.rain, E.cells, E.heavyNear, E.valid, E.n];
                band(iy, m, :) = band(iy, m, :) + reshape(E.heavyBand, [1 1 3]);
                dayH(iy, iday, m) = dayH(iy, iday, m) + E.heavy;
            end
            nMove(iy, ip) = nMove(iy, ip) + plans{iMain}.nMoves;
            tot(iy, ip, :, :) = tot(iy, ip, :, :) + reshape(r, [1 1 nM nK]);
        end
        fprintf('%d년 궤도 위상 %d/%d 완료 (%.0f s)\n', years(iy), ip, P.nPhase, toc);
    end
    clear Df DfE;
end

%% 4. 집계: 궤도 위상 8개 평균, 천저 대비 배수, 날짜 단위 부트스트랩 95% 신뢰구간
mTot = squeeze(mean(tot, 2));                    % nY × nM × nK
gain = mTot ./ mTot(:, 1, :);
gH   = squeeze(tot(:, :, :, 1)) ./ squeeze(tot(:, :, 1, 1));
gMin = squeeze(min(gH, [], 2));  gMax = squeeze(max(gH, [], 2));
movePerPass = sum(nMove, 2) ./ sum(nPass, 2);
bandGain = band ./ band(:, 1, 1);
rsB = RandStream('mt19937ar', 'Seed', 7);
ci = zeros(nY, nM, 2);
ciRatio = zeros(nY, 2);                          % (Early 큐 DP) ÷ (Final 큐 DP)
ratio = squeeze(mTot(:, iMain, 1) ./ mTot(:, iFin, 1));
for iy = 1:nY
    X = squeeze(dayH(iy, :, :));
    bs = zeros(2000, nM);  br = zeros(2000, 1);
    for b = 1:2000
        pick = randi(rsB, nDay, nDay, 1);
        s = sum(X(pick, :), 1);
        bs(b, :) = s / s(1);
        br(b) = s(iMain) / s(iFin);
    end
    ci(iy, :, :) = reshape(prctile(bs, [2.5 97.5])', [1 nM 2]);
    ciRatio(iy, :) = prctile(br, [2.5 97.5]);
end
% 장마 호우는 며칠씩 이어지므로 날짜가 서로 독립이 아니다 → 연속 5일 묶음으로 다시 뽑은 신뢰구간도 같이 낸다
blk = 5;
ciBlk = zeros(nY, 2);  ciRatioBlk = zeros(nY, 2);
for iy = 1:nY
    rsBB = RandStream('mt19937ar', 'Seed', 100 + years(iy));  % 해마다 따로 (해를 더해도 다른 해 값이 안 바뀌게)
    X = squeeze(dayH(iy, :, :));
    bg = zeros(2000, 1);  br = zeros(2000, 1);
    for b = 1:2000
        st = randi(rsBB, nDay - blk + 1, ceil(nDay / blk), 1);
        pick = reshape((st + (0:blk - 1))', [], 1);   % 묶음 안의 5일이 이어지도록 행 방향으로 편다
        pick = pick(1:nDay);
        s = sum(X(pick, :), 1);
        bg(b) = s(iMain) / s(1);
        br(b) = s(iMain) / s(iFin);
    end
    ciBlk(iy, :) = prctile(bg, [2.5 97.5]);
    ciRatioBlk(iy, :) = prctile(br, [2.5 97.5]);
end

%% 5. 화면 출력
for iy = 1:nY
    fprintf('\n[%d 장마, 시즌 통과 %.0f회, 위상 8개 평균]%s\n', years(iy), mean(nPass(iy, :)), ...
        ifelse(years(iy) == 2023, ' ← 학습한 해', ' ← 처음 보는 해(검증)'));
    fprintf('  %-30s %7s %7s %7s | %s\n', '방식', '호우', '강수', '호우세포', '호우 배수 (95% 신뢰구간) [위상 범위]  세포 배수');
    for m = 1:nM
        fprintf('  %-30s %7.0f %7.0f %7.1f | %.2f (%.2f~%.2f) [%.2f~%.2f]  %.2f\n', methods(m), mTot(iy, m, 1), ...
            mTot(iy, m, 2), mTot(iy, m, 3), gain(iy, m, 1), ci(iy, m, 1), ci(iy, m, 2), gMin(iy, m), gMax(iy, m), gain(iy, m, 3));
    end
    fprintf('  Early 큐 DP ÷ Final 큐 DP = %.2f (%.2f~%.2f) → Final 큐 이득의 %.0f%%가 남음\n', ratio(iy), ciRatio(iy, :), ...
        100 * (gain(iy, iMain, 1) - 1) / (gain(iy, iFin, 1) - 1));
    fprintf('  5일 묶음 신뢰구간: Early 큐 DP 배수 %.2f~%.2f, Early÷Final %.2f~%.2f\n', ciBlk(iy, :), ciRatioBlk(iy, :));
    fprintf('  각도대별 호우 표본 (천저 전체 = 1), DP 나우캐스트(Early 큐): 0~3° %.2f, 3~6° %.2f, 6~10° %.2f\n', bandGain(iy, iMain, :));
    fprintf('  통과당 기동 횟수 (DP 나우캐스트, Early 큐): %.1f회\n', movePerPass(iy));
end

%% 6. 그림
% 그림 1: 방식별 호우 프로파일 배수 (오차 막대 = 95% 신뢰구간)
f = figure('Position', [100 100 1150 480], 'Color', 'w');
ax = axes(f);  hold(ax, 'on');  grid(ax, 'on');
Y = gain(:, 2:end, 1)';
b = bar(ax, categorical(methods(2:end), methods(2:end)), Y, 'grouped');
for iy = 1:nY
    errorbar(ax, b(iy).XEndPoints, b(iy).YEndPoints, b(iy).YEndPoints - squeeze(ci(iy, 2:end, 1)), ...
        squeeze(ci(iy, 2:end, 2)) - b(iy).YEndPoints, 'k.', 'HandleVisibility', 'off');
    text(ax, b(iy).XEndPoints, b(iy).YEndPoints, compose('%.2f', b(iy).YData), ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', 'FontSize', 8);
end
yline(ax, 1, '-', '천저 고정', 'Color', [0.4 0.4 0.4], 'HandleVisibility', 'off');
ylabel(ax, '호우 프로파일 수, 천저 고정 대비 배수');
lg = string(years) + " (검증)";  lg(1) = string(years(1)) + " (학습)";
legend(ax, lg, 'Location', 'northwest');
title(ax, sprintf('큐 자료별 표적화 이득: Early(거친 빠른판) vs Final(정밀판), 진실 = Final (±%d°, 큐 지연 %d분)', P.maxDeg, P.cueL));
exportgraphics(f, fullfile(outDir, 'fig_early_gain.png'), 'Resolution', 150);

% 그림 2: 학습 표 비교 — 같은 큐 강도라도 Early에서 본 것은 실제 호우일 확률이 얼마나 다른가
lo = P.edges(1:end - 1);  hi = P.edges(2:end);
lbl = compose('%g~%g', lo', hi');  lbl{end} = sprintf('%g 이상', lo(end));
f2 = figure('Position', [100 100 900 420], 'Color', 'w');
ax = axes(f2);  hold(ax, 'on');  grid(ax, 'on');
x = 1:numel(lo);
plot(ax, x, 100 * calibF.pHeavy(:, 1), '-o', 'LineWidth', 2, 'DisplayName', 'Final 큐 (3단계, 가짜 오차 포함)');
plot(ax, x, 100 * calibE.pHeavy(:, 1), '-s', 'LineWidth', 2, 'DisplayName', 'Early 큐');
plot(ax, x, 100 * calibE2.pHeavy(:, 1), '--^', 'LineWidth', 1.2, 'DisplayName', 'Early 큐 + 가짜 오차');
set(ax, 'XTick', x, 'XTickLabel', lbl);  xtickangle(ax, 30);
xlabel(ax, '큐 장면에서 보인 강도 [mm/h]');  ylabel(ax, '30분 뒤 실제(Final) 호우 비율 [%]');
title(ax, '2023 학습 표: 큐가 보여 준 강도 → 실제 호우 확률');
legend(ax, 'Location', 'northwest');
exportgraphics(f2, fullfile(outDir, 'fig_early_calib.png'), 'Resolution', 140);

% 그림 3: 한 장면 예시 — 같은 시각의 Final과 Early
f3 = figure('Position', [100 100 1000 430], 'Color', 'w');
tl = tiledlayout(f3, 1, 2, 'TileSpacing', 'compact');
cm = [1 1 1; parula(255)];
for s = 1:2
    ax = nexttile(tl);
    if s == 1, Z = ex.F; nm = 'Final (정밀판, 진실)'; else, Z = ex.E; nm = 'Early (빠른판, 큐)'; end
    imagesc(ax, ex.lon, ex.lat, Z);  axis(ax, 'xy');  axis(ax, 'image');
    colormap(ax, cm);  clim(ax, [0 30]);
    hold(ax, 'on');  contour(ax, ex.lon, ex.lat, double(Z >= P.thrHeavy), [0.5 0.5], 'r', 'LineWidth', 1);
    title(ax, nm);  xlabel(ax, '경도 [°E]');  ylabel(ax, '위도 [°N]');
end
cb = colorbar(ax);  cb.Label.String = '강수 강도 [mm/h] (빨간 선 = 10 mm/h 호우)';
title(tl, sprintf('같은 시각 %s UTC의 두 자료', string(ex.t, 'yyyy-MM-dd HH:mm')));
exportgraphics(f3, fullfile(outDir, 'fig_early_example.png'), 'Resolution', 140);

%% 7. 저장
fid = fopen(fullfile(outDir, 'summary.txt'), 'w', 'n', 'UTF-8');
fprintf(fid, 'DP 4단계 Early 큐 결과 (%s 실행, %.0f s)\n', string(tRun), toc);
fprintf(fid, '조건: 550 km·경사 45°, 관측창 북위 %g~%g°·동경 %g~%g°, ±%g°(격자 %g°), 기동 %g°/s, 정착 %g s, 큐 지연 %g분\n', ...
    P.winLat, P.winLon, P.maxDeg, P.stepDeg, P.slewRate, P.settle, P.cueL);
fprintf(fid, '큐: IMERG Early(3IMERGHHE V07)의, 큐 시각 전에 끝난 30분 칸 (관측보다 30~60분 앞선 장면), 이동 벡터도 Early로 계산. 가짜 큐 오차 끔\n');
fprintf(fid, '채점(진실): IMERG Final(3IMERGHH V07). 학습 표 2023 (2024·2025에 그대로 적용). 씨앗·궤도 위상은 3단계와 같음\n');
fprintf(fid, '한계: Early는 실제로 약 4시간 뒤 나오므로 여기서는 자료 품질만 본다 (운용 큐는 천리안 2A)\n');
fprintf(fid, '한계: Early와 Final은 위성 입력과 보정 방향을 일부 공유하므로, Final로 채점한 Early 큐 성능은 독립 큐보다 낙관적일 수 있다\n');
fprintf(fid, '한계: 2023 Early는 재처리본(2024-05 생성), 2024·2025 Early는 실시간본(약 4시간 뒤 생성)이라 해 사이 차이에 처리 계열 차이가 섞인다\n');
for iy = 1:nY
    A = agree(iy);
    fprintf(fid, '\n[%d Early vs Final, 같은 시각·같은 칸] 호우 칸 적중 %.3f, 헛경보 %.3f, CSI %.3f | 호우 핵 인식 %.3f (핵 %d개; 3단계 가짜 오차를 같은 기준으로 재면 %.3f, pDet %.2f) | 강수 칸 적중 %.3f, 헛경보 %.3f | 강수량 비 %.3f\n', ...
        years(iy), A.podHeavy, A.farHeavy, A.csiHeavy, A.coreDet, A.nCore, A.coreDetModel, P.pDet, A.podRain, A.farRain, A.bias);
end
for iy = 1:nY
    fprintf(fid, '\n[%d, 시즌 통과 %.0f회]\n', years(iy), mean(nPass(iy, :)));
    fprintf(fid, '  방식, 호우, 강수, 호우세포, ±3°안호우, 관측표본, 호우배수, 95%%CI하한, 95%%CI상한, 위상최소, 위상최대, 세포배수\n');
    for m = 1:nM
        fprintf(fid, '  %s, %.1f, %.1f, %.1f, %.1f, %.1f, %.3f, %.3f, %.3f, %.3f, %.3f, %.3f\n', methods(m), mTot(iy, m, 1:5), ...
            gain(iy, m, 1), ci(iy, m, 1), ci(iy, m, 2), gMin(iy, m), gMax(iy, m), gain(iy, m, 3));
    end
    fprintf(fid, '  Early 큐 DP / Final 큐 DP = %.3f (95%%CI %.3f~%.3f; 5일 묶음 %.3f~%.3f)\n', ratio(iy), ciRatio(iy, :), ciRatioBlk(iy, :));
    fprintf(fid, '  DP 나우캐스트(Early 큐) 호우 배수 5일 묶음 95%%CI %.3f~%.3f\n', ciBlk(iy, :));
    fprintf(fid, '  각도대별 호우 표본(천저 전체 = 1), DP 나우캐스트(Early 큐): 0~3° %.3f, 3~6° %.3f, 6~10° %.3f\n', bandGain(iy, iMain, :));
    fprintf(fid, '  DP 나우캐스트(Early 큐)/완벽정보 DP = %.1f%%, 통과당 기동 %.2f회\n', ...
        100 * mTot(iy, iMain, 1) / mTot(iy, iOr, 1), movePerPass(iy));
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
key = struct('years', years, 'methods', methods, 'metrics', mets, 'passesPerSeason', mean(nPass, 2)', ...
    'meanTotals', mTot, 'gain', gain, 'ci95', ci, 'gainHeavyPhaseMin', gMin, 'gainHeavyPhaseMax', gMax, ...
    'earlyOverFinalCue', ratio', 'earlyOverFinalCueCi95', ciRatio, 'earlyOverFinalCueCi95Block5', ciRatioBlk, ...
    'gainDPEarlyCi95Block5', ciBlk, 'heavyByBand', band / P.nPhase, ...
    'movesPerPassDPEarly', movePerPass', 'agreement', agree, 'params', rmfield(P, 'C'), 'paramsEarly', rmfield(Pe, 'C'));
fid = fopen(fullfile(outDir, 'key_dp_early.json'), 'w', 'n', 'UTF-8');
fprintf(fid, '%s', jsonencode(key, 'PrettyPrint', true));
fclose(fid);
save(fullfile(outDir, 'results.mat'), 'years', 'methods', 'mets', 'tot', 'band', 'dayH', 'ci', 'ciRatio', 'ratio', 'ciBlk', 'ciRatioBlk', ...
    'nPass', 'nMove', 'mTot', 'gain', 'gMin', 'gMax', 'agree', 'P', 'Pe');
fid = fopen(fullfile(outDir, 'run_info.txt'), 'w', 'n', 'UTF-8');
fprintf(fid, '실행: %s (소요 %.0f s)\n스크립트: %s\nMATLAB: %s\n매개변수: %s\nEarly 매개변수: %s\n', string(tRun), toc, ...
    mfilename('fullpath'), version, jsonencode(rmfield(P, 'C')), jsonencode(rmfield(Pe, 'C')));
fclose(fid);
logRun(fullfile(here, '..', 'out', 'run_log.csv'), tRun, mfilename, outDir, sprintf( ...
    'Early큐 DP 호우 %.2f배(2023, CI %.2f~%.2f)/%.2f배(2024, CI %.2f~%.2f)/%.2f배(2025, CI %.2f~%.2f), Final큐 DP %.2f/%.2f/%.2f배, Early+가짜오차 %.2f/%.2f/%.2f배, Early 호우핵 인식 %.2f/%.2f/%.2f', ...
    gain(1, iMain, 1), ci(1, iMain, 1), ci(1, iMain, 2), gain(2, iMain, 1), ci(2, iMain, 1), ci(2, iMain, 2), ...
    gain(3, iMain, 1), ci(3, iMain, 1), ci(3, iMain, 2), gain(1, iFin, 1), gain(2, iFin, 1), gain(3, iFin, 1), ...
    gain(1, 5, 1), gain(2, 5, 1), gain(3, 5, 1), agree(1).coreDet, agree(2).coreDet, agree(3).coreDet));
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
