# 09. k_raineye_analysis.m 해설

> 담당: C   대상 파일: `matlab/k_raineye_analysis.m` (930줄)   관련 결과 폴더: `matlab/out/` (fig1~fig10.png, summary.txt, key_results.json, key_sensitivity.json, key_nlfm.json, results.mat)

> 이 문서의 숫자는 모두 2026-10-17 20:30 실행 결과(`matlab/out/summary.txt` 첫 줄)에서 읽었다. 손으로 다시 계산한 값은 식을 함께 적었다.

## 1. 한 줄 역할
궤도·안테나·레이더 상수(코드 안에 하드코딩)와 합성 강수 세포(난수로 만든 가짜 비구름)를 받아서, 제안서의 수치 근거 다섯 묶음 — 궤도 통과 횟수와 큐잉(미리 알려 주기) 이득, 감도(최소로 잴 수 있는 비의 세기), Ka 감쇠(비에 전파가 약해지는 양), PRF(펄스 반복 주파수) 타이밍, 펄스압축 부엽(압축 뒤 주변으로 새는 신호) — 을 한 번에 계산해 그림 10장과 요약 파일로 만든다.

## 2. 흐름 (입력 → 처리 → 출력)
| 단계 | 하는 일 | 쓰는 함수·변수 | 나오는 것 |
|---|---|---|---|
| 0~1절 | 상수 설정: 지구(C), 궤도(O), 관측창(W), 레이더 지향(R), 세포 통계(S), 큐(Q), 관측 방식 15개(modes) | `struct`, `mkMode` | `modes`(15개), `mName` |
| 2절 | 120일 동안의 합성 강수 세포 수 결정, 난수로 생성 | `makeCells` | `cel`(세포 목록) |
| 3절 | 궤도 2종 × 초기 위상 8개를 J2 섭동 원궤도로 전파, 관측창 통과 추출, 방식별 관측 모의 | `propagate`, `passGeometry`, `evalModes` | `orbStat`, `out`, `passes` |
| 4절 | 위상 평균, 천저 고정 대비 배수 | `mean`, `gain` | `mStat`, `mOut`, `gain` |
| 5절 | 그림 1~4 | `geoplot`, `bar`, `plot` | fig1~fig4.png |
| 6절 | SGP4(위성통신 툴박스)와 교차검증 | `satelliteScenario` | `xcheck` 문자열 |
| 7절 | 모의 1 요약 저장 | `fprintf`, `save` | summary.txt, results.mat |
| 8절 | 감도 예산: RainCube 실측 11 dBZ에서 상대 스케일링, 16가지 가정 조합 | 레이더 방정식 비율식 | `Zc`(9.04 dBZ), `sens` |
| 9절 | Ka 강우 감쇠, 못 보는 최저 고도, 그림 5 | ITU-R P.838-3 `k·R^α` | `PIA`, `lowest`, fig5 |
| 10절 | PRF 타이밍 가능 영역, 그림 6 | `slantRange`, `mod` | `needPRI`, `prfMaxTheory`, fig6 |
| 11절 | 선형 처프 펄스압축 + 창 함수, 그림 7 | `phased.LinearFMWaveform`, `phased.MatchedFilter`, `pcMetrics` | `pcm`, fig7 |
| 12절 | 모의 2·3 요약 추가, JSON 저장 | `jsonencode` | summary.txt(추가), key_results.json |
| 13절 | 기동 민첩성·큐 지연 민감도 17가지, 그림 8 | `evalModes` 재사용 | `sv`, fig8, key_sensitivity.json |
| 14절 | NLFM(비선형 처프)·부정합 필터 5가지 설계 × 4가지 구성, 그림 9·10 | `lsMismatch`, `windowedMF`, `beamAvgFar` | `nlr`, fig9, fig10, key_nlfm.json |
| 로컬 함수 | 위 단계가 부르는 14개 함수 | — | — |

## 3. 절별 해설

### 3.0 머리말과 초기화 (줄 1~29)
```matlab
clear; close all;
rng(2026, 'twister');
here = fileparts(mfilename('fullpath'));
outDir = fullfile(here, 'out');
set(groot, 'defaultAxesFontName', 'Malgun Gothic', ...);
```
주석에 "모의 1~3이 제안서 어느 절의 근거인지"와 "모의 1의 가정"이 적혀 있다. `rng(2026)`으로 난수 씨앗을 고정해서 누가 돌려도 같은 세포 목록이 나온다. 결과는 파일 옆 `out/` 폴더에 쌓이고, 그림 글꼴을 맑은 고딕으로 두어 한글이 깨지지 않게 한다. Phased Array System Toolbox가 꼭 필요하다(11절).

### 3.1 매개변수 (줄 31~80)
```matlab
C = struct('Re', 6378.137, 'mu', 398600.4418, 'J2', 1.08262668e-3, 'we', 7.2921159e-5);
O.h = 550;  O.days = 120;  O.dt = 10;  O.nPhase = 8;
O.inc = [45, ssoInclination(C, 550)];          % [deg]
W.lat = [28 38];  W.lon = [119 127];           % 관측창
R.fpHalf = 5.4;  R.reachQ = 29;  R.reachU = 97; % km
R.slewRate = 1.0;  R.settle = 8;  R.dwell = 6;  % deg/s, s, s
Q.latency = [0 10 20 30 45 60];  Q.Lbase = 30;  % 큐 지연 [min]
modes = mkMode("천저 고정", "nadir", 0, 0, false);
```
C는 지구 상수(반지름 km, 중력 상수 km³/s², J2 편평도 계수, 자전 각속도 rad/s)로 `dp/kre_lib.m` 21줄과 똑같다. 궤도는 고도 550 km, 경사각 45°와 태양동기(ssoInclination이 97.6°로 계산) 두 가지를 120일 동안 10초 간격으로 본다. 관측창은 북위 28~38°, 동경 119~127°(장마 상류 바다)다. `reachQ = 29 km`는 롤 ±3°를 지상 거리로 바꾼 값(550 × tan 3° = 28.8 km), `reachU = 97 km`는 ±10°(550 × tan 10° = 97.0 km)다. 관측 방식은 "천저 고정", "완벽 정보(상한)", 큐 지연 0~60분 × (위치고정 / 나우캐스트) 12개, "±10° 나우캐스트 30분"까지 15개다.

