# 08. k_raineye_system.m 해설

> 담당: C   대상 파일: `matlab/k_raineye_system.m` (326줄)   관련 결과 폴더: `matlab/out/system_budget/`

## 1. 한 줄 역할
다른 모의에서 정한 위성 설계값(고도 550 km, 경사 45°, Ka 35.75 GHz, 0.5 m 안테나 등)을 손으로 적어 넣고, 위성 시스템이 "실제로 만들어질 수 있는가"를 보여 주는 8가지 기술 버짓(예산표: 질량·전력·통신 링크·자료량·전달 지연·수신기 동적 범위·대전 지상국 접속·기울였을 때 바다 반사에 안 가리는 최저 고도)을 한 번에 계산해 `matlab/out/system_budget/`에 표·그림·JSON으로 저장한다.

실행 기록(`matlab/out/system_budget/run_info.txt`): 2026-10-19 23:05:38, MATLAB R2025b, 소요 21초. `matlab/out/run_log.csv`에는 같은 날 두 번(23:04, 23:05) 실행한 줄이 남아 있고, 한 줄 요약은 "±10° 정량 최저고도 3.0 km, ADC 여유 16 dB, 하향 여유 9.9 dB, 접속 5.9회/일, 관측창 동시가시 100%, 전력 1.49배, 질량 23.4 kg"이다.

## 2. 흐름 (입력 → 처리 → 출력)
| 단계 | 하는 일 | 쓰는 함수·변수 | 나오는 것 |
|---|---|---|---|
| 0 (줄 24~45) | 물리 상수와 설계값 P를 손으로 적어 넣음 (다른 모의 결과를 그대로 복사) | `c0`, `kB`, `Re`, 구조체 `P` | `P.h`, `P.f`, `P.Zmin` 등 18개 값 |
| 1 (줄 47~76) | 기울임각 0~10°마다 바다 반사(해면 클러터)가 가리는 높이 계산 | `cosd`, `rad2deg`, 표 `offT` | `offnadir_clean_height.csv`, `figS1_offnadir_clean_height.png` |
| 2 (줄 78~99) | 바다 반사와 가장 약한 비를 동시에 받으려면 ADC(아날로그→디지털 변환기)가 몇 비트 필요한지 | `NEZ1`, `needDR`, `needBits`, 구조체 `dr` | 필요 8비트, 채택 12비트, 여유 16.2 dB |
| 3 (줄 101~130) | S밴드(2 GHz대) 하향·상향 통신 링크 버짓 | `fspl` 익명함수, 구조체 `L`, 표 `linkT` | `link_budget.csv` |
| 4 (줄 132~166) | 궤도를 30일 SGP4로 돌려 대전 지상국 접속 횟수·시간, 관측창에 있을 때 지상국이 보이는 비율 | `satelliteScenario`, `satellite`, `groundStation`, `access`, `aer`, `states` | `daejeon_access.csv`, `figS2_daejeon_access.png`, 구조체 `acc` |
| 5 (줄 168~176) | 관측 끝 → 기상청 도착까지 걸리는 시간을 5단계로 더함 | 구조체 `lat`, 표 `latT` | `latency_budget.csv` (합계 10분) |
| 6 (줄 178~202) | 하루 자료량과 위성 안 신호처리 연산량 | `rawRate`, `nFFT`, `bytesProf`, 구조체 `dat` | 하루 60 MB vs 하향 용량 602 MB |
| 7 (줄 204~228) | 전력 소요(궤도 평균)와 태양전지판 생산, 배터리 방전심도 | 구조체 `pw`, `pv`, `bat`, 표 `powT` | `power_budget.csv` |
| 8 (줄 230~235) | 부품별 질량을 더하고 20% 마진 | `massKg`, 표 `massT`, `mass` | `mass_budget.csv` |
| 9 (줄 237~318) | 위 결과를 글(summary.txt)·CSV·xlsx·JSON·mat로 저장하고 실행 기록 추가 | `fprintf`, `writetable`, `jsonencode`, `save`, `logLine` | `summary.txt`, `key_system.json`, `results.mat`, `results.xlsx`, `run_info.txt`, `out/run_log.csv` 1줄 |

## 3. 절별 해설

