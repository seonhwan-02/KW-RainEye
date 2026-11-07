# 05. dp_step4_realistic.m 해설

> 담당: B   대상 파일: `dp/dp_step4_realistic.m` (293줄)   관련 결과 폴더: `out/dp_step4_realistic/`

## 1. 한 줄 역할
큐(어디에 비가 있는지 알려 주는 지도)를 정밀판 IMERG Final 대신 실시간에 가까운 거친 자료 IMERG Early로 바꿔도 '비 따라가는 지향 계획'(DP, 동적계획법)의 이득이 남는지를, 2023으로 학습하고 2024·2025로 검증해 7가지 방식의 호우 관측 수·배수·95% 신뢰구간·그림으로 만든다.

용어 풀이(처음 나오는 것만):
- IMERG(GPM 위성 강수 자료, 0.1° 격자·30분 간격). **Final**은 약 3.5개월 뒤 나오는 정밀판(앞뒤 시각 자료와 우량계 보정을 다 씀), **Early**는 약 4시간 뒤 나오는 빠른판(그 시각까지의 위성 자료만 씀). 이 코드에서 Final = 진실(채점), Early = 큐.
- 큐(cue): 위성이 지나가기 전에 "저기 비가 있다"고 알려 주는 장면. 운용 때는 천리안 2A가 맡는다.
- 나우캐스트(nowcast): 큐 장면을 이동 벡터(비가 움직이는 방향·속도)로 밀어 관측 시각의 비 위치를 예측하는 것.
- 호우 프로파일: 빔이 실제로 본 1.5초 표본 중 Final 강수가 10 mm/h 이상이었던 수. 모든 배수는 "천저 고정(위성 바로 아래만 봄) 대비 몇 배"다.

## 2. 흐름 (입력 → 처리 → 출력)
| 단계 | 하는 일 | 쓰는 함수·변수 | 나오는 것 |
|---|---|---|---|
| 준비 (줄 25~51) | 매개변수 두 벌(P: 가짜 오차 켬, Pe: 끔), 1단계 Final 학습 표 읽기, 방식 7개 이름·인덱스, 누적 배열 | `L.params`, `calib_2023.mat`→`calibF`, `iMain=4, iFin=6, iOr=7` | 빈 누적 배열 `tot, band, dayH, nPass, nMove` |
| 자료 (줄 53~61) | 해마다 Final·Early 읽고, 같은 시각·같은 칸에서 Early가 Final을 얼마나 맞히나 | `L.loadSeason(y,'final'/'early')`, `L.cueAgreement` | `agree(iy)`: 적중률·헛경보·호우 핵 인식률 |
| 학습 (줄 62~75, 2023만) | Early 큐 → 30·60분 뒤 Final 호우 확률 표 3벌 | `L.attachCue`, `L.calibrate` | `calibE, calibEP, calibE2` → `calib_early_2023.mat`, 예시 장면 `ex` |
| 시즌 반복 (줄 77~111) | 궤도 위상 8개 × 통과(약 307회)마다 7가지 방식의 빔 경로를 만들고 Final로 채점 | `L.orbitPasses, L.greedyPlan, L.rewardGrid, L.dpPlan, L.evaluate` | `tot(연,위상,방식,지표)`, `dayH(연,날,방식)`, `band`, `nMove` |
| 집계 (줄 113~153) | 위상 평균, 천저 대비 배수, 날짜 부트스트랩 CI, 5일 묶음 CI | `mTot, gain, ci, ciBlk, ratio, ciRatio` | 표에 들어갈 숫자 |
| 출력 (줄 155~281) | 화면 표, 그림 3장, summary/csv/json/mat/run_info, run_log 한 줄 | `exportgraphics, writetable, jsonencode, logRun` | `out/dp_step4_realistic/*`, `out/run_log.csv` |

## 3. 절별 해설

### 3.1 준비: 매개변수 두 벌과 방식 7개 (줄 25~51)
```matlab
L = kre_lib();
P = L.params();                                  % 3단계와 같은 매개변수 (가짜 큐 오차 켜짐)
Pe = P;  Pe.pDet = 1;  Pe.posSd = 0;  Pe.velSd = 0;   % Early 큐: 가짜 오차 끔
S = load(fullfile(here, '..', 'out', 'dp_step1_train', 'calib_2023.mat'));
calibF = S.calibN;                               % Final 큐로 학습한 표 (3단계와 같은 것)
years   = [2023 2024 2025];
methods = ["천저 고정", "기존 방식(Early 큐)", "DP 위치고정(Early 큐)", "DP 나우캐스트(Early 큐)", ...
           "DP 나우캐스트(Early+가짜 오차)", "DP 나우캐스트(Final 큐, 3단계)", "DP 완벽 정보(상한)"];
iMain = 4;  iFin = 6;  iOr = 7;
nDay  = 122;
tot   = zeros(nY, P.nPhase, nM, nK);   dayH = zeros(nY, nDay, nM);
```
3단계까지는 Final을 큐로 쓰면서 "큐가 호우 핵을 72%만 알아보고(pDet), 위치가 3 km(posSd), 속도가 2 m/s(velSd) 틀린다"는 **가짜 오차**를 일부러 넣었다. Early는 이미 실제 오차가 들어 있는 자료라서 `Pe`에서는 이 셋을 끈다(pDet=1이면 `rand >= 1`이 절대 참이 안 되어 못 알아보는 핵이 0개, posSd=0·velSd=0이면 더하는 난수가 0). `iMain=4`가 제안서 대표 숫자, `iFin=6`이 3단계 재현, `iOr=7`이 상한이다. `nDay=122`는 6~9월(30+31+31+30)이고, 시즌 30분 칸 수 5,856 = 122 × 48과 맞는다.

