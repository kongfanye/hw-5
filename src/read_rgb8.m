function A = read_rgb8(path)
%READ_RGB8  读取图像为 uint8 三通道（用于界面显示，比 read_gray 省去整幅浮点转换）。
%   兼容灰度、彩色、带 alpha、索引色、16 位和逻辑图像；多帧只取第一帧。
[A, map] = imread(path);
if ndims(A) == 4, A = A(:, :, :, 1); end
if ~isempty(map)
    A = im2uint8(ind2rgb(A, map));
elseif islogical(A)
    A = uint8(A) * 255;
elseif ~isa(A, 'uint8')
    A = im2uint8(A);
end
if size(A, 3) == 1
    A = repmat(A, [1 1 3]);
elseif size(A, 3) > 3
    A = A(:, :, 1:3);
end
end
