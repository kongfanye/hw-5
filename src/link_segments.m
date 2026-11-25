function [sk2, linkMask, nLinks] = link_segments(sk, z, cells, pitch, cfg, includeTJunctions)
%LINK_SEGMENTS  连接同一有效片内、间隔合理且方向一致的骨架断点（及可选的 T/X 型交点）。
%   1) 沿骨架测地步进估计端点切向（遇分叉点自动截断，不受邻近分支干扰）；
%   2) 两轮共线端点连接：兼容 1-3px 离散化错位、短间距角度匹配与跨汇流条长间距共线匹配；
%   3) T/X 型交点连接（includeTJunctions=true 时）：将指向主裂纹中段的分支端点平滑接入。
if nargin < 6, includeTJunctions = false; end

linkMask = false(size(sk));
nLinks = 0;
skCurr = sk;

for pass = 1:2
    [skNext, lm, nl] = link_endpoints_once(skCurr, z, cells, pitch, cfg);
    if nl == 0, break; end
    skCurr = skNext;
    linkMask = linkMask | lm;
    nLinks = nLinks + nl;
end

if includeTJunctions
    [skNext, lmT, nlT] = link_tjunctions(skCurr, cells, pitch);
    if nlT > 0
        skCurr = skNext;
        linkMask = linkMask | lmT;
        nLinks = nLinks + nlT;
    end
end

linkMask = linkMask & ~sk;
sk2 = skCurr;
end

function [sk2, lm, nLinks] = link_endpoints_once(sk, z, cells, pitch, cfg)
lm = false(size(sk));
nLinks = 0;
sk2 = sk;
L = bwlabel(sk, 8);
nL = max(L(:));
if nL < 2, return; end
ep = bwmorph(sk, 'endpoints');
[ey, ex] = find(ep);
nE = numel(ey);
if nE < 2, return; end
[h, w] = size(sk);
elab = L(sub2ind([h w], ey, ex));
ecell = cells(sub2ind([h w], ey, ex));

idxAll = find(L > 0);
segLen = accumarray(L(idxAll), 1, [nL 1]);
segZ = accumarray(L(idxAll), z(idxAll), [nL 1]) ./ max(segLen, 1);
dirs = endpoint_geodesic_dirs(L, ex, ey, elab, pitch);