### 3.2 자료 읽기와 Early–Final 일치도 (줄 53~61)
```matlab
for iy = 1:nY
    Df = L.loadSeason(years(iy), 'final');
    De = L.loadSeason(years(iy), 'early');
    A = L.cueAgreement(Df, De, P);
    A.year = years(iy);
    agree = [agree, A];
```
`loadSeason`의 두 번째 인자 `'early'`가 `K-RainEye_IMERG\early\YYYYMM` 폴더와 `cache_early_YYYY_JJAS.mat` 캐시를 고르게 한다(01번 3.x절 loadSeason 참고). `cueAgreement`는 같은 시각·같은 칸에서 "Final이 호우(≥10 mm/h)인 칸 중 Early도 호우라 한 비율(적중, podHeavy)", "Early가 호우라 했는데 아니었던 비율(헛경보, farHeavy)", "Final 호우 덩어리(핵) 중 Early가 그 안 어딘가를 호우로 본 비율(coreDet)"을 센다(01번 3.x절 cueAgreement 참고). 결과(`summary.txt`): 호우 핵 인식 2023 58.3%, 2024 36.5%, 2025 40.8%. 3단계 가짜 오차를 같은 잣대로 재면 약 76%였으니, 실제 Early는 가정보다 훨씬 거칠다.

### 3.3 2023 학습 표 만들기 (줄 62~75)
```matlab
    if iy == 1
        DfE = L.attachCue(Df, De);
        calibE  = L.calibrate(DfE, Pe, 'nowcast', 2023);   % 주 결과용
        calibEP = L.calibrate(DfE, Pe, 'persist', 2023);   % 위치고정용
        calibE2 = L.calibrate(DfE, P,  'nowcast', 2023);   % Early + 가짜 오차용
        save(fullfile(outDir, 'calib_early_2023.mat'), 'calibE', 'calibEP', 'calibE2', 'P', 'Pe');
        [~, kEx] = max(squeeze(sum(Df.Pr >= P.thrHeavy, [1 2])));
        ex = struct('F', Df.Pr(:, :, kEx), 'E', De.Pr(:, :, kEx), 't', Df.tSlot(kEx), ...);
    end
    DfE = L.attachCue(Df, De);
    clear De;
```
`attachCue(Df, De)`는 Final 구조체에 `cuePr`(Early 장면)과 `cueMotion`(Early로 구한 이동 벡터)을 붙인다. 이후 큐를 보는 함수(`cueScene`)는 `cuePr`이 있으면 그걸 쓰고, 채점(`evaluate`)과 상한(oracle)은 그대로 `Pr`(Final)을 쓴다(01번 3.x절 attachCue·cueScene의 cuePr 분기 참고). 붙이기 전에 크기·격자·시각·출처가 같은지 `assert`로 확인하므로 자료가 어긋나면 바로 멈춘다.
`calibrate`는 "Early에서 x mm/h로 보인 칸이 30분(lag 1)·60분(lag 2) 뒤 Final에서 호우였던 비율"을 강도 구간 11개 × lag 2개 표로 만든다. 숫자 예: 그림 2에서 Early 큐가 10~15 mm/h로 보인 칸은 30분 뒤 실제 호우일 확률이 약 28%, Final 큐(가짜 오차 포함)면 약 52%다. 즉 같은 강도라도 Early가 보여 준 것은 덜 믿어야 하고, 그 '덜 믿는 정도'를 2023 한 해로만 배운 뒤 2024·2025에 그대로 쓴다. 예시 장면 `ex`는 2023에서 Final 호우 칸이 가장 많았던 시각(2023-09-19 18:30 UTC)이다.

