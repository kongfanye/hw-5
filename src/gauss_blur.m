function B = gauss_blur(A, sigma)
%GAUSS_BLUR  可分离高斯平滑（边界复制填充）。替代 imgaussfilt，MATLAB/Octave 通用。
if sigma <= 0
    B = A; return;
end
r = max(1, ceil(3 * sigma));
x = -r:r;
h = exp(-x.^2 / (2 * sigma^2));
h = h / sum(h);
Ap = padarray(A, [r r], 'replicate');
B = conv2(h, h, Ap, 'valid');
end
