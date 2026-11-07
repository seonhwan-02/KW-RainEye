function L = kre_lib()
% K-RainEye 지향 계획 공용 함수 모음
%   L = kre_lib();  처럼 불러서  L.loadSeason(2023), L.dpPlan(...) 식으로 쓴다.
%   (MATLAB은 파일 하나에 공개 함수가 하나뿐이라, 안쪽 함수들의 핸들을 구조체에 담아 돌려준다.)
L.params       = @defaultParams;   % 기본 매개변수
L.loadSeason   = @loadSeason;      % IMERG 한 시즌(6~9월) 읽기 + 이동 벡터 ('final' 또는 'early')
L.attachCue    = @attachCue;       % 큐 장면만 다른 자료(IMERG Early)에서 가져오게 붙이기
L.cueAgreement = @cueAgreement;    % 큐 자료(Early)가 진실(Final)의 비를 얼마나 맞히나
L.orbitPasses  = @orbitPasses;     % 궤도 전파 → 관측창 통과 목록
L.heavyInSwath = @heavyInSwath;    % 통과 중 ±10° 안에 호우 칸이 있던 표본 수
L.calibrate    = @calibrate;       % 학습: 큐 강도 → 30분 뒤 실제 호우 확률 표
L.rewardGrid   = @rewardGrid;      % (시각 × 빔각) 보상 표
L.dpPlan       = @dpPlan;          % 동적계획법으로 최적 빔 경로
L.greedyPlan   = @greedyPlan;      % 기존 방식: 점 표적을 하나씩 찍는 스케줄러 (비교용)
L.evaluate     = @evaluate;        % 빔 경로를 실제 강수(IMERG)로 채점
L.sampleField  = @sampleField;     % 위경도 → IMERG 칸 값
end

%% ===================== 매개변수 =====================
function P = defaultParams()
P.C = struct('Re', 6378.137, 'mu', 398600.4418, 'J2', 1.08262668e-3, 'we', 7.2921159e-5);
P.h        = 550;                 % 고도 [km]
P.inc      = 45;                  % 경사 [deg]
P.dt       = 10;                  % 궤도 표본 간격 [s]
P.nPhase   = 8;                   % 초기 궤도 위상 개수 (결과는 평균)
P.profDt   = 1.5;                 % 관측 표본 간격 = 풋프린트 길이 통과 시간 [s]
P.winLat   = [28.5 39.5];         % 관측창 (서해~동해)
P.winLon   = [119.5 131.5];
P.maxDeg   = 10;                  % 지향 범위 ±[deg]
P.stepDeg  = 1;                   % 빔각 격자 간격 [deg]
P.slewRate = 1.5;                 % 기동 속도 [deg/s]
P.settle   = 4;                   % 정착 시간 [s]
P.dwell    = 3;                   % 기존 스케줄러의 표적당 응시 [s]
P.prePoint = 120;                 % 관측창 진입 전 미리 기울일 수 있는 시간 [s]
P.thrRain  = 1;                   % 강수 [mm/h]
P.thrHeavy = 10;                  % 호우 [mm/h]
P.cueL     = 15;                  % 큐 지연 [min]
P.pDet     = 0.72;                % 큐가 호우 핵을 제 강도로 알아볼 확률 (못 알아보면 약하게 보임)
P.weakFac  = [0.2 0.5];           % 못 알아본 호우 핵은 실제 강도의 이 배수(무작위)로 약하게 보인다
P.edges    = [0 0.5 1 2 3 5 7 10 15 20 30 inf];   % 학습 표의 큐 강도 구간 [mm/h]
P.lags     = [1 2];               % 큐 장면이 관측보다 몇 칸(30분) 앞서는가 (큐 지연 15분이면 1~2칸)
P.posSd    = 3;                   % 큐 위치오차 [km]
P.velSd    = 2 / 1000;            % 이동 속도 오차 [km/s]
P.alpha    = 0.05;                % 보상에서 '약한 비'의 가중 (호우 = 1)
P.greedyThr = 10;                 % 기존 방식이 표적으로 삼는 큐 강도 하한 [mm/h] (약한 비까지 겨냥하면 손해라 호우만)
P.blur     = 0;                   % 예측장을 흐리는 반경 [칸] (0이면 안 흐림)
end

