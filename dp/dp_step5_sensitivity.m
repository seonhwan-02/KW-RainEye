%% DP 지향 계획 5단계 sensitivity: 정착 시간·큐 지연·기동 속도가 바뀌면 이득이 얼마나 변하나 (Early 큐)
% 왜 필요한가
%   위성 요구조건(정착 8초 이내, 큐 지연 30분 이내)이 실제로 버틸 만한 값인지 확인한다.
%   4단계(dp_step4_realistic)의 주 결과인 'DP 나우캐스트(Early 큐)' 하나만, 조건을 하나씩 바꿔 다시 계산한다.
% 조건
%   기준          : 정착 4 s, 큐 지연 15분, 기동 1.5°/s  (4단계와 같아야 한다 → 같은 숫자가 나오는지 확인)
%   정착 2 s / 8 s: 위성이 더 민첩할 때 / 반사판 흔들림이 커서 멈추는 데 오래 걸릴 때 (요구조건 상한 8 s)
%   큐 지연 30·45분: 천리안 처리와 명령 올리기가 늦을 때 (요구조건 상한 30분)
%   기동 1°/s     : 자세 제어가 느릴 때
%   지향 ±3°·±5° : 기울이는 범위를 좁히면 (처음 설계는 ±3°였다)
%   큐 지연이 바뀌면 큐 장면이 관측보다 몇 칸(30분) 앞서는지가 달라지므로, 학습 표를 나이 1~4칸으로 다시 만든다 (2023만).
% 검증 원칙: 학습은 2023만, 2024·2025는 처음 보는 해. 채점은 Final. 궤도 위상·씨앗은 4단계와 같다.
% 먼저 4단계를 돌려 ../out/dp_step4_realistic/calib_early_2023.mat 이 있어야 한다. 전체 약 15~20분.
% 결과: ../out/dp_step5_sensitivity 에 summary.txt, key_sensitivity.json, cases.csv, results.mat, 그림 1장, run_info.txt
%       ../out/run_log.csv 에 한 줄 추가

clear; close all;
here = fileparts(mfilename('fullpath'));
outDir = fullfile(here, '..', 'out', 'dp_step5_sensitivity');
if ~exist(outDir, 'dir'), mkdir(outDir); end
set(groot, 'defaultAxesFontName', 'Malgun Gothic', 'defaultTextFontName', 'Malgun Gothic');
tRun = datetime('now');
tic;

L = kre_lib();
P0 = L.params();
P0.pDet = 1;  P0.posSd = 0;  P0.velSd = 0;      % Early 큐: 가짜 오차 끔 (4단계 Pe와 같음)
S = load(fullfile(here, '..', 'out', 'dp_step4_realistic', 'calib_early_2023.mat'));
calib0 = S.calibE;                               % 기준 조건의 학습 표 (4단계와 같은 것)

% 조건 목록: 이름, 정착 [s], 큐 지연 [min], 기동 [deg/s], 지향 범위 ±[deg]
cs = struct('name', {'기준 (정착 4 s, 큐 15분)', '정착 2 s', '정착 8 s', '큐 지연 30분', '큐 지연 45분', '기동 1°/s', '지향 ±3°', '지향 ±5°'}, ...
            'settle', {4, 2, 8, 4, 4, 4, 4, 4}, 'cueL', {15, 15, 15, 30, 45, 15, 15, 15}, ...
            'slewRate', {1.5, 1.5, 1.5, 1.5, 1.5, 1, 1.5, 1.5}, 'maxDeg', {10, 10, 10, 10, 10, 10, 3, 5});
nC = numel(cs);
years = [2023 2024 2025];
nY = numel(years);  nDay = 122;
heavy = zeros(nY, P0.nPhase, nC);                % 시즌 호우 프로파일 (DP)
nadir = zeros(nY, P0.nPhase);                    % 천저 고정
dayH  = zeros(nY, nDay, nC);  dayN = zeros(nY, nDay);
nMove = zeros(nY, nC);  nPass = zeros(nY, 1);
calib = cell(1, nC);

