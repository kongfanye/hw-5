function res = segment_cracks(Rs, I, cfg, wantDebug)
%SEGMENT_CRACKS  改进法后半段：脊线非极大值抑制 -> 双阈值滞后连接 -> 骨架化
%   -> 多轮共线/T型断点连接 -> 双准则形状方向筛选 -> 联合延伸生长与次生裂纹回收
%   -> 映射回原图 -> 判定。
if nargin < 4, wantDebug = false; end
prep = Rs.prep; pitch = prep.pitch; valid = prep.valid;
z = Rs.z; resp = Rs.resp; oriK = Rs.oriK; oriDeg = Rs.oriDeg; busBand = Rs.busBand;

% 强亮划痕邻域掩膜：仅抑制面积显著的表面强亮纹（R2 > 0.095）伴生暗边，避免误伤正常栅线间隙
brightThr = 0.095;
if isfield(cfg, 'brightScratchThresh'), brightThr = cfg.brightScratchThresh; end
if isfield(Rs, 'R2') && ~isempty(Rs.R2)
    brightStreak = (Rs.R2 > brightThr) & ~busBand & valid;
    brightStreak = bwareaopen(brightStreak, max(8, round(0.8 * pitch^2)));
    brightHalo = disk_dilate(brightStreak, round(0.28 * pitch));
else
    brightHalo = false(size(z));
end

% ---------- 4. 法向非极大值抑制 + 双阈值滞后连接 ----------
ridge = ridge_nms(z, oriK, cfg.nOrient) & valid;
horiz = min(oriDeg, 180 - oriDeg) <= cfg.parallelTol;
ridge(busBand & horiz) = false;
if cfg.useRidgeNms
    lowR = ridge & z >= cfg.zLow;
    lowC = bwmorph(lowR, 'bridge');
else
    lowC = z >= cfg.zLow & valid;
    lowC(busBand & horiz) = false;
end
zOff = 0.7;
if isfield(cfg, 'zCandOffset'), zOff = cfg.zCandOffset; end
zCandSeed = max(cfg.zLow + 0.5, cfg.zHigh - zOff);
seeds = lowC & ridge & z >= zCandSeed;
cand = imreconstruct(seeds, lowC, 8);

% ---------- 5. 骨架化与断点连接 ----------
sk = bwmorph(cand, 'thin', Inf);
sk = bwareaopen(sk, max(2, round(cfg.minSkelLen * pitch)), 8);
[sk2, linkMask, nLinks] = link_segments(sk, z, prep.cells, pitch, cfg);
widthArea = (z >= cfg.zLow & valid) | sk2;

% ---------- 6. 候选特征与双准则筛选 ----------
L = bwlabel(sk2, 8);
n = max(L(:));
F = component_features(L, z, resp, widthArea, linkMask, busBand, brightHalo, pitch);
maxWidPx = max(cfg.maxWidth * pitch, 3.5);
maxFaintWidPx = max(0.26 * pitch, 3.2);
if n > 0
    dF = abs(F.angle - 90);
    dB = min(F.angle, 180 - F.angle);
    lenP = F.len / pitch; spanP = F.span / pitch;
    parF = dF <= cfg.parallelTol;
    parB = dB <= cfg.parallelTol;

    % 准则 1：标准高置信隐裂（随 zHigh、minLength、minMeanZ、minCross 同步调节）
    realP = F.realLen / pitch;
    realOk = F.realLen >= 0.55 * F.len & realP >= 0.75 * cfg.minLength;
    base1 = F.maxZ >= cfg.zHigh & F.meanZ >= cfg.minMeanZ & F.width <= maxWidPx & realOk;
    okF = parF & lenP >= cfg.minLenParFinger;
    okB = parB & lenP >= cfg.minLenParBusbar;
    okD = ~parF & ~parB & F.nCross >= cfg.minCross;
    notBus = F.busFrac <= cfg.maxBusbarFrac;
    strong1 = base1 & notBus & F.brightFrac <= 0.60 & lenP >= cfg.minLength & (okF | okB | okD);

    % 准则 2：长程共线淡隐裂（峰值略低于 zHigh，但连续跨越 >=4 根细栅且长而直、远离汇流条）
    faintLen = max(cfg.minFaintLen, 1.8 * cfg.minLength);
    faintCross = max(cfg.minFaintCross, 1.8 * cfg.minCross);
    faintMeanZ = max(cfg.minFaintMeanZ, cfg.minMeanZ - 0.30);
    strong2 = F.maxZ >= zCandSeed & F.meanZ >= faintMeanZ & ...
              F.realLen >= 0.60 * F.len & realP >= 0.75 * faintLen & ...
              F.width <= maxFaintWidPx & F.busFrac <= min(0.30, cfg.maxBusbarFrac) & ...
              F.brightFrac <= 0.35 & ~parF & ~parB & ...
              lenP >= faintLen & F.nCross >= faintCross & spanP >= 0.75 * faintLen;

    strong = strong1 | strong2;
    weak = ~strong & F.maxZ >= cfg.zHigh & F.meanZ >= cfg.minMeanZ & F.width <= maxWidPx & ...
           F.realLen >= 0.55 * F.len & ~parF & lenP >= cfg.reviewFrac * cfg.minLength & ...
           F.nCross >= cfg.reviewFrac * cfg.minCross & ...
           F.busFrac <= min(0.35, cfg.maxBusbarFrac) & F.brightFrac <= 0.60;
