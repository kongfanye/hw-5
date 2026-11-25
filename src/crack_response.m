function Rs = crack_response(I, cfg)
%CRACK_RESPONSE  改进法前半段：有效区/背景 -> 亮度校正 -> 栅线与横向结构抑制
%   -> 多方向细暗线响应 -> 局部 z 分数 -> 重复结构响应降权 -> 长程方向一致性增强。
%   返回对齐坐标系中的各中间图，供 segment_cracks 分割与定位。
prep = prepare_image(I, cfg);
pitch = prep.pitch; valid = prep.valid; Ia = prep.Ia; B = prep.B;

% ---------- 1. 亮度校正：相对残差 ----------
Dn = (Ia - B) ./ max(B, 0.05);
Dn(~valid) = NaN;

% ---------- 2. 抑制细栅与横向重复结构 ----------
if prep.grid.ok
    P = block_profile(Dn, cfg.colBlock * pitch, 1, cfg.minBlockFrac);
    R1 = Dn - cfg.alphaFinger * P;
    Q = block_profile(R1, cfg.rowBlock * pitch, 2, cfg.minBlockFrac);
    R2 = R1 - cfg.betaBusbar * Q;
    [~, sdQ] = robust_stats(Q(valid));
    busRow = abs(Q) > cfg.busbarK * sdQ & ~isnan(Ia);
    rb = max(1, round(cfg.busbarHalfWidth * pitch));
    busBand = imdilate(busRow, true(2 * rb + 1, 1));
else
    R2 = Dn;
    busBand = false(size(Dn));
end

% ---------- 3. 细暗线增强、局部归一化与长程方向一致性桥接 ----------
[resp, oriK] = dark_line_response(R2, valid, pitch, cfg);
sdMap = tile_noise(R2, valid, cfg.noiseTile * pitch);
z = resp ./ sdMap;
z(~valid) = 0;
zRaw = z;
if prep.grid.ok
    % 重复结构的响应降权：沿细栅方向、沿主栅方向分块取高分位数并减去。
    % 横向采用较宽分块 rowBlockZ，既消除跨电池片的汇流条/断栅行残影，又避免误减低倾角长裂纹。
    zN = z; zN(~valid) = NaN;
    Zc = block_profile(zN, cfg.colBlock * pitch, 1, cfg.minBlockFrac, cfg.structQuantile);
    zN = zN - Zc;
    rowBlkZ = cfg.rowBlock;
    if isfield(cfg, 'rowBlockZ'), rowBlkZ = cfg.rowBlockZ; end
    Zr = block_profile(zN, rowBlkZ * pitch, 2, cfg.minBlockFrac, cfg.structQuantile);
    z = z - Zc - Zr;
    z(z < 0 | ~valid) = 0;
end
[z, oriK] = coherent_line_enhance(z, oriK, valid, busBand, pitch, cfg);
oriDeg = (double(oriK) - 1) * 180 / cfg.nOrient;
oriDeg(oriK == 0) = NaN;

Rs.prep = prep;
Rs.Dn = Dn;
Rs.R2 = R2;
Rs.resp = resp;
Rs.z = z;
Rs.zRaw = zRaw;
Rs.oriK = oriK;
Rs.oriDeg = oriDeg;
Rs.busBand = busBand;
end