### 3.2 합성 강수 세포 목록 (줄 82~91)
```matlab
Aext  = C.Re^2 * deg2rad(diff(lonExt)) * (sind(latExt(2)) - sind(latExt(1)));
Earea = pi * S.rMed^2 * exp(2 * S.rSig^2);
Elife = S.lMed * 60 * exp(S.lSig^2 / 2);
nCell = round(S.pRain * Aext * T / (Earea * Elife));
cel = makeCells(nCell, T, latExt, lonExt, S, Q);
```
"관측창 면적×시간의 8 %에 비가 온다"(S.pRain)는 가정에서 세포 수를 거꾸로 정한다. 세포 하나의 평균 면적(반경이 로그정규분포라 `πr²·exp(2σ²)`)과 평균 수명을 곱한 값으로 전체 면적×시간을 나누면 몇 개가 필요한지 나온다. 관측창 밖 150 km까지 여유를 두어(S.margin) 바깥에서 생겨 들어오는 세포도 포함한다. 실제 비가 아니라는 점이 이 파일의 가장 큰 한계이고, 뒤에 `k_raineye_imerg.m`과 `dp/` 폴더가 실제 IMERG 자료로 다시 계산했다.

### 3.3 궤도 전파와 통과별 관측 모의 (줄 93~129)
```matlab
for io = 1:nOrb
    for ip = 1:O.nPhase
        [t, lat, lon] = propagate(C, O.h, O.inc(io), phases(ip,1), phases(ip,2), gmst0, O.days, O.dt);
        inWin = lat >= W.lat(1) & lat <= W.lat(2) & lon >= W.lon(1) & lon <= W.lon(2);
        dIn = diff([false; inWin; false]);
        st = find(dIn == 1);  en = find(dIn == -1) - 1;
        orbStat(io, ip, :) = [sum(inWin)*O.dt/60/O.days, numel(st), mean((en-st+1)*O.dt)];
        ...
    end
    out(io, :, :, :) = reshape(evalModes(cel, passes(io, :), modes, R, W, S), ...);
end
```
초기 위상(승교점 적경, 궤도 위 위치) 8쌍을 난수로 뽑아 각각 120일을 전파한다. 위·경도가 관측창 안에 들어온 순간을 `diff`로 찾아 통과(pass)의 시작·끝을 자르고, 하루 체류 시간(분/일), 시즌 통과 횟수, 평균 통과 시간을 `orbStat`에 넣는다. 각 통과의 기하는 `passGeometry`가 km 단위 평면으로 바꿔 두고, `evalModes`가 방식 15개 모두를 한꺼번에 채점한다. 결과(`key_results.json` orbit): 경사 45°는 3.37분/일·257회, 태양동기는 1.81분/일·104회다. 확인: 257회 × 94.5 s ÷ (120일 × 60 s) = 3.37분/일로 서로 맞는다.

### 3.4 집계 (줄 131~141)
```matlab
mStat = squeeze(mean(orbStat, 2));               % nOrb x 3
mOut  = reshape(mean(out, 2), [nOrb, nM, 6]);    % nOrb x nM x 6
gain  = mOut ./ mOut(:, 1, :);                   % 천저 고정 대비 배수
iN30  = find(mName == sprintf("큐잉 ±3° 나우캐스트 %d분", Q.Lbase));
```
위상 8개를 평균해 궤도별 대푯값을 만들고, 모든 방식을 "천저 고정" 대비 배수로 바꾼다(`gain`). `out`의 6개 열은 [세포 수, 호우급 세포, warm형 세포, 프로파일 수, 정량 프로파일 수, 표적 수]다. 예: 경사 45° 나우캐스트 30분의 호우급 배수 = 321.75 ÷ 277 = 1.16배(`key_results.json` gain45.gainHeavy 10번째).

### 3.5 그림 1~4 (줄 143~213)
```matlab
geoplot(gx, dayTrack{io}(:, 1), dayTrack{io}(:, 2), '.', ...);      % 그림 1
bar(ax, categorical(O.name, O.name), vals(:, k), 0.6);               % 그림 2
Y = squeeze(mOut(1, sel, 1:3));  bar(ax, ..., Y, 'grouped');        % 그림 3
plot(ax, Q.latency, squeeze(gain(1, iNL, 1)), '-o', ...);           % 그림 4
```
그림 1은 하루 지상 궤적과 관측창(지도가 안 되면 보통 축으로 대체), 그림 2는 궤도 2종 비교 막대, 그림 3은 방식 5개의 세포 수(전체/호우급/warm형), 그림 4는 큐 지연(가로축)에 따른 배수 곡선이다. 그림 4에서 나우캐스트(이동 보정)가 위치고정보다 위에 있고, 지연 20분을 넘으면 ±3° 큐잉이 천저 고정(배수 1)보다 못해지는 것이 핵심 메시지다.

### 3.6 궤도 교차검증 (줄 215~233)
```matlab
if exist('satelliteScenario', 'file')
    sat = satellite(sc, (C.Re + O.h) * 1e3, 0, 45, rad2deg(phases(1,1)), 0, rad2deg(phases(1,2)), 'OrbitPropagator', 'sgp4');
    pos = states(sat, 'CoordinateFrame', 'ecef');
    latX = asind(pos(3, :) ./ rr);  lonX = atan2d(pos(2, :), pos(1, :));
```
자체 J2 전파기가 맞는지 3일 동안 MathWorks의 SGP4 전파기와 체류 시간을 비교한다. 결과 3.78 vs 3.83분/일(1.3 % 차이)로 자체 모델을 믿어도 된다는 근거다(`key_results.json` orbit.xcheck).

### 3.7 요약 저장 (줄 235~270)
```matlab
fid = fopen(fullfile(outDir, 'summary.txt'), 'w', 'n', 'UTF-8');
pr('  %s (경사 %.1f°): 관측창 체류 %.2f 분/일 (%.2f~%.2f), 통과 %.0f회/시즌 ...', ...);
save(fullfile(outDir, 'results.mat'), 'O', 'W', 'R', 'S', 'Q', 'mName', 'orbStat', 'out', 'mStat', 'mOut', 'gain', 'xcheck');
```
summary.txt를 새로 쓰고(이후 절은 'a'로 이어 붙임) 표와 가정을 글로 남긴다. results.mat에는 모의 1 변수만 저장되고 8절 이후의 감도·감쇠 결과는 key_results.json에만 있다.

