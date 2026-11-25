function g = estimate_grid(I, cfg)
%ESTIMATE_GRID  从像素估计细栅主方向与间距（在缩略图上进行）。
%   1) 亮细线图: Ic - 高斯平滑，取正值并排除饱和区；
%   2) Hough 线段按长度加权统计方向直方图，取前两个主方向为候选；
%   3) 对每个候选，在 +-angleRefineRange 内搜索投影最"尖锐"的角度；
%   4) 对齐后的垂直投影做自相关，取第一个显著峰为栅距；
%   5) 选周期性最强的候选作为细栅方向。失败时 ok=false 并给出原因。
[H, W] = size(I);
sc = min(1, cfg.coarseLongSide / max(H, W));
Ic = resize_img(I, sc);
Sm = gauss_blur(Ic, 0.8);
R = Sm - gauss_blur(Ic, 3);
R(R < 0) = 0;
darkBorder = bwareaopen(Ic < 0.04, 50);
sat = (gauss_blur(double(Ic > 0.95), 2) > 0.3) | disk_dilate(darkBorder, 10);
R(sat) = 0;
g.coarseScale = sc;
g.ok = false;
g.reason = '';
g.houghAngles = [];
% ---- Hough 主方向 ----
thr = percentile_val(R(~sat), 88);
BW = R > thr;
BW = bwareaopen(BW, 8);
cands = [];
try
    theta = -90:cfg.houghThetaStep:(90 - cfg.houghThetaStep);
    [Hh, T, Rr] = hough(BW, 'Theta', theta);
    P = houghpeaks(Hh, cfg.houghPeaks, 'Threshold', 0.15 * max(Hh(:)));
    L = houghlines(BW, T, Rr, P, 'FillGap', 3, 'MinLength', round(0.08 * min(size(BW))));
    if ~isempty(L)
        ang = mod([L.theta] + 90, 180);          % 法线角 -> 线方向角
        len = zeros(1, numel(L));
        for i = 1:numel(L)
            len(i) = norm(double(L(i).point1) - double(L(i).point2));
        end
        hist = accumarray(mod(round(ang), 180)' + 1, len', [180 1])';
        k = exp(-((-3:3).^2) / 4);
        hs = conv([hist(end-2:end) hist hist(1:3)], k, 'same');
        hs = hs(4:end-3);
        [pk1, i1] = max(hs);
        hs2 = hs;
        idx = mod((i1 - 1) + (-20:20), 180) + 1;
        hs2(idx) = 0;
        [pk2, i2] = max(hs2);
        cands = i1 - 1;
        if pk2 > 0.15 * pk1, cands(end + 1) = i2 - 1; end
        % 太阳能电池片主栅与细栅正交：始终同时考察正交方向，防止模糊/倾斜时 Hough 仅检出粗主栅
        cands = unique([cands, mod(cands + 90, 180)], 'stable');
        g.houghAngles = cands;
    end
catch err
    g.reason = ['Hough 失败: ' err.message];
end
if isempty(cands)
    cands = [0 90];   % 回退：只考虑水平和竖直
end
% ---- 投影细化与周期（分块进行，抵抗畸变/透视造成的栅线角度渐变） ----
% 投影权重用候选方向上"垂直于细栅的二阶导"脊线强度 max(0, -D_uu)，
% 只响应沿细栅方向的亮线；断栅短横线、汇流条等横向结构在 u 方向近似常数，权重接近 0。
G = gauss_blur(Ic, 1.0);
[Gx, Gy] = gradient(G);
[Gxx, Gxy] = gradient(Gx);
[~, Gyy] = gradient(Gy);
[yy, xx] = ndgrid(1:size(R, 1), 1:size(R, 2));
nT = 3;
ty = min(nT, floor((yy - 1) / (size(R, 1) / nT)) + 1);
tx = min(nT, floor((xx - 1) / (size(R, 2) / nT)) + 1);
tileId = (tx - 1) * nT + ty;
best = struct('score', -inf, 'angle', cands(1), 'pitchC', NaN);
for c = cands
    Duu = Gxx * sind(c)^2 + Gyy * cosd(c)^2 - 2 * Gxy * sind(c) * cosd(c);
    Wr = max(0, -Duu);
    Wr(sat) = 0;
    keep = Wr(:) > percentile_val(Wr(Wr > 0), 50);
    wts = Wr(keep); xs = xx(keep); ys = yy(keep); tid = tileId(keep);
    aG = refine_angle(xs, ys, wts, c, cfg.angleRefineRange, cfg.angleRefineStep);
    angT = nan(1, nT * nT); pitT = nan(1, nT * nT); perT = zeros(1, nT * nT);
    for t = 1:nT * nT
        m = tid == t;
        if nnz(m) < 2000, continue; end
        aT = refine_angle(xs(m), ys(m), wts(m), aG, 1.5, cfg.angleRefineStep);
        [pT, perT(t)] = projection_pitch(xs(m), ys(m), wts(m), aT, cfg);
        angT(t) = aT; pitT(t) = pT;
    end
    okT = isfinite(pitT) & perT > 0;
    if ~any(okT), continue; end
    score = median(perT(okT));
    if score > best.score
        best.score = score;
        best.angle = median(angT(okT));
        best.pitchC = median(pitT(okT));
        best.angleSpread = max(angT(okT)) - min(angT(okT));
        best.tileAngles = angT; best.tilePitch = pitT; best.tilePer = perT;
    end
