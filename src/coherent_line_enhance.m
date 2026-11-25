function [zOut, oriOut] = coherent_line_enhance(z, oriK, valid, busBand, pitch, cfg)
%COHERENT_LINE_ENHANCE  方向一致性长程暗线增强与跨栅线桥接。
%   真实隐裂（尤其是对比度仅 3%-5% 的淡裂纹）在跨过亮细栅线时响应会短暂跌落，
%   导致单尺度 (1*pitch) 响应断成许多短段；但在 2.5*pitch 尺度上，裂纹两侧像素的
%   响应方向高度一致，而背景散斑与焊点伪影方向杂乱或局限于汇流条内。
%
%   对每个候选方向 k：
%     1) 只保留方向与 k 相差 <= 1 个方向格 (+-15 deg) 的截断响应 zSup；
%     2) 分别沿正、反两个半轴 [step, cohHalf] 求带掩膜均值 Mfwd、Mbwd；
%     3) 双侧共线桥接项 Mbi = min(Mfwd, Mbwd)：仅当裂纹在某点前后两侧都连续存在时才显著，
%        可无缝补齐细栅交叉处的响应凹陷，且绝不会在裂纹真实端点之外产生延伸拖尾；
%     4) 长程一致性增益项 Mall = 0.5*(Mfwd + Mbwd)：对本身已在暗线上 (z > 1.2) 且长程方向
%        一致的淡裂纹给予温和增益，而短于 1.2*pitch 的孤立纹理 Mall 低于门限、增益为 0。

zOut = z;
oriOut = oriK;
if ~isfield(cfg, 'useCoherentEnhance') || ~cfg.useCoherentEnhance
    return;
end

K = cfg.nOrient;
cohHalf = max(4, round(cfg.cohHalfLen * pitch));
step = max(3, round(0.18 * pitch));
tPos = step:step:cohHalf;
nTap = numel(tPos);
if nTap < 2
    return;
end

zSup = min(single(z), single(cfg.cohCapZ));
horiz = (oriK == 1) | (oriK == 2) | (oriK == K);
zSup(busBand & horiz) = 0;
zSup(busBand & ~horiz) = min(zSup(busBand & ~horiz), single(cfg.cohBusCapZ));
zSup(~valid) = 0;
Vd = single(valid);

bestZ = single(z);
bestK = oriK;
zS = single(z);

for k = 1:K
    th = (k - 1) * 180 / K;
    c = cosd(th); s = sind(th);
    kPrev = mod(k - 2, K) + 1;
    kNext = mod(k, K) + 1;
    aligned = (oriK == k) | (oriK == kPrev) | (oriK == kNext);
    Ak = zSup;
    Ak(~aligned) = 0;

    Sfwd = zeros(size(z), 'single'); Cfwd = zeros(size(z), 'single');
    Sbwd = zeros(size(z), 'single'); Cbwd = zeros(size(z), 'single');
    for t = tPos
        dx = round(t * c); dy = round(t * s);
        Sfwd = Sfwd + shift_img(Ak, dx, dy, 0);
        Cfwd = Cfwd + shift_img(Vd, dx, dy, 0);
        Sbwd = Sbwd + shift_img(Ak, -dx, -dy, 0);
        Cbwd = Cbwd + shift_img(Vd, -dx, -dy, 0);
    end
    okF = Cfwd >= 0.45 * nTap;
    okB = Cbwd >= 0.45 * nTap;
    Mfwd = Sfwd ./ max(Cfwd, 1); Mfwd(~okF) = 0;
    Mbwd = Sbwd ./ max(Cbwd, 1); Mbwd(~okB) = 0;

    % 双侧桥接：跨细栅凹陷处前后均有共线响应，而在端点外至少一侧为 0
    Mbi = min(Mfwd, Mbwd);
    zBridge = single(cfg.cohBridgeGain) * max(single(0), Mbi - single(cfg.cohBridgeFloor));
    zBridge(Mbi < single(cfg.cohBridgeMin)) = 0;

    % 长程同向增强：仅作用于当前像素本身已有同向暗线响应的位置
    Mall = 0.5 * (Mfwd + Mbwd);
    onlyF = okF & ~okB; Mall(onlyF) = 0.75 * Mfwd(onlyF);
    onlyB = okB & ~okF; Mall(onlyB) = 0.75 * Mbwd(onlyB);
    zBoost = zS + single(cfg.cohBoostGain) * max(single(0), Mall - single(cfg.cohBoostFloor));
    zBoost(~aligned | zS < 1.2) = 0;

    zCand = max(zBridge, zBoost);
    zCand(~valid) = 0;
    if k == 1 || k == 2 || k == K
        zCand(busBand) = 0;
    end

    upd = zCand > bestZ;
    bestZ(upd) = zCand(upd);
    % 原本无显著响应的细栅桥接点赋予当前共线方向 k
    reori = upd & (zS < 1.5 | ~aligned);
    bestK(reori) = uint8(k);
end

zOut = double(bestZ);
oriOut = bestK;
end
