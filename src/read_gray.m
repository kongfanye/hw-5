function [G, RGB] = read_gray(path)
%READ_GRAY  读取图像并转为 [0,1] 浮点灰度；兼容灰度、彩色、带 alpha、索引色、16 位图。
%   RGB 为用于叠加显示的 uint8 三通道图。
[A, map] = imread(path);
if ndims(A) == 4, A = A(:, :, :, 1); end        % 多帧只取第一帧
if ~isempty(map)
    A = ind2rgb(A, map);                         % 索引色 -> double RGB
end
A = im2double(A);
if size(A, 3) == 4, A = A(:, :, 1:3); end
if size(A, 3) == 3
    G = 0.2989 * A(:, :, 1) + 0.5870 * A(:, :, 2) + 0.1140 * A(:, :, 3);
    RGB = im2uint8(A);
elseif size(A, 3) == 1
    G = A;
    RGB = repmat(im2uint8(A), [1 1 3]);
else
    G = mean(A, 3);
    RGB = repmat(im2uint8(G), [1 1 3]);
end
G = double(G);
end
