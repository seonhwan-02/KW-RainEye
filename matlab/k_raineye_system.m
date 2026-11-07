%% K-RainEye 시스템 기술 버짓 (시스템 구성(안)·개발 가능성용) — 12U 기준
% 2026-11-01: 16U → 12U로 바꿈. 전개 태양전지판 4장(12U 긴 면 크기), 질량표 12U, 레이더 가동은
%   '요구 10분/궤도'와 '운용 약 3분/궤도' 두 경우를 함께 계산하고, 한 궤도 안의 운용 모드 교대(관측→전송→충전) 시간표를 낸다.
%   16U 결과는 out/system_budget(2026-10-19)에 그대로 남아 있다.
% KASA 한국형 SE 핸드북의 "기술 버짓(Technical Budget)" 항목을 한 파일로 계산한다.
%   1. 지향각별 해면 클러터 없는 최저 고도 (상·중층 정량 관측 범위 근거)
%   2. 수신기 동적 범위와 ADC 비트 수
%   3. S밴드 링크 버짓 (하향 2 Mbps, 상향 명령)
%   4. 대전 지상국 접속 통계와 관측창 동시 가시율 (satelliteScenario, SGP4)
%   5. 자료 전달 지연 예산 (관측 → 기상청)
%   6. 탑재 자료량과 신호처리 부하
%   7. 전력 버짓과 배터리 방전심도
%   8. 질량 버짓
% 결과는 out/system_budget_12u 에 저장되고 out/run_log.csv 에 한 줄 추가된다.
% 모든 가정은 summary.txt 에 그대로 적는다. 가정은 상세 설계 전 개략값이다.

clear; close all;
here = fileparts(mfilename('fullpath'));
if isempty(here), here = pwd; end
runName = 'system_budget_12u';
outDir = fullfile(here, 'out', runName);
if ~exist(outDir, 'dir'), mkdir(outDir); end
set(groot, 'defaultAxesFontName', 'Malgun Gothic', 'defaultTextFontName', 'Malgun Gothic');
tRun = datetime('now');
tic;

c0 = 299792458; kB = 1.380649e-23; Re = 6378.137;

%% 0. 공통 설계값 (k_raineye_analysis.m 결과와 같은 값)
P.h       = 550;          % 고도 [km]
P.inc     = 45;           % 경사 [deg]
P.f       = 35.75e9;      % 레이더 주파수 [Hz]
P.D       = 0.5;          % 안테나 지름 [m]
P.hpbw    = 1.13;         % 반전력 빔폭 [deg] (RainCube 실측)
P.Pt      = 10;           % 첨두 송신 [W]
P.tau     = 166e-6;       % 펄스폭 [s]
P.B       = 1.2e6;        % 처프 대역 [Hz]
P.prf     = 1.8e3;        % PRF [Hz] (1.5~1.8 kHz 중 최대)
P.Tint    = 1.55;         % 풋프린트 길이 평균 시간 [s]
P.Zmin    = 10.5;         % 천저 최소탐지감도 [dBZ] (감도 예산)
P.Zsurf   = 58.7;         % Ka 천저 해면(σ0 10 dB) 250 m 구간 등가 반사도 [dBZ] (key_nlfm.json)
P.zRS     = 1.0;          % 채택 파형의 거리 부엽 깨끗한 높이(천저) [km] (key_nlfm.json cleanH 1024 m)
P.lossPC  = 1.5;          % 채택 파형 신호 손실 [dB]
P.res     = 175;          % 연직해상도 [m]
P.rxWin   = 319e-6;       % 수신 창 [s]
P.profDt  = 1.5;          % 프로파일 간격 [s]
P.bus     = '12U';        % 위성 규격 (2×2×3U, 22.6×22.6×34 cm급)
P.radarMinPerOrbit = 10;  % 궤도당 레이더 가동 요구조건 [min] (전력·자료량은 이 값으로 계산)
P.radarOpsMin = 3;        % 실제 운용 예상 [min/궤도]: 임무창 통과 약 94 s + 예열·여유 (넓힌 해역까지 보면 약 3분)
lambda = c0 / P.f;

