%% 09_check.m — k_raineye_analysis.m 검토 지적 확인 (문서 09, 5절)
% 저장된 결과(matlab/out/key_*.json, results.mat)를 읽어 식을 독립적으로 다시 계산해 비교한다.
% 원 스크립트는 다시 돌리지 않는다. 그림 없음, 60초 안에 끝남.
% PASS = 코드가 의도대로 동작함, FAIL = 지적이 맞음.
root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
outDir = fullfile(root, 'matlab', 'out');
K  = jsondecode(fileread(fullfile(outDir, 'key_results.json')));
KN = jsondecode(fileread(fullfile(outDir, 'key_nlfm.json')));
KS = jsondecode(fileread(fullfile(outDir, 'key_sensitivity.json')));
M  = load(fullfile(outDir, 'results.mat'), 'mStat', 'orbStat', 'O');

c0 = 299792458;  fRad = 35.75e9;  lam = c0 / fRad;
Re = 6378.137;  mu = 398600.4418;  J2 = 1.08262668e-3;  h = 550;

%% CHECK 1: 안테나 이득 차 dG = 2*dG + 20log10(bw/bw0) 부호 (문제 없음 예상)
bw = [1.13, 70 * lam / 1.0];  G = [42.6, 49.2];
dG1 = 2 * (G(2) - G(1)) + 20 * log10(bw(2) / bw(1));
ok1 = abs(dG1 - K.sens.dG1m) < 1e-6 && dG1 > 0;
fprintf('CHECK 1: %s - dG(1 m) 재계산 %.3f dB vs json %.3f dB (양수 = 1 m가 유리, 코드는 d에서 뺌)\n', ...
    tf(ok1), dG1, K.sens.dG1m);

%% CHECK 2: 감도 중심값 네 항 재계산, 대역 보정 부호 (문제 없음 예상)
Vg = Re * sqrt(mu / (Re + h)^3);  fp = 2 * h * tand(1.13 / 2);  Tfp = fp / Vg;
Tref = 7.9 / (Re * sqrt(mu / (Re + 400)^3));
PRF0 = 1 / 1660e-6;
terms = [20 * log10(h / 400), -5 * log10(1800 / PRF0), -5 * log10(Tfp / Tref), 5 * log10(1.2e6 / 2.5e6)];
Zc = 11 + sum(terms);
ok2 = abs(Zc - K.sens.central) < 1e-6 && terms(4) < 0;
fprintf('CHECK 2: %s - 중심값 11 %+.2f %+.2f %+.2f %+.2f = %.3f dBZ vs json %.3f (대역 보정 빼면 %.2f)\n', ...
    tf(ok2), terms, Zc, K.sens.central, Zc - terms(4));

%% CHECK 3: ITU-R P.838-3 계수(연직 경로)와 감쇠·못 보는 높이 재계산 (문제 없음 예상)
kH = p838k(fRad / 1e9, [-5.33980 -0.35351 -0.23789 -0.94158], [-0.10008 1.26970 0.86036 0.64552], ...
    [1.13098 0.45400 0.15354 0.16817], -0.18961, 0.71147);
kV = p838k(fRad / 1e9, [-3.80595 -3.44965 -0.39902 0.50167], [0.56934 -0.22911 0.73042 1.07319], ...
    [0.81061 0.51059 0.11899 0.27195], -0.16398, 0.63297);
aH = p838a(fRad / 1e9, [-0.14318 0.29591 0.32177 -5.37610 16.1721], [1.82442 0.77564 0.63773 -0.96230 -3.29980], ...
    [-0.55187 0.19822 0.13164 1.47828 3.43990], 0.67849, -1.95537);
aV = p838a(fRad / 1e9, [-0.07771 0.56727 -0.20238 -48.2991 48.5833], [2.33840 0.95545 1.14520 0.791669 0.791459], ...
    [-0.76284 0.54039 0.26809 0.116226 0.116479], -0.053739, 0.83433);
kVert = (kH + kV) / 2;                       % 앙각 90°, 편파 항 cos²θ = 0
aVert = (kH * aH + kV * aV) / (2 * kVert);
Rr = K.rain.R(:)';  Hr = 4.5;
gam = 0.3452 * Rr.^0.8851;  PIA = 2 * gam * Hr;
Ztrue = 10 * log10(200 * Rr.^1.6);  hg = (0:0.05:Hr)';
lowest = zeros(size(Rr));
for k = 1:numel(Rr)
    Zm = Ztrue(k) - 2 * gam(k) * (Hr - hg);  v = find(Zm >= K.sens.central, 1);
    if isempty(v), lowest(k) = Hr; else, lowest(k) = hg(v); end
end
ok3 = abs(kVert / 0.3452 - 1) < 0.003 && abs(aVert / 0.8851 - 1) < 0.003 && ...
    max(abs(PIA - K.rain.PIA(:)')) < 1e-6 && max(abs(lowest - K.rain.lowest(:)')) < 1e-9;
fprintf('CHECK 3: %s - P.838-3 연직 k=%.4f a=%.4f (코드 0.3452/0.8851), PIA 20 mm/h %.1f dB, 못 보는 높이 %s km\n', ...
    tf(ok3), kVert, aVert, PIA(3), mat2str(lowest, 3));