### 3.4 시즌 반복: 같은 궤도·같은 씨앗으로 7가지 방식 채점 (줄 77~111)
```matlab
for ip = 1:P.nPhase
    passes = L.orbitPasses(Df, P, ip);
    for kp = 1:numel(passes)
        G = passes{kp};
        seed = years(iy) * 1e5 + ip * 1e4 + kp;          % 3단계와 같은 씨앗
        plans{1} = struct('cb', zeros(size(G.tq)), 'valid', true(size(G.tq)));           % 천저
        plans{2} = L.greedyPlan(G, DfE, Pe, 'nowcast', RandStream('mt19937ar','Seed',seed));   % 기존 방식
        [Rw, th] = L.rewardGrid(G, DfE, Pe, 'persist', ..., calibEP);  plans{3} = L.dpPlan(Rw, th, P);
        [Rw, th] = L.rewardGrid(G, DfE, Pe, 'nowcast', ..., calibE);   plans{4} = L.dpPlan(Rw, th, P);
        [Rw, th] = L.rewardGrid(G, DfE, P,  'nowcast', ..., calibE2);  plans{5} = L.dpPlan(Rw, th, P);
        [Rw, th] = L.rewardGrid(G, Df,  P,  'nowcast', ..., calibF);   plans{6} = L.dpPlan(Rw, th, P);
        [Rw, th] = L.rewardGrid(G, Df,  P,  'oracle', [], []);         plans{7} = L.dpPlan(Rw, th, P);
        for m = 1:nM
            E = L.evaluate(G, Df, P, plans{m});
            r(m, :) = [E.heavy, E.rain, E.cells, E.heavyNear, E.valid, E.n];
            dayH(iy, iday, m) = dayH(iy, iday, m) + E.heavy;
        end
```
통과(관측창을 한 번 지나가는 구간) 하나마다 7가지 빔 경로를 만들고 **모두 Final로** 채점한다. 방식 2~5는 `DfE`(큐 = Early)를, 6·7은 `Df`(큐 = Final 또는 완벽 정보)를 넘긴다. 큐가 보는 장면은 `cueSlot`이 고른다: 큐 시각(통과 시작 15분 전) 이전에 **끝난** 마지막 30분 칸이다. 숫자 예: 통과 시작이 10:17:30이면 큐 시각은 10:02:30, 쓰는 칸은 09:30~10:00(가운데 09:45), 관측 시각과 32분 차이라 lag 1 표를 쓴다. 씨앗 `연도×1e5 + 위상×1e4 + 통과번호`는 3단계와 똑같아서 방식 6이 3단계 결과(2.45배/2.73배)를 정확히 재현한다(README 10/25 기록). `dayH`는 통과 시작 날짜에 호우 수를 쌓는 것으로, 뒤의 부트스트랩 재료다.

### 3.5 집계: 위상 평균, 배수, 두 가지 부트스트랩 (줄 113~153)
```matlab
mTot = squeeze(mean(tot, 2));                    % nY × nM × nK  (궤도 위상 8개 평균)
gain = mTot ./ mTot(:, 1, :);                    % 천저 고정 대비 배수
rsB = RandStream('mt19937ar', 'Seed', 7);
for iy = 1:nY
    X = squeeze(dayH(iy, :, :));                 % 122일 × 7방식
    for b = 1:2000
        pick = randi(rsB, nDay, nDay, 1);        % 날짜 122개를 복원 추출
        s = sum(X(pick, :), 1);
        bs(b, :) = s / s(1);   br(b) = s(iMain) / s(iFin);
    end
    ci(iy, :, :) = reshape(prctile(bs, [2.5 97.5])', [1 nM 2]);
end
blk = 5;
for iy = 1:nY
    rsBB = RandStream('mt19937ar', 'Seed', 100 + years(iy));
    for b = 1:2000
        st = randi(rsBB, nDay - blk + 1, ceil(nDay / blk), 1);   % 시작일 25개 (1~118)
        pick = reshape((st + (0:blk - 1))', [], 1);   pick = pick(1:nDay);
```
배수는 "위상 8개 평균 호우 수 ÷ 천저 평균 호우 수"다. 숫자 예(2024, `methods.csv`): 264.75 ÷ 129.875 = 2.038배.
부트스트랩(bootstrap, 자료를 다시 뽑아 흔들림을 재는 법): 122일을 복원 추출(뽑은 날을 다시 넣고 뽑음)해 배수를 2,000번 다시 계산하고 2.5%·97.5% 지점을 95% 신뢰구간으로 삼는다. 장마 호우는 며칠씩 이어져 날들이 독립이 아니므로, **연속 5일 묶음** 25개(시작일 1~118에서 뽑아 5일씩 펼침, 125개 중 앞 122개)로 뽑는 두 번째 CI도 낸다. 묶음 CI는 연도별 씨앗(`100 + 연도`)이라 해를 더해도 다른 해 값이 안 바뀐다. 결과: 2024 DP(Early) 배수 CI 1.79~2.36(날짜) / 1.79~2.39(5일 묶음)로 거의 같다.

