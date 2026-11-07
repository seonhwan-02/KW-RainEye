# 01. kre_lib.m 해설

> 담당: A   대상 파일: `dp/kre_lib.m` (565줄)   관련 결과 폴더: 직접 만드는 결과 없음 — 이 파일의 함수를 부르는 `dp/dp_step1~5*.m`이 `out/dp_step*/`에 결과를 쓴다

## 1. 한 줄 역할
IMERG(미국 NASA가 위성 여러 대의 자료를 합쳐 만든 전 지구 30분 강수 지도) 한 시즌(6~9월)을 받아서, 궤도 전파 → 큐(어디에 비가 있는지 알려 주는 선행 정보) 장면 만들기 → 학습 표 → (시각 × 빔각) 보상 표 → 동적계획법(DP, 작은 문제의 답을 쌓아 큰 문제의 최적해를 찾는 방법) 빔 경로 → 실제 강수로 채점까지, 모든 dp_step 스크립트가 공유하는 열두 개의 공용 함수를 구조체 `L`에 담아 돌려준다.

## 2. 흐름 (입력 → 처리 → 출력)
| 단계 | 하는 일 | 쓰는 함수·변수 | 나오는 것 |
|---|---|---|---|
| ① 설정 | 고도 550 km·경사 45°, ±10°, 기동 1.5°/s, 정착 4 s, 큐 지연 15분 같은 상수 묶음 | `params` → `P` | 매개변수 구조체 `P` |
| ② 자료 | 바탕화면 `K-RainEye_IMERG\YYYYMM`의 nc4 5,856장을 읽어 캐시(.mat)로 저장, 30분마다의 이동 벡터 계산 | `loadSeason(year, 'final'/'early')`, 내부 `estMotion` | `D.Pr`(위도×경도×시각), `D.tSlot`, `D.motion` |
| ③ 큐 자료 붙이기 | 큐(Early)와 진실(Final)을 한 구조체에 묶고, 둘의 일치도를 잰다 | `attachCue(D, Dc)`, `cueAgreement(Df, Dc, P)` | `D.cuePr`, `D.cueMotion`; 적중률·헛경보율 표 |
| ④ 궤도 | 원궤도 + J2(지구가 납작해서 생기는 궤도면 회전) 전파 → 관측창(북위 28.5~39.5°·동경 119.5~131.5°) 통과 목록, 통과마다 1.5 s 간격 표본의 직하점·진행 방향 | `orbitPasses(D, P, ip)`, 내부 `propagate`, `passSetup`, `passGeometry` | `passes{k} = G` (`G.tq`, `G.xq`, `G.yq`, `G.nq`, `G.kq`) |
| ⑤ 상한 | 매 표본에서 ±10° 안 어딘가에 호우가 있으면 1 — 기동 제약 없는 이론 상한 | `heavyInSwath(G, D, P)` | 표본 수 |
| ⑥ 학습 | 2023 시즌 전체로 "큐에서 x mm/h로 보인 칸이 30·60분 뒤 실제로 호우였던 비율" 표 | `calibrate(D, P, mode, seed)` | `calib.pHeavy`, `calib.pRain` (11구간 × 2열) |
| ⑦ 보상 표 | 통과 하나에 대해 (표본 q, 빔각 j)의 기대 점수 = P(호우) + 0.05·P(강수) | `rewardGrid(G, D, P, mode, rs, calib)`, 내부 `cueSlot`, `cueScene` | `Rw`(표본 × 21각), `th` |
| ⑧ 계획 | 기동 중엔 관측 못 한다는 제약 아래 보상 합이 최대인 빔각 경로 | `dpPlan(Rw, th, P)` / 비교용 `greedyPlan(G, D, P, mode, rs)` | `plan.th`, `plan.cb`, `plan.valid`, `plan.score` |
| ⑨ 채점 | 빔이 실제로 본 IMERG 칸 값으로 호우·강수 프로파일 수, 호우 세포 수를 센다 | `evaluate(G, D, P, plan)`, 내부 `beamLatLon`, `sampleField`, `countCells` | `E.heavy`, `E.rain`, `E.cells`, `E.heavyBand` |

## 3. 절별 해설

### 3.1 params — 매개변수 (줄 20~47)
```matlab
P.h        = 550;                 % 고도 [km]
P.inc      = 45;                  % 경사 [deg]
P.profDt   = 1.5;                 % 관측 표본 간격 = 풋프린트 길이 통과 시간 [s]
P.maxDeg   = 10;                  % 지향 범위 ±[deg]
P.slewRate = 1.5;                 % 기동 속도 [deg/s]
P.settle   = 4;                   % 정착 시간 [s]
P.thrHeavy = 10;                  % 호우 [mm/h]
P.cueL     = 15;                  % 큐 지연 [min]
P.pDet     = 0.72;                % 큐가 호우 핵을 제 강도로 알아볼 확률
P.weakFac  = [0.2 0.5];           % 못 알아본 호우 핵은 실제 강도의 이 배수로 약하게 보인다
P.edges    = [0 0.5 1 2 3 5 7 10 15 20 30 inf];   % 학습 표의 큐 강도 구간 [mm/h]
P.lags     = [1 2];               % 큐 장면이 관측보다 몇 칸(30분) 앞서는가
P.alpha    = 0.05;                % 보상에서 '약한 비'의 가중 (호우 = 1)
```
모든 스크립트가 같은 숫자를 쓰도록 한곳에 모아 둔 것이다. 고도 550 km의 원궤도 속도는 √(μ/a) = √(398600.4 / 6928.1) ≈ 7.59 km/s, 지상 속도는 약 7.0 km/s이므로 1.5 s 동안 약 10~11 km, 즉 풋프린트(레이더 빔이 땅에 닿는 자국) 하나 길이를 지나간다. 그래서 1.5 s가 "관측 표본 하나"다. 빔을 10° 기울이면 지상에서 550 × tan 10° ≈ 97 km 옆을 보고, 1°는 9.6 km, 3°는 28.8 km다. `pDet`, `weakFac`, `posSd`, `velSd`는 3단계에서 쓴 '가짜 큐 오차'이고, 4단계부터는 실제 Early 자료가 오차를 가지므로 `Pe.pDet = 1, posSd = 0, velSd = 0`으로 끈다(`dp_step4_realistic.m` 줄 29).

