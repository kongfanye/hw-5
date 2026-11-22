function res = segment_cracks(Rs, I, cfg, wantDebug)
%SEGMENT_CRACKS  改进法后半段：脊线非极大值抑制 -> 双阈值滞后连接 -> 骨架化
%   -> 断点连接 -> 形状/方向筛选 -> 映射回原图 -> 判定。
if nargin < 4, wantDebug = false; end
prep = Rs.prep; pitch = prep.pitch; valid = prep.valid;
z = Rs.z; resp = Rs.resp; oriK = Rs.oriK; oriDeg = Rs.oriDeg; busBand = Rs.busBand;

% ---------- 4. 法向非极大值抑制 + 双阈值滞后连接 ----------
ridge = ridge_nms(z, oriK, cfg.nOrient) & valid;
horiz = min(oriDeg, 180 - oriDeg) <= cfg.parallelTol;
ridge(busBand & horiz) = false;         % 汇流条带内去掉平行主栅的响应，保留交叉暗纹
if cfg.useRidgeNms
    lowR = ridge & z >= cfg.zLow;
    % 脊线可能有 1 像素错位，先用 bridge 补上单像素断开再求连通
    lowC = bwmorph(lowR, 'bridge');
else
    lowC = z >= cfg.zLow & valid;
    lowC(busBand & horiz) = false;
end
seeds = lowC & ridge & z >= cfg.zHigh;
cand = imreconstruct(seeds, lowC, 8);

% ---------- 5. 骨架化与断点连接 ----------
sk = bwmorph(cand, 'thin', Inf);
sk = bwareaopen(sk, max(2, round(cfg.minSkelLen * pitch)), 8);
[sk2, linkMask, nLinks] = link_segments(sk, z, prep.cells, pitch, cfg);
% 宽度用阈值区域（非脊线）估计
widthArea = (z >= cfg.zLow & valid) | sk2;

% ---------- 6. 候选特征与筛选 ----------
L = bwlabel(sk2, 8);
n = max(L(:));
F = component_features(L, z, resp, widthArea, linkMask, busBand, pitch);
if n > 0
    dF = abs(F.angle - 90);                         % 与细栅夹角
    dB = min(F.angle, 180 - F.angle);               % 与主栅夹角
    lenP = F.len / pitch; widP = F.width / pitch;
    base = F.meanZ >= cfg.minMeanZ & widP <= cfg.maxWidth;
    parF = dF <= cfg.parallelTol;
    parB = dB <= cfg.parallelTol;
    okF = parF & lenP >= cfg.minLenParFinger;
    okB = parB & lenP >= cfg.minLenParBusbar;
    okD = ~parF & ~parB & F.nCross >= cfg.minCross;
    notBus = F.busFrac <= cfg.maxBusbarFrac;          % 基本落在汇流条带内的候选视为汇流条结构
    strong = base & notBus & lenP >= cfg.minLength & (okF | okB | okD);
    weak = ~strong & base & ~parF & lenP >= cfg.reviewFrac * cfg.minLength & ...
        F.nCross >= cfg.reviewFrac * cfg.minCross & F.busFrac <= cfg.maxBusbarFrac;
else
    strong = false(0, 1); weak = false(0, 1);
