function P = debug_previews(dbg, fullSize, longSide)
%DEBUG_PREVIEWS  把对齐坐标系中的中间结果映射回原图方向，生成供界面显示的小尺寸预览。
%   P = debug_previews(res.debug, [H W], 1000)
%   返回（均为原图方向、长边 longSide 的 uint8/logical 图）：
%     valid  有效区域（logical）        bus   汇流条/横向结构带（logical，改进法）
%     corr   亮度校正残差 (I-B)/B（uint8，128 为 0，改进法）
%     supp   栅线抑制后残差（uint8，改进法）；基线为 D = max(B-I,0)（uint8）
%     resp   暗线响应 z（uint8，z=8 对应 255，改进法）
%     cls    候选类别（0 背景 1 候选 2 弱候选 3 裂纹 4 断点连接）
prep = dbg.prep; geom = prep.geom;
H = fullSize(1); W = fullSize(2);
k = min(1, longSide / max(H, W));
ho = max(1, round(H * k)); wo = max(1, round(W * k));
X = ((1:wo) - 0.5) / k + 0.5;
Y = ((1:ho)' - 0.5) / k + 0.5;
[XX, YY] = meshgrid(X, Y);
xw = (XX - 0.5) * geom.s + 0.5; yw = (YY - 0.5) * geom.s + 0.5;
dx = xw - geom.c(1); dy = yw - geom.c(2);
U = geom.ca(1) + dx * geom.g(1) + dy * geom.g(2);
V = geom.ca(2) + dx * geom.f(1) + dy * geom.f(2);
% 预览比对齐图粗 r 倍：细线先在对齐图上做 r×r 最大值滤波再采样，避免缩小后消失
r = max(1, ceil(geom.s / k));
se = true(2 * floor(r / 2) + 1);
P.size = [ho wo];
P.valid = fill0(interp2(double(prep.valid), U, V, 'nearest', NaN)) > 0.5;
P.bus = false(ho, wo);
if isfield(dbg, 'busBand')
    P.bus = fill0(interp2(double(dbg.busBand), U, V, 'nearest', NaN)) > 0.5;
end
P.corr = []; P.supp = []; P.resp = [];
if isfield(dbg, 'Dn')
    P.corr = to_u8(0.5 + fill0(interp2(dbg.Dn, U, V, 'linear', NaN)) / 0.3);
    P.supp = to_u8(0.5 + fill0(interp2(dbg.R2, U, V, 'linear', NaN)) / 0.3);
    z = dbg.z; z(isnan(z)) = 0;
    P.resp = to_u8(fill0(interp2(imdilate(z, se), U, V, 'linear', NaN)) / 8);
elseif isfield(dbg, 'D')
    D = dbg.D; D(isnan(D)) = 0;
    dmax = percentile_val(D(prep.valid), 99.5);
    P.supp = to_u8(fill0(interp2(D, U, V, 'linear', NaN)) / max(dmax, eps));
end
c = double(dbg.cls);
cd = zeros(size(c));
for kk = [1 2 4 3]                      % 按优先级膨胀：裂纹 > 连接 > 弱候选 > 候选
    cd(imdilate(c == kk, se)) = kk;
end
P.cls = uint8(fill0(interp2(cd, U, V, 'nearest', NaN)));
end

function A = fill0(A)
A(isnan(A)) = 0;
end

function B = to_u8(A)
B = uint8(255 * min(max(A, 0), 1));
end
