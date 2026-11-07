%% DP 지향 계획 4b단계 upstream: 임무 관측창(장마 상류 바다)만으로 다시 계산
% 왜 필요한가
%   4단계는 서해~동해를 넓게 잡은 상자(북위 28.5~39.5°·동경 119.5~131.5°, 한반도·동해 일부 포함)에서 계산했다.
%   제안서의 임무 관측창은 장마 상류 바다(북위 28~38°·동경 119~127°)다. 같은 방법으로 이 창만 다시 센다.
% 그대로 두는 것: 큐(IMERG Early)·채점(IMERG Final), 학습 표(4단계의 2023 표 그대로 — 표는 해역과 무관하게
%   영역 전체 칸으로 배웠다), 궤도 위상·씨앗, 기동·정착·큐 지연. 바뀌는 것: 관측창(통과 구간)만.
% 먼저 1단계와 4단계를 돌려 calib_2023.mat, calib_early_2023.mat 이 있어야 한다. 전체 약 8분.
% 결과: ../out/dp_step4b_upstream 에 summary.txt, key_upstream.json, methods.csv, results.mat, run_info.txt
%       ../out/run_log.csv 에 한 줄 추가

clear; close all;
here = fileparts(mfilename('fullpath'));
outDir = fullfile(here, '..', 'out', 'dp_step4b_upstream');
if ~exist(outDir, 'dir'), mkdir(outDir); end
tRun = datetime('now');
tic;

L = kre_lib();
P = L.params();
P.winLat = [28 38];  P.winLon = [119 127];       % 임무 관측창 (장마 상류 바다)
Pe = P;  Pe.pDet = 1;  Pe.posSd = 0;  Pe.velSd = 0;
S = load(fullfile(here, '..', 'out', 'dp_step1_train', 'calib_2023.mat'));         calibF = S.calibN;
S = load(fullfile(here, '..', 'out', 'dp_step4_realistic', 'calib_early_2023.mat')); calibE = S.calibE;

years   = [2023 2024 2025];
methods = ["천저 고정", "기존 방식(Early 큐)", "DP 나우캐스트(Early 큐)", "DP 나우캐스트(Final 큐, 3단계)", "DP 완벽 정보(상한)"];
iMain = 3;
nY = numel(years);  nM = numel(methods);  nDay = 122;
tot  = zeros(nY, P.nPhase, nM, 3);              % [호우 프로파일, 강수 프로파일, 호우 세포]
dayH = zeros(nY, nDay, nM);
nPass = zeros(nY, P.nPhase);

for iy = 1:nY
    Df = L.loadSeason(years(iy), 'final');
    De = L.loadSeason(years(iy), 'early');
    DfE = L.attachCue(Df, De);
    clear De;
    for ip = 1:P.nPhase
        passes = L.orbitPasses(Df, P, ip);
        nPass(iy, ip) = numel(passes);
        for kp = 1:numel(passes)
            G = passes{kp};
            seed = years(iy) * 1e5 + ip * 1e4 + kp;
            plans = cell(1, nM);
            plans{1} = struct('cb', zeros(size(G.tq)), 'valid', true(size(G.tq)));
            plans{2} = L.greedyPlan(G, DfE, Pe, 'nowcast', RandStream('mt19937ar', 'Seed', seed));
            [Rw, th] = L.rewardGrid(G, DfE, Pe, 'nowcast', RandStream('mt19937ar', 'Seed', seed), calibE);
            plans{3} = L.dpPlan(Rw, th, P);
            [Rw, th] = L.rewardGrid(G, Df, P, 'nowcast', RandStream('mt19937ar', 'Seed', seed), calibF);
            plans{4} = L.dpPlan(Rw, th, P);
            [Rw, th] = L.rewardGrid(G, Df, P, 'oracle', [], []);
            plans{5} = L.dpPlan(Rw, th, P);
            iday = min(floor(G.ts / 86400) + 1, nDay);
            for m = 1:nM
                E = L.evaluate(G, Df, P, plans{m});
                tot(iy, ip, m, :) = tot(iy, ip, m, :) + reshape([E.heavy, E.rain, E.cells], [1 1 1 3]);
                dayH(iy, iday, m) = dayH(iy, iday, m) + E.heavy;
            end
        end
        fprintf('%d년 궤도 위상 %d/%d 완료 (%.0f s)\n', years(iy), ip, P.nPhase, toc);
    end
    clear Df DfE;
end

