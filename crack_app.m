function app = crack_app(varargin)
%CRACK_APP  光伏电池片隐裂检测 —— 图形界面小程序
%
%   crack_app            打开界面。用左侧按钮添加有隐裂 / 无隐裂的图片或整个文件夹，
%                        点击“开始检测”，即可在界面上查看判定、裂纹位置、关键指标和中间结果。
%   crack_app('demo')    打开界面并载入项目中的示例图片和 outputs/ 中已有的检测结果（无需等待）。
%
%   操作：滚轮缩放、拖动平移、双击适应窗口；点击红线或右侧列表定位裂纹；
%         ↑/↓ 切换图片，1–6 切换视图，F 适应窗口，R 重新检测当前图片，Esc 取消选中裂纹。
%
%   app = crack_app(...) 还返回一组函数句柄，便于在脚本中演示或测试：
%     app.addFiles(paths)  app.addFolder(dir)  app.loadResults(dir)  app.loadDemo()
%     app.run()  app.runAll()  app.runSelected()  app.select(k)  app.setView(name)  app.zoomToCrack(i)
%     app.fit()  app.zoom(factor)  app.setMethod('improved'|'baseline')  app.export(dir)
%     app.state()  app.close()
%   视图名：'overlay' 检测标注 | 'original' 原图 | 'valid' 有效区域 | 'supp' 纹理抑制 |
%           'resp' 暗线响应 | 'cand' 候选筛选
%
%   检测只使用图像像素和 src/crack_config.m 中的参数；data/labels.csv 若存在，
%   仅用于在界面上显示“参考标签”作对照，不参与检测。

root = fileparts(mfilename('fullpath'));
addpath(fullfile(root, 'src'));
if exist('OCTAVE_VERSION', 'builtin') ~= 0
    pkg load image
end
S = init_state(root);
scr = get(0, 'ScreenSize');
fw = max(1180, min(1520, scr(3) - 40));
fh = max(760, min(930, scr(4) - 90));
pos = [max(1, round((scr(3) - fw) / 2)), max(1, round((scr(4) - fh) / 2)), fw, fh];
fig = figure('Name', '光伏电池片隐裂检测', 'NumberTitle', 'off', 'MenuBar', 'none', ...
    'ToolBar', 'none', 'Color', S.T.bg, 'Units', 'pixels', 'Position', pos, ...
    'Visible', 'off', 'IntegerHandle', 'off');
S.fig = fig;
S = build_ui(fig, S);
setappdata(fig, 'S', S);
set(fig, 'SizeChangedFcn', @(s, e) on_resize(fig), ...
    'WindowButtonDownFcn', @(s, e) on_mouse_down(fig), ...
    'WindowButtonMotionFcn', @(s, e) on_mouse_move(fig), ...
    'WindowButtonUpFcn', @(s, e) on_mouse_up(fig), ...
    'WindowScrollWheelFcn', @(s, e) on_wheel(fig, e), ...
    'CloseRequestFcn', @(s, e) on_close(fig));
% 键盘：MATLAB 用 WindowKeyPressFcn（焦点在控件上也能响应）；Octave 只触发图窗的 KeyPressFcn
if exist('OCTAVE_VERSION', 'builtin') ~= 0
    set(fig, 'KeyPressFcn', @(s, e) on_key(fig, e));
else
    set(fig, 'WindowKeyPressFcn', @(s, e) on_key(fig, e));
end
relayout(fig);
set(fig, 'Visible', 'on');
drawnow;
if nargin >= 1 && ischar(varargin{1}) && strcmpi(varargin{1}, 'demo')
    load_demo(fig, true);
end
app = struct('fig', fig, ...
    'addFiles', @(p) add_paths(fig, p), ...
    'addFolder', @(d) add_folder(fig, d), ...
    'loadResults', @(d) load_results(fig, d), ...
    'loadDemo', @() load_demo(fig, true), ...
    'run', @() run_detection(fig, 'pending', false), ...
    'runAll', @() run_detection(fig, 'all', false), ...
    'runSelected', @() run_detection(fig, 'selected', false), ...
    'select', @(k) select_item(fig, k, true), ...
    'setView', @(v) set_view(fig, v), ...
    'zoomToCrack', @(i) select_crack(fig, i, true), ...
    'fit', @() zoom_fit(fig), ...
    'zoom', @(f) zoom_by(fig, f, []), ...
    'setMethod', @(m) set_method(fig, m), ...
    'export', @(d) export_results(fig, d), ...
    'state', @() getappdata(fig, 'S'), ...
    'close', @() on_close(fig));
if nargout == 0
    clear app
end
end

%% ======================================================================
%  状态与外观
%  ======================================================================
function S = init_state(root)
S.root = root;
S.cfg = crack_config();
S.T = ui_theme();
ui_font(pick_font());
S.env = env_short();
S.items = new_item('');
S.items(1) = [];
S.sel = 0;
S.selCrack = 0;
S.view = 'overlay';
S.galOff = 0;
S.crackOff = 0;
S.running = false;
S.stop = false;
S.userPicked = false;
S.previewBusy = false;
S.method = 'improved';
S.Z = struct('cx', 1, 'cy', 1, 'scale', 1, 'fit', 1, 'W', 0, 'H', 0);
S.pan = struct('active', false, 'p0', [0 0], 'c0', [0 0], 'moved', false);
S.full = struct('k', 0, 'rgb', []);
S.hits = struct('region', {}, 'rect', {}, 'action', {}, 'arg', {});
S.labels = load_labels(root);
S.status = '就绪：添加图片或文件夹，然后点击“开始检测”';
S.progress = [];
S.readout = '';
S.L = struct();
S.h = struct();
S.ovH = {};
end

function T = ui_theme()
T.bg = hx('EEF2F7');
T.card = [1 1 1];
T.border = hx('E2E8F0');
T.text = hx('0F172A');
T.sub = hx('475569');
T.muted = hx('94A3B8');
T.faint = hx('F8FAFC');
T.accent = hx('4F46E5');
T.accentDark = hx('4338CA');
T.accentSoft = hx('EEF2FF');
T.header = hx('0F172A');
T.headerSub = hx('94A3B8');
T.viewer = hx('0B1220');
T.viewerLine = hx('1E293B');
T.crackLine = hx('FF3B30');
T.selLine = hx('22D3EE');
T.box = hx('FBBF24');
T.danger = hx('E11D48');
T.good = hx('059669');
end

function st = status_style(code)
switch code
    case 'crack'
        st = struct('label', '有隐裂', 'main', hx('E11D48'), 'soft', hx('FFE4E6'), 'text', hx('BE123C'), 'icon', 'alert');
    case 'no_crack'
        st = struct('label', '无隐裂', 'main', hx('059669'), 'soft', hx('D1FAE5'), 'text', hx('047857'), 'icon', 'check');
    case 'review'
        st = struct('label', '待复核', 'main', hx('D97706'), 'soft', hx('FEF3C7'), 'text', hx('B45309'), 'icon', 'question');
    case 'error'
        st = struct('label', '失败', 'main', hx('64748B'), 'soft', hx('F1F5F9'), 'text', hx('475569'), 'icon', 'cross');
    case 'running'
        st = struct('label', '检测中', 'main', hx('4F46E5'), 'soft', hx('E0E7FF'), 'text', hx('4338CA'), 'icon', 'dots');
    otherwise
        st = struct('label', '待检测', 'main', hx('94A3B8'), 'soft', hx('F1F5F9'), 'text', hx('64748B'), 'icon', 'dots');
end
end

function c = hx(s)
c = [hex2dec(s(1:2)), hex2dec(s(3:4)), hex2dec(s(5:6))] / 255;
end

function k = ui_fscale(setTo)
% 文字缩放系数：使坐标区文字实际像素大小等于名义字号（MATLAB 约为 1，Octave 约为 1.4）
persistent K
if nargin == 1, K = setTo; end
if isempty(K), K = 1; end
k = K;
end

function calibrate_font(ax)
try
    set(ax, 'Units', 'pixels');
    t = text(0, 0, repmat('测', 1, 10), 'Parent', ax, 'FontUnits', 'pixels', 'FontSize', 50, ...
        'FontName', ui_font(), 'Units', 'pixels', 'Visible', 'on');
    drawnow;
    e = get(t, 'Extent');
    delete(t);
    k = 500 / e(3);
    if isfinite(k) && k > 0.6 && k < 2.5
        ui_fscale(k);
    end
catch
end
end

function f = ui_font(setTo)
persistent F
if nargin == 1, F = setTo; end
if isempty(F), F = get(0, 'DefaultTextFontName'); end
f = F;
end

function f = pick_font()
prefer = {'Microsoft YaHei UI', 'Microsoft YaHei', 'PingFang SC', 'Hiragino Sans GB', ...
    'Noto Sans CJK SC', 'Source Han Sans SC', 'Source Han Sans CN', 'WenQuanYi Zen Hei', 'SimHei'};
f = get(0, 'DefaultTextFontName');
try
    have = lower(listfonts());
    for i = 1:numel(prefer)
        if any(strcmp(have, lower(prefer{i})))
            f = prefer{i};
            return;
        end
    end
catch
end
end

function s = env_short()
if exist('OCTAVE_VERSION', 'builtin') ~= 0
    s = ['GNU Octave ' version()];
else
    s = ['MATLAB R' version('-release')];
end
end

function L = load_labels(root)
L = struct('keys', {{}}, 'vals', []);
p = fullfile(root, 'data', 'labels.csv');
if exist(p, 'file') ~= 2, return; end
try
    T = read_csv_simple(p);
    L.keys = lower({T.file});
    L.vals = cellfun(@str2double, {T.label});
catch
end
end

function it = new_item(path)
it = struct('path', path, 'name', '', 'stem', '', 'relpath', '', 'key', '', ...
    'status', 'pending', 'source', 'none', 'method', '', 'thumb', [], 'preview', [], ...
    'W', 0, 'H', 0, 'res', [], 'dbg', [], 'maskIdx', [], 'runtime', NaN, 'err', '', 'label', NaN);
if isempty(path), return; end
[d, n, e] = fileparts(path);
[~, dn] = fileparts(d);
it.name = [n e];
it.stem = n;
it.relpath = [dn '/' n e];
it.key = lower(it.relpath);
end

%% ======================================================================
%  界面构建与布局
%  ======================================================================
function S = build_ui(fig, S)
T = S.T;
h.axHeader = decor_axes(fig);
h.axSide = decor_axes(fig);
h.axCenter = decor_axes(fig);
h.axView = axes('Parent', fig, 'Units', 'pixels', 'Position', [10 10 100 100], 'NextPlot', 'add');
h.hImg = image([1 2], [1 2], zeros(2, 2, 3, 'uint8'), 'Parent', h.axView);
h.hHi = image([1 2], [1 2], zeros(2, 2, 3, 'uint8'), 'Parent', h.axView);
set([h.hImg h.hHi], 'Visible', 'off', 'HitTest', 'off');
set(h.axView, 'Visible', 'off', 'YDir', 'reverse', 'XLimMode', 'manual', 'YLimMode', 'manual', ...
    'XLim', [0 1], 'YLim', [0 1], 'NextPlot', 'add', 'Layer', 'top');
no_interact(h.axView);
h.axInfo = decor_axes(fig);
h.axStatus = decor_axes(fig);
set(fig, 'Visible', 'on');
set(h.axStatus, 'Position', [1 1 900 200], 'XLim', [0 900], 'YLim', [0 200]);
calibrate_font(h.axStatus);
fn = ui_font();
btn = @(str, cb, bg, fg) uicontrol('Parent', fig, 'Style', 'pushbutton', 'String', str, ...
    'Callback', cb, 'BackgroundColor', bg, 'ForegroundColor', fg, 'FontName', fn, ...
    'FontUnits', 'pixels', 'FontSize', 14, 'FontWeight', 'bold', 'Units', 'pixels');