### 3.1 공통 상수와 설계값 (줄 24~45)
```matlab
c0 = 299792458; kB = 1.380649e-23; Re = 6378.137;
P.h       = 550;          % 고도 [km]
P.f       = 35.75e9;      % 레이더 주파수 [Hz]
P.D       = 0.5;          % 안테나 지름 [m]
P.hpbw    = 1.13;         % 반전력 빔폭 [deg] (RainCube 실측)
P.Pt      = 10;           % 첨두 송신 [W]
P.tau     = 166e-6;       % 펄스폭 [s]
P.B       = 1.2e6;        % 처프 대역 [Hz]
P.prf     = 1.8e3;        % PRF [Hz]
P.Zmin    = 10.5;         % 천저 최소탐지감도 [dBZ]
P.Zsurf   = 58.7;         % 해면 등가 반사도 [dBZ] (key_nlfm.json)
P.zRS     = 1.0;          % 거리 부엽 깨끗한 높이 [km] (cleanH 1024 m)
P.radarMinPerOrbit = 15;  % 궤도당 레이더 가동 [min]
lambda = c0 / P.f;
```
이 파일은 다른 파일을 읽지 않는다. 대신 `k_raineye_analysis.m`의 결과를 숫자로 베껴 넣는다. 예를 들어 `P.Zsurf = 58.7`은 `matlab/out/key_nlfm.json`의 `Zsurf: 58.66`에서, `P.zRS = 1.0`은 같은 파일 `cleanH`의 채택 파형 값 1024 m에서, `P.Zmin = 10.5`는 `matlab/out/sens_pcloss/summary.txt`의 "감도 10.52 dBZ"에서 왔다. `Re`(지구 반지름 6378.137 km)는 `k_raineye_analysis.m` 32줄, `dp/kre_lib.m` 21줄과 같다. 파장 λ = c/f = 299792458 / 35.75e9 = 0.00839 m(8.39 mm)다.

### 3.2 지향각별 해면 클러터 없는 최저 고도 (줄 47~63)
```matlab
th = (0:0.5:10)';
bHalf3 = P.hpbw / 2;                                  % 반전력 반각 [deg]
bNull  = rad2deg(1.22 * lambda / P.D);                % 첫 영점 반각 [deg]
zML3 = max(0, P.h * (1 - cosd(th) ./ cosd(max(th - bHalf3, 0))));
zMLn = max(0, P.h * (1 - cosd(th) ./ cosd(max(th - bNull, 0))));
zClean3 = zML3 + P.zRS + P.res / 2e3;
zCleanN = zMLn + P.zRS + P.res / 2e3;
dSens = 20 * log10(1 ./ cosd(th));                    % 거리 증가에 따른 감도 손실 [dB]
ground = P.h * tand(th);                              % 지상 오프셋 [km]
```
위성을 각도 θ만큼 기울이면 빔(전파 다발)의 안쪽 가장자리(θ − 반각 b)가 바다에 가장 먼저 닿는다. 그 거리는 h/cos(θ−b)이고, 빔 중심선에서 같은 거리는 지표 위 높이 h − [h/cos(θ−b)]·cos θ = h(1 − cos θ / cos(θ−b))에 해당한다. 이 높이 아래는 바다 반사와 비 신호가 같은 시각에 돌아와 구분이 안 된다(주엽 클러터). 여기에 펄스압축 파형의 거리 부엽(압축 뒤 남는 꼬리)이 깨끗해지는 1.0 km와 해상도 절반(175/2 m = 0.0875 km)을 더한다. 예: θ = 10°, 첫 영점 반각 b = 1.172°일 때 550 × (1 − cos10° / cos8.828°) = 1.863 km, 더해서 2.950 km(`offnadir_clean_height.csv` 마지막 줄 `cleanHeightFirstNullKm` 2.9502). 반전력 반각 0.565°를 쓰면 2.016 km. `dSens`는 거리가 1/cos θ배 멀어져 신호가 거리²에 반비례해 약해지는 양으로, 10°에서 0.13 dB뿐이다.

### 3.3 수신기 동적 범위와 ADC 비트 수 (줄 78~99)
```matlab
N = round(P.prf * P.Tint);                            % 독립 표본 수 = 2790
kDet = 3;
NEZ1 = P.Zmin - 10 * log10(kDet / sqrt(N));           % 단일 펄스 잡음등가 반사도
gPC = 10 * log10(P.B * P.tau) - P.lossPC;             % 펄스압축 이득 [dB]
snrSurfPost = P.Zsurf - NEZ1;                         % 해면 반사 압축 후 SNR
snrSurfPre  = snrSurfPost - gPC;                      % ADC 표본에서의 SNR
needDR      = snrSurfPre + calmSea + crest + noiseLSB;   % 10 + 12 + 20log10(3)
needBits    = ceil((needDR - 1.76) / 6.02);
adcBits = 12; adcENOB = 10; adcDR = 6.02 * adcENOB + 1.76;
adcMargin = adcDR - needDR;
```
감도 10.5 dBZ는 2790개 펄스를 평균한 뒤의 값이므로, 펄스 한 발의 잡음 수준(NEZ1)은 10.5 − 10·log10(3/√2790) = 10.5 + 12.46 = 22.96 dBZ로 더 높다. 바다 반사(58.7 dBZ)는 이보다 35.7 dB 세고, 펄스압축 이득 21.5 dB(= 10·log10(1.2e6 × 166e-6) − 1.5)를 빼면 ADC에 들어오는 순간에는 14.3 dB다. 잔잔한 바다에서 더 세질 여유 10 dB, 신호 첨두 여유 12 dB, 잡음을 3 LSB(최하위 비트) 크기로 잡는 9.5 dB를 더해 필요 동적 범위 45.8 dB → (45.8 − 1.76)/6.02 = 7.3 → 8비트. 채택한 12비트(유효 10비트, 62.0 dB) ADC는 16.2 dB 여유가 있다(`key_system.json` `dynamicRange`). `txIsoNeed`는 송신 10 W(40 dBm)가 수신 증폭기(한계 −10 dBm)로 새지 않도록 필요한 격리 50 dB다.

