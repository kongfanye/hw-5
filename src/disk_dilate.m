function B = disk_dilate(A, r, op)
%DISK_DILATE  基于精确欧氏距离变换 bwdist 的圆盘形态学运算（与 disk_mask(r) 等价，O(N) 线性时间）。
%   B = disk_dilate(A, r)          膨胀，等价于 imdilate(A, disk_mask(r))
%   B = disk_dilate(A, r, 'erode') 腐蚀，等价于 imerode(A, disk_mask(r))
%   B = disk_dilate(A, r, 'open')  开运算，等价于 imopen(A, disk_mask(r))
if nargin < 3, op = 'dilate'; end
A = logical(A);
r = max(0, round(r));
if r == 0
    B = A;
    return;
end
rad = sqrt(r^2 + 0.5);
switch op
    case 'dilate'
        if ~any(A(:))
            B = false(size(A));
        elseif all(A(:))
            B = true(size(A));
        else
            B = bwdist(A) <= rad;
        end
    case 'erode'
        B = ~disk_dilate(~A, r, 'dilate');
    case 'open'
        B = disk_dilate(disk_dilate(A, r, 'erode'), r, 'dilate');
    otherwise
        error('未知形态学操作: %s', op);
end
end
