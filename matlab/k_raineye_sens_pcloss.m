%% 감도 예산 다시 보기: 펄스압축 손실까지 넣은 16가지 조합과 감쇠 높이
% 왜 필요한가
%   k_raineye_analysis.m(모의 2)의 감도 16가지 조합(중심값 9.0 dBZ)은 펄스압축 손실을 넣기 전 값이다.
%   채택한 파형(LFM 20% 테이퍼 + 최소제곱 부정합 필터, 166 µs·0.5 m)은 손실이 약 1.49 dB라서
%   제안서 대표 감도는 10.5 dBZ다(out/key_nlfm.json). 16가지 조합과 감쇠 높이를 같은 기준으로 맞춘다.
% 식은 k_raineye_analysis.m 7~9절과 같다(그 파일의 해당 부분을 그대로 옮김).
% 결과: out/sens_pcloss_15/ 에 summary.txt, key_sens_pcloss.json, run_info.txt, out/run_log.csv 에 한 줄 추가

clear;
here = fileparts(mfilename('fullpath'));
outDir = fullfile(here, 'out', 'sens_pcloss_15');   % 2026-11-01: 요구 15 dBZ 집계 추가 (13 dBZ 집계도 함께 남김)
if ~exist(outDir, 'dir'), mkdir(outDir); end
tRun = datetime('now');

C = struct('Re', 6378.137, 'mu', 398600.4418);
O.h = 550;
K = jsondecode(fileread(fullfile(here, 'out', 'key_nlfm.json')));
iDes = find(strcmp(K.designs, 'LFM 테이퍼 + 부정합 필터'));
lossPC = K.loss(1, iDes);                         % 채택안 손실 [dB] (설정 1: 166 µs, 0.5 m)
Zadopt = K.Zmin(1, iDes);                         % 채택안 감도 [dBZ] (제안서 10.5 dBZ)

% ---- 감도 16가지 조합 (k_raineye_analysis.m 7절과 같은 식)
c0 = 299792458;  fRad = 35.75e9;  lam = c0 / fRad;
Vg   = C.Re * sqrt(C.mu / (C.Re + O.h)^3);
fpKm = 2 * O.h * tand(1.13 / 2);
Tfp  = fpKm / Vg;
Ref.R = 400;  Ref.PRF = 1 / 1660e-6;  Ref.B = 2.5e6;  Ref.Zs = [11.0 13.0];
Ref.Ts = [0.28, 7.9 / (C.Re * sqrt(C.mu / (C.Re + 400)^3))];
ant.bw = [1.13, 70 * lam / 1.0];  ant.G = [42.6, 49.2];
ant.dG = 2 * (ant.G - ant.G(1)) + 20 * log10(ant.bw / ant.bw(1));
PRFk = [1500 1800];  Bnew = 1.2e6;
sens = zeros(0, 6);
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
s05 = sens(sens(:, 5) == 1, 6) + lossPC;          % 펄스압축 손실 포함
s10 = sens(sens(:, 5) == 2, 6) + lossPC;
assert(abs(Zc + lossPC - Zadopt) < 0.05, '중심값 + 손실이 채택안 감도와 다르다');

% ---- 감쇠로 못 보는 맨 아래 높이 (k_raineye_analysis.m 9절과 같은 식, 감도만 바꿈)
kR = 0.3452;  aR = 0.8851;  Rr = [5 10 20 30 50];  Hr = 4.5;
gam = kR * Rr.^aR;  hg = (0:0.05:Hr)';  Ztrue = 10 * log10(200 * Rr.^1.6);
lowestAt = @(Zth) arrayfun(@(k) firstVis(Ztrue(k) - 2 * gam(k) * (Hr - hg), Zth, hg, Hr), 1:numel(Rr));
low90 = lowestAt(Zc);  low105 = lowestAt(Zadopt);