### 3.4 S밴드 링크 버짓 (줄 101~130)
```matlab
L.rangeMax = sqrt((Re + P.h)^2 - (Re * cosd(L.elMin))^2) - Re * sind(L.elMin);   % 1816 km
fspl = @(f, Rkm) 20 * log10(4 * pi * Rkm * 1e3 * f / c0);
L.dn.PtW = 2;  L.dn.lineLoss = 1;  L.dn.Gtx = 5;
L.dn.EIRP = 10 * log10(L.dn.PtW) - L.dn.lineLoss + L.dn.Gtx;      % [dBW]
L.gs.G = 10 * log10(L.gs.eta * (pi * L.gs.D * L.fDn / c0)^2);     % 3 m 접시 34.4 dBi
L.gs.GT = L.gs.G - 10 * log10(L.gs.Tsys);                          % G/T [dB/K]
L.dn.CN0 = L.dn.EIRP - L.dn.FSPL - L.dn.otherLoss + L.gs.GT - 10 * log10(kB);
L.dn.EbN0 = L.dn.CN0 - 10 * log10(L.dn.Rb);
L.dn.margin = L.dn.EbN0 - L.dn.req - L.dn.implLoss;
L.up.Gtx = L.gs.G - (20 * log10(L.fDn / L.fUp));
```
링크 버짓은 "보낸 전력 − 경로 손실 + 받는 쪽 성능 − 잡음"을 모두 dB(10배마다 10)로 더하고 빼는 표다. 가장 먼 거리는 지상국에서 앙각 10°로 보일 때 1816 km이고, 자유공간 손실 20·log10(4π × 1.816e6 × 2.25e9 / c) = 164.7 dB다. 위성 송신 2 W(3.0 dBW) − 선로 1 dB + 안테나 5 dBi = 7.0 dBW, 지상국 G/T 10.4 dB/K, 볼츠만 상수 −228.6 dBW/K/Hz를 합쳐 C/N0 79.4 dBHz. 2 Mbps(63.0 dB)를 빼면 Eb/N0 16.3 dB이고, 요구 4.4 dB + 구현 손실 2 dB를 빼면 여유 9.9 dB(`link_budget.csv` 1행). 상향은 지상 100 W라 여유 32.9 dB로 넉넉하다. 상향 주파수(2.05 GHz)는 하향(2.25 GHz)보다 낮아 같은 접시의 이득이 20·log10(2.25/2.05) = 0.81 dB 작아진다.

### 3.5 대전 지상국 접속과 관측창 동시 가시율 (줄 132~158)
```matlab
GS.lat = 36.37; GS.lon = 127.36;                       % 대전
Wn = struct('lat', [28 38], 'lon', [119 127]);         % 상류 관측창
sc = satelliteScenario(t0, t0 + days(nDays), dtS);     % 2030-06-15부터 30일, 30 s
a = (Re + P.h) * 1e3;                                  % 반장축 [m]
sat = satellite(sc, a, 0, P.inc, 0, 0, 0, 'OrbitPropagator', 'sgp4', 'Name', 'K-RainEye');
gs = groundStation(sc, GS.lat, GS.lon, 'MinElevationAngle', L.elMin, 'Name', 'Daejeon');
iv = accessIntervals(access(sat, gs));
durMin = minutes(iv.EndTime - iv.StartTime);
[pos, ~, tt] = states(sat, 'CoordinateFrame', 'geographic');
[~, el, rr] = aer(gs, sat);
inW = sLat >= Wn.lat(1) & sLat <= Wn.lat(2) & sLon >= Wn.lon(1) & sLon <= Wn.lon(2);
visW = inW & el >= L.elMin;
fracWinVisible = sum(visW) / max(sum(inW), 1);
```
MATLAB Aerospace Toolbox의 `satelliteScenario`로 위성을 30일 동안 30초 간격으로 돌린다(SGP4는 인공위성 궤도 예측에 널리 쓰는 표준 계산법). `satellite` 함수는 반장축을 m 단위로 받으므로 (6378.137 + 550) km에 1e3을 곱한다. 대전에서 앙각(지평선 위 각도) 10° 이상으로 보이는 구간을 모두 모으면 30일에 178번, 하루 5.93회, 평균 6.77분(최대 8.0분), 하루 합계 40.2분이다(`daejeon_access.csv` 178줄, `key_system.json` `access`). 위성이 관측창(북위 28~38°, 동경 119~127°) 안에 있던 208개 표본 중 대전이 앙각 10° 이상으로 보인 비율이 100%였는데, 관측창의 가장 먼 모서리(28°N, 119°E)도 대전에서 약 1220 km라 550 km 고도 위성이 앙각 약 18°로 보이기 때문이다. 이 100%가 "관측한 그 통과 안에서 바로 내려받는다"는 제안서 주장의 근거다.

