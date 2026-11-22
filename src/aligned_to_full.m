function [X, Y] = aligned_to_full(u, v, geom)
%ALIGNED_TO_FULL  对齐坐标 (u,v) -> 原图像素坐标 (X,Y)，左上角像素中心为 (1,1)。
du = u - geom.ca(1); dv = v - geom.ca(2);
xw = geom.c(1) + du * geom.g(1) + dv * geom.f(1);
yw = geom.c(2) + du * geom.g(2) + dv * geom.f(2);
X = (xw - 0.5) / geom.s + 0.5;
Y = (yw - 0.5) / geom.s + 0.5;
end