mTot = squeeze(mean(tot, 2));                    % nY × nM × 3
gain = mTot ./ mTot(:, 1, :);
ci = zeros(nY, nM, 2);
for iy = 1:nY
    rs = RandStream('mt19937ar', 'Seed', 300 + years(iy));
    X = squeeze(dayH(iy, :, :));
    bs = zeros(2000, nM);
    for b = 1:2000
        s = sum(X(randi(rs, nDay, nDay, 1), :), 1);
        bs(b, :) = s / s(1);
    end
    ci(iy, :, :) = reshape(prctile(bs, [2.5 97.5])', [1 nM 2]);
end

fprintf('\n임무 관측창(북위 %g~%g°·동경 %g~%g°) 기준, 위상 8개 평균\n', P.winLat, P.winLon);
for iy = 1:nY
    fprintf('[%d, 통과 %.0f회]\n', years(iy), mean(nPass(iy, :)));
    for m = 1:nM
        fprintf('  %-28s 호우 %6.1f  강수 %7.1f | 호우 배수 %.2f (%.2f~%.2f)  세포 배수 %.2f\n', methods(m), mTot(iy, m, 1), ...
            mTot(iy, m, 2), gain(iy, m, 1), ci(iy, m, 1), ci(iy, m, 2), gain(iy, m, 3));
    end
end

fid = fopen(fullfile(outDir, 'summary.txt'), 'w', 'n', 'UTF-8');
fprintf(fid, 'DP 4b단계: 임무 관측창만 (%s 실행, %.0f s)\n', string(tRun), toc);
fprintf(fid, '관측창: 북위 %g~%g°·동경 %g~%g° (장마 상류 바다). 그 밖의 조건은 4단계와 같음 (큐 Early·채점 Final, 학습 2023 → 2024·2025 검증)\n', P.winLat, P.winLon);
for iy = 1:nY
    fprintf(fid, '\n[%d, 시즌 통과 %.0f회]\n  방식, 호우, 강수, 호우세포, 호우배수, 95%%CI하한, 95%%CI상한, 세포배수\n', years(iy), mean(nPass(iy, :)));
    for m = 1:nM
        fprintf(fid, '  %s, %.1f, %.1f, %.1f, %.3f, %.3f, %.3f, %.3f\n', methods(m), mTot(iy, m, 1:3), gain(iy, m, 1), ...
            ci(iy, m, 1), ci(iy, m, 2), gain(iy, m, 3));
    end
end
fclose(fid);
mt = table();
for iy = 1:nY
    for m = 1:nM
        mt = [mt; table(years(iy), methods(m), mTot(iy, m, 1), mTot(iy, m, 2), mTot(iy, m, 3), gain(iy, m, 1), ...
            ci(iy, m, 1), ci(iy, m, 2), gain(iy, m, 3), 'VariableNames', ...
            {'year', 'method', 'heavyProf', 'rainProf', 'heavyCells', 'gainHeavy', 'ci95Low', 'ci95High', 'gainCells'})]; %#ok<AGROW>
    end
end
writetable(mt, fullfile(outDir, 'methods.csv'), 'Encoding', 'UTF-8');
key = struct('window', struct('lat', P.winLat, 'lon', P.winLon), 'years', years, 'methods', methods, ...
    'passesPerSeason', mean(nPass, 2)', 'meanTotals', mTot, 'gain', gain, 'ci95', ci, 'params', rmfield(P, 'C'));
fid = fopen(fullfile(outDir, 'key_upstream.json'), 'w', 'n', 'UTF-8');
fprintf(fid, '%s', jsonencode(key, 'PrettyPrint', true));
fclose(fid);
save(fullfile(outDir, 'results.mat'), 'years', 'methods', 'tot', 'dayH', 'mTot', 'gain', 'ci', 'nPass', 'P', 'Pe');
fid = fopen(fullfile(outDir, 'run_info.txt'), 'w', 'n', 'UTF-8');
fprintf(fid, '실행: %s (소요 %.0f s)\n스크립트: %s\nMATLAB: %s\n매개변수: %s\n', string(tRun), toc, ...
    mfilename('fullpath'), version, jsonencode(rmfield(P, 'C')));
fclose(fid);
logRun(fullfile(here, '..', 'out', 'run_log.csv'), tRun, mfilename, outDir, sprintf( ...
    '임무 관측창(28~38N 119~127E) Early큐 DP 호우 %.2f/%.2f/%.2f배(2023/2024/2025), Final큐 %.2f/%.2f/%.2f배, 기존방식 %.2f/%.2f/%.2f배', ...
    gain(1, iMain, 1), gain(2, iMain, 1), gain(3, iMain, 1), gain(1, 4, 1), gain(2, 4, 1), gain(3, 4, 1), ...
    gain(1, 2, 1), gain(2, 2, 1), gain(3, 2, 1)));
fprintf('\n저장: %s (%.0f s)\n', outDir, toc);

function logRun(file, tRun, script, outDir, note)
isNew = ~exist(file, 'file');
fid = fopen(file, 'a', 'n', 'UTF-8');
if isNew, fwrite(fid, [239 187 191]); fprintf(fid, 'time,script,outDir,note\n'); end
fprintf(fid, '%s,%s,%s,"%s"\n', string(tRun, 'yyyy-MM-dd HH:mm:ss'), script, outDir, note);
fclose(fid);
end