gapClose = 0.45 * pitch;
gap = cfg.linkGap * pitch;
gapL = cfg.linkGapLong * pitch;
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
        d = dist(j);
        v = [dx(j), dy(j)] / d;
        di = dirs(i, :); dj = dirs(j, :);
        hasI = ~isnan(di(1)); hasJ = ~isnan(dj(1));
        ci = di * v'; cj = dj * (-v');
        ok = false;
        if d <= 3.5
            if hasI && hasJ
                ok = (-di * dj') >= cosd(50) && ci >= 0.5 && cj >= 0.5;
            elseif hasI
                ok = ci >= 0.5;
            elseif hasJ
                ok = cj >= 0.5;
            else
                ok = d <= 2.0;
            end
        elseif d <= gapClose
            if hasI && hasJ
                mut = -di * dj';
                perp = abs(di(1) * dy(j) - di(2) * dx(j));
                ok = (ci >= cosT && cj >= cosT) || ...
                     (mut >= cosT && ci > 0.2 && cj > 0.2 && perp <= max(3.5, 0.22 * pitch));
            elseif hasI
                ok = ci >= cosT;
            elseif hasJ
                ok = cj >= cosT;
            end
        elseif d <= gap
            ok = true;
            if hasI, ok = ok && ci >= cosT; end
            if hasJ, ok = ok && cj >= cosT; end
            if ~hasI && ~hasJ, ok = false; end
        else
            ok = hasI && hasJ && ci >= cosL && cj >= cosL;
        end
        zi = segZ(elab(i)); zj = segZ(elab(j));
        ok = ok && max(zi, zj) <= 4.5 * max(min(zi, zj), eps);
        if ok
            pairs(end + 1, :) = [d, i, j]; %#ok<AGROW>
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
    if elab(i) == elab(j), continue; end
    used(i) = true; used(j) = true;
    oldLab = elab(j); newLab = elab(i);
    elab(elab == oldLab) = newLab;
    x1(end + 1) = ex(i); y1(end + 1) = ey(i); %#ok<AGROW>
    x2(end + 1) = ex(j); y2(end + 1) = ey(j); %#ok<AGROW>
end
nLinks = numel(x1);
if nLinks > 0
    lm = draw_segments(lm, x1, y1, x2, y2, true);
    sk2 = sk | lm;
end
end

function [sk2, lm, nLinks] = link_tjunctions(sk, cells, pitch)
lm = false(size(sk));
nLinks = 0;
sk2 = sk;
L = bwlabel(sk, 8);
nL = max(L(:));
if nL < 2, return; end
[h, w] = size(sk);
idxAll = find(L > 0);
segLen = accumarray(L(idxAll), 1, [nL 1]);

ep = bwmorph(sk, 'endpoints');
[ey, ex] = find(ep);
nE = numel(ey);
if nE == 0, return; end
elab = L(sub2ind([h w], ey, ex));
ecell = cells(sub2ind([h w], ey, ex));
dirs = endpoint_geodesic_dirs(L, ex, ey, elab, pitch);

maxStep = max(3, round(1.25 * pitch));
x1 = []; y1 = []; x2 = []; y2 = [];
for i = 1:nE
    if ecell(i) == 0 || isnan(dirs(i, 1)), continue; end
    if segLen(elab(i)) < 0.8 * pitch, continue; end
    di = dirs(i, :);
    for t = 1:maxStep
        px = round(ex(i) + t * di(1));
        py = round(ey(i) + t * di(2));
        if px < 2 || px > w - 1 || py < 2 || py > h - 1, break; end
        if cells(py, px) ~= ecell(i), break; end
        nb = L(py-1:py+1, px-1:px+1);
        hit = nb(nb > 0 & nb ~= elab(i));
        if ~isempty(hit)
            target = hit(1);
            if segLen(target) >= 2.0 * pitch
                [hy, hx] = find(nb == target, 1);
                x1(end + 1) = ex(i); y1(end + 1) = ey(i); %#ok<AGROW>
                x2(end + 1) = px + hx - 2; y2(end + 1) = py + hy - 2; %#ok<AGROW>
            end
            break;
        end
    end
end
nLinks = numel(x1);
if nLinks > 0
    lm = draw_segments(lm, x1, y1, x2, y2, true);
    sk2 = sk | lm;
end
end

function dirs = endpoint_geodesic_dirs(L, ex, ey, elab, pitch)
[h, w] = size(L);
nE = numel(ex);
r = max(4, round(0.65 * pitch));
dirs = nan(nE, 2);
if nE == 0, return; end

% 按列优先顺序排列 4-邻域与对角 8-邻域，与局部补丁 find + min(|dy|+|dx|) 完全一致
du = [-1,  0, 0, 1, -1, -1,  1, 1];
dv = [ 0, -1, 1, 0, -1,  1, -1, 1];

chainX = nan(nE, r + 1);
chainY = nan(nE, r + 1);
histIdx = zeros(nE, r + 1);
cnt = ones(nE, 1);

chainX(:, 1) = ex;
chainY(:, 1) = ey;
histIdx(:, 1) = sub2ind([h, w], ey, ex);
active = (1:nE)';

for st = 1:r
    if isempty(active), break; end
    nA = numel(active);
    cx = chainX(active, st);
    cy = chainY(active, st);
    elabA = elab(active);
    histA = histIdx(active, 1:st);

    validK = false(nA, 8);
    candX = zeros(nA, 8);
    candY = zeros(nA, 8);
    candIdx = zeros(nA, 8);
    for k = 1:8
        nx = cx + du(k);
        ny = cy + dv(k);
        inB = nx >= 1 & nx <= w & ny >= 1 & ny <= h;
        % 与半径 r 局部补丁一致：限制在端点周围 [-r, r] 窗口内
        inWin = abs(nx - ex(active)) <= r & abs(ny - ey(active)) <= r;
        okB = inB & inWin;
        nIdx = sub2ind([h, w], min(max(ny, 1), h), min(max(nx, 1), w));
        unvisited = ~any(bsxfun(@eq, histA, nIdx), 2);
        validK(:, k) = okB & (L(nIdx) == elabA) & unvisited;
        candX(:, k) = nx;
        candY(:, k) = ny;
        candIdx(:, k) = nIdx;
    end

    nValid = sum(validK, 2);
    keepMask = (nValid == 1) | (nValid > 1 & st < 5);
    if ~any(keepMask), break; end

    sub = find(keepMask);
    actKeep = active(sub);
    vk = validK(sub, :);
    [~, pick] = max(vk, [], 2);
    linPick = sub2ind(size(vk), (1:numel(sub))', pick);
    cxSub = candX(sub, :);
    cySub = candY(sub, :);
    ciSub = candIdx(sub, :);

    chainX(actKeep, st + 1) = cxSub(linPick);
    chainY(actKeep, st + 1) = cySub(linPick);
    histIdx(actKeep, st + 1) = ciSub(linPick);
    cnt(actKeep) = st + 1;
    active = actKeep;
end

for i = 1:nE
    c = cnt(i);
    if c >= 3
        tail = max(2, ceil(0.4 * c)):c;
        d = [ex(i) - mean(chainX(i, tail)), ey(i) - mean(chainY(i, tail))];
        nd = hypot(d(1), d(2));
        if nd >= 0.5
            dirs(i, :) = d / nd;
        end
    end
end
end
