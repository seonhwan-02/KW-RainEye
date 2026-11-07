function imerg_check(month, outDir, day)
% IMERG Harmony 자료 점검: 파일 수, 시간 간격, 영역, 결측, 강수 통계, 누적 지도
%   imerg_check('202307')                  바탕화면 K-RainEye_IMERG\202307 폴더를 점검
%   imerg_check('202307', [], '20230715')  그 폴더에서 하루(UTC)만 점검
if nargin < 1, month = '202307'; end
if nargin < 2 || isempty(outDir), outDir = fullfile(fileparts(mfilename('fullpath')), 'out'); end
if nargin < 3, day = ''; end
folder = fullfile(getenv('USERPROFILE'), 'Desktop', 'K-RainEye_IMERG', month);
d = dir(fullfile(folder, '*.nc4'));
assert(~isempty(d), '파일 없음: %s', folder);
if ~exist(outDir, 'dir'), mkdir(outDir); end

% 파일 이름의 시작 시각(S hhmmss)과 날짜로 정렬
key = regexp({d.name}, '\.(\d{8})-S(\d{6})', 'tokens', 'once');
key = cellfun(@(c) [c{1} c{2}], key, 'UniformOutput', false);
[key, ord] = unique(key);                                  % 같은 시각이 두 번 받아졌으면 하나만 쓴다
d = d(ord);
if ~isempty(day), d = d(startsWith(key, day)); end
n = numel(d);

f1  = fullfile(folder, d(1).name);
lat = double(ncread(f1, '/Grid/lat'));
lon = double(ncread(f1, '/Grid/lon'));
P   = nan(numel(lat), numel(lon), n, 'single');
t   = NaT(n, 1, 'TimeZone', 'UTC');
for k = 1:n
    f = fullfile(folder, d(k).name);
    P(:, :, k) = ncread(f, '/Grid/precipitation');          % 결측(_FillValue)은 NaN으로 읽힘
    t(k) = datetime(1980, 1, 6, 'TimeZone', 'UTC') + seconds(double(ncread(f, '/Grid/time')));
end

