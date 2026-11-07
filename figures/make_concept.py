import sys, os
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch, Polygon, Rectangle, Ellipse, Circle, Wedge
import numpy as np

out = sys.argv[1]
plt.rcParams['font.family'] = 'Malgun Gothic'
plt.rcParams['axes.unicode_minus'] = False

fig, ax = plt.subplots(figsize=(11, 6.0))
ax.set_xlim(0, 110); ax.set_ylim(0, 60); ax.axis('off')

SC = 74   # scene width
# backgrounds
ax.add_patch(Rectangle((0, 30), SC, 30, fc='#eef3fa', ec='none', zorder=0))
ax.add_patch(Rectangle((0, 7), SC, 23, fc='#f8fbfd', ec='none', zorder=0))
ax.text(72.5, 57.8, '우주', fontsize=8.5, color='#6b7d93', ha='right')
ax.add_patch(Rectangle((0, 0), 56, 7, fc='#bcd6ec', ec='none', zorder=1))
ax.text(2, 2.6, '서해 · 동중국해 (장마 상류 바다)', fontsize=9, color='#1f4e79')
ax.add_patch(Polygon([[54, 0], [SC, 0], [SC, 10.5], [66, 11.5], [59, 9.5], [55, 7]], closed=True,
                     fc='#d9e8c8', ec='#8aa05a', lw=1, zorder=1))
ax.text(69.5, 2.2, '한반도', fontsize=9, color='#4a6a1f', ha='center')


def cloud(cx, base, w, top):
    h = top - base
    circ = []
    for k in range(9):
        x = cx + (k - 4) / 4 * w * 0.42
        y = base + h * (0.35 + 0.25 * np.cos((k - 4) / 4 * np.pi / 2))
        r = h * (0.28 + 0.08 * np.cos((k - 4) / 4 * np.pi / 2))
        circ.append((x, y, r))
    circ.append((cx, top - h * 0.28, h * 0.3))
    for (x, y, r) in circ:
        ax.add_patch(Circle((x, y), r, fc='#ffffff', ec='#9aa8b6', lw=1.4, zorder=3))
    for (x, y, r) in circ:
        ax.add_patch(Circle((x, y), r - 0.25, fc='#ffffff', ec='none', zorder=3.5))
    ax.add_patch(Rectangle((cx - w * 0.55, base - 0.2), w * 1.1, h * 0.3, fc='#ffffff', ec='none', zorder=4))
    ax.plot([cx - w * 0.52, cx + w * 0.52], [base - 0.2, base - 0.2], color='#9aa8b6', lw=1.2, zorder=4)
    for k in np.linspace(cx - w * 0.4, cx + w * 0.4, 7):
        ax.plot([k, k - 0.7], [base - 0.4, 7.3], color='#5b8fc4', lw=1.1, zorder=2)


cloud(10.5, 9.5, 10, 26)
ax.text(10.5, 27.6, 'cold형 호우\n(꼭대기가 높음)', fontsize=8, ha='center', color='#33475b')
cloud(37, 9.5, 13, 17.5)
ax.text(29.5, 19.5, 'warm형 호우\n(꼭대기가 낮음)', fontsize=8, ha='right', color='#c0392b', fontweight='bold')


def satellite(x, y, s=1.0, ang=0, body='#4a6fa5', dish=False):
    t = np.deg2rad(ang)
    R = np.array([[np.cos(t), -np.sin(t)], [np.sin(t), np.cos(t)]])
    def tr(pts):
        return (R @ (np.array(pts).T * s)).T + np.array([x, y])
    ax.add_patch(Polygon(tr([[-1.2, -1.2], [1.2, -1.2], [1.2, 1.2], [-1.2, 1.2]]), fc=body, ec='#1f3b57', zorder=6))
    ax.add_patch(Polygon(tr([[-5, -0.8], [-1.4, -0.8], [-1.4, 0.8], [-5, 0.8]]), fc='#7fa7d8', ec='#1f3b57', zorder=6))
    ax.add_patch(Polygon(tr([[1.4, -0.8], [5, -0.8], [5, 0.8], [1.4, 0.8]]), fc='#7fa7d8', ec='#1f3b57', zorder=6))
    if dish:
        ax.add_patch(Polygon(tr([[-1.6, -1.3], [1.6, -1.3], [0.9, -2.6], [-0.9, -2.6]]), fc='#d0d5db', ec='#1f3b57', zorder=6))


# 천리안 2A
satellite(9, 53.5, s=0.9, body='#7a8a9c')
ax.text(9, 56.6, '천리안 2A (정지궤도)', fontsize=8.5, ha='center', fontweight='bold', color='#33475b')
ax.add_patch(Polygon([[9, 51.5], [4, 30.5], [46, 30.5]], closed=True, fc='#c9d6e6', ec='none', alpha=0.4, zorder=1))

# K-RainEye
sx, sy = 43, 50
satellite(sx, sy, s=1.0, ang=-10, body='#c0392b', dish=True)
ax.text(sx + 6.5, sy + 2.4, 'KW-RainEye', fontsize=9.5, fontweight='bold', color='#c0392b')
ax.text(sx + 6.5, sy - 0.4, '12U 큐브위성 · 고도 550 km', fontsize=8, color='#c0392b')
ax.plot([sx, sx], [sy - 3, 7.5], color='#999', lw=1, ls=':', zorder=2)
ax.text(sx + 0.7, 33.5, '바로 아래(천저)', fontsize=7.6, color='#777', rotation=90, va='center')
ax.add_patch(Polygon([[sx - 0.3, sy - 3.0], [34.2, 14.5], [39.6, 14.5]], closed=True, fc='#f5b7b1', ec='#c0392b',
                     lw=1, alpha=0.6, zorder=5))