### 3.2 loadSeason — IMERG 한 시즌 읽기와 이동 벡터 (줄 50~112, 보조 estMotion 157~181)
```matlab
months = arrayfun(@(m) sprintf('%d%02d', year, m), 6:9, 'UniformOutput', false);
cache = fullfile(root, sprintf('cache_%s%d_JJAS.mat', tag, year));
...
        Pm(:, :, k) = ncread(f, '/Grid/precipitation');
        tm(k) = datetime(1980, 1, 6, 'TimeZone', 'UTC') + seconds(double(ncread(f, '/Grid/time')));
...
Pr(isnan(Pr) | Pr < 0) = 0;
D.t0 = datetime(year, 6, 1, 'TimeZone', 'UTC');
D.kmLat = 110.57 * 0.1;
D.kmLon = 111.32 * 0.1 * cosd(mean(lat));
assert(all(diff(seconds(tSlot - D.t0)) == 1800), '30분 간격이 끊긴 곳이 있다');
...
    for k = 2:D.nT
        mv(k, :) = estMotion(Pr(:, :, k - 1), Pr(:, :, k), 6, D.kmLat, D.kmLon);
    end
D.motion = mv;                                   % [동, 북] [km/s]
```
6~9월은 30 + 31 + 31 + 30 = 122일이고 하루에 30분 칸이 48개이므로 한 시즌은 122 × 48 = 5,856장면이다(`out/dp_step1_train/summary.txt` 첫 줄의 "장면 5856개"). 처음 한 번만 nc4를 읽고 `cache_2023_JJAS.mat`로 저장해 두어 다음부터는 몇 초 만에 읽는다. 결측(NaN)과 음수(IMERG의 결측 표시값)는 0으로 둔다. 시간 기준 `D.t0`는 6월 1일 00:00 UTC이고, 이후 코드는 모두 "t0에서 몇 초 지났나"로 시각을 다룬다. 0.1° 격자 한 칸은 남북 11.06 km, 동서 111.32 × 0.1 × cos(위도) ≈ 9.2 km(북위 34°)다.
`estMotion`은 30분 전 장면 A와 지금 장면 B를 최대 ±6칸 밀어 보며 가장 잘 겹치는 이동량(정규화 상관이 최대인 위치)을 찾고, 포물선 보간으로 칸 아래 정밀도를 얻은 뒤 1,800초로 나눠 [동, 북] km/s로 돌려준다. 비 오는 칸이 30개 미만이면 NaN → 나중에 0(움직임 없음)으로 바꾼다. 이 벡터는 **직전 두 장면만** 쓰므로 미래 정보가 없다.

### 3.3 attachCue — 큐는 Early, 채점은 Final (줄 114~125)
```matlab
function D = attachCue(D, Dc)
assert(isequal(size(D.Pr), size(Dc.Pr)), '두 자료의 크기가 다르다');
assert(all(D.tSlot == Dc.tSlot), '두 자료의 시각이 다르다');
assert(~strcmp(D.src, Dc.src), '큐와 진실이 같은 자료다');
D.cuePr     = Dc.Pr;
D.cueMotion = Dc.motion;                         % 이동 벡터도 큐 자료로 다시 구한 것 (운용과 같게)
D.cueSrc    = Dc.src;
end
```
Final(약 3.5개월 뒤 나오는 정밀판)을 진실로, Early(약 4시간 뒤 나오는 빠른판, 그 시각까지의 자료만 씀)를 큐로 쓰기 위해 한 구조체에 두 장을 넣는다. `cuePr`가 있으면 `cueScene`(3.12)이 그쪽을 읽고, 채점 `evaluate`와 상한 `heavyInSwath`는 그대로 `D.Pr`(Final)을 읽는다. 이 한 줄 차이가 3단계(큐도 Final → 낙관적)와 4단계(큐 = Early → 현실적)를 가른다.

### 3.4 cueAgreement — 큐 자료가 진실을 얼마나 맞히나 (줄 127~155)
```matlab
hF = F >= P.thrHeavy;  hC = C >= P.thrHeavy;
hh = hh + nnz(hF & hC);  hm = hm + nnz(hF & ~hC);  hf = hf + nnz(~hF & hC);
...
        Lb = labelMask(hF);
        mx = accumarray(Lb(hF), double(C(hF)), [], @max);
        nCore = nCore + numel(mx);  nDet = nDet + nnz(mx >= P.thrHeavy);
        pk = accumarray(Lb(hF), double(F(hF)), [], @max);          % 진실 핵의 최대 강도
        pMiss = min(max((P.weakFac(2) - P.thrHeavy ./ pk) / diff(P.weakFac), 0), 1);
        sModel = sModel + sum(P.pDet + (1 - P.pDet) * pMiss);
...
A.podHeavy = hh / (hh + hm);  A.farHeavy = hf / max(hh + hf, 1);
A.coreDet  = nDet / max(nCore, 1);  A.coreDetModel = sModel / max(nCore, 1);
```
같은 시각·같은 칸에서 적중률(POD, 진실이 호우인 칸 중 큐도 호우라고 한 비율)과 헛경보율(FAR)을 세고, 호우 핵(10 mm/h 이상 칸이 8방향으로 이어진 덩어리) 단위로 "큐가 그 덩어리 안 어딘가를 호우로 봤나"(`coreDet`)도 센다. `coreDetModel`은 3단계의 가짜 오차 모형을 같은 잣대로 잰 값이다: 핵이 '못 알아본' 쪽(확률 1 − 0.72)으로 떨어져도 무작위 배수 f ∈ [0.2, 0.5]가 10/pk 이상이면 10 mm/h를 넘어 '본 것'이 되므로, 그 확률 (0.5 − 10/pk)/0.3을 더해 준다. 예: 최대 강도 pk = 40 mm/h인 핵이면 pMiss = (0.5 − 0.25)/0.3 = 0.83, 전체 0.72 + 0.28 × 0.83 = 0.95. 결과(`out/dp_step4_realistic/summary.txt`): 2023 Early의 호우 핵 인식 0.583, 2024 0.365, 2025 0.408, 같은 기준의 가짜 모형 0.757 → 실제 큐가 가정보다 거칠었다.

