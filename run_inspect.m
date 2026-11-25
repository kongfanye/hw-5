function summary = run_inspect(inputPaths, varargin)
%RUN_INSPECT  助教现场验收专用入口：对全新太阳能电池片图像判断是否有缺陷并标出缺陷位置。
%
%   最简用法（MATLAB 命令窗口直接输入，弹出图形化文件/文件夹选择框）：
%     run_inspect
%
%   指定助教给出的新文件夹、单张图片或多张图片（路径可含中文和空格）：
%     run_inspect('D:\助教测试样本')
%     run_inspect('D:\助教测试样本\sample_01.jpg')
%     run_inspect({'D:\图1.jpg', 'D:\图2.png'})
%
%   可选参数（名称-值对）：
%     'OutDir'      输出目录（默认 'outputs/inspect'，不会覆盖原有的 outputs/ 实验结果）
%     'ShowFigure'  是否弹出双栏联动缩放查看器（默认 true；无图形界面时自动跳过）
%     'Recursive'   扫描文件夹时是否包含子文件夹（默认 true）
%     'Debug'       是否输出 7 步中间结果拼图（默认 {}；设为 {'*'} 输出全部）
%
%   输出内容：
%     1. 命令行清晰打印每张图的【有无缺陷判定 + 裂纹条数 + 缺陷像素坐标框】汇总表；
%     2. 自动弹出交互式双栏结果窗口（左原图、右标注图，放大镜双图同步缩放，方向键翻页）；
%     3. 导出标注图 overlays/*.jpg、二值掩膜 masks/*.png、results.csv、defects.json。

root = fileparts(mfilename('fullpath'));
addpath(fullfile(root, 'src'));
check_requirements();

opt = struct('OutDir', fullfile(root, 'outputs', 'inspect'), ...
             'ShowFigure', true, 'Recursive', true, 'Debug', {{}});
for i = 1:2:numel(varargin)
    opt.(varargin{i}) = varargin{i + 1};
end

% 未传参数时：桌面 MATLAB 弹出交互选择框；命令行批处理模式使用默认样本目录
if nargin < 1 || isempty(inputPaths)
    if has_desktop_gui()
        [inputPaths, picked] = pick_inputs_gui(root);
        if ~picked
            fprintf('已取消选择。\n');
            summary = struct();
            return;
        end
    else
        inputPaths = default_repo_inputs(root);
    end
end
if ischar(inputPaths), inputPaths = {inputPaths}; end

files = list_images(inputPaths, opt.Recursive);
if isempty(files)
    fprintf('未在指定路径中找到可读取的图像文件（支持 jpg/jpeg/png/bmp/tif/tiff）：\n  %s\n', ...
        strjoin(inputPaths, '; '));
    summary = struct('n', 0);
    return;
end

% 清空旧的 inspect 输出子目录中的残留文件，避免与前一次验收混淆
clean_inspect_dir(opt.OutDir);

fprintf('\n================ 太阳能电池板内部缺陷（隐裂）检测 ================\n');
fprintf('待测图像数: %d 张\n', numel(files));
fprintf('输出目录  : %s\n\n', opt.OutDir);

cfg = crack_config();
summary = run_batch(inputPaths, opt.OutDir, 'Method', 'improved', ...
    'Config', cfg, 'Debug', opt.Debug, 'Recursive', opt.Recursive);

% 打印清晰直观的验收汇总表（含每条裂纹的位置坐标框）
print_acceptance_table(opt.OutDir);

if opt.ShowFigure
    show_results_viewer(files, opt.OutDir);
end
end

function tf = has_desktop_gui()
tf = false;
if exist('OCTAVE_VERSION', 'builtin') == 0
    try
        tf = usejava('desktop');
    catch
        tf = false;
    end
end
end

function [paths, ok] = pick_inputs_gui(root)
paths = {}; ok = false;
choice = questdlg('请选择助教测试图像的导入方式：', ...
    '太阳能电池板缺陷检测 — 验收入口', ...
    '选择文件夹', '选择图片(可多选)', '使用仓库自带样本', '选择文件夹');
if isempty(choice), return; end
switch choice
    case '选择文件夹'
        d = uigetdir(root, '选择包含待测太阳能电池片图像的文件夹');
        if isequal(d, 0), return; end
        paths = {d}; ok = true;
    case '选择图片(可多选)'
        [fn, pn] = uigetfile( ...
            {'*.jpg;*.jpeg;*.png;*.bmp;*.tif;*.tiff;*.JPG;*.JPEG;*.PNG;*.BMP;*.TIF;*.TIFF', ...
             '图像文件 (*.jpg, *.png, *.bmp, *.tif)'; '*.*', '所有文件 (*.*)'}, ...
            '选择待检测的太阳能电池片图像（可按住 Ctrl/Shift 多选）', root, 'MultiSelect', 'on');
        if isequal(fn, 0), return; end
        if ischar(fn)
            paths = {fullfile(pn, fn)};
        else
            paths = cellfun(@(f) fullfile(pn, f), fn, 'UniformOutput', false);
        end
        ok = true;
    case '使用仓库自带样本'
        paths = default_repo_inputs(root);
        ok = ~isempty(paths);
end
end

function dirs = default_repo_inputs(root)
cands = {{fullfile(root, 'data', 'raw')}, {fullfile(root, 'upload')}, ...
         {fullfile(root, 'cracked'), fullfile(root, 'uncracked')}};
dirs = {};
for i = 1:numel(cands)
    c = cands{i};
    c = c(cellfun(@(d) exist(d, 'dir') == 7, c));
    if ~isempty(c) && ~isempty(list_images(c, false))
        dirs = c;
        return;
    end
end
end

function clean_inspect_dir(outDir)
if exist(outDir, 'dir') ~= 7, return; end
subs = {'overlays', 'masks'};
for s = 1:numel(subs)
    sd = fullfile(outDir, subs{s});
    if exist(sd, 'dir') == 7
        L = dir(sd);
        for i = 1:numel(L)
            if ~L(i).isdir
                delete(fullfile(sd, L(i).name));
            end
        end
    end
end
end

function print_acceptance_table(outDir)
jsonPath = fullfile(outDir, 'defects.json');
if exist(jsonPath, 'file') ~= 2, return; end
J = jsondecode(read_text_utf8(jsonPath));
imgs = J.images;
if isstruct(imgs), imgs = num2cell(imgs); end

fprintf('\n==================== 逐张检测与缺陷位置汇总 ====================\n');
fprintf('%-4s  %-28s  %-10s  %-6s  %s\n', '序号', '图像文件', '是否有缺陷', '裂纹数', '缺陷位置框 [x_min,y_min,x_max,y_max]');
fprintf('%s\n', repmat('-', 1, 88));
for i = 1:numel(imgs)
    it = imgs{i};
    switch it.status_code
        case 'crack',    tag = '有缺陷(隐裂)';
        case 'no_crack', tag = '无缺陷';
        case 'review',   tag = '待复核';
        otherwise,       tag = it.status;
    end
    locStr = '—';
    if it.n_cracks > 0 && ~isempty(it.cracks)
        cr = it.cracks;
        if isstruct(cr), cr = num2cell(cr); end
        bs = cell(1, min(3, numel(cr)));
        for k = 1:numel(bs)
            b = cr{k}.bbox;
            bs{k} = sprintf('#%d[%d,%d,%d,%d]', cr{k}.id, b(1), b(2), b(3), b(4));
        end
        if numel(cr) > 3
            bs{end + 1} = sprintf('...共%d处', numel(cr));
        end
        locStr = strjoin(bs, ' ');
    elseif ~isempty(it.review_reasons)
        rv = it.review_reasons;
        if ischar(rv), rv = {rv}; end
        locStr = strjoin(rv(:)', '；');
    end
    fprintf('%-4d  %-28s  %-10s  %-6d  %s\n', i, it.file, tag, it.n_cracks, locStr);
end
fprintf('%s\n', repmat('=', 1, 88));
fprintf('标注叠加图目录: %s\n', fullfile(outDir, 'overlays'));
fprintf('汇总表格文件  : %s\n\n', fullfile(outDir, 'results.csv'));
end
