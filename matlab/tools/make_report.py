import json, base64, sys, os, html, datetime

d = sys.argv[1]
out = os.path.join(d, 'out')
k = json.load(open(os.path.join(out, 'key_results.json'), encoding='utf-8'))
summ = open(os.path.join(out, 'summary.txt'), encoding='utf-8').read()


def img(name, cap):
    b = base64.b64encode(open(os.path.join(out, name), 'rb').read()).decode()
    return f'<figure><img src="data:image/png;base64,{b}" alt="{html.escape(cap)}"><figcaption>{html.escape(cap)}</figcaption></figure>'


def f(x, n=2):
    return f'{x:.{n}f}'


g = k['gain45']
m = g['modes']
gi = m.index
LAT = [0, 10, 20, 30, 45, 60]
iN = {L: gi(f'큐잉 ±3° 나우캐스트 {L}분') for L in LAT}
iP = {L: gi(f'큐잉 ±3° 위치고정 {L}분') for L in LAT}
iO = gi('완벽 정보(상한, ±3°)')
iU = gi('큐잉 ±10° 나우캐스트 30분')
o, s, r, p, pc = k['orbit'], k['sens'], k['rain'], k['prf'], k['pc']
ks = json.load(open(os.path.join(out, 'key_sensitivity.json'), encoding='utf-8'))
kn = json.load(open(os.path.join(out, 'key_nlfm.json'), encoding='utf-8'))
dsn = kn['designs']; cfgn = kn['cfg']
def nrow(ic):
    return ''.join(f"<tr><td>{html.escape(cfgn[ic]) if j == 0 else ''}</td><td>{html.escape(dsn[j])}</td><td>{kn['farBeam'][ic][j]:.1f} dB</td><td>{kn['need'][ic][j]:.1f} dB</td><td>{kn['margin'][ic][j]:+.1f} dB</td><td>{kn['cleanH'][ic][j]/1e3:.2f} km</td><td>{kn['Zmin'][ic][j]:.1f} dBZ</td><td>{kn['loss'][ic][j]:.2f} dB</td></tr>" for j in range(len(dsn)))
rows_nlfm = ''.join(nrow(ic) for ic in range(len(cfgn)))
iT = dsn.index('LFM 테이퍼 + 부정합 필터'); iNL = dsn.index('NLFM + 정합 필터')
lab = ks['label']
def sidx(prefix):
    return next(i for i, x in enumerate(lab) if x.startswith(prefix))
rows_sens = ''.join(f"<tr><td>{html.escape(lab[i])}</td><td>{ks['gainCells'][i]:.2f}</td><td>{ks['gainHeavy'][i]:.2f}</td><td>{ks['gainProf'][i]:.2f}</td><td>{ks['gainQuant'][i]:.2f}</td><td>{ks['targetsPerPass'][i]:.1f}</td></tr>" for i in range(len(lab)))
iB = 0
iA10 = lab.index('민첩 + 10분')
iR10 = sidx('현실 목표안: 정착 4 s·응시 3 s·1.5°/s·10분')
iR15 = sidx('현실 목표안: 정착 4 s·응시 3 s·1.5°/s·15분·전체')

rows_gain = ''.join(
    f"<tr><td>{L}분</td><td>{f(g['gainCells'][iN[L]])}</td><td>{f(g['gainHeavy'][iN[L]])}</td>"
    f"<td>{f(g['gainProf'][iN[L]])}</td><td>{f(g['gainCells'][iP[L]])}</td><td>{f(g['gainHeavy'][iP[L]])}</td></tr>"
    for L in LAT)
rows_rain = ''.join(
    f"<tr><td>{R:g} mm/h</td><td>{f(gm)}</td><td>{f(gp)}</td><td>{f(pia, 1)}</td><td>{f(lo)}</td></tr>"
    for R, gm, gp, pia, lo in zip(r['R'], r['gamma'], r['gammaRainpl'], r['PIA'], r['lowest']))
