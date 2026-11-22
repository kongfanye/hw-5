function B = to_aligned(A, geom, method)
%TO_ALIGNED  把工作图 A 重采样到栅线对齐坐标系（越界处为 NaN）。
if nargin < 3, method = 'linear'; end
ha = geom.alignedSize(1); wa = geom.alignedSize(2);
[U, V] = meshgrid(1:wa, 1:ha);
du = U - geom.ca(1); dv = V - geom.ca(2);
X = geom.c(1) + du * geom.g(1) + dv * geom.f(1);
Y = geom.c(2) + du * geom.g(2) + dv * geom.f(2);
B = interp2(double(A), X, Y, method, NaN);
end