%% ===================== 자료 =====================
function D = loadSeason(year, src)
% 바탕화면\K-RainEye_IMERG\YYYY06~09 의 nc4를 읽는다. 처음 한 번은 몇 분 걸리고 캐시를 만든다.
%   src = 'final' (기본, 약 3.5개월 뒤 나오는 정밀판: 앞뒤 시간 자료 + 우량계 보정)
%         'early' (약 4시간 뒤 나오는 빠른판: 그 시각까지의 자료만, 월별 우량계 보정 대신 기후 평균 보정만) → K-RainEye_IMERG\early\YYYYMM
if nargin < 2, src = 'final'; end
src = validatestring(src, {'final', 'early'});
root  = fullfile(getenv('USERPROFILE'), 'Desktop', 'K-RainEye_IMERG');
if strcmp(src, 'early'), dataDir = fullfile(root, 'early');  tag = 'early_';
else,                    dataDir = root;                     tag = '';  end
months = arrayfun(@(m) sprintf('%d%02d', year, m), 6:9, 'UniformOutput', false);
cache = fullfile(root, sprintf('cache_%s%d_JJAS.mat', tag, year));
if exist(cache, 'file')
    S = load(cache);
    Pr = S.Pr; lat = S.lat; lon = S.lon; tSlot = S.tSlot;
else
    fprintf('%d년 %s nc4를 처음 읽습니다 (몇 분 걸림)...\n', year, src);
    Pr = []; lat = []; lon = []; tSlot = NaT(0, 1, 'TimeZone', 'UTC');
    for m = months
        d = dir(fullfile(dataDir, m{1}, '*.nc4'));
        key = regexp({d.name}, '\.(\d{8})-S(\d{6})', 'tokens', 'once');
        key = cellfun(@(c) [c{1} c{2}], key, 'UniformOutput', false);
        [~, ord] = unique(key);                  % 같은 시각이 두 번 받아졌으면 하나만
        d = d(ord);
        if isempty(lat)
            f1 = fullfile(d(1).folder, d(1).name);
            lat = double(ncread(f1, '/Grid/lat'));  lon = double(ncread(f1, '/Grid/lon'));
        end
        Pm = zeros(numel(lat), numel(lon), numel(d), 'single');
        tm = NaT(numel(d), 1, 'TimeZone', 'UTC');
        for k = 1:numel(d)
            f = fullfile(d(k).folder, d(k).name);
            Pm(:, :, k) = ncread(f, '/Grid/precipitation');
            tm(k) = datetime(1980, 1, 6, 'TimeZone', 'UTC') + seconds(double(ncread(f, '/Grid/time')));
        end
        Pr = cat(3, Pr, Pm);  tSlot = [tSlot; tm]; %#ok<AGROW>
    end
    Pr(isnan(Pr) | Pr < 0) = 0;
    save(cache, 'Pr', 'lat', 'lon', 'tSlot', 'months', '-v7.3');
end
D.Pr = Pr;  D.lat = lat;  D.lon = lon;  D.tSlot = tSlot;  D.nT = size(Pr, 3);
D.t0 = datetime(year, 6, 1, 'TimeZone', 'UTC');
D.year = year;
D.src = src;
D.kmLat = 110.57 * 0.1;
D.kmLon = 111.32 * 0.1 * cosd(mean(lat));
assert(all(diff(seconds(tSlot - D.t0)) == 1800), '30분 간격이 끊긴 곳이 있다');

% 나우캐스트용 이동 벡터: 30분 전 장면과 지금 장면을 겹쳐 가장 잘 맞는 이동량
mfile = fullfile(root, sprintf('motion_%s%d_JJAS.mat', tag, year));
if exist(mfile, 'file')
    S = load(mfile);  mv = S.motion;
else
    fprintf('%d년 %s 이동 벡터 계산 (1~2분)...\n', year, src);
    mv = nan(D.nT, 2);
    for k = 2:D.nT
        mv(k, :) = estMotion(Pr(:, :, k - 1), Pr(:, :, k), 6, D.kmLat, D.kmLon);
    end
    motion = mv;  kmLat = D.kmLat;  kmLon = D.kmLon; %#ok<NASGU>
    save(mfile, 'motion', 'kmLat', 'kmLon');
end
mv(isnan(mv)) = 0;
D.motion = mv;                                   % [동, 북] [km/s]
end

function D = attachCue(D, Dc)
% 큐(어디를 볼지 고르는 장면)는 Dc에서, 채점(실제로 본 비)은 D에서 쓰게 만든다.
%   예: D = Final(진실), Dc = Early(운용 때 쓸 수 있는 거친 자료)
%   큐 장면을 쓰는 곳(cueScene → rewardGrid, greedyPlan, calibrate)만 바뀌고, 채점·상한은 D.Pr 그대로다.
assert(isequal(size(D.Pr), size(Dc.Pr)), '두 자료의 크기가 다르다');
assert(max(abs(D.lat - Dc.lat)) < 1e-6 && max(abs(D.lon - Dc.lon)) < 1e-6, '두 자료의 격자가 다르다');
assert(all(D.tSlot == Dc.tSlot), '두 자료의 시각이 다르다');
assert(~strcmp(D.src, Dc.src), '큐와 진실이 같은 자료다');
D.cuePr     = Dc.Pr;
D.cueMotion = Dc.motion;                         % 이동 벡터도 큐 자료로 다시 구한 것 (운용과 같게)
D.cueSrc    = Dc.src;
end

