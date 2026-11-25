function cfg = crack_config()
%CRACK_CONFIG  集中定义检测参数。
%   长度类参数大多以"细栅间距 pitch"为单位；程序对每张图从像素估计栅距，
%   再换算成工作图像素。这样同一套参数可用于不同分辨率、不同拍摄角度的原图。
%   灰度类参数以 [0,1] 浮点灰度为单位；"相对残差"指 (I-B)/B。

cfg.version = '1.1';

% ---------------- 尺度 ----------------
cfg.coarseLongSide   = 1200;  % 估计栅线方向/间距用的缩略图长边 (px)
cfg.targetPitchPx    = 28;    % 工作图中希望的细栅间距 (px)，决定工作缩放比
cfg.minWorkScale     = 0.20;  % 工作缩放比下限
cfg.maxWorkScale     = 1.60;  % 低分辨率图允许适度上采样，避免栅距过小导致离散量化误差
cfg.maxWorkLongSide  = 2500;  % 上采样时的工作图长边上限 (px)
cfg.defaultPitchFrac = 0.0102;% 栅距估计失败时，按原图长边的该比例取栅距

% ---------------- 栅线方向与间距估计 ----------------
cfg.houghThetaStep   = 0.5;   % Hough 角度步长 (deg)
cfg.houghPeaks       = 60;    % Hough 峰值数
cfg.angleRefineRange = 3.0;   % 在 Hough 主方向附近细化的范围 (deg)
cfg.angleRefineStep  = 0.1;   % 细化步长 (deg)
cfg.pitchRangeCoarse = [4 46];% 缩略图上栅距搜索范围 (px)，覆盖单片近景与多片全景并避开汇流条大周期
cfg.minPeriodicity   = 0.12;  % 归一化自相关峰低于该值 -> 栅线周期不可靠

% ---------------- 有效区域 ----------------
cfg.brightThresh     = 0.90;  % 平滑灰度高于此值为亮缝/过曝候选
cfg.brightOpenRadius = 0.45;  % 亮区开运算半径 (pitch)：去掉细栅，只留宽亮带和大亮斑
cfg.bigBrightArea    = 4.0;   % 面积大于该值 (pitch^2) 的亮区视为亮缝/过曝区
cfg.seamMargin       = 0.8;   % 亮缝/过曝区/外圈黑框向外排除的宽度 (pitch)，避开片边暗边与切角
cfg.spotMargin       = 0.25;  % 小亮斑（焊点/反光）外扩 (pitch)
cfg.borderMargin     = 0.5;   % 图像边界留白 (pitch)
cfg.minCellArea      = 20;    % 有效连通区最小面积 (pitch^2)
cfg.minValidFrac     = 0.30;  % 有效面积占图像比例低于此值 -> 待复核
cfg.brightWarnFrac   = 0.25;  % 被排除的亮区占比超过此值时写入备注

% ---------------- 背景估计 ----------------
cfg.bgSigma = 1.5;            % 带掩膜高斯背景的 sigma (pitch)

% ---------------- 基线方法 ----------------
cfg.base.k         = 3.0;     % 阈值 = 中位数 + k * 1.4826 * MAD（对 max(B-I,0)）
cfg.base.minArea   = 0.3;     % 最小连通域面积 (pitch^2)
cfg.base.minLength = 2.0;     % 最小主轴长度 (pitch)

% ---------------- 栅线 / 横向结构抑制 ----------------
cfg.colBlock    = 2.5;        % 沿细栅方向求中值的分块长度 (pitch)
cfg.rowBlock    = 4.0;        % 沿主栅方向求中值的分块宽度 (pitch)
cfg.rowBlockZ   = 10.0;       % z 分数横向分位数抑制分块宽度 (pitch)，防止误伤小倾角长裂纹
cfg.alphaFinger = 1.0;        % 细栅纹理减去比例
cfg.betaBusbar  = 1.0;        % 横向重复结构减去比例
cfg.minBlockFrac = 0.3;       % 分块内有效像素比例下限
cfg.busbarK     = 3.5;        % 横向剖面 |Q| > busbarK*鲁棒标准差 视为汇流条/横向结构行
cfg.busbarHalfWidth = 0.35;   % 汇流条带半宽 (pitch)