### 3.5 orbitPasses — 궤도 전파와 관측창 통과 (줄 184~217, 보조 propagate 487~501, passGeometry 503~515)
```matlab
phs = RandStream('mt19937ar', 'Seed', 7);
phases = [rand(phs, P.nPhase, 1), rand(phs, P.nPhase, 1)] * 2 * pi;
[t, la, lo] = propagate(P.C, P.h, P.inc, phases(ip, 1), phases(ip, 2), gmst0, D.nT * 1800 / 86400, P.dt);
inWin = la >= P.winLat(1) & la <= P.winLat(2) & lo >= P.winLon(1) & lo <= P.winLon(2);
dIn = diff([false; inWin; false]);
st = find(dIn == 1);  en = find(dIn == -1) - 1;
...                                   % passSetup
G.tq = (t(s):P.profDt:t(e))';
u = [gradient(G.xq), gradient(G.yq)];  u = u ./ vecnorm(u, 2, 2);
G.nq = [-u(:, 2), u(:, 1)];                      % 진행 방향의 왼쪽 단위벡터 (빔 오프셋 +)
G.kq = min(max(floor(G.tq / 1800) + 1, 1), nT);  % 각 표본이 속한 30분 칸
```
궤도 시작 위상(승교점 적경과 궤도 내 위치) 8쌍을 씨앗 7로 고정해 뽑아 두므로, 누가 언제 돌려도 같은 궤도가 나온다. `propagate`는 원궤도에 J2 영년 섭동(지구가 납작해서 궤도면이 천천히 도는 효과)만 넣는다. 경사 45°·550 km에서 궤도면은 하루 약 −5.3°씩 서쪽으로 돈다(−1.5·n·J2·(Re/a)²·cos i × 86400 s). 10초 간격 위치가 관측창 안에 연속으로 있는 구간 하나가 '통과'이고, 그 안을 1.5 s 간격 표본 `tq`로 다시 나눈다. `nq`는 진행 방향의 왼쪽 수직 벡터로, 빔각 +는 왼쪽, −는 오른쪽으로 기울인다는 뜻이다. `kq`는 표본이 속한 30분 칸 번호(k번째 칸 = (k−1)·1800 ~ k·1800초). 결과: 시즌 통과 2023년 308회, 2024·2025년 307회(`out/dp_step4_realistic/summary.txt`), 2단계 예시 통과는 표본 127개 ≈ 190초(`out/dp_step2_demo/summary.txt`).

### 3.6 heavyInSwath — 기동 제약 없는 이론 상한 (줄 219~225)
```matlab
c = P.h * tand(-P.maxDeg:P.stepDeg:P.maxDeg);
[blat, blon] = beamLatLon(G, c);
val = sampleField(D.Pr, D.lat, D.lon, blat, blon, repmat(G.kq, 1, numel(c)));
n = sum(any(val >= P.thrHeavy, 2));
```
표본마다 21개 빔각(−10°, −9°, …, +10°)이 닿는 칸의 실제 값을 보고, 그중 하나라도 10 mm/h 이상이면 1로 센다. 빔을 순간이동시킬 수 있을 때의 최대치라서 어떤 계획도 이 값을 넘을 수 없다. 3단계 결과 "이론 상한 천저의 5.56배(2023)"(`out/dp_step3_validate/summary.txt`)가 이 함수에서 나온다.

### 3.7 calibrate — 학습: 큐 강도 → 실제 호우 확률 표 (줄 298~331)
```matlab
rs = RandStream('mt19937ar', 'Seed', seed);
for k = 2:D.nT - max(P.lags)
    [F, e, v] = cueScene(D, P, k, mode, rs);
    for il = 1:nl
        dtLead = P.lags(il) * 1800;              % 가운데 시각끼리의 차이
        srcLat = LAT - (e(2) + v(2) * dtLead) / ky;
        srcLon = LON - (e(1) + v(1) * dtLead) ./ kx;
        cv = sampleField(F, D.lat, D.lon, srcLat, srcLon, ones(size(srcLat)));
        ok = ~isnan(cv);
        truth = D.Pr(:, :, k + P.lags(il));
        bin = discretize(cv(ok), P.edges);
        cnt(:, il) = cnt(:, il) + accumarray(bin, 1, [nb 1]);
        nH(:, il)  = nH(:, il)  + accumarray(bin, double(truth(ok) >= P.thrHeavy), [nb 1]);
calib.pHeavy = nH ./ max(cnt, 1);
```
"큐 장면에서 7~10 mm/h로 보인 자리가 30분 뒤(lag 1) 또는 60분 뒤(lag 2)에 실제로 호우일 확률"을 시즌의 모든 장면 쌍과 모든 칸(5,856 × 15,600, `dp_step1_train.m` 머리말)으로 센다. 큐 장면에는 `cueScene`으로 가짜 오차(또는 Early 자료)를 넣고, 이동 벡터로 옮긴 자리의 큐 값을 그 칸의 진실과 짝지어 구간별로 쌓는다. k는 2부터(이동 벡터는 직전 장면이 있어야 함) nT − 2까지(60분 뒤 진실이 있어야 함)다. 결과(`out/dp_step1_train/summary.txt`): 큐 10~15 mm/h → 30분 뒤 호우 52.5%, 60분 뒤 39.3%; 7~10 → 21.2%; 0~0.5 → 0.01%; 30 이상 → 87.7%. 즉 큐가 "호우"라고 해도 30분 뒤엔 절반만 호우이고, 이 불확실성을 그대로 보상에 반영하는 것이 DP의 핵심이다. 표는 2023으로만 만들고 2024·2025에 그대로 적용한다(검증 원칙).

