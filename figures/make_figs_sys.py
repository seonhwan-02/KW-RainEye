import sys, os, csv
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch, Patch
import numpy as np

out, modes_csv = sys.argv[1], sys.argv[2]
plt.rcParams['font.family'] = 'Malgun Gothic'
plt.rcParams['axes.unicode_minus'] = False

OWN = ('#fdecea', '#c0392b')     # 자체 설계·개발
COOP = ('#fdf0e1', '#d35400')    # 협력 개발
BUY = ('#e8f0f8', '#2c6e9b')     # 상용 조달·기존 시설
USER = ('#f4f6ea', '#5b7a1f')    # 사용자·외부


def box(ax, x, y, w, h, text, kind, fs=8.6, bold=False, lw=1.2):
    fc, ec = kind
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle='round,pad=0.25,rounding_size=0.8',
                                fc=fc, ec=ec, lw=lw))
    ax.text(x + w / 2, y + h / 2, text, ha='center', va='center', fontsize=fs,
            fontweight='bold' if bold else 'normal', linespacing=1.25)


def frame(ax, x, y, w, h, title, ec='#7a93ad', fc='#f7f9fb'):
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle='round,pad=0.3,rounding_size=1.2', fc=fc, ec=ec, lw=1))
    ax.text(x + 1.2, y + h - 1.6, title, fontsize=10, fontweight='bold', color='#1f3b57', va='top')


def arrow(ax, x1, y1, x2, y2, style='-|>', color='#33475b', lw=1.1, ls='-'):
    ax.add_patch(FancyArrowPatch((x1, y1), (x2, y2), arrowstyle=style, mutation_scale=11,
                                 color=color, lw=lw, linestyle=ls))


def legend_dev(ax, x, y):
    items = [(OWN, '자체 설계·개발'), (COOP, '협력 개발'), (BUY, '상용 조달·기존 시설'), (USER, '사용자·외부 기관')]
    for i, (k, t) in enumerate(items):
        ax.add_patch(FancyBboxPatch((x + i * 26, y), 3, 2.2, boxstyle='round,pad=0.1', fc=k[0], ec=k[1], lw=1))
        ax.text(x + i * 26 + 4, y + 1.1, t, fontsize=8.5, va='center')


# ---------------- 1. 시스템 아키텍처 (KASA 체계 구성: 위성·지상국·사용자·발사체)
fig, ax = plt.subplots(figsize=(11, 7.4))
ax.set_xlim(0, 110); ax.set_ylim(0, 74); ax.axis('off')
frame(ax, 1, 38, 108, 34, '위성 (12U 1기, 약 21 kg, 고도 550 km·경사 45°)')
box(ax, 3, 52, 33, 14.5, '탑재체: Ka대역 강수레이더\n35.75 GHz 펄스압축\nRF부(협력) · 디지털 신호처리부(자체)\n0.5 m 전개 반사판(조달)', OWN, fs=8.6, bold=False)
box(ax, 40, 52, 30, 14.5, '임무 비행소프트웨어(자체)\n모드 관리 · 표적 일정 실행\n레이더 제어 · 탑재 L1 처리\n자료 관리 · 고장 관리', OWN, fs=8.6)
box(ax, 74, 41, 33, 25.5, '위성 본체 (상용 12U 플랫폼)\n구조계 · 열제어계\n전력계(전개 태양전지판 4장)\n자세제어계 · S대역 통신\n본체 비행소프트웨어\n항력장치 (추진계 없음)', BUY, fs=8.6)
box(ax, 3, 41, 67, 7.5, '탑재체-본체 접속: 전력 첨두 35 W · 명령/원격측정 · L1 자료 · GNSS 시각 · 지향 명령(롤·피치 ±10°)', BUY, fs=8.3)
arrow(ax, 36, 59, 40, 59, style='<|-|>')
arrow(ax, 70, 59, 74, 59, style='<|-|>')
arrow(ax, 20, 52, 20, 48.6, style='<|-|>')
arrow(ax, 55, 52, 55, 48.6, style='<|-|>')

