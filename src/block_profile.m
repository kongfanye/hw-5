function P = block_profile(R, blk, dim, minFrac, q)
%BLOCK_PROFILE  沿 dim 方向分块求稳健中位数，得到重复纹理估计。
%   dim=1：每个行块内逐列求中位数（对齐图中即沿细栅方向），
%          得到"垂直于细栅方向的一维纹理"，块间沿行方向线性插值；
%   dim=2：每个列块内逐行求中位数（沿主栅方向的横向重复结构）。
%   R 中 NaN 视为无效像素；分块内有效比例低于 minFrac 的列取邻块值。
%   q 为分位数（默认 0.5，中位数）。
if nargin < 5, q = 0.5; end
if dim == 2
    P = block_profile(R.', blk, 1, minFrac, q).';
    return;
end
[h, w] = size(R);
blk = max(3, min(round(blk), h));
step = max(1, round(blk / 2));
starts = 1:step:max(1, h - blk + 1);
if starts(end) + blk - 1 < h
    starts(end + 1) = h - blk + 1;
end
nb = numel(starts);
M = nan(nb, w);
cen = zeros(nb, 1);
for b = 1:nb
    rows = starts(b):min(h, starts(b) + blk - 1);
    M(b, :) = nanmedian_cols(R(rows, :), ceil(minFrac * numel(rows)), q);
    cen(b) = mean(rows);
end
% 沿块方向前向/后向填充缺失值
for b = 2:nb
    m = isnan(M(b, :)); M(b, m) = M(b - 1, m);
end
for b = nb - 1:-1:1
    m = isnan(M(b, :)); M(b, m) = M(b + 1, m);
end
M(isnan(M)) = 0;
if nb == 1
    P = repmat(M, h, 1);
    return;
end
yi = min(max((1:h)', cen(1)), cen(end));
P = interp1(cen, M, yi, 'linear');
end
