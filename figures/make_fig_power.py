"""그림 7: 태양전지판 구성별 생산 전력 (2026-11-03 사용자 제공 디자인을 맑은 고딕으로 재현)
숫자 출처: ../matlab/out/system_budget_12u/key_system.json (power.alt, power.items.totalMargin, power.ops.totalMargin)
사용: python make_fig_power.py ../matlab/out/system_budget_12u/key_system.json figs/figF_power.png
"""
import json, sys
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

src, out = sys.argv[1], sys.argv[2]
K = json.load(open(src, encoding='utf-8'))
alt = K['power']['alt']
need_req = K['power']['items']['totalMargin']      # 요구(레이더 10분/궤도, 마진 포함)
need_ops = K['power']['ops']['totalMargin']        # 운용(레이더 3분/궤도, 마진 포함)
disp = {'몸체 부착만(유효 1.3면)': '몸체 부착만', '전개 2장': '전개 2장', '전개 4장(채택)': '전개 4장(채택)', '전개 6장': '전개 6장'}
names = [disp[n] for n in alt['names']]
oa = alt['oa']
plt.rcParams['font.family'] = 'Malgun Gothic'
plt.rcParams['axes.unicode_minus'] = False
NAVY, BLUE, GRAY = '#1f3b57', '#1a56db', '#c3cbd4'
GREEN, ORANGE = '#1e9e50', '#e8650f'

fig, ax = plt.subplots(figsize=(9.0, 3.9))
y = range(len(names))
ax.barh(y, oa, color=[BLUE if '채택' in n else GRAY for n in names], height=0.6)
for i, (n, w) in enumerate(zip(names, oa)):
    ax.text(w + 0.8, i, f'{w:.1f} W', va='center', fontsize=13, fontweight='bold',
            color=BLUE if '채택' in n else '#666')
for xv, c in [(need_ops, GREEN), (need_req, ORANGE)]:
    ax.axvline(xv, color=c, ls='--', lw=2.2)
ax.annotate(f'소요 전력(운용)\n{need_ops:.1f} W', xy=(need_ops, 3.62), xytext=(need_ops - 7.5, 4.75),
            fontsize=11.5, fontweight='bold', color=GREEN, ha='center', va='center', linespacing=1.3,
            bbox=dict(boxstyle='round,pad=0.45', fc='#eefaf1', ec=GREEN, lw=1.8),
            arrowprops=dict(arrowstyle='-', color=GREEN, lw=1.8))
ax.annotate(f'소요 전력(요구)\n{need_req:.1f} W', xy=(need_req, 3.62), xytext=(need_req + 7.5, 4.75),
            fontsize=11.5, fontweight='bold', color=ORANGE, ha='center', va='center', linespacing=1.3,
            bbox=dict(boxstyle='round,pad=0.45', fc='#fdf3ea', ec=ORANGE, lw=1.8),
            arrowprops=dict(arrowstyle='-', color=ORANGE, lw=1.8))
ax.set_yticks(list(y)); ax.set_yticklabels(names, fontsize=13, fontweight='bold', color=NAVY)
ax.set_xlabel('궤도 평균 전력 [W]', fontsize=13, fontweight='bold', color=NAVY)
ax.set_xlim(0, 52); ax.set_ylim(-0.55, 5.5)
ax.set_xticks([0, 10, 20, 30, 40, 50])
for s in ('top', 'right'):
    ax.spines[s].set_visible(False)
for s in ('bottom', 'left'):
    ax.spines[s].set_color(NAVY); ax.spines[s].set_linewidth(1.6)
ax.tick_params(axis='x', labelsize=12, colors=NAVY)
for t in ax.get_xticklabels():
    t.set_fontweight('bold')
fig.savefig(out, dpi=200, bbox_inches='tight')
print('saved', out, '| 운용', round(need_ops, 1), '요구', round(need_req, 1))
