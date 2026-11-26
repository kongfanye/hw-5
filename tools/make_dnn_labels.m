function make_dnn_labels(names)
%MAKE_DNN_LABELS  为深度网络生成半自动像素标签（只用于训练网络，检测流程不读取）。
%
%   make_dnn_labels              处理 cracked/ 与 uncracked/ 中的全部图像
%   make_dnn_labels({'cracked_07'})  只处理指定图像（不含扩展名）
%
%   参考工程（Tabernik 等方法）依靠人工逐像素涂出的裂纹掩膜训练网络。本项目没有逐像素掩膜，
%   这里用两种已有信息半自动生成：
%     1) 传统方法（改进法）在对齐坐标系中检出的裂纹中心线；
%     2) data/annotations.json 中的人工参考折线：沿折线每隔约 1.5 px 取点，在法向 ±1 个栅距内
%        找方向一致的暗线响应最大处（z ≥ labelZAccept），把折线“吸附”到真实暗线脊上。
%   正样本 = 两者并集（宽约 3 个工作像素）。不确定像素设为“忽略”（训练时不计损失）：
%     - 折线吸附失败处的走廊（该处裂纹太淡或被遮挡，无法确定确切位置）；
%     - 正样本两侧 2 个工作像素的过渡带；
%     - 参考区域框内、未被标为裂纹的强暗线候选（多为未逐条描线的网状细分支）。
%   无隐裂图像全部像素为负样本。
%   输出：data/dnn_labels/<名称>.png（原图尺寸，0 = 背景，255 = 裂纹，128 = 忽略）
%         data/dnn_labels/preview/<名称>.jpg（红 = 裂纹，黄 = 忽略，便于人工核查）
root = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root, 'src'));
check_requirements();
cfg = crack_config();
lc = struct('corridor', 1.0, 'zAccept', 2.5, 'oriTol', 30, 'step', 1.5, ...
    'medWin', 9, 'medTol', 3, 'posRadius', 1, 'ringRadius', 3);
outDir = fullfile(root, 'data', 'dnn_labels');
if exist(fullfile(outDir, 'preview'), 'dir') ~= 7, mkdir(fullfile(outDir, 'preview')); end
A = jsondecode(read_text_utf8(fullfile(root, 'data', 'annotations.json')));
ann = A.images;
if isstruct(ann), ann = num2cell(ann); end
annFiles = cellfun(@(a) a.file, ann, 'UniformOutput', false);
files = list_images({fullfile(root, 'cracked'), fullfile(root, 'uncracked')}, false);
if nargin >= 1 && ~isempty(names)
    files = files(ismember({files.stem}, names));