frame(ax, 1, 3, 70, 31, '지상국')
box(ax, 3, 16, 20, 12, '임무통제 및\n자료수신국\n대전 S대역\n(기존 시설 활용)', BUY, fs=8.5)
box(ax, 27, 16, 26, 12, '자료처리국(자체)\n큐잉 엔진 · 표적 일정 생성\nL1 → L2 처리\n품질 표시 · 전달', OWN, fs=8.5)
box(ax, 27, 5, 26, 7.5, '검보정(협력): 국립기상과학원\nGPM 지상검증 체계 재사용', COOP, fs=8.2)
box(ax, 3, 5, 20, 7.5, '위성-지상국 접속\nS대역 상향 64 kbps\n하향 2 Mbps', BUY, fs=7.9)
arrow(ax, 23, 22, 27, 22, style='<|-|>')
arrow(ax, 40, 16, 40, 12.8, style='<|-|>')
arrow(ax, 13, 41, 13, 28.4, style='<|-|>', lw=1.3)
ax.text(14.2, 35.5, 'S대역 무선 링크(앙각 10° 이상, 하루 5.9회)', fontsize=8, color='#2c6e9b')

frame(ax, 74, 14, 35, 20, '사용자 · 외부 접속', ec='#8aa05a', fc='#fafbf4')
box(ax, 76, 22, 31, 7.5, '기상청 국가기상위성센터\n천리안 2A 영상 · KIM 예측 → 큐 제공', USER, fs=8.3)
box(ax, 76, 15.2, 31, 5.6, '기상청 예보·특보 / KIM 자료동화\nL2 수신(관측 후 15분 이내)', USER, fs=8.2)
arrow(ax, 76, 25.5, 53.3, 25.5, color='#5b7a1f')
ax.text(64.5, 26.4, '큐(천리안·KIM)', fontsize=8, color='#5b7a1f', ha='center')
arrow(ax, 53.3, 18.2, 76, 18.2, color='#5b7a1f')
ax.text(64.5, 19.1, 'L2 산출물', fontsize=8, color='#5b7a1f', ha='center')
box(ax, 76, 4.5, 31, 7, '발사체: 중경사 라이드쉐어(12U 분리장치)\n위성-발사체 접속 요구서 · 접속 제어 문서', BUY, fs=8.2)
legend_dev(ax, 2, 0.2)
fig.savefig(os.path.join(out, 'figC_system_arch.png'), dpi=200, bbox_inches='tight')
plt.close(fig)

# ---------------- 2. 탑재체 블록도 (RF·디지털 처리 체인, 개발 방식 색 구분)
fig, ax = plt.subplots(figsize=(11, 5.6))
ax.set_xlim(0, 110); ax.set_ylim(0, 56); ax.axis('off')
ax.text(1, 54.5, '송신 경로', fontsize=9.5, fontweight='bold', color='#c0392b', va='top')
box(ax, 1, 40, 17, 11, '디지털 제어부(FPGA)\n선형 처프 1.2 MHz\n앞뒤 20% 진폭 성형\nPRF 1.5~1.8 kHz 가변', OWN, fs=8.2)
box(ax, 22, 40, 14, 11, '상향변환\nIF → 35.75 GHz', COOP, fs=8.4)
box(ax, 40, 40, 15, 11, 'GaN 고출력 증폭기\n첨두 10 W · 펄스 166 µs\n듀티 약 30%', COOP, fs=8.0)
box(ax, 59, 40, 15, 11, '순환기·송수신\n스위치·리미터\n격리 50 dB 이상', BUY, fs=8.2)
box(ax, 78, 37, 19, 16, '0.5 m 전개\n메쉬 반사판\n42.6 dBi · 빔폭 1.13°\n풋프린트 10.8 km', BUY, fs=8.4, bold=True)
for x1, x2 in [(18, 22), (36, 40), (55, 59), (74, 78)]:
    arrow(ax, x1, 45.5, x2, 45.5)
ax.text(98.5, 45, '천저 및\n롤·피치 ±10°\n지향 관측', fontsize=8.3, color='#c0392b', va='center')
ax.text(1, 34.5, '수신 경로', fontsize=9.5, fontweight='bold', color='#2c6e9b', va='top')
box(ax, 59, 21, 15, 10, '저잡음 증폭기\n(LNA)', BUY, fs=8.4)
box(ax, 40, 21, 15, 10, '하향변환\n35.75 GHz → IF', COOP, fs=8.4)
box(ax, 22, 21, 14, 10, 'ADC 12비트\n복소 1.8 MS/s\n동적 범위 62 dB', BUY, fs=8.2)
box(ax, 1, 21, 17, 10, 'FPGA 실시간 처리\n펄스압축(최소제곱\n부정합 필터)·평균', OWN, fs=8.2)
arrow(ax, 66.5, 40, 66.5, 31.3)
for x1, x2 in [(59, 55), (40, 36), (22, 18)]:
    arrow(ax, x1, 26, x2, 26)