### 3.8 모의 2: 감도 예산 (줄 272~317)
```matlab
Vg   = C.Re * sqrt(C.mu / (C.Re + O.h)^3);           % 지상 궤적 속도 [km/s]
fpKm = 2 * O.h * tand(1.13 / 2);  Tfp = fpKm / Vg;    % 풋프린트 10.85 km, 통과 1.55 s
Ref.R = 400;  Ref.PRF = 1 / 1660e-6;  Ref.B = 2.5e6;  Ref.Zs = [11.0 13.0];
ant.dG = 2 * (ant.G - ant.G(1)) + 20 * log10(ant.bw / ant.bw(1));
d = 20*log10(O.h/Ref.R) - 5*log10(pf/Ref.PRF) - 5*log10(Tfp/tr) - ant.dG(ia);
if ub, d = d + 5 * log10(Bnew / Ref.B); end
sens(end + 1, :) = [zr, tr, pf, ub, ia, zr + d];
```
감도를 처음부터 계산하지 않고, RainCube가 궤도에서 실제로 잰 11.0 dBZ(400 km)에서 "달라진 것만" 더하고 뺀다. 거리가 멀면 되돌아오는 전력이 거리²에 반비례하므로 +20log10(550/400) = +2.77 dB 나빠진다. 펄스를 더 많이 쏘면(PRF 1800 vs 602 Hz) 잡음이 평균되어 √N만큼 좋아지므로 −5log10(1800/602) = −2.38 dB, 적분 시간이 길면 −5log10(1.55/1.09) = −0.76 dB, 대역이 좁으면(1.2 vs 2.5 MHz) +5log10(1.2/2.5) = −1.59 dB(부호 설명은 5절 2번). 합: 11.0 + 2.77 − 2.38 − 0.76 − 1.59 = 9.04 dBZ가 중심값 `Zc`다. 기준값 2개 × 적분시간 2개 × PRF 2개 × 대역 보정 유무 2개 = 16가지가 0.5 m 안테나 조합이고 6.1~13.0 dBZ(`key_results.json` sens.range05), 1 m 안테나는 이득 차 7.5 dB(2×6.6 dB − 5.7 dB)만큼 더 좋다.

### 3.9 모의 2: Ka 강우 감쇠와 관측 깊이 (줄 319~358)
```matlab
kR = 0.3452;  aR = 0.8851;                            % ITU-R P.838-3, 35.75 GHz 연직
gam = kR * Rr.^aR;                                    % 비감쇠 [dB/km, 단방향]
Hr  = 4.5;  PIA = 2 * gam * Hr;                       % 왕복 경로적분감쇠 [dB]
Ztrue  = 10 * log10(200 * Rr.^1.6);                   % Marshall-Palmer
Zm(:, k) = Ztrue(k) - 2 * gam(k) * (Hr - hg);
vis = Zm(:, k) >= Zc;  lowest(k) = hg(find(vis, 1));
```
비감쇠(1 km 지날 때 약해지는 dB)는 강우율 R(mm/h)의 거듭제곱 `k·R^α`로 주어진다. 예: 20 mm/h → 0.3452 × 20^0.8851 = 4.89 dB/km. 비가 지표부터 4.5 km(액상층, 그 위는 얼음이라 감쇠 작음)까지 고르게 온다고 보고, 전파가 내려갔다 올라오므로 ×2 해서 왕복 PIA = 2 × 4.89 × 4.5 = 44 dB다. 높이 h에서 보이는 반사도는 참값(마셜-파머 식, 20 mm/h → 43.8 dBZ)에서 그 위 비층의 왕복 감쇠를 뺀 값이고, 이것이 감도 9.04 dBZ 아래로 떨어지는 높이가 "못 보는 최저 고도"다. 20 mm/h: 43.8 − 9.79 × (4.5 − h) ≥ 9.04 → h ≥ 0.95 km(`key_results.json` rain.lowest 3번째).

**그림 5(fig5_attenuation.png) 읽는 법.** 왼쪽: 가로축이 위성에서 보이는 반사도, 세로축이 고도. 선 하나가 강우율 하나이고 아래로 갈수록 왼쪽으로 기운다(비층을 더 많이 지나 더 약해짐). 점선(감도 9.0 dBZ)과 만나는 높이 아래는 못 본다 — 50 mm/h(초록)는 약 2.65 km, 20 mm/h(노랑)는 약 0.95 km, 5·10 mm/h는 바닥까지 보인다. 오른쪽: 왕복 PIA 막대(13·24·44·63·99 dB). 분홍 띠(42~49 dB)는 해면 반사로 PIA를 잴 수 있는 한계 가정이라 30 mm/h 이상은 해면 기준 보정도 어렵다는 뜻이다.

### 3.10 모의 3: PRF 타이밍 (줄 360~391)
```matlab
tau = 166e-6;  guard = 10e-6;  Htop = 20;  Hbot = -3;
Rs  = slantRange(C.Re, O.h, angs(ia));
inc = asind((C.Re + O.h) / C.Re * sind(angs(ia)));
t1  = 2 * (Rs - Htop / cosd(inc)) * 1e3 / c0;
t2  = 2 * (Rs - Hbot / cosd(inc)) * 1e3 / c0 + tau;
feas(ia, ip) = (w + tau + guard <= PRI) && (ph >= tau + guard) && (ph + w <= PRI);
```
레이더는 송신하는 동안 수신을 못 하므로, 고도 20 km부터 지표 아래 3 km(거울상 여유)까지의 메아리가 돌아오는 창(t1~t2)이 다음 펄스 송신(166 µs + 보호 10 µs)과 겹치지 않아야 한다. 창 길이는 왕복 23 km ÷ 빛의 속도 = 153 µs에 펄스 길이 166 µs를 더한 319 µs이고, 송신 176 µs를 더하면 PRI(펄스 간격)가 최소 495 µs, 즉 PRF 최대 2.02 kHz다. 다만 메아리가 어느 펄스 뒤에 떨어지느냐(`ph = mod(t1, PRI)`)가 각도마다 달라서, 1.8 kHz 고정으로는 0~10° 중 73 %만 가능하고 1.5 kHz는 100 %, 1.5~1.8 kHz를 각도별로 바꾸면 100 %다(`key_results.json` prf). 그림 6은 이 가능 영역을 PRF × 롤 각도 평면에 초록으로 칠한 것이다.

