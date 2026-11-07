import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch
import os, sys

out = sys.argv[1]
plt.rcParams['font.family'] = 'Malgun Gothic'
plt.rcParams['axes.unicode_minus'] = False

# ---------- Figure A: forecast skill problem ----------
yrs = list(range(2017, 2027))
csi = [0.35, 0.42, 0.43, 0.45, 0.35, 0.38, 0.45, 0.33, 0.43, 0.32]
fig, (a1, a2) = plt.subplots(1, 2, figsize=(11, 4.2), gridspec_kw={'width_ratios': [1.35, 1]})
cols = ['#9db4cc'] * 9 + ['#c0392b']
b = a1.bar([str(y) for y in yrs], csi, color=cols, edgecolor='#33475b', linewidth=0.6)
for x, v in zip(range(len(yrs)), csi):
    a1.text(x, v + 0.008, f'{v:.2f}', ha='center', va='bottom', fontsize=9)
a1.set_ylim(0, 0.62)
a1.set_ylabel('강수 적중률 (CSI)')
a1.set_title('여름철(6~8월) 단기 강수 예보 적중률', fontsize=12, fontweight='bold')
a1.annotate('2026년 0.32\n최근 10년 최저', xy=(9, 0.32), xytext=(8.0, 0.535),
            fontsize=9.5, color='#c0392b', ha='center',
            arrowprops=dict(arrowstyle='->', color='#c0392b'))
a1.grid(axis='y', alpha=0.3)
a1.tick_params(axis='x', labelsize=9)
a1.text(0, -0.2, '자료: 기상청 제출 자료(김위상 의원실 분석), 경북매일 2026.10.11',
        transform=a1.transAxes, fontsize=8, color='#555')

cases = ['거제\n2026.8.16~17 (이틀)', '가평\n2025.7 (일강수)']
pred = [271.7, 8.4]
obs = [927.6, 233.6]
import numpy as np
x = np.arange(2)
w = 0.36
a2.bar(x - w/2, pred, w, label='예측 (KIM 하루 전·기상청 예측)', color='#9db4cc', edgecolor='#33475b', linewidth=0.6)
a2.bar(x + w/2, obs, w, label='실제 관측', color='#c0392b', edgecolor='#33475b', linewidth=0.6)
for i in range(2):
    a2.text(x[i] - w/2, pred[i] + 15, f'{pred[i]:g}', ha='center', fontsize=9)
    a2.text(x[i] + w/2, obs[i] + 15, f'{obs[i]:g}', ha='center', fontsize=9)
a2.text(x[0], 1010, '예측은 실제의 29%', ha='center', fontsize=9.5, color='#c0392b')
a2.text(x[1], 330, '오차율 96%', ha='center', fontsize=9.5, color='#c0392b')
a2.set_xticks(x)
a2.set_xticklabels(cases, fontsize=9)
a2.set_ylim(0, 1100)
a2.set_ylabel('강수량 (mm)')
a2.set_title('극한호우 예측 강수량과 실제', fontsize=12, fontweight='bold')
a2.legend(fontsize=8.5, loc='upper right', frameon=False)
a2.grid(axis='y', alpha=0.3)
a2.text(0, -0.2, '자료: 기상청 제출 자료(김기현 의원실 분석), 데일리안 2026.10.8',
        transform=a2.transAxes, fontsize=8, color='#555')
fig.tight_layout()
fig.savefig(os.path.join(out, 'figA_forecast_problem.png'), dpi=200, bbox_inches='tight')
plt.close(fig)

# ---------- Figure B: system block diagram ----------
fig, ax = plt.subplots(figsize=(11, 6.8))
ax.set_xlim(0, 110)
ax.set_ylim(0, 68)
ax.axis('off')

def box(x, y, w, h, text, fc='#ffffff', ec='#33475b', fs=9, bold=False):
    p = FancyBboxPatch((x, y), w, h, boxstyle='round,pad=0.25,rounding_size=0.8',
                       fc=fc, ec=ec, lw=1.1)
    ax.add_patch(p)
    ax.text(x + w/2, y + h/2, text, ha='center', va='center', fontsize=fs,
            fontweight='bold' if bold else 'normal', linespacing=1.25)

def arrow(x1, y1, x2, y2, color='#33475b', style='-|>'):
    ax.add_patch(FancyArrowPatch((x1, y1), (x2, y2), arrowstyle=style, mutation_scale=11,
                                 color=color, lw=1.1))

