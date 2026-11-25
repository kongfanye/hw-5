function fig = show_results_viewer(files, outDir)
%SHOW_RESULTS_VIEWER  交互式双栏检测结果浏览器（MATLAB 桌面端验收专用）。
%   左侧显示原始图像，右侧显示隐裂标注叠加图，双栏坐标联动缩放（linkaxes）：
%   助教使用工具栏放大镜放大右侧任意标记框时，左侧原图同步放大到同一像素位置，
%   便于直接核对红线覆盖下的原始暗色裂纹。
%   支持按钮切换、键盘左右方向键翻页、一键筛选"仅看有缺陷"。
fig = [];
if ~can_open_figure()
    return;
end
jsonPath = fullfile(outDir, 'defects.json');
if exist(jsonPath, 'file') ~= 2 || isempty(files)
    return;
end
J = jsondecode(read_text_utf8(jsonPath));
imgs = J.images;
if isstruct(imgs), imgs = num2cell(imgs); end
if isempty(imgs), return; end

st = struct();
st.outDir = outDir;
st.allItems = imgs;
st.files = files;
st.onlyDefect = false;
st.activeIdx = 1:numel(imgs);
st.pos = 1;

fig = figure('Name', '太阳能电池片内部缺陷（隐裂）检测验收视图', ...
    'NumberTitle', 'off', 'Color', [0.14 0.14 0.16], ...
    'Units', 'normalized', 'Position', [0.05 0.08 0.90 0.82], ...
    'Toolbar', 'figure', 'WindowKeyPressFcn', @on_key);