fid = fopen(fullfile(outDir, 'summary.txt'), 'w', 'n', 'UTF-8');
fprintf(fid, '감도 예산 (펄스압축 손실 포함) %s\n', string(tRun));
fprintf(fid, '채택 파형: LFM 테이퍼 + 부정합 필터, 손실 %.2f dB, 감도 %.2f dBZ (중심값 %.2f + 손실)\n', lossPC, Zadopt, Zc);
fprintf(fid, '0.5 m 안테나 16가지 조합: %.1f ~ %.1f dBZ, 요구 15 dBZ 이하 %d/%d개, (참고) 13 dBZ 이하 %d/%d개\n', min(s05), max(s05), nnz(s05 <= 15), numel(s05), nnz(s05 <= 13), numel(s05));
fprintf(fid, '요구 15 dBZ 대비 여유: 대표 %.1f dB, 최악 조합 %.1f dB\n', 15 - Zadopt, 15 - max(s05));
fprintf(fid, '(참고) 1 m 안테나 16가지 조합: %.1f ~ %.1f dBZ, 15 dBZ 이하 %d/%d개\n', min(s10), max(s10), nnz(s10 <= 15), numel(s10));
fprintf(fid, '감쇠로 못 보는 맨 아래 높이 [km] (강우율 %s mm/h): 감도 %.1f dBZ %s | 감도 %.1f dBZ %s\n', mat2str(Rr), ...
    Zc, mat2str(round(low90, 2)), Zadopt, mat2str(round(low105, 2)));
fprintf(fid, '\n조합, 기준반사도, 기준적분[s], PRF, 대역보정, 안테나(1=0.5m), 감도(손실포함)\n');
for k = 1:size(sens, 1)
    fprintf(fid, '%d, %.1f, %.3f, %d, %d, %d, %.2f\n', k, sens(k, 1:5), sens(k, 6) + lossPC);
end
fclose(fid);
key = struct('lossPC', lossPC, 'Zadopt', Zadopt, 'Zcentral', Zc, 'Zreq', 15, 'range05', [min(s05) max(s05)], 'meet13_05', mean(s05 <= 13), ...
    'n13_05', nnz(s05 <= 13), 'n15_05', nnz(s05 <= 15), 'marginReq', 15 - Zadopt, 'marginWorst', 15 - max(s05), 'n15_10', nnz(s10 <= 15), 'range10', [min(s10) max(s10)], 'R', Rr, 'lowestAt90', low90, 'lowestAtAdopt', low105);
fid = fopen(fullfile(outDir, 'key_sens_pcloss.json'), 'w', 'n', 'UTF-8');  fprintf(fid, '%s', jsonencode(key, 'PrettyPrint', true));  fclose(fid);
fid = fopen(fullfile(outDir, 'run_info.txt'), 'w', 'n', 'UTF-8');
fprintf(fid, '실행: %s\n스크립트: %s\nMATLAB: %s\n', string(tRun), mfilename('fullpath'), version);  fclose(fid);
lf = fullfile(here, 'out', 'run_log.csv');
fid = fopen(lf, 'a', 'n', 'UTF-8');
fprintf(fid, '%s,%s,%s,"%s"\n', string(tRun, 'yyyy-MM-dd HH:mm:ss'), mfilename, outDir, sprintf( ...
    '손실포함 감도 %.1f dBZ, 0.5m 16조합 %.1f~%.1f dBZ (요구 15 이하 %d/16, 13 이하 %d/16), 20·30 mm/h 못 보는 높이 %.2f/%.2f km', ...
    Zadopt, min(s05), max(s05), nnz(s05 <= 15), nnz(s05 <= 13), low105(Rr == 20), low105(Rr == 30)));
fclose(fid);
fprintf('감도 %.2f dBZ, 16조합 %.1f~%.1f dBZ (13 이하 %d/16), 1 m %.1f~%.1f | 못 보는 높이 20 mm/h %.2f→%.2f km, 30 mm/h %.2f→%.2f km\n', ...
    Zadopt, min(s05), max(s05), nnz(s05 <= 13), min(s10), max(s10), low90(Rr == 20), low105(Rr == 20), low90(Rr == 30), low105(Rr == 30));

function h = firstVis(Zm, Zth, hg, Hr)
vis = Zm >= Zth;
if any(vis), h = hg(find(vis, 1)); else, h = Hr; end
end
