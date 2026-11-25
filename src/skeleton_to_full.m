function out = skeleton_to_full(prep, Lsk, oriDeg, widthA, If, cfg, maxPts)
%SKELETON_TO_FULL  把对齐坐标系中的裂纹骨架映射回原图分辨率并精定位。
%   1) 骨架像素 (u,v) -> 原图坐标 (X,Y)（反旋转 + 反缩放，像素中心对齐）；
%   2) 在原图上沿局部法向 +-snapRadius 搜索最暗点（沿裂纹方向 3 点平均），
%      把中心线吸附到原图暗线中心；
%   3) 相邻骨架像素之间在原图上连线，得到原图中心线；
%   4) 按估计宽度膨胀得到裂纹掩膜，并统计每条裂纹的位置信息。
%   输出坐标：左上角像素 (1,1)，x 为列，y 为行，边界框含两端。
geom = prep.geom; s = geom.s;
[H, W] = size(If);
out.Lfull = zeros(H, W, 'uint16');
out.mask = false(H, W);
out.cracks = struct('id', {}, 'bbox', {}, 'centroid', {}, 'length_px', {}, ...
    'width_px', {}, 'angle_deg', {}, 'endpoints', {}, 'points', {});
idx = find(Lsk > 0);
if isempty(idx), return; end
[v, u] = ind2sub(size(Lsk), idx);
lab = double(Lsk(idx));
n = max(lab);
[X, Y] = aligned_to_full(u, v, geom);
a = oriDeg(idx); a(isnan(a)) = 0;
du = cosd(a); dv = sind(a);
dx = du * geom.g(1) + dv * geom.f(1);
dy = du * geom.g(2) + dv * geom.f(2);
nx = -dy; ny = dx;
% ---- 原图吸附（直接双线性采样，避免对整幅大图重复构造 interp2 网格） ----
r = cfg.snapRadius;
bestV = inf(size(X)); tb = zeros(size(X));
Wm1 = max(1, W - 1); Hm1 = max(1, H - 1);
for t = -r:r
    val = zeros(size(X));
    for q = -1:1
        xq = min(max(X + t * nx + q * dx, 1), W);
        yq = min(max(Y + t * ny + q * dy, 1), H);
        x0 = min(floor(xq), Wm1); y0 = min(floor(yq), Hm1);
        fx = xq - x0; fy = yq - y0;
        p00 = y0 + (x0 - 1) * H;
        val = val + (1 - fx) .* ((1 - fy) .* If(p00) + fy .* If(p00 + 1)) + ...
                     fx      .* ((1 - fy) .* If(p00 + H) + fy .* If(p00 + H + 1));
    end
    upd = val < bestV - 1e-9;
    bestV(upd) = val(upd); tb(upd) = t;
end
% 吸附偏移沿裂纹平滑（5x5 邻域内同一骨架像素的均值），避免中心线锯齿
T = zeros(size(Lsk)); Wm = zeros(size(Lsk));
T(idx) = tb; Wm(idx) = 1;
k5 = ones(1, 5);
Ts = conv2(k5, k5, T, 'same') ./ max(conv2(k5, k5, Wm, 'same'), 1);
tb = Ts(idx);
Xs = min(max(X + tb .* nx, 1), W);
Ys = min(max(Y + tb .* ny, 1), H);
% ---- 相邻骨架像素在原图上连线 ----
P = zeros(size(Lsk));
P(idx) = 1:numel(idx);
[ha, wa] = size(Lsk);
offs = [1 0; 0 1; 1 1; -1 1];
pi1 = []; pi2 = [];
for k = 1:size(offs, 1)
    uu = u + offs(k, 1); vv = v + offs(k, 2);
    ok = uu >= 1 & uu <= wa & vv >= 1 & vv <= ha;
    j = zeros(size(u));
    j(ok) = P(sub2ind([ha wa], vv(ok), uu(ok)));
    m = j > 0;
    m(m) = lab(j(m)) == lab(m);
    pi1 = [pi1; find(m)]; pi2 = [pi2; j(m)]; %#ok<AGROW>
end
Lf = out.Lfull;
Lf(sub2ind([H W], round(Ys), round(Xs))) = uint16(lab);
Lf = draw_segments(Lf, Xs(pi1), Ys(pi1), Xs(pi2), Ys(pi2), uint16(lab(pi1)));
out.Lfull = Lf;
% 长度：骨架像素数按主方向做对角修正，再换算到原图像素
cntK = accumarray(lab, 1, [n 1]);
mu = accumarray(lab, u, [n 1]) ./ max(cntK, 1); mv = accumarray(lab, v, [n 1]) ./ max(cntK, 1);
cuu = accumarray(lab, u.^2, [n 1]) ./ max(cntK, 1) - mu.^2;
cvv = accumarray(lab, v.^2, [n 1]) ./ max(cntK, 1) - mv.^2;
cuv = accumarray(lab, u .* v, [n 1]) ./ max(cntK, 1) - mu .* mv;
phi = 0.5 * atan2(2 * cuv, cuu - cvv);
lenK = cntK ./ max(abs(cos(phi)), abs(sin(phi))) / s;
% ---- 端点 ----
ep = bwmorph(Lsk > 0, 'endpoints');
isEp = ep(idx);
% ---- 中心线像素按标签分组 ----
cidx = find(Lf > 0);
clab = double(Lf(cidx));
[cy, cx] = ind2sub([H W], cidx);
[clab, ord] = sort(clab); cy = cy(ord); cx = cx(ord);
first = [1; find(diff(clab)) + 1]; last = [first(2:end) - 1; numel(clab)];
labsPresent = clab(first);
mask = out.mask;
cr = out.cracks;
for q = 1:numel(labsPresent)
    k = labsPresent(q);
    ii = first(q):last(q);
    px = cx(ii); py = cy(ii);
    hw = max(cfg.maskMinHalfWidth, round(widthA(k) / s / 2));
    x1 = max(1, min(px) - hw - 1); x2 = min(W, max(px) + hw + 1);
    y1 = max(1, min(py) - hw - 1); y2 = min(H, max(py) + hw + 1);
    loc = false(y2 - y1 + 1, x2 - x1 + 1);
    loc(sub2ind(size(loc), py - y1 + 1, px - x1 + 1)) = true;
    loc = disk_dilate(loc, hw);
    mask(y1:y2, x1:x2) = mask(y1:y2, x1:x2) | loc;
    [ly, lx] = find(loc);
    c = struct();
    c.id = k;
    c.bbox = [min(lx) + x1 - 1, min(ly) + y1 - 1, max(lx) + x1 - 1, max(ly) + y1 - 1];
    m = lab == k;
    sx = Xs(m); sy = Ys(m);
    c.centroid = [mean(sx), mean(sy)];
    c.length_px = lenK(k);
    c.width_px = max(1, widthA(k) / s);
    if numel(sx) >= 2
        C = cov([sx, sy]);
        [Ev, Dv] = eig(C);
        [~, im] = max(diag(Dv));
        e = Ev(:, im);
        c.angle_deg = mod(atan2d(e(2), e(1)), 180);
        proj = (sx - mean(sx)) * e(1) + (sy - mean(sy)) * e(2);
        [~, o] = sort(proj);
    else
        c.angle_deg = 0; o = 1;
    end
    em = m & isEp;
    c.endpoints = round([Xs(em), Ys(em)]);
    step = max(1, ceil(numel(o) / maxPts));
    o = o(1:step:end);
    c.points = round([sx(o), sy(o)]);
    cr(end + 1) = c; %#ok<AGROW>
end
out.mask = mask;
out.cracks = cr;
end
