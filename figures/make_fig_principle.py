"""그림(원리) 2장: ① 펄스와 메아리 개념도(figH1, 구름 단면 포함), ② 높이별 프로파일(figH2).
2026-11-03 사용자 요청: 그림 분리, 구름 매끈하게, 그리고 구름 '속'이 층별로 어떻게 재지는지 보이게(단면).
사용: python make_fig_principle.py figs
"""
import sys, os
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch, Polygon, Circle, Rectangle

out = sys.argv[1]
plt.rcParams['font.family'] = 'Malgun Gothic'
plt.rcParams['axes.unicode_minus'] = False
NAVY, RED, BLUE, ORANGE, GOLD = '#1f3b57', '#c0392b', '#2a78d6', '#eb6834', '#f0b429'

# ================================================== 그림 H1: 펄스와 메아리 (구름 단면)
fig, a = plt.subplots(figsize=(8.2, 5.4))
fig.subplots_adjust(0, 0, 1, 1)
a.set_xlim(0, 100); a.set_ylim(0, 66); a.axis('off')
a.add_patch(Rectangle((0, 7), 100, 59, fc='#f2f7fc', ec='none', zorder=0))
a.add_patch(Rectangle((0, 0), 100, 7, fc='#aecfe9', ec='none', zorder=0))
a.text(2, 2.6, '바다', fontsize=12, color='#1f4e79', fontweight='bold')

# 위성
sx, sy = 50, 57
a.add_patch(Rectangle((sx - 20, sy - 0.2), 14, 3.2, fc='#cfe0f3', ec=NAVY, lw=1.2, zorder=8))
a.add_patch(Rectangle((sx + 6, sy - 0.2), 14, 3.2, fc='#cfe0f3', ec=NAVY, lw=1.2, zorder=8))
a.add_patch(Rectangle((sx - 5, sy - 2.6), 10, 7.4, fc='#fdeeee', ec=RED, lw=2.2, zorder=8))
a.add_patch(Polygon([[sx - 3.6, sy - 2.6], [sx + 3.6, sy - 2.6], [sx + 2, sy - 4.8], [sx - 2, sy - 4.8]], fc='#d9dee5', ec=NAVY, lw=1.2, zorder=8))
a.text(sx, sy + 7, 'KW-RainEye', ha='center', fontsize=13, fontweight='bold', color=RED, zorder=8)


# 구름 (두 겹 원으로 매끈한 윤곽)
def cloud(cx, base, w, top):
    h = top - base
    circ = []
    for k in range(9):
        x = cx + (k - 4) / 4 * w * 0.42
        y = base + h * (0.35 + 0.25 * np.cos((k - 4) / 4 * np.pi / 2))
        r = h * (0.30 + 0.09 * np.cos((k - 4) / 4 * np.pi / 2))
        circ.append((x, y, r))
    circ.append((cx, top - h * 0.3, h * 0.33))
    for (x, y, r) in circ:
        a.add_patch(Circle((x, y), r, fc='#ffffff', ec='#8fa1b3', lw=1.6, zorder=2))
    for (x, y, r) in circ:
        a.add_patch(Circle((x, y), r - 0.33, fc='#ffffff', ec='none', zorder=2.5))
    a.add_patch(Rectangle((cx - w * 0.55, base - 0.3), w * 1.1, h * 0.32, fc='#ffffff', ec='none', zorder=3))
    a.plot([cx - w * 0.53, cx + w * 0.53], [base - 0.3, base - 0.3], color='#8fa1b3', lw=1.4, zorder=3)


cloud(50, 20, 32, 38)
a.text(36.5, 37.5, '비구름(단면)', ha='right', fontsize=12, color=NAVY, fontweight='bold', zorder=7)

# ---- 구름 속 세 층 (단면)
# 얼음 알갱이층
for (ix, iy) in [(42, 33.8), (47, 35.2), (53, 34.8), (57.5, 33.2), (44.5, 31.8), (50.5, 32.2)]:
    a.plot(ix, iy, marker='*', ms=9, color='#7fa7d8', zorder=3.6)
# 융해층(밝은 띠): 눈(*)이 내려오며 녹아 빗방울(●)이 되는 변화를 그대로 보여 준다
a.add_patch(Rectangle((37.5, 26.2), 25, 3.0, fc=GOLD, alpha=0.55, ec='none', zorder=3.5))
for xx in [41.5, 46.5, 52, 57]:
    a.plot(xx, 29.7, marker='*', ms=8.5, color='#7fa7d8', zorder=3.8)
    a.add_patch(FancyArrowPatch((xx, 29.1), (xx, 26.9), arrowstyle='-|>', mutation_scale=9, color='#8a6d1a', lw=1.3, zorder=3.8))
    a.add_patch(Circle((xx, 25.8), 0.55, fc='#2a78d6', ec='none', zorder=3.8))
# 빗방울층
for xx in np.linspace(40, 60, 7):
    a.plot([xx, xx - 1.1], [25.2, 21.3], color='#5b8fc4', lw=1.6, zorder=3.6)
# 구름 아래 비
for xx in np.linspace(41, 59, 7):
    a.plot([xx, xx - 1.4], [19, 8], color='#5b8fc4', lw=1.5, zorder=1.5)

# 층 설명 (오른쪽 리더선)
for (x1, y1, x2, y2, t, c) in [(60.5, 32.8, 68, 33.6, '얼음 알갱이층', NAVY),
                               (62.5, 27.7, 68, 27.7, '융해층', '#8a6d1a'),
                               (60.5, 23.2, 68, 21.8, '빗방울층', NAVY)]:
    a.plot([x1, x2 - 0.6], [y1, y2], color='#9aa5b1', lw=1.1, zorder=6)
    a.text(x2, y2, t, fontsize=10.5, color=c, fontweight='bold', va='center', zorder=7)

