function A = fill_nan_nearest(A)
%FILL_NAN_NEAREST  用最近的非 NaN 像素值填充 NaN（基于 bwdist 的最近点索引）。
m = isnan(A);
if ~any(m(:)), return; end
if all(m(:)), A(:) = 0; return; end
[~, idx] = bwdist(~m);
A(m) = A(idx(m));
end