### 3.6 자료 전달 지연 예산 (줄 168~176)
```matlab
lat.items = ["관측 자료 하향(같은 통과 안 실시간·통과 끝 일괄)"; "지상 수신·L1 정리"; ...
             "L2 처리(에코 정상고도·융해층·PIA)"; "품질 표시·형식 변환"; "기상청 전송(전용망)"];
lat.minutes = [4; 1; 3; 1; 1];
lat.total = sum(lat.minutes);
lat.req = 15;
lat.margin = lat.req - lat.total;
```
계산이 아니라 단계별 소요 시간을 손으로 정한 표다. 4 + 1 + 3 + 1 + 1 = 10분, 요구 15분이므로 여유 5분(`latency_budget.csv`). 여유는 "요구 − 소요"로, 양수가 좋다. 이 숫자들은 근거 파일이 없는 가정이므로 심사에서 물으면 "개략 운용 가정"이라고 답해야 한다.

### 3.7 탑재 자료량과 신호처리 부하 (줄 178~202)
```matlab
fsADC = 1.5 * P.B;                                     % 복소 표본률 1.8 MS/s
bitsIQ = 2 * adcBits;                                  % I·Q 각 12비트 = 24비트
rawRate = fsADC * bitsIQ;                              % 43.2 Mbit/s
rxDuty = P.rxWin * P.prf;                              % 수신 창 비율 0.574
nFFT = 2^nextpow2(fsADC * (P.tau + P.rxWin));          % 1024
cmacPerPulse = 2 * nFFT * log2(nFFT) / 2 + nFFT;       % FFT·곱·IFFT 복소 연산
nBins = 100;                                           % 25 km / 250 m
bytesProf = nBins * 2 * 2 + 64;                        % 464 B
profPerOrbit = P.radarMinPerOrbit * 60 / P.profDt;     % 600개
orbitsPerDay = 86400 / (2 * pi * sqrt((a)^3 / 3.986004418e14));
dataPerDayMB = l1PerDayMB + diagPerDayMB + hkPerDayMB;
dataCapPerDayMB = L.dn.Rb * contactMinPerDay * 60 / 8 / 1e6;
```
ADC가 뽑는 원시 자료는 1.8 MS/s × 24비트 = 43.2 Mbit/s로, 그대로 내려보내기엔 너무 많다. 그래서 위성 안에서 펄스압축(1024점 FFT, 약 2천만 복소 연산/초, 작은 FPGA 수준)과 평균을 해서 높이 100칸짜리 프로파일(464바이트)로 줄인다. 1.5초마다 한 개씩 궤도당 15분이면 600개 = 0.28 MB, 하루 15.05궤도면 4.2 MB. 진단용 원시 10초(54 MB)와 상태정보 2 MB를 더해 하루 60.2 MB다. 하향 용량은 2 Mbit/s × 40.2분 × 60 / 8 / 1e6 = 602.5 MB라 10.0배 여유(`key_system.json` `data.capRatio`). 단위 환산은 bit → byte가 /8, byte → MB가 /1e6이다.

### 3.8 전력 버짓 (줄 204~228)
```matlab
T = 2 * pi * sqrt(a^3 / 3.986004418e14) / 60;          % 궤도 주기 95.65 min
rho = asind(Re / (Re + P.h));                          % 지구가 보이는 반각 67.0°
eclMax = T * (2 * rho / 360);                          % 최대 일식 35.6 min
sunFrac = 1 - eclMax / T;                              % 0.628
pw.busW = 14.0;  pw.radarW = 35;  pw.adcsExtraW = 10;  pw.adcsMin = 5;
pw.radarAvg = pw.radarW * P.radarMinPerOrbit / T;      % 35 W × 15/95.65 = 5.49 W
pw.total = pw.busW + pw.radarAvg + pw.adcsAvg + pw.sbandAvg;   % 20.34 W
pw.totalMargin = pw.total * 1.2;                       % 24.41 W
pv.area = 4 * 0.226 * 0.454; pv.eff = 0.295; pv.pack = 0.85; pv.S = 1361;
pv.peakBOL = pv.area * pv.S * pv.eff * pv.pack;        % 140 W
pv.EOL = pv.peakBOL * 0.9 * 0.92;                      % 116 W (수명 말)
pv.oa = pv.EOL * sunFrac * pv.cosf;                    % × 0.628 × 0.5 = 36.4 W
bat.eclWh = pw.busW * eclMax / 60 + pw.radarW * P.radarMinPerOrbit / 60 + pw.adcsAvg * eclMax / 60;
bat.DoD = bat.eclWh / bat.Wh;                          % 17.4 / 90 = 19%
```
전력은 "궤도 평균 W"로 비교한다. 레이더는 켜졌을 때 35 W지만 궤도 95.65분 중 15분만 켜므로 평균 5.49 W다. 버스(위성 기본 장치) 14 W, 자세 기동 0.52 W, S밴드 0.33 W를 더해 20.34 W, 상세 설계에서 늘어날 몫 20%를 곱해 24.41 W(`power_budget.csv`). 생산 쪽은 16U의 긴 네 면 넓이(4 × 0.226 × 0.454 = 0.41 m²)에 태양 상수 1361 W/m², 셀 효율 29.5%, 채움률 85%를 곱한 140 W에서 시작해, 수명 말 열화(0.9 × 0.92)로 116 W, 햇빛 비율 0.628과 평균 입사 계수 0.5를 곱해 36.4 W다. 생산/소요 = 36.4/24.4 = 1.49배. 배터리는 가장 긴 일식(35.6분) 동안 버스 14 W × 0.593 h = 8.3 Wh, 레이더 35 W × 0.25 h = 8.75 Wh, 자세 0.3 Wh로 17.4 Wh를 쓰고, 90 Wh 중 19%다(저궤도 장기 운용 기준 약 30% 이하).

