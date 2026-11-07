function imerg_view(day, slot, savePng)
% IMERG 30분 강수 파일(.nc4)을 지도 위에서 직접 보는 뷰어 (MATLAB 앱 창)
%   imerg_view                             2023-07-15(UTC)를 연다
%   imerg_view('2024-07-10')               그 날짜(UTC)를 연다
%   imerg_view('2024-07-10', 30)           30번째 칸(14:30 UTC)부터 연다
%   imerg_view('2023-07-14', 47, 'a.png')  창 없이 그 칸을 그림 파일로 저장 (점검용)
%
% 창 안에서 할 수 있는 것
%   날짜 고르기(받아 둔 날짜만 선택됨), 시각 슬라이더, ◀ ▶ 버튼과 ←/→ 키로 30분씩 이동,
%   재생/정지(30분 간격 애니메이션), 보기 전환(30분 강수강도 / 그날 0시부터 누적),
%   색 범위 조절, 파일 구조 보기(ncdisp), 현재 화면 PNG 저장(imerg/out).
%   지도 위 칸을 클릭하면 위도·경도·값이 보인다.
% 자료 위치: 바탕화면\K-RainEye_IMERG\YYYYMM\*.nc4 (harmony_download.py로 받은 것)

if nargin < 1 || isempty(day), day = '2023-07-15'; end
if nargin < 2 || isempty(slot), slot = 1; end
if nargin < 3, savePng = ''; end

S.root  = fullfile(getenv('USERPROFILE'), 'Desktop', 'K-RainEye_IMERG');
S.outDir = fullfile(fileparts(mfilename('fullpath')), 'out');
S.dates = availableDates(S.root);
assert(~isempty(S.dates), '받아 둔 IMERG 파일이 없습니다: %s', S.root);
S.mode = 1;                                      % 1: 30분 강수강도, 2: 그날 누적
S.cmax = [30 100];                               % 보기별 색 상한 [mm/h, mm]
S.k = slot;
S.pts = {'서울', 37.57, 126.98; '오송', 36.62, 127.33; '광주', 35.16, 126.85; '부산', 35.18, 129.08; '제주', 33.50, 126.53};

% ---------- 창 없이 그림만 저장 ----------
if ~isempty(savePng)
    loadDay(datetime(day, 'InputFormat', 'yyyy-MM-dd'));
    fig = figure('Visible', 'off', 'Position', [80 60 980 760], 'Color', 'w');
    gx = geoaxes(fig);
    H = buildMap(gx);
    S.k = min(max(slot, 1), S.n);
    draw();
    exportgraphics(fig, savePng, 'Resolution', 130);
    close(fig);
    return;
end

% ---------- 앱 창 ----------
fig = uifigure('Name', 'IMERG 뷰어 - K-RainEye', 'Position', [60 40 1100 860], 'Color', 'w');
g = uigridlayout(fig, [4 9]);
g.RowHeight = {32, '1x', 44, 26};
g.ColumnWidth = {150, 40, 40, 70, 150, 120, 110, '1x', 110};

dp = uidatepicker(g, 'DisplayFormat', 'yyyy-MM-dd', 'Limits', [min(S.dates) max(S.dates)], ...
    'ValueChangedFcn', @(s, ~) onDate(s.Value));
missing = setdiff(min(S.dates):caldays(1):max(S.dates), S.dates);
if ~isempty(missing), dp.DisabledDates = missing; end
bPrev = uibutton(g, 'Text', '◀', 'ButtonPushedFcn', @(~, ~) step(-1)); %#ok<NASGU>
bNext = uibutton(g, 'Text', '▶', 'ButtonPushedFcn', @(~, ~) step(+1)); %#ok<NASGU>
bPlay = uibutton(g, 'Text', '재생', 'ButtonPushedFcn', @(~, ~) togglePlay());
dd = uidropdown(g, 'Items', {'30분 강수강도 [mm/h]', '그날 누적 [mm]'}, 'ValueChangedFcn', @(s, ~) onMode(s));
sp = uispinner(g, 'Limits', [1 1000], 'Step', 5, 'ValueDisplayFormat', '색 상한 %.0f', ...
    'ValueChangedFcn', @(s, ~) onClim(s.Value));
bInfo = uibutton(g, 'Text', '파일 구조 보기', 'ButtonPushedFcn', @(~, ~) showStructure()); %#ok<NASGU>
uilabel(g, 'Text', '');
bSave = uibutton(g, 'Text', 'PNG 저장', 'ButtonPushedFcn', @(~, ~) savePngNow()); %#ok<NASGU>