% ---------------- 细暗线增强与长程方向一致性增强 ----------------
cfg.nOrient        = 12;      % 候选方向数（180/12 = 15 deg 间隔）
cfg.smoothLen      = 1.0;     % 单尺度沿候选方向平滑长度 (pitch)
cfg.sideOffsets    = [0.08 0.13 0.20]; % 法向两侧取样偏移 (pitch)，原图约 4/7/11 px
cfg.noiseTile      = 6;       % 局部噪声统计分块边长 (pitch)
cfg.structQuantile = 0.7;     % 重复结构响应估计所用分位数
cfg.useCoherentEnhance = true;% 开启长程方向一致性桥接与淡裂纹增强
cfg.cohHalfLen     = 1.25;    % 单侧同向积分长度 (pitch)，总跨度 2.5*pitch
cfg.cohCapZ        = 4.0;     % 同向积分输入响应截断上限，防止局部强点外溢
cfg.cohBusCapZ     = 2.0;     % 汇流条带内同向积分响应上限
cfg.cohBridgeGain  = 1.90;    % 双侧同向跨栅线桥接增益
cfg.cohBridgeFloor = 0.42;    % 双侧同向桥接底噪门限
cfg.cohBridgeMin   = 1.00;    % 启用双侧桥接的最小同向均值
cfg.cohBoostGain   = 1.00;    % 长程连续淡裂纹同向增益
cfg.cohBoostFloor  = 0.95;    % 长程增益启动门限（短于 ~1.2*pitch 的散斑不获益）

% ---------------- 分割、筛选与连接 ----------------
cfg.zHigh       = 4.5;        % 标准裂纹峰值阈值（局部稳健 z 分数，且位于响应脊线上）
cfg.zLow        = 2.5;        % 滞后生长阈值
cfg.zCandOffset = 0.7;        % 连接前候选种子相对 zHigh 的下探量（默认 4.5-0.7 = 3.8）
cfg.useRidgeNms = false;      % true: 只在法向非极大值抑制后的脊线上做滞后连接
cfg.minSkelLen  = 0.4;        % 连接前丢弃的极短骨架 (pitch)
cfg.minLength   = 3.0;        % 标准裂纹骨架最短长度 (pitch)
cfg.minCross    = 2.0;        % 斜向裂纹最少跨越的细栅数
cfg.parallelTol = 15;         % 与细栅/主栅夹角小于此值视为平行 (deg)
cfg.minLenParFinger = 8;      % 近似平行细栅的裂纹最短长度 (pitch)
cfg.minLenParBusbar = 5;      % 近似平行主栅的裂纹最短长度 (pitch)
cfg.maxBusbarFrac   = 0.5;    % 候选骨架落在汇流条带内的比例上限
cfg.maxWidth    = 0.30;       % 平均宽度上限 (pitch)；更宽的视为斑块
cfg.minMeanZ    = 3.0;        % 标准裂纹骨架平均 z 分数下限
cfg.minFaintLen   = 5.5;      % 长程淡裂纹最短骨架长度 (pitch)
cfg.minFaintCross = 4.0;      % 长程淡裂纹最少跨越细栅数
cfg.minFaintMeanZ = 2.70;     % 长程淡裂纹平均 z 分数下限
cfg.brightScratchThresh = 0.095; % 强亮划痕残差阈值，用于抑制其伴生暗影误标
cfg.linkGap     = 1.5;        % 断点连接最大间距 (pitch)
cfg.linkAngle   = 35;         % 断点连接方向偏差上限 (deg)
cfg.linkGapLong = 3.5;        % 共线断点（如被汇流条隔开）允许的最大间距 (pitch)
cfg.linkAngleLong = 15;       % 长距离连接的方向偏差上限 (deg)
cfg.growIter    = 3;          % 分支生长迭代次数（0 关闭）
cfg.growDist    = 2.5;        % 与已确认裂纹的最大并入距离 (pitch)
cfg.growMinLen  = 1.0;        % 生长段最短长度 (pitch)
cfg.growMinZ    = 2.75;       % 生长段平均 z 下限
cfg.growSeedZ   = 3.3;        % 生长候选的种子阈值（仅在已确认有裂纹的图像中启用）
cfg.growLowZ    = 2.05;       % 生长候选的连通生长下限
cfg.secMinLen   = 4.5;        % 同片次生独立淡裂纹最短长度 (pitch)
cfg.secMinCross = 3.5;        % 同片次生独立淡裂纹最少跨越细栅数
cfg.secMinMaxZ  = 3.4;        % 同片次生独立淡裂纹峰值 z 下限
cfg.secMinMeanZ = 2.60;       % 同片次生独立淡裂纹平均 z 下限
cfg.reviewFrac  = 0.6;        % 长度/跨栅数达到阈值该比例的强候选 -> 待复核

% ---------------- 原图定位与输出 ----------------
cfg.snapRadius     = 3;       % 原图上沿法向吸附到暗线中心的搜索半径 (原图 px)
cfg.maskMinHalfWidth = 2;     % 原图掩膜半宽下限 (px)
cfg.overlayQuality = 85;      % 标注图 JPEG 质量
cfg.debugLongSide  = 1400;    % 调试图长边 (px)
cfg.saveDebugFor   = {};      % 需要输出中间结果的文件名（不含扩展名），{'*'} 表示全部
end