### 3.9 질량 버짓 (줄 230~235)
```matlab
massItems = ["구조·전개 기구"; "레이더 전자부"; "0.5 m 전개 안테나"; "전력(태양전지판·배터리)"; ...
             "자세제어"; "OBC·통신"; "열제어·배선"; "항력장치"];
massKg = [4.5; 4.0; 2.5; 3.0; 2.5; 1.0; 1.5; 0.5];
mass.sum = sum(massKg); mass.withMargin = mass.sum * 1.2;
```
8개 항목을 더하면 4.5 + 4.0 + 2.5 + 3.0 + 2.5 + 1.0 + 1.5 + 0.5 = 19.5 kg, 20% 마진을 더하면 23.4 kg(`mass_budget.csv`). 항목 값은 모두 손으로 넣은 개략값이다. 초소형위성 기준 100 kg보다 훨씬 가볍다.

### 3.10 저장 (줄 237~318)
```matlab
fid = fopen(fullfile(outDir, 'summary.txt'), 'w', 'n', 'UTF-8');
...
writetable(offT, fullfile(outDir, 'offnadir_clean_height.csv'), 'Encoding', 'UTF-8');
writetable(linkT, fullfile(outDir, 'link_budget.csv'), 'Encoding', 'UTF-8');
key = struct('run', runName, 'time', string(tRun), 'params', P, 'offnadir', ..., ...
    'dynamicRange', dr, 'link', L, 'access', acc, 'latency', ..., 'data', dat, 'power', ..., 'mass', ...);
fprintf(fidj, '%s', jsonencode(key, 'PrettyPrint', true));
save(fullfile(outDir, 'results.mat'), 'P', 'offT', 'dr', 'L', 'acc', 'iv', 'lat', 'dat', 'pw', 'pv', 'bat', 'massT', 'mass');
logLine(fullfile(here, 'out', 'run_log.csv'), tRun, mfilename, outDir, sprintf(...));
```
같은 결과를 사람이 읽는 `summary.txt`, 표 5개의 CSV와 `results.xlsx`, 기계가 읽는 `key_system.json`과 `results.mat`로 저장한다. 저장 폴더는 스크립트 위치 기준 `out/system_budget`이고(`here = fileparts(mfilename('fullpath'))`), 마지막에 `out/run_log.csv`에 한 줄을 덧붙인다. 확인 스크립트 `checks/check08.m`은 이 중 `key_system.json`을 읽어 재계산한다.

## 4. 핵심 가정 3개
1. **레이더는 궤도마다 15분 켠다(`P.radarMinPerOrbit = 15`)** — 관측창 체류는 하루 3.4분 정도(`matlab/out/summary.txt`)지만 예열·교정까지 넉넉히 잡았다. 깨지면(예: 30분) 레이더 평균 전력이 11 W로 늘어 마진 포함 소요 31 W가 되지만 생산 36.4 W 안이고(코드가 계산한 한도는 42분), 하루 L1 자료량도 2배가 되나 60 MB 수준이라 영향이 작다.
2. **태양전지판 0.41 m²에 평균 입사 계수 0.5(`pv.cosf`)** — 태양을 따라 돌지 않는 고정 패널의 평균 기울어짐을 대충 절반으로 본 것이다. 이 넓이는 16U 긴 네 면 전체와 같아서, 패널이 몸체에 붙은 것이면 한쪽 두 면만 햇빛을 받아 계수가 0.32 정도로 떨어지고 생산이 약 23 W로 소요 24.4 W에 못 미친다(5절 5번). 따라서 이 가정은 "전개형(펼치는) 패널"을 뜻한다고 문서에 적어야 한다.
3. **바다 반사 등가 반사도 58.7 dBZ와 거리 부엽 깨끗한 높이 1.0 km는 `k_raineye_analysis.m`의 채택 파형 결과를 복사한 값** — 그 분석에서 σ0(해면 후방산란 계수) 10 dB, 250 m 출력 구간을 가정했다. 파형이나 σ0 가정이 바뀌면 이 파일의 ADC 비트 수와 최저 고도 결과도 함께 다시 돌려야 한다(두 파일이 자동으로 연결되어 있지 않다).

