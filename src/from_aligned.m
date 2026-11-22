function B = from_aligned(M, geom, method)
%FROM_ALIGNED  把对齐坐标系中的图 M 映射回工作图坐标（越界处为 NaN）。
if nargin < 3, method = 'linear'; end
h = geom.workSize(1); w = geom.workSize(2);
[X, Y] = meshgrid(1:w, 1:h);
dx = X - geom.c(1); dy = Y - geom.c(2);
U = geom.ca(1) + dx * geom.g(1) + dy * geom.g(2);
V = geom.ca(2) + dx * geom.f(1) + dy * geom.f(2);
B = interp2(double(M), U, V, method, NaN);
end