# 빔 원뿔(구름 단면 위로 비치게) + 높이 칸
a.add_patch(Polygon([[sx - 2, sy - 4.8], [sx + 2, sy - 4.8], [sx + 11, 7], [sx - 11, 7]], fc=ORANGE, alpha=0.10, ec=ORANGE, lw=1.2, zorder=4))
for h in np.arange(9.5, 48, 3.4):
    t = (sy - 4.8 - h) / (sy - 4.8 - 7)
    half = 2 + (11 - 2) * t
    a.plot([sx - half, sx + half], [h, h], color=ORANGE, lw=0.9, alpha=0.75, zorder=4.1)
a.annotate('높이 175 m 칸으로\n차례로 받는다', xy=(sx + 7.4, 17), xytext=(sx + 19, 12),
           fontsize=11, color='#b35c12', fontweight='bold', linespacing=1.35, va='center',
           arrowprops=dict(arrowstyle='-', color='#b35c12', lw=1.4), zorder=6)

# 펄스(내려감)와 메아리(올라옴)
a.add_patch(FancyArrowPatch((30, 51), (30, 26), arrowstyle='-|>', mutation_scale=22, color=ORANGE, lw=3.6, zorder=5))
a.text(28, 45.5, '① 전파 펄스', ha='right', fontsize=12.5, color='#b35c12', fontweight='bold', zorder=5)
a.text(28, 41.8, '초당 1,800번 송신', ha='right', fontsize=10.5, color=NAVY, zorder=5)
a.add_patch(FancyArrowPatch((62, 40.5), (70, 54.5), arrowstyle='-|>', mutation_scale=22, color=BLUE, lw=3.2, linestyle=(0, (6, 3)), zorder=5))
a.text(72, 60.5, '② 돌아온 메아리', ha='left', va='top', fontsize=12.5, color=BLUE, fontweight='bold', zorder=5)
a.text(72, 56.8, '돌아온 시간 = 비의 높이\n메아리 세기 = 비의 세기(dBZ)\n층마다 세기가 다르게 돌아온다', ha='left', va='top', fontsize=10, color=NAVY, linespacing=1.5, zorder=5)

# 펄스압축 설명 띠
a.add_patch(FancyBboxPatch((8, 9.5), 24, 7.5, boxstyle='round,pad=0.5,rounding_size=1.2', fc='white', ec=NAVY, lw=1.4, zorder=5))
a.text(20, 13.2, '펄스압축: 긴 펄스를 짧게\n압축해 높이를 잘게 나눔', ha='center', va='center', fontsize=10, color=NAVY, linespacing=1.45, zorder=6)
fig.savefig(os.path.join(out, 'figH1_principle.png'), dpi=200, bbox_inches='tight')
plt.close(fig)

# ================================================== 그림 H2: 프로파일 (2026-11-03 재설계: x=높이, y=세기, 점+선, 층별 배경색)
fig, b = plt.subplots(figsize=(7.4, 3.7))
h = np.arange(1.25, 8.3, 0.35)
z = 15 + 15 * np.exp(-((h - 4.0) / 2.6) ** 2)
z[(h >= 4.4) & (h <= 5.0)] += 7
bands = [(0, 1.1, '#e3e7eb', '#7d8893', '바다 반사로\n가려짐'),
         (1.1, 4.4, '#d9e9fa', '#3f6fae', '빗방울층'),
         (4.4, 5.0, '#fdeec9', '#8a6d1a', '융해층'),
         (5.0, 8.2, '#e3f2ec', '#1e7a5a', '얼음 알갱이층'),
         (8.2, 10, '#f4f6f8', '#7d8893', '구름 꼭대기 위')]
for x0, x1, fc, tc, name in bands:
    b.axvspan(x0, x1, color=fc, zorder=0)
    b.text((x0 + x1) / 2, 39.2, name, ha='center', va='top', fontsize=9.3, color=tc, fontweight='bold', linespacing=1.25, zorder=3)
mask = (h >= 4.4) & (h <= 5.0)
b.plot(h, z, '-', color='#1f3b57', lw=2.2, zorder=4)
b.plot(h[~mask], z[~mask], 'o', ms=5, color='#2a78d6', zorder=5)
b.plot(h[mask], z[mask], 'o', ms=7, color='#f0b429', mec='#8a6d1a', mew=1.2, zorder=6)
b.set_xlim(0, 10); b.set_ylim(13, 40)
b.set_yticks([15, 20, 25, 30, 35, 40])
# 15 dBZ 아래는 물결로 자름(축 생략 표시, 글꼴에 없는 ≈ 대신 직접 그림)
b.add_patch(Rectangle((-0.02, 13.45), 0.04, 1.15, transform=b.get_yaxis_transform(), color='white', zorder=6, clip_on=False))
_xw = np.linspace(-0.016, 0.016, 60)
for _dy in (0.0, 0.5):
    b.plot(_xw, 13.75 + _dy + 0.22 * np.sin(_xw / 0.016 * np.pi * 1.5), transform=b.get_yaxis_transform(),
           color='#1f3b57', lw=1.6, clip_on=False, zorder=7)
b.set_xlabel('높이 [km]', fontsize=11.5, color='#1f3b57')
b.set_ylabel('비의 세기 [dBZ]', fontsize=11.5, color='#1f3b57')
for sp in ('top', 'right'):
    b.spines[sp].set_visible(False)
b.tick_params(labelsize=10.5)
fig.savefig(os.path.join(out, 'figH2_profile.png'), dpi=200, bbox_inches='tight')
print('saved figH1, figH2')