## 5. 코드 검토 결과
| 번호 | 줄 | 지적 | 어떤 입력에서 틀어지나 | 판정 | 근거 |
|---|---|---|---|---|---|
| 1 | 54~57 | 클러터 높이를 평평한 지구로 계산한다. 10°에서 지상 오프셋 97 km면 지구 곡률로 바다가 약 0.7 km 더 멀어져 클러터 높이가 커진다 | 기울임각이 클수록(10°에서 +0.2 km, 3°에서 +0.02 km) | **개선 제안(결과에는 영향 없음)** | 구면 기하로 다시 계산하면 첫 영점 기준 2.95 → 약 3.15 km. 제안서의 "약 3 km"는 유지되나 소수 첫째 자리 "3.0 km"는 바뀔 수 있음 |
| 2 | 38, 187~188 | `P.res = 175` m인데 `nBins = 100 % 25 km / 250 m`과 `P.Zsurf`(250 m 구간 기준)는 250 m 구간을 쓴다 | 출력 구간을 175 m로 바꾸면 프로파일 636 B, 하루 자료 60 → 62 MB, 필요 동적 범위 +1.55 dB(비트 수는 8 그대로) | **문제 없음(오해)** | `k_raineye_analysis.m` 274·549줄이 감도·해면 반사도를 "250 m 출력 구간" 기준으로 정의하므로 일관됨. 다만 250을 변수(`P.gate`)로 빼 두면 혼동이 줄어듦 |
| 3 | 191, 205 | 중력 상수가 `3.986004418e14`(m³/s²)로 다른 파일의 `398600.4418`(km³/s²)과 숫자가 달라 보인다 | 없음(단위만 다름) | **문제 없음(오해)** | km 상수로 다시 계산한 주기 95.65분, 하루 15.055궤도가 `key_system.json`과 1e-9 안에서 일치 |
| 4 | 138~139 | `satellite(sc, a, ...)`의 반장축 `a`에 1e3을 곱해 m로 넘긴다 | km로 넘기면 궤도가 지구 안으로 들어가 결과가 모두 깨짐 | **문제 없음(오해)** | `satelliteScenario`는 m 단위를 받음. 결과 `access.minRangeKm` 552 km가 고도 550 km와 맞으므로 단위가 옳음 |
| 5 | 216~220 | 태양전지판 넓이 0.41 m²(긴 네 면 전부)에 입사 계수 0.5를 곱한다. 몸체 부착이면 네 면이 동시에 햇빛을 받을 수 없다 | 패널이 몸체 부착형일 때 | **개선 제안(결과에는 영향 없음)** | 몸체 부착 4면 가정(평균 유효 넓이 = 한 면 × 4/π)으로 바꾸면 생산 23.2 W < 소요 24.4 W로 결론이 뒤집힘. 전개형 패널 가정임을 코드 주석과 제안서에 명시해야 함 |
| 6 | 223 | "최악 일식 방전"에 S밴드 송신(8 W × 10분)이 빠져 있다 | 일식 중에 지상국 통과가 겹칠 때 | **개선 제안(결과에는 영향 없음)** | 넣으면 17.4 → 18.7 Wh, 방전심도 19.3 → 20.8%. 기준 30% 안이라 결론 불변 |
| 7 | 108~127 | 링크 버짓의 단위(dBW, dB/K, −10log10(kB) = 228.6)와 상향 안테나 이득 보정 방향(낮은 주파수 → 이득 감소) | 없음 | **문제 없음(오해)** | EIRP 7.01 dBW, FSPL 164.67 dB, C/N0 79.35 dBHz, 여유 9.94 dB를 식으로 재계산해 1e-6 안에서 일치. 상향 이득 33.59 < 하향 34.40 dBi로 방향 옳음 |
| 8 | 154, 196~197, 214~215, 235 | 합계가 항목 합과 같은지, 마진 ×1.2 방향, bit→MB 환산(/8/1e6) | 없음 | **문제 없음(오해)** | 질량 19.5 = 항목 합, 23.4 = ×1.2; 전력 20.34 = 4항목 합, 24.41 = ×1.2; 지연 10 = 합, 여유 = 15 − 10; 자료 101.5 MB/통과, 602.5 MB/일이 식과 일치 |

**어떻게 확인했나.** `checks/check08.m`이 `matlab/out/system_budget/key_system.json`을 읽어 각 항목을 식으로 다시 계산한다(원 스크립트는 다시 돌리지 않음). 1번은 위성–지구 중심–지표 삼각형으로 정확한 경사거리를 구해 평면 근사와 비교하고, 2번은 `k_raineye_analysis.m` 본문에 `dRb = 250`이 있는지 글자로 확인한다. 5·6번은 대안 가정으로 재계산해 결론이 바뀌는지 본다. 예상 결과: 1·5·6번 FAIL(지적이 맞음, 단 6번은 결론 불변), 나머지 PASS.

### 5.9 확인 스크립트 실행 결과 (2026-10-31, `checks/check08.m`, 8.0초)

PASS = 코드가 의도대로 동작함(지적이 오해이거나 버그 없음), FAIL = 지적이 맞음(개선 제안 포함).