### 3.11 모의 3: 펄스압축 거리 부엽 (줄 393~430)
```matlab
wav = phased.LinearFMWaveform('SampleRate', fs, 'PulseWidth', tau, 'PRF', 1600, 'SweepBandwidth', Bs(ib), ...);
coef = getMatchedFilter(wav);
mf = phased.MatchedFilter('Coefficients', coef, 'SpectrumWindow', 'Taylor', 'SidelobeAttenuation', 40, 'Nbar', 5, ...);
y = mf([x; zeros(numel(coef), 1)]);
[res, psl, far, rgm, adb] = pcMetrics(abs(y), fs, c0);
```
166 µs 긴 펄스를 주파수를 훑으며(처프) 쏘고 정합 필터로 압축하면 해상도 c/(2B)가 된다(1.2 MHz → 125 m). 압축 출력 옆에는 부엽이 생기는데, 창 함수(Hann, Taylor)를 주파수 영역에 곱하면 부엽은 내려가고 주엽은 넓어진다. 0.6/1.2 MHz × 창 3종 = 6가지를 돌려 [−3 dB 해상도, 첨두 부엽, 1 km 밖 최대 부엽]을 잰다. 1.2 MHz + Taylor: 169 m, −37.3 dB, 1 km 밖 −41.0 dB(`key_results.json` pc).

**그림 7(fig7_pulse_compression.png) 읽는 법.** 가로축은 첨두(표적)로부터의 거리 km, 세로축은 첨두를 0 dB로 둔 출력. 가운데 뾰족한 봉우리가 주엽(파랑 0.6 MHz가 가장 넓음 = 해상도 나쁨), 양옆 물결이 부엽이다. 점선 −60 dB는 "해면 반사(약 59 dBZ)가 약한 비(약 0 dBZ)를 덮지 않으려면 이만큼 내려가야 한다"는 거친 요구선인데, 세 곡선 모두 ±1 km에서 −40 dB 근처라 요구에 20 dB 모자란다. 이 부족이 14절(NLFM·부정합 필터)을 만든 이유다.

### 3.12 모의 2·3 요약 추가와 JSON (줄 432~477)
```matlab
key.sens = struct('central', Zc, 'range05', [min(s05) max(s05)], 'range10', ..., 'dG1m', ant.dG(2), 'meet13_05', mean(s05 <= 13), ...);
key.rain = struct('R', Rr, 'gamma', gam, 'gammaRainpl', gamPL, 'PIA', PIA, 'Ztrue', Ztrue, 'lowest', lowest);
key.prf  = struct('needPRI', needPRI, 'prfMax', prfMaxTheory, 'f15', fixedFrac(1500), ...);
key.pc   = struct('B', Bs, 'wins', wins, 'res', pcm(:, :, 1), 'psl', pcm(:, :, 2), 'far', pcm(:, :, 3));
fprintf(fidj, '%s', jsonencode(key, 'PrettyPrint', true));
```
summary.txt 뒤에 모의 2·3 표를 붙이고, 뒤 파일들이 읽기 쉽게 `key_results.json`에 숫자만 모아 둔다. `meet13_05 = 0.9375`는 16개 중 15개가 13 dBZ 이하라는 뜻(15/16)이다. 교차검증 문자열, 궤도 배수(gain45·gainSSO)도 함께 들어간다.

### 3.13 모의 1-b: 지향 민첩성·큐 지연 민감도 (줄 479~539)
```matlab
V = mkV("기준: 정착 8 s·응시 6 s·1°/s·±3°·30분", 8, 6, 1, R.reachQ, 30, false);
V(end+1) = mkV("현실 목표안: 정착 4 s·응시 3 s·1.5°/s·10분·전체", 4, 3, 1.5, R.reachQ, 10, false);
for iv = 1:nV
    Rv = R;  Rv.settle = V(iv).settle;  Rv.dwell = V(iv).dwell;  Rv.slewRate = V(iv).slew;
    mv = mkMode(V(iv).label, "nowcast", V(iv).reach, V(iv).L, V(iv).ho);
    rv = squeeze(mean(evalModes(cel, passes(1, :), mv, Rv, W, S), 1));
    sv(iv, :) = [rv(1)/nadirRes(1), rv(2)/nadirRes(2), rv(4)/nadirRes(4), rv(5)/nadirRes(5), rv(6)/nPass45];
end
```
3절에서 만든 통과 목록을 다시 써서, 정착 시간(기동 뒤 흔들림이 가라앉는 시간)·응시 시간·기동 속도·허용 각도·큐 지연·호우급만 겨냥 여부를 한 가지씩, 그리고 묶어서 바꾼 17가지를 경사 45°에서 돌린다. 모두 천저 고정 대비 배수다. 결과(`key_sensitivity.json`): 기준안은 호우급 1.16배, 정착을 8→2 s로 줄이면 1.28배, 큐 지연 30→10분이면 1.39배, "현실 목표안(정착 4 s·응시 3 s·1.5°/s·10분)"은 호우급 1.51배·정량 프로파일 1.54배다.

**그림 8(fig8_agility_sensitivity.png) 읽는 법.** 세로로 17개 조건, 가로가 천저 고정 대비 배수이고 회색 세로선 1.0이 "천저와 같음"이다. 파랑 = 전체 세포, 주황 = 호우급, 노랑 = 정량 프로파일(±3° 안에서 얻은 높이별 단면 수). 눈여겨볼 것 셋: (1) 기준안 파랑이 0.99로 1보다 작다 — 30분 늦은 큐로 ±3°만 겨냥하면 전체 세포는 오히려 손해다. (2) "허용 ±5°"에서 노랑이 0.69로 뚝 떨어진다 — 멀리 겨냥하면 정량 관측(±3° 조건)에서 빠진다. (3) 맨 아래 "현실 목표안 10분·전체"가 1.31/1.51/1.54로 가장 균형 있다. 단, 이 배수는 합성 세포 결과이고 실제 IMERG에서는 재현되지 않았다(README 핵심 결과의 경고).