box(ax, 1, 5, 25, 11, '탑재 L1 처리(자체 SW)\n해면 추적 · 잡음 추정\n반사도 프로파일 생성\n(1.5 s마다 464 B)', OWN, fs=8.2)
arrow(ax, 9.5, 21, 9.5, 16.3)
box(ax, 30, 5, 22, 11, '위성 본체 OBC\n저장 · 우선순위 하향\nS대역 2 Mbps', BUY, fs=8.2)
arrow(ax, 26, 10.5, 30, 10.5)
box(ax, 56, 3.5, 52, 14, '주요 성능(설계안)\n천저 감도 약 10.5 dBZ(요구 13 dBZ 이하) · 연직해상도 175 m\n거리 부엽 -48.1 dB(빔 평균) · 해면 위 1.1 km부터 정량(천저)\n±10° 지향 시 고도 약 3 km 이상 정량 · 가동 시 DC 27~35 W\n원시 자료 43 Mbps → 탑재 처리 후 궤도당 0.3 MB', ('#ffffff', '#c0392b'), fs=8.2)
legend_dev(ax, 2, 0.2)
fig.savefig(os.path.join(out, 'figC_payload.png'), dpi=200, bbox_inches='tight')
plt.close(fig)

# ---------------- 3. 시스템 모드 상태도 (11/3 밤: 간격 넓히고 글씨 키움)
fig, ax = plt.subplots(figsize=(11.5, 6.1))
ax.set_xlim(0, 120); ax.set_ylim(0, 63); ax.axis('off')
NAVY = '#1f3b57'
NL = chr(10)
BLU = ('#eaf3fd', '#1a6fdb')
RED = ('#fdeeee', '#e02b2b')


def mbox(x, y, w, h, title, body, kind, tfs=13, bfs=10.5):
    fc, ec = kind
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle='round,pad=0.35,rounding_size=1.6', fc=fc, ec=ec, lw=2.2))
    if body:
        ax.text(x + w / 2, y + h - 3.2, title, ha='center', va='center', fontsize=tfs, fontweight='bold', color=NAVY)
        ax.text(x + w / 2, y + (h - 3.2) / 2 - 0.7, body, ha='center', va='center', fontsize=bfs, color=NAVY, linespacing=1.35)
    else:
        ax.text(x + w / 2, y + h / 2, title, ha='center', va='center', fontsize=tfs, fontweight='bold', color=NAVY)


def marr(x1, y1, x2, y2, color=NAVY, ls='-', lw=2.4, st='-|>'):
    ax.add_patch(FancyArrowPatch((x1, y1), (x2, y2), arrowstyle=st, mutation_scale=17, color=color, lw=lw, ls=ls))


def lab(x, y, t, color=NAVY, fs=11, ha='center'):
    ax.text(x, y, t, fontsize=fs, fontweight='bold', color=color, ha=ha, va='center')


mbox(1, 46, 24, 14, '발사 및 초기 운영', '분리, 전개, 점검', BLU)
mbox(36, 46, 18, 14, '안전 모드', '레이더 차단,' + NL + '지상 대기', BLU)
mbox(64, 46, 25, 14, '충전 및 대기 모드', '태양 지향,' + NL + '기울기 계획 수신', RED)
mbox(99, 46, 20, 14, '교정 모드', '내부 점검,' + NL + '해면 기준 점검', RED)
marr(25.7, 53, 35.3, 53); lab(30.5, 55.6, '전개 완료')
marr(54.7, 56, 63.3, 56); lab(59, 58.7, '지상 명령')
marr(63.3, 49.5, 54.7, 49.5, color='#e02b2b', ls='--', lw=2); lab(59, 46.8, '고장 감지', color='#e02b2b')
marr(89.7, 56, 98.3, 56); lab(94, 58.7, '교정 일정')
marr(98.3, 49.5, 89.7, 49.5); lab(94, 46.8, '교정 완료')