ax.add_patch(Wedge((sx, sy - 3), 8, 252, 270, width=0.6, fc='#c0392b', ec='none', zorder=5))
ax.text(sx - 4.6, sy - 13, '±10°\n기울여 따라가기', fontsize=7.8, color='#c0392b', ha='right')

# ground station and KMA
gx, gy = 60.5, 10
ax.add_patch(Polygon([[gx - 1.1, gy], [gx + 1.1, gy], [gx, gy + 2.3]], fc='#7a8a9c', ec='#33475b', zorder=6))
ax.add_patch(Wedge((gx, gy + 3.3), 2.2, 200, 340, fc='#d0d5db', ec='#33475b', zorder=6))
ax.text(gx, gy - 2.4, '대전 지상국', fontsize=8.2, ha='center', fontweight='bold', color='#2c6e9b', zorder=8)
kx, ky = 69.5, 11.5
ax.add_patch(Rectangle((kx - 2.8, ky - 0.5), 5.6, 4, fc='#f4f6ea', ec='#5b7a1f', lw=1.1, zorder=6))
for k in range(3):
    ax.add_patch(Rectangle((kx - 2.1 + k * 1.6, ky + 0.5), 0.9, 0.9, fc='#ffffff', ec='#5b7a1f', lw=0.6, zorder=7))
ax.text(kx, ky - 2.4, '기상청', fontsize=8.2, ha='center', fontweight='bold', color='#5b7a1f', zorder=8)
# KIM은 기상청이 돌리는 수치예보 모델이므로 기상청 건물 위에 잘 보이게 붙인다
ax.add_patch(Rectangle((kx - 3.9, ky + 4.2), 7.8, 5.6, fc='#5b7a1f', ec='#3f5715', lw=1.1, zorder=7))
ax.text(kx, ky + 7.0, 'KIM\n수치예보', fontsize=8.8, ha='center', va='center', fontweight='bold', color='white', linespacing=1.15, zorder=8)


def arrow(p1, p2, color, rad=0.0, lw=1.6, ls='-'):
    ax.add_patch(FancyArrowPatch(p1, p2, arrowstyle='-|>', mutation_scale=12, color=color, lw=lw, ls=ls,
                                 connectionstyle=f'arc3,rad={rad}', zorder=9))


def num(x, y, n, color):
    ax.add_patch(Circle((x, y), 1.5, fc=color, ec='white', lw=1, zorder=10))
    ax.text(x, y, n, fontsize=8.5, ha='center', va='center', color='white', fontweight='bold', zorder=11)


# ① 천리안 영상 → 기상청(KIM과 합쳐 호우 후보 찾기)
arrow((12.5, 51.5), (kx - 1, ky + 10.0), '#5b7a1f', rad=-0.28, ls='--')
num(25, 49.6, '1', '#5b7a1f')
# ② 지상국 → 위성 (표적 목록 업링크)
arrow((gx - 0.6, gy + 6), (sx + 2.0, sy - 3.4), '#2c6e9b', rad=0.12)
num(53.5, 31, '2', '#2c6e9b')
# ③ 겨냥 관측
num(36.3, 24, '3', '#c0392b')
# ④ 위성 → 지상국 → 기상청 (하향·전달)
arrow((sx + 4.2, sy - 2.0), (gx + 1.6, gy + 6.2), '#2c6e9b', rad=-0.25)
arrow((gx + 2.8, gy + 1.3), (kx - 3.0, ky + 1.3), '#5b7a1f')
num(64.5, 30, '4', '#2c6e9b')

# right panel: steps
px = 76.5
ax.add_patch(FancyBboxPatch((px, 0.8), 32.5, 58, boxstyle='round,pad=0.3,rounding_size=1', fc='#ffffff', ec='#b8c4d0', lw=1, zorder=6))
steps = [('1', '#5b7a1f', '호우 후보 찾기', '천리안 2A 영상과 수치예보(KIM)로\n바다 위 호우 후보를 고른다'),
         ('2', '#2c6e9b', '"어떻게 기울일지" 보내기', '비를 따라갈 기울기 계획을 세워\n대전 지상국이 위성에 올린다'),
         ('3', '#c0392b', '비 따라가며 관측', '위성이 계획대로 ±10° 안에서 기울이며\n레이더로 비구름 속을 높이별로 잰다'),
         ('4', '#5b7a1f', '15분 안에 전달', '자료를 내려받아 관측 후 15분 안에\n기상청 예보관에게 보낸다')]
for k, (n, col, head, body) in enumerate(steps):
    y = 54 - k * 14.2
    num(px + 2.6, y, n, col)
    ax.text(px + 5, y, head, fontsize=10.5, fontweight='bold', va='center', color='#1f2d3d', zorder=11)
    ax.text(px + 2, y - 5.2, body, fontsize=9.2, va='center', color='#33475b', linespacing=1.4, zorder=11)

fig.savefig(os.path.join(out, 'figE_concept.png'), dpi=200, bbox_inches='tight')
print('ok')
