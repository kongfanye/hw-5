function O = make_overlay(RGB, res, methodLabel)
%MAKE_OVERLAY  原尺寸标注图：裂纹中心线半透明红色醒目细线，每条裂纹编号与边界框，
%   左上角写判定状态。只用基本矩阵运算与内置点阵字体，不依赖计算机视觉工具箱。
O = RGB;
[H, W, ~] = size(O);
sc = max(2, round(max(H, W) / 1300));           % 字号随图像尺寸缩放
lw = max(2, round(max(H, W) / 1500));           % 中心线半宽（大图和缩略图均清晰可见）
boxLw = max(2, round(max(H, W) / 1100));        % 边界框线宽
if ~isempty(res.centerline) && any(res.centerline(:))
    [ys, xs] = find(res.centerline);
    y1 = max(1, min(ys) - lw - 1); y2 = min(H, max(ys) + lw + 1);
    x1 = max(1, min(xs) - lw - 1); x2 = min(W, max(xs) + lw + 1);
    subLine = disk_dilate(res.centerline(y1:y2, x1:x2), lw);
    a = 0.82;
    col = [255 20 20];
    for c = 1:3
        ch = double(O(y1:y2, x1:x2, c));
        ch(subLine) = (1 - a) * ch(subLine) + a * col(c);
        O(y1:y2, x1:x2, c) = uint8(ch);
    end
end
boxCol = [255 220 0];
for i = 1:numel(res.cracks)
    b = res.cracks(i).bbox;
    pad = 5 * lw;
    x1 = max(1, b(1) - pad); y1 = max(1, b(2) - pad);
    x2 = min(W, b(3) + pad); y2 = min(H, b(4) + pad);
    O = draw_rect(O, x1, y1, x2, y2, boxLw, boxCol);
    ty = y1 - 9 * sc - 2; if ty < 1, ty = y1 + 2; end
    O = draw_text(O, sprintf('#%d', res.cracks(i).id), x1, ty, sc, boxCol, [0 0 0]);
end
switch res.statusCode
    case 'crack',    s = sprintf('DEFECT (CRACK)  N=%d', res.nCracks); col = [255 70 70];
    case 'no_crack', s = 'NO DEFECT'; col = [80 255 80];
    case 'review',   s = 'REVIEW'; col = [255 200 0];
    otherwise,       s = upper(res.statusCode); col = [255 255 255];
end
if nargin < 3 || isempty(methodLabel)
    banner = s;
else
    banner = [upper(methodLabel) ': ' s];
end
O = draw_text(O, banner, 12, 12, 2 * sc, col, [0 0 0]);
end

function O = draw_rect(O, x1, y1, x2, y2, t, col)
[H, W, ~] = size(O);
t = max(1, t);
rows = {max(1, y1):min(H, y1 + t - 1), max(1, y2 - t + 1):min(H, y2)};
cols = {max(1, x1):min(W, x1 + t - 1), max(1, x2 - t + 1):min(W, x2)};
for c = 1:3
    O(rows{1}, x1:x2, c) = col(c);
    O(rows{2}, x1:x2, c) = col(c);
    O(y1:y2, cols{1}, c) = col(c);
    O(y1:y2, cols{2}, c) = col(c);
end
end