function A = cueAgreement(Df, Dc, P)
% 같은 시각·같은 칸에서 큐 자료(Dc)가 진실(Df)을 얼마나 맞히나
%   pod = 진실의 호우(강수) 칸 중 큐도 호우(강수)로 본 비율, far = 큐가 호우라 했는데 아니었던 비율
%   coreDet = 진실의 호우 핵(이어진 덩어리) 중 큐가 그 안 어딘가를 호우로 본 비율
%   coreDetModel = 3단계의 가짜 큐 오차(pDet, weakFac)를 같은 기준으로 잰 값 (못 알아본 핵도 최대값 × 0.2~0.5가
%                  10 mm/h 이상이면 '본 것'이 되므로 P.pDet보다 조금 크다. P.blur = 0일 때 성립)
%   bias = 큐 강수량 합 / 진실 강수량 합
hh = 0; hm = 0; hf = 0; rh = 0; rm = 0; rf = 0; sF = 0; sC = 0; nCore = 0; nDet = 0; sModel = 0;
for k = 1:Df.nT
    F = Df.Pr(:, :, k);  C = Dc.Pr(:, :, k);
    hF = F >= P.thrHeavy;  hC = C >= P.thrHeavy;
    rF = F >= P.thrRain;   rC = C >= P.thrRain;
    hh = hh + nnz(hF & hC);  hm = hm + nnz(hF & ~hC);  hf = hf + nnz(~hF & hC);
    rh = rh + nnz(rF & rC);  rm = rm + nnz(rF & ~rC);  rf = rf + nnz(~rF & rC);
    sF = sF + sum(F, 'all', 'double');  sC = sC + sum(C, 'all', 'double');
    if any(hF(:))
        Lb = labelMask(hF);
        mx = accumarray(Lb(hF), double(C(hF)), [], @max);
        nCore = nCore + numel(mx);  nDet = nDet + nnz(mx >= P.thrHeavy);
        pk = accumarray(Lb(hF), double(F(hF)), [], @max);          % 진실 핵의 최대 강도
        pMiss = min(max((P.weakFac(2) - P.thrHeavy ./ pk) / diff(P.weakFac), 0), 1);
        sModel = sModel + sum(P.pDet + (1 - P.pDet) * pMiss);
    end
end
A.podHeavy = hh / (hh + hm);  A.farHeavy = hf / max(hh + hf, 1);  A.csiHeavy = hh / (hh + hm + hf);
A.podRain  = rh / (rh + rm);  A.farRain  = rf / max(rh + rf, 1);  A.csiRain  = rh / (rh + rm + rf);
A.coreDet  = nDet / max(nCore, 1);  A.nCore = nCore;  A.coreDetModel = sModel / max(nCore, 1);
A.bias     = sC / sF;
end

function v = estMotion(A, B, maxS, kmLat, kmLon)
A = log1p(double(A));  B = log1p(double(B));
if nnz(A > log1p(1)) < 30 || nnz(B > log1p(1)) < 30, v = [NaN NaN]; return; end
[n1, n2] = size(A);
Sc = -inf(2 * maxS + 1);
for di = -maxS:maxS
    for dj = -maxS:maxS
        ia = max(1, 1 - di):min(n1, n1 - di);
        ja = max(1, 1 - dj):min(n2, n2 - dj);
        a = A(ia, ja);  b = B(ia + di, ja + dj);
        Sc(di + maxS + 1, dj + maxS + 1) = sum(a .* b, 'all') / sqrt(sum(a.^2, 'all') * sum(b.^2, 'all') + eps);
    end
end
[~, m] = max(Sc(:));
[r, c] = ind2sub(size(Sc), m);
dr = 0; dc = 0;
if r > 1 && r < size(Sc, 1), dr = parab(Sc(r - 1, c), Sc(r, c), Sc(r + 1, c)); end
if c > 1 && c < size(Sc, 2), dc = parab(Sc(r, c - 1), Sc(r, c), Sc(r, c + 1)); end
v = [(c - maxS - 1 + dc) * kmLon, (r - maxS - 1 + dr) * kmLat] / 1800;
end

function d = parab(ym, y0, yp)
den = ym - 2 * y0 + yp;
if den >= 0, d = 0; else, d = 0.5 * (ym - yp) / den; end
end

