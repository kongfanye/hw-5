function [med, sd] = robust_stats(x)
%ROBUST_STATS  中位数与 1.4826*MAD（稳健标准差），忽略 NaN。
x = x(~isnan(x(:)));
if isempty(x)
    med = NaN; sd = NaN; return;
end
med = median(x);
sd = 1.4826 * median(abs(x - med));
end