### 3.6 화면 출력 (줄 155~169)
```matlab
fprintf('  Early 큐 DP ÷ Final 큐 DP = %.2f (%.2f~%.2f) → Final 큐 이득의 %.0f%%가 남음\n', ratio(iy), ciRatio(iy, :), ...
    100 * (gain(iy, iMain, 1) - 1) / (gain(iy, iFin, 1) - 1));
```
"남은 이득"은 (Early 배수 − 1) ÷ (Final 배수 − 1)이다. 숫자 예(2024): (2.038 − 1) ÷ (2.727 − 1) = 1.038 ÷ 1.727 = 0.60 → 60%. 2023은 74%, 2025는 57%(README의 "57~74%"의 출처). 호우 수 자체의 비(ratio)는 2024에 264.75 ÷ 354.125 = 0.748이다.

### 3.7 그림 세 장 (줄 171~219)
- **fig_early_gain.png** (그림 1): 가로축에 방식 6개(천저 제외), 세로축은 천저 대비 호우 프로파일 배수, 막대 색은 2023(파랑, 학습)·2024(주황, 검증)·2025(노랑, 검증), 오차 막대는 날짜 부트스트랩 95% CI, 회색 선이 천저 = 1. 보이는 것: 기존 방식 1.17/1.13/1.21, DP 위치고정 1.96/1.88/1.97, **DP 나우캐스트(Early) 2.08/2.04/2.05**, Early+가짜 오차 1.95/1.98/1.95, Final 큐 2.45/2.73/2.84, 상한 4.13/4.21/4.73. 세 해 막대 높이가 거의 같고 CI가 겹쳐 "처음 보는 해에서도 약 2배"가 한눈에 보인다.
- **fig_early_calib.png** (그림 2): 가로축은 큐 장면에서 보인 강도 구간(0~0.5 … 30 이상 mm/h), 세로축은 30분 뒤 실제(Final) 호우 비율. 파란 원 = Final 큐(가짜 오차 포함), 주황 네모 = Early 큐, 노란 점선 = Early + 가짜 오차. 7 mm/h 아래에서는 세 선이 거의 포개지지만 7~10 구간부터 벌어져 10~15 구간에서 약 52% 대 28%, 30 이상에서 약 87% 대 75%다(정확한 값은 `calib_early_2023.mat`의 `calibE.pHeavy`). Early에 가짜 오차까지 더해도 Early 단독과 거의 같다 → Early의 실제 오차가 이미 가짜 오차보다 크다는 뜻.
- **fig_early_example.png** (그림 3): 2023-09-19 18:30 UTC 같은 시각의 Final(왼쪽)과 Early(오른쪽), 색은 강수 강도 0~30 mm/h, 빨간 선은 10 mm/h 호우 경계. Final에는 북위 33~34°·동경 120~122°와 북위 35~37°·동경 121~124°에 큰 호우 덩어리 두 개가 있는데, Early는 남쪽 덩어리만 비슷하게 잡고 북쪽 큰 덩어리는 작은 점 하나로만 보인다. 호우 핵 인식률 58%(2023)가 실제로 어떤 모습인지 보여 주는 장면이다.

### 3.8 저장 (줄 221~281)
```matlab
writetable(mt, fullfile(outDir, 'methods.csv'), 'Encoding', 'UTF-8');
key = struct('years', years, 'methods', methods, ..., 'gain', gain, 'ci95', ci, ...
    'earlyOverFinalCue', ratio', 'earlyOverFinalCueCi95Block5', ciRatioBlk, 'gainDPEarlyCi95Block5', ciBlk, ...
    'agreement', agree, 'params', rmfield(P, 'C'), 'paramsEarly', rmfield(Pe, 'C'));
save(fullfile(outDir, 'results.mat'), 'years', 'methods', 'mets', 'tot', 'band', 'dayH', 'ci', ...);
logRun(fullfile(here, '..', 'out', 'run_log.csv'), tRun, mfilename, outDir, sprintf('Early큐 DP 호우 %.2f배(2023, CI %.2f~%.2f)/...', ...));
```
`summary.txt`는 사람이 읽는 표, `methods.csv`는 연도×방식 21행(열: heavyProf, gainHeavy, ci95Low/High, 위상 최소·최대, 각도대별 호우 등), `key_dp_early.json`은 제안서·보고서 생성기가 읽는 숫자 묶음, `results.mat`는 원자료(`tot, dayH, band` 등)라 부트스트랩을 다시 돌릴 수 있다. `run_info.txt`에 MATLAB 버전과 매개변수 전체를 남기고, `run_log.csv`에 한 줄을 덧붙인다(메모리 규칙 "모든 실행은 결과 폴더 + run_log"). csv의 각도대별 열은 `band / P.nPhase`라 세 열의 합이 `heavyProf`와 같다(2023 DP Early: 61.75 + 40.125 + 121.75 = 223.625).