else
    strong = false(0, 1); weak = false(0, 1);
end

sIdx = find(strong);
[~, o] = sort(F.len(sIdx), 'descend');
sIdx = sIdx(o);
nS = numel(sIdx);
map = zeros(n + 1, 1);
map(sIdx + 1) = 1:nS;
Lfin = reshape(map(L + 1), size(L));

finWidth = F.width(sIdx);
finMeanZ = F.meanZ(sIdx);
finMeanResp = F.meanResp(sIdx);
finNCross = F.nCross(sIdx);

% ---- 6b. 确认存在隐裂后的共线延伸、分支生长与同片次生淡裂纹回收（仅 nS > 0 时执行）----
nGrown = 0;
if nS > 0 && cfg.growIter > 0
    growLow = max(1.8, min(cfg.growLowZ, cfg.zLow - 0.3));
    lowC2 = z >= growLow & valid;
    lowC2(busBand & horiz) = false;
    seeds2 = (lowC2 & ridge & z >= cfg.growSeedZ) | (Lfin > 0);
    cand2 = imreconstruct(seeds2, lowC2 | (Lfin > 0), 8);
    skAll = bwmorph(cand2, 'thin', Inf);
    skAll = bwareaopen(skAll, max(2, round(cfg.minSkelLen * pitch)), 8) | (Lfin > 0);
    skAll = bwmorph(skAll, 'thin', Inf);
    [skLinked, lmAll, ~] = link_segments(skAll, z, prep.cells, pitch, cfg, true);
    sk3 = skLinked & ~(Lfin > 0);
    L3 = bwlabel(sk3, 8);
    n3 = max(L3(:));
    if n3 > 0
        F3 = component_features(L3, z, resp, widthArea | cand2, lmAll, busBand, brightHalo, pitch);
        l3 = F3.len / pitch; sp3 = F3.span / pitch;
        dF3 = abs(F3.angle - 90); dB3 = min(F3.angle, 180 - F3.angle);
        parF3 = dF3 <= cfg.parallelTol; parB3 = dB3 <= cfg.parallelTol;

        % (a) 与已确认裂纹连通或邻近的延伸段与网状分叉段
        okNear = F3.width <= maxWidPx & F3.meanZ >= cfg.growMinZ & l3 >= cfg.growMinLen & ...
                 F3.busFrac <= cfg.maxBusbarFrac & F3.brightFrac <= 0.40 & ...
                 ~(parF3 & l3 < cfg.minLenParFinger);
        acc = Lfin > 0;
        addedNear = false(n3, 1);
        idx3 = find(L3 > 0);
        for it = 1:cfg.growIter
            D = bwdist(acc);
            dmin = accumarray(L3(idx3), D(idx3), [n3 1], @min);
            nw = okNear & ~addedNear & dmin <= cfg.growDist * pitch;
            if ~any(nw), break; end
            addedNear = addedNear | nw;
            acc = acc | ismember(L3, find(nw));
        end
        if any(addedNear)
            [D0, ~] = bwdist(Lfin > 0);
            nearIds = find(addedNear);
            dOrder = zeros(numel(nearIds), 1);
            for q = 1:numel(nearIds)
                dOrder(q) = min(D0(L3 == nearIds(q)));
            end
            [~, ordN] = sort(dOrder, 'ascend');
            nearIds = nearIds(ordN);
            for q = 1:numel(nearIds)
                cid = nearIds(q);
                cm = (L3 == cid);
                cidx = find(cm);
                [Dcur, nearCur] = bwdist(Lfin > 0);
                [dBest, pBest] = min(Dcur(cidx));
                idTarget = Lfin(nearCur(cidx(pBest)));
                Lfin(cm) = idTarget;
                linkMask = linkMask | (lmAll & cm);
                if dBest > 1 && dBest <= 1.8 * pitch
                    [yA, xA] = ind2sub(size(Lfin), cidx(pBest));
                    [yB, xB] = ind2sub(size(Lfin), nearCur(cidx(pBest)));
                    bridge = draw_segments(false(size(Lfin)), xA, yA, xB, yB, true);
                    Lfin(bridge & Lfin == 0) = idTarget;
                    linkMask = linkMask | bridge;
                end
            end
            nGrown = nGrown + nnz(addedNear);
        end

        % (b) 同片独立长程次生淡裂纹（独立编号）
        okSecDiag = ~parF3 & ~parB3 & l3 >= cfg.secMinLen & F3.nCross >= cfg.secMinCross & sp3 >= 3.4;
        okSecBus  = parB3 & ~parF3 & l3 >= max(5.5, cfg.minLenParBusbar) & F3.busFrac <= 0.20 & sp3 >= 4.5;
        okSec = ~addedNear & F3.realLen >= 0.55 * F3.len & F3.width <= maxFaintWidPx & ...
                F3.maxZ >= cfg.secMinMaxZ & F3.meanZ >= cfg.secMinMeanZ & ...
                F3.busFrac <= 0.30 & F3.brightFrac <= 0.35 & (okSecDiag | okSecBus);
        secIds = find(okSec);
        if ~isempty(secIds)
            [~, os] = sort(F3.len(secIds), 'descend');
            secIds = secIds(os);
            for q = 1:numel(secIds)
                cid = secIds(q);
                nS = nS + 1;
                cm = (L3 == cid);
                Lfin(cm) = nS;
                linkMask = linkMask | (lmAll & cm);
                finWidth(nS, 1) = F3.width(cid);
                finMeanZ(nS, 1) = F3.meanZ(cid);
                finMeanResp(nS, 1) = F3.meanResp(cid);
                finNCross(nS, 1) = F3.nCross(cid);
            end
            nGrown = nGrown + numel(secIds);
        end
    end

    for k = 1:nS
        [~, uk] = find(Lfin == k);
        if ~isempty(uk)
            finNCross(k) = (max(uk) - min(uk)) / pitch;
        end
    end
