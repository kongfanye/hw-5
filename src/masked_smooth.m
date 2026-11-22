function B = masked_smooth(A, V, sigma)
%MASKED_SMOOTH  带掩膜高斯平滑：B = G*(A.*V) ./ G*V。
%   只用有效像素 V 估计平滑值，避免亮缝、过曝区抬高邻近背景。
%   sigma 较大时先按块平均缩小，再平滑、插值放大，以节省时间。
V = double(V);
A(isnan(A)) = 0;
A = A .* V;
f = max(1, floor(sigma / 6));
[h, w] = size(A);
if f > 1
    hh = ceil(h / f) * f; ww = ceil(w / f) * f;
    Ap = zeros(hh, ww); Vp = zeros(hh, ww);
    Ap(1:h, 1:w) = A; Vp(1:h, 1:w) = V;
    As = squeeze(sum(sum(reshape(Ap, f, hh / f, f, ww / f), 1), 3));
    Vs = squeeze(sum(sum(reshape(Vp, f, hh / f, f, ww / f), 1), 3));
    if hh / f == 1, As = As(:)'; Vs = Vs(:)'; end
    num = gauss_blur(As, sigma / f);
    den = gauss_blur(Vs, sigma / f);
    Bs = num ./ max(den, 1e-6);
    Bs(den < 1e-3) = NaN;
    Bs = fill_nan_nearest(Bs);
    % 小图像素中心位于大图坐标 (i-0.5)*f + 0.5，用可分离线性插值放大
    My = resample_matrix(size(Bs, 1), h, f, 0);
    Mx = resample_matrix(size(Bs, 2), w, f, 0);
    B = My * Bs * Mx.';
else
    num = gauss_blur(A, sigma);
    den = gauss_blur(V, sigma);
    B = num ./ max(den, 1e-6);
    B(den < 1e-3) = NaN;
    B = fill_nan_nearest(B);
end
end
