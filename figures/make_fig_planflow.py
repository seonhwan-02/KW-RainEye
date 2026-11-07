# -*- coding: utf-8 -*-
"""그림(지향 계획 흐름): 큐 수신부터 기울기 순서 상향까지 (2026-11-04, 시스템 구성 3절용)
수치 없는 구조도라 결과 파일을 읽지 않는다. 사용: python make_fig_planflow.py figs/figL_plan.png
"""
import sys
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

out = sys.argv[1]
plt.rcParams['font.family'] = 'Malgun Gothic'
plt.rcParams['axes.unicode_minus'] = False

NAVY = '#1f3b57'
OWN = ('#fdecea', '#c0392b')     # 자체 개발(지상 소프트웨어)
BUY = ('#e8f0f8', '#2c6e9b')     # 위성 실행
USER = ('#f4f6ea', '#5b7a1f')    # 외부 큐


def box(ax, x, y, w, h, title, sub, kind, fs=10.5, sfs=9.0):
    fc, ec = kind
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle='round,pad=0.25,rounding_size=0.8',
                                fc=fc, ec=ec, lw=1.3))
    ax.text(x + w / 2, y + h - 2.6, title, ha='center', va='center', fontsize=fs,
            fontweight='bold', color=NAVY)
    ax.text(x + w / 2, y + (h - 2.6) / 2 - 0.6, sub, ha='center', va='center', fontsize=sfs,
            color='#44505c', linespacing=1.45)


def arrow(ax, x0, x1, y):
    ax.add_patch(FancyArrowPatch((x0, y), (x1, y), arrowstyle='-|>', mutation_scale=16,
                                 lw=1.6, color='#5a6b7c'))


fig, ax = plt.subplots(figsize=(11.8, 3.1))
ax.set_xlim(0, 122)
ax.set_ylim(0, 31)
ax.axis('off')

# 외부 큐
box(ax, 1, 7, 19, 15, '큐', '천리안 2A 영상\nKIM 예측 강수대\n예보관 지정 해역', USER)

# 지상 소프트웨어 틀
ax.add_patch(FancyBboxPatch((24.5, 2.5), 63, 26, boxstyle='round,pad=0.3,rounding_size=1.2',
                            fc='#f7f9fb', ec='#7a93ad', lw=1))
ax.text(26, 27.2, '지상 소프트웨어(자체 개발)', fontsize=10, fontweight='bold', color=NAVY, va='top')

box(ax, 27, 7, 17.5, 15, '① 나우캐스트', '큐 장면을 비 이동만큼\n옮겨 위치 예측', OWN)
box(ax, 47.5, 7, 17.5, 15, '② 호우 확률 점수', '배운 확률표로\n시각과 각도별 점수', OWN)
box(ax, 68, 7, 17.5, 15, '③ 기울기 순서', '동적계획법으로\n통과 전체 최적', OWN)

# 위성 실행
box(ax, 101, 7, 20, 15, '위성', '명령 순서 그대로\n기울여 관측', BUY)

arrow(ax, 20.6, 26.3, 14.5)
arrow(ax, 45.1, 46.8, 14.5)
arrow(ax, 65.6, 67.3, 14.5)
arrow(ax, 86.1, 100.3, 14.5)
ax.text(93.2, 16.6, '상향', ha='center', fontsize=9.2, fontweight='bold', color='#5a6b7c')

fig.savefig(out, dpi=200, bbox_inches='tight', facecolor='white')
print('saved', out)