%% 1. 지향각별 해면 클러터 없는 최저 고도
% 기울인 빔에서 해면 반사는 빔 가장자리에서 먼저 돌아온다. 그 가장 이른 해면 반사 거리를
% 빔 중심선 위 고도로 바꾼 값이 주엽 클러터 높이이고, 여기에 파형의 거리 부엽 깨끗한 높이(1.0 km)를 더한다.
% 보수적 경계는 반전력 가장자리 대신 첫 영점(1.22 λ/D)을 쓴다.
th = (0:0.5:10)';
bHalf3 = P.hpbw / 2;                                  % 반전력 반각 [deg]
bNull  = rad2deg(1.22 * lambda / P.D);                % 첫 영점 반각 [deg]
zML3 = max(0, P.h * (1 - cosd(th) ./ cosd(max(th - bHalf3, 0))));
zMLn = max(0, P.h * (1 - cosd(th) ./ cosd(max(th - bNull, 0))));
zClean3 = zML3 + P.zRS + P.res / 2e3;
zCleanN = zMLn + P.zRS + P.res / 2e3;
dSens = 20 * log10(1 ./ cosd(th));                    % 거리 증가에 따른 감도 손실 [dB]
ground = P.h * tand(th);                              % 지상 오프셋 [km]
offT = table(th, ground, zML3, zMLn, zClean3, zCleanN, dSens, 'VariableNames', ...
    {'offNadirDeg', 'groundOffsetKm', 'mainlobeClutterHalfPowerKm', 'mainlobeClutterFirstNullKm', ...
     'cleanHeightHalfPowerKm', 'cleanHeightFirstNullKm', 'rangeSensLossDb'});
i10 = find(th == 10);  i3 = find(th == 3);  i5 = find(th == 5);

f1 = figure('Visible', 'off', 'Position', [100 100 820 420]);
ax = axes(f1); hold(ax, 'on'); grid(ax, 'on');
fill(ax, [th; flipud(th)], [zClean3; flipud(zCleanN)], [0.85 0.92 0.9], 'EdgeColor', 'none', 'DisplayName', '추정 범위');
plot(ax, th, zClean3, '-', 'Color', [0.06 0.49 0.42], 'LineWidth', 1.8, 'DisplayName', '반전력 가장자리 기준');
plot(ax, th, zCleanN, '--', 'Color', [0.06 0.49 0.42], 'LineWidth', 1.8, 'DisplayName', '첫 영점 기준(보수적)');
yline(ax, 4.5, ':', '장마 융해층 약 4.5~5 km', 'Color', [0.76 0.25 0.18], 'LineWidth', 1.2, 'LabelHorizontalAlignment', 'right', 'HandleVisibility', 'off');
xline(ax, 3, '-', '±3°', 'Color', [0.5 0.5 0.5], 'HandleVisibility', 'off');
xline(ax, 10, '-', '±10°', 'Color', [0.5 0.5 0.5], 'LabelHorizontalAlignment', 'left', 'HandleVisibility', 'off');
xlabel(ax, '지향 오프셋 [deg]'); ylabel(ax, '해면 클러터 없는 최저 고도 [km]');
title(ax, '지향각별 정량 관측 가능 최저 고도 (주엽 해면 반사 + 거리 부엽 1.0 km)');
legend(ax, 'Location', 'northwest'); ylim(ax, [0 6]);
exportgraphics(f1, fullfile(outDir, 'figS1_offnadir_clean_height.png'), 'Resolution', 150);

%% 2. 수신기 동적 범위와 ADC
% 단일 펄스(압축 후) 잡음등가 반사도 NEZ1 은 N개 독립 표본 평균 감도에서 역산한다.
% Zmin = NEZ1 + 10log10(k/sqrt(N)), k = 3 (3σ 탐지)
N = round(P.prf * P.Tint);
kDet = 3;
NEZ1 = P.Zmin - 10 * log10(kDet / sqrt(N));
gPC = 10 * log10(P.B * P.tau) - P.lossPC;             % 펄스압축 이득(손실 반영) [dB]
snrSurfPost = P.Zsurf - NEZ1;                         % 해면 반사 압축 후 SNR [dB]
snrSurfPre  = snrSurfPost - gPC;                      % 해면 반사 압축 전(ADC 표본) SNR [dB]
calmSea     = 10;                                     % 잔잔한 바다 σ0 상승 여유 [dB]
crest       = 12;                                     % 가우스 잡음·신호 첨두 여유(4σ) [dB]
noiseLSB    = 20 * log10(3);                          % 잡음 rms = 3 LSB 확보 [dB]
needDR      = snrSurfPre + calmSea + crest + noiseLSB;   % ADC 필요 동적 범위 [dB]
needBits    = ceil((needDR - 1.76) / 6.02);
adcBits = 12; adcENOB = 10; adcDR = 6.02 * adcENOB + 1.76;
adcMargin = adcDR - needDR;
txIsoNeed = 10 * log10(P.Pt * 1e3) - (-10) ;          % 송신 40 dBm → LNA 손상 한계 -10 dBm 가정 시 필요 격리 [dB]
dr = struct('Nindep', N, 'kDet', kDet, 'NEZ1_dBZ', NEZ1, 'pcGain_dB', gPC, ...
    'surfSNRpost_dB', snrSurfPost, 'surfSNRpre_dB', snrSurfPre, 'calmSeaMargin_dB', calmSea, ...
    'crest_dB', crest, 'noiseLSB_dB', noiseLSB, 'needDR_dB', needDR, 'needBits', needBits, ...
    'adcBits', adcBits, 'adcENOB', adcENOB, 'adcDR_dB', adcDR, 'adcMargin_dB', adcMargin, ...
    'txRxIsolationNeed_dB', txIsoNeed, 'echoRange_dB', P.Zsurf - P.Zmin);