### 3.14 모의 3-b: NLFM 설계와 거리 부엽 절충 (줄 541~640)
```matlab
Zsurf = 10 * log10(10^(sig0/10) / dRb * lam^4 / (pi^5 * K2) * 1e18);   % 해면 상당 반사도 58.7 dBZ
fdC  = 2 * 7.6e3 / lam * sind(bwC / 2);                               % 빔 가장자리 도플러
fiN  = interp1(tauC * cumtrapz(fg, wTay) / trapz(fg, wTay), fg, tC, 'pchip');   % NLFM 순간 주파수
pairs = {sLFM, windowedMF(...); sNL, conj(flipud(sNL)); sLFM, lsMismatch(...); sNL, lsMismatch(...); sTp, lsMismatch(...)};
dCfg = -10 * log10(tauC / 166e-6) - ant.dG(1 + (cfg(ic).D > 0.75));
loss = 10 * log10(norm(sLFM)^2 / (max(abs(y))^2 / norm(h)^2));
Zmin = Zc + dCfg + loss;  need = -(Zsurf - Zmin);
[farB, hClean, rg, pdb] = beamAvgFar(s, h, tC, fsN, c0, fdC, -need);
nlr(ic, id, :) = [res, psl, far, loss, farB, hClean, Zmin, need, need - farB];
```
바다 표면은 레이더에 아주 밝게 보인다(σ0 = 10 dB를 250 m 구간의 반사도로 바꾸면 58.7 dBZ). 그 부엽이 감도선(약 10 dBZ)보다 낮으려면 부엽이 −(58.7 − 10.5) ≈ −48 dB 아래여야 하는데, 7번 그림의 창 함수로는 −41 dB가 한계다. 그래서 5가지 설계(LFM+테일러 창, NLFM+정합, LFM+최소제곱 부정합 필터, NLFM+부정합, 가장자리 20 % 테이퍼 LFM+부정합)를 4가지 구성(펄스 166/83 µs × 안테나 0.5/1 m)에서 비교한다. 핵심은 "빔 평균": 위성이 7.6 km/s로 움직여 빔 가장자리의 해면 메아리는 ±17.9 kHz(0.5 m) 도플러 이동을 갖는데, 이를 가우시안 빔 가중으로 평균하면 NLFM은 부엽이 −14 dB까지 망가진다(도플러에 약함). 반면 테이퍼 LFM+부정합 필터는 빔 평균 −48.1 dB로 요구 −48.1 dB에 딱 걸리고(여유 −0.1 dB), 지표 위 1.02 km부터 오염이 없다. 그 대가가 SNR 손실 1.49 dB → 감도 9.04 + 1.49 = 10.5 dBZ(`key_nlfm.json` loss(1,5), Zmin(1,5)). 이것이 제안서 대표 감도다.

**그림 9(fig9_nlfm.png) 읽는 법.** 왼쪽: 펄스 안 시간(0~166 µs)에 따라 순간 주파수가 −0.6에서 +0.6 MHz로 올라가는 모습. 파랑(LFM)은 직선, 주황(NLFM)은 가운데에서 천천히·양끝에서 빨리 훑어 가운데 주파수에 에너지를 몰아 창 함수 효과를 낸다. 오른쪽(166 µs·1 m 구성): 해면 첨두로부터의 거리에 대한 빔 평균 출력. 주황(NLFM+정합)은 ±1 km 밖에서 −40 dB쯤이고 어깨가 넓다 — 도플러에 약하다. 보라(LFM 테이퍼+부정합)는 ±1 km 밖에서 −70 dB 아래로 떨어져 점선 요구선(−55.7 dB)을 넉넉히 통과한다. 노랑(LFM+부정합, 테이퍼 없음)은 요구선에 못 미친다. 그림 10은 같은 '여유 dB'를 4구성 × 5설계 막대로 요약한 것이다(0 이상이면 통과).

### 3.15 로컬 함수 (줄 642~930)
```matlab
function h = lsMismatch(s, M, excl, ld)     % 주엽 밖 에너지 최소화, 중심 출력 1로 고정
function [farB, hClean, rg, pdb] = beamAvgFar(s, h, tN, fs, c0, fdHalf, dyn)   % 빔 가중 도플러 평균
function h = windowedMF(s, fs, B, sll)      % 정합 필터 × 테일러 창(주파수 영역)
function res = evalModes(cel, passRow, modes, R, W, S)   % 통과×방식 채점
function inc = ssoInclination(C, h)         % 태양동기 경사각
function [t, lat, lon] = propagate(...)     % J2 원궤도 → 위경도
function c = makeCells(...)                 % 합성 세포 난수 생성
function P = passGeometry(t, lat, lon)      % 통과를 km 평면 직선 구간으로
function [tc, cc, latS, lonS] = crossTimes(P, x0, y0, vx, vy, tref)   % 세포가 궤적을 가로지르는 시각
function acc = schedule(cand, ts, R)        % 기동 시간이 맞는 표적만 채택
function s = slewTime(c1, c2, R)            % 롤 각도 차/속도 + 정착
function [cb, valid] = beamAt(acc, tq, R)   % 시각별 빔 위치, 기동 중이면 무효
function Rs = slantRange(Re, h, offDeg)     % 오프나디르 각 → 경사거리
function [res, psl, far, rgm, adb] = pcMetrics(a, fs, c0)   % 해상도·첨두 부엽·1 km 밖 부엽
```
가장 중요한 셋만 풀어 쓴다. **propagate**: 원궤도에서 J2(지구가 납작해서 생기는 섭동) 때문에 승교점이 `−1.5·n·k·cos i`로 돌고, 궤도 위 각도는 `n[1 + 1.5k(4cos²i − 1)]`로 흐른다(근지점 이동 + 평균 근점 이각 변화의 합). 그 뒤 지구 자전각 `gmst0 + ωe·t`만큼 돌려 위·경도를 만든다. **evalModes**: 통과마다 (1) 어떤 세포가 실제로 위성 궤적을 언제·얼마나 옆으로 지나는지(`crossTimes`), (2) 큐 시각에 보였던 세포 위치를 나우캐스트로 미루어 표적 후보를 만들고(`schedule`로 기동 가능한 것만 채택), (3) 그 시각에 빔이 어디를 보고 있었는지(`beamAt`)를 대조해 명중(빔 중심과 세포 중심 거리 ≤ 세포 반경 + 풋프린트 반폭)을 센다. 프로파일 수는 "세포를 가로지르는 현의 길이 ÷ 지상 속도 ÷ 1.5 s"다. **schedule**: 호우급 우선, 시각 순으로 넣되 앞뒤 표적과의 기동 시간(각도 차 ÷ 1°/s + 정착 8 s)이 맞아야 채택한다.

