%% 08_check.m - k_raineye_system.m 해설(08번) 5절 지적 확인용
% 저장된 결과 matlab/out/system_budget/key_system.json 을 읽어 식으로 다시 계산한다.
% 원 스크립트는 다시 돌리지 않는다. 그림 없음. 1초 안에 끝난다.
% PASS = 코드가 의도대로 동작함, FAIL = 지적이 맞음.
root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
jf = fullfile(root, 'matlab', 'out', 'system_budget', 'key_system.json');
if ~exist(jf, 'file'), error('결과 파일이 없음: %s', jf); end
fid = fopen(jf, 'r', 'n', 'UTF-8'); txt = fread(fid, '*char')'; fclose(fid);
K = jsondecode(txt);
P = K.params;
Re = 6378.137; mu = 398600.4418;            % k_raineye_analysis.m, dp/kre_lib.m 과 같은 상수 [km, km^3/s^2]
c0 = 299792458; kB = 1.380649e-23;
nPass = 0; nFail = 0;
fprintf('08_check: %s (실행 %s)\n', jf, K.time);

%% CHECK 1: 평평한 지구 근사 vs 구면 지구 (10°, 첫 영점 기준)
th = 10; lam = c0 / P.f; bNull = rad2deg(1.22 * lam / P.D);
r = Re + P.h;
slant = @(al) r * cosd(al) - sqrt(Re^2 - (r * sind(al)).^2);     % 지표까지 정확한 경사거리 [km]
Rn = slant(max(th - bNull, 0));                                   % 빔 안쪽 가장자리가 바다에 닿는 거리
zMLsph = sqrt(r^2 + Rn^2 - 2 * r * Rn * cosd(th)) - Re;           % 그 거리의 빔 중심선 점의 지표 위 높이
zCleanSph = zMLsph + P.zRS + P.res / 2e3;
zCleanFlat = K.offnadir.cleanFirstNullKm(end);                    % 코드 값 (th = 10°)
d1 = zCleanSph - zCleanFlat;
ok = abs(d1) <= 0.1;
[nPass, nFail] = report(1, ok, sprintf('10° 최저 고도 평면 %.2f km, 구면 %.2f km (차 %+.2f km); 0.1 km 넘으면 지적 맞음(결론 "약 3 km"는 유지)', zCleanFlat, zCleanSph, d1), nPass, nFail);

%% CHECK 2: 250 m 출력 구간 규약이 k_raineye_analysis.m 과 일치하는가 (nBins=100, Zsurf)
af = fullfile(root, 'matlab', 'k_raineye_analysis.m');
fid = fopen(af, 'r', 'n', 'UTF-8'); atxt = fread(fid, '*char')'; fclose(fid);
has250 = contains(atxt, 'dRb = 250');
bytes250 = 100 * 2 * 2 + 64;
nBinsAlt = round(25e3 / P.res); bytesAlt = nBinsAlt * 4 + 64;
l1DayAlt = K.data.profilesPerOrbit * bytesAlt / 1e6 * K.data.orbitsPerDay;
totAlt = l1DayAlt + K.data.diagPerDayMB + K.data.hkPerDayMB;
needDRAlt = K.dynamicRange.needDR_dB + 10 * log10(250 / P.res);
bitsAlt = ceil((needDRAlt - 1.76) / 6.02);
ok = has250 && K.data.bytesPerProfile == bytes250 && bitsAlt == K.dynamicRange.needBits;
[nPass, nFail] = report(2, ok, sprintf('analysis.m에 dRb = 250 %s, 프로파일 %d B; 175 m 구간이면 %d B, 하루 %.1f→%.1f MB, 필요 비트 %d→%d (결론 불변)', ...
    tf(has250, '있음', '없음'), K.data.bytesPerProfile, bytesAlt, K.data.dataPerDayMB, totAlt, K.dynamicRange.needBits, bitsAlt), nPass, nFail);

%% CHECK 3: 궤도 상수 (km 단위 μ로 다시 계산한 주기·하루 궤도 수·최대 일식)
Tmin = 2 * pi * sqrt(r^3 / mu) / 60;
opd = 1440 / Tmin;
rho = asind(Re / r); ecl = Tmin * 2 * rho / 360;
e3 = max([abs(Tmin - K.power.orbitMin) / K.power.orbitMin, abs(opd - K.data.orbitsPerDay) / K.data.orbitsPerDay, ...
          abs(ecl - K.power.eclipseMaxMin) / K.power.eclipseMaxMin]);
ok = e3 < 1e-6;
[nPass, nFail] = report(3, ok, sprintf('주기 %.3f분, 하루 %.3f궤도, 최대 일식 %.2f분 (상대 오차 %.1e)', Tmin, opd, ecl, e3), nPass, nFail);

%% CHECK 4: satellite() 반장축 단위(m) - 결과의 최소 거리가 고도와 맞는가, 최대 거리 식
rangeMax = sqrt(r^2 - (Re * cosd(K.link.elMin))^2) - Re * sind(K.link.elMin);
ok = abs(K.access.minRangeKm - P.h) < 20 && abs(rangeMax - K.link.rangeMax) < 1e-6;
[nPass, nFail] = report(4, ok, sprintf('최소 거리 %.1f km (고도 %d km), 앙각 %d° 최대 거리 %.1f km', K.access.minRangeKm, P.h, K.link.elMin, rangeMax), nPass, nFail);