ax.add_patch(FancyBboxPatch((56, 4), 63, 25, boxstyle='round,pad=0.35,rounding_size=1.6', fc=RED[0], ec=RED[1], lw=2.2))
ax.text(87.5, 25.4, '관측 모드', ha='center', va='center', fontsize=14, fontweight='bold', color=NAVY)
mbox(59, 6, 27, 14, '천저 관측', '기본 운용', RED, tfs=12.5, bfs=10.5)
mbox(91, 6, 25, 14, '추적 관측', '계획 각도로' + NL + '호우 추적', RED, tfs=12.5, bfs=10.5)
marr(86.6, 13, 90.4, 13, st='<|-|>', lw=2.2)
marr(71, 45.4, 71, 29.8); lab(69.2, 37.5, '계획 시각 도달', ha='right')
marr(82, 29.8, 82, 45.4); lab(83.8, 37.5, '관측창 이탈', ha='left')

mbox(4, 8, 33, 17, '전송 모드', '지상국 접속 시' + NL + 'L1 자료 우선 하향', BLU, tfs=13.5, bfs=11)
marr(55.4, 16.5, 37.8, 16.5); lab(46.5, 19, '관측 종료', fs=11)
marr(37, 25.6, 65, 45.4, color='#1a6fdb', lw=2.4)
marr(56, 23, 46, 45.4, color='#e02b2b', ls='--', lw=2); lab(48.8, 41.5, '고장 감지', color='#e02b2b', ha='right')
fig.savefig(os.path.join(out, 'figC_modes.png'), dpi=200, bbox_inches='tight')
plt.close(fig)

# ---------------- 4. 실강수 자료 표적화 이득 (IMERG 2023 장마, 서해~동해 관측창)
rows = list(csv.DictReader(open(modes_csv, encoding='utf-8-sig')))
win = '서해~동해 전체'
pick = [('천저 고정', '천저 고정'),
        ('큐잉 ±3° 나우캐스트 15분', '±3°·15분'),
        ('큐잉 ±5° 나우캐스트 15분', '±5°·15분'),
        ('큐잉 ±10° 나우캐스트 10분', '±10°·10분'),
        ('나우캐스트 15분·±10°', '±10°·15분'),
        ('큐잉 ±10° 나우캐스트 30분', '±10°·30분'),
        ('큐잉 ±10° 나우캐스트 15분·정착 8 s(이전 기준안)', '±10°·15분\n정착 8 s'),
        ('큐잉 ±10° 위치고정 15분', '±10°·15분\n위치고정'),
        ('완벽 정보(상한, ±10°)', '완벽 정보\n(상한)')]
gh, gc = [], []
for m, _ in pick:
    r = [x for x in rows if x['window'] == win and x['mode'] == m][0]
    gh.append(float(r['gainHeavy'])); gc.append(float(r['gainCells']))
labels = [p[1] for p in pick]
fig, ax = plt.subplots(figsize=(11, 4.4))
x = np.arange(len(pick)); w = 0.38
b1 = ax.bar(x - w / 2, gh, w, label='호우 프로파일(10 mm/h 이상)', color='#2c6e9b')
b2 = ax.bar(x + w / 2, gc, w, label='호우 세포(서로 다른 호우 덩어리)', color='#c0392b')
for b, v in list(zip(b1, gh)) + list(zip(b2, gc)):
    ax.text(b.get_x() + b.get_width() / 2, v + 0.04, f'{v:.2f}', ha='center', fontsize=8)
ax.axhline(1, color='#555', lw=0.9)
ax.axvspan(2.5, 7.5, color='#e8f4ec', zorder=0)
ax.text(5, max(gc) * 1.02, '설계안: 지향 ±10°', ha='center', fontsize=9, color='#0f6b4a', fontweight='bold')
ax.set_xticks(x); ax.set_xticklabels(labels, fontsize=8.4)
ax.set_ylabel('천저 고정 대비 배수'); ax.set_ylim(0, max(gc) * 1.12)
ax.legend(fontsize=8.5, loc='upper left', frameon=False)
ax.grid(axis='y', alpha=0.3)
ax.set_title('실강수(GPM IMERG 2023년 6~9월)로 계산한 표적화 이득 (경사 45° 궤도 위상 8개 평균)', fontsize=11, fontweight='bold')
fig.tight_layout()
fig.savefig(os.path.join(out, 'figD_real_gain.png'), dpi=200, bbox_inches='tight')
plt.close(fig)
print('ok')