%% ===================== 궤도와 통과 =====================
function [passes, phases] = orbitPasses(D, P, ip)
% 궤도 위상 ip로 시즌 전체를 전파하고, 관측창 안에 있는 구간(통과)마다 관측 기하를 만든다
phs = RandStream('mt19937ar', 'Seed', 7);
phases = [rand(phs, P.nPhase, 1), rand(phs, P.nPhase, 1)] * 2 * pi;
jd0   = juliandate(D.t0);
gmst0 = deg2rad(mod(280.46061837 + 360.98564736629 * (jd0 - 2451545), 360));
[t, la, lo] = propagate(P.C, P.h, P.inc, phases(ip, 1), phases(ip, 2), gmst0, D.nT * 1800 / 86400, P.dt);
inWin = la >= P.winLat(1) & la <= P.winLat(2) & lo >= P.winLon(1) & lo <= P.winLon(2);
dIn = diff([false; inWin; false]);
st = find(dIn == 1);  en = find(dIn == -1) - 1;
passes = {};
for kp = 1:numel(st)
    G = passSetup(t, la, lo, st(kp), en(kp), P, D.nT);
    if ~isempty(G), passes{end + 1} = G; end %#ok<AGROW>
end
end

function G = passSetup(t, la, lo, s, e, P, nT)
% 통과 하나: 1.5 s 간격 관측 표본의 위성 직하점 위치, 진행 방향, 궤적 왼쪽 방향(빔을 기울이는 방향)
G = [];
if e - s < 2, return; end
k1 = max(s - 1, 1);  k2 = min(e + 1, numel(t));
G.Pg = passGeometry(t(k1:k2), la(k1:k2), lo(k1:k2));
G.ts = t(s);
G.tq = (t(s):P.profDt:t(e))';
laq = interp1(t(k1:k2), la(k1:k2), G.tq);
loq = interp1(t(k1:k2), lo(k1:k2), G.tq);
G.xq = (loq - G.Pg.lonm) * G.Pg.kx;              % 통과 중심 기준 국소 평면 [km]
G.yq = (laq - G.Pg.latm) * G.Pg.ky;
u = [gradient(G.xq), gradient(G.yq)];
u = u ./ vecnorm(u, 2, 2);
G.nq = [-u(:, 2), u(:, 1)];                      % 진행 방향의 왼쪽 단위벡터 (빔 오프셋 +)
G.kq = min(max(floor(G.tq / 1800) + 1, 1), nT);  % 각 표본이 속한 30분 칸
end

function n = heavyInSwath(G, D, P)
% 이론 상한: 매 표본마다 ±maxDeg 안 어딘가에 호우 칸이 있으면 1 (기동 제약 없음)
c = P.h * tand(-P.maxDeg:P.stepDeg:P.maxDeg);
[blat, blon] = beamLatLon(G, c);
val = sampleField(D.Pr, D.lat, D.lon, blat, blon, repmat(G.kq, 1, numel(c)));
n = sum(any(val >= P.thrHeavy, 2));
end

%% ===================== 보상 표 =====================
function [Rw, th, info] = rewardGrid(G, D, P, mode, rs, calib)
% Rw(q, j) = 표본 q 시각에 빔각 th(j)로 봤을 때 기대 점수 = P(호우) + alpha × P(강수)
%   mode = 'oracle'  : 실제 강수를 그대로 안다 (상한, 확률 대신 0/1)
%          'nowcast' : 큐 지연 전 장면을 이동 벡터로 옮겨 예측
%          'persist' : 큐 지연 전 장면을 그대로 쓴다 (움직임 무시)
%   calib : calibrate()가 2023 자료로 학습한 표 (큐 강도 → 실제 호우·강수 확률)
th = -P.maxDeg:P.stepDeg:P.maxDeg;
c  = P.h * tand(th);                              % 빔각 → 지상 오프셋 [km]
[blat, blon] = beamLatLon(G, c);
info = struct();
if strcmp(mode, 'oracle')
    val = sampleField(D.Pr, D.lat, D.lon, blat, blon, repmat(G.kq, 1, numel(c)));
    val(isnan(val)) = 0;
    Rw = double(val >= P.thrHeavy) + P.alpha * double(val >= P.thrRain);
    return;
end
[kc, tRef] = cueSlot(G.ts, P, D.nT);
if isnan(kc)                                      % 시즌 맨 처음이라 쓸 수 있는 큐 장면이 없다 → 보상 0 (DP는 천저 유지)
    Rw = zeros(numel(G.tq), numel(th));  info = struct('kc', NaN);
    return;
