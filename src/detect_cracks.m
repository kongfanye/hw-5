function res = detect_cracks(I, cfg, wantDebug)
%DETECT_CRACKS  改进法：单张电池片图像的隐裂检测与定位。
%   res = detect_cracks(I, cfg)        I 为灰度图 (double, [0,1])，cfg 见 crack_config
%   res = detect_cracks(I, cfg, true)  同时返回中间结果 res.debug
%   只使用图像像素和参数，不读取文件名、目录名或参考标签。
%
%   流程：有效区与背景 -> 亮度校正 -> 栅线/横向结构抑制 -> 多方向细暗线响应
%        -> 局部 z 分数与双阈值 -> 骨架化 -> 断点连接 -> 形状筛选
%        -> 原图坐标映射与暗线吸附。
if nargin < 3, wantDebug = false; end
t0 = tic;
Rs = crack_response(I, cfg);
res = segment_cracks(Rs, I, cfg, wantDebug);
res.diag.runtime_s = toc(t0);
end