### 3.8 rewardGrid·cueSlot — (시각 × 빔각) 보상 표 (줄 228~273)
```matlab
th = -P.maxDeg:P.stepDeg:P.maxDeg;
c  = P.h * tand(th);                              % 빔각 → 지상 오프셋 [km]
[blat, blon] = beamLatLon(G, c);
if strcmp(mode, 'oracle')
    Rw = double(val >= P.thrHeavy) + P.alpha * double(val >= P.thrRain);  return;
end
[kc, tRef] = cueSlot(G.ts, P, D.nT);              % tCue = ts - cueL*60; kc = floor(tCue/1800); tRef = (kc-0.5)*1800
[F, e, v] = cueScene(D, P, kc, mode, rs);
dtq = G.tq - tRef;
srcLat = blat - (e(2) + v(2) * dtq) / G.Pg.ky;
srcLon = blon - (e(1) + v(1) * dtq) / G.Pg.kx;
cv = sampleField(F, D.lat, D.lon, srcLat, srcLon, ones(size(srcLat)));
bin = discretize(cv, P.edges);
lag = min(max(G.kq - kc, 1), numel(P.lags));
Rw  = calib.pHeavy(ix) + P.alpha * calib.pRain(ix);
```
표본 q 시각에 빔각 th(j)로 봤을 때 기대 점수를 표로 만든다. 'oracle'은 실제 값을 그대로 보는 상한(0/1). 'nowcast'·'persist'는 먼저 `cueSlot`으로 **큐 시각(통과 시작 15분 전) 이전에 끝난 마지막 30분 칸** kc를 고른다. 예: 통과 시작이 t0 + 10,000초면 큐 시각은 9,100초, 5번째 칸(7,200~9,000초)은 끝났고 6번째 칸(9,000~10,800초)은 아직 진행 중이므로 kc = 5다(floor(9100/1800) = 5). 진행 중인 칸은 앞으로 올 비까지 평균한 값이라 쓰면 미래를 엿보는 셈이 되므로 쓰지 않는다. 그 장면의 가운데 시각 tRef = 8,100초에서 관측 시각까지의 시간 dtq만큼 비가 이동 벡터 v로 움직였다고 보고, "관측 시각에 p에 있을 비 = 큐 장면에서 p − e − v·dtq에 있던 비"로 거꾸로 찾아 큐 강도를 읽는다('persist'는 v = 0). 읽은 강도의 구간과 '몇 칸 앞선 장면인가'(kq − kc = 1 또는 2)에 맞는 학습 표 값이 보상이 된다. 큐 칸의 끝에서 관측까지는 15~45분, 칸 가운데에서는 30~60분이므로 lags = [1 2]와 맞는다. 큐 칸이 2보다 작으면(시즌 첫 45분) 큐가 없다고 보고 보상 0을 돌려주며, 그러면 DP는 천저를 유지한다.

### 3.9 dpPlan — 동적계획법으로 최적 빔 경로 (줄 334~374)
```matlab
Rw(:, th == 0) = Rw(:, th == 0) + 1e-6;                       % 점수가 같으면 천저
dth  = abs(th(:) - th(:)');
slew = dth / P.slewRate + P.settle;  slew(dth == 0) = 0;
m    = ceil(slew / P.profDt);                                 % 이동 중 놓치는 표본 수
V(1, :) = Rw(1, :);                                           % 진입 전에 미리 기울여 둘 수 있다
for q = 2:nq
    best = V(q - 1, :);  bj = 1:nj;  bq = repmat(q - 1, 1, nj);   % 일단 '머무름'
    for jp = 1:nj
        qp = q - 1 - m(jp, :);                                % jp에서 출발해 j에 도착하려면 qp에 jp를 보고 있어야 함
        ok = qp >= 1 & (1:nj) ~= jp;
        cand(ok) = V(sub2ind([nq nj], qp(ok), repmat(jp, 1, nnz(ok))));
        better = cand > best;
        best(better) = cand(better);  bj(better) = jp;  bq(better) = qp(better);
    end
    V(q, :) = best + Rw(q, :);
```
V(q, j) = "표본 q에서 빔각 j를 관측하며 끝나는 경로 중 최고 점수". 같은 각도에 머무르면 다음 표본도 바로 관측하고(비용 0), 각도를 jp → j로 바꾸면 기동 시간(각도 차 / 1.5°/s + 정착 4 s)만큼의 표본을 놓친다. 예: 1° 바꾸면 1/1.5 + 4 = 4.67 s → ceil(4.67/1.5) = 4표본(6 s)을 못 본다(표본 하나가 1.5 s짜리 관측이므로, 관측을 마친 뒤 기동을 시작해 4.67 s 뒤에 도착하면 다음 1.5 s 경계에 맞는 첫 표본이 네 번째 뒤다). −10° → +10°는 20/1.5 + 4 = 17.3 s → 12표본. 표본 127개 × 빔각 21개 표에서 이 계산은 순식간이라 위성 탑재 컴퓨터로도 충분하다. 마지막 표본에서 가장 좋은 상태부터 `Bj`, `Bq`로 되짚어 경로를 복원하고, 기동 중이던 표본은 `th = NaN`, `valid = false`로 둔다. 천저(0°)에 1e-6의 가산점을 주는 것은 모든 보상이 0일 때 천저에 머무르게 하기 위해서다. 결과: 통과당 기동 1.3~1.5회(`out/dp_step4_realistic/summary.txt`).

