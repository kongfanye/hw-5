function O = make_overlay(RGB, res, methodLabel)
%MAKE_OVERLAY  原尺寸标注图：裂纹中心线半透明红色细线，每条裂纹编号与边界框，
%   左上角写判定状态。只用基本矩阵运算与内置点阵字体，不依赖计算机视觉工具箱。
O = RGB;
[H, W, ~] = size(O);
sc = max(2, round(max(H, W) / 1400));           % 字号随图像尺寸缩放
lw = max(1, round(max(H, W) / 2500));           % 线宽（半宽）
if ~isempty(res.centerline) && any(res.centerline(:))
    line = imdilate(res.centerline, disk_mask(lw));
    a = 0.75;
    for c = 1:3
        ch = double(O(:, :, c));
        col = [255 0 0];
        ch(line) = (1 - a) * ch(line) + a * col(c);
        O(:, :, c) = uint8(ch);
    end
end
boxCol = [255 220 0];
for i = 1:numel(res.cracks)
    b = res.cracks(i).bbox;
    pad = 6 * lw;
    x1 = max(1, b(1) - pad); y1 = max(1, b(2) - pad);
    x2 = min(W, b(3) + pad); y2 = min(H, b(4) + pad);
    O = draw_rect(O, x1, y1, x2, y2, lw + 1, boxCol);
    ty = y1 - 9 * sc - 2; if ty < 1, ty = y1 + 2; end
    O = draw_text(O, sprintf('#%d', res.cracks(i).id), x1, ty, sc, boxCol, [0 0 0]);
end
switch res.statusCode
    case 'crack',    s = sprintf('CRACK  N=%d', res.nCracks); col = [255 60 60];
    case 'no_crack', s = 'NO CRACK'; col = [80 255 80];
    case 'review',   s = 'REVIEW'; col = [255 200 0];
    otherwise,       s = upper(res.statusCode); col = [255 255 255];
end
O = draw_text(O, [upper(methodLabel) ': ' s], 10, 10, 2 * sc, col, [0 0 0]);
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