%% 3. S밴드 링크 버짓
L.fDn = 2.25e9; L.fUp = 2.05e9;
L.elMin = 10;
L.rangeMax = sqrt((Re + P.h)^2 - (Re * cosd(L.elMin))^2) - Re * sind(L.elMin);   % [km]
fspl = @(f, Rkm) 20 * log10(4 * pi * Rkm * 1e3 * f / c0);
% 하향 (위성 → 지상)
L.dn.PtW = 2;  L.dn.lineLoss = 1;  L.dn.Gtx = 5;      % 상용 큐브위성 S밴드 송신기 2 W, 패치 5 dBi
L.dn.EIRP = 10 * log10(L.dn.PtW) - L.dn.lineLoss + L.dn.Gtx;      % [dBW]
L.dn.FSPL = fspl(L.fDn, L.rangeMax);
L.dn.otherLoss = 2;                                    % 대기·편파·지향 손실 합
L.gs.D = 3; L.gs.eta = 0.55; L.gs.Tsys = 250;
L.gs.G = 10 * log10(L.gs.eta * (pi * L.gs.D * L.fDn / c0)^2);
L.gs.GT = L.gs.G - 10 * log10(L.gs.Tsys);
L.dn.CN0 = L.dn.EIRP - L.dn.FSPL - L.dn.otherLoss + L.gs.GT - 10 * log10(kB);
L.dn.Rb = 2e6;
L.dn.EbN0 = L.dn.CN0 - 10 * log10(L.dn.Rb);
L.dn.req = 4.4; L.dn.implLoss = 2;                     % QPSK + 길쌈/RS 부호 BER 1e-6 요구, 구현 손실
L.dn.margin = L.dn.EbN0 - L.dn.req - L.dn.implLoss;
% 상향 (지상 → 위성, 명령·표적 목록)
L.up.PtW = 100; L.up.Gtx = L.gs.G - (20 * log10(L.fDn / L.fUp)); L.up.lineLoss = 2;
L.up.EIRP = 10 * log10(L.up.PtW) - L.up.lineLoss + L.up.Gtx;
L.up.FSPL = fspl(L.fUp, L.rangeMax);
L.up.Grx = 0; L.up.Tsys = 500; L.up.GT = L.up.Grx - 10 * log10(L.up.Tsys);
L.up.CN0 = L.up.EIRP - L.up.FSPL - L.dn.otherLoss + L.up.GT - 10 * log10(kB);
L.up.Rb = 64e3;
L.up.EbN0 = L.up.CN0 - 10 * log10(L.up.Rb);
L.up.margin = L.up.EbN0 - L.dn.req - L.dn.implLoss;
linkT = table(["하향 2 Mbps"; "상향 64 kbps"], [L.dn.EIRP; L.up.EIRP], [L.dn.FSPL; L.up.FSPL], ...
    [L.gs.GT; L.up.GT], [L.dn.CN0; L.up.CN0], [L.dn.EbN0; L.up.EbN0], [L.dn.margin; L.up.margin], ...
    'VariableNames', {'link', 'EIRP_dBW', 'FSPL_dB', 'GT_dBK', 'CN0_dBHz', 'EbN0_dB', 'margin_dB'});