end
[F, e, v] = cueScene(D, P, kc, mode, rs);
% 관측 시각 t의 위치 p에 있을 비 = 큐 장면(가운데 시각 tRef)에서 p - e - v·(t - tRef) 에 있던 비
dtq = G.tq - tRef;
srcLat = blat - (e(2) + v(2) * dtq) / G.Pg.ky;
srcLon = blon - (e(1) + v(1) * dtq) / G.Pg.kx;
cv = sampleField(F, D.lat, D.lon, srcLat, srcLon, ones(size(srcLat)));
cv(isnan(cv)) = 0;
bin = discretize(cv, P.edges);
% 큐 장면이 관측 시각보다 몇 칸(30분 단위) 앞선 것인지에 맞는 학습 표 줄을 쓴다
lag = min(max(G.kq - kc, 1), numel(P.lags));
lag = repmat(lag, 1, numel(th));
ix  = sub2ind(size(calib.pHeavy), bin, lag);
Rw  = calib.pHeavy(ix) + P.alpha * calib.pRain(ix);
info = struct('kc', kc, 'tRef', tRef, 'v', v, 'e', e, 'cueVal', cv);
end

function [kc, tRef] = cueSlot(ts, P, nT)
% 큐가 쓸 수 있는 장면: 큐 시각(통과 cueL분 전) 이전에 '끝난' 마지막 30분 칸
%   (그 시각을 포함하는 칸은 앞으로 올 시간까지 평균한 값이라 쓰면 미래 정보가 섞인다)
%   이동 벡터가 직전 칸(kc-1)을 쓰므로 kc가 2보다 작으면 큐가 없는 것으로 본다 (NaN)
tCue = ts - P.cueL * 60;
kc = min(floor(tCue / 1800), nT);
if kc < 2, kc = NaN; end
tRef = (kc - 0.5) * 1800;                         % 그 칸의 가운데 시각 [s]
end

function [F, e, v] = cueScene(D, P, kc, mode, rs)
% 큐가 보는 장면: 실제 장면(kc)에 큐의 한계를 넣는다
%   ① 호우 핵(10 mm/h 이상 덩어리)의 일부를 실제보다 약하게 본다 (warm형 호우는 적외선에서 약하게 보임)
%   ② 장면 전체 위치오차 e [km], ③ 이동 속도오차 → v [km/s]
%   attachCue로 큐 자료(Early)를 붙였으면 그 장면과 그 이동 벡터에서 시작한다
%   (Early 자체에 실제 오차가 들어 있으므로 보통 pDet = 1, posSd = 0, velSd = 0 으로 추가 오차를 끈다)
if isfield(D, 'cuePr'), F = double(D.cuePr(:, :, kc));  mv = D.cueMotion;
else,                   F = double(D.Pr(:, :, kc));     mv = D.motion;  end
Lb = labelMask(F >= P.thrHeavy);
nObj = max(Lb(:));
miss = [false; rand(rs, nObj, 1) >= P.pDet];      % 못 알아본 호우 핵
fac  = [1; P.weakFac(1) + diff(P.weakFac) * rand(rs, nObj, 1)];
fac(~miss) = 1;
F = F .* fac(Lb + 1);                             % 못 알아본 핵만 0.2~0.5배로 약하게
if P.blur > 0
    k = ones(2 * P.blur + 1) / (2 * P.blur + 1)^2;
    F = conv2(F, k, 'same');
end
e = P.posSd * randn(rs, 1, 2);
v = mv(kc, :) + P.velSd * randn(rs, 1, 2);
if strcmp(mode, 'persist'), v = [0 0]; end
end

function calib = calibrate(D, P, mode, seed)
% 학습: "큐 장면에서 x mm/h로 보인 곳이 lag칸(30분 × lag) 뒤에 실제로 호우·강수였던 비율"
%   시즌의 모든 장면 쌍(k → k+lag)과 모든 칸을 쓴다. 큐의 한계(cueScene)도 똑같이 넣는다.
%   결과 표: 행 = 큐 강도 구간, 열 = lag (1 = 30분 뒤, 2 = 60분 뒤)
if nargin < 3, mode = 'nowcast'; end
if nargin < 4, seed = 2023; end
rs = RandStream('mt19937ar', 'Seed', seed);
nb = numel(P.edges) - 1;  nl = numel(P.lags);
cnt = zeros(nb, nl);  nH = zeros(nb, nl);  nR = zeros(nb, nl);
[LON, LAT] = meshgrid(D.lon, D.lat);
ky = 110.57;  kx = 111.32 * cosd(LAT);
for k = 2:D.nT - max(P.lags)
    [F, e, v] = cueScene(D, P, k, mode, rs);
    for il = 1:nl
        dtLead = P.lags(il) * 1800;              % 가운데 시각끼리의 차이
        srcLat = LAT - (e(2) + v(2) * dtLead) / ky;
        srcLon = LON - (e(1) + v(1) * dtLead) ./ kx;
        cv = sampleField(F, D.lat, D.lon, srcLat, srcLon, ones(size(srcLat)));
        ok = ~isnan(cv);
        truth = D.Pr(:, :, k + P.lags(il));
        bin = discretize(cv(ok), P.edges);
        cnt(:, il) = cnt(:, il) + accumarray(bin, 1, [nb 1]);
        nH(:, il)  = nH(:, il)  + accumarray(bin, double(truth(ok) >= P.thrHeavy), [nb 1]);
        nR(:, il)  = nR(:, il)  + accumarray(bin, double(truth(ok) >= P.thrRain), [nb 1]);
    end