end

% ---------- 7. 映射回原图 ----------
oriMap = oriDeg;
if n > 0
    lm = linkMask & L > 0;
    oriMap(lm) = F.angle(L(lm));
end
needOri = (Lfin > 0) & isnan(oriMap);
if any(needOri(:))
    for k = 1:nS
        mk = (Lfin == k);
        if any(mk(:) & isnan(oriMap(:)))
            [vk, uk] = find(mk);
            angK = mod(0.5 * atan2d(2 * cov_uv(uk, vk), var_u(uk) - var_u(vk)), 180);
            oriMap(mk & isnan(oriMap)) = angK;
        end
    end
end

if isempty(I)
    out.Lfull = zeros(0, 0, 'uint16'); out.mask = false(0, 0);
    out.cracks = struct('id', num2cell(1:nS));
else
    out = skeleton_to_full(prep, Lfin, oriMap, finWidth, I, cfg, 200);
end
cr = out.cracks;
for i = 1:numel(cr)
    k = cr(i).id;
    cr(i).mean_z = round(finMeanZ(k) * 100) / 100;
    cr(i).contrast_pct = round(finMeanResp(k) * 1000) / 10;
    cr(i).n_fingers_crossed = round(finNCross(k) * 10) / 10;
end

% ---------- 8. 判定 ----------
reasons = prep.reviewReasons;
nW = nnz(weak);
if nS > 0
    statusCode = 'crack';