### 3.10 greedyPlan — 비교용 기존 방식 (줄 377~401, 보조 crossTimes·schedule·slewTime·beamAt 517~565)
```matlab
[kc, tRef] = cueSlot(G.ts, P, D.nT);
[F, e, v] = cueScene(D, P, kc, mode, rs);         % DP와 똑같은 큐 장면 (공정한 비교)
idx = find(localMax(F) & F >= P.greedyThr);       % 큐 장면의 국지 최대점 중 10 mm/h 이상 = 표적
x0 = (D.lon(jj) - Pg.lonm) * Pg.kx + e(1);
y0 = (D.lat(ii) - Pg.latm) * Pg.ky + e(2);
[tc, cc] = crossTimes(Pg, x0, y0, v(1) * ones(size(x0)), v(2) * ones(size(x0)), tRef);
pri  = 1 + double(val >= P.thrHeavy);
cand = ~isnan(tc) & abs(cc) <= reach;             % reach = 550·tan 10° ≈ 97 km
acc  = schedule([tc(cand), cc(cand), pri(cand)], G.ts, R);
[cb, valid] = beamAt(acc, G.tq, R);
```
제안서 이전 방식과 같은 "점 표적을 하나씩 찍는" 스케줄러다. 큐 장면에서 주변 8칸보다 큰 국지 최대점을 표적으로 뽑고, 움직이는 표적이 위성 궤적 옆을 지나는 시각 `tc`와 옆 거리 `cc`를 구한 뒤(`crossTimes`), 우선순위·시각 순으로 "앞 표적에서 다음 표적까지 기동 시간이 맞는가"를 확인하며 넣는다(`schedule`). 표적마다 3 s(`dwell`) 응시하고 그 각도에 머무른다. 결과: Early 큐 기존 방식은 천저의 1.17/1.13/1.22배(2023/2024/2025), DP 나우캐스트는 2.08/2.04/2.06배(`out/dp_step4_realistic/summary.txt`). 장마 강수대는 궤도와 같은 남서→북동으로 길어서 점 표적 방식은 손해를 보기 쉽다(README '핵심 결과' 아래 메모).

### 3.11 evaluate — 실제 강수로 채점 (줄 404~420, 보조 beamLatLon 423~429, countCells 442~450)
```matlab
[blat, blon] = beamLatLon(G, plan.cb);
[val, ii, jj] = sampleField(D.Pr, D.lat, D.lon, blat, blon, G.kq);
val(~plan.valid) = NaN;
heavy = val >= P.thrHeavy;
E.rain   = nnz(val >= P.thrRain);                 % 강수 프로파일 수
E.heavy  = nnz(heavy);                            % 호우 프로파일 수
E.heavyNear = nnz(heavy & abs(plan.cb) <= P.h * tand(3) + 1e-6);   % 그중 ±3° 안
ang = abs(atand(plan.cb / P.h));
E.heavyBand = [nnz(heavy & ang <= 3 + 1e-6), nnz(heavy & ang > 3 + 1e-6 & ang <= 6 + 1e-6), nnz(heavy & ang > 6 + 1e-6)];
E.cells  = countCells(D.Pr, P.thrHeavy, ii(heavy), jj(heavy), G.kq(heavy));   % 서로 다른 호우 세포 수
```
계획이 정한 빔 위치가 닿는 칸의 **실제(Final)** 값을 읽어, 1 mm/h 이상이면 강수 프로파일, 10 mm/h 이상이면 호우 프로파일로 센다. 기동 중 표본은 NaN이라 세지 않는다. 0~3°, 3~6°, 6~10° 각도대별 호우 수도 따로 센다(±3° 안은 레이더가 전 고도를 정량 관측할 수 있는 범위). `countCells`는 같은 30분 칸 안에서 호우 칸 덩어리(세포)에 번호를 붙여 서로 다른 세포를 몇 개 봤는지 센다. 결과: 2023 Early 큐 DP는 각도대별로 천저 전체 대비 0~3° 0.574, 3~6° 0.373, 6~10° 1.131 → 이득이 주로 6~10°에서 나온다(`out/dp_step4_realistic/summary.txt`).

### 3.12 sampleField·cueScene — 위경도 → 칸 값, 큐 장면 만들기 (줄 431~440, 275~296)
```matlab
ii = round((blat - lat(1)) / (lat(2) - lat(1))) + 1;          % sampleField: 가장 가까운 0.1° 칸
jj = round((blon - lon(1)) / (lon(2) - lon(1))) + 1;
in = ii >= 1 & ii <= n1 & jj >= 1 & jj <= n2 & ~isnan(ii) & ~isnan(jj);
val = nan(size(blat));
val(in) = Pr(sub2ind([size(Pr, 1) size(Pr, 2) size(Pr, 3)], ii(in), jj(in), kq(in)));
...                                                           % cueScene
if isfield(D, 'cuePr'), F = double(D.cuePr(:, :, kc));  mv = D.cueMotion;
else,                   F = double(D.Pr(:, :, kc));     mv = D.motion;  end
Lb = labelMask(F >= P.thrHeavy);
miss = [false; rand(rs, nObj, 1) >= P.pDet];      % 못 알아본 호우 핵
fac  = [1; P.weakFac(1) + diff(P.weakFac) * rand(rs, nObj, 1)];
fac(~miss) = 1;
F = F .* fac(Lb + 1);                             % 못 알아본 핵만 0.2~0.5배로 약하게
e = P.posSd * randn(rs, 1, 2);
v = mv(kc, :) + P.velSd * randn(rs, 1, 2);
if strcmp(mode, 'persist'), v = [0 0]; end
```
`sampleField`는 위경도를 "격자 첫 칸에서 몇 칸 떨어졌나"로 바꿔 반올림하고, 자료 영역 밖이면 NaN을 준다(부르는 쪽에서 0으로 바꾼다). `cueScene`은 큐가 보는 장면을 만든다: 실제(또는 Early) 장면 kc에서 호우 핵 덩어리마다 확률 0.28(= 1 − 0.72)로 '못 알아봄'을 뽑아 그 핵만 0.2~0.5배로 약하게 만들고(적외선으로 보면 따뜻한 구름의 호우가 약하게 보이는 현상을 흉내), 장면 전체를 3 km 표준편차로 옮기고(위치오차), 이동 벡터에 2 m/s 오차를 더한다. 모든 난수는 부르는 쪽이 준 `RandStream`에서 나오므로 같은 씨앗이면 같은 장면이 나온다. 4단계부터는 Early 장면이 이미 거칠어서 이 가짜 오차를 끈다.

