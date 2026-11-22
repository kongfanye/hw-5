function v = percentile_val(x, p)
%PERCENTILE_VAL  百分位数（线性插值，忽略 NaN）。替代需统计工具箱的 prctile。
x = sort(x(~isnan(x(:))));
if isempty(x), v = NaN; return; end
n = numel(x);
pos = 1 + (n - 1) * p / 100;
lo = floor(pos); hi = ceil(pos);
v = x(lo) + (x(hi) - x(lo)) * (pos - lo);
end
