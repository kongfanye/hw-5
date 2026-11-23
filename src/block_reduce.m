function B = block_reduce(A, f)
%BLOCK_REDUCE  按 f×f 像素块求平均缩小图像（逐通道，返回与输入同类的整型或双精度）。
%   多余的边缘行列被舍去；f = 1 时原样返回。
if f <= 1, B = A; return; end
cls = class(A);
[H, W, C] = size(A);
h = floor(H / f); w = floor(W / f);
X = single(A(1:h * f, 1:w * f, :));
X = reshape(sum(reshape(X, f, h, w * f, C), 1), h, w * f, C);
X = permute(X, [2 1 3]);
X = reshape(sum(reshape(X, f, w, h, C), 1), w, h, C);
X = permute(X, [2 1 3]) / f ^ 2;
if strcmp(cls, 'double') || strcmp(cls, 'single')
    B = cast(X, cls);
else
    B = cast(round(X), cls);
end
end
