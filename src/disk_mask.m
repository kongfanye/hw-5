function se = disk_mask(r)
%DISK_MASK  半径 r 的圆盘结构元素（逻辑矩阵，可直接用于 imdilate/imerode/imopen）。
r = max(0, round(r));
[x, y] = meshgrid(-r:r, -r:r);
se = (x.^2 + y.^2) <= r^2 + 0.5;
end