%% 4. 대전 지상국 접속 통계와 관측창 동시 가시율 (SGP4, 30일, 30 s 간격)
GS.lat = 36.37; GS.lon = 127.36;                       % 대전
Wn = struct('lat', [28 38], 'lon', [119 127]);         % 상류 관측창
t0 = datetime(2030, 6, 15, 0, 0, 0, 'TimeZone', 'UTC');
nDays = 30; dtS = 30;
sc = satelliteScenario(t0, t0 + days(nDays), dtS);
a = (Re + P.h) * 1e3;
sat = satellite(sc, a, 0, P.inc, 0, 0, 0, 'OrbitPropagator', 'sgp4', 'Name', 'K-RainEye');
gs = groundStation(sc, GS.lat, GS.lon, 'MinElevationAngle', L.elMin, 'Name', 'Daejeon');
ac = access(sat, gs);
iv = accessIntervals(ac);
durMin = minutes(iv.EndTime - iv.StartTime);
passPerDay = height(iv) / nDays;
contactMinPerDay = sum(durMin) / nDays;
[pos, ~, tt] = states(sat, 'CoordinateFrame', 'geographic');
sLat = pos(1, :)'; sLon = pos(2, :)';
[~, el, rr] = aer(gs, sat);
el = el(:); rr = rr(:) / 1e3;
n = min([numel(sLat), numel(el)]); sLat = sLat(1:n); sLon = sLon(1:n); el = el(1:n); rr = rr(1:n);
inW = sLat >= Wn.lat(1) & sLat <= Wn.lat(2) & sLon >= Wn.lon(1) & sLon <= Wn.lon(2);
visW = inW & el >= L.elMin;
fracWinVisible = sum(visW) / max(sum(inW), 1);
dataPerPassMB = L.dn.Rb * mean(durMin) * 60 / 8 / 1e6;
acc = struct('passPerDay', passPerDay, 'meanPassMin', mean(durMin), 'maxPassMin', max(durMin), ...
    'contactMinPerDay', contactMinPerDay, 'fracWindowSamplesVisible', fracWinVisible, ...
    'windowSamples', sum(inW), 'dataPerMeanPassMB', dataPerPassMB, 'rangeMaxKm', L.rangeMax, ...
    'minRangeKm', min(rr(el >= L.elMin)));

f2 = figure('Visible', 'off', 'Position', [100 100 820 380]);
ax = axes(f2);
histogram(ax, durMin, 0:1:14, 'FaceColor', [0.06 0.49 0.42]);
grid(ax, 'on'); xlabel(ax, '접속 시간 [분] (앙각 10° 이상)'); ylabel(ax, '30일 동안 접속 횟수');
title(ax, sprintf('대전 지상국 접속: 하루 %.1f회, 평균 %.1f분, 관측창 동시 가시율 %.0f%%', ...
    passPerDay, mean(durMin), 100 * fracWinVisible));
exportgraphics(f2, fullfile(outDir, 'figS2_daejeon_access.png'), 'Resolution', 150);

%% 5. 자료 전달 지연 예산 (관측 종료 → 기상청 L2 수신)
lat = struct();
lat.items = ["관측 자료 하향(같은 통과 안 실시간·통과 끝 일괄)"; "지상 수신·L1 정리"; "L2 처리(에코 정상고도·융해층·PIA)"; ...
             "품질 표시·형식 변환"; "기상청 전송(전용망)"];
lat.minutes = [4; 1; 3; 1; 1];
lat.total = sum(lat.minutes);
lat.req = 15;
lat.margin = lat.req - lat.total;
latT = table(lat.items, lat.minutes, 'VariableNames', {'step', 'minutes'});

%% 6. 탑재 자료량과 신호처리 부하
fsADC = 1.5 * P.B;                                     % 복소 표본률 [S/s]
bitsIQ = 2 * adcBits;
rawRate = fsADC * bitsIQ;                              % 수신 창 동안 원시 자료율 [bit/s]
rxDuty = P.rxWin * P.prf;
rawAvg = rawRate * rxDuty;
nFFT = 2^nextpow2(fsADC * (P.tau + P.rxWin));
cmacPerPulse = 2 * nFFT * log2(nFFT) / 2 + nFFT;       % FFT·곱·IFFT 복소 연산 근사
cmacRate = cmacPerPulse * P.prf;
nBins = 100;                                           % 25 km / 250 m
bytesProf = nBins * 2 * 2 + 64;                        % 반사도·잡음 각 2 B + 머리말
profPerOrbit = P.radarMinPerOrbit * 60 / P.profDt;
l1PerOrbitMB = profPerOrbit * bytesProf / 1e6;
orbitsPerDay = 86400 / (2 * pi * sqrt((a)^3 / 3.986004418e14));
l1PerDayMB = l1PerOrbitMB * orbitsPerDay;
diagRawSec = 10;
diagPerDayMB = rawRate * diagRawSec / 8 / 1e6;
hkPerDayMB = 2;
dataPerDayMB = l1PerDayMB + diagPerDayMB + hkPerDayMB;
dataCapPerDayMB = L.dn.Rb * contactMinPerDay * 60 / 8 / 1e6;
dat = struct('fsADC', fsADC, 'rawRateMbps', rawRate / 1e6, 'rxDuty', rxDuty, 'rawAvgMbps', rawAvg / 1e6, ...
    'nFFT', nFFT, 'cmacRateM', cmacRate / 1e6, 'bytesPerProfile', bytesProf, 'profilesPerOrbit', profPerOrbit, ...
    'L1perOrbitMB', l1PerOrbitMB, 'orbitsPerDay', orbitsPerDay, 'L1perDayMB', l1PerDayMB, ...
    'diagRawSecPerDay', diagRawSec, 'diagPerDayMB', diagPerDayMB, 'hkPerDayMB', hkPerDayMB, ...
    'dataPerDayMB', dataPerDayMB, 'downlinkCapPerDayMB', dataCapPerDayMB, 'capRatio', dataCapPerDayMB / dataPerDayMB);