## 4. 핵심 가정 3개
1. **IMERG 30분 칸은 그 칸이 끝나는 순간 큐로 쓸 수 있다** — 실제 운용 큐(천리안 2A 적외선 + KIM 예보)는 몇 분 안에 나오지만 여기서는 IMERG가 큐 대역을 대신하므로, "끝난 칸만 쓴다 + 15분 지연"으로 보수적으로 둔다 — IMERG Early는 실제로 약 4시간 뒤 나오므로 이 가정은 '자료의 거칠기'만 흉내 내는 것이고, 지연까지 흉내 내면 큐가 더 낡아져 이득이 줄어든다(5단계: 큐 지연 30분 1.93배, 45분 1.81배, README '핵심 결과').
2. **큐의 오차는 (가) 가짜 모형 pDet 0.72·위치 3 km·속도 2 m/s 또는 (나) Early 자료 자체의 오차로 충분히 표현된다** — 천리안 적외선 강수 추정의 알려진 한계(따뜻한 구름 호우 과소 추정)를 단순하게 넣은 것 — Early와 Final은 입력을 일부 공유해 독립 큐보다 낙관적일 수 있고, 실제 큐가 더 거칠면 Early 호우 핵 인식 0.37~0.58에서 얻은 약 2배 이득이 더 내려간다.
3. **기동은 일정 속도 1.5°/s + 정착 4 s이고 기동 중엔 관측하지 못하며, 빔은 궤적의 왼쪽/오른쪽(진행 방향에 수직)으로만 기울인다** — 자세 제어 하드웨어의 보수적 수치이고 수직 방향 지향이 가장 단순하다 — 정착 8 s로 늘려도 2.02배(5단계)라 둔감하지만, 지향 범위를 ±3°로 줄이면 1.21배로 떨어져 '±10°까지 기울일 수 있는 자세 제어'가 이 이득의 전제다.

## 5. 코드 검토 결과
| 번호 | 줄 | 지적 | 어떤 입력에서 틀어지나 | 판정 | 근거 |
|---|---|---|---|---|---|
| 1 | 265~273, 281~282, 249 | 큐가 관측 시각 뒤 장면을 보지 않는가? `cueSlot`이 큐 시각(통과 15분 전)을 **포함하는** 칸을 쓰면 미래 평균이 섞인다 | 통과 시작이 30분 칸 경계 직후일 때 | **문제 없음(오해)** | `kc = floor(tCue/1800)`은 큐 시각 전에 끝난 마지막 칸(kc·1800 ≤ tCue). `cueScene`은 `Pr(:,:,kc)`와 `motion(kc,:)`(= kc−1, kc 장면)만 읽음. CHECK 1 |
| 2 | 89~95, 216, 270 | 시간축·격자 규약: `t0` = 6/1 00:00이 자료 첫 칸과 같은가, k번째 칸 = (k−1)·1800~k·1800초 규약이 `kq`·`kc`와 맞는가, 위도가 오름차순인가(`estMotion`의 '행 증가 = 북' 가정) | 자료 첫 파일이 6/1 00:00이 아니거나 위도가 내림차순인 자료 | **문제 없음** | `assert`는 간격만 보고 시작 시각은 안 보지만, 실제 2023 캐시는 첫 칸 = t0, 5,856칸, 위경도 오름차순 0.1°. CHECK 2 |
| 3 | 175, 111, 250~253, 312~314 | 이동 벡터 단위(km/s)와 부호([동, 북])가 `rewardGrid`·`calibrate`의 "p − e − v·dt" 되찾기와 맞는가(초 × km/s ÷ km/도) | 부호가 하나라도 뒤집히면 나우캐스트가 비를 반대쪽으로 옮겨 위치고정보다 나빠짐 | **문제 없음** | 가짜 자료에서 동쪽 20 m/s × 1,900 s = 38 km → 최대 보상이 예상대로 −4°(동쪽)에 나오고, 실제 2023 이동 벡터 평균의 동쪽 성분이 양수(장마 강수대 동진). 3단계에서 나우캐스트(2.45배) > 위치고정(2.22배)인 것과도 부합. CHECK 3·4 |
| 4 | 341~342, 349 | 기동 중 놓치는 표본 `m = ceil(slew/1.5)`가 하나 많은 것 아닌가(4.67 s면 3표본 뒤 4.5 s에 끝나는데 4표본을 버림)? 또 DP 전이 `qp = q−1−m`가 정말 최적인가 | 모든 기동 | **문제 없음(오해)** | 표본 하나는 1.5 s 동안의 관측이라 관측을 마친 뒤 기동을 시작하면 도착은 1.5 + 4.67 = 6.17 s 뒤 → 다음 관측 가능 표본은 7.5 s(4표본 뒤). 1° 기동 시 NaN 4개, 점수 8 재현. 표본 8 × 빔각 3 보상 표의 4^8개 경로 전수 조사 최댓값 = DP 점수. CHECK 5 |
| 5 | 258~260 | 학습 표의 열 선택 `lag = min(max(kq−kc,1), numel(P.lags))`가 '칸 차이'를 '열 번호'로 그대로 쓴다 → `P.lags`가 1부터 연속(1:n)이라는 암묵적 가정 | `P.lags = [2 3]`처럼 1부터 시작하지 않게 바꿀 때 | **개선 제안(결과에는 영향 없음)** | 기본 [1 2]와 5단계의 1:4에서는 바른 열. [2 3]이면 틀린 열을 고른다. `find(P.lags == kq−kc)`로 바꾸면 안전. 현재 모든 스크립트가 1:n만 쓴다. CHECK 6 (FAIL = 지적 맞음) |
| 6 | 186~187, 285~286, 293~294, 304 | 난수 재현성: 궤도 위상, 큐 오차, 학습 표가 실행마다 달라지지 않는가 | 전역 `rng`에 기대는 코드가 있으면 다른 스크립트 실행 순서에 따라 결과가 바뀜 | **문제 없음** | 궤도 위상은 씨앗 7 고정, 큐 오차는 부르는 쪽이 준 `RandStream`, 학습은 씨앗 인자(2023). 전역 `rand` 호출 없음. 같은 씨앗 → 같은 표, 다른 씨앗 → 다른 표. CHECK 7 |
| 7 | 234~241, 254~256, 245~247, 383~386 | 경계: ±10° 양 끝이 포함되는가, 빔이 자료 영역 밖으로 나갈 때 NaN이 보상 표나 DP에 들어가지 않는가, 큐가 없을 때(시즌 첫 45분) 어떻게 되는가 | 관측창 서쪽 끝 통과, 시즌 첫 통과 | **문제 없음** | 21개 각(−10~10) 포함, 영역 밖은 NaN → 0, `kc < 2`면 보상 0 → DP 천저 유지·기존 방식 표적 0. CHECK 8 |
| 8 | 309, 317 | `calibrate`의 장면 범위 `k = 2 : nT − max(lags)`와 `truth = Pr(:,:,k+lag)` 인덱스가 하나 어긋나지 않는가 | 시즌 양 끝 | **문제 없음** | 20×20×12 가짜 시즌에서 칸 수 합 = 9장면 × 400칸(2~10번째 장면), 20 mm/h 구간 호우 확률 1·0 구간 0. CHECK 9 |