light = hx('EEF2FF');
h.bAddFiles = btn('添加图片', @(s, e) on_add_files(fig), light, T.accentDark);
h.bAddFolder = btn('添加文件夹', @(s, e) on_add_folder(fig), light, T.accentDark);
h.bRun = btn('开始检测', @(s, e) run_detection(fig, 'pending', true), T.accent, [1 1 1]);
set(h.bRun, 'FontSize', 16);
h.bLoad = btn('载入已有结果', @(s, e) on_load_results(fig), hx('F1F5F9'), T.sub);
h.bExport = btn('导出结果', @(s, e) on_export(fig), hx('F1F5F9'), T.sub);
h.pMethod = uicontrol('Parent', fig, 'Style', 'popupmenu', ...
    'String', {'改进法（栅线抑制 + 暗线增强）', '基线（背景差分阈值）'}, 'Value', 1, ...
    'Callback', @(s, e) on_method(fig), 'FontName', fn, 'FontUnits', 'pixels', 'FontSize', 13, ...
    'BackgroundColor', [1 1 1], 'ForegroundColor', T.text, 'Units', 'pixels');
S.h = h;
end

function ax = decor_axes(fig)
ax = axes('Parent', fig, 'Units', 'pixels', 'Position', [1 1 10 10], 'Visible', 'off', ...
    'YDir', 'reverse', 'XLimMode', 'manual', 'YLimMode', 'manual', 'NextPlot', 'add', ...
    'HitTest', 'off');
no_interact(ax);
end

function no_interact(ax)
% 关闭 MATLAB 新版坐标区自带的滚轮缩放/拖动交互和浮动工具栏，避免与自定义交互冲突
try, disableDefaultInteractivity(ax); catch, end
try, set(get(ax, 'Toolbar'), 'Visible', 'off'); catch, end
end

function L = compute_layout(fig)
p = get(fig, 'Position');
W = p(3); H = p(4);
m = 12; hh = 62; sb = 28;
sideW = 300; infoW = max(330, min(380, round(W * 0.25)));
bodyY = sb + m; bodyH = H - hh - sb - 2 * m;
L.W = W; L.H = H;
L.header = [0, H - hh, W, hh];
L.status = [0, 0, W, sb];
L.side = [m, bodyY, sideW, bodyH];
L.info = [W - m - infoW, bodyY, infoW, bodyH];
cx = m + sideW + m;
cw = L.info(1) - m - cx;
L.center = [cx, bodyY, cw, bodyH];
tb = 52; cap = 40;
L.viewFrame = [cx, bodyY + cap, cw, bodyH - tb - cap];
inset = 6;
L.view = [cx + inset, bodyY + cap + inset, cw - 2 * inset, bodyH - tb - cap - 2 * inset];
end

function relayout(fig)
S = getappdata(fig, 'S');
if isempty(S), return; end
S.L = compute_layout(fig);
L = S.L; h = S.h;
set(h.axHeader, 'Position', L.header);
set(h.axSide, 'Position', L.side);
set(h.axCenter, 'Position', L.center);
set(h.axView, 'Position', L.view);
set(h.axInfo, 'Position', L.info);
set(h.axStatus, 'Position', L.status);
% 侧栏按钮（局部坐标：自上而下）
sx = L.side(1); sy = L.side(2); sw = L.side(3); sh = L.side(4);
pad = 14; bw = (sw - 2 * pad - 10) / 2;
top = @(y, hgt) sy + sh - y - hgt;
set(h.bAddFiles, 'Position', [sx + pad, top(40, 36), bw, 36]);
set(h.bAddFolder, 'Position', [sx + pad + bw + 10, top(40, 36), bw, 36]);
set(h.pMethod, 'Position', [sx + pad + 70, top(86, 30), sw - 2 * pad - 70, 30]);
set(h.bRun, 'Position', [sx + pad, top(128, 42), sw - 2 * pad, 42]);
set(h.bLoad, 'Position', [sx + pad, top(180, 32), bw, 32]);
set(h.bExport, 'Position', [sx + pad + bw + 10, top(180, 32), bw, 32]);
setappdata(fig, 'S', S);
if S.sel > 0, refit_after_resize(fig); end
redraw_all(fig);
end

function refit_after_resize(fig)
% 窗口大小改变：原来处于“适应窗口”时重新适应，否则保持当前中心与缩放
S = getappdata(fig, 'S');
if S.Z.W == 0, fit_zoom_state(fig); return; end
wasFit = abs(S.Z.scale - S.Z.fit) <= 1e-6 * S.Z.fit;
S.Z.fit = max(S.Z.W / S.L.view(3), S.Z.H / S.L.view(4)) * 1.02;
if wasFit
    S.Z.scale = S.Z.fit;
    S.Z.cx = (S.Z.W + 1) / 2; S.Z.cy = (S.Z.H + 1) / 2;
end
setappdata(fig, 'S', S);
end

function on_resize(fig)
if ~ishghandle(fig), return; end
relayout(fig);
end

function redraw_all(fig)
draw_header(fig);
draw_side(fig);
draw_center(fig);
draw_viewer(fig);
draw_info(fig);
draw_status(fig);
end

%% ======================================================================
%  绘图工具
%  ======================================================================
function [ax, w, h] = begin_draw(fig, axName, region)
S = getappdata(fig, 'S');
ax = S.h.(axName);
r = get(ax, 'Position');
w = r(3); h = r(4);
delete(get(ax, 'Children'));
set(ax, 'XLim', [0 max(w, 1)], 'YLim', [0 max(h, 1)]);
S.hits = S.hits(~strcmp({S.hits.region}, region));
setappdata(fig, 'S', S);
end

function add_hit(fig, axName, region, lr, action, arg)
% lr = 局部矩形 [x y w h]（左上为原点）；记录为图窗坐标（左下为原点）
S = getappdata(fig, 'S');
p = get(S.h.(axName), 'Position');
fr = [p(1) + lr(1), p(2) + p(4) - lr(2) - lr(4), lr(3), lr(4)];
S.hits(end + 1) = struct('region', region, 'rect', fr, 'action', action, 'arg', arg);
setappdata(fig, 'S', S);
end

function hd = rrect(ax, x, y, w, h, r, face, edge, lw)
if nargin < 8 || isempty(edge), edge = 'none'; end
if nargin < 9, lw = 1; end
w = max(w, 0.5); h = max(h, 0.5);
cv = [min(1, 2 * r / w), min(1, 2 * r / h)];
hd = rectangle('Parent', ax, 'Position', [x y w h], 'Curvature', cv, 'FaceColor', face, ...
    'EdgeColor', edge, 'LineWidth', lw, 'HitTest', 'off');
end

function hd = txt(ax, x, y, s, fs, col, varargin)
hd = text(x, y, s, 'Parent', ax, 'FontUnits', 'pixels', 'FontSize', fs * ui_fscale(), 'Color', col, ...
    'FontName', ui_font(), 'Interpreter', 'none', 'VerticalAlignment', 'middle', ...
    'HorizontalAlignment', 'left', 'HitTest', 'off', varargin{:});
end

