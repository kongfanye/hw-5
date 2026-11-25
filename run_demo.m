function run_demo(inputDirs, outRoot)
%RUN_DEMO  完整实验演示入口：用同一批原图分别运行改进法与基线，并在匹配参考标签时自动评估。
%   在项目目录的 MATLAB 命令窗口输入  run_demo
%   或在终端执行                      matlab -batch "run_demo"
%   （助教现场给新图验收时，推荐直接运行更快速的  run_inspect  或  run_inspect('图片目录')）
%
%   输入路径默认按顺序选择第一个存在且含图像的：
%     data/raw/  ->  upload/  ->  cracked/ 与 uncracked/（本仓库原图所在目录）
%   也可显式指定文件夹或单张图像：
%     run_demo({'D:\新建 文件夹\图片'})
%     run_demo({'D:\新建 文件夹\图片'}, 'D:\输出结果')

root = fileparts(mfilename('fullpath'));
addpath(fullfile(root, 'src'));
if exist('OCTAVE_VERSION', 'builtin') ~= 0
    pkg load image
end
isCustomInput = nargin >= 1 && ~isempty(inputDirs);
if ~isCustomInput
    inputDirs = default_input_dirs(root);
end
if ischar(inputDirs), inputDirs = {inputDirs}; end
if nargin < 2 || isempty(outRoot)
    if isCustomInput && ~matches_repo_labels(root, inputDirs)
        outRoot = fullfile(root, 'outputs', 'custom_demo');
    else
        outRoot = fullfile(root, 'outputs');
    end
end
if exist(outRoot, 'dir') ~= 7, mkdir(outRoot); end
logFile = fullfile(outRoot, 'run_demo_log.txt');
if exist(logFile, 'file') == 2, delete(logFile); end
diary(logFile);
diary on
info = env_info();
fprintf('==== run_demo ====\n');
fprintf('时间: %s\n', info.time);
fprintf('运行命令: run_demo（终端等价命令: matlab -batch "run_demo"；新图验收推荐: run_inspect）\n');
fprintf('运行环境: %s; %s; %s\n', info.platform, info.imageToolbox, info.computer);
fprintf('项目目录: %s\n', root);
fprintf('输入路径: %s\n', strjoin(inputDirs, '; '));
fprintf('输出目录: %s\n', outRoot);
if isempty(inputDirs)
    fprintf('未找到含图像的输入目录（data/raw、upload、cracked、uncracked），请传入图像路径或使用 run_inspect。\n');
    diary off
    return;
end
% 代表样本：单条裂纹、多条/网状裂纹、细栅近水平、带交叉亮缝的无隐裂图、细栅倾斜
debugList = {'cracked_07', 'cracked_09', 'cracked_01', 'cracked_04', 'uncracked_07'};
cfg = crack_config();
t0 = tic;
fprintf('\n---- 改进法 -> %s ----\n', outRoot);
s1 = run_batch(inputDirs, outRoot, 'Method', 'improved', 'Config', cfg, 'Debug', debugList);
fprintf('\n---- 基线 -> %s ----\n', fullfile(outRoot, 'baseline'));
s2 = run_batch(inputDirs, fullfile(outRoot, 'baseline'), 'Method', 'baseline', 'Config', cfg, 'Debug', debugList);
fprintf('\n---- 汇总 ----\n');
fprintf('改进法: %d 张；有隐裂 %d，无隐裂 %d，待复核 %d，错误 %d\n', s1.n, s1.nCrack, s1.nNoCrack, s1.nReview, s1.nError);
fprintf('基线  : %d 张；有隐裂 %d，无隐裂 %d，待复核 %d，错误 %d\n', s2.n, s2.nCrack, s2.nNoCrack, s2.nReview, s2.nError);
if matches_repo_labels(root, inputDirs)
    fprintf('\n---- 评估（仅评估阶段读取 data/labels.csv 与 data/annotations.json） ----\n');
    try
        relMain = relative_or_abs(root, outRoot);
        relBase = relative_or_abs(root, fullfile(outRoot, 'baseline'));
        evaluate_results(root, {relMain, relBase}, fullfile(outRoot, 'evaluation'), [25 50]);
    catch err
        fprintf('评估失败: %s\n', err.message);
    end
else
    fprintf('\n提示：当前输入为外部新样本（不在 data/labels.csv 参考集中），已跳过参考集指标对比。\n');
    files = list_images(inputDirs, false);
    show_results_viewer(files, outRoot);
end
fprintf('\n总耗时 %.1f 分钟\n', toc(t0) / 60);
diary off
end

function tf = matches_repo_labels(root, inputDirs)
tf = false;
labelFile = fullfile(root, 'data', 'labels.csv');
if exist(labelFile, 'file') ~= 2, return; end
files = list_images(inputDirs, false);
if isempty(files), return; end
labels = read_csv_simple(labelFile);
lf = {labels.file};
rf = {files.relpath};
tf = any(ismember(rf, lf));
end

function rel = relative_or_abs(root, p)
prefix = [strip_trail(root) filesep];
if strncmp(p, prefix, numel(prefix))
    rel = strrep(p(numel(prefix) + 1:end), '\', '/');
else
    rel = p;
end
end

function p = strip_trail(p)
while numel(p) > 1 && (p(end) == '/' || p(end) == '\')
    p = p(1:end - 1);
end
end

function dirs = default_input_dirs(root)
cands = {{fullfile(root, 'data', 'raw')}, {fullfile(root, 'upload')}, ...
    {fullfile(root, 'cracked'), fullfile(root, 'uncracked')}};
dirs = {};
for i = 1:numel(cands)
    c = cands{i};
    c = c(cellfun(@(d) exist(d, 'dir') == 7, c));
    if isempty(c), continue; end
    if ~isempty(list_images(c, false))
        dirs = c;
        return;
    end
end
end