for iy = 1:nY
    Df = L.loadSeason(years(iy), 'final');
    De = L.loadSeason(years(iy), 'early');
    D = L.attachCue(Df, De);
    clear De;
    if iy == 1
        % 학습: 큐 지연이 기준과 다른 조건만 나이 1~4칸 표를 새로 만든다
        for c = 1:nC
            if cs(c).cueL == 15
                calib{c} = calib0;
            else
                Pc = P0;  Pc.cueL = cs(c).cueL;  Pc.lags = 1:4;
                calib{c} = L.calibrate(D, Pc, 'nowcast', 2023);
            end
        end
        fprintf('학습 완료 (%.0f s)\n', toc);
    end
    for ip = 1:P0.nPhase
        passes = L.orbitPasses(D, P0, ip);
        nPass(iy) = nPass(iy) + numel(passes);
        for kp = 1:numel(passes)
            G = passes{kp};
            seed = years(iy) * 1e5 + ip * 1e4 + kp;           % 4단계와 같은 씨앗
            iday = min(floor(G.ts / 86400) + 1, nDay);
            E0 = L.evaluate(G, D, P0, struct('cb', zeros(size(G.tq)), 'valid', true(size(G.tq))));
            nadir(iy, ip) = nadir(iy, ip) + E0.heavy;
            dayN(iy, iday) = dayN(iy, iday) + E0.heavy;
            for c = 1:nC
                Pc = P0;  Pc.settle = cs(c).settle;  Pc.cueL = cs(c).cueL;  Pc.slewRate = cs(c).slewRate;  Pc.maxDeg = cs(c).maxDeg;
                if cs(c).cueL ~= 15, Pc.lags = 1:4; end
                [Rw, th] = L.rewardGrid(G, D, Pc, 'nowcast', RandStream('mt19937ar', 'Seed', seed), calib{c});
                plan = L.dpPlan(Rw, th, Pc);
                E = L.evaluate(G, D, Pc, plan);
                heavy(iy, ip, c) = heavy(iy, ip, c) + E.heavy;
                dayH(iy, iday, c) = dayH(iy, iday, c) + E.heavy;
                nMove(iy, c) = nMove(iy, c) + plan.nMoves;
            end
        end
        fprintf('%d년 궤도 위상 %d/%d 완료 (%.0f s)\n', years(iy), ip, P0.nPhase, toc);
    end
    clear Df D;
end

