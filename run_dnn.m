function run_dnn(inputs, varargin)
%RUN_DNN  在 MATLAB 中调用 Python 深度网络检测新图像，并与传统方法（改进法）融合。
%
%   run_dnn                          弹窗选择文件夹，检测其中全部图像
%   run_dnn('D:\新图片')              检测指定文件夹（或单张图像、元胞数组）
%   run_dnn(..., 'Fuse', false)      只运行网络，不运行传统方法、不融合
%   run_dnn(..., 'Python', 'C:\Python312\python.exe')   指定 Python 解释器
%   run_dnn(..., 'OutDir', 'D:\结果')
%
%   步骤：1) 传统方法 run_batch → <OutDir>/traditional；
%         2) Python 网络 dnn/predict.py → <OutDir>/dnn；
%         3) 融合（传统裂纹 ∪ 网络补充的裂纹）→ <OutDir>/fusion。
%   三个目录的格式都与 run_batch 相同；可用 crack_app 的“载入已有结果”查看。
%   需要已安装 Python 和 dnn/requirements.txt 中的依赖；Python 解释器按以下顺序查找：
%   'Python' 参数 → 环境变量 DNN_PYTHON → python3 → python → py -3。
root = fileparts(mfilename('fullpath'));
addpath(fullfile(root, 'src'));
check_requirements();
opt = struct('Fuse', true, 'Python', '', 'OutDir', fullfile(root, 'outputs', 'dnn_inspect'));
for i = 1:2:numel(varargin), opt.(varargin{i}) = varargin{i + 1}; end
if nargin < 1 || isempty(inputs)
    d = uigetdir(root, '选择要检测的图片文件夹');
    if isequal(d, 0), return; end
    inputs = {d};
end
if ischar(inputs), inputs = {inputs}; end
py = find_python(opt.Python);
if isempty(py)
    error('crack:python', ['没有找到装好 TensorFlow 的 Python。请先安装 Python 3.9–3.12，再运行：\n' ...
        '    pip install -r "%s"\n或用 ''Python'' 参数指定解释器路径。'], fullfile(root, 'dnn', 'requirements.txt'));
end
if exist(opt.OutDir, 'dir') ~= 7, mkdir(opt.OutDir); end
args = sprintf(' "%s"', inputs{:});
cmd = sprintf('%s "%s"%s --out "%s"', py, fullfile(root, 'dnn', 'predict.py'), args, fullfile(opt.OutDir, 'dnn'));
if opt.Fuse
    fprintf('---- 1/2 传统方法（改进法） ----\n');
    run_batch(inputs, fullfile(opt.OutDir, 'traditional'));
    cmd = sprintf('%s --fuse "%s" --fuse-out "%s"', cmd, fullfile(opt.OutDir, 'traditional'), fullfile(opt.OutDir, 'fusion'));
    fprintf('---- 2/2 深度网络 + 融合 ----\n');
end
fprintf('%s\n', cmd);
status = system(cmd);
if status ~= 0
    error('crack:python', 'Python 网络检测失败（返回码 %d），请查看上面的输出。', status);
end
fprintf('\n结果目录：%s\n  dnn/     网络检测结果\n', opt.OutDir);
if opt.Fuse
    fprintf('  traditional/  传统方法结果\n  fusion/  融合结果（网络补充的裂纹在标注图中为品红色）\n');
end
fprintf('可在 crack_app 中点“载入已有结果”选择上述任一目录查看。\n');
end