%% 7. 전력 버짓
T = 2 * pi * sqrt(a^3 / 3.986004418e14) / 60;          % 궤도 주기 [min]
rho = asind(Re / (Re + P.h));
eclMax = T * (2 * rho / 360);                          % 최대 일식 [min] (β=0, 원통 그림자)
sunFrac = 1 - eclMax / T;
pw.busW = 14.0;  pw.radarW = 35;  pw.adcsExtraW = 10;  pw.adcsMin = 5;
pw.sbandW = 8;  pw.sbandMinPerPass = 10;
pw.radarAvg = pw.radarW * P.radarMinPerOrbit / T;
pw.adcsAvg  = pw.adcsExtraW * pw.adcsMin / T;
pw.sbandAvg = pw.sbandW * pw.sbandMinPerPass * passPerDay / (T * orbitsPerDay);
pw.total = pw.busW + pw.radarAvg + pw.adcsAvg + pw.sbandAvg;
pw.totalMargin = pw.total * 1.2;
pv.nPanel = 4; pv.panelW = 0.226; pv.panelL = 0.34;   % 전개 패널 4장(양쪽 날개 2단), 12U 긴 면 크기
pv.area = pv.nPanel * pv.panelW * pv.panelL; pv.eff = 0.295; pv.pack = 0.85; pv.S = 1361;
pv.peakBOL = pv.area * pv.S * pv.eff * pv.pack;
pv.EOL = pv.peakBOL * 0.9 * 0.92;
pv.cosf = 0.5;
pv.oa = pv.EOL * sunFrac * pv.cosf;
pw.ratio = pv.oa / pw.totalMargin;
bat.Wh = 90;
bat.eclWh = pw.busW * eclMax / 60 + pw.radarW * P.radarMinPerOrbit / 60 + pw.adcsAvg * eclMax / 60;
bat.DoD = bat.eclWh / bat.Wh;
radarMaxMin = (pv.oa / 1.2 - pw.busW - pw.adcsAvg - pw.sbandAvg) * T / pw.radarW;   % 생산 한도 내 최대 가동
% 운용 예상(3분/궤도)일 때 소요와 배율
ops.radarAvg = pw.radarW * P.radarOpsMin / T;
ops.total = pw.busW + ops.radarAvg + pw.adcsAvg + pw.sbandAvg;
ops.totalMargin = ops.total * 1.2;
ops.ratio = pv.oa / ops.totalMargin;
ops.eclWh = pw.busW * eclMax / 60 + pw.radarW * P.radarOpsMin / 60 + pw.adcsAvg * eclMax / 60;
ops.DoD = ops.eclWh / bat.Wh;
% 패널 구성 대안 (같은 식, 면적만 다름): 몸체 부착만 / 전개 2장 / 전개 4장 / 전개 6장
alt.names = ["몸체 부착만(유효 1.3면)"; "전개 2장"; "전개 4장(채택)"; "전개 6장"];
alt.area = [1.3; 2; 4; 6] * pv.panelW * pv.panelL;
alt.oa = alt.area * pv.S * pv.eff * pv.pack * 0.9 * 0.92 * sunFrac * pv.cosf;
alt.ratioReq = alt.oa / pw.totalMargin;  alt.ratioOps = alt.oa / ops.totalMargin;
% 한 궤도 안의 운용 모드 교대 (관측 → 전송 → 충전·대기). 전송은 대전 접속이 있는 궤도에만 생긴다.
mode.orbitMin = T;
mode.obsReq = P.radarMinPerOrbit;  mode.obsOps = P.radarOpsMin;
mode.txPerPass = pw.sbandMinPerPass;  mode.txOrbitsPerDay = passPerDay;  mode.orbitsPerDay = orbitsPerDay;
mode.slewSettle = pw.adcsMin;
mode.chargeReq = T - mode.obsReq - mode.txPerPass - mode.slewSettle;   % 접속 궤도·요구 가동일 때 남는 충전·대기 시간
mode.chargeOps = T - mode.obsOps - mode.txPerPass - mode.slewSettle;
powT = table(["버스 상시 부하"; "레이더(요구 10분/궤도)"; "자세 기동 추가분"; "S밴드 송신"; "합계"; "합계(마진 20%)"; "생산(수명 말, 궤도 평균)"; ...
              "레이더(운용 3분/궤도)"; "합계(운용, 마진 20%)"], ...
    [pw.busW; pw.radarAvg; pw.adcsAvg; pw.sbandAvg; pw.total; pw.totalMargin; pv.oa; ops.radarAvg; ops.totalMargin], ...
    'VariableNames', {'item', 'orbitAvgW'});