dt   = minutes(diff(t));
nNaN = nnz(isnan(P));
tag = month;  if ~isempty(day), tag = day; end
L = strings(0, 1);                                         % 화면과 파일에 같이 남길 줄
L(end+1) = sprintf('[점검] %s 폴더%s (%s 실행)', month, ifelse(~isempty(day), [' · ' day], ''), string(datetime('now')));
L(end+1) = sprintf('  파일 %d개, 합계 %.2f MB', n, sum([d.bytes]) / 2^20);
L(end+1) = sprintf('  시간: %s ~ %s (UTC), 간격 %s분, 중복 %d개', t(1), t(end), mat2str(unique(dt)'), n - numel(unique(t)));
L(end+1) = sprintf('  위도 %.2f~%.2f (%d칸), 경도 %.2f~%.2f (%d칸)', lat(1), lat(end), numel(lat), lon(1), lon(end), numel(lon));
L(end+1) = sprintf('  결측 %d / %d (%.3f%%)', nNaN, numel(P), 100 * nNaN / numel(P));
L(end+1) = sprintf('  강수강도 최소 %.2f, 최대 %.1f mm/h', min(P(:)), max(P(:)));

% 강수 통계
acc = sum(P, 3, 'omitnan') * 0.5;                          % 기간 누적 [mm] (30분 = 0.5 h)
[amax, im] = max(acc(:));  [ia, io] = ind2sub(size(acc), im);
heavy = squeeze(mean(P >= 10, [1 2])) * 100;              % 10 mm/h 이상 칸 비율 [%]
pmax  = squeeze(max(P, [], [1 2]));
L(end+1) = sprintf('  기간 누적 최대 %.0f mm (%.2fN, %.2fE), 영역 평균 %.1f mm', amax, lat(ia), lon(io), mean(acc(:), 'omitnan'));
L(end+1) = sprintf('  10 mm/h 이상 칸 비율: 평균 %.2f%%, 최대 %.2f%%', mean(heavy), max(heavy));

% 참고 지점 (오송 36.62N 127.33E 등)
pts = {'서울', 37.57, 126.98; '오송', 36.62, 127.33; '광주', 35.16, 126.85; '부산', 35.18, 129.08; '제주', 33.50, 126.53};
ptAcc = zeros(size(pts, 1), 1);  ptMax = ptAcc;
for i = 1:size(pts, 1)
    [~, a] = min(abs(lat - pts{i, 2}));  [~, b] = min(abs(lon - pts{i, 3}));
    ptAcc(i) = acc(a, b);  ptMax(i) = max(P(a, b, :));
    L(end+1) = sprintf('  %s 누적 %.0f mm, 최대 %.1f mm/h', pts{i, 1}, ptAcc(i), ptMax(i)); %#ok<AGROW>
end

% 결과 저장: 사람이 읽는 txt + 숫자 json (그림과 같은 out 폴더)
fprintf('%s\n', L);
fid = fopen(fullfile(outDir, sprintf('check_%s.txt', tag)), 'w', 'n', 'UTF-8');
fprintf(fid, '%s\n', L);
fclose(fid);
ks = struct('folder', month, 'day', day, 'files', n, 'MB', sum([d.bytes]) / 2^20, 'tStartUTC', string(t(1)), ...
    'tEndUTC', string(t(end)), 'stepMin', unique(dt)', 'duplicates', n - numel(unique(t)), 'nan', nNaN, ...
    'maxRate', max(P(:)), 'accMax', amax, 'accMaxLat', lat(ia), 'accMaxLon', lon(io), 'accMean', mean(acc(:), 'omitnan'), ...
    'heavyFracMeanPct', mean(heavy), 'heavyFracMaxPct', max(heavy), 'points', {pts(:, 1)'}, 'pointAcc', ptAcc', 'pointMax', ptMax');
fid = fopen(fullfile(outDir, sprintf('check_%s.json', tag)), 'w', 'n', 'UTF-8');
fprintf(fid, '%s', jsonencode(ks, 'PrettyPrint', true));
fclose(fid);

% 그림: 누적 지도 + 시간별 변화
tk  = t + hours(9);  tk.TimeZone = '';                     % 한국 시각
fig = figure('Visible', 'off', 'Position', [100 100 1150 470]);
tl  = tiledlayout(fig, 1, 2, 'TileSpacing', 'compact');
ax  = nexttile(tl);
imagesc(ax, lon, lat, acc, 'AlphaData', ~isnan(acc));  axis(ax, 'xy');  axis(ax, 'image');
colormap(ax, [1 1 1; turbo(255)]);  clim(ax, [0 max(50, ceil(amax / 50) * 50)]);
cb = colorbar(ax);  cb.Label.String = '누적 강수 [mm]';
hold(ax, 'on');
plot(ax, [pts{:, 3}], [pts{:, 2}], 'k^', 'MarkerFaceColor', 'w', 'MarkerSize', 6);
text(ax, [pts{:, 3}] + 0.2, [pts{:, 2}], pts(:, 1), 'FontSize', 9, 'FontWeight', 'bold');
xlabel(ax, '경도 [°E]');  ylabel(ax, '위도 [°N]');
title(ax, sprintf('IMERG 누적 강수 (%s ~ %s KST)', datestr(tk(1), 'mm/dd HH:MM'), datestr(tk(end) + minutes(30), 'mm/dd HH:MM')));
ax = nexttile(tl);
yyaxis(ax, 'left');   plot(ax, tk, pmax, 'LineWidth', 1.5);  ylabel(ax, '영역 최대 강수강도 [mm/h]');
yyaxis(ax, 'right');  plot(ax, tk, heavy, 'LineWidth', 1.5); ylabel(ax, '10 mm/h 이상 칸 비율 [%]');
grid(ax, 'on');  xlabel(ax, '한국 시각');  title(ax, '30분 간격 변화');
png = fullfile(outDir, sprintf('check_%s.png', tag));
exportgraphics(fig, png, 'Resolution', 140);
fprintf('  그림: %s\n', png);
end

function v = ifelse(c, a, b)
if c, v = a; else, v = b; end
end
