function B = shift_img(A, dx, dy, padval)
%SHIFT_IMG  整数平移：B(y,x) = A(y+dy, x+dx)，越界处填 padval（0 或 NaN）。
[h, w] = size(A);
if isnan(padval)
    B = nan(h, w, class(A));
elseif padval == 0
    B = zeros(h, w, class(A));
else
    B = zeros(h, w, class(A)) + padval;
end
if abs(dx) >= w || abs(dy) >= h, return; end
ys = max(1, 1 - dy):min(h, h - dy);
xs = max(1, 1 - dx):min(w, w - dx);
B(ys, xs) = A(ys + dy, xs + dx);
end