## 4. 핵심 가정 3개
1. **감도는 RainCube 실측 11.0 dBZ에서 상대 스케일링으로 얻는다(8절)** — 송신 전력·안테나 효율 같은 세부 값을 모르므로 "달라진 것"만 더하고 뺀다. 깨지면: 기준값의 적분 시간·대역·PRF(모두 2차 자료)가 틀리면 중심값이 통째로 움직인다. 특히 RainCube PRI 1660 µs(PRF 602 Hz)가 사실 PRF 1660 Hz라면 PRF 항이 −2.38 dB에서 −0.18 dB로 바뀌어 중심값이 약 2.2 dB 나빠진다(확인 못 함, 5절 참고). 그래서 16가지 조합으로 범위를 같이 낸다.
2. **비는 지표부터 4.5 km까지 고르게 오고 그 위는 감쇠가 없다(9절)** — 장마 융해층(얼음이 녹는 높이) 약 4.5~5 km를 액상층 두께로 썼고 `k_raineye_sens_pcloss.m` 53줄, `k_raineye_system.m` 70줄과 같은 4.5다. 깨지면: 융해층이 5 km면 PIA가 11 % 늘고 못 보는 높이가 올라간다; 비가 고르지 않으면(대류 세포) 국소 PIA가 훨씬 클 수 있다.
3. **펄스 간 메아리는 서로 독립이고, 빔 안 도플러는 가우시안 빔으로 가중된다(8·14절)** — 위성 속도 때문에 빔 가장자리 도플러가 ±17.9 kHz라 상관 시간이 수십 µs로 PRI 555 µs보다 훨씬 짧아 '펄스 수 N → √N 개선'이 성립한다. 깨지면: 독립 표본이 줄어 감도가 나빠지고, 14절에서는 같은 도플러 퍼짐이 NLFM을 기각시킨 이유이므로 빔 모양이 다르면 부엽 여유 숫자가 달라진다.

## 5. 코드 검토 결과
| 번호 | 줄 | 지적 | 어떤 입력에서 틀어지나 | 판정 | 근거 |
|---|---|---|---|---|---|
| 1 | 289 | 안테나 이득 차 `dG = 2ΔG + 20log10(θ/θ0)`의 부호: 빔이 좁아지면(θ 작음) 20log 항이 음수가 되어 이득 효과를 깎는 게 맞나? | 모든 입력 | **문제 없음(오해)** | 체적 표적의 수신 전력 ∝ G²·θ²이므로 감도 개선량은 2ΔG + 20log10(θ/θ0)이 맞다. 1 m: 2×6.6 − 5.69 = 7.51 dB = `key_results.json` sens.dG1m. 코드는 `d = ... − ant.dG`로 빼므로 1 m가 7.5 dB 좋아진다 |
| 2 | 300 | 대역 보정 `+5log10(B/B0)`: 대역이 좁으면(1.2 < 2.5 MHz) 음수가 되어 감도가 **좋아지는데**, 주석은 "독립 거리 표본 수"라서 반대로 읽힌다 | 모든 입력 | **문제 없음(오해)** | 거리 셀 하나의 에너지 ∝ 1/B, 250 m 안의 독립 셀 수 ∝ B(√로 평균)라 순효과는 √B에 비례 → +5log10(B/B0) = −1.59 dB가 맞다. 보정을 빼면 중심값 10.63 dBZ. 주석만 "셀 에너지 ↑, 독립 표본 ↓의 합"으로 고치면 좋다 |
| 3 | 322 | ITU-R P.838-3 계수 0.3452/0.8851이 표(35 GHz: kV 0.3224, 40 GHz: 0.4274)의 보간값과 다르다 | 모든 강우율 | **문제 없음(오해)** | P.838-3 공식으로 35.75 GHz를 계산하면 kH 0.3528·αH 0.8987, kV 0.3375·αV 0.8708이고, 연직 경로(앙각 90°) 식 k = (kH+kV)/2 = 0.3452, α = (kH αH + kV αV)/(2k) = 0.8850으로 코드와 일치. 왕복 ×2, Hr 4.5도 다른 파일과 같다 |
| 4 | 279, 303, 383 | 감도 중심값은 PRF 1.8 kHz를 가정하는데, 10절 결과는 1.8 kHz 고정이 각도의 73 %에서만 가능하다 | 롤 5° 부근에서 1.8 kHz를 못 쓰는 각도 | **개선 제안(결과에는 영향 없음)** | 1.5 kHz로 바꾸면 중심값은 9.04 + 5log10(1800/1500) = 9.43 dBZ. 16조합에 PRF 1500이 이미 들어 있어 범위(6.1~13.0)는 그대로이지만, "중심값 = 1.8 kHz"라는 전제를 문서에 밝히는 게 좋다 |
| 5 | 414 | 그림 7의 요구선 `yline(−60, '요구 −60 dB(해면 대비)')`이 14절에서 계산한 요구 −48 dB(= −(58.7 − 10.5))와 다르다 | 그림 표기만 | **개선 제안(결과에는 영향 없음)** | −60은 14절 전에 쓴 어림값이고 수치 결과에는 안 쓰인다. 그림 7 선을 `nlr(1,5,8)`로 그리거나 캡션에 "어림 요구"라고 적으면 두 그림이 맞는다 |
| 6 | 550 | 해면 상당 반사도 `Zsurf`를 출력 구간 250 m(dRb)로 나누는데, 채택안의 실제 해상도는 175 m라 해면 에너지가 더 좁은 셀에 몰린다 | 채택안(여유 −0.1 dB)처럼 경계에 걸린 구성 | **개선 제안(결과에는 영향 없음)** | 175 m로 두면 Zsurf가 10log10(250/175) = 1.55 dB 올라 요구가 −49.7 dB, 여유가 −1.6 dB가 된다. 제안서의 "±10°에서 3.0 km" 수치는 `k_raineye_system.m`이 58.7을 그대로 쓰므로 함께 다시 보면 좋다. 정의의 문제이지 계산 오류는 아니다 |
| 7 | 136, 462~471, 536 | 결과 저장 키와 값: `gain`의 4번째 열이 '프로파일'인데 JSON 키는 gainProf, 13절 `sv(:,4)`가 정량 프로파일인데 그림 8 범례와 키 gainQuant가 맞는가 | 저장 파일만 | **문제 없음(오해)** | `out` 열 순서 [세포, 호우, warm, 프로파일, 정량, 표적]대로 gain(:,:,4) = 프로파일, sv(:,4) = 정량이 맞다. 교차 확인: mStat 체류 3.37 = 257회 × 94.5 s ÷ 7200, key_nlfm Zmin(1,5) − key_results central = 1.49 = loss(1,5), README '1.51/1.54'는 key_sensitivity 마지막 행 |
| 8 | (없음) | 이 파일은 `out/run_log.csv`에 실행 줄을 남기지 않는다(다른 MATLAB 파일은 남김) | 실행 기록 추적 | **개선 제안(결과에는 영향 없음)** | run_log.csv에 k_raineye_analysis 줄이 없다. 요약 파일 첫 줄의 날짜(2026-10-17 20:30)로만 실행 시각을 알 수 있다. 끝에 `fprintf(fid, '%s,k_raineye_analysis,%s,"..."\n', ...)` 한 줄을 붙이면 된다 |