%% 8. 질량 버짓
massItems = ["구조·전개 기구(12U)"; "레이더 전자부"; "0.5 m 전개 안테나"; "전력(전개 패널 4장·배터리)"; ...
             "자세제어"; "OBC·통신"; "열제어·배선"; "항력장치"];
massKg = [3.5; 4.0; 2.5; 3.0; 2.0; 1.0; 1.2; 0.5];      % 12U 개략값 (16U: 4.5/4.0/2.5/3.0/2.5/1.0/1.5/0.5 = 23.4 kg)
mass.limit12U = 24;                                     % 12U 발사관 허용 질량(제품에 따라 20~24 kg)
massT = table(massItems, massKg, 'VariableNames', {'item', 'kg'});
mass.sum = sum(massKg); mass.withMargin = mass.sum * 1.2;

%% 9. 저장
fid = fopen(fullfile(outDir, 'summary.txt'), 'w', 'n', 'UTF-8');
pr = @(varargin) fprintf(fid, varargin{:});
pr('K-RainEye 시스템 기술 버짓 — %s 기준 (%s 실행)\n\n', P.bus, string(tRun));
pr('[1] 지향각별 해면 클러터 없는 최저 고도 (주엽 해면 반사 + 거리 부엽 %.1f km + 해상도 절반)\n', P.zRS);
pr('  반전력 반각 %.3f°, 첫 영점 반각 %.3f°\n', bHalf3, bNull);
for k = [1, i3, i5, i10]
    pr('  %4.1f° (지상 %5.1f km): %.2f~%.2f km, 거리 감도 손실 %.2f dB\n', th(k), ground(k), zClean3(k), zCleanN(k), dSens(k));
end
pr('  → ±10°에서도 고도 약 %.1f km 이상은 해면 오염 없이 정량 관측 가능 (장마 융해층 약 4.5~5 km 위)\n\n', zCleanN(i10));
pr('[2] 수신기 동적 범위와 ADC\n');
pr('  독립 표본 %d개, 단일 펄스 잡음등가 반사도 %.1f dBZ, 펄스압축 이득 %.1f dB\n', N, NEZ1, gPC);
pr('  해면 반사 SNR: 압축 후 %.1f dB, ADC 표본 %.1f dB\n', snrSurfPost, snrSurfPre);
pr('  필요 동적 범위 %.1f dB (잔잔한 바다 +%d dB, 첨두 +%d dB, 잡음 3 LSB) → 최소 %d비트\n', needDR, calmSea, crest, needBits);
pr('  채택: %d비트 ADC (유효 %d비트, %.1f dB) → 여유 %.1f dB\n', adcBits, adcENOB, adcDR, adcMargin);
pr('  송수신 격리: 송신 40 dBm, LNA 입력 한계 -10 dBm 가정 시 %.0f dB 필요(순환기 + 송수신 스위치·리미터)\n\n', txIsoNeed);
pr('[3] S밴드 링크 버짓 (최저 앙각 %d°, 최대 거리 %.0f km)\n', L.elMin, L.rangeMax);
pr('  하향: 송신 %g W, 안테나 %g dBi → EIRP %.1f dBW, 자유공간 손실 %.1f dB, 지상국 %g m(G/T %.1f dB/K)\n', ...
    L.dn.PtW, L.dn.Gtx, L.dn.EIRP, L.dn.FSPL, L.gs.D, L.gs.GT);
pr('        C/N0 %.1f dBHz, %g Mbps Eb/N0 %.1f dB, 요구 %.1f + 구현손실 %g dB → 여유 %.1f dB\n', ...
    L.dn.CN0, L.dn.Rb / 1e6, L.dn.EbN0, L.dn.req, L.dn.implLoss, L.dn.margin);
pr('  상향: %g W, EIRP %.1f dBW, 위성 G/T %.1f dB/K, %g kbps Eb/N0 %.1f dB → 여유 %.1f dB\n\n', ...
    L.up.PtW, L.up.EIRP, L.up.GT, L.up.Rb / 1e3, L.up.EbN0, L.up.margin);