gx = geoaxes(g);
gx.Layout.Row = 2;  gx.Layout.Column = [1 9];
sl = uislider(g, 'Limits', [1 48], 'MajorTicks', 1:6:48, ...
    'MajorTickLabels', compose('%02d:00', 0:3:21), 'MinorTicks', 1:48, ...
    'ValueChangedFcn', @(s, ~) goTo(round(s.Value)));    % 손을 뗄 때 이동 (끄는 중 이벤트는 안 씀)
sl.Layout.Row = 3;  sl.Layout.Column = [1 9];
info = uilabel(g, 'Text', '', 'FontSize', 12);
info.Layout.Row = 4;  info.Layout.Column = [1 9];

H = buildMap(gx);
tm = timer('ExecutionMode', 'fixedSpacing', 'Period', 0.5, 'TimerFcn', @(~, ~) step(+1));
fig.CloseRequestFcn = @onClose;
fig.WindowKeyPressFcn = @onKey;

d0 = datetime(day, 'InputFormat', 'yyyy-MM-dd');
if ~any(S.dates == d0), d0 = S.dates(1); end
dp.Value = d0;
loadDay(d0);
sp.Value = S.cmax(S.mode);
goTo(slot);
fprintf('IMERG 뷰어를 열었습니다. 받아 둔 날짜 %d일 (%s ~ %s)\n', numel(S.dates), ...
    char(min(S.dates), 'yyyy-MM-dd'), char(max(S.dates), 'yyyy-MM-dd'));

