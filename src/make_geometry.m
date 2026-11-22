function geom = make_geometry(workSize, thetaDeg, s)
%MAKE_GEOMETRY  建立"工作图 <-> 栅线对齐图"的坐标变换。
%   thetaDeg 为细栅方向与 x 轴（向右）夹角，y 轴向下，取值 [0,180)。
%   对齐图中细栅沿竖直方向 (v 轴)，主栅/横向结构沿水平方向 (u 轴)。
%   工作图点 p 与对齐图点 (u,v) 的关系：p = c + (u-cu)*g + (v-cv)*f
h = workSize(1); w = workSize(2);
f = [cosd(thetaDeg), sind(thetaDeg)];   % 细栅方向 (x,y)
g = [sind(thetaDeg), -cosd(thetaDeg)];  % 垂直细栅方向
c = [(w + 1) / 2, (h + 1) / 2];
corners = [0.5 0.5; w + 0.5 0.5; 0.5 h + 0.5; w + 0.5 h + 0.5] - c;
pu = corners * g'; pv = corners * f';
wa = ceil(max(pu) - min(pu)); ha = ceil(max(pv) - min(pv));
geom.theta = thetaDeg;
geom.s = s;
geom.workSize = [h w];
geom.alignedSize = [ha wa];
geom.c = c;
geom.ca = [(wa + 1) / 2, (ha + 1) / 2];
geom.f = f;
geom.g = g;
end