| 번호 | 결과 | 설명 |
|---|---|---|
| 1 | **FAIL** | 10° 최저 고도 평면 2.95 km, 구면 3.11 km (차 +0.16 km); 0.1 km 넘으면 지적 맞음(결론 "약 3 km"는 유지) |
| 2 | **PASS** | analysis.m에 dRb = 250 있음, 프로파일 464 B; 175 m 구간이면 636 B, 하루 60.2→61.7 MB, 필요 비트 8→8 (결론 불변) |
| 3 | **PASS** | 주기 95.650분, 하루 15.055궤도, 최대 일식 35.61분 (상대 오차 1.5e-16) |
| 4 | **PASS** | 최소 거리 552.3 km (고도 550 km), 앙각 10° 최대 거리 1815.7 km |
| 5 | **FAIL** | 코드(전개형, 계수 0.5) 생산 36.4 W; 몸체 부착 4면이면 23.2 W vs 소요 24.4 W → 부족하면 지적 맞음(전개형 가정 명시 필요) |
| 6 | **FAIL** | 코드 17.37 Wh (S밴드 없음 17.37, 포함 18.70) → 방전심도 19.3% vs 20.8% (기준 30% 안, 결론 불변) |
| 7 | **PASS** | EIRP 7.01 dBW, G/T 10.42 dB/K, C/N0 79.35 dBHz, 하향 여유 9.94 dB, 상향 접시 이득 33.59 < 34.40 dBi (최대 오차 0.0e+00) |
| 8 | **PASS** | 질량 19.5/23.4 kg, 전력 20.34/24.41 W, 지연 10/5분, 자료 101.5 MB/통과, 602.5 MB/일 (14개 식 최대 오차 0.0e+00) |

요약: PASS 5개, FAIL 3개.

**판정 대조:** FAIL로 나온 항목은 모두 5절 표에서 이미 그렇게 판정한 지적(개선 제안)이다. 제안서에 쓰인 숫자(이득 배수, 감도, 감쇠 높이, 신뢰구간)는 어느 FAIL에도 영향을 받지 않는다.

## 6. 다른 문서와의 연결
- 이 파일이 부르는 것: 프로젝트 파일은 없음. MATLAB Aerospace Toolbox의 `satelliteScenario`, `satellite`, `groundStation`, `access`, `aer`, `states`를 쓴다(툴박스가 없으면 4절부터 실행이 멈춤). 설계값은 `k_raineye_analysis.m` 해설 문서의 모의 2(감도)·모의 3-b(펄스압축) 절 결과와 `k_raineye_sens_pcloss.m`의 감도 10.5 dBZ를 숫자로 베껴 넣은 것이다.
- 이 파일을 부르는 것: 없음. 결과 폴더 `matlab/out/system_budget/`을 `README.md` '핵심 결과' 표의 "시스템 버짓" 행이 인용하고, `proposal/fill_form2.py` 441줄의 각주가 "k_raineye_system.m 결과"라고 적는다.
- 제안서에서 쓰인 숫자 (숫자, 제안서 위치, 결과 파일 경로):
  - 19.5 kg, 23.4 kg, 구조 4.5 kg, 레이더 전자부 4.0 kg — `proposal/content/feasibility.json` "1. 100 kg 이하인가?"; `system.json` "무게는 22~25 kg" — `matlab/out/system_budget/mass_budget.csv`, `key_system.json` `mass.sum/withMargin`
  - 35 W, 궤도당 15분, 24.4 W, 36.4 W, 약 1.5배, 배터리 약 19% — `feasibility.json` "2. 전력은 충분한가?"; `system.json` 표 '위성 본체에 바라는 조건' 전력 행 "궤도 평균 생산(36.4 W)이 필요량의 약 1.5배" — `power_budget.csv`, `key_system.json` `power.items.totalMargin`(24.41), `power.pv.oa`(36.40), `power.items.ratio`(1.491), `power.battery.DoD`(0.193)
  - 약 3.0 km(±10°), 약 1 km(천저) — `feasibility.json` "5. 바다 반사에 묻히지 않나?"; `overview.json`, `difficulty.json`의 "고도 약 3 km" — `offnadir_clean_height.csv` 10° 행 `cleanHeightFirstNullKm` 2.950, 0° 행 1.0875
  - 하루 5.9회, 평균 6.8분 — `system.json` 표 통신 행 — `key_system.json` `access.passPerDay`(5.933), `access.meanPassMin`(6.770), `daejeon_access.csv`
  - "관측 해역 위에 있는 동안 지상국이 늘 보였다" — `feasibility.json` "7." — `key_system.json` `access.fracWindowSamplesVisible` = 1 (208 표본)
  - 내려받기 4분, 지상 처리 5분, 전송 1분, 합계 10분, 여유 5분 — `feasibility.json` "7." — `latency_budget.csv`(1 + 3 + 1 = 지상 처리 5분)
  - 하루 약 60 MB, 용량 약 600 MB, 10분의 1, 링크 여유 9.9 dB — `feasibility.json` "7."; `system.json` "하루 자료량은 내려보낼 수 있는 양의 10분의 1 정도" — `key_system.json` `data.dataPerDayMB`(60.19), `data.downlinkCapPerDayMB`(602.5), `link_budget.csv` 하향 `margin_dB` 9.944
  - 12비트 ADC(유효 10비트), 1.8 MS/s, 필요 46 dB·여유 16 dB, 궤도당 가동 42분 이하, 상향 여유 32.9 dB, 거리 1,816 km — v2 제안서 본문 `proposal/_form_text_v2.md` 102·112·165·174·317줄 — `key_system.json` `dynamicRange`, `power.radarMaxMinPerOrbit`(42.3), `link.up.margin`, `link.rangeMax`

