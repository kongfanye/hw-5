function B = resize_img(A, s)
%RESIZE_IMG  按比例 s 缩放：可分离稀疏重采样，缩小时带高斯抗混叠 (sigma = 0.45/s)。
%   坐标约定：输出像素中心 x' 对应输入 x = (x' - 0.5)/s + 0.5，
%   与 aligned_to_full 中工作图 -> 原图的换算一致。
if abs(s - 1) < 1e-9
    B = A; return;
end
[h, w] = size(A);
ho = max(1, round(h * s)); wo = max(1, round(w * s));
sig = 0;
if s < 1, sig = 0.45 / s; end
My = resample_matrix(h, ho, s, sig);
Mx = resample_matrix(w, wo, s, sig);
B = My * double(A) * Mx.';
end
