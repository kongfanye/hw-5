function [best, bestK] = dark_line_response(R, V, pitch, cfg)
%DARK_LINE_RESPONSE  多方向细暗线响应。
%   对每个候选方向 theta：先沿 theta 方向短距离平滑（带掩膜均值），
%   再沿法向两侧偏移 d 取样，响应 = max(0, min(左侧, 右侧) - 中心)。
%   取所有方向、所有偏移中的最大响应；bestK 为取得最大响应的方向序号。
%   台阶状边缘（一侧暗一侧亮）响应接近 0，只有"中心比两侧都暗"的细线有响应。
A0 = single(R); bad = ~V | isnan(R);
A0(bad) = 0;
Vd = single(~bad);
K = cfg.nOrient;
half = max(2, round(cfg.smoothLen * pitch / 2));
offs = unique(max(1, round(cfg.sideOffsets * pitch)));
best = zeros(size(R), 'single');
bestK = zeros(size(R), 'uint8');
taps = -half:2:half;                 % 隔点取样，平滑长度不变、计算量减半
nTap = numel(taps);
for k = 1:K
    th = (k - 1) * 180 / K;
    c = cosd(th); s = sind(th);
    S = zeros(size(R), 'single'); C = zeros(size(R), 'single');
    for t = taps
        dx = round(t * c); dy = round(t * s);
        S = S + shift_img(A0, dx, dy, 0);
        C = C + shift_img(Vd, dx, dy, 0);
    end
    S = S ./ max(C, eps);
    S(C < 0.6 * nTap) = NaN;
    nx = -s; ny = c;
    for d = offs
        ox = round(d * nx); oy = round(d * ny);
        L = shift_img(S, ox, oy, NaN);
        Rt = shift_img(S, -ox, -oy, NaN);
        r = min(L, Rt) - S;
        r(isnan(L) | isnan(Rt) | isnan(S) | r < 0) = 0;
        upd = r > best;
        best(upd) = r(upd);
        bestK(upd) = k;
    end
end
best = double(best);
end