st.lblBanner = uicontrol(fig, 'Style', 'text', 'Units', 'normalized', ...
    'Position', [0.02 0.93 0.96 0.055], 'String', '', ...
    'BackgroundColor', [0.14 0.14 0.16], 'ForegroundColor', [1 1 1], ...
    'FontSize', 13, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');

st.axOrig = axes('Parent', fig, 'Units', 'normalized', 'Position', [0.03 0.13 0.455 0.77]);
st.axOver = axes('Parent', fig, 'Units', 'normalized', 'Position', [0.515 0.13 0.455 0.77]);

st.lblInfo = uicontrol(fig, 'Style', 'text', 'Units', 'normalized', ...
    'Position', [0.03 0.062 0.94 0.045], 'String', '', ...
    'BackgroundColor', [0.14 0.14 0.16], 'ForegroundColor', [0.88 0.88 0.90], ...
    'FontSize', 10, 'HorizontalAlignment', 'center');

uicontrol(fig, 'Style', 'pushbutton', 'Units', 'normalized', ...
    'Position', [0.18 0.012 0.14 0.045], 'String', '◀ 上一张 (←)', ...
    'FontSize', 10, 'Callback', @(~, ~) step_page(fig, -1));

uicontrol(fig, 'Style', 'pushbutton', 'Units', 'normalized', ...
    'Position', [0.34 0.012 0.14 0.045], 'String', '下一张 (→) ▶', ...
    'FontSize', 10, 'Callback', @(~, ~) step_page(fig, 1));

st.btnFilter = uicontrol(fig, 'Style', 'pushbutton', 'Units', 'normalized', ...
    'Position', [0.50 0.012 0.16 0.045], 'String', sprintf('筛选：全部样本 (%d)', numel(imgs)), ...
    'FontSize', 10, 'Callback', @(~, ~) toggle_filter(fig));

uicontrol(fig, 'Style', 'pushbutton', 'Units', 'normalized', ...
    'Position', [0.68 0.012 0.14 0.045], 'String', '重置全景 (R)', ...
    'FontSize', 10, 'Callback', @(~, ~) reset_view(fig));

setappdata(fig, 'viewerState', st);
render_current(fig);
end

function tf = can_open_figure()
tf = false;
if exist('OCTAVE_VERSION', 'builtin') ~= 0
    try
        tf = isguirunning();
    catch
        tf = false;
    end
else
    try
        tf = usejava('desktop');
    catch
        tf = false;
    end
end
end

function step_page(fig, delta)
if ~ishandle(fig), return; end
st = getappdata(fig, 'viewerState');
if isempty(st.activeIdx), return; end
st.pos = mod(st.pos - 1 + delta, numel(st.activeIdx)) + 1;
setappdata(fig, 'viewerState', st);
render_current(fig);
end

function toggle_filter(fig)
if ~ishandle(fig), return; end
st = getappdata(fig, 'viewerState');
st.onlyDefect = ~st.onlyDefect;
if st.onlyDefect
    keep = cellfun(@(x) strcmp(x.status_code, 'crack') || strcmp(x.status_code, 'review'), st.allItems);
    if ~any(keep)
        st.onlyDefect = false;
        set(st.btnFilter, 'String', '筛选：全部样本(无缺陷项)');
        setappdata(fig, 'viewerState', st);
        return;
    end
    st.activeIdx = find(keep);
    set(st.btnFilter, 'String', sprintf('筛选：仅缺陷/复核 (%d)', numel(st.activeIdx)));
else
    st.activeIdx = 1:numel(st.allItems);
    set(st.btnFilter, 'String', sprintf('筛选：全部样本 (%d)', numel(st.activeIdx)));
end
st.pos = 1;
setappdata(fig, 'viewerState', st);
render_current(fig);
end

function reset_view(fig)
if ~ishandle(fig), return; end
st = getappdata(fig, 'viewerState');
if isfield(st, 'imgW') && st.imgW > 0
    set(st.axOrig, 'XLim', [0.5, st.imgW + 0.5], 'YLim', [0.5, st.imgH + 0.5]);
    set(st.axOver, 'XLim', [0.5, st.imgW + 0.5], 'YLim', [0.5, st.imgH + 0.5]);
end
end

function on_key(fig, evt)
if ~isfield(evt, 'Key') && ~isprop(evt, 'Key'), return; end
switch lower(evt.Key)
    case {'rightarrow', 'downarrow', 'n', 'space', 'pagedown'}
        step_page(fig, 1);
    case {'leftarrow', 'uparrow', 'p', 'pageup'}
        step_page(fig, -1);
    case 'r'
        reset_view(fig);
    case 'f'
        toggle_filter(fig);
end
end

function render_current(fig)
st = getappdata(fig, 'viewerState');
idx = st.activeIdx(st.pos);
item = st.allItems{idx};

% 读取原图与标注叠加图
origRGB = [];
if idx <= numel(st.files) && strcmp(st.files(idx).relpath, item.file) && exist(st.files(idx).path, 'file') == 2
    [~, origRGB] = read_gray(st.files(idx).path);
else
    hit = find(strcmp({st.files.relpath}, item.file), 1);
    if ~isempty(hit) && exist(st.files(hit).path, 'file') == 2
        [~, origRGB] = read_gray(st.files(hit).path);
    end
end
ovPath = fullfile(st.outDir, strrep(item.overlay, '/', filesep));
if exist(ovPath, 'file') == 2
    overRGB = imread(ovPath);
else
    overRGB = origRGB;
end
if isempty(origRGB), origRGB = overRGB; end
if isempty(origRGB), return; end

[H, W, ~] = size(overRGB);
st.imgH = H; st.imgW = W;

try linkaxes([st.axOrig, st.axOver], 'off'); catch, end
cla(st.axOrig);
image(origRGB, 'Parent', st.axOrig);
axis(st.axOrig, 'image');
set(st.axOrig, 'XLim', [0.5, W + 0.5], 'YLim', [0.5, H + 0.5], ...
    'XColor', [0.75 0.75 0.78], 'YColor', [0.75 0.75 0.78], 'FontSize', 9);
title(st.axOrig, '原始电池片图像（使用放大镜可双图同步缩放核对）', ...
    'Color', [0.92 0.92 0.95], 'FontSize', 11, 'Interpreter', 'none');

cla(st.axOver);
image(overRGB, 'Parent', st.axOver);
axis(st.axOver, 'image');
set(st.axOver, 'XLim', [0.5, W + 0.5], 'YLim', [0.5, H + 0.5], ...
    'XColor', [0.75 0.75 0.78], 'YColor', [0.75 0.75 0.78], 'FontSize', 9);
title(st.axOver, '缺陷判定与位置标记（红线=裂纹中心，黄框=位置边界框）', ...
    'Color', [0.92 0.92 0.95], 'FontSize', 11, 'Interpreter', 'none');

try linkaxes([st.axOrig, st.axOver], 'xy'); catch, end

switch item.status_code
    case 'crack'
        fg = [1.0 0.38 0.38];
        verdict = sprintf('【有缺陷（隐裂）】 检出 %d 处', item.n_cracks);
    case 'no_crack'
        fg = [0.40 0.95 0.45];
        verdict = '【无缺陷（无隐裂）】';
    case 'review'
        fg = [1.0 0.82 0.25];
        verdict = '【待人工复核】';
    otherwise
        fg = [0.9 0.9 0.9];
        verdict = ['【' item.status '】'];
end
set(st.lblBanner, 'String', sprintf('[%d / %d]  %s   ——   %s', ...
    st.pos, numel(st.activeIdx), item.file, verdict), 'ForegroundColor', fg);

% 拼接位置框与诊断信息
boxTxt = '缺陷像素位置框 [x_min, y_min, x_max, y_max]: 无';
if item.n_cracks > 0 && ~isempty(item.cracks)
    cr = item.cracks;
    if isstruct(cr), cr = num2cell(cr); end
    parts = cell(1, min(4, numel(cr)));
    for k = 1:numel(parts)
        b = cr{k}.bbox;
        parts{k} = sprintf('#%d[%d,%d,%d,%d]', cr{k}.id, b(1), b(2), b(3), b(4));
    end
    if numel(cr) > 4
        parts{end + 1} = sprintf('...共%d处', numel(cr));
    end
    boxTxt = ['缺陷位置框: ' strjoin(parts, '  ')];
end
dg = item.diagnostics;
diagTxt = '';
if isstruct(dg) && isfield(dg, 'finger_angle_deg')
    diagTxt = sprintf('  |  细栅方向 %.1f°  栅距 %.1fpx  有效区 %.0f%%  耗时 %.1fs', ...
        dg.finger_angle_deg, dg.pitch_px, 100 * dg.valid_frac, dg.runtime_s);
end
set(st.lblInfo, 'String', [boxTxt diagTxt]);
setappdata(fig, 'viewerState', st);
drawnow;
end
