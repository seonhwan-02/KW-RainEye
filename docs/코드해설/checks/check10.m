%% 10_check.m — 10번 해설(matlab/k_raineye_sens_pcloss.m)의 코드 검토 지적을 확인하는 스크립트
% 실행: MATLAB에서 이 파일을 그냥 실행 (그림 없음, 몇 초 안에 끝남)
% 출력: 지적마다 한 줄  CHECK n: PASS/FAIL - 설명
%   PASS = 코드가 의도대로 동작함(지적은 오해 또는 영향 없음), FAIL = 지적이 맞음
% 원 스크립트는 다시 돌리지 않는다(run_log.csv에 줄이 추가되므로).
% 대신 식을 여기서 독립적으로 다시 써서 저장된 결과 matlab/out/sens_pcloss/key_sens_pcloss.json 과 비교한다.

root    = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
mdir    = fullfile(root, 'matlab');
outDir  = fullfile(mdir, 'out', 'sens_pcloss');
srcFile = fullfile(mdir, 'k_raineye_sens_pcloss.m');

J   = jsondecode(readU8(fullfile(outDir, 'key_sens_pcloss.json')));   % 이 스크립트가 남긴 결과
K   = jsondecode(readU8(fullfile(mdir, 'out', 'key_nlfm.json')));      % 채택 파형 손실의 출처 (09번 14절)
txt = readU8(srcFile);
iDes = find(abs(K.loss(1, :) - J.lossPC) < 1e-9, 1);                   % 채택안 열 (손실 값으로 찾음, 문자 비교 안 함)
iNoL = find(abs(K.loss(1, :)) < 1e-9, 1);                              % 손실 0인 설계 열 (NLFM + 정합 필터)
near = @(a, b, tol) numel(a) == numel(b) && all(abs(a(:) - b(:)) < tol);

%% ---- 식을 독립적으로 다시 쓴다 (원 코드의 변수 이름을 쓰지 않음) ----
Re = 6378.137;  mu = 398600.4418;  hSat = 550;  hRef = 400;
lam  = 299792458 / 35.75e9;
vg   = @(h) Re * sqrt(mu / (Re + h)^3);                                % 지상 궤적 속도 [km/s]
Tpass = 2 * hSat * tand(1.13 / 2) / vg(hSat);                          % 550 km에서 풋프린트 통과 시간 [s]
Tref  = [0.28, 7.9 / vg(hRef)];                                        % 기준 적분시간 두 가지 [s]
PRFref = 1 / 1660e-6;  Bref = 2.5e6;  Bnew = 1.2e6;
dGant = [0, 2 * (49.2 - 42.6) + 20 * log10((70 * lam / 1.0) / 1.13)];  % 1 m 안테나 이득 변화 [dB]
[ZR, TR, PF, UB, IA] = ndgrid([11 13], Tref, [1500 1800], [1 0], 1:2); % 2×2×2×2×2 = 32가지
Zmin = ZR + 20 * log10(hSat / hRef) - 5 * log10(PF / PRFref) - 5 * log10(Tpass ./ TR) ...
       - dGant(IA) + UB .* (5 * log10(Bnew / Bref));
my05 = Zmin(IA == 1) + J.lossPC;   my10 = Zmin(IA == 2) + J.lossPC;
myZc = Zmin(ZR == 11 & abs(TR - Tref(2)) < 1e-12 & PF == 1800 & UB == 1 & IA == 1);

%% CHECK 1: 감도 식이 09번(k_raineye_analysis.m 8절)과 같은가 — 독립 재계산 vs 저장된 json
e1 = [abs(myZc - J.Zcentral), abs([min(my05) max(my05)] - J.range05(:)'), abs([min(my10) max(my10)] - J.range10(:)')];
ok1 = all(e1 < 1e-6) && nnz(my05 <= 13) == J.n13_05 && abs(mean(my05 <= 13) - J.meet13_05) < 1e-12;
say(1, ok1, sprintf('독립 재계산: 중심 %.4f, 0.5 m %.2f~%.2f, 1 m %.2f~%.2f dBZ, 13 이하 %d/16 — json과 최대 차 %.1e dB', ...
    myZc, min(my05), max(my05), min(my10), max(my10), nnz(my05 <= 13), max(e1)));

%% CHECK 2: 중심 조합 판별(isCentral, 줄 46)이 32행 중 정확히 한 행만 고르나 — 원 코드와 같은 조건을 그대로 적용
sens = [ZR(:), TR(:), PF(:), UB(:), IA(:), Zmin(:)];
isC  = sens(:, 1) == 11 & abs(sens(:, 2) - Tref(2)) < 1e-9 & sens(:, 3) == 1800 & sens(:, 4) == 1 & sens(:, 5) == 1;
ok2  = nnz(isC) == 1 && near(sens(isC, 6), J.Zcentral, 1e-9);
say(2, ok2, sprintf('isCentral 참인 행 %d개 (1개여야 함), 그 행의 감도 %.4f dBZ = json Zcentral %.4f', nnz(isC), sum(sens(isC, 6)), J.Zcentral));