elseif ~isempty(reasons)
    statusCode = 'review';
elseif nW > 0
    statusCode = 'review';
    reasons{end + 1} = sprintf('有 %d 条接近阈值的弱暗纹候选', nW);
else
    statusCode = 'no_crack';
end
res = assemble_result('improved', statusCode, cr, out, prep, reasons);
res.diag.nCandidates = n;
res.diag.nWeak = nW;
res.diag.nLinks = nLinks;
res.diag.nGrown = nGrown;
if wantDebug
    cls = zeros(size(L), 'uint8');
    cls(cand) = 1;
    if n > 0
        cls(ismember(L, find(weak))) = 2;
    end
    cls(Lfin > 0) = 3;
    cls(linkMask & Lfin > 0) = 4;
    res.debug.prep = prep;
    res.debug.Dn = Rs.Dn;
    res.debug.R2 = Rs.R2;
    res.debug.z = z;
    res.debug.zRaw = Rs.zRaw;
    res.debug.cls = cls;
    res.debug.busBand = busBand;
    res.debug.features = F;
    res.debug.strong = strong;
    res.debug.weak = weak;
end
end

function c = cov_uv(u, v)
u = u - mean(u); v = v - mean(v);
c = mean(u .* v);
end

function s = var_u(u)
u = u - mean(u);
s = mean(u.^2);
end

function F = component_features(L, z, resp, area, linkMask, busBand, brightHalo, pitch)
n = max(L(:));
F.len = zeros(n, 1); F.realLen = F.len; F.meanZ = F.len; F.maxZ = F.len; F.width = F.len;
F.nCross = F.len; F.span = F.len; F.angle = F.len; F.busFrac = F.len;
F.brightFrac = F.len; F.meanResp = F.len;
if n == 0, return; end
idx = find(L > 0);
lab = L(idx);
[v, u] = ind2sub(size(L), idx);
F.len = accumarray(lab, 1, [n 1]);
isL = linkMask(idx);
zc = accumarray(lab(~isL), 1, [n 1]);
F.realLen = zc;
F.meanZ = accumarray(lab(~isL), z(idx(~isL)), [n 1]) ./ max(zc, 1);
F.maxZ = accumarray(lab(~isL), z(idx(~isL)), [n 1], @max, 0);
F.meanResp = accumarray(lab(~isL), resp(idx(~isL)), [n 1]) ./ max(zc, 1);
dt = bwdist(~area);
F.width = accumarray(lab, max(1, 2 * dt(idx) - 1), [n 1]) ./ F.len;
umin = accumarray(lab, u, [n 1], @min); umax = accumarray(lab, u, [n 1], @max);
vmin = accumarray(lab, v, [n 1], @min); vmax = accumarray(lab, v, [n 1], @max);
F.nCross = (umax - umin) / pitch;
F.span = hypot(umax - umin, vmax - vmin);
su = accumarray(lab, u, [n 1]) ./ F.len; sv = accumarray(lab, v, [n 1]) ./ F.len;
cuu = accumarray(lab, u.^2, [n 1]) ./ F.len - su.^2;
cvv = accumarray(lab, v.^2, [n 1]) ./ F.len - sv.^2;
cuv = accumarray(lab, u .* v, [n 1]) ./ F.len - su .* sv;
F.angle = mod(0.5 * atan2d(2 * cuv, cuu - cvv), 180);
F.busFrac = accumarray(lab(~isL), double(busBand(idx(~isL))), [n 1]) ./ max(zc, 1);
F.brightFrac = accumarray(lab(~isL), double(brightHalo(idx(~isL))), [n 1]) ./ max(zc, 1);
end
