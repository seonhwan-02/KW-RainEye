# KW-RainEye 분석 코드

장마 상류 바다의 호우를 따라가며 비구름 속을 높이별로 재는 **Ka대역 강수레이더 12U 초소형위성** 임무의 분석 코드입니다.
2026 스페이스 해커톤(우주항공청) 부문 3, 초소형위성 임무 아이디어 제안에 쓴 계산과 그림을 모두 담았습니다.

- 팀 KW-RainEye: 김선환(팀장, 성능 검증), 김재석(지향 계획 소프트웨어), 박건준(레이더와 시스템)
- 제안서 원문과 원고 생성 코드는 본선 심사(2026년 11월 26일)가 끝난 뒤 공개합니다.

## 무엇을 계산했나

| 질문 | 방법 | 코드 |
|---|---|---|
| 어떻게 겨냥하나 | 정지궤도·수치예보 큐를 실제 호우 확률로 바꾸고, 기동·정착 시간을 넣은 동적계획법으로 한 통과의 기울기 순서를 정함 | `dp/kre_lib.m`, `dp/dp_step1~3` |
| 정말 더 잡나 | 2023~2025년 장마철 GPM IMERG 실강수에 위성 궤도를 적용. 2023년 학습, 2024·2025년 검증 | `dp/dp_step3~5` |
| 볼 수 있고 12U에 들어가나 | RainCube 실측 감도 환산, 펄스압축 파형, Ka 감쇠, 해면 반사, 질량·전력·통신·전달 시간 예산 | `matlab/*.m` |

## 주요 결과

| 항목 | 결과 | 결과 파일 |
|---|---|---|
| 겨냥 이득(임무 관측창, 천저 대비 호우 기록) | 2024년 2.13배, 2025년 2.38배 | `out/dp_step4b_upstream/methods.csv` |
| 겨냥 이득(서해~동해 넓힌 해역) | 2024년 2.04배, 2025년 2.05배 | `out/dp_step4_realistic/methods.csv` |
| 점 겨냥(처음 설계)과 비교 | 2024년 1.15배, 2025년 1.40배 | `out/dp_step4b_upstream/methods.csv` |
| 대표 감도(요구 15 dBZ) | 10.5 dBZ, 가정 16가지 중 16가지 충족 | `matlab/out/sens_pcloss_15/` |
| 12U 전력(전개 패널 4장) | 생산 27.3 W, 요구 대비 1.23배, 운용 대비 1.42배 | `matlab/out/system_budget_12u/` |
| 질량(마진 20% 포함) | 21.2 kg | `matlab/out/system_budget_12u/` |
| 관측 후 기상청 전달(계획) | 10분(요구 15분) | `matlab/out/system_budget_12u/` |
| 경사 45° 대 태양동기궤도 체류 | 1.86배 | `matlab/out/key_results.json` |

모든 숫자는 모의와 개략 설계값입니다. 실제 부품 사양과 지상 시험으로 다시 확인해야 합니다.

## 폴더 구조

```
matlab/        레이더·시스템 설계 계산
  k_raineye_analysis.m      궤도, 감도 예산, 감쇠, 펄스압축 파형(LFM/NLFM), 부엽
  k_raineye_sens_pcloss.m   펄스압축 손실을 넣은 감도 16가지 조합, 감쇠 높이
  k_raineye_system.m        12U 시스템 예산(해면 반사 높이, ADC, 링크, 지상국 접속, 전력, 질량, 모드 교대)
  k_raineye_imerg*.m        초기 실강수 겨냥 모의(서해, 넓힌 해역)
  tools/make_report.py      결과 HTML 보고서
  out/                      결과(요약 txt, json, csv, 그림)
dp/            비를 따라가는 지향 계획
  kre_lib.m                 공용 함수(자료 읽기, 궤도, 큐, 확률표, 보상, 동적계획법, 채점)
  dp_step1_train.m          2023년으로 큐 강도별 호우 확률표 학습
  dp_step2_demo.m           한 번의 통과로 경로 시연
  dp_step3_validate.m       시즌 검증(Final 큐 + 오차 모형)
  dp_step4_realistic.m      거친 큐(IMERG Early)로 2023~2025년 검증
  dp_step4b_upstream.m      임무 관측창(북위 28~38°, 동경 119~127°) 검증
  dp_step5_sensitivity.m    정착 시간·큐 지연·기동 속도·지향 범위 바꿔 보기
out/           지향 계획 결과(단계별 폴더)
imerg/         GPM IMERG 자료 받기와 점검
figures/       제안서 그림 스크립트(결과 파일을 읽어 그림)
docs/코드해설/  코드 파일별 해설과 점검 스크립트(checks/)
```

## 실행 환경

- MATLAB R2025b. `dp/`와 `k_raineye_sens_pcloss.m`, `k_raineye_imerg*.m`은 기본 MATLAB만 씁니다.
  `k_raineye_analysis.m`은 Signal Processing, Phased Array System, Aerospace, Satellite Communications Toolbox,
  `k_raineye_system.m`은 Aerospace, Satellite Communications Toolbox가 필요합니다.
- Python 3.10 이상: `pip install -r requirements.txt`

## 실행 순서

1. **자료 받기**: NASA Earthdata 계정이 필요합니다(아이디·비밀번호는 실행 중 입력, 저장하지 않음).
   ```
   python imerg/harmony_download.py 2023-06-01 2023-09-30          # Final(채점용)
   python imerg/harmony_download.py 2023-06-01 2023-09-30 early    # Early(큐용)
   ```
   자료는 `바탕화면/K-RainEye_IMERG/`에 쌓입니다(연도마다 수 GB, 저장소에는 없음).
2. **레이더·시스템 계산**: MATLAB에서 `matlab/k_raineye_analysis.m` → `k_raineye_sens_pcloss.m` → `k_raineye_system.m`
3. **지향 계획**: `dp/dp_step1_train.m` → `dp_step2_demo.m` → `dp_step3_validate.m` → `dp_step4_realistic.m` → `dp_step4b_upstream.m` → `dp_step5_sensitivity.m`
4. **그림**: `figures` 폴더에서 실행합니다. 예:
   ```
   cd figures
   python make_figD_dp.py ../out/dp_step4_realistic/methods.csv figs/figD_dp_gain.png
   python make_fig_power.py ../matlab/out/system_budget_12u/key_system.json figs/figF_power.png
   ```

결과는 항상 `out/`과 `matlab/out/` 아래 파일로 저장되고, 모든 수치는 그 파일에서 읽습니다.

## 생성형 AI 활용

코드 작성, 결과 정리, 해설 문서 작성에 Claude(Anthropic)를 보조 도구로 썼습니다. 모든 수치와 출처는 팀이 확인했습니다.
