"""그림(관측 가능 높이): 천저와 10° 기울임을 좌우로 나눠 비교 (2026-11-03 사용자 요청 2차 개편)
숫자 출처(손으로 치지 않음):
  ../matlab/out/sens_pcloss_15/key_sens_pcloss.json  R(강우율), lowestAtAdopt(감쇠로 못 보는 맨 아래 높이)
  ../matlab/out/system_budget_12u/key_system.json    offnadir.cleanFirstNullKm(바다 반사 없는 최저 높이, 0°와 10°)
사용: python make_fig_depth.py figs/figI_depth.png
"""
import json, sys
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.patches import Patch

out = sys.argv[1]
Z = json.load(open('../matlab/out/sens_pcloss_15/key_sens_pcloss.json', encoding='utf-8'))
S = json.load(open('../matlab/out/system_budget_12u/key_system.json', encoding='utf-8'))
R = Z['R']
atten = Z['lowestAtAdopt']
deg = S['offnadir']['deg']
clut0 = S['offnadir']['cleanFirstNullKm'][deg.index(0)]
clut10 = S['offnadir']['cleanFirstNullKm'][deg.index(10)]
plt.rcParams['font.family'] = 'Malgun Gothic'
plt.rcParams['axes.unicode_minus'] = False
NAVY, GREEN, GRAY, ORANGE, GOLD = '#1f3b57', '#1baf7a', '#b7bfc8', '#eb6834', '#f0b429'
TOP = 6   # 2026-11-03 사용자 요청: 위가 너무 길어 표시 범위를 6 km로 제한(관측은 구름 꼭대기까지 이어짐)

fig, axes = plt.subplots(1, 2, figsize=(10.2, 4.1), sharey=True)
for ax, clut, title in [(axes[0], clut0, '천저 관측 (기울이지 않음)'), (axes[1], clut10, '10° 기울여 겨냥')]:
    for k, at in enumerate(atten):
        ax.bar(k, clut, width=0.58, color=GRAY, zorder=2)
        if at > clut:
            ax.bar(k, at - clut, bottom=clut, width=0.58, color=ORANGE, zorder=2)
        floor = max(at, clut)
        ax.bar(k, TOP - floor, bottom=floor, width=0.58, color=GREEN, alpha=0.85, zorder=2)
        ax.text(k, floor + 0.15, f'{floor:.1f}', ha='center', va='bottom', fontsize=10.5, fontweight='bold', color=NAVY, zorder=4)
    ax.axhspan(4.5, 5.0, color=GOLD, alpha=0.35, zorder=1)
    ax.text(len(R) / 2 - 0.5, 0.5, f'바다 반사가 {clut:.1f} km 아래를 가림', ha='center', va='center',
            fontsize=10, color='#4d5760', fontweight='bold', zorder=4)
    ax.set_xticks(range(len(R)))
    ax.set_xticklabels([f'{r:g}' for r in R], fontsize=11)
    ax.set_xlabel('강우율 [mm/h]', fontsize=11, color=NAVY)
    ax.set_ylim(0, TOP)
    ax.set_yticks(range(0, TOP + 1))
    ax.set_title(title, fontsize=12.5, fontweight='bold', color=NAVY, pad=21)
    for sp in ('top', 'right'):
        ax.spines[sp].set_visible(False)
    ax.tick_params(labelsize=10.5)
axes[0].set_ylabel('높이 [km]', fontsize=11.5, color=NAVY)
axes[0].text(3.3, 4.75, '융해층', fontsize=9.5, color='#8a6d1a', va='center', fontweight='bold', zorder=4)
axes[0].text(0.0, 1.015, '관측은 구름 꼭대기까지 이어짐 (그림 표시는 6 km까지)', transform=axes[0].transAxes, fontsize=9.2, color='#0e7a52', fontweight='bold', va='bottom')
axes[1].text(0.0, 1.015, '융해층과 얼음층은 그대로 관측', transform=axes[1].transAxes, fontsize=9.2, color='#0e7a52', fontweight='bold', va='bottom')
fig.legend(handles=[Patch(color=GREEN, label='관측 가능'), Patch(color=GRAY, label='바다 반사로 가림'), Patch(color=ORANGE, label='비 감쇠로 가림')],
           loc='lower center', bbox_to_anchor=(0.5, -0.04), ncol=3, fontsize=10.5, frameon=False)
fig.tight_layout(rect=[0, 0.04, 1, 1])
fig.savefig(out, dpi=200, bbox_inches='tight')
print('saved', out, '| 하한 천저', round(clut0, 2), '10도', round(clut10, 2), '| 감쇠', atten)