**어떻게 확인했나(요약).** 확인 코드는 `checks/check01.m`에 있고, 실제 자료는 2·4번만 `L.loadSeason(2023,'final')` 캐시를 읽는다. 1번은 kc 뒤 장면과 이동 벡터를 전부 바꿔도 같은 씨앗의 보상 표가 바이트 단위로 같은지(그리고 kc 장면을 지우면 달라지는지)를 봤다. 3번은 천저 밑에 남북으로 가는 폭 0.1°의 호우 띠를 놓고 동쪽 20 m/s를 주어 최대 보상 빔각이 −4°(= round(atan(−38/550)))에 나오는지, 'persist'면 0°인지 봤다. 4번은 `dpPlan`이 낸 경로를 직접 다시 채점하고, 작은 표에서는 모든 경로를 다 세어 본 최댓값과 비교했다. 5번은 일부러 `lags = [2 3]`을 넣어 틀린 열을 고르는 것을 확인했으므로 CHECK 6은 FAIL로 찍히는 것이 정상이다(지적이 맞다는 뜻, 결과 영향 없음). 2번의 '위도 오름차순'은 코드가 직접 검사하지 않는 가정이라, 다른 해·다른 자료를 처음 읽을 때 한 번은 확인할 가치가 있다.

### 5.9 확인 스크립트 실행 결과 (2026-10-31, `checks/check01.m`, 12.0초)

PASS = 코드가 의도대로 동작함(지적이 오해이거나 버그 없음), FAIL = 지적이 맞음(개선 제안 포함).

| 번호 | 결과 | 설명 |
|---|---|---|
| 1 | **PASS** | 통과 시작 10000초, 큐 시각 9100초 → 쓴 칸 kc=5 (7200~9000초, 큐 시각 전에 끝남). kc 뒤 장면·이동 벡터를 바꿔도 보상 표 동일 → 미래 정보 누수 없음 |
| 3 | **PASS** | 동쪽 20 m/s × 1900초 = 38 km → 나우캐스트 최대 보상 빔각 -4° (예상 -4°), 위치고정은 0°. km/s·초·km/도 단위와 [동, 북] 부호가 맞음 |
| 5 | **PASS** | 1° 기동 시 놓치는 표본 4개(= 6초 ≥ 4.67초, 표본 하나가 1.5초 관측이므로 맞음), 점수 8.000 재현. 4^8개 경로 전수 조사 최댓값과 DP 점수 차이 0.0e+00 → 최적 |
| 6 | **FAIL** | 기본 lags=[1 2]에서는 바른 열(60분)을 고름(1)이지만, lags=[2 3]처럼 1부터 연속이 아니면 틀린 열을 고름(0). 지적 맞음 ? 개선 제안: 현재 모든 스크립트는 1:n만 쓰므로 결과에는 영향 없음 |
| 7 | **PASS** | 같은 씨앗 → 보상 표·학습 표 동일, 다른 씨앗 → 보상 표 다름; orbitPasses는 안에서 씨앗 7을 고정해 두 번 불러도 같은 위상·같은 통과 5회 |
| 8 | **PASS** | 빔각 -10~10° 21개 포함, 자료 밖 빔은 NaN→0으로 보상 표에 NaN 없음, 큐 없는 통과(kc<2)는 보상 0 → DP 천저 유지·기존 방식 표적 0 |
| 9 | **PASS** | 칸 수 합 = 9장면 × 400칸 (첫 칸은 이동 벡터가 없어 빼고, 끝 2칸은 60분 뒤 진실이 없어 뺌), 20 mm/h 구간 호우 확률 1, 0 구간 0 → 인덱스 범위·표 계산 맞음 |
| 2 | **PASS** | 2023 자료 120×130칸 × 5856장면, 첫 칸 시작 = t0 + 0초, 30분 간격 끊김 없음, 칸 번호 = floor(t/1800)+1 규약 일치, 위도·경도 오름차순 0.1°, NaN·음수 없음 |
| 4 | **PASS** | 이동 벡터 구한 장면 5638개, 평균 [동 4.5, 북 1.9] m/s, 속도 중앙값 5.8 m/s → 동쪽 성분 양수(강수대 동진)·수 m/s~수십 m/s 범위로 부호·단위(km/s) 규약이 맞음 |

요약: PASS 8개, FAIL 1개.

**판정 대조:** FAIL로 나온 항목은 모두 5절 표에서 이미 그렇게 판정한 지적(개선 제안)이다. 제안서에 쓰인 숫자(이득 배수, 감도, 감쇠 높이, 신뢰구간)는 어느 FAIL에도 영향을 받지 않는다.

