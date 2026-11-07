"""그림 E-2: 한 궤도(95.6분) 안의 운용 모드 교대 타임라인 (관측 → 기동·정착 → 전송 → 충전·대기)
숫자 출처: ../matlab/out/system_budget_12u/key_system.json (power.mode, power.items)
사용: python make_fig_timeline.py ../matlab/out/system_budget_12u/key_system.json figs/figE_timeline.png
"""
import json, sys
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.patches import Patch

src, out = sys.argv[1], sys.argv[2]
K = json.load(open(src, encoding='utf-8'))
M = K['power']['mode']
T = M['orbitMin']
plt.rcParams['font.family'] = 'Malgun Gothic'
plt.rcParams['axes.unicode_minus'] = False

C_OBS, C_SLEW, C_TX, C_CHG = '#eb6834', '#9aa5b1', '#2a78d6', '#1baf7a'
rows = [('요구 조건\n(레이더 %g분)' % M['obsReq'], M['obsReq'], M['slewSettle'], M['txPerPass'], M['chargeReq']),
        ('운용 예상\n(레이더 %g분)' % M['obsOps'], M['obsOps'], M['slewSettle'], M['txPerPass'], M['chargeOps'])]

fig, ax = plt.subplots(figsize=(11, 3.6))
for i, (name, obs, slew, tx, chg) in enumerate(rows):
    y = 1 - i
    x = 0
    for w, c, lab in [(obs, C_OBS, '관측'), (slew, C_SLEW, '기동과 정착'), (tx, C_TX, '전송'), (chg, C_CHG, '충전 및 대기')]:
        ax.barh(y, w, left=x, height=0.55, color=c, edgecolor='white', linewidth=1.2)
        if w >= 6:
            ax.text(x + w / 2, y, f'{lab}\n{w:.0f}분', ha='center', va='center', fontsize=10.5,
                    color='white' if c != C_SLEW else '#223', fontweight='bold')
        x += w
    ax.text(-1.5, y, name, ha='right', va='center', fontsize=11)
ax.set_xlim(0, T); ax.set_ylim(-0.6, 1.6)
ax.set_yticks([])
ax.set_xlabel('한 궤도 안의 시간 [분]\n(궤도 주기 %.1f분, 최대 일식 %.1f분)' % (T, K['power']['eclipseMaxMin']), fontsize=10.5)
for s in ('top', 'right', 'left'):
    ax.spines[s].set_visible(False)
ax.tick_params(axis='x', labelsize=10)
ax.legend(handles=[Patch(color=C_OBS, label='관측 모드: 레이더 켬, ±10° 기울여 관측'),
                   Patch(color=C_SLEW, label='기동과 정착: 자세 바꾸고 멈추기'),
                   Patch(color=C_TX, label='전송 모드: 대전 접속 궤도에서만(하루 %.1f회 / 궤도 %.1f회)' % (M['txOrbitsPerDay'], M['orbitsPerDay'])),
                   Patch(color=C_CHG, label='충전 및 대기 모드: 태양 지향, 다음 계획 수신')],
          loc='upper center', bbox_to_anchor=(0.5, -0.42), ncol=2, fontsize=9.8, frameon=False)
ax.set_title('한 궤도 안에서 관측, 전송, 충전을 번갈아 쓴다', fontsize=12.5, loc='left', pad=8)
fig.savefig(out, dpi=200, bbox_inches='tight')
print('saved', out)
