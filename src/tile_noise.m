function sdMap = tile_noise(R, V, tile)
%TILE_NOISE  分块估计残差的稳健标准差 (1.4826*MAD)，双线性插值成整幅图。
%   有效像素不足的块用最近块填充；整体下限为各块中位数的一半，
%   防止极平滑区域把微弱噪声放大成高 z 分数。
[h, w] = size(R);
tile = max(8, round(tile));
nty = max(1, round(h / tile)); ntx = max(1, round(w / tile));
ye = round(linspace(0, h, nty + 1)); xe = round(linspace(0, w, ntx + 1));
sd = nan(nty, ntx);
for i = 1:nty
    for j = 1:ntx
        r = ye(i) + 1:ye(i + 1); c = xe(j) + 1:xe(j + 1);
        v = R(r, c); m = V(r, c);
        v = v(m & ~isnan(v));
        if numel(v) >= 0.15 * numel(m)
            [~, sd(i, j)] = robust_stats(v);
        end
    end
end
if all(isnan(sd(:)))
    [~, s0] = robust_stats(R(V));
    if ~isfinite(s0) || s0 <= 0, s0 = 1e-3; end
    sdMap = repmat(s0, h, w);
    return;
end
sd = fill_nan_nearest(sd);
floorv = 0.5 * median(sd(:));
sd = max(sd, max(floorv, 1e-6));
yc = (ye(1:end-1) + ye(2:end) + 1) / 2;
xc = (xe(1:end-1) + xe(2:end) + 1) / 2;
if nty == 1 && ntx == 1
    sdMap = repmat(sd, h, w); return;
end
if nty == 1, yc = [yc - 1, yc + 1]; sd = [sd; sd]; end
if ntx == 1, xc = [xc - 1, xc + 1]; sd = [sd, sd]; end
[X, Y] = meshgrid(1:w, 1:h);
X = min(max(X, xc(1)), xc(end)); Y = min(max(Y, yc(1)), yc(end));
sdMap = interp2(xc, yc, sd, X, Y, 'linear');
end