ax.add_patch(FancyBboxPatch((1, 26.5), 108, 40.5, boxstyle='round,pad=0.3,rounding_size=1.2', fc='#f3f7fb', ec='#7a93ad', lw=1))
ax.text(3, 64.3, '우주 부문: 12U 위성 1기 (약 21 kg, 고도 550 km·경사 45°)', fontsize=10.5, fontweight='bold', color='#1f3b57')
ax.text(3, 60.6, '탑재체: Ka대역 강수레이더 (35.75 GHz)', fontsize=9.5, fontweight='bold', color='#c0392b')
box(3, 49, 17, 9, '디지털 제어부\n(FPGA)\n처프 생성·타이밍', fc='#fdecea')
box(24, 49, 13, 9, '상향변환\n35.75 GHz', fc='#fdecea')
box(41, 49, 14, 9, 'GaN 고출력\n증폭기\n첨두 10 W', fc='#fdecea')
box(59, 49, 12, 9, '순환기·\n송수신 스위치', fc='#fdecea')
box(75, 48, 17, 11, '0.5 m 전개\n메쉬 반사판\n42.6 dBi·빔폭 1.13°', fc='#fdecea', bold=True)
ax.text(94, 53.5, '천저 및\n±10° 지향\n관측', fontsize=8.5, va='center', color='#c0392b')
arrow(20, 53.5, 24, 53.5); arrow(37, 53.5, 41, 53.5); arrow(55, 53.5, 59, 53.5); arrow(71, 53.5, 75, 53.5)
box(41, 39, 14, 7, '저잡음 증폭기\n·하향변환', fc='#fdecea')
box(3, 39, 34, 7, 'ADC·펄스압축(부정합 필터)·적분\n→ L1 반사도 프로파일', fc='#fdecea')
arrow(65, 49, 55, 43.5)
arrow(41, 42.5, 37, 42.5)
box(60, 39, 48, 7, '주요 성능(설계안): 천저 감도 약 10.5 dBZ · 연직해상도 250 m 이하\n풋프린트 10.8 km · PRF 1.5~1.8 kHz · 펄스 166 µs · 대역 1.2 MHz', fc='#ffffff', ec='#c0392b', fs=8.3)
ax.text(3, 35.6, '위성 버스', fontsize=9.5, fontweight='bold', color='#1f3b57')
box(3, 28.5, 18, 5.5, 'S밴드 통신\n하향 2 Mbps', fc='#e8f0f8', fs=8.5)
box(24, 28.5, 19, 5.5, '탑재 컴퓨터(OBC)\n·대용량 저장장치', fc='#e8f0f8', fs=8.5)
box(46, 28.5, 21, 5.5, '자세제어: 별추적기·\n반작용휠·자기토커', fc='#e8f0f8', fs=8.5)
box(70, 28.5, 18, 5.5, '전력: 전개 태양전지판\n·배터리', fc='#e8f0f8', fs=8.5)
box(91, 28.5, 17, 5.5, '열제어·구조\n·항력장치', fc='#e8f0f8', fs=8.5)
arrow(30, 39, 30, 34.3)
arrow(24, 31.25, 21, 31.25)

ax.add_patch(FancyBboxPatch((1, 1), 108, 21.5, boxstyle='round,pad=0.3,rounding_size=1.2', fc='#fbf6f0', ec='#b08a5a', lw=1))
ax.text(3, 19.6, '지상 부문', fontsize=10.5, fontweight='bold', color='#6b4a1f')
box(3, 3, 19, 13.5, '대전 지상국\nS밴드 송수신\n(관측창 전체 가시)', fc='#fff4e5')
box(28, 3, 29, 13.5, '임무 운용센터\n① 큐잉 엔진: 표적 목록 생성\n② 이동 예측 보정(나우캐스트)\n③ L2 처리: 에코 정상고도·\n융해층·빙정층 반사도·PIA', fc='#fff4e5', fs=8.5)
box(64, 3, 19, 13.5, '기상청\n천리안 2A·KIM\n(큐 제공)\nL2 수신\n(관측 후 15분 이내)', fc='#fff4e5', fs=8.5)
box(89, 3, 19, 13.5, '활용\n예보관 호우 감시\nKIM 자료동화 평가\n검보정(GPM 체계)', fc='#fff4e5', fs=8.5)
arrow(12, 28.2, 12, 16.9, style='<|-|>')
ax.text(13.3, 24.6, '표적 업링크 / 자료 하향', fontsize=8, va='center', color='#6b4a1f')
arrow(22, 9.75, 28, 9.75, style='<|-|>')
arrow(64, 12.0, 57, 12.0)
ax.text(60.5, 13.0, '큐', fontsize=8, ha='center', color='#6b4a1f')
arrow(57, 7.0, 64, 7.0)
ax.text(60.5, 4.3, 'L2', fontsize=8, ha='center', color='#6b4a1f')
arrow(83, 9.75, 89, 9.75)

fig.savefig(os.path.join(out, 'figB_system_block.png'), dpi=200, bbox_inches='tight')
plt.close(fig)
print('ok')