%% 집계: 위상 평균 배수와 날짜 단위 부트스트랩 95% 신뢰구간
gain = squeeze(sum(heavy, 2)) ./ sum(nadir, 2);  % nY × nC
ci = zeros(nY, nC, 2);
for iy = 1:nY
    rs = RandStream('mt19937ar', 'Seed', 200 + years(iy));
    bs = zeros(2000, nC);
    for b = 1:2000
        pick = randi(rs, nDay, nDay, 1);
        bs(b, :) = sum(squeeze(dayH(iy, pick, :)), 1) / sum(dayN(iy, pick));
    end
    ci(iy, :, :) = reshape(prctile(bs, [2.5 97.5])', [1 nC 2]);
end
movePerPass = nMove ./ nPass;
rel = gain ./ gain(:, 1);                        % 기준 조건 대비

fprintf('\n호우 프로파일 배수 (천저 고정 = 1), DP 나우캐스트(Early 큐)\n');
fprintf('  %-26s', '조건');  fprintf('  %14s', string(years) + ["(학습)", "(검증)", "(검증)"]);  fprintf('\n');
for c = 1:nC
    fprintf('  %-26s', cs(c).name);
    for iy = 1:nY, fprintf('  %4.2f (%.2f~%.2f)', gain(iy, c), ci(iy, c, 1), ci(iy, c, 2)); end
    fprintf('\n');
end

%% 그림: 조건별 배수 (오차 막대 = 95% 신뢰구간)
f = figure('Position', [100 100 1000 440], 'Color', 'w');
ax = axes(f);  hold(ax, 'on');  grid(ax, 'on');
names = string({cs.name});
b = bar(ax, categorical(names, names), gain', 'grouped');
for iy = 1:nY
    errorbar(ax, b(iy).XEndPoints, b(iy).YEndPoints, b(iy).YEndPoints - ci(iy, :, 1), ci(iy, :, 2) - b(iy).YEndPoints, ...
        'k.', 'HandleVisibility', 'off');
    text(ax, b(iy).XEndPoints, b(iy).YEndPoints, compose('%.2f', b(iy).YData), ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', 'FontSize', 8);
end
yline(ax, 1, '-', '천저 고정', 'Color', [0.4 0.4 0.4], 'HandleVisibility', 'off');
lg = string(years) + " (검증)";  lg(1) = string(years(1)) + " (학습)";
legend(ax, lg, 'Location', 'southwest');
ylabel(ax, '호우 프로파일 수, 천저 고정 대비 배수');
title(ax, 'DP 나우캐스트(Early 큐): 정착 시간·큐 지연·기동 속도에 따른 이득');
exportgraphics(f, fullfile(outDir, 'fig_sensitivity.png'), 'Resolution', 150);

%% 저장
fid = fopen(fullfile(outDir, 'summary.txt'), 'w', 'n', 'UTF-8');
fprintf(fid, 'DP 5단계 감도 결과 (%s 실행, %.0f s)\n', string(tRun), toc);
fprintf(fid, '방식: DP 나우캐스트, 큐 = IMERG Early(가짜 오차 끔), 채점 = IMERG Final, 학습 2023 → 2024·2025 검증, 궤도 위상 %d개 평균\n', P0.nPhase);
fprintf(fid, '바꾼 것: 정착 시간, 큐 지연(학습 표도 그 나이로 다시 만듦), 기동 속도, 지향 범위. 나머지는 4단계와 같음\n');
fprintf(fid, '조건, 정착[s], 큐지연[min], 기동[deg/s], 지향[±deg], %s\n', strjoin(compose('%d 배수, %d CI하한, %d CI상한, %d 기준대비, %d 통과당기동', ...
    repmat(years', 1, 5)), ', '));
for c = 1:nC
    fprintf(fid, '%s, %g, %g, %g, %g', cs(c).name, cs(c).settle, cs(c).cueL, cs(c).slewRate, cs(c).maxDeg);
    for iy = 1:nY
        fprintf(fid, ', %.3f, %.3f, %.3f, %.3f, %.2f', gain(iy, c), ci(iy, c, 1), ci(iy, c, 2), rel(iy, c), movePerPass(iy, c));
    end
    fprintf(fid, '\n');
end
fclose(fid);
ct = table();
for c = 1:nC
    for iy = 1:nY
        ct = [ct; table(string(cs(c).name), cs(c).settle, cs(c).cueL, cs(c).slewRate, cs(c).maxDeg, years(iy), gain(iy, c), ...
            ci(iy, c, 1), ci(iy, c, 2), rel(iy, c), movePerPass(iy, c), 'VariableNames', ...
            {'case', 'settle_s', 'cueLatency_min', 'slewRate_degps', 'maxDeg', 'year', 'gainHeavy', 'ci95Low', 'ci95High', ...
            'relToBaseline', 'movesPerPass'})]; %#ok<AGROW>
    end
end
writetable(ct, fullfile(outDir, 'cases.csv'), 'Encoding', 'UTF-8');
key = struct('years', years, 'cases', cs, 'gain', gain, 'ci95', ci, 'relToBaseline', rel, 'movesPerPass', movePerPass, ...
    'nadirHeavyPerSeason', (sum(nadir, 2) / P0.nPhase)', 'params', rmfield(P0, 'C'));
fid = fopen(fullfile(outDir, 'key_sensitivity.json'), 'w', 'n', 'UTF-8');
fprintf(fid, '%s', jsonencode(key, 'PrettyPrint', true));
fclose(fid);
save(fullfile(outDir, 'results.mat'), 'years', 'cs', 'heavy', 'nadir', 'dayH', 'dayN', 'gain', 'ci', 'rel', 'movePerPass', 'P0');
fid = fopen(fullfile(outDir, 'run_info.txt'), 'w', 'n', 'UTF-8');
fprintf(fid, '실행: %s (소요 %.0f s)\n스크립트: %s\nMATLAB: %s\n기준 매개변수: %s\n', string(tRun), toc, ...
    mfilename('fullpath'), version, jsonencode(rmfield(P0, 'C')));
fclose(fid);
ix = @(nm) find(strcmp({cs.name}, nm));
logRun(fullfile(here, '..', 'out', 'run_log.csv'), tRun, mfilename, outDir, sprintf( ...
    'Early큐 DP 호우 배수 2024/2025: 기준 %.2f/%.2f, 정착8s %.2f/%.2f, 큐30분 %.2f/%.2f, 큐45분 %.2f/%.2f, 기동1도/s %.2f/%.2f, ±3도 %.2f/%.2f, ±5도 %.2f/%.2f', ...
    gain(2, 1), gain(3, 1), gain(2, ix('정착 8 s')), gain(3, ix('정착 8 s')), gain(2, ix('큐 지연 30분')), gain(3, ix('큐 지연 30분')), ...
    gain(2, ix('큐 지연 45분')), gain(3, ix('큐 지연 45분')), gain(2, ix('기동 1°/s')), gain(3, ix('기동 1°/s')), ...
    gain(2, ix('지향 ±3°')), gain(3, ix('지향 ±3°')), gain(2, ix('지향 ±5°')), gain(3, ix('지향 ±5°'))));
fprintf('\n저장: %s (%.0f s)\n', outDir, toc);

function logRun(file, tRun, script, outDir, note)
isNew = ~exist(file, 'file');
fid = fopen(file, 'a', 'n', 'UTF-8');
if isNew, fwrite(fid, [239 187 191]); fprintf(fid, 'time,script,outDir,note\n'); end
fprintf(fid, '%s,%s,%s,"%s"\n', string(tRun, 'yyyy-MM-dd HH:mm:ss'), script, outDir, note);
fclose(fid);
end