판정 요약: 진짜 버그 0, 문제 없음(오해) 4, 개선 제안 4.

**어떻게 확인했나(각 번호).**
1. `checks/check09.m` CHECK 1: λ = c/35.75 GHz, 빔폭 70λ/1 m로 dG를 다시 계산해 `sens.dG1m`과 1e-6 이내 비교.
2. CHECK 2: 네 항을 손 계산 식으로 다시 더해 `sens.central`과 비교하고, 대역 보정을 뺀 값(10.63)도 함께 출력.
3. CHECK 3: P.838-3 공식 계수(kH·kV·αH·αV 각 4~5항 가우시안 합)를 넣어 35.75 GHz 값을 만들고 연직 경로 식으로 k·α를 구해 코드 상수와 0.3 % 이내 비교. 같은 상수로 γ, PIA = 2γ·4.5, 못 보는 높이까지 재계산해 `rain`과 비교.
4. CHECK 4: `needPRI`(= 2×23 km/c + 166 + 176 µs)와 `prfMax`를 재계산하고, `prf.f18 < 1`인데 중심값이 1800 Hz를 쓰는지 확인(맞으면 지적이 성립하므로 FAIL로 표시).
5. CHECK 5: `key_nlfm.json`의 need(1,5)가 −60과 1 dB 이상 다르면 FAIL(지적이 맞음).
6. CHECK 6: Zsurf를 공식으로 재계산(58.7)하고 175 m 기준 여유를 구해 1 dB 이상 나빠지면 FAIL(지적이 맞음).
7. CHECK 7: results.mat의 mStat·orbStat·O.inc와 JSON 세 파일의 값을 서로 대조(체류 = 통과×통과시간, 태양동기 경사 97.6°, loss 1.49, 마지막 행 1.51/1.54).
8. CHECK 8: run_log.csv에 'k_raineye_analysis' 문자열이 없으면 FAIL(지적이 맞음).

### 5.9 확인 스크립트 실행 결과 (2026-10-31, `checks/check09.m`, 8.0초)

PASS = 코드가 의도대로 동작함(지적이 오해이거나 버그 없음), FAIL = 지적이 맞음(개선 제안 포함).

| 번호 | 결과 | 설명 |
|---|---|---|
| 1 | **PASS** | dG(1 m) 재계산 7.511 dB vs json 7.511 dB (양수 = 1 m가 유리, 코드는 d에서 뺌) |
| 2 | **PASS** | 중심값 11 +2.77 -2.38 -0.76 -1.59 = 9.036 dBZ vs json 9.036 (대역 보정 빼면 10.63) |
| 3 | **PASS** | P.838-3 연직 k=0.3452 a=0.8851 (코드 0.3452/0.8851), PIA 20 mm/h 44.0 dB, 못 보는 높이 [0 0 0.95 1.85 2.65] km |
| 4 | **FAIL** | 필요 PRI 495.4 us, 최대 PRF 2.018 kHz (json 일치 1); 1.8 kHz 가능 비율 73%인데 중심값은 1.8 kHz 가정, 1.5 kHz면 9.43 dBZ |
| 5 | **FAIL** | 14절 요구 부엽 -48.1 dB (= -(58.7 - 10.5)), 그림 7 선은 -60 dB |
| 6 | **FAIL** | Zsurf 재계산 58.66 dBZ (json 58.66); 해상도 175 m 기준이면 60.21 dBZ, 채택안 여유 -0.05 -> -1.60 dB |
| 7 | **PASS** | 체류 3.37 vs 통과×시간 3.37 분/일, SSO 경사 97.59°, Zmin-Zc = 1.49 dB = loss, 마지막 행 호우 1.51·정량 1.54, 13 dBZ 충족 15/16 |
| 8 | **FAIL** | run_log.csv에 k_raineye_analysis 줄 없음 |

요약: PASS 4개, FAIL 4개.

**판정 대조:** FAIL로 나온 항목은 모두 5절 표에서 이미 그렇게 판정한 지적(개선 제안)이다. 제안서에 쓰인 숫자(이득 배수, 감도, 감쇠 높이, 신뢰구간)는 어느 FAIL에도 영향을 받지 않는다.

## 6. 다른 문서와의 연결
- 이 파일이 부르는 것: MATLAB 기본 + Phased Array System Toolbox(`phased.LinearFMWaveform`, `phased.MatchedFilter`, `taylorwin`, `tukeywin`), 있으면 Satellite Communications Toolbox(`satelliteScenario`)와 `rainpl`. 프로젝트 안 다른 .m 파일은 부르지 않는다(로컬 함수만 씀).
- 이 파일을 부르는 것(결과 파일을 읽는 것):
  - `matlab/k_raineye_sens_pcloss.m`(10번 문서) — `out/key_nlfm.json`의 loss(1,5) = 1.49 dB와 Zmin(1,5) = 10.5 dBZ를 읽고, 이 파일 8~9절의 식을 그대로 옮겨 **감도 16조합과 감쇠 높이를 펄스압축 손실을 더한 10.5 dBZ 기준으로 다시 계산**했다. 그래서 이 파일의 "16개 중 15개 ≤ 13 dBZ, 최악 13.0 dBZ, 못 보는 높이 0.95/1.85 km(20/30 mm/h)"가 제안서에서는 "14/16, 최악 14.5 dBZ, 1.1/1.95 km"로 바뀌어 있다(`out/sens_pcloss/summary.txt`).
  - `matlab/k_raineye_system.m` 37~38줄 — Zmin 10.5 dBZ, Zsurf 58.7 dBZ를 상수로 받아 ±10° 클러터 고도(3.0 km)를 낸다.
  - `matlab/tools/make_report.py` → `K-RainEye_MATLAB_결과보고.html` — out/의 그림·json으로 보고서를 만든다.
  - `dp/kre_lib.m` 21줄 — 지구 상수 C와 `propagate` 식을 같은 형태로 쓴다(코드 복사본).
