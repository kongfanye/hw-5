function py = find_python(given)
%FIND_PYTHON  查找装好深度网络依赖（TensorFlow、OpenCV、scikit-image）的 Python 解释器。
%   返回可直接拼进 system 命令的解释器字符串；找不到时返回空。
%   查找顺序：参数 given → 环境变量 DNN_PYTHON → python3 → python → py -3。
if nargin < 1, given = ''; end
cands = {};
if ~isempty(given), cands{end + 1} = ['"' given '"']; end
env = getenv('DNN_PYTHON');
if ~isempty(env), cands{end + 1} = ['"' env '"']; end
cands = [cands, {'python3', 'python', 'py -3'}];
if isempty(getenv('TF_CPP_MIN_LOG_LEVEL'))
    setenv('TF_CPP_MIN_LOG_LEVEL', '2');   % 不显示 TensorFlow 的启动提示
end
py = '';
for i = 1:numel(cands)
    [st, ~] = system([cands{i} ' -c "import tensorflow, cv2, skimage"']);
    if st == 0
        py = cands{i};
        return;
    end
end
end
