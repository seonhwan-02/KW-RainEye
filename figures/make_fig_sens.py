"""그림 8: 감도 계산 계단(왼쪽 판만, 2026-11-03 사용자 요청: 16조합 산점도 제거, 크고 쉽게)
숫자 출처: ../matlab/out/sens_pcloss_15/key_sens_pcloss.json
  계단의 각 단계는 k_raineye_sens_pcloss.m 과 같은 식으로 다시 계산하고, 합이 json의 Zcentral·Zadopt와 맞는지 확인한다.
사용: python make_fig_sens.py ../matlab/out/sens_pcloss_15 figs/figG_sens.png
"""
import json, math, os, sys
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

d, out = sys.argv[1], sys.argv[2]
K = json.load(open(os.path.join(d, 'key_sens_pcloss.json'), encoding='utf-8'))
Zreq, Zc, Zad, loss = K['Zreq'], K['Zcentral'], K['Zadopt'], K['lossPC']
Re, mu, h, Rref = 6378.137, 398600.4418, 550, 400
Tfp = 2 * h * math.tan(math.radians(1.13 / 2)) / (Re * math.sqrt(mu / (Re + h) ** 3))
Tref = 7.9 / (Re * math.sqrt(mu / (Re + 400) ** 3))
d_alt = 20 * math.log10(h / Rref)
d_prf = -5 * math.log10(1800 * 1660e-6)
d_int = -5 * math.log10(Tfp / Tref)
d_bw = 5 * math.log10(1.2 / 2.5)
steps = [('RainCube 실측\n(고도 400 km)', 11.0), ('고도\n550 km', d_alt), ('송신\n반복률', d_prf), ('평균\n시간', d_int), ('대역\n보정', d_bw), ('펄스압축\n손실', loss)]
assert abs(11 + d_alt + d_prf + d_int + d_bw - Zc) < 0.02
assert abs(Zc + loss - Zad) < 0.02

plt.rcParams['font.family'] = 'Malgun Gothic'
plt.rcParams['axes.unicode_minus'] = False
NAVY = '#1f3b57'
fig, ax = plt.subplots(figsize=(8.6, 4.5))

cum = 0
tops = []
for i, (lab, v) in enumerate(steps):
    if i == 0:
        ax.bar(i, v, color='#9aa5b1', width=0.62)
        cum = v
        ax.text(i, v + 0.3, f'{v:.1f}', ha='center', fontsize=12, fontweight='bold', color=NAVY)
    else:
        base = cum if v >= 0 else cum + v
        ax.bar(i, abs(v), bottom=base, color='#eb6834' if v > 0 else '#1baf7a', width=0.62)
        ax.text(i, max(cum, cum + v) + 0.3, f'{v:+.1f}', ha='center', fontsize=11.5, fontweight='bold',
                color='#c2551e' if v > 0 else '#12835a')
        cum += v
    tops.append(cum)
    if i < len(steps) - 1:
        ax.plot([i + 0.31, i + 1 - 0.31], [cum, cum], color='#b7bec7', lw=1.1, ls=':')
ax.plot([len(steps) - 1 + 0.31, len(steps) - 0.31], [cum, cum], color='#b7bec7', lw=1.1, ls=':')
ax.bar(len(steps), cum, color='#2a78d6', width=0.62)
ax.text(len(steps), cum + 0.3, f'{cum:.1f}', ha='center', fontsize=13, fontweight='bold', color='#1a56db')
ax.axhline(Zreq, color='#c0392b', ls='--', lw=2)
ax.text(0.1, Zreq + 0.3, f'요구 {Zreq:g} dBZ', color='#c0392b', fontsize=12, fontweight='bold')
ax.annotate('', xy=(len(steps) + 0.55, cum), xytext=(len(steps) + 0.55, Zreq),
            arrowprops=dict(arrowstyle='<->', color='#12835a', lw=1.8))
ax.text(len(steps) + 0.72, (Zreq + cum) / 2, f'여유\n{Zreq - cum:.1f} dB', color='#12835a', fontsize=11, fontweight='bold', va='center')
ax.set_xticks(range(len(steps) + 1))
ax.set_xticklabels([s[0] for s in steps] + ['대표 감도'], fontsize=10.5, color=NAVY)
ax.set_ylabel('최소 감지 반사도 [dBZ]\n(낮을수록 약한 비까지 봄)', fontsize=10.5, color=NAVY)
ax.set_ylim(0, 17)
ax.set_xlim(-0.6, len(steps) + 1.35)
for s in ('top', 'right'):
    ax.spines[s].set_visible(False)
ax.tick_params(axis='y', labelsize=10)
ax.set_title('감도 계산: 실측 기준에서 설계 차이만 더하고 뺀다', fontsize=13, loc='left', pad=9, fontweight='bold', color=NAVY)
fig.savefig(out, dpi=200, bbox_inches='tight')
print('saved', out, '| 대표', round(cum, 2), '여유', round(Zreq - cum, 2))