function [starts, wide] = char_info(s)
% 字符起始位置与“宽字符”标记。MATLAB 的 char 是 UTF-16 码元；Octave 的 char 是 UTF-8 字节，
% 需按首字节划分字符，避免截断时把一个汉字切成两半。
b = double(s(:)');
if exist('OCTAVE_VERSION', 'builtin') ~= 0
    starts = find(b < 128 | b >= 192);
    wide = b(starts) >= 224;
else
    starts = 1:numel(b);
    wide = b > 255;
end
end

function w = text_w(s, fs)
[~, wide] = char_info(s);
w = fs * (sum(wide) * 1.0 + sum(~wide) * 0.57);
end

function t = first_chars(s, m)
starts = char_info(s);
if m >= numel(starts), t = s; return; end
t = s(1:starts(m + 1) - 1);
end

function s = ellip(s, maxw, fs)
if text_w(s, fs) <= maxw, return; end
starts = char_info(s);
m = numel(starts);
while m > 1 && text_w([first_chars(s, m) '…'], fs) > maxw
    m = m - 1;
end
s = [first_chars(s, m) '…'];
end

function lines = wrap_text(s, maxw, fs, maxLines)
lines = {};
starts = char_info(s);
ends = [starts(2:end) - 1, numel(s)];
cur = '';
for i = 1:numel(starts)
    ch = s(starts(i):ends(i));
    if text_w([cur ch], fs) > maxw
        lines{end + 1} = cur; %#ok<AGROW>
        cur = ch;
    else
        cur = [cur ch]; %#ok<AGROW>
    end
end
if ~isempty(cur), lines{end + 1} = cur; end
if numel(lines) > maxLines
    lines = lines(1:maxLines);
    lines{end} = ellip([lines{end} '……'], maxw, fs);
end
end

function wch = chip(ax, x, y, s, fs, bg, fg, align)
% 圆角标签；align = 'left' 时 x 为左边，'right' 时 x 为右边；y 为中心
if nargin < 8, align = 'left'; end
wch = text_w(s, fs) + 2 * round(fs * 0.75);
hgt = round(fs * 1.75);
if strcmp(align, 'right'), x = x - wch; end
rrect(ax, x, y - hgt / 2, wch, hgt, hgt / 2, bg);
txt(ax, x + wch / 2, y, s, fs, fg, 'HorizontalAlignment', 'center', 'FontWeight', 'bold');
end

function draw_icon(ax, kind, cx, cy, r, bg, fg)
rrect(ax, cx - r, cy - r, 2 * r, 2 * r, r, bg);
lw = max(1.5, r * 0.14);
switch kind
    case 'check'
        line([cx - 0.42 * r, cx - 0.1 * r, cx + 0.45 * r], [cy + 0.02 * r, cy + 0.34 * r, cy - 0.32 * r], ...
            'Parent', ax, 'Color', fg, 'LineWidth', lw, 'HitTest', 'off');
    case 'cross'
        line([cx - 0.32 * r, cx + 0.32 * r], [cy - 0.32 * r, cy + 0.32 * r], 'Parent', ax, 'Color', fg, 'LineWidth', lw, 'HitTest', 'off');
        line([cx - 0.32 * r, cx + 0.32 * r], [cy + 0.32 * r, cy - 0.32 * r], 'Parent', ax, 'Color', fg, 'LineWidth', lw, 'HitTest', 'off');
    case 'alert'
        line([cx cx], [cy - 0.48 * r, cy + 0.12 * r], 'Parent', ax, 'Color', fg, 'LineWidth', lw * 1.2, 'HitTest', 'off');
        rrect(ax, cx - 0.1 * r, cy + 0.3 * r, 0.2 * r, 0.2 * r, 0.1 * r, fg);
    case 'question'
        txt(ax, cx, cy + 0.04 * r, '?', round(1.25 * r), fg, 'HorizontalAlignment', 'center', 'FontWeight', 'bold');
    otherwise   % dots
        for d = -1:1
            rrect(ax, cx + d * 0.38 * r - 0.11 * r, cy - 0.11 * r, 0.22 * r, 0.22 * r, 0.11 * r, fg);
        end
end
end

function s = fmt_int(v)
% 千位分隔的整数
s = sprintf('%d', round(v));
n = numel(s);
neg = n > 0 && s(1) == '-';
if neg, s = s(2:end); n = n - 1; end
for k = n - 3:-3:1
    s = [s(1:k) ',' s(k + 1:end)];
end
if neg, s = ['-' s]; end
end

%% ======================================================================
%  顶栏、侧栏、状态栏
%  ======================================================================
function draw_header(fig)
[ax, w, h] = begin_draw(fig, 'axHeader', 'header');
S = getappdata(fig, 'S'); T = S.T;
rrect(ax, 0, 0, w, h, 0, T.header);
rrect(ax, 0, h - 3, w, 3, 0, T.accent);
% 图标：圆角方块中的一道裂纹
rrect(ax, 18, 12, 38, 38, 10, T.accent);
for gx = 26:7:47
    line([gx gx], [17 45], 'Parent', ax, 'Color', hx('818CF8'), 'LineWidth', 1, 'HitTest', 'off');
end
line([24 32 30 38 48], [17 27 31 39 45], 'Parent', ax, 'Color', [1 1 1], 'LineWidth', 2.6, 'HitTest', 'off');
txt(ax, 70, 23, '光伏电池片隐裂检测', 20, [1 1 1], 'FontWeight', 'bold');
txt(ax, 70, 45, 'Solar-cell micro-crack inspector  ·  栅线抑制 + 多方向细暗线增强 + 形状筛选', 12, T.headerSub);
x = w - 18;
x = x - chip(ax, x, h / 2, S.env, 12, hx('1E293B'), hx('CBD5E1'), 'right') - 8;
x = x - chip(ax, x, h / 2, ['参数 v' S.cfg.version], 12, hx('1E293B'), hx('CBD5E1'), 'right') - 8;
if strcmp(S.method, 'improved'), m = '改进法'; else, m = '基线方法'; end
chip(ax, x, h / 2, m, 12, hx('312E81'), hx('C7D2FE'), 'right');
end

function draw_side(fig)
[ax, w, h] = begin_draw(fig, 'axSide', 'side');
S = getappdata(fig, 'S'); T = S.T;
pad = 14;
rrect(ax, 0, 0, w, h, 14, T.card, T.border);
txt(ax, pad, 20, '图片输入', 12, T.muted, 'FontWeight', 'bold');
txt(ax, pad, 101, '检测方法', 13, T.sub);
line([pad w - pad], [228 228], 'Parent', ax, 'Color', T.border, 'HitTest', 'off');
% ---- 图片列表 ----
N = numel(S.items);
txt(ax, pad, 248, '图片列表', 14, T.text, 'FontWeight', 'bold');
chip(ax, pad + 66, 248, sprintf('%d', N), 11, T.accentSoft, T.accentDark);
if N > 0 && ~S.running
    txt(ax, w - pad, 248, '清空', 13, T.accent, 'HorizontalAlignment', 'right', 'FontWeight', 'bold');
    add_hit(fig, 'axSide', 'side', [w - pad - 40, 236, 42, 24], 'clear', 0);
end
sumH = 178;
galTop = 266; galBot = h - pad - sumH - 12;
stride = 72; rowH = 64;
nVis = max(1, floor((galBot - galTop + (stride - rowH)) / stride));
S = getappdata(fig, 'S');
S.galOff = max(0, min(S.galOff, N - nVis));
S.L.galRect = local_rect(S.h.axSide, [0, galTop, w, galBot - galTop]);
S.L.galVis = nVis;
setappdata(fig, 'S', S);
if N == 0
    rrect(ax, pad, galTop, w - 2 * pad, min(140, galBot - galTop), 12, T.faint, T.border);
    txt(ax, w / 2, galTop + 46, '还没有图片', 15, T.sub, 'HorizontalAlignment', 'center', 'FontWeight', 'bold');
    txt(ax, w / 2, galTop + 74, '点击上方按钮添加有隐裂 / 无隐裂的', 12, T.muted, 'HorizontalAlignment', 'center');
    txt(ax, w / 2, galTop + 94, '电池片图片（jpg / png / bmp / tif）', 12, T.muted, 'HorizontalAlignment', 'center');
end
rw = w - 2 * pad - 8;
for v = 1:min(nVis, N - S.galOff)
    k = S.galOff + v;
    it = S.items(k);
    y0 = galTop + (v - 1) * stride;
    isSel = k == S.sel;
    if isSel
        rrect(ax, pad, y0, rw, rowH, 12, T.accentSoft, T.accent, 1.6);
    else
        rrect(ax, pad, y0, rw, rowH, 12, T.card, T.border);
    end
    tx = pad + 7; ty = y0 + 6; tw = 78; th = 52;
    if ~isempty(it.thumb)
        image([tx + 0.5, tx + tw - 0.5], [ty + 0.5, ty + th - 0.5], it.thumb, 'Parent', ax, 'HitTest', 'off');
    else
        rrect(ax, tx, ty, tw, th, 4, hx('E2E8F0'));
        txt(ax, tx + tw / 2, ty + th / 2, '…', 16, T.muted, 'HorizontalAlignment', 'center');
    end
    nx = tx + tw + 10;
    txt(ax, nx, y0 + 19, ellip(it.name, rw - (nx - pad) - 10, 13), 13, T.text, 'FontWeight', 'bold');
    st = status_style(it.status);
    cw = chip(ax, nx, y0 + 44, st.label, 11, st.soft, st.text);
    meta = '';
    if any(strcmp(it.status, {'crack', 'no_crack', 'review'})) && ~isempty(it.res)
        if strcmp(it.status, 'crack')
            meta = sprintf('%d 条裂纹', it.res.nCracks);
        elseif isfinite(it.runtime)
            meta = sprintf('%.0f s', it.runtime);
        end
    end
    if ~isempty(meta)
        txt(ax, nx + cw + 8, y0 + 44, meta, 11, T.muted);
    end
    if ~isnan(it.label) && any(strcmp(it.status, {'crack', 'no_crack'}))
        agree = (it.label == 1) == strcmp(it.status, 'crack');
        if agree
            draw_icon(ax, 'check', pad + rw - 15, y0 + 44, 8, hx('D1FAE5'), hx('059669'));
        else
            draw_icon(ax, 'cross', pad + rw - 15, y0 + 44, 8, hx('FFE4E6'), hx('E11D48'));
        end
    end
    add_hit(fig, 'axSide', 'side', [pad, y0, rw, rowH], 'select', k);
end
if N > nVis      % 滚动条
    trackH = nVis * stride - (stride - rowH);
    rrect(ax, w - pad - 4, galTop, 4, trackH, 2, hx('E2E8F0'));
    th = max(24, trackH * nVis / N);
    ty = galTop + (trackH - th) * S.galOff / max(1, N - nVis);
    rrect(ax, w - pad - 4, ty, 4, th, 2, hx('94A3B8'));
end
draw_summary(fig, ax, pad, h - pad - sumH, w - 2 * pad, sumH);
end

function r = local_rect(ax, lr)
p = get(ax, 'Position');
r = [p(1) + lr(1), p(2) + p(4) - lr(2) - lr(4), lr(3), lr(4)];
end

function draw_summary(fig, ax, x, y, w, h)
S = getappdata(fig, 'S'); T = S.T;
rrect(ax, x, y, w, h, 12, T.faint, T.border);
codes = {S.items.status};
N = numel(codes);
cnt = @(c) nnz(strcmp(codes, c));
nC = cnt('crack'); nN = cnt('no_crack'); nR = cnt('review'); nE = cnt('error');
nDone = nC + nN + nR + nE;
txt(ax, x + 14, y + 22, '检测概览', 14, T.text, 'FontWeight', 'bold');
txt(ax, x + w - 14, y + 22, sprintf('已完成 %d / %d', nDone, N), 12, T.sub, 'HorizontalAlignment', 'right');
bx = x + 14; bw = w - 28; by = y + 42;
rrect(ax, bx, by, bw, 10, 5, hx('E2E8F0'));
segs = {nC, 'crack'; nN, 'no_crack'; nR, 'review'; nE, 'error'};
cx = bx;
for i = 1:size(segs, 1)
    if N == 0 || segs{i, 1} == 0, continue; end
    sw = bw * segs{i, 1} / N;
    st = status_style(segs{i, 2});
    rrect(ax, cx, by, sw, 10, min(5, sw / 2), st.main);
    cx = cx + sw;
end
items = {'有隐裂', nC, 'crack'; '无隐裂', nN, 'no_crack'; '待复核', nR, 'review'; '待检测', N - nDone, 'pending'};
for i = 1:4
    col = mod(i - 1, 2); row = floor((i - 1) / 2);
    lx = x + 14 + col * (w - 28) / 2; ly = y + 76 + row * 30;
    st = status_style(items{i, 3});
    rrect(ax, lx, ly - 5, 10, 10, 5, st.main);
    txt(ax, lx + 18, ly, items{i, 1}, 13, T.sub);
    txt(ax, lx + (w - 28) / 2 - 16, ly, sprintf('%d', items{i, 2}), 16, T.text, 'FontWeight', 'bold', 'HorizontalAlignment', 'right');
end
% 与参考标签对照（只用于展示，不参与检测）
lab = [S.items.label];
dec = strcmp(codes, 'crack') | strcmp(codes, 'no_crack');
m = dec & ~isnan(lab);
if any(m)
    agree = nnz((lab(m) == 1) == strcmp(codes(m), 'crack'));
    s = sprintf('与参考标签一致  %d / %d', agree, nnz(m));
    txt(ax, x + 14, y + h - 22, s, 13, T.text, 'FontWeight', 'bold');
    pc = sprintf('%.0f%%', 100 * agree / nnz(m));
    if agree == nnz(m), st = status_style('no_crack'); else, st = status_style('review'); end
    chip(ax, x + w - 14, y + h - 22, pc, 11, st.soft, st.text, 'right');
else
    txt(ax, x + 14, y + h - 22, '参考标签：data/labels.csv（仅作对照）', 11, T.muted);
end
end

function draw_status(fig)
[ax, w, h] = begin_draw(fig, 'axStatus', 'status');
S = getappdata(fig, 'S'); T = S.T;
rrect(ax, 0, 0, w, h, 0, T.card);
line([0 w], [0.5 0.5], 'Parent', ax, 'Color', T.border, 'HitTest', 'off');
x = 14;
if ~isempty(S.progress)
    pw = 180;
    rrect(ax, x, h / 2 - 4, pw, 8, 4, hx('E0E7FF'));
    f = S.progress(1) / max(1, S.progress(2));
    if f > 0, rrect(ax, x, h / 2 - 4, max(8, pw * f), 8, 4, T.accent); end
    x = x + pw + 12;
end
txt(ax, x, h / 2, S.status, 12, T.sub);
S.h.readout = txt(ax, w - 14, h / 2, S.readout, 12, T.muted, 'HorizontalAlignment', 'right');
setappdata(fig, 'S', S);
end

function set_status(fig, s, progress)
S = getappdata(fig, 'S');
S.status = s;
if nargin >= 3, S.progress = progress; end
setappdata(fig, 'S', S);
draw_status(fig);
end

%% ======================================================================
%  中间区域：视图切换、图像、说明
%  ======================================================================
function V = view_defs()
V = {'overlay', '检测标注'; 'original', '原图'; 'valid', '有效区域'; ...
     'supp', '纹理抑制'; 'resp', '暗线响应'; 'cand', '候选筛选'};
end

function ok = view_available(it, v)
ok = true;
if any(strcmp(v, {'overlay', 'original'})), return; end
ok = ~isempty(it) && ~isempty(it.dbg);
if ~ok, return; end
switch v
    case 'supp', ok = ~isempty(it.dbg.supp);
    case 'resp', ok = ~isempty(it.dbg.resp);
end
end

function draw_center(fig)
[ax, w, h] = begin_draw(fig, 'axCenter', 'center');
S = getappdata(fig, 'S'); T = S.T;
it = [];
if S.sel > 0, it = S.items(S.sel); end
% ---- 视图切换（分段按钮） ----
V = view_defs();
segW = max(64, min(92, floor((w - 250) / size(V, 1))));
rrect(ax, 0, 6, segW * size(V, 1) + 8, 40, 12, T.card, T.border);
for i = 1:size(V, 1)
    x = 4 + (i - 1) * segW;
    avail = ~isempty(it) && view_available(it, V{i, 1});
    if strcmp(S.view, V{i, 1})
        rrect(ax, x, 10, segW, 32, 9, T.accent);
        col = [1 1 1];
    elseif avail
        col = T.sub;
    else
        col = hx('CBD5E1');
    end
    txt(ax, x + segW / 2, 26, V{i, 2}, 13, col, 'HorizontalAlignment', 'center', 'FontWeight', 'bold');
    if avail
        add_hit(fig, 'axCenter', 'center', [x, 8, segW, 36], 'view', i);
    end
end
% ---- 缩放按钮 ----
zb = {'适应', 'fit', 46; '1:1', 'one', 40; '−', 'out', 34; '+', 'in', 34};
x = w;
for i = size(zb, 1):-1:1
    bw = zb{i, 3};
    x = x - bw;
    rrect(ax, x, 10, bw, 32, 8, T.card, T.border);
    txt(ax, x + bw / 2, 26, zb{i, 1}, 14, T.sub, 'HorizontalAlignment', 'center', 'FontWeight', 'bold');
    if ~isempty(it), add_hit(fig, 'axCenter', 'center', [x, 10, bw, 32], zb{i, 2}, 0); end
    x = x - 6;
end
if ~isempty(it) && ~isempty(it.preview)
    z = 100 / S.Z.scale;
    txt(ax, x - 6, 26, sprintf('%.0f%%', z), 13, T.sub, 'HorizontalAlignment', 'right');
end
% ---- 图像框 ----
fy = 52; capH = 40;
rrect(ax, 0, fy, w, h - fy - capH, 14, T.viewer, T.viewerLine);
% ---- 底部说明 ----
cy = h - capH / 2 + 2;
if isempty(it)
    txt(ax, 4, cy, '滚轮缩放 · 拖动平移 · 双击适应窗口 · ↑/↓ 切换图片 · 1–6 切换视图 · R 重新检测当前图片', 12, T.muted);
else
    st = status_style(it.status);
    cw = chip(ax, 2, cy, st.label, 12, st.soft, st.text);
    nm = sprintf('%s', it.relpath);
    if it.W > 0, nm = sprintf('%s   %d × %d', it.relpath, it.W, it.H); end
    txt(ax, cw + 12, cy, nm, 13, T.text, 'FontWeight', 'bold');
    leg = view_legend(S.view, it);
    txt(ax, w - 4, cy, ellip(leg, max(80, w - cw - text_w(nm, 13) - 40), 12), 12, T.sub, 'HorizontalAlignment', 'right');
end
% ---- 空白页 / 提示 ----
if isempty(S.items)
    draw_welcome(fig, ax, w, fy, h - fy - capH);
elseif ~isempty(it) && isempty(it.preview)
    txt(ax, w / 2, fy + (h - fy - capH) / 2, '正在加载图像…', 15, hx('CBD5E1'), 'HorizontalAlignment', 'center');
elseif ~isempty(it) && ~view_available(it, S.view)
    txt(ax, w / 2, fy + (h - fy - capH) / 2 - 12, '该视图需要在本界面中运行检测后生成', 15, hx('CBD5E1'), 'HorizontalAlignment', 'center');
    txt(ax, w / 2, fy + (h - fy - capH) / 2 + 14, '（载入的批处理结果不含中间图，可点击“开始检测”重新分析）', 12, hx('94A3B8'), 'HorizontalAlignment', 'center');
end
end

function s = view_legend(v, it)
switch v
    case 'overlay'
        if ~isempty(it.res) && it.res.nCracks > 0
            s = '红线：裂纹中心线   黄框：裂纹编号与外接框   点击红线可选中';
        else
            s = '检测标注（未检出裂纹时无标记）';
        end
    case 'original', s = '原始图像';
    case 'valid', s = '红：排除的亮缝 / 过曝 / 边界   蓝：汇流条带（降权）';
    case 'supp'
        if ~isempty(it.dbg) && ~isempty(it.dbg.resp)
            s = '减去细栅与横向重复纹理后的残差（越暗越比背景暗）';
        else
            s = '基线：D = max(B − I, 0)（越亮越比背景暗）';
        end
    case 'resp', s = '多方向细暗线响应 z（越亮越像细暗线）';
    case 'cand', s = '蓝：未入选候选   橙：弱候选   红：最终裂纹   绿：断点连接';
    otherwise, s = '';
end
end

function draw_welcome(fig, ax, w, fy, fh)
S = getappdata(fig, 'S'); T = S.T;
cy = fy + fh / 2;
rrect(ax, w / 2 - 34, cy - 170, 68, 68, 18, hx('1E1B4B'));
for gx = w / 2 - 20:9:w / 2 + 22
    line([gx gx], [cy - 160, cy - 112], 'Parent', ax, 'Color', hx('3730A3'), 'LineWidth', 1.2, 'HitTest', 'off');
end
line(w / 2 + [-22 -6 -10 6 22], cy + [-160 -142 -134 -120 -112], 'Parent', ax, 'Color', hx('F87171'), 'LineWidth', 3, 'HitTest', 'off');
txt(ax, w / 2, cy - 68, '添加电池片图片，开始隐裂检测', 22, [1 1 1], 'HorizontalAlignment', 'center', 'FontWeight', 'bold');
txt(ax, w / 2, cy - 38, '支持有隐裂、无隐裂样本混合输入；程序自动估计栅线方向与间距，逐张判定并标出裂纹位置', 13, hx('94A3B8'), 'HorizontalAlignment', 'center');
steps = {'1', '添加图片', '图片或整个文件夹'; '2', '开始检测', '每张约 10–90 秒'; '3', '查看结果', '判定 · 位置 · 中间图'};
cw = 170; gap = 18; x0 = w / 2 - (3 * cw + 2 * gap) / 2;
for i = 1:3
    x = x0 + (i - 1) * (cw + gap);
    rrect(ax, x, cy - 8, cw, 82, 14, hx('111A2E'), hx('1E293B'));
    rrect(ax, x + 14, cy + 6, 26, 26, 13, T.accent);
    txt(ax, x + 27, cy + 19, steps{i, 1}, 14, [1 1 1], 'HorizontalAlignment', 'center', 'FontWeight', 'bold');
    txt(ax, x + 50, cy + 19, steps{i, 2}, 15, [1 1 1], 'FontWeight', 'bold');
    txt(ax, x + 14, cy + 54, steps{i, 3}, 12, hx('94A3B8'));
end
hasDemo = exist(fullfile(S.root, 'cracked'), 'dir') == 7 || exist(fullfile(S.root, 'uncracked'), 'dir') == 7;
if hasDemo
    bw = 360; bx = w / 2 - bw / 2; by = cy + 104;
    rrect(ax, bx, by, bw, 44, 12, T.accent);
    hasRes = exist(fullfile(S.root, 'outputs', 'defects.json'), 'file') == 2;
    if hasRes
        lab = '一键载入示例：20 张图片 + 已有检测结果';
    else
        lab = '一键载入示例图片（cracked/ + uncracked/）';
    end
    txt(ax, w / 2, by + 22, lab, 14, [1 1 1], 'HorizontalAlignment', 'center', 'FontWeight', 'bold');
    add_hit(fig, 'axCenter', 'center', [bx, by, bw, 44], 'demo', 0);
    if hasRes
        txt(ax, w / 2, by + 68, '只载入图片、不载入结果', 13, hx('A5B4FC'), 'HorizontalAlignment', 'center');
        add_hit(fig, 'axCenter', 'center', [w / 2 - 90, by + 56, 180, 24], 'demoimgs', 0);
    end
end
end

function draw_viewer(fig)
S = getappdata(fig, 'S');
ax = S.h.axView;
delete_handles(S.ovH);
S.ovH = {};
it = [];
if S.sel > 0, it = S.items(S.sel); end
if isempty(it) || isempty(it.preview) || ~view_available(it, S.view)
    set([S.h.hImg S.h.hHi], 'Visible', 'off');
    setappdata(fig, 'S', S);
    return;
end
W = it.W; H = it.H;
C = view_image(it, S.view);
[ch, cw, ~] = size(C);
set(S.h.hImg, 'CData', C, 'XData', [0.5 * W / cw + 0.5, (cw - 0.5) * W / cw + 0.5], ...
    'YData', [0.5 * H / ch + 0.5, (ch - 0.5) * H / ch + 0.5], 'Visible', 'on');
setappdata(fig, 'S', S);
apply_zoom(fig);
update_hires(fig);
draw_overlay(fig);
end

function C = view_image(it, v)
P = it.preview;
switch v
    case {'overlay', 'original'}
        C = P;
    case 'valid'
        d = it.dbg; g = to_size(gray_of(P), d.size);
        base = cat(3, g, g, g);
        C = tint(base, ~d.valid, [225 29 72], 0.55);
        C = tint(C, d.bus & d.valid, [59 130 246], 0.38);
    case 'supp'
        g = it.dbg.supp;
        C = cat(3, g, g, g);
    case 'resp'
        C = apply_cmap(it.dbg.resp, magma_map());
    case 'cand'
        d = it.dbg; g = uint8(0.3 * double(to_size(gray_of(P), d.size)));
        C = cat(3, g, g, g);
        cols = [96 165 250; 251 146 60; 255 59 48; 52 211 153];
        for k = 1:4
            C = paint(C, d.cls == k, cols(k, :));
        end
    otherwise
        C = P;
end
end

function g = gray_of(P)
g = uint8(mean(double(P), 3));
end

function B = to_size(A, sz)
if size(A, 1) == sz(1) && size(A, 2) == sz(2), B = A; return; end
ys = min(size(A, 1), max(1, round(((1:sz(1)) - 0.5) * size(A, 1) / sz(1) + 0.5)));
xs = min(size(A, 2), max(1, round(((1:sz(2)) - 0.5) * size(A, 2) / sz(2) + 0.5)));
B = A(ys, xs, :);
end

function C = tint(C, m, col, a)
for c = 1:3
    ch = double(C(:, :, c));
    ch(m) = (1 - a) * ch(m) + a * col(c);
    C(:, :, c) = uint8(ch);
end
end

function C = paint(C, m, col)
for c = 1:3
    ch = C(:, :, c); ch(m) = col(c); C(:, :, c) = ch;
end
end

function C = apply_cmap(g, M)
idx = double(g) + 1;
C = uint8(cat(3, reshape(M(idx, 1), size(g)), reshape(M(idx, 2), size(g)), reshape(M(idx, 3), size(g))));
end

function M = magma_map()
a = [0 0 4; 28 16 68; 79 18 123; 129 37 129; 181 54 122; 229 80 100; 251 135 97; 254 194 135; 252 253 191];
t = linspace(0, 1, size(a, 1));
M = zeros(256, 3);
for c = 1:3
    M(:, c) = interp1(t, a(:, c), linspace(0, 1, 256));
end
end

function draw_overlay(fig)
S = getappdata(fig, 'S');
if ~isempty(S.ovH)
    delete_handles(S.ovH);
    S.ovH = {};
    setappdata(fig, 'S', S);
end
if S.sel == 0, return; end
ax = S.h.axView;
it = S.items(S.sel);
if ~strcmp(S.view, 'overlay') || isempty(it.res) || it.res.nCracks == 0
    return;
end
T = S.T;
H = {};
cr = it.res.cracks;
for i = 1:numel(cr)
    isSel = i == S.selCrack;
    if isSel, col = T.selLine; else, col = T.crackLine; end
    c = cr(i);
    if ~isempty(c.pixel_xy)
        % 按当前缩放把中心线像素归并到约 1 个屏幕像素的格子，再按 8 邻接连线：
        % 缩小时线条连贯不发糊，放大时保留逐像素细节
        q = max(1, floor(S.Z.scale));
        xy = double(c.pixel_xy);
        if q > 1, xy = unique(round(xy / q), 'rows'); end
        [X, Y] = pixel_segments(xy);
        X = X * q; Y = Y * q;
        H{end + 1} = line(X, Y, 'Parent', ax, 'Color', [0.2 0.03 0.03], 'LineWidth', 3.2, 'HitTest', 'off'); %#ok<AGROW>
        H{end + 1} = line(X, Y, 'Parent', ax, 'Color', col, 'LineWidth', 2 + 0.8 * isSel, 'HitTest', 'off'); %#ok<AGROW>
    elseif ~isempty(c.points)
        [X, Y] = points_polyline(c.points);
        H{end + 1} = line(X, Y, 'Parent', ax, 'Color', [0.2 0.03 0.03], 'LineWidth', 3.2, 'HitTest', 'off'); %#ok<AGROW>
        H{end + 1} = line(X, Y, 'Parent', ax, 'Color', col, 'LineWidth', 2 + 0.8 * isSel, 'HitTest', 'off'); %#ok<AGROW>
    end
    b = double(c.bbox);
    if isSel, bc = T.selLine; lw = 2; else, bc = T.box; lw = 1.2; end
    H{end + 1} = rectangle('Parent', ax, 'Position', [b(1) - 0.5, b(2) - 0.5, b(3) - b(1) + 1, b(4) - b(2) + 1], ...
        'EdgeColor', bc, 'LineWidth', lw, 'HitTest', 'off'); %#ok<AGROW>
    H{end + 1} = text(b(1), b(2), sprintf(' #%d ', c.id), 'Parent', ax, 'Color', hx('111827'), ...
        'BackgroundColor', bc, 'FontUnits', 'pixels', 'FontSize', 12 * ui_fscale(), 'FontWeight', 'bold', ...
        'FontName', ui_font(), 'Interpreter', 'none', 'VerticalAlignment', 'bottom', ...
        'HorizontalAlignment', 'left', 'Margin', 1, 'Clipping', 'on', 'HitTest', 'off'); %#ok<AGROW>
end
S.ovH = H;
setappdata(fig, 'S', S);
end

function delete_handles(H)
% 删除句柄元胞数组中仍然有效的图形对象（元胞可同时存放线、矩形、文字等不同类型）
for i = 1:numel(H)
    if ishghandle(H{i}), delete(H{i}); end
end
end

function [X, Y] = points_polyline(P)
% 载入结果只有沿主方向排序的采样点：相邻点距离明显大于常规间距处断开（分叉、断续段）
P = double(P);
if size(P, 1) < 2, X = P(:, 1); Y = P(:, 2); return; end
d = hypot(diff(P(:, 1)), diff(P(:, 2)));
thr = max(20, 4 * median(d));
X = P(1, 1); Y = P(1, 2);
for i = 2:size(P, 1)
    if d(i - 1) > thr
        X(end + 1, 1) = NaN; Y(end + 1, 1) = NaN; %#ok<AGROW>
    end
    X(end + 1, 1) = P(i, 1); Y(end + 1, 1) = P(i, 2); %#ok<AGROW>
end
end

function [X, Y] = pixel_segments(xy)
% 把中心线像素按 8 邻接连成线段（NaN 分隔），用于绘制清晰的矢量标注
x = double(xy(:, 1)); y = double(xy(:, 2));
K = y * 100000 + x;
X = []; Y = [];
D = [1 0; 0 1; 1 1; -1 1];
for d = 1:4
    [tf, loc] = ismember((y + D(d, 2)) * 100000 + x + D(d, 1), K);
    i1 = find(tf); i2 = loc(tf);
    n = numel(i1);
    X = [X; reshape([x(i1)'; x(i2)'; nan(1, n)], [], 1)]; %#ok<AGROW>
    Y = [Y; reshape([y(i1)'; y(i2)'; nan(1, n)], [], 1)]; %#ok<AGROW>
end
end

%% ======================================================================
%  缩放与平移
%  ======================================================================
function fit_zoom_state(fig)
S = getappdata(fig, 'S');
if S.sel == 0 || S.items(S.sel).W == 0, return; end
it = S.items(S.sel);
vw = S.L.view(3); vh = S.L.view(4);
s = max(it.W / vw, it.H / vh) * 1.02;
S.Z = struct('cx', (it.W + 1) / 2, 'cy', (it.H + 1) / 2, 'scale', s, 'fit', s, 'W', it.W, 'H', it.H);
setappdata(fig, 'S', S);
end

function apply_zoom(fig)
S = getappdata(fig, 'S');
Z = S.Z;
vw = S.L.view(3); vh = S.L.view(4);
Z.scale = min(max(Z.scale, 0.04), Z.fit * 1.6);
Z.cx = min(max(Z.cx, 1), max(1, Z.W));
Z.cy = min(max(Z.cy, 1), max(1, Z.H));
S.Z = Z;
setappdata(fig, 'S', S);
set(S.h.axView, 'XLim', Z.cx + [-1 1] * vw * Z.scale / 2, 'YLim', Z.cy + [-1 1] * vh * Z.scale / 2);
end

function zoom_fit(fig)
fit_zoom_state(fig);
apply_zoom(fig);
update_hires(fig);
draw_center(fig);
draw_overlay(fig);
end

function zoom_by(fig, f, p)
% 以图窗点 p（像素）为中心缩放；p 为空时以视图中心缩放
S = getappdata(fig, 'S');
if S.sel == 0 || S.Z.W == 0, return; end
vr = S.L.view;
if isempty(p), p = [vr(1) + vr(3) / 2, vr(2) + vr(4) / 2]; end
[dx, dy] = fig_to_data(S, p);
s2 = min(max(S.Z.scale / f, 0.04), S.Z.fit * 1.6);
S.Z.cx = dx - (p(1) - (vr(1) + vr(3) / 2)) * s2;
S.Z.cy = dy + (p(2) - (vr(2) + vr(4) / 2)) * s2;
S.Z.scale = s2;
setappdata(fig, 'S', S);
apply_zoom(fig);
draw_center(fig);
update_hires(fig);
draw_overlay(fig);
end

function [x, y] = fig_to_data(S, p)
vr = S.L.view;
x = S.Z.cx + (p(1) - (vr(1) + vr(3) / 2)) * S.Z.scale;
y = S.Z.cy - (p(2) - (vr(2) + vr(4) / 2)) * S.Z.scale;
end

function update_hires(fig)
% 放大到超过预览分辨率时，从原图裁剪可见区域叠加显示，保证细节清晰
S = getappdata(fig, 'S');
hHi = S.h.hHi;
if S.sel == 0 || ~any(strcmp(S.view, {'overlay', 'original'}))
    set(hHi, 'Visible', 'off'); return;
end
it = S.items(S.sel);
if isempty(it.preview), set(hHi, 'Visible', 'off'); return; end
pScale = it.W / size(it.preview, 2);
if S.Z.scale > 0.8 * pScale
    set(hHi, 'Visible', 'off'); return;
end
if S.full.k ~= S.sel || isempty(S.full.rgb)
    old = S.status;
    set_status(fig, '正在载入原图以显示细节…');
    drawnow;
    try
        RGB = read_rgb8(it.path);
    catch
        set_status(fig, old);
        return;
    end
    S = getappdata(fig, 'S');
    S.full = struct('k', S.sel, 'rgb', RGB);
    S.status = old;
    setappdata(fig, 'S', S);
    draw_status(fig);
end
xl = get(S.h.axView, 'XLim'); yl = get(S.h.axView, 'YLim');
mx = 0.4 * diff(xl); my = 0.4 * diff(yl);
x1 = max(1, floor(xl(1) - mx)); x2 = min(it.W, ceil(xl(2) + mx));
y1 = max(1, floor(yl(1) - my)); y2 = min(it.H, ceil(yl(2) + my));
if x2 <= x1 || y2 <= y1, set(hHi, 'Visible', 'off'); return; end
set(hHi, 'CData', S.full.rgb(y1:y2, x1:x2, :), 'XData', [x1 x2], 'YData', [y1 y2], 'Visible', 'on');
end

%% ======================================================================
%  右侧信息面板
%  ======================================================================
function draw_info(fig)
[ax, w, h] = begin_draw(fig, 'axInfo', 'info');
S = getappdata(fig, 'S'); T = S.T;
pad = 16;
rrect(ax, 0, 0, w, h, 14, T.card, T.border);
if S.sel == 0
    txt(ax, w / 2, h / 2 - 10, '选择左侧图片查看检测信息', 15, T.sub, 'HorizontalAlignment', 'center', 'FontWeight', 'bold');
    txt(ax, w / 2, h / 2 + 16, '判定 · 关键指标 · 裂纹位置', 12, T.muted, 'HorizontalAlignment', 'center');
    return;
end
it = S.items(S.sel);
st = status_style(it.status);
res = it.res;
% ---- 判定卡片 ----
cardH = 118;
rrect(ax, pad, pad, w - 2 * pad, cardH, 16, st.soft);
rrect(ax, pad, pad + 18, 5, cardH - 36, 2.5, st.main);
draw_icon(ax, st.icon, pad + 46, pad + 46, 22, st.main, [1 1 1]);
txt(ax, pad + 80, pad + 34, '检测判定', 12, st.text);
txt(ax, pad + 80, pad + 62, st.label, 30, st.text, 'FontWeight', 'bold');
switch it.status
    case 'crack'
        tl = sum([res.cracks.length_px]);
        sub = sprintf('检出 %d 条隐裂 · 总长 %s px', res.nCracks, fmt_int(tl));
    case 'no_crack'
        sub = '有效区域内未发现细暗线裂纹';
    case 'review'
        sub = '证据不足，请人工复核';
        if ~isempty(res) && ~isempty(res.reviewReasons), sub = res.reviewReasons{1}; end
    case 'running'
        sub = '正在检测，请稍候…';
    case 'error'
        sub = it.err;
    otherwise
        sub = '点击左侧“开始检测”分析此图';
end
txt(ax, pad + 18, pad + 96, ellip(sub, w - 2 * pad - 36, 13), 13, T.sub);
if ~isempty(res)
    if strcmp(it.method, 'baseline'), mm = '基线'; else, mm = '改进法'; end
    if strcmp(it.source, 'loaded'), src = '载入结果'; else, src = '本次检测'; end
    tag = sprintf('%s · %s', mm, src);
    if isfinite(it.runtime), tag = sprintf('%s · %.1f s', tag, it.runtime); end
    txt(ax, w - pad - 14, pad + 34, tag, 11, st.text, 'HorizontalAlignment', 'right');
end
y = pad + cardH + 12;
% ---- 参考标签 ----
if ~isnan(it.label)
    if it.label == 1, ls = '有隐裂'; else, ls = '无隐裂'; end
    txt(ax, pad, y + 12, '参考标签', 12, T.muted);
    cw = chip(ax, pad + 60, y + 12, ls, 11, hx('F1F5F9'), T.sub);
    if any(strcmp(it.status, {'crack', 'no_crack'}))
        agree = (it.label == 1) == strcmp(it.status, 'crack');
        if agree
            draw_icon(ax, 'check', pad + 60 + cw + 16, y + 12, 9, hx('D1FAE5'), hx('059669'));
            txt(ax, pad + 60 + cw + 30, y + 12, '与检测一致', 12, hx('047857'));
        else
            draw_icon(ax, 'cross', pad + 60 + cw + 16, y + 12, 9, hx('FFE4E6'), hx('E11D48'));
            txt(ax, pad + 60 + cw + 30, y + 12, '与检测不一致', 12, hx('BE123C'));
        end
    end
    txt(ax, w - pad, y + 12, '仅作对照', 11, T.muted, 'HorizontalAlignment', 'right');
    y = y + 30;
end
% ---- 指标卡片 ----
txt(ax, pad, y + 12, '图像与栅线', 14, T.text, 'FontWeight', 'bold');
y = y + 26;
vals = metric_values(it);
tw = (w - 2 * pad - 10) / 2; th = 56;
for i = 1:6
    col = mod(i - 1, 2); row = floor((i - 1) / 2);
    x = pad + col * (tw + 10); yy = y + row * (th + 8);
    rrect(ax, x, yy, tw, th, 10, T.faint, T.border);
    txt(ax, x + 12, yy + 17, vals{i, 1}, 11, T.muted);
    txt(ax, x + 12, yy + 39, vals{i, 2}, 18, T.text, 'FontWeight', 'bold');
    if ~isempty(vals{i, 3})
        txt(ax, x + 14 + text_w(vals{i, 2}, 18) * 0.98, yy + 41, vals{i, 3}, 11, T.muted);
    end
end
y = y + 3 * th + 2 * 8 + 10;
% ---- 说明（复核原因 / 备注） ----
notes = {};
if ~isempty(res)
    notes = [res.reviewReasons(:)', res.notes(:)'];
end
if strcmp(it.status, 'error') && ~isempty(it.err), notes = {it.err}; end
if ~isempty(notes)
    lines = wrap_text(strjoin(notes, '；'), w - 2 * pad - 34, 12, 2);
    nh = 16 + 18 * numel(lines);
    rrect(ax, pad, y, w - 2 * pad, nh, 10, hx('FFFBEB'), hx('FDE68A'));
    draw_icon(ax, 'alert', pad + 15, y + nh / 2, 7, hx('F59E0B'), [1 1 1]);
    for i = 1:numel(lines)
        txt(ax, pad + 30, y + 8 + 9 + (i - 1) * 18, lines{i}, 12, hx('92400E'));
    end
    y = y + nh + 10;
end
% ---- 裂纹列表 ----
metaH = 54;
listTop = y + 26; listBot = h - pad - metaH;
nCr = 0;
if ~isempty(res), nCr = res.nCracks; end
txt(ax, pad, y + 12, '裂纹列表', 14, T.text, 'FontWeight', 'bold');
chip(ax, pad + 66, y + 12, sprintf('%d', nCr), 11, st.soft, st.text);
if nCr > 0
    txt(ax, w - pad, y + 12, '点击定位', 11, T.muted, 'HorizontalAlignment', 'right');
end
rowH = 50; stride = 56;
nVis = max(1, floor((listBot - listTop + 6) / stride));
S = getappdata(fig, 'S');
S.crackOff = max(0, min(S.crackOff, nCr - nVis));
S.L.crackRect = local_rect(S.h.axInfo, [0, listTop, w, listBot - listTop]);
setappdata(fig, 'S', S);
if nCr == 0
    msg = '—';
    if strcmp(it.status, 'no_crack'), msg = '未检出裂纹'; end
    if strcmp(it.status, 'pending'), msg = '尚未检测'; end
    rrect(ax, pad, listTop, w - 2 * pad, 50, 10, T.faint, T.border);
    txt(ax, w / 2, listTop + 25, msg, 13, T.muted, 'HorizontalAlignment', 'center');
end
for v = 1:min(nVis, nCr - S.crackOff)
    i = S.crackOff + v;
    c = res.cracks(i);
    yy = listTop + (v - 1) * stride;
    isSel = i == S.selCrack;
    if isSel
        rrect(ax, pad, yy, w - 2 * pad, rowH, 10, hx('ECFEFF'), T.selLine, 1.5);
        bc = hx('0891B2');
    else
        rrect(ax, pad, yy, w - 2 * pad, rowH, 10, T.card, T.border);
        bc = st.main;
    end
    rrect(ax, pad + 10, yy + 12, 34, 26, 8, bc);
    txt(ax, pad + 27, yy + 25, sprintf('#%d', c.id), 12, [1 1 1], 'HorizontalAlignment', 'center', 'FontWeight', 'bold');
    l1 = sprintf('长 %s px  ·  %.0f°  ·  宽 %.1f px', fmt_int(c.length_px), c.angle_deg, c.width_px);
    txt(ax, pad + 54, yy + 17, ellip(l1, w - 2 * pad - 64, 13), 13, T.text, 'FontWeight', 'bold');
    b = c.bbox;
    if isfinite(c.contrast_pct)
        l2 = sprintf('对比度 %.1f%% · 跨 %.0f 根细栅 · (%d,%d)–(%d,%d)', c.contrast_pct, c.n_fingers_crossed, b(1), b(2), b(3), b(4));
    else
        l2 = sprintf('位置 (%d,%d)–(%d,%d)', b(1), b(2), b(3), b(4));
    end
    txt(ax, pad + 54, yy + 36, ellip(l2, w - 2 * pad - 64, 11), 11, T.sub);
    add_hit(fig, 'axInfo', 'info', [pad, yy, w - 2 * pad, rowH], 'crack', i);
end
if nCr > nVis
    trackH = nVis * stride - 6;
    rrect(ax, w - 8, listTop, 3, trackH, 1.5, hx('E2E8F0'));
    th2 = max(20, trackH * nVis / nCr);
    rrect(ax, w - 8, listTop + (trackH - th2) * S.crackOff / max(1, nCr - nVis), 3, th2, 1.5, hx('94A3B8'));
end
% ---- 文件信息 ----
line([pad w - pad], h - pad - metaH + 6 + [0 0], 'Parent', ax, 'Color', T.border, 'HitTest', 'off');
txt(ax, pad, h - pad - metaH + 24, '文件', 11, T.muted);
txt(ax, pad + 40, h - pad - metaH + 24, ellip(it.path, w - 2 * pad - 40, 11), 11, T.sub);
txt(ax, pad, h - pad - metaH + 44, '坐标', 11, T.muted);
txt(ax, pad + 40, h - pad - metaH + 44, '原图像素，左上角 (1,1)，x 为列、y 为行', 11, T.sub);
end

function V = metric_values(it)
V = {'细栅方向', '—', ''; '细栅间距', '—', ''; '有效区域', '—', ''; ...
     '亮缝 / 过曝', '—', ''; '裂纹数量', '—', ''; '裂纹总长', '—', ''};
if isempty(it.res), return; end
d = it.res.diag;
V(1, 2:3) = {sprintf('%.1f°', d.fingerAngleDeg), angle_word(d.fingerAngleDeg)};
V(2, 2:3) = {sprintf('%.1f', d.pitchFullPx), 'px'};
V(3, 2:3) = {sprintf('%.0f', 100 * d.validFrac), '%'};
V(4, 2:3) = {sprintf('%.0f', 100 * d.brightFrac), '%'};
V(5, 2:3) = {sprintf('%d', it.res.nCracks), '条'};
if it.res.nCracks > 0
    V(6, 2:3) = {fmt_int(sum([it.res.cracks.length_px])), 'px'};
else
    V(6, 2:3) = {'0', 'px'};
end
end

function s = angle_word(a)
d = min(abs(mod(a, 180) - 90), 90);    % 与竖直方向的夹角
if d <= 3, s = '竖直';
elseif d >= 87, s = '水平';
else, s = '倾斜';
end
end

%% ======================================================================
%  鼠标、键盘
%  ======================================================================
function in = in_rect(p, r)
in = p(1) >= r(1) && p(1) <= r(1) + r(3) && p(2) >= r(2) && p(2) <= r(2) + r(4);
end

function on_mouse_down(fig)
S = getappdata(fig, 'S');
p = get(fig, 'CurrentPoint');
for i = numel(S.hits):-1:1
    if in_rect(p, S.hits(i).rect)
        do_action(fig, S.hits(i).action, S.hits(i).arg);
        return;
    end
end
if S.sel > 0 && in_rect(p, S.L.view) && S.items(S.sel).W > 0
    if strcmp(get(fig, 'SelectionType'), 'open')
        zoom_fit(fig);
        return;
    end
    S.pan = struct('active', true, 'p0', p, 'c0', [S.Z.cx S.Z.cy], 'moved', false);
    setappdata(fig, 'S', S);
end
end

function on_mouse_move(fig)
S = getappdata(fig, 'S');
if isempty(S), return; end
p = get(fig, 'CurrentPoint');
if S.pan.active
    d = p - S.pan.p0;
    if any(abs(d) > 3), S.pan.moved = true; end
    S.Z.cx = S.pan.c0(1) - d(1) * S.Z.scale;
    S.Z.cy = S.pan.c0(2) + d(2) * S.Z.scale;
    setappdata(fig, 'S', S);
    apply_zoom(fig);
    S = getappdata(fig, 'S');
end
if S.sel > 0 && in_rect(p, S.L.view) && S.items(S.sel).W > 0
    [x, y] = fig_to_data(S, p);
    it = S.items(S.sel);
    if x >= 0.5 && y >= 0.5 && x <= it.W + 0.5 && y <= it.H + 0.5
        g = sample_gray(S, it, x, y);
        s = sprintf('x = %d   y = %d   灰度 = %.3f', round(x), round(y), g);
    else
        s = '';
    end
else
    s = '';
end
if ~strcmp(s, S.readout)
    S.readout = s;
    setappdata(fig, 'S', S);
    if isfield(S.h, 'readout') && ishghandle(S.h.readout)
        set(S.h.readout, 'String', s);
    end
end
end

function g = sample_gray(S, it, x, y)
xi = min(max(round(x), 1), it.W); yi = min(max(round(y), 1), it.H);
if S.full.k == S.sel && ~isempty(S.full.rgb)
    g = mean(double(S.full.rgb(yi, xi, :))) / 255;
else
    [ph, pw, ~] = size(it.preview);
    px = min(max(round((xi - 0.5) * pw / it.W + 0.5), 1), pw);
    py = min(max(round((yi - 0.5) * ph / it.H + 0.5), 1), ph);
    g = mean(double(it.preview(py, px, :))) / 255;
end
end

function on_mouse_up(fig)
S = getappdata(fig, 'S');
if isempty(S) || ~S.pan.active, return; end
moved = S.pan.moved;
S.pan.active = false;
setappdata(fig, 'S', S);
if moved
    update_hires(fig);
    return;
end
% 单击：选中最近的裂纹（屏幕距离 12 像素以内）
if ~strcmp(S.view, 'overlay') || isempty(S.items(S.sel).res), return; end
[x, y] = fig_to_data(S, S.pan.p0);
cr = S.items(S.sel).res.cracks;
best = 0; bd = inf;
for i = 1:numel(cr)
    P = double(cr(i).pixel_xy);
    if isempty(P), P = double(cr(i).points); end
    if isempty(P), continue; end
    d = min((P(:, 1) - x).^2 + (P(:, 2) - y).^2);
    if d < bd, bd = d; best = i; end
end
if best > 0 && sqrt(bd) / S.Z.scale <= 12
    select_crack(fig, best, false);
elseif S.selCrack > 0
    select_crack(fig, 0, false);
end
end

function on_wheel(fig, e)
S = getappdata(fig, 'S');
p = get(fig, 'CurrentPoint');
n = 0;
try, n = e.VerticalScrollCount; catch, end
if n == 0, return; end
if isfield(S.L, 'galRect') && in_rect(p, S.L.galRect)
    S.galOff = S.galOff + sign(n);
    setappdata(fig, 'S', S);
    draw_side(fig);
elseif isfield(S.L, 'crackRect') && in_rect(p, S.L.crackRect)
    S.crackOff = S.crackOff + sign(n);
    setappdata(fig, 'S', S);
    draw_info(fig);
elseif S.sel > 0 && in_rect(p, S.L.view)
    zoom_by(fig, 1.25 ^ (-n), p);
end
end

function on_key(fig, e)
S = getappdata(fig, 'S');
try
    k = lower(e.Key);
catch
    return;
end
switch k
    case {'uparrow', 'leftarrow', 'up', 'left'}
        if S.sel > 1, select_item(fig, S.sel - 1, true); end
    case {'downarrow', 'rightarrow', 'down', 'right'}
        if S.sel < numel(S.items), select_item(fig, S.sel + 1, true); end
    case 'f'
        zoom_fit(fig);
    case 'r'
        run_detection(fig, 'selected', false);
    case 'escape'
        select_crack(fig, 0, false);
    case {'1', '2', '3', '4', '5', '6'}
        V = view_defs();
        set_view(fig, V{str2double(k), 1});
    case {'add', 'equal'}
        zoom_by(fig, 1.25, []);
    case {'subtract', 'hyphen', 'minus'}
        zoom_by(fig, 0.8, []);
end
end

function do_action(fig, action, arg)
S = getappdata(fig, 'S');
switch action
    case 'select'
        if S.running, S.userPicked = true; setappdata(fig, 'S', S); end
        select_item(fig, arg, true);
    case 'crack'
        select_crack(fig, arg, true);
    case 'view'
        V = view_defs();
        set_view(fig, V{arg, 1});
    case 'fit'
        zoom_fit(fig);
    case 'one'
        if S.sel > 0
            zoom_by(fig, S.Z.scale, []);
        end
    case 'in'
        zoom_by(fig, 1.4, []);
    case 'out'
        zoom_by(fig, 1 / 1.4, []);
    case 'clear'
        clear_items(fig);
    case 'demo'
        load_demo(fig, true);
    case 'demoimgs'
        load_demo(fig, false);
end
end

function on_close(fig)
if ~ishghandle(fig), return; end
S = getappdata(fig, 'S');
if ~isempty(S) && S.running
    S.stop = true;
    setappdata(fig, 'S', S);
end
delete(fig);
end

%% ======================================================================
%  选择、视图
%  ======================================================================
function select_item(fig, k, refit)
S = getappdata(fig, 'S');
if k < 1 || k > numel(S.items), return; end
changed = S.sel ~= k;
S.sel = k;
if changed
    S.selCrack = 0; S.crackOff = 0;
    if S.full.k ~= k, S.full = struct('k', 0, 'rgb', []); end
end
it = S.items(k);
if ~view_available(it, S.view), S.view = 'overlay'; end
% 让选中项在列表中可见
nVis = 1;
if isfield(S.L, 'galVis'), nVis = S.L.galVis; end
if k <= S.galOff, S.galOff = k - 1; end
if k > S.galOff + nVis, S.galOff = k - nVis; end
setappdata(fig, 'S', S);
if isempty(it.preview)
    ensure_preview(fig, k);
end
if changed || refit
    fit_zoom_state(fig);
end
draw_side(fig);
draw_center(fig);
draw_viewer(fig);
draw_info(fig);
end

function select_crack(fig, i, zoomTo)
S = getappdata(fig, 'S');
if S.sel == 0, return; end
it = S.items(S.sel);
if isempty(it.res) || i > it.res.nCracks, return; end
S.selCrack = i;
if i > 0
    if ~strcmp(S.view, 'overlay'), S.view = 'overlay'; end
    nVis = 6;
    if isfield(S.L, 'crackRect'), nVis = max(1, floor((S.L.crackRect(4) + 6) / 56)); end
    if i <= S.crackOff, S.crackOff = i - 1; end
    if i > S.crackOff + nVis, S.crackOff = i - nVis; end
    if zoomTo
        b = double(it.res.cracks(i).bbox);
        vw = S.L.view(3); vh = S.L.view(4);
        s = max([(b(3) - b(1) + 1) * 1.5 / vw, (b(4) - b(2) + 1) * 1.5 / vh, 0.25]);
        S.Z.scale = min(s, S.Z.fit);
        S.Z.cx = (b(1) + b(3)) / 2; S.Z.cy = (b(2) + b(4)) / 2;
    end
end
setappdata(fig, 'S', S);
draw_center(fig);
draw_viewer(fig);
draw_info(fig);
end

function set_view(fig, v)
S = getappdata(fig, 'S');
V = view_defs();
if ~any(strcmp(V(:, 1), v)), return; end
if S.sel > 0 && ~view_available(S.items(S.sel), v), return; end
S.view = v;
setappdata(fig, 'S', S);
draw_center(fig);
draw_viewer(fig);
end

function set_method(fig, m)
S = getappdata(fig, 'S');
if S.running, return; end
S.method = m;
set(S.h.pMethod, 'Value', 1 + strcmp(m, 'baseline'));
setappdata(fig, 'S', S);
draw_header(fig);
n = 0;
for k = 1:numel(S.items)
    if ~isempty(S.items(k).res) && ~strcmp(S.items(k).method, m), n = n + 1; end
end
if n > 0
    set_status(fig, sprintf('已切换为%s；有 %d 张图片的结果来自另一种方法，点击“开始检测”可重新检测全部', method_name(m), n));
else
    set_status(fig, sprintf('已切换为%s', method_name(m)));
end
end

function s = method_name(m)
if strcmp(m, 'baseline'), s = '基线方法'; else, s = '改进法'; end
end

function on_method(fig)
S = getappdata(fig, 'S');
v = get(S.h.pMethod, 'Value');
if v == 2, set_method(fig, 'baseline'); else, set_method(fig, 'improved'); end
end

%% ======================================================================
%  添加图片、生成预览
%  ======================================================================
function on_add_files(fig)
filt = {'*.jpg;*.jpeg;*.png;*.bmp;*.tif;*.tiff;*.JPG;*.JPEG;*.PNG;*.BMP;*.TIF;*.TIFF', '图像文件'};
[f, d] = uigetfile(filt, '选择电池片图片（可多选）', 'MultiSelect', 'on');
if isequal(f, 0), return; end
if ischar(f), f = {f}; end
add_paths(fig, cellfun(@(x) fullfile(d, x), f, 'UniformOutput', false));
end

function on_add_folder(fig)
S = getappdata(fig, 'S');
d = uigetdir(S.root, '选择包含电池片图片的文件夹');
if isequal(d, 0), return; end
add_folder(fig, d);
end

function add_folder(fig, d)
files = list_images({d}, false);
if isempty(files)
    set_status(fig, sprintf('文件夹中没有找到图像：%s', d));
    return;
end
add_paths(fig, {files.path});
end

function added = add_paths(fig, paths)
if ischar(paths), paths = {paths}; end
S = getappdata(fig, 'S');
if S.running, return; end
added = 0;
have = {S.items.path};
for i = 1:numel(paths)
    p = paths{i};
    if exist(p, 'file') ~= 2 || any(strcmp(have, p)), continue; end
    it = new_item(p);
    j = find(strcmp(S.labels.keys, it.key), 1);
    if ~isempty(j), it.label = S.labels.vals(j); end
    S.items(end + 1) = it;
    have{end + 1} = p; %#ok<AGROW>
    added = added + 1;
end
first = S.sel == 0 && ~isempty(S.items);
setappdata(fig, 'S', S);
set_status(fig, sprintf('已添加 %d 张图片，共 %d 张', added, numel(S.items)));
if first
    select_item(fig, 1, true);
else
    draw_side(fig);
    draw_center(fig);
end
ensure_previews(fig);
end

function ensure_preview(fig, k)
S = getappdata(fig, 'S');
it = S.items(k);
try
    RGB = read_rgb8(it.path);
catch err
    S.items(k).status = 'error';
    S.items(k).err = ['读取失败：' err.message];
    setappdata(fig, 'S', S);
    return;
end
S = getappdata(fig, 'S');
[S.items(k).preview, S.items(k).thumb] = make_previews(RGB);
S.items(k).H = size(RGB, 1); S.items(k).W = size(RGB, 2);
if k == S.sel, S.full = struct('k', k, 'rgb', RGB); end
setappdata(fig, 'S', S);
end

function [P, Th] = make_previews(RGB)
% 预览：按整数倍块平均缩小到长边约 1400–1600 像素；缩略图：78×52 居中裁剪
[H, W, ~] = size(RGB);
P = block_reduce(RGB, max(1, ceil(max(H, W) / 1600)));
tw = 78; th = 52;
k2 = max(tw / size(P, 2), th / size(P, 1));
T = zeros(max(th, round(size(P, 1) * k2)), max(tw, round(size(P, 2) * k2)), 3, 'uint8');
for c = 1:3
    T(:, :, c) = uint8(resize_img(double(P(:, :, c)), k2));
end
y0 = floor((size(T, 1) - th) / 2); x0 = floor((size(T, 2) - tw) / 2);
Th = T(y0 + (1:th), x0 + (1:tw), :);
end

function ensure_previews(fig)
S = getappdata(fig, 'S');
if S.previewBusy, return; end
S.previewBusy = true;
setappdata(fig, 'S', S);
while true
    if ~ishghandle(fig), return; end
    S = getappdata(fig, 'S');
    todo = find(arrayfun(@(x) isempty(x.thumb) && ~strcmp(x.status, 'error'), S.items));
    if isempty(todo), break; end
    % 优先处理当前可见的
    nv = 6;
    if isfield(S.L, 'galVis'), nv = S.L.galVis; end
    vis = S.galOff + (1:nv);
    pick = todo(ismember(todo, [S.sel vis]));
    if isempty(pick), pick = todo; end
    k = pick(1);
    if ~S.running
        set_status(fig, sprintf('正在生成预览 %d / %d：%s', numel(S.items) - numel(todo) + 1, numel(S.items), S.items(k).name));
    end
    ensure_preview(fig, k);
    S = getappdata(fig, 'S');
    if k == S.sel
        fit_zoom_state(fig);
        draw_center(fig);
        draw_viewer(fig);
        draw_info(fig);
    end
    draw_side(fig);
    drawnow;
end
S = getappdata(fig, 'S');
S.previewBusy = false;
setappdata(fig, 'S', S);
if ~S.running
    set_status(fig, sprintf('共 %d 张图片 · 点击“开始检测”分析待检测的图片', numel(S.items)));
end
end

function clear_items(fig)
S = getappdata(fig, 'S');
if S.running, return; end
S.items(:) = [];
S.sel = 0; S.selCrack = 0; S.galOff = 0; S.crackOff = 0;
S.full = struct('k', 0, 'rgb', []);
S.view = 'overlay';
setappdata(fig, 'S', S);
set_status(fig, '已清空图片列表');
redraw_all(fig);
end

%% ======================================================================
%  检测
%  ======================================================================
function run_detection(fig, which, interactive)
S = getappdata(fig, 'S');
if S.running
    S.stop = true;
    setappdata(fig, 'S', S);
    set_status(fig, '将在当前图片完成后停止…');
    return;
end
if isempty(S.items)
    set_status(fig, '请先添加图片');
    return;
end
codes = {S.items.status};
if strcmp(which, 'all')
    idx = 1:numel(S.items);
elseif strcmp(which, 'selected')
    idx = S.sel;
    if idx == 0, return; end
else
    idx = find(strcmp(codes, 'pending') | arrayfun(@(x) ~isempty(x.res) && ~strcmp(x.method, S.method), S.items));
end
if isempty(idx) && ~strcmp(which, 'selected')
    if interactive
        a = questdlg(sprintf('所有图片都已用%s检测过。是否重新检测全部 %d 张？', method_name(S.method), numel(S.items)), ...
            '重新检测', '重新检测', '取消', '取消');
        if ~strcmp(a, '重新检测'), return; end
    end
    idx = 1:numel(S.items);
end
S.running = true; S.stop = false; S.userPicked = false;
setappdata(fig, 'S', S);
set_busy(fig, true);
nTot = numel(idx);
tStart = tic;
nDone = 0;
for n = 1:nTot
    if ~ishghandle(fig), return; end
    S = getappdata(fig, 'S');
    if S.stop, break; end
    k = idx(n);
    S.items(k).status = 'running';
    if ~S.userPicked, S.sel = 0; end
    setappdata(fig, 'S', S);
    if ~S.userPicked, select_item(fig, k, true); else, draw_side(fig); end
    eta = '';
    if nDone > 0, eta = sprintf('，预计剩余 %.0f 秒', toc(tStart) / nDone * (nTot - n + 1)); end
    set_status(fig, sprintf('正在检测 %d / %d：%s%s', n, nTot, S.items(k).name, eta), [n - 1, nTot]);
    drawnow;
    errMsg = '';
    try
        [G, RGB] = read_gray(S.items(k).path);
        t0 = tic;
        if strcmp(S.method, 'baseline')
            res = detect_baseline(G, S.cfg, true);
        else
            res = detect_cracks(G, S.cfg, true);
        end
        P = debug_previews(res.debug, size(G), 1000);
        rt = toc(t0);
    catch err
        errMsg = err.message;
    end
    if ~ishghandle(fig), return; end
    S = getappdata(fig, 'S');
    it = S.items(k);
    if isempty(errMsg)
        if isempty(it.preview)
            [it.preview, it.thumb] = make_previews(RGB);
            it.H = size(RGB, 1); it.W = size(RGB, 2);
        end
        it.res = slim_result(res);
        it.dbg = P;
        it.maskIdx = uint32(find(res.mask));
        it.status = res.statusCode;
        it.source = 'detected';
        it.method = S.method;
        it.runtime = rt;
        it.err = '';
        if k == S.sel, S.full = struct('k', k, 'rgb', RGB); end
    else
        it.status = 'error';
        it.err = ['处理失败：' errMsg];
    end
    S.items(k) = it;
    S.selCrack = 0;
    setappdata(fig, 'S', S);
    clear G RGB res P
    nDone = nDone + 1;
    set_status(fig, sprintf('已完成 %d / %d', n, nTot), [n, nTot]);
    if S.sel == k
        draw_center(fig); draw_viewer(fig); draw_info(fig);
    end
    draw_side(fig);
    drawnow;
end
if ~ishghandle(fig), return; end
S = getappdata(fig, 'S');
stopped = S.stop;
S.running = false; S.stop = false;
setappdata(fig, 'S', S);
set_busy(fig, false);
codes = {S.items.status};
msg = sprintf('检测%s：%d 张用时 %.0f 秒 · 有隐裂 %d · 无隐裂 %d · 待复核 %d · 失败 %d', ...
    pick_str(stopped, '已停止', '完成'), nDone, toc(tStart), nnz(strcmp(codes, 'crack')), ...
    nnz(strcmp(codes, 'no_crack')), nnz(strcmp(codes, 'review')), nnz(strcmp(codes, 'error')));
S.status = msg; S.progress = [];
for k = 1:numel(S.items)
    if strcmp(S.items(k).status, 'running'), S.items(k).status = 'pending'; end
end
setappdata(fig, 'S', S);
redraw_all(fig);
end

function s = pick_str(c, a, b)
if c, s = a; else, s = b; end
end

function r = slim_result(res)
% 界面只保留显示与导出需要的字段（掩膜以下标形式另存，避免占用大量内存）
r = struct('statusCode', res.statusCode, 'status', res.status, 'nCracks', res.nCracks, ...
    'cracks', norm_cracks(res.cracks), 'reviewReasons', {res.reviewReasons}, 'notes', {res.notes}, ...
    'diag', res.diag);
end

function C = norm_cracks(cr)
C = struct('id', {}, 'bbox', {}, 'centroid', {}, 'length_px', {}, 'width_px', {}, 'angle_deg', {}, ...
    'mean_z', {}, 'contrast_pct', {}, 'n_fingers_crossed', {}, 'endpoints', {}, 'points', {}, 'pixel_xy', {});
if isempty(cr), return; end
if iscell(cr)
    cc = cr;
else
    cc = num2cell(cr);
end
for i = 1:numel(cc)
    c = cc{i};
    n = struct('id', c.id, 'bbox', double(c.bbox(:)'), 'centroid', double(c.centroid(:)'), ...
        'length_px', c.length_px, 'width_px', c.width_px, 'angle_deg', c.angle_deg, ...
        'mean_z', getf(c, 'mean_z', NaN), 'contrast_pct', getf(c, 'contrast_pct', NaN), ...
        'n_fingers_crossed', getf(c, 'n_fingers_crossed', NaN), ...
        'endpoints', reshape_pts(getf(c, 'endpoints', [])), 'points', reshape_pts(getf(c, 'points', [])), ...
        'pixel_xy', getf(c, 'pixel_xy', []));
    C(end + 1) = n; %#ok<AGROW>
end
end

function v = getf(s, f, d)
if isfield(s, f) && ~isempty(s.(f)), v = s.(f); else, v = d; end
end

function P = reshape_pts(P)
P = double(P);
if isempty(P), P = zeros(0, 2); return; end
if size(P, 2) ~= 2 && numel(P) == 2, P = P(:)'; end
end

function set_busy(fig, busy)
S = getappdata(fig, 'S');
h = S.h;
others = [h.bAddFiles h.bAddFolder h.bLoad h.bExport h.pMethod];
if busy
    set(others, 'Enable', 'off');
    set(h.bRun, 'String', '停止检测', 'BackgroundColor', S.T.danger);
else
    set(others, 'Enable', 'on');
    set(h.bRun, 'String', '开始检测', 'BackgroundColor', S.T.accent);
end
draw_side(fig);
end

%% ======================================================================
%  载入已有结果、示例
%  ======================================================================
function on_load_results(fig)
S = getappdata(fig, 'S');
start = fullfile(S.root, 'outputs');
if exist(start, 'dir') ~= 7, start = S.root; end
d = uigetdir(start, '选择包含 defects.json 的结果文件夹（如 outputs 或 outputs/baseline）');
if isequal(d, 0), return; end
load_results(fig, d);
end

function load_demo(fig, withResults)
S = getappdata(fig, 'S');
dirs = {fullfile(S.root, 'cracked'), fullfile(S.root, 'uncracked')};
dirs = dirs(cellfun(@(d) exist(d, 'dir') == 7, dirs));
if isempty(dirs), return; end
files = list_images(dirs, false);
if withResults && exist(fullfile(S.root, 'outputs', 'defects.json'), 'file') == 2
    S = getappdata(fig, 'S');
    S.previewBusy = true;          % 先挂上结果再统一生成预览
    setappdata(fig, 'S', S);
    add_paths(fig, {files.path});
    S = getappdata(fig, 'S'); S.previewBusy = false; setappdata(fig, 'S', S);
    load_results(fig, fullfile(S.root, 'outputs'));
else
    add_paths(fig, {files.path});
end
end

function load_results(fig, d)
S = getappdata(fig, 'S');
if S.running, return; end
jp = fullfile(d, 'defects.json');
if exist(jp, 'file') ~= 2
    set_status(fig, sprintf('没有找到 %s', jp));
    return;
end
try
    J = jsondecode(read_text_utf8(jp));
catch err
    set_status(fig, ['读取结果失败：' err.message]);
    return;
end
imgs = J.images;
if isstruct(imgs), imgs = num2cell(imgs); end
method = 'improved';
if isfield(J, 'method'), method = J.method; end
nNew = 0; nHit = 0;
for i = 1:numel(imgs)
    im = imgs{i};
    S = getappdata(fig, 'S');
    key = lower(im.file);
    k = find(strcmp({S.items.key}, key), 1);
    if isempty(k)
        p = resolve_path(S.root, d, im.file);
        if isempty(p), continue; end
        add_paths_silent(fig, p);
        S = getappdata(fig, 'S');
        k = numel(S.items);
        nNew = nNew + 1;
    end
    it = S.items(k);
    if strcmp(im.status_code, 'error')
        it.status = 'error'; it.err = im.error;
    else
        it.res = loaded_result(im);
        it.status = im.status_code;
        it.source = 'loaded';
        it.method = method;
        it.dbg = [];
        it.maskIdx = [];
        it.runtime = NaN;
        if isfield(im, 'diagnostics') && isfield(im.diagnostics, 'runtime_s')
            it.runtime = im.diagnostics.runtime_s;
        end
        if isfield(im, 'image_size') && numel(im.image_size) == 2 && it.W == 0
            it.W = im.image_size(1); it.H = im.image_size(2);
        end
    end
    S.items(k) = it;
    setappdata(fig, 'S', S);
    nHit = nHit + 1;
end
S = getappdata(fig, 'S');
S.status = sprintf('已载入 %d 条%s结果（%s）', nHit, method_name(method), jp);
cur = max(1, S.sel);
S.sel = 0;
setappdata(fig, 'S', S);
if ~isempty(S.items)
    select_item(fig, min(cur, numel(S.items)), true);
end
redraw_all(fig);
ensure_previews(fig);
end

function add_paths_silent(fig, p)
S = getappdata(fig, 'S');
it = new_item(p);
j = find(strcmp(S.labels.keys, it.key), 1);
if ~isempty(j), it.label = S.labels.vals(j); end
S.items(end + 1) = it;
setappdata(fig, 'S', S);
end

function p = resolve_path(root, d, rel)
cands = {fullfile(root, rel), fullfile(d, rel), fullfile(fileparts(d), rel), fullfile(fileparts(fileparts(d)), rel)};
p = '';
for i = 1:numel(cands)
    if exist(cands{i}, 'file') == 2
        p = cands{i};
        return;
    end
end
end

function r = loaded_result(im)
dg = struct('fingerAngleDeg', NaN, 'pitchFullPx', NaN, 'validFrac', NaN, 'brightFrac', NaN, ...
    'gridOk', true, 'periodicity', NaN, 'workScale', NaN, 'nCandidates', NaN);
if isfield(im, 'diagnostics') && isstruct(im.diagnostics)
    q = im.diagnostics;
    dg.fingerAngleDeg = getf(q, 'finger_angle_deg', NaN);
    dg.pitchFullPx = getf(q, 'pitch_px', NaN);
    dg.validFrac = getf(q, 'valid_frac', NaN);
    dg.brightFrac = getf(q, 'bright_frac', NaN);
    dg.gridOk = getf(q, 'grid_ok', true);
    dg.periodicity = getf(q, 'grid_periodicity', NaN);
    dg.workScale = getf(q, 'work_scale', NaN);
    dg.nCandidates = getf(q, 'n_candidates', NaN);
end
r = struct('statusCode', im.status_code, 'status', im.status, 'nCracks', im.n_cracks, ...
    'cracks', norm_cracks(getf(im, 'cracks', [])), 'reviewReasons', {to_cellstr(getf(im, 'review_reasons', {}))}, ...
    'notes', {to_cellstr(getf(im, 'notes', {}))}, 'diag', dg);
r.nCracks = numel(r.cracks);
end

function c = to_cellstr(x)
if isempty(x), c = {};
elseif ischar(x), c = {x};
else, c = x(:)';
end
end

%% ======================================================================
%  导出
%  ======================================================================
function on_export(fig)
S = getappdata(fig, 'S');
d = uigetdir(S.root, '选择导出文件夹');
if isequal(d, 0), return; end
export_results(fig, d);
end

function export_results(fig, outDir)
S = getappdata(fig, 'S');
sel = find(strcmp({S.items.source}, 'detected'));
if isempty(sel)
    set_status(fig, '没有本次检测的结果可导出（载入的结果在原输出目录中已有）');
    return;
end
if exist(outDir, 'dir') ~= 7, mkdir(outDir); end
for sub = {'overlays', 'masks'}
    if exist(fullfile(outDir, sub{1}), 'dir') ~= 7, mkdir(fullfile(outDir, sub{1})); end
end
recs = struct([]);
details = {};
for n = 1:numel(sel)
    k = sel(n);
    it = S.items(k);
    set_status(fig, sprintf('正在导出 %d / %d：%s', n, numel(sel), it.name), [n - 1, numel(sel)]);
    drawnow;
    [r, detail] = empty_record(it.relpath, it.stem);
    try
        RGB = read_rgb8(it.path);
        res = it.res;
        res.mask = false(it.H, it.W);
        res.mask(it.maskIdx) = true;
        res.centerline = false(it.H, it.W);
        for i = 1:numel(res.cracks)
            xy = double(res.cracks(i).pixel_xy);
            if ~isempty(xy), res.centerline(sub2ind([it.H it.W], xy(:, 2), xy(:, 1))) = true; end
        end
        O = make_overlay(RGB, res, it.method);
        ovRel = ['overlays/' it.stem '.jpg']; mkRel = ['masks/' it.stem '.png'];
        imwrite(O, fullfile(outDir, ovRel), 'Quality', S.cfg.overlayQuality);
        imwrite(res.mask, fullfile(outDir, mkRel));
        [r, detail] = fill_record(r, detail, res, [it.H it.W], it.runtime, ovRel, mkRel);
    catch err
        r.status = '处理失败'; r.status_code = 'error'; r.error = csv_clean(err.message);
        detail.status = r.status; detail.error = r.error;
    end
    if isempty(recs)
        recs = struct('rec', r, 'detail', detail);
    else
        recs(end + 1) = struct('rec', r, 'detail', detail); %#ok<AGROW>
    end
    details{end + 1} = detail; %#ok<AGROW>
end
info = env_info();
write_results_csv(fullfile(outDir, 'results.csv'), recs);
methods = unique({S.items(sel).method});
write_defects_json(fullfile(outDir, 'defects.json'), strjoin(methods, '+'), info, details);
write_json(fullfile(outDir, 'run_config.json'), struct('source', 'crack_app', 'environment', info, 'config', S.cfg));
skipped = nnz(strcmp({S.items.source}, 'loaded'));
msg = sprintf('已导出 %d 张图片的结果到 %s', numel(sel), outDir);
if skipped > 0, msg = sprintf('%s（%d 张载入的结果未重复导出）', msg, skipped); end
set_status(fig, msg, []);
end
