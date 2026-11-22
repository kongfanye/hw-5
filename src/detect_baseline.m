function res = detect_baseline(I, cfg, wantDebug)
%DETECT_BASELINE  基线：在有效区对 max(B - I, 0) 做全局稳健阈值分割，
%   再按面积和主轴长度做简单连通域筛选。与改进法共用有效区、背景 B、
%   工作尺度和原图映射，只缺少栅线抑制、方向性暗线增强和形状/方向筛选。
if nargin < 3, wantDebug = false; end
t0 = tic;
prep = prepare_image(I, cfg);
pitch = prep.pitch; valid = prep.valid;
D = prep.B - prep.Ia;
D(D < 0) = 0;
D(~valid | isnan(D)) = NaN;
[med, sd] = robust_stats(D(valid));
T = med + cfg.base.k * sd;
bw = D > T & valid;
bw = bwareaopen(bw, max(2, round(cfg.base.minArea * pitch^2)), 8);
L0 = bwlabel(bw, 8);
n0 = max(L0(:));
st = regionprops(L0, 'MajorAxisLength', 'Area');
if n0 > 0
    maj = [st.MajorAxisLength]';
    keep = find(maj >= cfg.base.minLength * pitch);
else
    keep = zeros(0, 1);
end
area = zeros(n0, 1);
if n0 > 0, area = [st.Area]'; end
[~, o] = sort(area(keep), 'descend');
keep = keep(o);
map = zeros(n0 + 1, 1); map(keep + 1) = 1:numel(keep);
Lk = reshape(map(L0 + 1), size(L0));
sk = bwmorph(Lk > 0, 'thin', Inf);
Lsk = Lk; Lsk(~sk) = 0;
nK = numel(keep);
idx = find(Lsk > 0); lab = Lsk(idx);
[v, u] = ind2sub(size(Lsk), idx);
oriMap = nan(size(Lsk));
widthA = ones(nK, 1);
if nK > 0
    cnt = accumarray(lab, 1, [nK 1]);
    su = accumarray(lab, u, [nK 1]) ./ cnt; sv = accumarray(lab, v, [nK 1]) ./ cnt;
    cuu = accumarray(lab, u.^2, [nK 1]) ./ cnt - su.^2;
    cvv = accumarray(lab, v.^2, [nK 1]) ./ cnt - sv.^2;
    cuv = accumarray(lab, u .* v, [nK 1]) ./ cnt - su .* sv;
    ang = mod(0.5 * atan2d(2 * cuv, cuu - cvv), 180);
    oriMap(idx) = ang(lab);
    widthA = area(keep) ./ max(cnt, 1);
end
out = skeleton_to_full(prep, Lsk, oriMap, widthA, I, cfg, 30);
reasons = prep.reviewReasons;
if nK > 0
    statusCode = 'crack';
elseif ~isempty(reasons)
    statusCode = 'review';
else
    statusCode = 'no_crack';
end
res = assemble_result('baseline', statusCode, out.cracks, out, prep, reasons);
res.diag.threshold = T;
res.diag.nCandidates = n0;
res.diag.runtime_s = toc(t0);
if wantDebug
    cls = zeros(size(L0), 'uint8');
    cls(L0 > 0) = 1;
    cls(Lk > 0) = 3;
    res.debug.prep = prep;
    res.debug.D = D;
    res.debug.cls = cls;
end
end
