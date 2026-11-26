function check_requirements()
%CHECK_REQUIREMENTS  检查运行环境，缺少条件时给出中文说明。
%   MATLAB：需要 R2016b 及以上（jsondecode），推荐 R2020a 及以上（源文件为 UTF-8 编码，
%           更早版本在中文 Windows 上会把中文显示成乱码），以及 Image Processing Toolbox。
%   GNU Octave：需要 7.0 及以上和 image 包（pkg install -forge image）。
isOctave = exist('OCTAVE_VERSION', 'builtin') ~= 0;
if isOctave
    try
        pkg('load', 'image');
    catch
        error('crack:env', ['缺少 GNU Octave 的 image 包。请在 Octave 命令窗口运行一次：\n' ...
            '    pkg install -forge image\n安装完成后重新启动本程序。']);
    end
    if exist('jsondecode') == 0 %#ok<EXIST>
        error('crack:env', '需要 GNU Octave 7.0 或更高版本（当前 %s）。', version());
    end
    return;
end
if exist('jsondecode') == 0 %#ok<EXIST>
    error('crack:env', '需要 MATLAB R2016b 或更高版本（当前 R%s）。', version('-release'));
end
hasIPT = ~isempty(ver('images')) && license('test', 'image_toolbox');
if ~hasIPT
    error('crack:env', ['没有检测到 Image Processing Toolbox（图像处理工具箱）。\n' ...
        '请在 MATLAB 主页 → 附加功能 → 获取附加功能 中安装，或联系学校的 MATLAB 许可管理员。']);
end
rel = version('-release');
yr = str2double(rel(1:4));
if isfinite(yr) && (yr < 2020 || (yr == 2020 && rel(5) < 'a'))
    warning('crack:env', ['当前为 MATLAB R%s。本项目源文件为 UTF-8 编码，R2020a 之前的版本' ...
        '在中文 Windows 上可能把界面和输出中的中文显示为乱码，建议使用 R2020a 或更高版本。'], rel);
end
end