%% CHECK 3: assert 허용 오차 0.05 dB — 실제 차이는 얼마인가, 1e-6으로 좁혀도 통과하나
d3  = abs(J.Zcentral + J.lossPC - J.Zadopt);
ok3 = d3 < 1e-6 && near(K.Zmin(1, iDes), J.Zadopt, 1e-9) && near(K.Zmin(1, iNoL), J.Zcentral, 1e-9);
say(3, ok3, sprintf('|중심값 + 손실 - 채택 감도| = %.1e dB (코드 허용 0.05 dB, 1e-6으로 좁혀도 통과). key_nlfm Zmin(1,%d)=%.4f=채택, Zmin(1,%d)=%.4f=중심', ...
    d3, iDes, K.Zmin(1, iDes), iNoL, K.Zmin(1, iNoL)));

%% CHECK 4: 1 m 안테나 조합에도 같은 lossPC(0.5 m 설정의 손실)를 더하는 것이 맞나 — key_nlfm의 1 m 설정 손실과 감도로 확인
loss1m = K.loss(2, iDes);                      % 설정 2 = 166 µs · 1 m
z1mCentral = J.Zcentral - dGant(2) + J.lossPC; % 1 m 중심 조합(손실 포함)을 손으로 계산
ok4 = near(loss1m, J.lossPC, 1e-9) && near(K.Zmin(2, iDes), z1mCentral, 1e-6);
say(4, ok4, sprintf('key_nlfm 손실 0.5 m %.4f / 1 m %.4f dB (같음), 1 m 중심 조합 %.2f dBZ = key_nlfm Zmin(2,%d) %.2f', ...
    J.lossPC, loss1m, z1mCentral, iDes, K.Zmin(2, iDes)));

%% CHECK 5: 감쇠 높이 firstVis — 독립 구현과 일치하나, 격자(0.05 km) 때문에 정확한 교차 높이보다 얼마나 위로 나오나, 경계(모두 안 보임→Hr)
kR = 0.3452;  aR = 0.8851;  Rr = [5 10 20 30 50];  Hr = 4.5;  hg = (0:0.05:Hr)';
gam = kR * Rr.^aR;  Ztrue = 10 * log10(200 * Rr.^1.6);
myLow = zeros(size(Rr));  hidden = zeros(size(Rr));
hExact = max(0, Hr - (Ztrue - J.Zadopt) ./ (2 * gam));                 % 식으로 푼 교차 높이 (음수면 땅까지 보임 → 0)
for k = 1:numel(Rr)
    Zm = Ztrue(k) - 2 * gam(k) * (Hr - hg);
    myLow(k)  = myFirstVis(Zm, J.Zadopt, hg, Hr);
    hidden(k) = myFirstVis(Zm, 1000, hg, Hr);                          % 감도 1000 dBZ면 아무 높이도 안 보임 → Hr이 나와야 함
end
ok5 = near(myLow, J.lowestAtAdopt, 1e-9) && all(myLow >= hExact - 1e-9) && all(myLow - hExact <= 0.05 + 1e-9) ...
      && all(hidden == Hr) && all(Ztrue > J.Zadopt);
say(5, ok5, sprintf('독립 구현 = json %s km. 정확한 교차 높이 20 mm/h %.3f→격자 %.2f, 30 mm/h %.3f→%.2f (격자가 최대 0.05 km 위, 보수적). 모든 Ztrue(%.0f~%.0f dBZ) > 감도라 "Hr 반환" 경계는 안 걸림, 걸리면 %g 반환', ...
    mat2str(myLow), hExact(3), myLow(3), hExact(4), myLow(4), min(Ztrue), max(Ztrue), hidden(1)));

%% CHECK 6: json 값과 summary.txt 문장이 같은 숫자인가 (0.5 m 범위·13 이하 개수, 1 m 범위·개수, 감쇠 높이)
S = readU8(fullfile(outDir, 'summary.txt'));
t05 = str2double(regexp(S, '0\.5 m[^\n]*?([\d.]+) ~ ([\d.]+) dBZ[^\n]*?(\d+)/(\d+)', 'tokens', 'once'));
t10 = str2double(regexp(S, '\n1 m[^\n]*?([\d.]+) ~ ([\d.]+) dBZ[^\n]*?(\d+)/(\d+)', 'tokens', 'once'));
tLo = regexp(S, '\[([\d. ]+)\] \| [^\[]*\[([\d. ]+)\]', 'tokens', 'once');
lo90 = str2num(['[' tLo{1} ']']);  loAd = str2num(['[' tLo{2} ']']); %#ok<ST2NM>
ok6 = near(t05, [round(J.range05(:)', 1), J.n13_05, 16], 1e-9) && near(t10, [round(J.range10(:)', 1), nnz(my10 <= 13), 16], 1e-9) ...
      && near(lo90, round(J.lowestAt90, 2), 1e-9) && near(loAd, round(J.lowestAtAdopt, 2), 1e-9);
