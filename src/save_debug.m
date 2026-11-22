function save_debug(res, RGB, overlay, outDir, stem, cfg)
%SAVE_DEBUG  按处理顺序保存中间结果（映射回原图方向，缩小到 debugLongSide）。
%   01 原图 | 02 有效区域 | 03 亮度校正残差 | 04 栅线抑制后残差 | 05 暗线响应 z
%   06 筛选前候选（蓝=未入选候选，橙=弱候选，红=最终裂纹，绿=断点连接）| 07 最终叠加图
%   并生成 00_montage.jpg 总览。基线方法输出对应的 D=max(B-I,0) 与阈值结果。
d = res.debug;
prep = d.prep; geom = prep.geom;
dd = fullfile(outDir, stem);
if exist(dd, 'dir') ~= 7, mkdir(dd); end
[H, W, ~] = size(RGB);
k = min(1, cfg.debugLongSide / max(H, W));
small = @(A) resize_img(double(A), k);
toWork = @(M, m) from_aligned(M, geom, m);
% 工作图 -> 调试图尺寸
kw = cfg.debugLongSide / max(geom.workSize);
kw = min(1, kw);
wsmall = @(A) resize_img(A, kw);
tiles = {};
names = {};
% 01 原图
g = small(mean(double(RGB), 3) / 255);
tiles{end + 1} = gray2rgb8(g); names{end + 1} = '01 INPUT';
% 02 有效区域（无效区染红，汇流条带染蓝）
v = wsmall(fillnan(toWork(double(prep.valid), 'nearest'), 0)) > 0.5;
base = wsmall(prep.Iw);
rgb = gray2rgb8(base);
rgb = tint(rgb, ~v, [255 0 0], 0.45);
if isfield(d, 'busBand')
    bb = wsmall(fillnan(toWork(double(d.busBand), 'nearest'), 0)) > 0.5;
    rgb = tint(rgb, bb & v, [0 120 255], 0.35);
end
tiles{end + 1} = rgb; names{end + 1} = '02 VALID AREA';
if strcmp(res.method, 'improved')
    tiles{end + 1} = gray2rgb8(sym_scale(wsmall(fillnan(toWork(d.Dn, 'linear'), 0)), 0.15));
    names{end + 1} = '03 CORRECTED (I-B)/B';
    tiles{end + 1} = gray2rgb8(sym_scale(wsmall(fillnan(toWork(d.R2, 'linear'), 0)), 0.15));
    names{end + 1} = '04 GRID SUPPRESSED';
    zz = wsmall(fillnan(toWork(d.z, 'linear'), 0));
    tiles{end + 1} = gray2rgb8(min(zz / 8, 1)); names{end + 1} = '05 DARK LINE RESPONSE Z';
else
    Dd = d.D; Dd(isnan(Dd)) = 0;
    dmax = percentile_val(Dd(prep.valid), 99.5);
    tiles{end + 1} = gray2rgb8(min(wsmall(fillnan(toWork(Dd, 'linear'), 0)) / max(dmax, eps), 1));
    names{end + 1} = '03 D = MAX(B-I,0)';
end
% 06 候选分类
cls = toWork(double(d.cls), 'nearest'); cls(isnan(cls)) = 0;
cls = imdilate_cls(cls);
cs = resize_nearest(cls, size(wsmall(prep.Iw)));
rgb = gray2rgb8(0.35 * base);
rgb = paint(rgb, cs == 1, [60 110 255]);
rgb = paint(rgb, cs == 2, [255 150 0]);
rgb = paint(rgb, cs == 3, [255 40 40]);
rgb = paint(rgb, cs == 4, [40 255 40]);
tiles{end + 1} = rgb; names{end + 1} = '06 CANDIDATES';
% 07 叠加图
ov = uint8(cat(3, small(double(overlay(:, :, 1))), small(double(overlay(:, :, 2))), small(double(overlay(:, :, 3)))));
tiles{end + 1} = ov; names{end + 1} = '07 FINAL OVERLAY';
% 统一尺寸并保存
sz = size(tiles{end}); sz = sz(1:2);
for i = 1:numel(tiles)
    t = tiles{i};
    if size(t, 1) ~= sz(1) || size(t, 2) ~= sz(2)
        t = uint8(cat(3, resize_to(double(t(:, :, 1)), sz), resize_to(double(t(:, :, 2)), sz), resize_to(double(t(:, :, 3)), sz)));
    end
    tiles{i} = t;
    fn = lower(strrep(strrep(names{i}, ' ', '_'), '/', '_'));
    fn = regexprep(fn, '[^a-z0-9_]', '');
    imwrite(t, fullfile(dd, [fn '.jpg']), 'Quality', 90);
end
% 总览
nc = 4; nr = ceil(numel(tiles) / nc);
th = round(sz(1) / 2); tw = round(sz(2) / 2);
M = zeros(nr * (th + 4), nc * (tw + 4), 3, 'uint8') + 40;
for i = 1:numel(tiles)
    r = floor((i - 1) / nc); c = mod(i - 1, nc);
    t = tiles{i};
    t = uint8(cat(3, resize_to(double(t(:, :, 1)), [th tw]), resize_to(double(t(:, :, 2)), [th tw]), resize_to(double(t(:, :, 3)), [th tw])));
    t = draw_text(t, names{i}, 4, 4, 2, [255 255 0], [0 0 0]);
    M(r * (th + 4) + (1:th), c * (tw + 4) + (1:tw), :) = t;
end
imwrite(M, fullfile(dd, '00_montage.jpg'), 'Quality', 90);
end

function A = fillnan(A, v)
A(isnan(A)) = v;
end

function rgb = gray2rgb8(g)
g = uint8(255 * min(max(g, 0), 1));
rgb = cat(3, g, g, g);
end

function g = sym_scale(A, r)
g = 0.5 + A / (2 * r);
end

function rgb = tint(rgb, m, col, a)
for c = 1:3
    ch = double(rgb(:, :, c));
    ch(m) = (1 - a) * ch(m) + a * col(c);
    rgb(:, :, c) = uint8(ch);
end
end

function rgb = paint(rgb, m, col)
for c = 1:3
    ch = rgb(:, :, c); ch(m) = col(c); rgb(:, :, c) = ch;
end
end

function c = imdilate_cls(c)
% 细线在缩小后会消失：按类别优先级（裂纹 > 连接 > 弱 > 候选）膨胀 1 像素
out = zeros(size(c));
for k = [1 2 4 3]
    m = imdilate(c == k, true(3));
    out(m) = k;
end
c = out;
end

function B = resize_nearest(A, sz)
ys = min(size(A, 1), max(1, round(((1:sz(1)) - 0.5) * size(A, 1) / sz(1) + 0.5)));
xs = min(size(A, 2), max(1, round(((1:sz(2)) - 0.5) * size(A, 2) / sz(2) + 0.5)));
B = A(ys, xs);
end

function B = resize_to(A, sz)
if isequal(size(A), sz(1:2)), B = A; return; end
s = sz(1) / size(A, 1);
B = resize_img(A, s);
if any(size(B) ~= sz)
    B = resize_nearest(B, sz);
end
end
