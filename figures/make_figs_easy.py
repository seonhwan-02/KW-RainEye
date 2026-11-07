"""제안서용 그림: 시스템 구성도(그림 3)와 레이더 송수신 구성도(그림 4).
사용: python make_figs_easy.py <출력 폴더>
2026-11-02 사용자 요청 반영:
  - 범례를 위성 용어로: 자체 개발 / 공동 개발 / 상용·기존 시설 / 정보 활용
  - 상자 글을 핵심만 남김(예: '디지털로 바꾸기' → 'ADC')
색 구분(색약도 구분되게 색과 테두리 모양을 함께 바꿈):
  자체 개발 = 진한 빨강 굵은 테두리, 공동 개발 = 노랑, 상용·기존 시설 = 회색, 정보 활용 = 청록 점선
"""
import sys, os
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

out = sys.argv[1]
plt.rcParams['font.family'] = 'Malgun Gothic'
plt.rcParams['axes.unicode_minus'] = False

# (채움, 테두리, 테두리 굵기, 테두리 모양)
OWN = ('#f7b9b0', '#a8231a', 2.4, '-')      # 자체 개발
COOP = ('#fde2a0', '#b86b00', 1.6, '-')     # 공동 개발
BUY = ('#e4e8ed', '#5c6b7a', 1.3, '-')      # 상용·기존 시설
USER = ('#c4ebe2', '#0d7366', 1.8, '--')    # 정보 활용
NOTE = ('#ffffff', '#33475b', 1.2, '-')     # 설명 상자
FS = 12


def box(ax, x, y, w, h, text, kind, fs=FS, bold=False):
    fc, ec, lw, ls = kind
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle='round,pad=0.25,rounding_size=0.8',
                                fc=fc, ec=ec, lw=lw, ls=ls))
    ax.text(x + w / 2, y + h / 2, text, ha='center', va='center', fontsize=fs,
            fontweight='bold' if bold else 'normal', linespacing=1.3)


def frame(ax, x, y, w, h, title, ec='#7a93ad', fc='#f7f9fb', ls='-', tc='#1f3b57', tx=None):
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle='round,pad=0.3,rounding_size=1.2', fc=fc, ec=ec, lw=1.2, ls=ls))
    ax.text(x + 1.2 if tx is None else tx, y + h - 1.0, title, fontsize=FS + 1, fontweight='bold', color=tc, va='top')


def arrow(ax, x1, y1, x2, y2, style='-|>', color='#33475b', lw=1.5):
    ax.add_patch(FancyArrowPatch((x1, y1), (x2, y2), arrowstyle=style, mutation_scale=14, color=color, lw=lw))


def legend(ax, x, y, items, offs):
    for (k, t), dx in zip(items, offs):
        fc, ec, lw, ls = k
        ax.add_patch(FancyBboxPatch((x + dx, y), 4, 2.6, boxstyle='round,pad=0.1', fc=fc, ec=ec, lw=lw, ls=ls))
        ax.text(x + dx + 5.2, y + 1.3, t, fontsize=FS, va='center')


ALL = [(OWN, '자체 개발'), (COOP, '공동 개발'), (BUY, '상용, 기존 시설'), (USER, '정보 활용')]

# ---------------- 그림 3. 시스템 구성도
fig, ax = plt.subplots(figsize=(7.6, 5.66))
fig.subplots_adjust(0, 0, 1, 1)
ax.set_xlim(0, 110); ax.set_ylim(-4, 78); ax.axis('off')

frame(ax, 1, 40, 108, 37, '위성: 12U 큐브위성 1기 (약 21 kg)')
box(ax, 3, 55, 32, 16, 'Ka 강수레이더\n(자체 설계)\n비구름 높이별 관측', OWN, fs=FS + 0.5)
box(ax, 39, 55, 30, 16, '임무 소프트웨어 (자체)\n관측 계획 실행\n레이더 제어\n고장 시 안전모드', OWN)
box(ax, 73, 43, 34, 28, '위성 본체 (상용)\n구조 · 열 · 전력\n자세제어 (±10° 지향)\nS대역 통신\n궤도이탈 장치', BUY, fs=FS + 0.5)
box(ax, 3, 43, 66, 8, '본체 ↔ 레이더: 전력 · 명령 · 시각 · 관측 자료', BUY, fs=FS - 1)
arrow(ax, 35, 63, 39, 63, style='<|-|>'); arrow(ax, 69, 63, 73, 63, style='<|-|>')

frame(ax, 1, 2, 70, 34, '지상', tx=17)
box(ax, 3, 15, 20, 15, '대전 지상국\n(기존 시설)\n명령 상향\n자료 수신', BUY)
box(ax, 27, 15, 28, 15, '지상 소프트웨어 (자체)\n큐잉 · 지향 계획\n기상청용 자료(L2) 생성', OWN)
box(ax, 27, 4, 28, 8.5, '검보정 (공동)\n국립기상과학원 GPM 체계', COOP, fs=FS - 1.5)
box(ax, 3, 4, 20, 8.5, 'S대역 통신\n하루 약 6회 접속', BUY, fs=FS - 1.5)
arrow(ax, 23, 22.5, 27, 22.5, style='<|-|>'); arrow(ax, 41, 15, 41, 12.7, style='<|-|>')
arrow(ax, 13, 42.8, 13, 30.3, style='<|-|>', lw=1.8)