% ================= 중첩 함수 =================
    function loadDay(d)
        folder = fullfile(S.root, char(d, 'yyyyMM'));
        f = dir(fullfile(folder, '*.nc4'));
        key = fileKeys(f);
        [key, ord] = unique(key);                % 같은 시각이 두 번 받아졌으면 하나만
        f = f(ord);
        f = f(startsWith(key, char(d, 'yyyyMMdd')));
        assert(~isempty(f), '파일 없음: %s', char(d, 'yyyy-MM-dd'));
        f1 = fullfile(f(1).folder, f(1).name);
        S.lat = double(ncread(f1, '/Grid/lat'));
        S.lon = double(ncread(f1, '/Grid/lon'));
        S.n = numel(f);
        S.P = zeros(numel(S.lat), numel(S.lon), S.n, 'single');
        S.t = NaT(S.n, 1);
        for j = 1:S.n
            fj = fullfile(f(j).folder, f(j).name);
            S.P(:, :, j) = ncread(fj, '/Grid/precipitation');
            S.t(j) = datetime(1980, 1, 6) + seconds(double(ncread(fj, '/Grid/time')));
        end
        S.files = f;
        S.day = d;
        [S.LON, S.LAT] = meshgrid(S.lon, S.lat);
    end

    function H = buildMap(ax)
        try
            geobasemap(ax, 'grayland');
        catch
            geobasemap(ax, 'darkwater');
        end
        hold(ax, 'on');
        if ~isfield(S, 'lat')                    % 앱 창은 날짜를 읽기 전에 지도를 만든다
            la = [28.05 39.95];  lo = [119.05 131.95];
        else
            la = S.lat([1 end])';  lo = S.lon([1 end])';
        end
        geolimits(ax, la, lo);
        geoplot(ax, la([1 2 2 1 1]), lo([1 1 2 2 1]), '-', 'Color', [0.3 0.3 0.3]);
        H.sc = geoscatter(ax, nan, nan, 30, nan, 's', 'filled');
        colormap(ax, turbo(256));
        H.cb = colorbar(ax);
        H.sc.DataTipTemplate.DataTipRows(1).Label = '위도';
        H.sc.DataTipTemplate.DataTipRows(2).Label = '경도';
        H.sc.DataTipTemplate.DataTipRows(end + 1) = dataTipTextRow('값', 'CData', '%.1f');
        geoplot(ax, [S.pts{:, 2}], [S.pts{:, 3}], 'k^', 'MarkerFaceColor', 'w', 'MarkerSize', 6);
        text(ax, [S.pts{:, 2}] - 0.15, [S.pts{:, 3}] + 0.2, S.pts(:, 1), 'FontSize', 9, 'FontWeight', 'bold');
        H.ax = ax;
    end

    function draw()
        k = S.k;
        if S.mode == 1
            v = S.P(:, :, k);
            unit = '강수강도 [mm/h]';  thr = 0.1;
        else
            v = sum(S.P(:, :, 1:k), 3) * 0.5;    % 30분 = 0.5시간
            unit = sprintf('누적 강수 [mm] (00:00~%s UTC)', char(S.t(k) + minutes(30), 'HH:mm'));  thr = 0.5;
        end
        m = v > thr;
        set(H.sc, 'LatitudeData', S.LAT(m), 'LongitudeData', S.LON(m), 'CData', double(v(m)));
        clim(H.ax, [0 S.cmax(S.mode)]);
        H.cb.Label.String = unit;
        tk = S.t(k) + hours(9);
        title(H.ax, sprintf('%s UTC  (%s KST)   %d/%d', char(S.t(k), 'yyyy-MM-dd HH:mm'), ...
            char(tk, 'MM-dd HH:mm'), k, S.n));
        if exist('info', 'var') && isvalid(info)
            info.Text = sprintf('  파일: %s   |   최대 %.1f   |   비 칸 %d개 · 30분 강수 10 mm/h 이상 %d개', ...
                S.files(k).name, max(v(:)), nnz(m), nnz(S.P(:, :, k) >= 10));
        end
        drawnow limitrate;
    end

    function goTo(k)
        S.k = min(max(k, 1), S.n);
        draw();
        if exist('sl', 'var') && isvalid(sl)
            sl.Limits = [1 max(S.n, 2)];
            sl.Value = S.k;
        end
    end

    function step(dk)
        k = S.k + dk;
        if k > S.n, k = 1; elseif k < 1, k = S.n; end   % 하루 안에서 돈다
        goTo(k);
    end

    function togglePlay()
        if strcmp(tm.Running, 'on')
            stop(tm);  bPlay.Text = '재생';
        else
            start(tm);  bPlay.Text = '정지';
        end
    end

    function onDate(d)
        wasOn = strcmp(tm.Running, 'on');
        if wasOn, stop(tm); end
        info.Text = '  읽는 중...';  drawnow;
        loadDay(d);
        S.k = min(S.k, S.n);
        draw();
        if wasOn, start(tm); end
    end

    function onMode(s)
        S.mode = find(strcmp(s.Items, s.Value));
        sp.Value = S.cmax(S.mode);
        draw();
    end

    function onClim(v)
        S.cmax(S.mode) = v;
        draw();
    end

    function showStructure()
        f1 = fullfile(S.files(S.k).folder, S.files(S.k).name);
        txt = evalc('ncdisp(f1)');
        w = uifigure('Name', ['파일 구조 - ' S.files(S.k).name], 'Position', [120 120 760 560]);
        gl = uigridlayout(w, [1 1]);
        uitextarea(gl, 'Value', splitlines(string(txt)), 'Editable', 'off', 'FontName', 'Consolas');
    end

    function savePngNow()
        if ~exist(S.outDir, 'dir'), mkdir(S.outDir); end
        name = sprintf('view_%s_%sUTC_%s.png', char(S.t(S.k), 'yyyyMMdd'), char(S.t(S.k), 'HHmm'), ...
            ternary(S.mode == 1, '강수강도', '누적'));
        file = fullfile(S.outDir, name);
        exportapp(fig, file);
        info.Text = ['  저장했습니다: ' file];
    end

    function onKey(~, e)
        switch e.Key
            case 'rightarrow', step(+1);
            case 'leftarrow',  step(-1);
            case 'space',      togglePlay();
        end
    end

    function onClose(~, ~)
        try
            stop(tm); delete(tm);
        catch
        end
        delete(fig);
    end
end

function d = availableDates(root)
% 받아 둔 달 폴더(YYYYMM)의 파일 이름에서 날짜 목록을 만든다
d = NaT(0, 1);
m = dir(root);
m = m([m.isdir] & ~cellfun(@isempty, regexp({m.name}, '^\d{6}$', 'once')));
for i = 1:numel(m)
    key = fileKeys(dir(fullfile(root, m(i).name, '*.nc4')));
    if isempty(key), continue; end
    ds = unique(extractBefore(string(key(:)), 9));
    d = [d; datetime(ds, 'InputFormat', 'yyyyMMdd')]; %#ok<AGROW>
end
d = unique(d);
end

function key = fileKeys(f)
% 파일 이름의 날짜+시작시각 (예: 20230715003000)
key = regexp({f.name}, '\.(\d{8})-S(\d{6})', 'tokens', 'once');
key = cellfun(@(c) [c{1} c{2}], key, 'UniformOutput', false);
end

function v = ternary(c, a, b)
if c, v = a; else, v = b; end
end
