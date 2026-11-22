function info = env_info()
%ENV_INFO  记录运行环境：MATLAB 或 GNU Octave 版本、图像处理工具箱/包版本。
info.isOctave = exist('OCTAVE_VERSION', 'builtin') ~= 0;
if info.isOctave
    info.platform = ['GNU Octave ' version()];
    try
        p = pkg('list', 'image');
        info.imageToolbox = ['image package ' p{1}.version];
    catch
        info.imageToolbox = 'image package (版本未知)';
    end
else
    info.platform = ['MATLAB ' version()];
    try
        v = ver('images');
        info.imageToolbox = ['Image Processing Toolbox ' v.Version];
    catch
        info.imageToolbox = 'Image Processing Toolbox (版本未知)';
    end
end
info.computer = computer();
info.time = datestr(now, 'yyyy-mm-dd HH:MM:SS');
end