### 3.9 보조 함수 (줄 283~293)
```matlab
function logRun(file, tRun, script, outDir, note)
isNew = ~exist(file, 'file');
fid = fopen(file, 'a', 'n', 'UTF-8');
if isNew, fwrite(fid, [239 187 191]); fprintf(fid, 'time,script,outDir,note\n'); end
fprintf(fid, '%s,%s,%s,"%s"\n', string(tRun, 'yyyy-MM-dd HH:mm:ss'), script, outDir, note);
```
`ifelse`는 한 줄 조건식, `logRun`은 파일이 없을 때만 BOM(엑셀이 한글을 제대로 읽게 하는 3바이트)과 머리글을 쓰고, 메모에 쉼표가 있어도 깨지지 않게 큰따옴표로 감싼다.

## 4. 핵심 가정 3개
1. **Early의 거친 정도가 운용 큐(천리안 2A)의 거친 정도를 대신한다** — 실제 운용 큐 자료를 통째로 구해 모의하기 어렵고, Early는 "그 시각까지의 위성 자료만 쓴 실시간 추정"이라 성격이 비슷하다. 깨지면(천리안 적외선이 Early보다 훨씬 거칠면) 2배 이득이 더 줄어든다. 다만 그림 2가 보여 주듯 큐가 거칠어지면 학습 표가 자동으로 '덜 믿게' 조정되므로, 이득이 사라지기보다 서서히 줄어드는 쪽이다(Final 큐 → Early 큐로 가면서 2.73 → 2.04배).
2. **Early의 4시간 지연은 무시하고 품질만 본다** — 큐 지연은 3단계와 같은 15분으로 두고, 큐 장면은 큐 시각 전에 끝난 30분 칸이다. 운용 큐(천리안)는 몇 분 안에 나오므로 지연 문제는 자료 품질과 분리해 본 것이다. 깨지면(큐가 진짜 4시간 늦으면) 5단계 감도 결과처럼 큐 지연 45분에 1.8배 수준까지 떨어지고 그 이상은 계산하지 않았다.
3. **2023 한 해로 배운 '큐 강도 → 호우 확률' 표가 다른 해에도 통한다** — 학습·검증 분리를 지키기 위해 2024·2025에는 2023 표를 그대로 쓴다. 깨지면(해마다 Early 성격이 달라지면) 검증 해 배수가 학습 해보다 눈에 띄게 낮아야 하는데, 2.08 → 2.04 → 2.05로 거의 같아 현재 자료에서는 유지된다. 단, 2023 Early는 재처리본이라 2024·2025 실시간본보다 좋다(호우 핵 인식 58% 대 37·41%). 그래서 2023 표는 실시간본에 대해 약간 '낙관적인' 표인데도 검증 해에서 배수가 유지됐다는 점이 오히려 강건함의 근거가 된다.