end
sIdx = find(strong);
[~, o] = sort(F.len(sIdx), 'descend');
sIdx = sIdx(o);
nS = numel(sIdx);
map = zeros(n + 1, 1);
map(sIdx + 1) = 1:nS;
% ---- 分支生长：只在已有确认裂纹时进行（不改变无裂纹图像的判定）----
%      用较低的种子阈值 growSeedZ 另取一套候选，与已确认裂纹相距 <= growDist 且
%      形态合格（宽度、平均响应、长度，非汇流条结构，非短的平行细栅段）的线段
%      逐步并入最近的裂纹，用于保留分叉和较弱的延伸段。
Lfin = reshape(map(L + 1), size(L));
nGrown = 0;
if nS > 0 && cfg.growIter > 0
    seeds2 = lowC & ridge & z >= cfg.growSeedZ;
    cand2 = imreconstruct(seeds2, lowC, 8) & ~imdilate(Lfin > 0, disk_mask(2));
    sk3 = bwmorph(cand2, 'thin', Inf);
    sk3 = bwareaopen(sk3, max(2, round(cfg.minSkelLen * pitch)), 8);
    L3 = bwlabel(sk3, 8);
    n3 = max(L3(:));
    if n3 > 0
        F3 = component_features(L3, z, resp, widthArea | cand2, false(size(L3)), busBand, pitch);
        l3 = F3.len / pitch;
        okG = F3.width / pitch <= cfg.maxWidth & F3.meanZ >= cfg.growMinZ & l3 >= cfg.growMinLen & ...
            F3.busFrac <= cfg.maxBusbarFrac & ~(abs(F3.angle - 90) <= cfg.parallelTol & l3 < cfg.minLenParFinger);
        acc = Lfin > 0;
        added = false(n3, 1);
        idx3 = find(L3 > 0);
        for it = 1:cfg.growIter
            D = bwdist(acc);
            dmin = accumarray(L3(idx3), D(idx3), [n3 1], @min);
            nw = okG & ~added & dmin <= cfg.growDist * pitch;
            if ~any(nw), break; end
            added = added | nw;
            acc = acc | ismember(L3, find(nw));
        end
        if any(added)
            [~, near] = bwdist(Lfin > 0);
            gm = ismember(L3, find(added));
            Lfin(gm) = Lfin(near(gm));
            nGrown = nnz(added);
        end
    end
end

% ---------- 7. 映射回原图 ----------
oriMap = oriDeg;
if n > 0
    lm = linkMask & L > 0;
    oriMap(lm) = F.angle(L(lm));
end
widthA = F.width(sIdx);
if isempty(I)        % 仅判定（调参用），不做原图映射
    out.Lfull = zeros(0, 0, 'uint16'); out.mask = false(0, 0);
    out.cracks = struct('id', num2cell(1:nS));
else
    out = skeleton_to_full(prep, Lfin, oriMap, widthA, I, cfg, 200);
end
cr = out.cracks;
for i = 1:numel(cr)
    k = sIdx(cr(i).id);
    cr(i).mean_z = round(F.meanZ(k) * 100) / 100;
    cr(i).contrast_pct = round(F.meanResp(k) * 1000) / 10;   % 中心相对两侧暗多少 (%)
    cr(i).n_fingers_crossed = round(F.nCross(k) * 10) / 10;
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


function F = component_features(L, z, resp, area, linkMask, busBand, pitch)
% 每个骨架连通段的特征（对齐坐标系，细栅竖直）。
n = max(L(:));
F.len = zeros(n, 1); F.meanZ = F.len; F.width = F.len; F.nCross = F.len;
F.angle = F.len; F.busFrac = F.len; F.meanResp = F.len;
if n == 0, return; end
idx = find(L > 0);
lab = L(idx);
[v, u] = ind2sub(size(L), idx);
F.len = accumarray(lab, 1, [n 1]);
isL = linkMask(idx);
zc = accumarray(lab(~isL), 1, [n 1]);
F.meanZ = accumarray(lab(~isL), z(idx(~isL)), [n 1]) ./ max(zc, 1);
F.meanResp = accumarray(lab(~isL), resp(idx(~isL)), [n 1]) ./ max(zc, 1);
dt = bwdist(~area);
F.width = accumarray(lab, max(1, 2 * dt(idx) - 1), [n 1]) ./ F.len;
umin = accumarray(lab, u, [n 1], @min); umax = accumarray(lab, u, [n 1], @max);
F.nCross = (umax - umin) / pitch;
su = accumarray(lab, u, [n 1]) ./ F.len; sv = accumarray(lab, v, [n 1]) ./ F.len;
cuu = accumarray(lab, u.^2, [n 1]) ./ F.len - su.^2;
cvv = accumarray(lab, v.^2, [n 1]) ./ F.len - sv.^2;
cuv = accumarray(lab, u .* v, [n 1]) ./ F.len - su .* sv;
F.angle = mod(0.5 * atan2d(2 * cuv, cuu - cvv), 180);
F.busFrac = accumarray(lab, double(busBand(idx)), [n 1]) ./ F.len;
end