frame(ax, 74, 13, 35, 23, '정보 활용', ec='#0d7366', fc='#f3fbf9', ls='--', tc='#0d5a50')
box(ax, 76, 22.5, 31, 8, '기상청 (천리안 2A · KIM)\n관측 후보 제공', USER, fs=FS - 1)
box(ax, 76, 14.5, 31, 6.5, '예보관: 15분 안에 받아\n호우 판단에 활용', USER, fs=FS - 1)
arrow(ax, 76, 26.5, 55.3, 25.5, color='#0d7366', lw=1.8)
ax.text(63.5, 27.6, '볼 곳 후보', fontsize=FS - 1, color='#0d5a50', ha='center', fontweight='bold')
arrow(ax, 55.3, 18.5, 76, 17.8, color='#0d7366', lw=1.8)
ax.text(63.5, 15.4, '관측 결과', fontsize=FS - 1, color='#0d5a50', ha='center', fontweight='bold')
box(ax, 76, 3, 31, 7.5, '발사 (상용)\n경사 45° 라이드쉐어', BUY, fs=FS - 1)
legend(ax, 2, -3.6, ALL, [0, 20, 40, 72])
fig.savefig(os.path.join(out, 'figC_system_easy.png'), dpi=220, bbox_inches='tight')
plt.close(fig)

# ---------------- 그림 4. 레이더 송수신 구성도
fig, ax = plt.subplots(figsize=(7.6, 4.9))
fig.subplots_adjust(0, 0, 1, 1)
ax.set_xlim(0, 110); ax.set_ylim(-5, 66); ax.axis('off')


def board(ax, x, y, w, h, own_text):
    """FPGA 보드는 상용(회색), 그 안의 펌웨어는 자체 개발(빨강)."""
    box(ax, x, y, w, h, '', BUY)
    ax.text(x + w / 2, y + h - 4.6, 'FPGA 보드 (상용)', ha='center', va='center', fontsize=FS - 1, linespacing=1.2)
    box(ax, x + 1, y + 0.8, w - 2, 8.6, own_text, OWN, fs=FS - 1.5)


ax.text(0.5, 65.5, '송신 경로', fontsize=FS + 1, fontweight='bold', color='#33475b', va='top')
board(ax, 0.5, 43, 24, 19, '펌웨어 (자체)\n파형 생성')
box(ax, 28, 46, 16, 13, '상향변환\n(35.75 GHz)', COOP)
box(ax, 47.5, 46, 16, 13, 'GaN\n전력증폭기', COOP)
box(ax, 67.5, 46, 17, 13, '송수신\n스위치', BUY)
box(ax, 88.5, 44, 20, 17, '0.5 m\n전개 안테나', BUY, bold=True)
for x1, x2 in [(24.5, 28), (44, 47.5), (63.5, 67.5), (84.5, 88.5)]:
    arrow(ax, x1, 52.5, x2, 52.5)
ax.text(98.5, 37, '천저 또는 ±10°\n기울여 비구름 겨냥', fontsize=FS - 1, color='#33475b', ha='center', va='center',
        linespacing=1.25)

ax.text(0.5, 41.5, '수신 경로', fontsize=FS + 1, fontweight='bold', color='#33475b', va='top')
box(ax, 67.5, 22, 17, 12, '저잡음 증폭기\n(LNA)', BUY, fs=FS - 0.5)
box(ax, 47.5, 22, 16, 12, '하향변환', COOP)
box(ax, 28, 22, 16, 12, 'ADC', BUY)
board(ax, 0.5, 18.5, 24, 19, '펌웨어 (자체)\n펄스압축 · 높이 분해')
arrow(ax, 76, 46, 76, 34.2)
for x1, x2 in [(67.5, 63.5), (47.5, 44), (28, 24.5)]:
    arrow(ax, x1, 28, x2, 28)

box(ax, 0.5, 2, 25, 12, 'L1 처리\n소프트웨어 (자체)', OWN)
arrow(ax, 11, 18.5, 11, 14.2)
box(ax, 29.5, 2, 16, 12, '위성 컴퓨터\n저장 · 전송', BUY)
arrow(ax, 25.5, 8, 29.5, 8)
box(ax, 49.5, 0.5, 59, 15.5, '주요 성능\n감도 약 10.5 dBZ (요구 15 dBZ 이하)\n연직 해상도 175 m (요구 250 m 이하)\n±10° 지향 시 고도 약 3 km 위는 해면 반사 없음\n관측 시 전력 약 35 W',
    NOTE, fs=FS - 1.5)
legend(ax, 2, -4.6, ALL[:3], [0, 25, 50])
fig.savefig(os.path.join(out, 'figC_payload_easy.png'), dpi=220, bbox_inches='tight')
plt.close(fig)
print('ok')