## 7. 본선 예상 질문 3개와 답
**Q1.** 16U 큐브위성에서 35 W짜리 레이더를 정말 돌릴 수 있나요? 태양전지판이 그만큼 나오나요?
**A.** 레이더는 궤도 95.6분 중 15분만 켜므로 궤도 평균으로는 5.5 W이고, 위성 전체 소요는 마진 20%를 넣어 24.4 W입니다. 16U 긴 네 면 넓이의 전개형 패널(0.41 m², 효율 29.5%)이 수명 말기에 햇빛 비율 0.63과 입사 계수 0.5로 36.4 W를 만들어 1.49배 여유가 있고, 이 한도 안에서는 레이더를 궤도당 42분까지 켤 수 있습니다. 단, 패널이 몸체 부착형이면 생산이 23 W로 떨어져 전개형이 필수 조건입니다(`matlab/out/system_budget/power_budget.csv`).

**Q2.** 위성을 10° 기울이면 바다 반사가 비를 가린다고 했는데, "3 km 위는 괜찮다"는 근거가 무엇인가요?
**A.** 기울이면 빔 안쪽 가장자리(첫 영점 기준 반각 1.17°)가 바다에 먼저 닿는데, 그 반사가 빔 중심선에서는 지표 위 1.86 km 높이의 비와 같은 시각에 돌아옵니다. 여기에 펄스압축 꼬리가 깨끗해지는 1.0 km와 해상도 절반을 더해 2.95 km이고, 지구 곡률까지 넣으면 약 3.15 km입니다. 장마 융해층(4.5~5 km)과 그 위가 목표이므로 ±10°에서도 상·중층은 정량 관측이 됩니다(`offnadir_clean_height.csv`).

**Q3.** 지상국이 대전 하나뿐인데 15분 안에 기상청까지 전달이 가능한가요?
**A.** 관측창(북위 28~38°, 동경 119~127°)의 가장 먼 모서리도 대전에서 약 1200 km라, 550 km 고도 위성이 관측창 안에 있을 때는 항상 대전에서 앙각 10° 이상으로 보입니다(30일 SGP4 모의, 208 표본 중 100%). 그래서 관측한 그 통과 안에서 바로 내려받고, 하향 4분 + 지상 처리 5분 + 전송 1분 = 10분으로 5분 여유를 둡니다. 단, 지연 예산의 단계별 시간은 운용 가정이고 아직 실측 근거는 없습니다.

## 8. 스스로 확인 문제 3개 (답은 부록)
1. 질량 마진을 20%가 아니라 30%로 잡으면 총질량은 몇 kg인가? (소계 19.5 kg)
2. 레이더를 궤도당 30분 켜면 레이더 평균 전력과 마진 포함 총소요는 얼마이고, 생산 36.4 W 안에 들어가는가? (궤도 95.65분, 나머지 항목 14.0 + 0.52 + 0.33 W)
3. 하향 속도를 2 Mbps에서 1 Mbps로 낮추면 Eb/N0 여유와 하루 하향 용량은 어떻게 바뀌는가? (현재 여유 9.94 dB, 하루 접속 40.17분)

## 9. 5분 설명 대본 (직접 채우기)
(빈칸)

## 10. 세 문장 요약 (직접 채우기)
1. 이 파일은 ______를 받아서 ______를 만든다.
2. 핵심 가정은 ______다.
3. 제안서에서 이 파일이 책임지는 숫자는 ______다.

## 부록. 확인 문제 답
1. 19.5 × 1.3 = 25.35 kg. 제안서의 "22~25 kg" 범위를 살짝 넘으므로, 마진을 키우려면 그 문구도 함께 고쳐야 한다.
2. 레이더 평균 35 × 30 / 95.65 = 10.98 W. 총소요 14.0 + 10.98 + 0.52 + 0.33 = 25.83 W, ×1.2 = 31.0 W. 생산 36.4 W 안이므로 여유 1.17배로 아직 들어간다(코드의 한도 42.3분과 일치하는 방향).
3. 속도를 반으로 줄이면 10·log10(2) = 3.01 dB가 Eb/N0에 더해져 여유 9.94 + 3.01 = 12.95 dB. 하루 용량은 1e6 × 40.17 × 60 / 8 / 1e6 = 301 MB로 절반이 되지만, 하루 자료 60 MB의 5배라 여전히 충분하다.
