function prep = prepare_image(I, cfg)
%PREPARE_IMAGE  基线与改进法共用的前端：
%   栅线方向/间距估计 -> 工作尺度 -> 栅线对齐 -> 有效区域 -> 带掩膜背景 B。
%   I 为原图灰度 (double, [0,1])。所有中间图都在"对齐坐标系"中，
%   细栅沿竖直方向；最终结果用 aligned_to_full 映射回原图坐标。

[H, W] = size(I);
prep.fullSize = [H W];
prep.notes = {};
prep.reviewReasons = {};

% ---------- 1. 栅线方向和间距 ----------
grid = estimate_grid(I, cfg);
prep.grid = grid;
if ~grid.ok
    prep.reviewReasons{end + 1} = ['栅线方向/间距估计不稳定，回退为局部暗纹检测（' grid.reason '）'];
end
s = cfg.targetPitchPx / grid.pitchFull;
s = min(max(s, cfg.minWorkScale), cfg.maxWorkScale);
pitch = grid.pitchFull * s;               % 工作图中的栅距 (px)
prep.scale = s;
prep.pitch = pitch;

% ---------- 2. 工作图与对齐 ----------
Iw = resize_img(I, s);
if grid.ok
    theta = grid.theta;
else
    theta = 90;                           % 不旋转
end
geom = make_geometry(size(Iw), theta, s);
Ia = to_aligned(Iw, geom, 'linear');
prep.geom = geom;
prep.Iw = Iw;
prep.Ia = Ia;

% ---------- 3. 有效区域 ----------
inb = ~isnan(Ia);
inb = imerode(inb, disk_mask(cfg.borderMargin * pitch));
I0 = Ia; I0(isnan(I0)) = 0;
Is = gauss_blur(I0, 0.25 * pitch);
bright = Is > cfg.brightThresh & inb;
bright = imopen(bright, disk_mask(cfg.brightOpenRadius * pitch));
big = bwareaopen(bright, round(cfg.bigBrightArea * pitch^2));
small = bright & ~big;
invalid = ~inb | imdilate(big, disk_mask(cfg.seamMargin * pitch)) | ...
          imdilate(small, disk_mask(cfg.spotMargin * pitch));
valid = ~invalid;
valid = bwareaopen(valid, round(cfg.minCellArea * pitch^2), 4);
prep.valid = valid;
prep.brightBig = big & inb;
prep.cells = bwlabel(valid, 4);
nIn = max(1, nnz(~isnan(Ia)));
prep.validFrac = nnz(valid) / nIn;
prep.brightFrac = nnz(big & inb) / nIn;
if prep.validFrac < cfg.minValidFrac
    prep.reviewReasons{end + 1} = sprintf('可检测面积不足（有效区仅占 %.0f%%）', 100 * prep.validFrac);
end
if prep.brightFrac > cfg.brightWarnFrac
    prep.notes{end + 1} = sprintf('亮缝/过曝区占 %.0f%%，该区域不参与检测', 100 * prep.brightFrac);
end

% ---------- 4. 带掩膜背景 ----------
B = masked_smooth(Ia, valid, cfg.bgSigma * pitch);
prep.B = B;
end