rows_pc = ''
for ib, B in enumerate(pc['B']):
    for iw, w in enumerate(pc['wins']):
        rows_pc += (f"<tr><td>{B / 1e6:.1f} MHz</td><td>{w}</td><td>{pc['res'][ib][iw]:.0f} m</td>"
                    f"<td>{pc['psl'][ib][iw]:.1f} dB</td><td>{pc['far'][ib][iw]:.1f} dB</td></tr>")
quantRatio = g['quant'][iU] / g['quant'][0]
now = datetime.datetime.now().strftime('%Y-%m-%d %H:%M')

H = f'''<!doctype html><html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>K-RainEye MATLAB 결과</title>
<style>
:root{{--bg:#f6f8f9;--fg:#15232b;--mut:#56656d;--line:#d7dfe3;--acc:#0f7c6c;--accs:#e2f1ee;--hot:#b93b28;--hots:#f8e6e2}}
@media (prefers-color-scheme:dark){{:root{{--bg:#10181c;--fg:#e2ebee;--mut:#9fb1b8;--line:#2b3b44;--acc:#4cc2ad;--accs:#163a35;--hot:#ef7a64;--hots:#3b211c}}}}
body{{background:var(--bg);color:var(--fg);font-family:"Malgun Gothic","Apple SD Gothic Neo",system-ui,sans-serif;line-height:1.7;margin:0}}
.w{{max-width:900px;margin:0 auto;padding:32px 20px 80px}}
h1{{font-size:28px;margin:0 0 6px}} h2{{font-size:20px;margin:40px 0 10px;border-top:1px solid var(--line);padding-top:18px}} h3{{font-size:16px;margin:18px 0 6px}}
.mut{{color:var(--mut);font-size:14px}}
.box{{border-left:3px solid var(--acc);background:var(--accs);padding:12px 16px;margin:12px 0}}
.box.hot{{border-left-color:var(--hot);background:var(--hots)}}
table{{border-collapse:collapse;width:100%;font-size:14px;margin:8px 0}} th,td{{border-bottom:1px solid var(--line);padding:7px 9px;text-align:left;vertical-align:top}} th{{color:var(--mut);font-weight:600}}
.tw{{overflow-x:auto}} figure{{margin:10px 0}} img{{max-width:100%;border:1px solid var(--line);border-radius:6px;background:#fff}}
figcaption{{font-size:13px;color:var(--mut)}}
code,pre{{font-family:Consolas,monospace;font-size:13px}} pre{{white-space:pre-wrap;background:var(--accs);padding:12px;border-radius:6px;overflow-x:auto}}
</style></head><body><div class="w">
<h1>K-RainEye MATLAB 결과 보고</h1>
<p class="mut">분석 파일 <code>matlab/k_raineye_analysis.m</code> · MATLAB R2025b (Phased Array System, Satellite Communications Toolbox) · 보고서 생성 {now}</p>

<h2>결론</h2>
<ol>
<li><b>궤도:</b> 경사 45°가 태양동기궤도보다 관측창 체류 {f(o['dwell'][0])} vs {f(o['dwell'][1])} 분/일({f(o['dwell'][0] / o['dwell'][1])}배), 통과 {o['passes'][0]:.0f} vs {o['passes'][1]:.0f}회/시즌({f(o['passes'][0] / o['passes'][1])}배). SGP4 교차검증과 일치해요.</li>
<li><b>표적화 이득은 작아요.</b> 큐 지연 30분이면 전체 세포 {f(g['gainCells'][iN[30]])}배, 호우급 {f(g['gainHeavy'][iN[30]])}배예요. 지연 10분이면 호우급 {f(g['gainHeavy'][iN[10]])}배, 완벽 정보 상한도 전체 {f(g['gainCells'][iO])}배·호우급 {f(g['gainHeavy'][iO])}배예요.</li>
<li><b>민첩성 민감도:</b> 이득을 가장 크게 바꾸는 건 <b>큐 지연</b>과 <b>정착 시간</b>이에요. 기동 속도(1→2°/s)와 응시 시간(6→3 s)은 거의 영향이 없어요. 정착 4 s·큐 지연 10분이면 호우급 {ks['gainHeavy'][iR10]:.2f}배·프로파일 {ks['gainProf'][iR10]:.2f}배, 정착 2 s까지 줄이면 호우급 {ks['gainHeavy'][iA10]:.2f}배·프로파일 {ks['gainProf'][iA10]:.2f}배예요.</li>
<li><b>감도:</b> 0.5 m 안테나 중심값 {f(s['central'], 1)} dBZ, 가정에 따라 {f(s['range05'][0], 1)}~{f(s['range05'][1], 1)} dBZ. 목표 13 dBZ를 가정 조합의 {s['meet13_05'] * 100:.0f}%에서 충족해요. 1 m 안테나면 {f(s['range10'][0], 1)}~{f(s['range10'][1], 1)} dBZ.</li>
<li><b>강우 감쇠:</b> 20 mm/h에서 왕복 {f(r['PIA'][2], 0)} dB, 하부 {f(r['lowest'][2])} km가 안 보여요. 30 mm/h면 {f(r['lowest'][3])} km, 50 mm/h면 {f(r['lowest'][4])} km예요.</li>
<li><b>PRF:</b> 이론 최대 {p['prfMax'] / 1e3:.2f} kHz라 2.1 kHz는 불가해요. 1.8 kHz 고정은 롤 각도의 {p['f18'] * 100:.0f}%에서만 되고, 1.5~1.8 kHz 가변이면 {p['band'] * 100:.0f}%예요.</li>
<li><b>펄스압축·비선형 처프:</b> 비선형 처프(NLFM)는 도플러 0에서는 신호 손실 없이 부엽 −40 dB를 내지만, 0.5 m 안테나의 빔 안 도플러(±18 kHz)가 걸리면 빔 평균 부엽이 {kn['farBeam'][0][iNL]:.0f} dB로 무너져 <b>기각</b>했어요. 대신 <b>선형 처프 + 펄스 가장자리 20% 테이퍼 + 부정합 필터</b>가 해면 부엽을 요구선({kn['need'][0][iT]:.0f} dB)까지 낮춰, 지표 위 약 {kn['cleanH'][0][iT]/1e3:.1f} km부터 오염 없이 볼 수 있어요(감도 {kn['Zmin'][0][iT]:.1f} dBZ, 손실 {kn['loss'][0][iT]:.1f} dB).</li>
</ol>

<div class="box hot"><b>제안서에서 바꿔야 할 것.</b> 이전 초안의 "큐잉 포착률 60% vs 무작위 8%"는 검증되지 않은 수치였고, 이번 모의로 지지되지 않아요. 큐잉은 <b>'더 많이'가 아니라 '호우급을 더'</b> 보는 효과이고, 그 효과도 <b>큐 지연이 짧고(15분 이내, 목표 10분) 자세 정착이 빠를 때(4초 이내)</b>만 나와요. 민감도 분석으로 이 두 값을 요구사항으로 도출했어요(모의 1-b).</div>

<h2>모의 1: 궤도 커버리지</h2>
{img('fig1_ground_track.png', '그림 1. 하루 지상 궤적과 장마 관측창(북위 28~38°, 동경 119~127°)')}
{img('fig2_orbit_compare.png', '그림 2. 550 km 궤도 비교(장마철 120일, 초기 위상 8개 평균)')}
<div class="tw"><table><tr><th>궤도</th><th>체류 [분/일]</th><th>통과 [회/시즌]</th><th>평균 통과 [s]</th></tr>
<tr><td>{o['name'][0]}</td><td>{f(o['dwell'][0])}</td><td>{o['passes'][0]:.0f}</td><td>{o['passSec'][0]:.0f}</td></tr>
<tr><td>{o['name'][1]}</td><td>{f(o['dwell'][1])}</td><td>{o['passes'][1]:.0f}</td><td>{o['passSec'][1]:.0f}</td></tr></table></div>
<p class="mut">교차검증: {html.escape(o['xcheck'])}. 이전 검증 단계의 Python 계산(1.84배, 2.42배)과도 맞아요.</p>

<h2>모의 1: 큐잉 표적화 이득</h2>
{img('fig3_mode_hits.png', '그림 3. 관측 방식별 시즌당 강수 세포 포착(경사 45°, 지연 30분 기준)')}
{img('fig4_latency_gain.png', '그림 4. 큐 지연에 따른 표적화 이득(천저 고정 대비 배수)')}
<div class="tw"><table><tr><th>큐 지연</th><th>나우캐스트: 전체 세포</th><th>나우캐스트: 호우급</th><th>나우캐스트: 프로파일</th><th>위치고정: 전체</th><th>위치고정: 호우급</th></tr>{rows_gain}
<tr><td>완벽 정보 상한</td><td>{f(g['gainCells'][iO])}</td><td>{f(g['gainHeavy'][iO])}</td><td>{f(g['gainProf'][iO])}</td><td>-</td><td>-</td></tr>
<tr><td>±10° 겨냥, 30분</td><td>{f(g['gainCells'][iU])}</td><td>{f(g['gainHeavy'][iU])}</td><td>{f(g['gainProf'][iU])}</td><td colspan="2">정량 프로파일은 천저의 {quantRatio * 100:.0f}%</td></tr></table></div>
<p class="mut">수치는 천저 고정 대비 배수예요. 경사 45°, 정량 관측 ±3°(±29 km), 위상 8개 평균.</p>
<h3>왜 이득이 작은가</h3>
<ul>
<li>정량 관측을 ±3°로 제한해서 겨냥할 수 있는 폭이 ±29 km뿐이에요. 풋프린트 10.8 km와 세포 크기(반경 중앙값 8 km)에 비해 크게 넓지 않아요.</li>
<li>한 번 통과가 평균 {o['passSec'][0]:.0f}초인데, 기동 1°/s에 정착 8초와 응시 6초가 들어가 통과당 겨냥 횟수가 적어요.</li>
<li>천저만 봐도 강수 비율 8%에서 이미 많은 세포를 지나가요. 다른 세포로 겨냥을 옮기면 그사이 천저에서 만났을 세포를 놓쳐요.</li>
<li>큐가 오래될수록 세포가 움직여 위치가 어긋나요. 위치고정 큐는 지연 20분부터 천저보다 오히려 나빠요.</li>
<li>천리안이 warm형 세포를 덜 잡는다고 가정했어요(탐지확률 0.6). 이 약점이 그대로 반영됐어요.</li>
</ul>

<h2>모의 1-b: 지향 민첩성·큐 지연 민감도</h2>
<p>기준안(정착 8 s, 응시 6 s, 기동 1°/s, 정량 ±3°, 큐 지연 30분, 나우캐스트)에서 한 가지씩 바꾸고, 마지막에 조합안을 봤어요. 모두 경사 45°, 천저 고정 대비 배수예요.</p>
{img('fig8_agility_sensitivity.png', '그림 8. 지향 민첩성·큐 지연·운용 정책에 따른 표적화 이득')}
<div class="tw"><table><tr><th>조건</th><th>전체 세포</th><th>호우급</th><th>프로파일</th><th>정량 프로파일</th><th>통과당 표적</th></tr>{rows_sens}</table></div>
<h3>여기서 나오는 요구사항</h3>
<div class="tw"><table><tr><th>항목</th><th>요구사항</th><th>근거</th></tr>
<tr><td>큐 지연</td><td>15분 이내, 목표 10분</td><td>30분 → 10분에서 호우급 {ks['gainHeavy'][iB]:.2f} → {ks['gainHeavy'][sidx('큐 지연 10분')]:.2f}배. 영향이 가장 큼</td></tr>
<tr><td>정착 시간</td><td>4초 이내, 목표 2초</td><td>8 → 4 → 2 s에서 세포 {ks['gainCells'][iB]:.2f} → {ks['gainCells'][sidx('정착 4 s')]:.2f} → {ks['gainCells'][sidx('정착 2 s')]:.2f}배. 전개 안테나의 진동 감쇠가 관건이라 자세제어 설계 과제가 됨</td></tr>
<tr><td>기동 속도</td><td>1°/s면 충분</td><td>2°/s로 올려도 세포 {ks['gainCells'][sidx('기동 2°/s')]:.2f}배로 거의 같음 → 요구를 낮출 수 있어 실현가능성에 유리</td></tr>
<tr><td>응시 시간</td><td>3초면 충분</td><td>6 → 3 s 차이 미미</td></tr>
<tr><td>정량 관측 각도</td><td>±3° 유지</td><td>±5°로 넓히면 호우급은 {ks['gainHeavy'][sidx('허용 ±5°')]:.2f}배로 늘지만 정량 프로파일이 {ks['gainQuant'][sidx('허용 ±5°')]:.2f}배로 줄어요(3~5°는 클러터로 정량 제외)</td></tr>
<tr><td>운용 정책</td><td>전체 겨냥 + 호우급 우선</td><td>호우급만 겨냥하면 다른 세포를 천저로 계속 보지만, 민첩해지면 전체 겨냥이 더 나아요</td></tr></table></div>
<div class="box"><b>제안서에 쓸 문장.</b> "정착 4초·큐 지연 10분 운용에서 호우급 세포 포착이 천저 고정 대비 {ks['gainHeavy'][iR10]:.1f}배, 강수 프로파일이 {ks['gainProf'][iR10]:.1f}배로 늘어난다(합성 강수 모델, 경사 45°). 이득은 큐 지연과 자세 정착 시간에 좌우되므로 두 값을 시스템 요구사항으로 정했다."</div>

<h2>모의 2: 감도 예산</h2>
<p>기준점은 RainCube 궤도 실측 11.0 dBZ(400 km)와 보수값 13 dBZ예요. 거리, PRF, 적분 시간, 대역, 안테나만 바뀐다고 보고 16개 가정 조합을 계산했어요.</p>
<div class="tw"><table><tr><th>항목</th><th>값</th></tr>
<tr><td>풋프린트 / 통과 시간</td><td>{f(s['fp'])} km / {f(s['Tfp'])} s</td></tr>
<tr><td>중심값 (기준 11.0, PRF 1.8 kHz, 0.5 m)</td><td>{f(s['central'], 1)} dBZ</td></tr>
<tr><td>0.5 m 범위 (13 dBZ 충족 비율)</td><td>{f(s['range05'][0], 1)} ~ {f(s['range05'][1], 1)} dBZ ({s['meet13_05'] * 100:.0f}%)</td></tr>
<tr><td>1 m 범위 (이득 차 {f(s['dG1m'], 1)} dB)</td><td>{f(s['range10'][0], 1)} ~ {f(s['range10'][1], 1)} dBZ ({s['meet13_10'] * 100:.0f}%)</td></tr></table></div>
<p class="mut">가장 큰 불확실성은 RainCube 실측값의 적분 시간과 처프 대역(2차 자료)이에요. 최악 조합도 13.0 dBZ라 목표선에 걸쳐요.</p>

<h2>모의 2: Ka 강우 감쇠와 관측 깊이</h2>
{img('fig5_attenuation.png', '그림 5. 감쇠 후 겉보기 반사도와 강우율별 왕복 감쇠')}
<div class="tw"><table><tr><th>강우율</th><th>비감쇠 [dB/km] P.838</th><th>rainpl (참고)</th><th>왕복 PIA [dB]</th><th>관측 가능 최저 고도 [km]</th></tr>{rows_rain}</table></div>
<p class="mut">MATLAB <code>rainpl</code>은 지상 링크용 경로길이 보정(ITU-R P.530)이 들어가 1 km 경로에서 약 1.5배 큰 값을 줘요. 연직 위성 경로에는 ITU-R P.838-3 계수를 직접 썼어요. 반사도는 Marshall-Palmer 관계라 Ka 비레일리 효과는 반영하지 않았어요.</p>

<h2>모의 3: PRF 타이밍</h2>
{img('fig6_prf_timing.png', '그림 6. PRF와 롤 오프셋에 따른 타이밍 가능 영역')}
<p>수신 창(고도 20 km ~ 지표 아래 3 km) 319 µs와 송신·보호 176 µs를 합치면 PRI가 최소 495 µs라 이론 최대 PRF는 {p['prfMax'] / 1e3:.2f} kHz예요. 고정 PRF로 롤 0~10° 전 구간에서 가능한 비율은 1.5 kHz {p['f15'] * 100:.0f}%, 1.8 kHz {p['f18'] * 100:.0f}%, 2.1 kHz {p['f21'] * 100:.0f}%예요. 각도에 따라 1.5~1.8 kHz 사이에서 PRF를 바꾸면 {p['band'] * 100:.0f}%예요.</p>

<h2>모의 3: 펄스압축 거리 부엽</h2>
{img('fig7_pulse_compression.png', '그림 7. 166 µs 선형 처프의 펄스압축 응답')}
<div class="tw"><table><tr><th>대역</th><th>창</th><th>−3 dB 해상도</th><th>첨두 부엽</th><th>1 km 밖 최대 부엽</th></tr>{rows_pc}</table></div>
<p>0.6 MHz는 창을 걸면 해상도가 320~360 m라 250 m 목표를 못 맞춰요. 그래서 1.2 MHz로 바꾼 게 맞아요. 다만 선형 처프와 창만으로는 해면 반사 대비 −60 dB 부엽을 못 만들어서, 비선형 처프(NLFM)나 부정합 필터 설계가 새 과제로 생겼어요. 그 설계 결과는 바로 아래 모의 3-b에 있어요.</p>

<h2>모의 3-b: 비선형 처프 설계와 거리 부엽 절충</h2>
<h3>비선형 처프(NLFM)란</h3>
<p>펄스 안에서 주파수를 일정한 속도로 훑는 선형 처프와 달리, 대역 가장자리 주파수는 빨리 지나가고 가운데 주파수에 오래 머물게 바꾸는 방식이에요. 그러면 송신 진폭을 일정하게 둔 채(포화 GaN 증폭기에 유리) 스펙트럼이 창 모양이 되어 부엽이 줄고, 수신 창을 쓸 때의 신호 손실이 없어요. 대신 도플러에 민감하다는 약점이 있어요.</p>
<h3>요구 부엽은 어떻게 정했나</h3>
<p>Ka 천저 해면 σ0를 10 dB로 두면, 해면 반사는 250 m 거리 구간에서 약 {kn['Zsurf']:.1f} dBZ 상당이에요. 해면 부엽이 감도선(약 9~10 dBZ) 아래로 내려가려면 1 km 밖 부엽이 약 −48~−50 dB여야 해요. 처음 잡았던 −60 dB는 과도한 기준이었어요. 감도가 좋아지는 구성(1 m 안테나)은 요구도 그만큼 엄격해져요.</p>
{img('fig9_nlfm.png', '그림 9. 선형·비선형 처프의 주파수 곡선과, 빔 안 도플러를 넣은 해면 응답(166 µs, 1 m)')}
{img('fig10_sidelobe_margin.png', '그림 10. 구성별 해면 부엽 여유(0 이상이면 해면 부엽이 감도선 아래)')}
<div class="tw"><table><tr><th>구성</th><th>설계</th><th>빔 평균 1 km 밖 부엽</th><th>요구</th><th>여유</th><th>오염 없는 고도</th><th>감도</th><th>신호 손실</th></tr>{rows_nlfm}</table></div>
<h3>결론</h3>
<ul>
<li><b>NLFM은 기각:</b> 0.5 m 안테나에서는 빔 안 도플러 퍼짐 때문에 빔 평균 부엽이 {kn['farBeam'][0][iNL]:.0f} dB까지 나빠져요. 1 m 안테나(도플러 절반)면 {kn['farBeam'][1][iNL]:.0f} dB로 회복되지만 여전히 요구에 못 미쳐요. 선형 처프는 도플러가 걸려도 봉우리가 옆으로 조금 밀릴 뿐 모양이 유지돼요.</li>
<li><b>채택안:</b> 선형 처프 + 가장자리 20% 테이퍼 + 최소제곱 부정합 필터. 166 µs·0.5 m에서 여유 {kn['margin'][0][iT]:+.1f} dB, 지표 위 {kn['cleanH'][0][iT]/1e3:.2f} km부터 오염 없음. 83 µs로 줄이면 여유 {kn['margin'][2][iT]:+.1f} dB·{kn['cleanH'][2][iT]/1e3:.2f} km로 좋아지지만 감도가 {kn['Zmin'][2][iT]:.1f} dBZ로 목표선(13 dBZ)을 살짝 넘어요.</li>
<li><b>과학 목표와 맞물림:</b> 지표 위 약 1 km는 강한 비에서 Ka 감쇠로도 안 보이는 구간(20 mm/h에서 0.95 km)이라, 상·중층 중심의 산출 목표와 충돌하지 않아요.</li>
<li><b>새 요구사항:</b> 송신 포락선 앞뒤 20%를 성형할 수 있는 증폭기 구동(에너지 손실 약 0.6 dB), 지상 처리에서 부정합 필터 적용(손실 약 1.5 dB).</li>
</ul>

<h2>가정과 한계</h2>
<ul>
<li>강수는 합성 세포 모델이에요(강수 비율 8%, 반경 중앙값 8 km, 수명 60분, 동북동 이동 약 9 m/s, 호우급 30%, warm형 60%). 실제 관측 자료가 아니에요.</li>
<li>궤도는 원궤도 J2 모델이고, 초기 위상 8개의 평균이에요.</li>
<li>지향은 롤만 썼고 피치 응시는 넣지 않았어요. 기동 1°/s, 정착 8 s, 응시 6 s, 응시 후 다음 기동까지 각도를 유지해요.</li>
<li>감도는 RainCube 기준 상대 스케일링이라 기준값의 적분 조건과 대역이 불확실해요.</li>
</ul>

<h2>다음 할 일</h2>
<ol>
<li>GPM IMERG 30분 실강수 자료(2023~2025 장마철)로 표적화 이득 다시 계산하기. 합성 모델보다 훨씬 설득력이 있어요.</li>
<li>자세 정착 4초가 전개 안테나 달린 16U에서 가능한지 Simulink 자세 모델로 확인하기(나중에 할 4번과 연결).</li>
<li>GaN 증폭기에서 펄스 가장자리 성형(상승·하강 시간)이 가능한지, 해면 σ0 가정(10 dB)을 바꾸면 요구 부엽이 어떻게 변하는지 확인하기.</li>
<li>큐 지연 단축 체계: 천리안 자료 처리 시간과 대전 지상국 S밴드 업링크 시점을 시간표로 정리하기.</li>
</ol>

<h2>실행 방법</h2>
<p><code>matlab</code> 폴더에서 <code>k_raineye_analysis</code>를 실행하면 <code>out</code> 폴더에 그림 10장, <code>summary.txt</code>, <code>key_results.json</code>, <code>results.mat</code>가 생겨요. 실행 시간은 약 1분 30초예요.</p>
<h3>MATLAB 원본 요약 출력</h3>
<pre>{html.escape(summ)}</pre>
</div></body></html>'''
open(os.path.join(d, 'K-RainEye_MATLAB_결과보고.html'), 'w', encoding='utf-8').write(H)
print('ok')