- 제안서에서 쓰인 숫자 (숫자, 제안서 위치, 결과 파일 경로):
  - 경사 45° 체류 3.37분/일·257회, 태양동기 1.81분/일·104회 — `proposal/content/feasibility.json` blocks[27] — `matlab/out/key_results.json` orbit.dwell/passes
  - 두 궤도 계산법(SGP4 vs J2) 일치 — feasibility.json blocks[28] 근처 — key_results.json orbit.xcheck(3.78 vs 3.83분/일)
  - 출발점 RainCube 실측 11.0 dBZ(400 km) — feasibility.json blocks[12] — 코드 `Ref.Zs(1)`(줄 285)
  - 손실 넣기 전 감도 9.0 dBZ(그림 점선) — feasibility.json blocks[19] 캡션 — key_results.json sens.central = 9.04
  - 대표 감도 10.5 dBZ(요구 13) — feasibility.json blocks[11], `system.json` blocks[10] — `matlab/out/key_nlfm.json` Zmin(1,5) = 10.53(이 파일 14절), 재확인 `out/sens_pcloss/summary.txt`
  - 16가지 중 14가지 ≤ 13 dBZ, 최악 14.5 dBZ, 1 m 안테나면 16/16 — feasibility.json blocks[13] — `out/sens_pcloss/summary.txt`(이 파일 값 15/16·13.0에 1.49 dB를 더한 것)
  - 20 mm/h 1.1 km, 30 mm/h 1.95 km 못 봄 — feasibility.json blocks[20] 근처 — `out/sens_pcloss/summary.txt`(이 파일 9절은 9.0 dBZ 기준 0.95/1.85 km, key_results.json rain.lowest)
  - 융해층 약 4.5~5 km, 바로 아래 약 1 km 위부터 깨끗 — feasibility.json blocks[23] — 코드 `Hr = 4.5`(줄 330), key_nlfm.json cleanH(1,5) = 1.02 km (±10°의 3.0 km는 `out/system_budget/`)
  - 높이 간격 175 m — system.json blocks[10] — key_nlfm.json res(1,5) = 175 m
  - PRF 최대 2.02 kHz·1.5~1.8 kHz 가변, 빔 안 도플러 ±17.9 kHz로 NLFM 기각, 빔평균 부엽 −48 dB — `README.md` 핵심 결과 표 — key_results.json prf, key_nlfm.json farBeam(1,5) = −48.1, summary.txt 모의 3-b
  - 합성 세포 표적지향 이득 호우 1.51배·프로파일 1.54배 — README.md 핵심 결과 표(제안서에서는 DP 실측 결과로 교체됨) — `matlab/out/key_sensitivity.json` 마지막 행

## 7. 본선 예상 질문 3개와 답
**Q1.** RainCube 대비 감도가 어떻게 되고, 왜 그런가요?
**A.** RainCube 실측 11.0 dBZ(400 km)에서 출발해 거리 550 km(+2.8 dB), PRF 1.8 kHz(−2.4 dB), 풋프린트 통과 적분 1.55 s(−0.8 dB), 대역 1.2 MHz(−1.6 dB)를 더하면 9.0 dBZ이고, 해면 부엽을 잡으려고 고른 테이퍼 파형의 손실 1.5 dB를 더해 10.5 dBZ입니다. 같은 안테나·송신기인데도 더 높이 날면서 비슷한 감도인 이유는 펄스를 3배 많이 쏘고 더 오래 적분하기 때문입니다. 기준값의 PRF·대역이 2차 자료라 16가지 가정 조합으로 7.6~14.5 dBZ 범위를 함께 냈습니다.

**Q2.** Ka 대역은 비에 많이 약해지는데, 호우를 볼 수 있나요?
**A.** 20 mm/h에서 왕복 44 dB, 50 mm/h에서 99 dB가 약해져 맨 아래 약 1~2.7 km는 못 봅니다. 그러나 장마 호우의 핵심인 융해층(4.5~5 km)과 그 위 얼음층은 감쇠 전이라 그대로 보이고, 못 보는 깊이 자체가 경로적분감쇠(PIA)로 강우량 정보를 줍니다(GPM DPR도 같은 원리). 즉 "지표 비를 직접 재는 것"이 아니라 "상층 구조 + PIA"를 산출물로 삼는 설계입니다.

**Q3.** 왜 비선형 처프(NLFM)를 쓰지 않고 선형 처프에 부정합 필터를 썼나요?
**A.** 위성이 7.6 km/s로 움직여 빔 가장자리 해면 메아리가 ±17.9 kHz 도플러를 갖는데, NLFM은 도플러에 약해 빔 평균 부엽이 −14 dB까지 무너집니다. 가장자리 20 % 테이퍼 LFM + 최소제곱 부정합 필터는 빔 평균 −48 dB로 해면(58.7 dBZ)이 감도선 아래로 내려가고, 지표 위 1 km부터 오염이 없습니다. 대가는 SNR 손실 1.49 dB뿐이라 이것을 채택했습니다.

## 8. 스스로 확인 문제 3개 (답은 부록)
1. 고도를 550 km에서 500 km로 낮추면 8절의 거리 항은 몇 dB가 되는가? (다른 항은 그대로)
2. 30 mm/h 비에서 왕복 PIA가 63 dB인 이유를 `k·R^α`와 4.5 km로 계산해 보라.
3. 10절에서 수신 창 아래 끝을 지표 아래 3 km가 아니라 0 km로 두면 필요한 최소 PRI는 몇 µs가 되고 최대 PRF는 얼마인가?

## 9. 5분 설명 대본 (직접 채우기)
(빈칸)

## 10. 세 문장 요약 (직접 채우기)
1. 이 파일은 ______를 받아서 ______를 만든다.
2. 핵심 가정은 ______다.
3. 제안서에서 이 파일이 책임지는 숫자는 ______다.

## 부록. 확인 문제 답
1. 20log10(500/400) = 20 × 0.0969 = +1.94 dB (550 km의 +2.77 dB보다 0.83 dB 유리).
2. γ = 0.3452 × 30^0.8851 = 0.3452 × 20.3 = 7.01 dB/km; 왕복 PIA = 2 × 7.01 × 4.5 = 63.1 dB (`key_results.json` rain.PIA 4번째).
3. 창 길이 = 2 × 20 km ÷ c + 166 µs = 133.4 + 166 = 299.4 µs; 송신·보호 176 µs를 더해 PRI ≥ 475.4 µs → 최대 PRF 2.10 kHz (3 km 거울상 여유를 두면 495 µs·2.02 kHz).