end
calib.edges  = P.edges;
calib.lags   = P.lags;
calib.count  = cnt;
calib.pHeavy = nH ./ max(cnt, 1);
calib.pRain  = nR ./ max(cnt, 1);
calib.mode   = mode;
calib.year   = D.year;
end

%% ===================== 동적계획법 =====================
function plan = dpPlan(Rw, th, P)
% 표본 q에서 빔각 j를 '관측 중'으로 두는 경로 중 보상 합이 가장 큰 것을 찾는다.
%   한 칸 머무름: 다음 표본도 바로 관측 (비용 없음)
%   각도 바꿈 j' → j: 기동 + 정착 시간만큼의 표본은 관측 못 함 (그 표본들의 보상 0)
[nq, nj] = size(Rw);
Rw(:, th == 0) = Rw(:, th == 0) + 1e-6;                       % 점수가 같으면 천저를 고르도록 아주 작은 가산점
dth  = abs(th(:) - th(:)');                                   % nj × nj 각도 차
slew = dth / P.slewRate + P.settle;  slew(dth == 0) = 0;
m    = ceil(slew / P.profDt);                                 % 이동 중 놓치는 표본 수
V  = -inf(nq, nj);                                            % V(q, j): q에서 j를 관측하며 끝나는 최고 점수
Bj = zeros(nq, nj);  Bq = zeros(nq, nj);                      % 되짚기용: 직전 관측 상태
V(1, :) = Rw(1, :);                                           % 진입 전에 미리 기울여 둘 수 있다
for q = 2:nq
    best = V(q - 1, :);  bj = 1:nj;  bq = repmat(q - 1, 1, nj);   % 일단 '머무름'
    for jp = 1:nj
        qp = q - 1 - m(jp, :);                                % jp에서 출발해 j에 도착하려면 qp에 jp를 보고 있어야 함
        ok = qp >= 1 & (1:nj) ~= jp;
        cand = -inf(1, nj);
        cand(ok) = V(sub2ind([nq nj], qp(ok), repmat(jp, 1, nnz(ok))));
        better = cand > best;
        best(better) = cand(better);  bj(better) = jp;  bq(better) = qp(better);
    end
    V(q, :) = best + Rw(q, :);
    Bj(q, :) = bj;  Bq(q, :) = bq;
end
% 되짚기: 마지막 표본에서 가장 좋은 상태부터 거꾸로 따라간다
[score, j] = max(V(nq, :));
thq = nan(nq, 1);                                             % 표본별 빔각 (NaN = 기동 중)
q = nq;
while q >= 1
    thq(q) = th(j);
    if q == 1, break; end
    pj = Bj(q, j);  pq = Bq(q, j);
    q = pq;  j = pj;
end
plan.th    = thq;
plan.valid = ~isnan(thq);
plan.cb    = P.h * tand(thq);  plan.cb(~plan.valid) = 0;
plan.score = score;
plan.nMoves = nnz(diff(thq(plan.valid)) ~= 0);               % 각도를 바꾼 횟수 (기동 1번 = 1)
end

%% ===================== 기존 방식 (비교용) =====================
function plan = greedyPlan(G, D, P, mode, rs)
% 큐 장면의 국지 최대점(P.greedyThr 이상)을 표적으로 뽑아, 시각 순으로 기동 제약이 맞는 것만 넣는다
%   큐 장면은 DP와 똑같이 cueScene으로 만든다 (공정한 비교)
R = struct('h', P.h, 'slewRate', P.slewRate, 'settle', P.settle, 'dwell', P.dwell, 'prePoint', P.prePoint);
reach = P.h * tand(P.maxDeg);
[kc, tRef] = cueSlot(G.ts, P, D.nT);
if isnan(kc)                                      % 큐가 없으면 천저
    plan = struct('cb', zeros(size(G.tq)), 'valid', true(size(G.tq)), 'th', zeros(size(G.tq)), 'nTargets', 0);
    return;
end
[F, e, v] = cueScene(D, P, kc, mode, rs);
idx = find(localMax(F) & F >= P.greedyThr);
[ii, jj] = ind2sub(size(F), idx);
val = F(idx);
Pg = G.Pg;
x0 = (D.lon(jj) - Pg.lonm) * Pg.kx + e(1);
y0 = (D.lat(ii) - Pg.latm) * Pg.ky + e(2);
[tc, cc] = crossTimes(Pg, x0, y0, v(1) * ones(size(x0)), v(2) * ones(size(x0)), tRef);
pri  = 1 + double(val >= P.thrHeavy);
cand = ~isnan(tc) & abs(cc) <= reach;
acc  = schedule([tc(cand), cc(cand), pri(cand)], G.ts, R);
[cb, valid] = beamAt(acc, G.tq, R);
plan.cb = cb;  plan.valid = valid;  plan.th = atand(cb / P.h);  plan.th(~valid) = NaN;
plan.nTargets = size(acc, 1);
end

%% ===================== 채점 =====================
function E = evaluate(G, D, P, plan)
% 빔이 실제로 본 칸의 IMERG 값으로 센다
[blat, blon] = beamLatLon(G, plan.cb);
[val, ii, jj] = sampleField(D.Pr, D.lat, D.lon, blat, blon, G.kq);
val(~plan.valid) = NaN;
heavy = val >= P.thrHeavy;
E.rain   = nnz(val >= P.thrRain);                 % 강수 프로파일 수
E.heavy  = nnz(heavy);                            % 호우 프로파일 수
E.heavyNear = nnz(heavy & abs(plan.cb) <= P.h * tand(3) + 1e-6);   % 그중 ±3° 안 (전 고도 정량)
ang = abs(atand(plan.cb / P.h));                  % 빔각 크기 [deg]
E.heavyBand = [nnz(heavy & ang <= 3 + 1e-6), nnz(heavy & ang > 3 + 1e-6 & ang <= 6 + 1e-6), ...
               nnz(heavy & ang > 6 + 1e-6)];      % 각도대별 호우 표본: 0~3°, 3~6°, 6~10°
E.cells  = countCells(D.Pr, P.thrHeavy, ii(heavy), jj(heavy), G.kq(heavy));   % 서로 다른 호우 세포 수
E.valid  = nnz(plan.valid);                       % 관측한 표본 수
E.n      = numel(G.tq);
E.blat = blat;  E.blon = blon;  E.val = val;
end

%% ===================== 보조 함수 =====================
function [blat, blon] = beamLatLon(G, c)
% 오프셋 c [km] (스칼라·행벡터·열벡터)로 기울였을 때 빔이 닿는 위경도
bx = G.xq + G.nq(:, 1) .* c;
by = G.yq + G.nq(:, 2) .* c;
blat = G.Pg.latm + by / G.Pg.ky;
blon = G.Pg.lonm + bx / G.Pg.kx;
end

function [val, ii, jj] = sampleField(Pr, lat, lon, blat, blon, kq)
% 가장 가까운 0.1° 칸의 값 (자료 영역 밖이면 NaN)
[n1, n2, ~] = size(Pr);
ii = round((blat - lat(1)) / (lat(2) - lat(1))) + 1;
jj = round((blon - lon(1)) / (lon(2) - lon(1))) + 1;
in = ii >= 1 & ii <= n1 & jj >= 1 & jj <= n2 & ~isnan(ii) & ~isnan(jj);
val = nan(size(blat));
val(in) = Pr(sub2ind([size(Pr, 1) size(Pr, 2) size(Pr, 3)], ii(in), jj(in), kq(in)));
ii(~in) = 0;  jj(~in) = 0;
end

function n = countCells(Pr, thr, ii, jj, kq)
n = 0;
for k = unique(kq(:))'
    s = kq == k;
    Lb = labelMask(Pr(:, :, k) >= thr);
    lab = Lb(sub2ind(size(Lb), ii(s), jj(s)));
    n = n + numel(unique(lab(lab > 0)));
end
end

function L = labelMask(M)
% 8방향으로 이어진 덩어리에 번호 매기기
[n1, n2] = size(M);
L = zeros(n1, n2);
lab = 0;
for s = find(M)'
    if L(s) ~= 0, continue; end
    lab = lab + 1;  L(s) = lab;  stack = s;
    while ~isempty(stack)
        p = stack(end);  stack(end) = [];
        [i, j] = ind2sub([n1 n2], p);
        for di = -1:1
            for dj = -1:1
                a = i + di;  b = j + dj;
                if a >= 1 && a <= n1 && b >= 1 && b <= n2 && M(a, b) && L(a, b) == 0
                    L(a, b) = lab;  stack(end + 1) = a + (b - 1) * n1; %#ok<AGROW>
                end
            end
        end
    end
end
end

function M = localMax(F)
Fp = -inf(size(F) + 2);
Fp(2:end - 1, 2:end - 1) = F;
M = true(size(F));
for di = -1:1
    for dj = -1:1
        if di == 0 && dj == 0, continue; end
        M = M & F >= Fp((2:end - 1) + di, (2:end - 1) + dj);
    end
end
end

function [t, lat, lon] = propagate(C, h, incDeg, raan0, u0, gmst0, nDays, dt)
% 원궤도 + J2 영년 섭동 → 구형 지구 위경도
a = C.Re + h;  n = sqrt(C.mu / a^3);  i = deg2rad(incDeg);  k = C.J2 * (C.Re / a)^2;
raanDot = -1.5 * n * k * cos(i);
uDot    = n * (1 + 1.5 * k * (4 * cos(i)^2 - 1));
t = (0:dt:nDays * 86400 - dt)';
raan = raan0 + raanDot * t;  u = u0 + uDot * t;
x = cos(raan) .* cos(u) - sin(raan) .* sin(u) * cos(i);
y = sin(raan) .* cos(u) + cos(raan) .* sin(u) * cos(i);
z = sin(u) * sin(i);
th = gmst0 + C.we * t;
xe =  cos(th) .* x + sin(th) .* y;
ye = -sin(th) .* x + cos(th) .* y;
lat = asind(z);  lon = atan2d(ye, xe);
end

function P = passGeometry(t, lat, lon)
P.latm = mean(lat);  P.lonm = mean(lon);
P.kx = 111.32 * cosd(P.latm);  P.ky = 110.57;
x = (lon - P.lonm) * P.kx;  y = (lat - P.latm) * P.ky;
n = numel(t);
idx = unique([1:5:n, n]);  m = numel(idx) - 1;
P.t1 = t(idx(1:m));  P.t2 = t(idx(2:m + 1));
p1 = [x(idx(1:m)), y(idx(1:m))];  p2 = [x(idx(2:m + 1)), y(idx(2:m + 1))];
Lseg = sqrt(sum((p2 - p1).^2, 2));
P.u = (p2 - p1) ./ Lseg;  P.nrm = [-P.u(:, 2), P.u(:, 1)];
P.V = Lseg ./ (P.t2 - P.t1);  P.p1 = p1;
P.ts = t(1);  P.te = t(end);
end

function [tc, cc] = crossTimes(P, x0, y0, vx, vy, tref)
n = numel(x0);  tc = nan(n, 1);  cc = nan(n, 1);  m = numel(P.t1);
for j = 1:m
    dtj = P.t1(j) - tref;
    qx = x0 + vx .* dtj - P.p1(j, 1);  qy = y0 + vy .* dtj - P.p1(j, 2);
    a0 = qx * P.u(j, 1) + qy * P.u(j, 2);  c0 = qx * P.nrm(j, 1) + qy * P.nrm(j, 2);
    va = vx * P.u(j, 1) + vy * P.u(j, 2);  vc = vx * P.nrm(j, 1) + vy * P.nrm(j, 2);
    tau = a0 ./ (P.V(j) - va);  dur = P.t2(j) - P.t1(j);
    if j < m, s = tau >= -1e-6 & tau < dur; else, s = tau >= -1e-6 & tau <= dur + 1e-6; end   % 경계 반올림 오차 허용
    s = s & isnan(tc);
    tc(s) = P.t1(j) + tau(s);  cc(s) = c0(s) + vc(s) .* tau(s);
end
end

function acc = schedule(cand, ts, R)
acc = zeros(0, 2);
if isempty(cand), return; end
[~, ord] = sortrows([-cand(:, 3), cand(:, 1)]);
for k = ord'
    tj = cand(k, 1);  cj = cand(k, 2);  pos = sum(acc(:, 1) < tj);
    if pos == 0, prevEnd = ts - R.prePoint;  prevC = 0;
    else, prevEnd = acc(pos, 1) + R.dwell / 2;  prevC = acc(pos, 2); end
    okk = (tj - R.dwell / 2) - prevEnd >= slewTime(prevC, cj, R);
    if okk && pos < size(acc, 1)
        okk = (acc(pos + 1, 1) - R.dwell / 2) - (tj + R.dwell / 2) >= slewTime(cj, acc(pos + 1, 2), R);
    end
    if okk, acc = [acc(1:pos, :); tj, cj; acc(pos + 1:end, :)]; end
end
end

function s = slewTime(c1, c2, R)
dphi = abs(atand(c2 / R.h) - atand(c1 / R.h));
if dphi < 0.05, s = 0; else, s = dphi / R.slewRate + R.settle; end
end

function [cb, valid] = beamAt(acc, tq, R)
cb = zeros(size(tq));  valid = true(size(tq));
if isempty(acc) || isempty(tq), return; end
m = size(acc, 1);
cPrev = [0; acc(1:m - 1, 2)];
se = acc(:, 1) - R.dwell / 2;
sl = arrayfun(@(k) slewTime(cPrev(k), acc(k, 2), R), (1:m)');
ss = se - sl;
for q = 1:numel(tq)
    k = find(ss <= tq(q), 1, 'last');
    if isempty(k), continue; end
    if tq(q) < se(k), valid(q) = false; else, cb(q) = acc(k, 2); end
end
end
