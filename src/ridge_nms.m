function ridge = ridge_nms(z, oriK, nOrient)
%RIDGE_NMS  沿暗线法向的非极大值抑制，得到 1 像素宽的响应脊线。
%   像素 p 的方向序号为 oriK(p)，法向 n = (-sin t, cos t)；
%   若 z(p) >= z(p+n) 且 z(p) >= z(p-n)（法向 1 像素邻点），保留为脊线。
ridge = false(size(z));
for k = 1:nOrient
    m = oriK == k;
    if ~any(m(:)), continue; end
    t = (k - 1) * 180 / nOrient;
    ox = round(-sind(t)); oy = round(cosd(t));
    a = shift_img(z, ox, oy, 0);
    b = shift_img(z, -ox, -oy, 0);
    ridge = ridge | (m & z >= a & z >= b & z > 0);
end
end