%% CHECK 5: 태양전지판 가정 - 몸체 부착 4면이면 생산이 소요(마진 포함)를 넘는가
pv = K.power.pv; pw = K.power.items;
oaCode = pv.EOL * K.power.sunFrac * pv.cosf;                       % 코드 식 재현
A1 = 0.226 * 0.454;                                                % 긴 면 하나 [m^2]
effBody = A1 * 4 / pi;                                             % 4면 부착, 태양이 긴 축에 수직일 때 궤도 평균 유효 넓이
oaBody = pv.EOL / pv.area * effBody * K.power.sunFrac;
ok = abs(oaCode - pv.oa) < 1e-6 && oaBody >= pw.totalMargin;
[nPass, nFail] = report(5, ok, sprintf('코드(전개형, 계수 0.5) 생산 %.1f W; 몸체 부착 4면이면 %.1f W vs 소요 %.1f W → 부족하면 지적 맞음(전개형 가정 명시 필요)', pv.oa, oaBody, pw.totalMargin), nPass, nFail);

%% CHECK 6: 최악 일식 방전에 S밴드 송신이 들어 있는가
bat = K.power.battery;
eclNoSb = pw.busW * K.power.eclipseMaxMin / 60 + pw.radarW * P.radarMinPerOrbit / 60 + pw.adcsAvg * K.power.eclipseMaxMin / 60;
eclSb = eclNoSb + pw.sbandW * pw.sbandMinPerPass / 60;
ok = abs(bat.eclWh - eclSb) < 1e-3;
[nPass, nFail] = report(6, ok, sprintf('코드 %.2f Wh (S밴드 없음 %.2f, 포함 %.2f) → 방전심도 %.1f%% vs %.1f%% (기준 30%% 안, 결론 불변)', bat.eclWh, eclNoSb, eclSb, 100 * bat.DoD, 100 * eclSb / bat.Wh), nPass, nFail);

%% CHECK 7: 링크 버짓 단위와 상향 이득 보정 방향
L = K.link;
fspl = @(f, Rkm) 20 * log10(4 * pi * Rkm * 1e3 * f / c0);
EIRP = 10 * log10(L.dn.PtW) - L.dn.lineLoss + L.dn.Gtx;
G = 10 * log10(L.gs.eta * (pi * L.gs.D * L.fDn / c0)^2);
GT = G - 10 * log10(L.gs.Tsys);
CN0 = EIRP - fspl(L.fDn, L.rangeMax) - L.dn.otherLoss + GT - 10 * log10(kB);
margin = CN0 - 10 * log10(L.dn.Rb) - L.dn.req - L.dn.implLoss;
GtxUp = G - 20 * log10(L.fDn / L.fUp);
e7 = max(abs([EIRP - L.dn.EIRP, G - L.gs.G, CN0 - L.dn.CN0, margin - L.dn.margin, GtxUp - L.up.Gtx]));
ok = e7 < 1e-6 && L.up.Gtx < L.gs.G && L.dn.margin > 0;
[nPass, nFail] = report(7, ok, sprintf('EIRP %.2f dBW, G/T %.2f dB/K, C/N0 %.2f dBHz, 하향 여유 %.2f dB, 상향 접시 이득 %.2f < %.2f dBi (최대 오차 %.1e)', EIRP, GT, CN0, margin, GtxUp, G, e7), nPass, nFail);

%% CHECK 8: 합계 = 항목 합, 마진 ×1.2, bit→MB 환산
m = K.mass; d = K.data; la = K.latency; dr = K.dynamicRange;
chk = [abs(sum(m.kg) - m.sum), abs(m.sum * 1.2 - m.withMargin), ...
       abs(pw.busW + pw.radarAvg + pw.adcsAvg + pw.sbandAvg - pw.total), abs(pw.total * 1.2 - pw.totalMargin), ...
       abs(pv.oa / pw.totalMargin - pw.ratio), abs(pw.radarW * P.radarMinPerOrbit / K.power.orbitMin - pw.radarAvg), ...
       abs(sum(la.minutes) - la.total), abs(la.req - la.total - la.margin), ...
       abs(L.dn.Rb * K.access.meanPassMin * 60 / 8 / 1e6 - K.access.dataPerMeanPassMB), ...
       abs(L.dn.Rb * K.access.contactMinPerDay * 60 / 8 / 1e6 - d.downlinkCapPerDayMB), ...
       abs(d.profilesPerOrbit * d.bytesPerProfile / 1e6 - d.L1perOrbitMB), ...
       abs(d.L1perDayMB + d.diagPerDayMB + d.hkPerDayMB - d.dataPerDayMB), ...
       abs(dr.surfSNRpre_dB + dr.calmSeaMargin_dB + dr.crest_dB + dr.noiseLSB_dB - dr.needDR_dB), ...
       abs(dr.adcDR_dB - dr.needDR_dB - dr.adcMargin_dB)];
ok = max(chk) < 1e-6;
[nPass, nFail] = report(8, ok, sprintf('질량 %.1f/%.1f kg, 전력 %.2f/%.2f W, 지연 %d/%d분, 자료 %.1f MB/통과, %.1f MB/일 (14개 식 최대 오차 %.1e)', ...
    m.sum, m.withMargin, pw.total, pw.totalMargin, la.total, la.margin, K.access.dataPerMeanPassMB, d.downlinkCapPerDayMB, max(chk)), nPass, nFail);

fprintf('08_check 끝: PASS %d, FAIL %d (FAIL = 해설 5절 지적이 맞음)\n', nPass, nFail);

function [nPass, nFail] = report(n, ok, msg, nPass, nFail)
if ok, s = 'PASS'; nPass = nPass + 1; else, s = 'FAIL'; nFail = nFail + 1; end
fprintf('CHECK %d: %s - %s\n', n, s, msg);
end

function s = tf(ok, a, b)
if ok, s = a; else, s = b; end
end