## 5. 코드 검토 결과
| 번호 | 줄 | 지적 | 어떤 입력에서 틀어지나 | 판정 | 근거 |
|---|---|---|---|---|---|
| 1 | 83~96 (kre_lib cueSlot·rewardGrid) | Early 큐가 관측 시각 뒤(미래) 장면을 보는가 | 큐 칸 번호가 큐 시각을 포함하는 칸이거나 그 뒤면 미래 누수 | **문제 없음(오해)** | 큐 칸 = `floor((ts−900)/1800)`로 큐 시각 전에 끝난 마지막 칸, 이동 벡터도 그 칸과 그 앞 칸만 씀. 큐 시각 이후 칸에만 호우를 넣은 가짜 자료에서 보상이 전부 0 |
| 2 | 64, 74 (kre_lib attachCue) | Early·Final 격자·시각 정렬 확인이 충분한가; 줄 64와 74에서 `attachCue`를 두 번 부름 | 캐시 하나가 한 칸 빠졌거나 시각이 어긋나면 | **문제 없음** + 중복 호출은 **개선 제안(결과에는 영향 없음)** | 크기·위경도·tSlot·출처 4개 assert. 실제 2023 캐시 두 개가 통과하고, 시각을 30분 민 가짜 자료는 멈춤. 줄 64의 호출은 줄 74와 같은 결과라 지워도 됨 |
| 3 | 17, 230 | 2023 Early가 재처리본(2024-05 생성)인데 코드에서는 따로 처리하지 않음 | 2023 표를 실시간본에 적용할 때 큐를 조금 과신 | **개선 제안(결과에는 영향 없음)** | 코드는 문구로만 남김. 결과상 2023 인식률(58%)이 2024·2025(37·41%)보다 높아 경고가 사실. 2024로 학습해 2025를 검증하는 교차 확인을 추가하면 더 단단해짐 |
| 4 | 113~153 | 5일 묶음 부트스트랩의 블록 경계(시작일 범위, 묶음 안 연속성, 122일 자르기)와 씨앗 | 시작일이 118을 넘으면 인덱스 초과; 전치 순서가 틀리면 묶음이 끊김 | **문제 없음** | 시작일 1~118, `(st+(0:4))'`을 열 방향으로 펴 묶음 안 5일이 연속, 최대 인덱스 122. 저장된 `dayH`로 다시 계산한 CI가 `results.mat`의 `ci`·`ciBlk`와 일치 |
| 5 | 42, 86~96, 251~261, 280 | 방식 인덱스(iMain·iFin·iOr)와 csv 행 순서·이름 일치; 줄 280에 가짜 오차 방식이 숫자 5로 고정 | methods 순서를 바꾸면 run_log 메모가 다른 방식을 가리킴 | **문제 없음** + 숫자 5는 **개선 제안** | `methods(4)`='DP 나우캐스트(Early 큐)', `(6)`='…Final 큐', `(7)`='…상한'이고 plans{4/6/7}가 그 방식. csv `gainHeavy`가 `results.mat`의 `gain`과 같고 각도대 세 열 합 = heavyProf |
| 6 | 35 | Pe(pDet=1, posSd=0, velSd=0)가 정말 가짜 오차를 끄는가 | `rand >= pDet`가 pDet=1에서 참이 될 수 있으면 | **문제 없음** | `rand`는 [0,1)이라 1 이상이 없음. 가짜 자료에서 Pe는 씨앗 20개 모두 같은 보상 표, P는 씨앗에 따라 달라짐 |
| 7 | kre_lib loadSeason 86, rewardGrid 240·255, evaluate 408 | NaN·음수 강수(IMERG 결측 −9999.9) 처리 | 결측이 0으로 바뀌어 '비 없음'으로 채점 | **문제 없음** | 캐시를 만들 때 `Pr(isnan|<0)=0`, 자료 영역 밖은 NaN → 보상 0·채점 제외. 2023 Final·Early 캐시에 NaN·음수 0개 |
| 8 | 276~292 | run_log 메모가 저장 결과와 같은 숫자인가, 쉼표 포함 메모의 csv 안전성 | 메모에 큰따옴표가 들어가면 열이 깨짐 | **문제 없음** | 마지막 `dp_step4_realistic` 줄의 2.08/2.04/2.05와 CI가 `results.mat` `gain(:,4,1)`·`ci`와 일치, 메모는 큰따옴표로 감쌈(메모 안에 큰따옴표 없음) |

어떻게 확인했나(`checks/check05.m`, 실행 결과는 그 스크립트 출력 참고):
- **1번**: 격자 41×41·10칸짜리 가짜 자료를 만들어 큐 시각을 포함하는 칸부터 뒤쪽에만 20 mm/h를 넣고 `rewardGrid`를 불렀다. 돌아온 `info.kc`가 `(kc)*1800 ≤ ts−900 < (kc+1)*1800`을 만족하고 보상 표가 전부 0이면 미래를 안 본 것이다. 반대로 kc 칸에 비를 넣으면 보상이 양수가 되어 검사 자체가 유효함을 확인했다.
- **2번**: `L.loadSeason(2023,'final')`·`(2023,'early')` 캐시로 `attachCue`를 실제로 불러 4개 assert 통과를 보고, 작은 가짜 구조체의 `tSlot`을 30분 밀거나 `src`를 같게 하면 오류가 나는지 try/catch로 봤다.
- **3번**: `results.mat`의 `agree`에서 2023 coreDet가 2024·2025보다 큰지 봤다(문구가 사실인지).
- **4번**: 줄 120~153을 그대로 옮겨 `results.mat`의 `dayH`로 CI를 다시 계산해 저장값과 1e-9 안에서 같은지, 묶음 인덱스가 1~122 안에서 5일씩 이어지는지 봤다.
- **5번**: `results.mat`의 `methods(4/6/7)` 이름, `tot`에서 다시 만든 `gain`, `methods.csv`의 `gainHeavy`·각도대 열을 비교했다.
- **6번**: 가운데 호우 덩어리 하나가 있는 가짜 자료로 `rewardGrid`를 씨앗 20개로 불러, Pe는 전부 같고 P는 하나라도 다른지 봤다.
- **7번**: 두 캐시에서 `nnz(isnan(Pr))`과 `min(Pr)`을 봤고, 자료 밖을 겨냥한 빔이 `evaluate`에서 세어지지 않는지 가짜 자료로 봤다.
- **8번**: `run_log.csv`에서 마지막 `dp_step4_realistic` 줄의 "x.xx배"와 CI를 정규식으로 뽑아 `results.mat`와 소수 둘째 자리까지 비교했다.

### 5.9 확인 스크립트 실행 결과 (2026-10-31, `checks/check05.m`, 12.0초)

PASS = 코드가 의도대로 동작함(지적이 오해이거나 버그 없음), FAIL = 지적이 맞음(개선 제안 포함).