%% CHECK 4: PRF 타이밍 재계산 + 중심값이 1.8 kHz(각도 73 %만 가능)를 가정 (개선 제안: FAIL = 지적 맞음)
win = (2 * 23e3 / c0 + 166e-6) * 1e6;  needPRI = win + 176;  prfMax = 1e6 / needPRI;
okCalc = abs(needPRI - K.prf.needPRI) < 1e-6 && abs(prfMax - K.prf.prfMax) < 1e-6;
Zc1500 = K.sens.central + 5 * log10(1800 / 1500);
issue4 = okCalc && K.prf.f18 < 1 && K.prf.f15 >= 1;
fprintf('CHECK 4: %s - 필요 PRI %.1f us, 최대 PRF %.3f kHz (json 일치 %d); 1.8 kHz 가능 비율 %.0f%%인데 중심값은 1.8 kHz 가정, 1.5 kHz면 %.2f dBZ\n', ...
    tf(~issue4), needPRI, prfMax / 1e3, okCalc, 100 * K.prf.f18, Zc1500);

%% CHECK 5: 그림 7 요구선 -60 dB vs 14절 요구 부엽 (개선 제안: FAIL = 지적 맞음)
iD = find(strcmp(KN.designs, 'LFM 테이퍼 + 부정합 필터'));
need15 = KN.need(1, iD);
issue5 = abs(need15 - (-60)) > 1;
fprintf('CHECK 5: %s - 14절 요구 부엽 %.1f dB (= -(%.1f - %.1f)), 그림 7 선은 -60 dB\n', ...
    tf(~issue5), need15, KN.Zsurf, KN.Zmin(1, iD));

%% CHECK 6: 해면 상당 반사도 250 m 기준 → 175 m 기준이면 여유 변화 (개선 제안: FAIL = 지적 맞음)
Zs250 = 10 * log10(10^(10 / 10) / 250 * lam^4 / (pi^5 * 0.88) * 1e18);
Zs175 = Zs250 + 10 * log10(250 / KN.res(1, iD));
margin175 = KN.margin(1, iD) - (Zs175 - Zs250);
issue6 = abs(Zs250 - KN.Zsurf) < 1e-6 && (KN.margin(1, iD) - margin175) > 1;
fprintf('CHECK 6: %s - Zsurf 재계산 %.2f dBZ (json %.2f); 해상도 %.0f m 기준이면 %.2f dBZ, 채택안 여유 %+.2f -> %+.2f dB\n', ...
    tf(~issue6), Zs250, KN.Zsurf, KN.res(1, iD), Zs175, KN.margin(1, iD), margin175);

%% CHECK 7: 저장 키·값 교차 대조 (문제 없음 예상)
dwellFromPass = M.mStat(1, 2) * M.mStat(1, 3) / (M.O.days * 60);     % 통과 수 × 통과 시간 → 분/일
a = Re + h;  n = sqrt(mu / a^3);  kk = J2 * (Re / a)^2;
incSSO = acosd(-(2 * pi / (365.2422 * 86400)) / (1.5 * n * kk));
lossChk = KN.Zmin(1, iD) - K.sens.central;
ok7 = abs(dwellFromPass / M.mStat(1, 1) - 1) < 0.02 && abs(incSSO - M.O.inc(2)) < 1e-6 && ...
    abs(lossChk - KN.loss(1, iD)) < 1e-6 && abs(KS.gainHeavy(end) - 1.51) < 0.01 && abs(KS.gainQuant(end) - 1.54) < 0.01 && ...
    abs(K.sens.meet13_05 - 15 / 16) < 1e-9 && abs(K.orbit.dwell(1) - M.mStat(1, 1)) < 1e-9;
fprintf('CHECK 7: %s - 체류 %.2f vs 통과×시간 %.2f 분/일, SSO 경사 %.2f°, Zmin-Zc = %.2f dB = loss, 마지막 행 호우 %.2f·정량 %.2f, 13 dBZ 충족 %d/16\n', ...
    tf(ok7), M.mStat(1, 1), dwellFromPass, incSSO, lossChk, KS.gainHeavy(end), KS.gainQuant(end), round(16 * K.sens.meet13_05));

%% CHECK 8: run_log.csv에 이 파일의 실행 줄이 있는가 (개선 제안: FAIL = 지적 맞음)
logTxt = '';
if exist(fullfile(outDir, 'run_log.csv'), 'file'), logTxt = fileread(fullfile(outDir, 'run_log.csv')); end
hasLine = contains(logTxt, 'k_raineye_analysis');
fprintf('CHECK 8: %s - run_log.csv에 k_raineye_analysis 줄 %s\n', tf(hasLine), ifelse(hasLine, '있음', '없음'));

%% ---- 보조 함수
function s = tf(ok)
if ok, s = 'PASS'; else, s = 'FAIL'; end
end

function s = ifelse(c, a, b)
if c, s = a; else, s = b; end
end

function k = p838k(f, a, b, c, mk, ck)
% ITU-R P.838-3 (3)식: log10 k = sum a_j exp(-((log10 f - b_j)/c_j)^2) + m_k log10 f + c_k
lf = log10(f);
k = 10^(sum(a .* exp(-((lf - b) ./ c).^2)) + mk * lf + ck);
end

function al = p838a(f, a, b, c, ma, ca)
% ITU-R P.838-3 (4)식: alpha = sum a_j exp(-((log10 f - b_j)/c_j)^2) + m_a log10 f + c_a
lf = log10(f);
al = sum(a .* exp(-((lf - b) ./ c).^2)) + ma * lf + ca;
end
