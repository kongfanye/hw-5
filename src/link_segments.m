function [sk2, linkMask, nLinks] = link_segments(sk, z, cells, pitch, cfg)
%LINK_SEGMENTS  连接同一有效片内、间隔短且方向相符的骨架断点。
%   端点方向取端点指向其所在骨架局部均值点的反方向（向外延伸方向）。
%   连接条件：两端点属于不同骨架段、同一连通有效区（同片）、
%   距离 <= linkGap*pitch 且两端延伸方向与连线夹角都 <= linkAngle，
%   或距离 <= linkGapLong*pitch 且夹角都 <= linkAngleLong（跨汇流条的共线断点），
%   两段平均响应相差不超过 4 倍。按距离贪心匹配，每个端点最多连一次。
linkMask = false(size(sk));
nLinks = 0;
sk2 = sk;
L = bwlabel(sk, 8);
ep = bwmorph(sk, 'endpoints');
[ey, ex] = find(ep);
nE = numel(ey);
if nE < 2, return; end
[h, w] = size(sk);
elab = L(sub2ind([h w], ey, ex));
ecell = cells(sub2ind([h w], ey, ex));
% 各段平均响应
nL = max(L(:));
idxAll = find(L > 0);
segZ = accumarray(L(idxAll), z(idxAll), [nL 1]) ./ max(accumarray(L(idxAll), 1, [nL 1]), 1);
% 端点延伸方向
r = max(3, round(0.6 * pitch));
dirs = zeros(nE, 2);
for i = 1:nE
    ys = max(1, ey(i) - r):min(h, ey(i) + r);
    xs = max(1, ex(i) - r):min(w, ex(i) + r);
    [py, px] = find(L(ys, xs) == elab(i));
    py = py + ys(1) - 1; px = px + xs(1) - 1;
    d = [ex(i) - mean(px), ey(i) - mean(py)];
    if norm(d) < 0.5
        dirs(i, :) = [NaN NaN];    % 极短段：方向不确定，只检查另一端
    else
        dirs(i, :) = d / norm(d);
    end
end
gap = cfg.linkGap * pitch;
gapL = cfg.linkGapLong * pitch;       % 方向高度一致时允许的较长间隔（跨汇流条/焊点）
cosT = cosd(cfg.linkAngle);
cosL = cosd(cfg.linkAngleLong);
pairs = zeros(0, 3);
for i = 1:nE
    if ecell(i) == 0, continue; end
    dx = ex - ex(i); dy = ey - ey(i);
    dist = hypot(dx, dy);
    cand = find(dist <= gapL & dist > 0 & elab ~= elab(i) & ecell == ecell(i));
    cand = cand(cand > i);
    for j = cand'
        v = [dx(j), dy(j)] / dist(j);
        ci = dirs(i, :) * v'; cj = dirs(j, :) * (-v');
        if dist(j) <= gap
            ok = true;
            if ~isnan(ci), ok = ok && ci >= cosT; end
            if ~isnan(cj), ok = ok && cj >= cosT; end
            if isnan(ci) && isnan(cj), ok = false; end
        else
            ok = ~isnan(ci) && ~isnan(cj) && ci >= cosL && cj >= cosL;
        end
        zi = segZ(elab(i)); zj = segZ(elab(j));
        ok = ok && max(zi, zj) <= 4 * max(min(zi, zj), eps);
        if ok
            pairs(end + 1, :) = [dist(j), i, j]; %#ok<AGROW>
        end
    end
end
if isempty(pairs), return; end
pairs = sortrows(pairs, 1);
used = false(nE, 1);
x1 = []; y1 = []; x2 = []; y2 = [];
for p = 1:size(pairs, 1)
    i = pairs(p, 2); j = pairs(p, 3);
    if used(i) || used(j), continue; end
    used(i) = true; used(j) = true;
    x1(end + 1) = ex(i); y1(end + 1) = ey(i); %#ok<AGROW>
    x2(end + 1) = ex(j); y2(end + 1) = ey(j); %#ok<AGROW>
end
nLinks = numel(x1);
linkMask = draw_segments(linkMask, x1, y1, x2, y2, true);
linkMask = linkMask & ~sk;
sk2 = sk | linkMask;
end
