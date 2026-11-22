function M = draw_segments(M, x1, y1, x2, y2, val)
%DRAW_SEGMENTS  在矩阵 M 上画多条线段 (x1,y1)-(x2,y2)（列、行坐标，1 起）。
%   向量化实现：按最长线段确定统一采样数，适合大量短线段。
%   val 可为标量，或与线段数相同长度的向量（每条线段写入各自的值）。
if nargin < 6, val = true; end
if isempty(x1), return; end
if isscalar(val), val = repmat(val, numel(x1), 1); end
val = val(:);
[h, w] = size(M);
x1 = x1(:); y1 = y1(:); x2 = x2(:); y2 = y2(:);
len = hypot(x2 - x1, y2 - y1);
% 长线段单独画，避免统一采样数过大
long = len > 50;
if any(long)
    il = find(long);
    for i = il'
        n = ceil(len(i)) + 1;
        t = linspace(0, 1, n);
        xs = round(x1(i) + (x2(i) - x1(i)) * t);
        ys = round(y1(i) + (y2(i) - y1(i)) * t);
        ok = xs >= 1 & xs <= w & ys >= 1 & ys <= h;
        M(sub2ind([h w], ys(ok), xs(ok))) = val(i);
    end
    x1 = x1(~long); y1 = y1(~long); x2 = x2(~long); y2 = y2(~long);
    len = len(~long); val = val(~long);
end
if isempty(x1), return; end
n = max(2, ceil(max(len)) + 1);
t = linspace(0, 1, n);
xs = round(x1 + (x2 - x1) * t);
ys = round(y1 + (y2 - y1) * t);
V = repmat(val, 1, n);
ok = xs >= 1 & xs <= w & ys >= 1 & ys <= h;
M(sub2ind([h w], ys(ok), xs(ok))) = V(ok);
end