end
if ~isfinite(best.score)
    best.score = 0;
end
g.theta = mod(best.angle, 180);
g.periodicity = best.score;
g.pitchCoarse = best.pitchC;
g.pitchFull = best.pitchC / sc;
if isfield(best, 'tileAngles')
    g.tileAngles = best.tileAngles; g.tilePitchFull = best.tilePitch / sc;
    g.tilePeriodicity = best.tilePer; g.angleSpread = best.angleSpread;
end
if ~isfinite(g.pitchFull) || g.periodicity < cfg.minPeriodicity
    g.ok = false;
    if isempty(g.reason)
        g.reason = sprintf('栅线周期性弱(%.2f)', g.periodicity);
    end
    g.pitchFull = cfg.defaultPitchFrac * max(H, W);
else
    g.ok = true;
end
end

function [aBest, sBest] = refine_angle(xs, ys, wts, a0, range, step)
aBest = a0; sBest = -inf;
for a = a0 + (-range:0.5:range)
    s = proj_sharpness(xs, ys, wts, a);
    if s > sBest, sBest = s; aBest = a; end
end
a1 = aBest;
for a = a1 + (-0.5:step:0.5)
    s = proj_sharpness(xs, ys, wts, a);
    if s > sBest, sBest = s; aBest = a; end
end
end

function p = projection(xs, ys, wts, a)
% 沿方向 a（度）投影：横坐标 u = (x,y)·(sin a, -cos a)，1 px 分箱、线性软分配。
% 角度恰为 0/90 度时 u 为整数，软分配保证每个箱都有样本；空箱线性插值。
u = xs * sind(a) - ys * cosd(a);
u = u - min(u) + 1;
i0 = floor(u); fr = u - i0;
n = max(i0) + 1;
s = accumarray(i0, wts .* (1 - fr), [n 1]) + accumarray(i0 + 1, wts .* fr, [n 1]);
c = accumarray(i0, 1 - fr, [n 1]) + accumarray(i0 + 1, fr, [n 1]);
p = s ./ max(c, eps);
bad = c < 2;
if any(bad) && any(~bad)
    k = (1:n)';
    p(bad) = interp1(k(~bad), p(~bad), k(bad), 'linear', 0);
end
end

function s = proj_sharpness(xs, ys, wts, a)
p = projection(xs, ys, wts, a);
p = p - movmean_simple(p, 41);
s = mean(p.^2);
end

function [pitch, per, p] = projection_pitch(xs, ys, wts, a, cfg)
p = projection(xs, ys, wts, a);
p = p - movmean_simple(p, 41);
p = p(:)';
n = numel(p);
lagMin = cfg.pitchRangeCoarse(1); lagMax = min(cfg.pitchRangeCoarse(2), n - 2);
ac = zeros(1, lagMax + 1);
p0 = p - mean(p);
den = sum(p0.^2) + eps;
for L = 0:lagMax
    ac(L + 1) = sum(p0(1:end-L) .* p0(1+L:end)) / den;
end
seg = ac(lagMin + 1:lagMax + 1);
isPk = [false, seg(2:end-1) > seg(1:end-2) & seg(2:end-1) >= seg(3:end), false];
pkIdx = find(isPk);
if isempty(pkIdx)
    pitch = NaN; per = 0; return;
end
mx = max(seg(pkIdx));
first = pkIdx(find(seg(pkIdx) >= 0.5 * mx & seg(pkIdx) >= 0.1, 1));
if isempty(first), pitch = NaN; per = 0; return; end
% 抛物线细化
y1 = seg(first - 1); y2 = seg(first); y3 = seg(first + 1);
d = 0.5 * (y1 - y3) / (y1 - 2 * y2 + y3 + eps);
pitch = (lagMin + first - 1) + d;   % 分箱为 1 px
per = y2;
end

function m = movmean_simple(p, k)
p = p(:);
h = floor(k / 2);
pp = [repmat(p(1), h, 1); p; repmat(p(end), h, 1)];
c = cumsum([0; pp]);
m = (c(k + 1:end) - c(1:end - k)) / k;
end
