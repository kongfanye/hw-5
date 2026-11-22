function m = nanmedian_cols(X, minCount, q)
%NANMEDIAN_COLS  逐列忽略 NaN 的分位数（默认 q=0.5 即中位数），MATLAB/Octave 通用。
%   有效个数少于 minCount 的列返回 NaN。
if nargin < 2, minCount = 1; end
if nargin < 3, q = 0.5; end
[n, w] = size(X);
S = sort(X, 1);              % NaN 排在末尾
cnt = sum(~isnan(X), 1);
m = nan(1, w);
ok = cnt >= max(1, minCount);
if ~any(ok), return; end
c = cnt(ok);
cols = find(ok);
pos = 1 + (c - 1) * q;
lo = floor(pos); hi = ceil(pos); fr = pos - lo;
m(ok) = S(sub2ind([n w], lo, cols)) .* (1 - fr) + S(sub2ind([n w], hi, cols)) .* fr;
end
