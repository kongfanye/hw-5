function M = resample_matrix(nIn, nOut, s, smoothSigma)
%RESAMPLE_MATRIX  一维重采样稀疏矩阵 M (nOut x nIn)，输出 = M * 输入。
%   输出像素 i 的中心对应输入坐标 x = (i - 0.5)/s + 0.5。
%   smoothSigma > 0 时用高斯权重（缩小时抗混叠），否则为线性插值。
x = ((1:nOut)' - 0.5) / s + 0.5;
x = min(max(x, 1), nIn);
if smoothSigma > 0
    r = ceil(3 * smoothSigma);
    off = -r:r;
    J = floor(x) + off;                     % nOut x (2r+1)
    Wt = exp(-((J - x).^2) / (2 * smoothSigma^2));
else
    J = [floor(x), floor(x) + 1];
    Wt = [1 - (x - floor(x)), x - floor(x)];
end
J = min(max(J, 1), nIn);                    % 边界复制
I = repmat((1:nOut)', 1, size(J, 2));
M = sparse(I(:), J(:), Wt(:), nOut, nIn);
M = spdiags(1 ./ full(sum(M, 2)), 0, nOut, nOut) * M;
end