| 번호 | 결과 | 설명 |
|---|---|---|
| 1 | **PASS** | 큐 칸 = 큐 시각 전에 끝난 마지막 30분 칸, 그 뒤 칸의 호우는 보상 0 (ts 8가지) |
| 2 | **PASS** | 2023 Final·Early 캐시 정렬 통과(nT=5856), 시각/출처/칸수 어긋난 가짜 자료는 assert로 멈춤 [3/3]; 줄 64 중복 호출은 결과 영향 없음 |
| 3 | **PASS** | 호우 핵 인식 2023 0.583 > 2024 0.365, 2025 0.408 → 재처리본 경고가 사실(코드는 문구로만 처리, 개선 제안: 2024 학습→2025 검증 교차 확인) |
| 4 | **PASS** | 묶음 인덱스 1~122·5일 연속 예, 재계산 CI와 저장값 최대 차 0.0e+00 (DP Early 2024 묶음 CI 1.785~2.386) |
| 5 | **PASS** | methods(4/6/7)=Early 나우캐스트/Final/상한 예, tot→gain 재계산 예, csv 21행 gainHeavy·각도대 합=heavyProf 예 (2024 대표 2.038, Final 2.727, 상한 4.211); 줄 280의 숫자 5는 개선 제안 |
| 6 | **PASS** | results.mat의 Pe 값 예, Pe는 씨앗 20개 모두 같은 보상 표 예, P는 씨앗에 따라 달라짐 예 |
| 7 | **PASS** | 2023 캐시 NaN 0/0개, 최소값 0/0 (Final/Early), 영역 밖 표본 NaN 예 → 보상 0·채점 제외 |
| 8 | **PASS** | 마지막 줄의 2.08/2.04/2.05배/CI가 results.mat gain(:,4,1)·ci와 일치, 메모는 큰따옴표로 감쌈 |

요약: PASS 8개, FAIL 0개.

**판정 대조:** FAIL 없음. 지적 8개가 모두 오해이거나 결과에 영향 없는 개선 제안으로 확인됐다.

## 6. 다른 문서와의 연결
- 이 파일이 부르는 것: `dp/kre_lib.m`(01번) — `loadSeason`의 src 인자(01번 3.x절), `attachCue`·`cueAgreement`(01번 3.x절), `cueScene`의 cuePr 분기와 `cueSlot`(01번 3.x절), `calibrate`·`rewardGrid`·`dpPlan`·`greedyPlan`·`evaluate`(01번 3.x절). 입력으로 `out/dp_step1_train/calib_2023.mat`(dp_step1_train 해설)의 `calibN`을 쓴다.
- 이 파일을 부르는 것: 사람이 직접 실행(1→2→3→4 순). 결과를 읽는 것: `dp/dp_step5_sensitivity.m`(같은 Early 큐 설정을 기준값으로 씀), `dp/dp_step4b_upstream.m`(06번, 임무 관측창으로 같은 계산), `proposal/make_figD_dp.py`(`methods.csv`로 제안서 그림 D), README '핵심 결과' 표.
- 제안서에서 쓰인 숫자 (모두 `out/dp_step4_realistic/methods.csv`·`summary.txt`, 관측창 28.5~39.5N·119.5~131.5E = **서해~동해로 넓힌 해역**):
  - 대표 방식 DP 나우캐스트(Early 큐) 호우 배수: 2024 **2.04배**(95% CI 1.79~2.36), 2025 **2.05배**(1.78~2.42), 학습 해 2023 2.08배(1.83~2.36) — README '핵심 결과', 제안서 결과 절의 "넓힌 해역 2.04·2.05배".
  - Final 큐(3단계 재현): 2024 2.73배, 2025 2.84배, 2023 2.45배. Early는 그 이득의 60%(2024)·57%(2025)·74%(2023).
  - 완벽 정보 상한: 2024 4.21배, 2025 4.73배, 2023 4.13배. 대표 방식은 상한의 48.4%·43.4%·50.3%(`summary.txt`).
  - 기존 방식(Early 큐) 1.13/1.21배, Early+가짜 오차 1.98/1.95배(2024/2025). 호우 핵 인식 58/37/41%.
  - **주의**: 제안서 본문의 대표 숫자 "2.1~2.4배"는 **임무 관측창**(28~38N·119~127E, 06번 문서 `out/dp_step4b_upstream/`) 값이고, 이 문서의 2.04·2.05배는 **넓힌 해역** 값이다. 제안서는 두 숫자를 구분해 "임무 관측창 2.1~2.4배(2024·2025 검증; 넓힌 해역 2.04·2.05배)"로 쓴다(README 권장 표현). 심사에서 두 숫자가 섞이지 않게 답해야 한다.