pr('[4] 대전 지상국 접속 (SGP4, %d일, 앙각 %d° 이상)\n', nDays, L.elMin);
pr('  하루 %.1f회, 평균 %.1f분(최대 %.1f분), 하루 접속 %.1f분, 평균 통과당 하향 용량 %.0f MB\n', ...
    passPerDay, mean(durMin), max(durMin), contactMinPerDay, dataPerPassMB);
pr('  상류 관측창 안 표본 중 지상국 동시 가시 %.0f%% (%d 표본)\n\n', 100 * fracWinVisible, sum(inW));
pr('[5] 자료 전달 지연 예산 (관측 종료 → 기상청)\n');
for k = 1:numel(lat.minutes), pr('  %-40s %4.0f분\n', lat.items(k), lat.minutes(k)); end
pr('  합계 %d분 / 요구 %d분 → 여유 %d분\n\n', lat.total, lat.req, lat.margin);
pr('[6] 탑재 자료량·신호처리\n');
pr('  ADC 복소 %.1f MS/s × %d비트 → 원시 %.1f Mbps (수신 듀티 %.0f%%, 평균 %.1f Mbps)\n', fsADC / 1e6, bitsIQ, rawRate / 1e6, 100 * rxDuty, rawAvg / 1e6);
pr('  펄스압축 FFT %d점, 복소 연산 약 %.0f M/s (소형 FPGA로 실시간 처리 가능 수준)\n', nFFT, cmacRate / 1e6);
pr('  L1 프로파일 %d B, 궤도당 %.0f개 = %.2f MB, 하루 %.1f MB\n', bytesProf, profPerOrbit, l1PerOrbitMB, l1PerDayMB);
pr('  진단 원시 %d s/일 = %.0f MB, 상태정보 %d MB → 하루 합계 %.0f MB / 하향 용량 %.0f MB (%.1f배)\n\n', ...
    diagRawSec, diagPerDayMB, hkPerDayMB, dataPerDayMB, dataCapPerDayMB, dataCapPerDayMB / dataPerDayMB);
pr('[7] 전력 버짓 (궤도 %.1f분, 최대 일식 %.1f분, 일조 비율 %.2f)\n', T, eclMax, sunFrac);
for k = 1:height(powT), pr('  %-22s %6.1f W\n', powT.item(k), powT.orbitAvgW(k)); end
pr('  생산/소요(마진 포함) %.2f배, 생산 한도 안 레이더 최대 가동 궤도당 %.0f분\n', pw.ratio, radarMaxMin);
pr('  운용 예상(레이더 %g분/궤도): 소요(마진 포함) %.1f W, 생산/소요 %.2f배, 일식 방전심도 %.0f%%\n', P.radarOpsMin, ops.totalMargin, ops.ratio, 100 * ops.DoD);
pr('  패널 구성 대안 (면적 m² / 생산 W / 요구 기준 배율 / 운용 기준 배율):\n');
for k = 1:numel(alt.names), pr('    %-20s %5.2f  %5.1f  %4.2f  %4.2f\n', alt.names(k), alt.area(k), alt.oa(k), alt.ratioReq(k), alt.ratioOps(k)); end
pr('  운용 모드 교대(한 궤도 %.1f분, 접속 있는 궤도): 관측 %g분(요구)/%g분(운용) → 전송 %g분 → 기동·정착 %g분 → 충전·대기 %.0f분(요구)/%.0f분(운용)\n', ...
    T, mode.obsReq, mode.obsOps, mode.txPerPass, mode.slewSettle, mode.chargeReq, mode.chargeOps);
pr('  접속은 하루 %.1f회(궤도 %.1f회 중)라 전송이 없는 궤도가 더 많다.\n', passPerDay, orbitsPerDay);
pr('  태양전지판 전개 %d장 × %.1f×%.0f cm = %.2f m², BOL 첨두 %.0f W, EOL %.0f W, 입사 계수 %.2f\n', pv.nPanel, 100 * pv.panelW, 100 * pv.panelL, pv.area, pv.peakBOL, pv.EOL, pv.cosf);
pr('  배터리 %d Wh, 최악 일식 방전 %.1f Wh → 방전심도 %.0f%%\n\n', bat.Wh, bat.eclWh, 100 * bat.DoD);
pr('[8] 질량 버짓\n');
for k = 1:height(massT), pr('  %-24s %4.1f kg\n', massT.item(k), massT.kg(k)); end
pr('  소계 %.1f kg, 마진 20%% 포함 %.1f kg (12U 발사관 허용 약 %d kg 안, 초소형위성 기준 100 kg 이하)\n', mass.sum, mass.withMargin, mass.limit12U);
fclose(fid);