say(6, ok6, sprintf('summary: 0.5 m %.1f~%.1f (%d/%d), 1 m %.1f~%.1f (%d/%d), 높이 %s | %s — json과 일치 %d', ...
    t05, t10, mat2str(lo90), mat2str(loAd), ok6));

%% CHECK 7: json에 1 m 안테나의 "13 dBZ 이하 개수"가 있나 (개선 제안: summary에는 있는데 json에는 range10만 있음, FAIL = 지적이 맞음)
ok7 = isfield(J, 'n13_10') || isfield(J, 'meet13_10');
say(7, ok7, sprintf('json 키: %s — 1 m 개수 키(n13_10/meet13_10) 있음 %d (summary.txt에는 "%d/%d개"로 적혀 있음)', ...
    strjoin(fieldnames(J)', ', '), ok7, t10(3), t10(4)));

%% CHECK 8: run_log.csv 기록 — 네 칸(time,script,outDir,note) 형식이고 note의 숫자가 json과 같은가
logFile = fullfile(mdir, 'out', 'run_log.csv');
rows = regexp(readU8(logFile), '[^\n]*,k_raineye_sens_pcloss,[^\n]*', 'match');
ok8 = false;  msg8 = 'run_log.csv에 k_raineye_sens_pcloss 행이 없음';
if ~isempty(rows)
    r = strtrim(rows{end});
    fmtOk = ~isempty(regexp(r, '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2},k_raineye_sens_pcloss,[^,]+,".*"$', 'once'));
    n = str2double(regexp(r, '([\d.]+) dBZ, 0\.5m.*?([\d.]+)~([\d.]+) dBZ.*?(\d+)/16.*?([\d.]+)/([\d.]+) km', 'tokens', 'once'));
    want = [round(J.Zadopt, 1), round(J.range05(:)', 1), J.n13_05, round(J.lowestAtAdopt(J.R == 20), 2), round(J.lowestAtAdopt(J.R == 30), 2)];
    ok8 = fmtOk && near(n, want, 1e-9);
    msg8 = sprintf('행 %d개, 마지막 행 형식 OK %d, note 숫자 %s = json %s', numel(rows), fmtOk, mat2str(n), mat2str(want));
end
say(8, ok8, msg8);

%% CHECK 9: 머리 주석의 절 번호 — 22줄에 "7절과 같은 식"이라 적었는데 k_raineye_analysis.m에서 감도 예산은 몇 절인가 (개선 제안, FAIL = 지적이 맞음)
A = readU8(fullfile(mdir, 'k_raineye_analysis.m'));
secSens = regexp(A, '%% (\d+)\. [^\n]*감도 예산', 'tokens', 'once');
secAtt  = regexp(A, '%% (\d+)\. [^\n]*감쇠', 'tokens', 'once');
if isempty(secSens), secSens = {'?'}; end
if isempty(secAtt),  secAtt  = {'?'}; end
cmt7 = ~isempty(regexp(txt, '7절과 같은 식', 'once'));
ok9 = ~cmt7 || strcmp(secSens{1}, '7');
say(9, ok9, sprintf('k_raineye_analysis.m 감도 예산 = %s절, 감쇠 = %s절; 이 파일 22줄 주석은 "7절" (%d)', ...
    secSens{1}, secAtt{1}, cmt7));

%% ---------- 도우미 ----------
function say(n, ok, msg)
if ok, s = 'PASS'; else, s = 'FAIL'; end
fprintf('CHECK %d: %s - %s\n', n, s, msg);
end

function h = myFirstVis(Zm, Zth, hg, Hr)
% 원 코드의 firstVis를 같은 뜻으로 다시 쓴 것: 감도 이상인 가장 낮은 격자 높이, 하나도 없으면 Hr
i1 = find(Zm >= Zth, 1);
if isempty(i1), h = Hr; else, h = hg(i1); end
end

function s = readU8(p)
% UTF-8로 저장된 텍스트 파일을 MATLAB 기본 인코딩과 상관없이 읽는다
fid = fopen(p, 'r', 'n', 'UTF-8');
assert(fid > 0, '파일을 열 수 없음: %s', p);
s = fread(fid, '*char')';
fclose(fid);
s = strrep(s, char(13), '');   % CRLF → LF
end