## 7. 본선 예상 질문 3개와 답
**Q1.** 실제 운용에서는 천리안 2A를 큐로 쓴다면서 왜 IMERG Early로 모의했나요?
**A.** 천리안 적외선에서 강수를 뽑은 자료를 세 해 분량으로 구해 같은 격자에 맞추기 어려워, "그 시각까지의 위성 자료만 쓴 실시간 강수 추정"이라는 성격이 같은 IMERG Early를 대신 썼습니다. 이 모의는 큐가 거칠어졌을 때 이득이 얼마나 남는지를 보는 것이고, Early의 4시간 지연은 운용 큐(몇 분)와 다르므로 지연은 15분으로 두고 품질 차이만 봤습니다. 거친 큐에서도 2.04~2.05배가 남았고, 큐가 가짜 오차보다 더 거칠어도(핵 인식 37%) 이득이 서서히 줄 뿐 사라지지 않았습니다.

**Q2.** Early와 Final이 같은 위성 입력을 쓰는데, Final로 채점하면 Early 큐 성능이 과대평가되는 것 아닌가요?
**A.** 맞습니다. 그래서 코드 머리말과 summary.txt에 그 한계를 명시했고, 독립된 큐라면 성능이 이보다 낮을 수 있습니다. 다만 같은 시각·같은 칸에서 Early가 Final 호우 핵을 37~58%밖에 못 맞히고 헛경보도 43~57%로, 두 자료는 호우 위치에서 상당히 다릅니다. 또 큐 자체가 아니라 큐를 30~60분 뒤 호우 확률로 바꾸는 표를 2023으로만 배워 다른 해에 적용했으므로, 평가의 핵심인 '거친 큐로도 겨냥이 되는가'는 유지됩니다.

**Q3.** 2023은 재처리본, 2024·2025는 실시간본이라면 학습과 검증 자료가 다른 종류인데 괜찮나요?
**A.** 2023 재처리본이 실시간본보다 좋기 때문에(핵 인식 58% 대 37·41%) 2023으로 배운 표는 실시간본에 대해 큐를 조금 과신하는 쪽, 즉 검증 해에 불리한 방향입니다. 그런데도 검증 해 배수(2.04·2.05배)가 학습 해(2.08배)와 거의 같아, 자료 종류가 바뀌어도 결과가 견딘다는 근거가 됩니다. 더 단단히 하려면 2024로 배워 2025를 검증하는 교차 확인을 추가할 수 있습니다(5절 3번 개선 제안).

## 8. 스스로 확인 문제 3개 (답은 부록)
1. 통과 시작 시각이 06:40:00 UTC일 때 큐가 쓰는 30분 칸은 몇 시부터 몇 시까지이고, 관측 시각과의 차이로 lag 표는 몇 번을 쓰나?
2. 2025년 methods.csv에서 DP 나우캐스트(Early 큐) 호우 264.75? 아니면 235.5? 천저 고정 114.625로 배수를 직접 계산해 보고 `gainHeavy` 열과 맞춰 보라.
3. `Pe`에서 `pDet = 1`로 두면 `cueScene`의 `miss = rand(rs, nObj, 1) >= P.pDet`는 어떤 값이 되고, 그래도 `rand`를 부르는 이유(또는 부작용)는 무엇인가?

## 9. 5분 설명 대본 (직접 채우기)
(빈칸)

## 10. 세 문장 요약 (직접 채우기)
1. 이 파일은 ______를 받아서 ______를 만든다.
2. 핵심 가정은 ______다.
3. 제안서에서 이 파일이 책임지는 숫자는 ______다.

## 부록. 확인 문제 답
1. 큐 시각 = 06:40 − 15분 = 06:25. 그 전에 끝난 마지막 30분 칸은 06:00~06:30이 아니라 **05:30~06:00**이다(06:00~06:30 칸은 06:30에 끝나 06:25에는 아직 안 나왔다). 칸 가운데 05:45와 관측 06:40의 차이는 55분 → `G.kq − kc` = 2 → lag 2(60분) 표를 쓴다. (코드로는 `floor((06:25를 초로)/1800)`이 05:30~06:00 칸의 번호가 된다.)
2. 2025년 DP 나우캐스트(Early 큐) 호우는 **235.5**(264.75는 2024년 값). 235.5 ÷ 114.625 = 2.0545… → `gainHeavy` 2.0545256과 같다(`out/dp_step4_realistic/methods.csv` 2025 행).
3. `rand`는 0 이상 1 미만이므로 `>= 1`은 항상 거짓 → `miss`가 모두 false, 어떤 핵도 약해지지 않는다. 그래도 `rand`·`randn`은 호출되어 난수열을 소비하지만 결과에 쓰이지 않으므로 값에 영향이 없고, 같은 씨앗을 쓰는 다른 방식(5·6)과 난수열이 섞이지도 않는다(방식마다 새 RandStream을 만든다).