## 6. 다른 문서와의 연결
- 이 파일이 부르는 것: 없음(MATLAB 내장 함수만). 자료는 바탕화면 `K-RainEye_IMERG\YYYYMM\*.nc4`와 캐시 `cache_[early_]YYYY_JJAS.mat`, `motion_[early_]YYYY_JJAS.mat`.
- 이 파일을 부르는 것: `dp/dp_step1_train.m`(02번: `params`, `loadSeason`, `calibrate`), `dp_step2_demo.m`(03번: + `orbitPasses`, `heavyInSwath`, `rewardGrid`, `dpPlan`, `greedyPlan`, `evaluate`), `dp_step3_validate.m`(04번), `dp_step4_realistic.m`(05번: + `attachCue`, `cueAgreement`), `dp_step4b_upstream.m`, `dp_step5_sensitivity.m`. `dp/rain.m`은 1~3단계와 이 파일을 한 파일에 붙여 넣은 연습본(4단계 이전 내용)이다.
- 직접 만드는 결과 파일: 없음. 결과 숫자는 모두 부르는 스크립트가 `out/dp_step1_train/`, `out/dp_step2_demo/`, `out/dp_step3_validate/`, `out/dp_step4_realistic/`, `out/dp_step4b_upstream/`, `out/dp_step5_sensitivity/`에 쓴다(`summary.txt`, `key_*.json`, `methods.csv`, `results.mat`).
- 제안서에서 쓰인 숫자(README '핵심 결과' 표 기준):
  - 호우 프로파일 2.08배(2023 학습, 95% 신뢰구간 1.83~2.36), 2.04배(2024), 2.05배(2025), Early 큐 DP — `out/dp_step4_realistic/summary.txt`
  - Final 큐 DP 2.45/2.73/2.84배, 완벽 정보 DP 4.13/4.21/4.73배, 기존 방식(Early 큐) 1.17/1.13/1.22배, 통과당 기동 1.53/1.30/1.50회 — 같은 파일
  - Early vs Final 호우 핵 인식 0.583/0.365/0.408(가짜 모형 기준 0.757) — 같은 파일 (`cueAgreement`)
  - 임무 관측창(28~38°N·119~127°E) 2.10/2.13/2.38배 — `out/dp_step4b_upstream/summary.txt`
  - 정착 8 s 2.02배, 큐 지연 30분 1.93배, ±3° 1.21배 — `out/dp_step5_sensitivity/summary.txt`
  - 학습 표: 큐 10~15 mm/h → 30분 뒤 호우 52.5%, 60분 뒤 39.3% — `out/dp_step1_train/summary.txt`

## 7. 본선 예상 질문 3개와 답
**Q1.** 큐 자료가 미래 정보를 쓰는 건 아닌가요? 30분 평균 자료를 쓰면 관측 시각의 비를 이미 알고 있는 셈 아닌가요?
**A.** 큐는 통과 시작 15분 전 시각에 이미 '끝난' 마지막 30분 칸만 씁니다(`cueSlot`, 줄 270: `floor(tCue/1800)`). 그 칸이 끝난 뒤 15~45분 지난 장면을 이동 벡터(이것도 그 칸과 바로 앞 칸으로만 계산)로 옮겨 예측하고, 채점은 관측 시각의 실제 값으로 따로 합니다. 다만 IMERG Final은 앞뒤 시간을 보간해 만든 자료라 3단계는 낙관적일 수 있어, 4단계부터는 그 시각까지의 자료만 쓰는 Early를 큐로 바꿨고 그래도 약 2배가 남았습니다.

**Q2.** 실제 위성은 천리안 2A를 쓸 텐데 IMERG로 모의한 결과가 왜 의미가 있나요?
**A.** 천리안 2A 적외선 강수 추정의 시간 해상도(10분)와 오차 특성을 그대로 흉내 낼 과거 자료가 없어서, 공개된 위성 강수 추정 중 가장 거친 IMERG Early(그 시각까지의 위성 자료만, 월별 우량계 보정 없음)를 '거친 큐'로, Final을 '진실'로 썼습니다. 큐의 호우 핵 인식률이 실제 Early에서 37~58%로 가정(72%)보다 나빴는데도 이득이 2배 안팎으로 유지된 것이 핵심이고, 천리안은 15분보다 빨리 나오므로 지연 면에서는 유리합니다. 한계로 Early와 Final이 입력을 일부 공유한다는 점은 제안서에 같이 적었습니다.

**Q3.** 동적계획법이 정말 최적인가요? 탑재 컴퓨터에서 돌릴 수 있나요?
**A.** 상태가 (표본, 빔각)이고 전이가 '머무름' 또는 '기동 뒤 도착'뿐이라, 보상이 0 이상이면 V(q, j) 점화식이 모든 경로 중 최댓값을 정확히 줍니다(작은 표에서 모든 경로를 다 세어 본 값과 일치, `checks/check01.m` CHECK 5). 통과 하나가 표본 약 130개 × 빔각 21개라 덧셈·비교 수만 번이면 끝나고, 보상 표를 만드는 데 필요한 것도 큐 장면 한 장과 학습 표(11 × 2 숫자)뿐이라 지상에서 올려 주든 위성에서 계산하든 부담이 없습니다.

## 8. 스스로 확인 문제 3개 (답은 부록)
1. 빔을 −5°에서 +5°로 바꾸면 기동 시간은 몇 초이고, DP는 표본을 몇 개 놓친 것으로 계산하나?
2. 통과 시작이 6월 1일 02:20 UTC(t0 + 8,400초)일 때 큐가 쓰는 30분 칸 번호 kc와 그 칸의 시간 범위, 가운데 시각 tRef는?
3. `attachCue`로 Early를 붙인 뒤 `evaluate`가 읽는 자료는 Early인가 Final인가? 코드의 어느 줄로 알 수 있나?

## 9. 5분 설명 대본 (직접 채우기)
(빈칸)

## 10. 세 문장 요약 (직접 채우기)
1. 이 파일은 ______를 받아서 ______를 만든다.
2. 핵심 가정은 ______다.
3. 제안서에서 이 파일이 책임지는 숫자는 ______다.

## 부록. 확인 문제 답
1. 각도 차 10° → 10 / 1.5 + 4 = 10.67초. 놓치는 표본 m = ceil(10.67 / 1.5) = ceil(7.11) = 8개(12초). (줄 341~342)
2. 큐 시각 tCue = 8,400 − 15 × 60 = 7,500초. kc = floor(7500 / 1800) = 4 → 4번째 칸은 5,400~7,200초(01:30~02:00 UTC), 이미 끝났으므로 사용. tRef = (4 − 0.5) × 1800 = 6,300초(01:45 UTC). 관측 칸은 floor(8400/1800) + 1 = 5이므로 lag = 5 − 4 = 1(30분 열). (줄 269~272, 258)
3. Final이다. `evaluate`(줄 407)는 `D.Pr`를 읽고, `attachCue`(줄 122)는 Early를 `D.cuePr`라는 다른 필드에 넣을 뿐 `D.Pr`는 건드리지 않는다. `cuePr`를 읽는 곳은 `cueScene`(줄 281) 하나뿐이다.