end
for i = 1:numel(files)
    f = files(i);
    t0 = tic;
    [G, RGB] = read_gray(f.path);
    [H, W] = size(G);
    k = find(strcmp(annFiles, f.relpath), 1);
    pl = {};
    regions = zeros(0, 4);
    if ~isempty(k)
        pl = ann{k}.polylines;
        if isstruct(pl), pl = num2cell(pl); end
        regions = ann{k}.regions;
    end
    if isempty(pl)
        lab = zeros(H, W, 'uint8');
        imwrite(lab, fullfile(outDir, [f.stem '.png']));
        write_preview(RGB, lab, fullfile(outDir, 'preview', [f.stem '.jpg']));
        fprintf('%s：无参考裂纹，全部为负样本（%.1fs）\n', f.relpath, toc(t0));
        continue;
    end
    Rs = crack_response(G, cfg);
    res = segment_cracks(Rs, G, cfg, true);
    prep = Rs.prep; g = prep.geom; pitch = prep.pitch;
    z = Rs.z; ori = Rs.oriDeg; valid = prep.valid;
    [ha, wa] = size(z);
    det = res.debug.cls >= 3;                    % 传统方法最终裂纹（含断点连接）
    snapped = false(ha, wa);
    ign = false(ha, wa);
    R = max(3, round(lc.corridor * pitch));
    nAcc = 0; nTot = 0;
    for j = 1:numel(pl)
        P = double(pl{j}.points);
        [u, v] = full_to_aligned(P(:, 1), P(:, 2), g);
        [u, v] = densify(u, v, lc.step);
        n = numel(u);
        if n < 3, continue; end
        tu = gradient(u); tv = gradient(v);
        tl = max(hypot(tu, tv), eps); tu = tu ./ tl; tv = tv ./ tl;
        nu = -tv; nv = tu;
        phi = mod(atan2d(tv, tu), 180);
        offs = -R:R;
        best = nan(n, 1); bz = zeros(n, 1);
        for q = 1:n
            uu = round(u(q) + offs * nu(q)); vv = round(v(q) + offs * nv(q));
            ok = uu >= 1 & uu <= wa & vv >= 1 & vv <= ha;
            if ~any(ok), continue; end
            id = sub2ind([ha wa], vv(ok), uu(ok));
            zz = z(id); oo = ori(id);
            d = abs(mod(oo - phi(q) + 90, 180) - 90);
            w = ones(size(zz)); w(isnan(d) | d > lc.oriTol) = 0.25;
            sc = zz(:) .* w(:);
            [m, im] = max(sc);
            oo2 = offs(ok);
            if m > 0
                best(q) = oo2(im); bz(q) = zz(im);
            end
        end
        acc = bz >= lc.zAccept & isfinite(best);
        % 吸附偏移沿折线做中值平滑，剔除跳到相邻栅线或其他裂纹上的离群点
        medv = best;
        hw = floor(lc.medWin / 2);
        for q = 1:n
            r = max(1, q - hw):min(n, q + hw);
            b = best(r(acc(r)));
            if ~isempty(b), medv(q) = median(b); end
        end
        acc = acc & abs(best - medv) <= lc.medTol;
        nAcc = nAcc + nnz(acc); nTot = nTot + n;
        su = u + best .* nu; sv = v + best .* nv;
        for q = 1:n - 1
            if acc(q) && acc(q + 1)
                snapped = draw_segments(snapped, round(su(q)), round(sv(q)), round(su(q + 1)), round(sv(q + 1)), true);
            end
        end
        % 吸附失败的点：其走廊内无法确定裂纹确切位置，设为忽略
        for q = find(~acc(:))'
            ign = paint_disk(ign, u(q), v(q), R);
        end
    end
    pos = imdilate(det | snapped, disk_mask(lc.posRadius));
    ign = ign | (pos & ~valid);                  % 亮缝 / 过曝中看不见的部分不当作正样本
    pos = pos & valid;
    ring = imdilate(pos, disk_mask(lc.ringRadius)) & ~pos;
    ign = ign | ring;
    % 参考区域框内未标为裂纹的强暗线候选：多为未逐条描线的细分支，设为忽略
    regA = false(ha, wa);
    [UU, VV] = meshgrid(1:wa, 1:ha);
    [Xf, Yf] = aligned_to_full(UU, VV, g);
    for r = 1:size(regions, 1)
        b = regions(r, :);
        regA = regA | (Xf >= b(1) & Xf <= b(3) & Yf >= b(2) & Yf <= b(4));
    end
    candOther = (res.debug.cls == 1 | res.debug.cls == 2) & regA & ~pos;
    ign = ign | imdilate(candOther, disk_mask(2));
    labA = zeros(ha, wa, 'uint8');
    labA(ign) = 128;
    labA(pos) = 255;
    % 对齐坐标 → 工作图 → 原图（最近邻）
    labW = from_aligned(double(labA), g, 'nearest');
    labW(isnan(labW)) = 0;
    [hw2, ww2] = size(labW);
    rr = min(hw2, max(1, round(((1:H) - 0.5) * g.s + 0.5)));
    cc = min(ww2, max(1, round(((1:W) - 0.5) * g.s + 0.5)));
    lab = uint8(labW(rr, cc));
    imwrite(lab, fullfile(outDir, [f.stem '.png']));
    write_preview(RGB, lab, fullfile(outDir, 'preview', [f.stem '.jpg']));
    fprintf('%s：传统检出 %d px，折线吸附成功 %d/%d 点，正样本 %.2f%%，忽略 %.2f%%（%.1fs）\n', ...
        f.relpath, nnz(det), nAcc, nTot, 100 * nnz(lab == 255) / numel(lab), ...
        100 * nnz(lab == 128) / numel(lab), toc(t0));
end
end

function [u, v] = full_to_aligned(X, Y, g)
xw = (X - 0.5) * g.s + 0.5; yw = (Y - 0.5) * g.s + 0.5;
dx = xw - g.c(1); dy = yw - g.c(2);
u = g.ca(1) + dx * g.g(1) + dy * g.g(2);
v = g.ca(2) + dx * g.f(1) + dy * g.f(2);
end

function [uo, vo] = densify(u, v, step)
uo = []; vo = [];
for i = 1:numel(u) - 1
    L = hypot(u(i + 1) - u(i), v(i + 1) - v(i));
    n = max(2, ceil(L / step) + 1);
    t = linspace(0, 1, n)';
    if i > 1, t = t(2:end); end
    uo = [uo; u(i) + t * (u(i + 1) - u(i))]; %#ok<AGROW>
    vo = [vo; v(i) + t * (v(i + 1) - v(i))]; %#ok<AGROW>
end
end

function M = paint_disk(M, cu, cv, r)
[h, w] = size(M);
u1 = max(1, floor(cu - r)); u2 = min(w, ceil(cu + r));
v1 = max(1, floor(cv - r)); v2 = min(h, ceil(cv + r));
if u1 > u2 || v1 > v2, return; end
[UU, VV] = meshgrid(u1:u2, v1:v2);
M(v1:v2, u1:u2) = M(v1:v2, u1:u2) | ((UU - cu) .^ 2 + (VV - cv) .^ 2 <= r ^ 2);
end

function write_preview(RGB, lab, path)
[H, W, ~] = size(RGB);
k = min(1, 1400 / max(H, W));
P = block_reduce(RGB, max(1, ceil(1 / k)));
rr = min(H, max(1, round(((1:size(P, 1)) - 0.5) * H / size(P, 1) + 0.5)));
cc = min(W, max(1, round(((1:size(P, 2)) - 0.5) * W / size(P, 2) + 0.5)));
L = lab(rr, cc);
Lp = imdilate(L == 255, true(3)); Li = L == 128 & ~Lp;
for c = 1:3
    ch = double(P(:, :, c));
    col = [255 40 40]; coli = [255 200 0];
    ch(Li) = 0.55 * ch(Li) + 0.45 * coli(c);
    ch(Lp) = col(c);
    P(:, :, c) = uint8(ch);
end
imwrite(P, path, 'Quality', 88);
end
