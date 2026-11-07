"""제안서 그림 D(겨냥 효과): DP 4단계 결과(methods.csv)로 방식별 호우 포착 배수를 그린다.
사용: python make_figD_dp.py ../out/dp_step4_realistic/methods.csv figs/figD_dp_gain.png
"""
import csv
import sys

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

src, out = sys.argv[1], sys.argv[2]
plt.rcParams['font.family'] = 'Malgun Gothic'
plt.rcParams['axes.unicode_minus'] = False

rows = list(csv.DictReader(open(src, encoding='utf-8-sig')))
years = sorted({int(r['year']) for r in rows})
years = [y for y in years if y <= 2024]   # 2026-11-03 사용자 결정: 그림에는 학습(2023)·검증(2024)만, 2025 검증은 본문 수치로
# 그림에 넣는 방식과 쉬운 이름 (천저 고정은 기준선 1로만 그린다)
SHOW = [('기존 방식(Early 큐)', '점 겨냥 찍기\n(처음 설계)'),
        ('DP 나우캐스트(Early 큐)', '비 따라가기 계획\n거친 큐 (IMERG Early)'),
        ('DP 나우캐스트(Final 큐, 3단계)', '비 따라가기 계획\n정밀 큐 (IMERG Final)'),
        ('DP 완벽 정보(상한)', '비를 미리 다 안다면\n(상한)')]
COLORS = ['#2a78d6', '#eb6834', '#1baf7a']       # 해별 색 (검증한 3색)
INK, INK2, GRID = '#0b0b0b', '#52514e', '#e4e3df'


def val(method, year, col):
    for r in rows:
        if r['method'] == method and int(r['year']) == year:
            return float(r[col])
    raise KeyError((method, year))


fig, ax = plt.subplots(figsize=(9.5, 4.4))
w = 0.34
ax.axvspan(1 - 0.48, 1 + 0.48, color='#fdf0e1', zorder=0)   # 제안 방식 강조
for iy, y in enumerate(years):
    xs = [k + (iy - (len(years) - 1) / 2) * w for k in range(len(SHOW))]
    g = [val(m, y, 'gainHeavy') for m, _ in SHOW]
    lo = [val(m, y, 'ci95Low') for m, _ in SHOW]
    hi = [val(m, y, 'ci95High') for m, _ in SHOW]
    lab = f'{y} (학습)' if iy == 0 else f'{y} (검증)'
    ax.bar(xs, g, width=w, color=COLORS[iy], edgecolor='white', linewidth=2, label=lab, zorder=2)
    ax.errorbar(xs, g, yerr=[[a - b for a, b in zip(g, lo)], [b - a for a, b in zip(g, hi)]],
                fmt='none', ecolor=INK2, elinewidth=1.2, capsize=3.5, zorder=3)
    for x, v, h in zip(xs, g, hi):
        ax.text(x, h + 0.06, f'{v:.2f}', ha='center', va='bottom', fontsize=10.5, color=INK, zorder=4)
ax.axhline(1, color=INK2, linewidth=1.2, linestyle='--', zorder=3, label='바로 아래만 볼 때 = 1')
ax.text(1, 2.72, '이 제안의 방식', ha='center', va='bottom', fontsize=11.5, color=INK, fontweight='bold')
ax.set_xticks(range(len(SHOW)))
ax.set_xticklabels([n for _, n in SHOW], fontsize=11, color=INK)
ax.set_ylabel('호우 관측 기록 수\n(바로 아래만 볼 때의 몇 배)', fontsize=10.5, color=INK)
ax.set_ylim(0, 5.6)
ax.yaxis.grid(True, color=GRID, linewidth=0.8)
ax.set_axisbelow(True)
for s in ('top', 'right'):
    ax.spines[s].set_visible(False)
for s in ('left', 'bottom'):
    ax.spines[s].set_color('#b5b4ae')
ax.tick_params(colors=INK2)
h, l = ax.get_legend_handles_labels()
ax.legend(h[1:] + h[:1], l[1:] + l[:1], loc='upper left', frameon=False, fontsize=10.5, ncol=len(years) + 1)
fig.tight_layout()
fig.savefig(out, dpi=200)
print('saved', out)