writetable(offT, fullfile(outDir, 'offnadir_clean_height.csv'), 'Encoding', 'UTF-8');
writetable(linkT, fullfile(outDir, 'link_budget.csv'), 'Encoding', 'UTF-8');
writetable(latT, fullfile(outDir, 'latency_budget.csv'), 'Encoding', 'UTF-8');
writetable(powT, fullfile(outDir, 'power_budget.csv'), 'Encoding', 'UTF-8');
writetable(massT, fullfile(outDir, 'mass_budget.csv'), 'Encoding', 'UTF-8');
ivT = table(iv.StartTime, iv.EndTime, durMin, 'VariableNames', {'startUTC', 'endUTC', 'durationMin'});
writetable(ivT, fullfile(outDir, 'daejeon_access.csv'), 'Encoding', 'UTF-8');
try
    writetable(offT, fullfile(outDir, 'results.xlsx'), 'Sheet', 'offnadir');
    writetable(linkT, fullfile(outDir, 'results.xlsx'), 'Sheet', 'link');
    writetable(latT, fullfile(outDir, 'results.xlsx'), 'Sheet', 'latency');
    writetable(powT, fullfile(outDir, 'results.xlsx'), 'Sheet', 'power');
    writetable(massT, fullfile(outDir, 'results.xlsx'), 'Sheet', 'mass');
catch ME
    warning('xlsx 저장 실패: %s', ME.message);
end
key = struct('run', runName, 'time', string(tRun), 'params', P, ...
    'offnadir', struct('deg', th', 'cleanHalfPowerKm', zClean3', 'cleanFirstNullKm', zCleanN', 'sensLossDb', dSens'), ...
    'dynamicRange', dr, 'link', L, 'access', acc, 'latency', struct('items', lat.items', 'minutes', lat.minutes', ...
    'total', lat.total, 'req', lat.req, 'margin', lat.margin), 'data', dat, ...
    'power', struct('orbitMin', T, 'eclipseMaxMin', eclMax, 'sunFrac', sunFrac, 'items', pw, 'pv', pv, ...
    'battery', bat, 'radarMaxMinPerOrbit', radarMaxMin, 'ops', ops, 'alt', alt, 'mode', mode), ...
    'mass', struct('items', massItems', 'kg', massKg', 'sum', mass.sum, 'withMargin', mass.withMargin, 'limit12U', mass.limit12U));
fidj = fopen(fullfile(outDir, 'key_system.json'), 'w', 'n', 'UTF-8');
fprintf(fidj, '%s', jsonencode(key, 'PrettyPrint', true));
fclose(fidj);
save(fullfile(outDir, 'results.mat'), 'P', 'offT', 'dr', 'L', 'acc', 'iv', 'lat', 'dat', 'pw', 'pv', 'bat', 'massT', 'mass', 'ops', 'alt', 'mode');
fid = fopen(fullfile(outDir, 'run_info.txt'), 'w', 'n', 'UTF-8');
fprintf(fid, '실행: %s (소요 %.0f s)\n스크립트: %s\nMATLAB: %s\n', string(tRun), toc, mfilename('fullpath'), version);
fprintf(fid, '시나리오: %s 부터 %d일, %d s 간격, SGP4, 대전(%.2fN, %.2fE) 앙각 %d°\n', string(t0), nDays, dtS, GS.lat, GS.lon, L.elMin);
fprintf(fid, '설계값 P: %s\n', jsonencode(P));
fclose(fid);
logLine(fullfile(here, 'out', 'run_log.csv'), tRun, mfilename, outDir, ...
    sprintf('%s: ±10° 정량 최저고도 %.1f km, 하향 여유 %.1f dB, 접속 %.1f회/일, 전력 요구10분 %.2f배·운용3분 %.2f배, 패널 %.2f m², 질량 %.1f kg', ...
    P.bus, zCleanN(i10), L.dn.margin, passPerDay, pw.ratio, ops.ratio, pv.area, mass.withMargin));
fprintf('완료 (%.0f s): %s\n', toc, outDir);

function logLine(f, t, script, outDir, note)
newFile = ~exist(f, 'file');
fid = fopen(f, 'a', 'n', 'UTF-8');
if newFile, fprintf(fid, 'time,script,outDir,note\n'); end
fprintf(fid, '%s,%s,%s,"%s"\n', char(t, 'yyyy-MM-dd HH:mm:ss'), script, outDir, note);
fclose(fid);
end
