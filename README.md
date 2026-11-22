# 太阳能电池片隐裂检测（MATLAB）

数字图像处理大作业：对电池片实拍图逐张判断是否存在**可见隐裂**，并在原图上标出裂纹位置。
方法为传统图像处理（不训练模型）：有效区域与背景估计 → 栅线方向/间距估计与纹理抑制 →
多方向细暗线增强 → 双阈值、骨架化、断点连接与形状筛选 → 映射回原图并吸附到暗线中心。

完整的设计说明、实验结果和局限分析见 [`docs/设计报告.md`](docs/设计报告.md)。

## 运行环境

| 项目 | 说明 |
| --- | --- |
| 实测环境 | **GNU Octave 8.4.0 + image 包 2.14.0**（Ubuntu 24.04，x86_64）。`outputs/` 中的全部结果均由该环境实际运行 `run_demo` 生成 |
| MATLAB | 本次开发环境**没有安装 MATLAB**，MATLAB 下的实测结果尚待生成。代码只使用 MATLAB 基础函数和 Image Processing Toolbox 函数，避开了 Octave 专有语法；需要 MATLAB R2016b 及以上（`jsondecode`）+ Image Processing Toolbox |
| 不依赖 | Statistics Toolbox、Computer Vision Toolbox（百分位数、稳健统计、文字绘制、JSON 写出都在 `src/` 中自行实现） |

用到的工具箱函数：`hough / houghpeaks / houghlines / imdilate / imerode / imopen / imreconstruct / bwmorph / bwlabel / bwareaopen / bwdist / regionprops / padarray / im2double / im2uint8 / ind2rgb`。

## 快速开始

在项目目录的 MATLAB 命令窗口：

```matlab
run_demo
```

或在终端（项目目录下）：

```bash
matlab -batch "run_demo"
```

GNU Octave（本次实测所用）：

```bash
octave --no-gui --eval "run_demo"
```

`run_demo` 会用同一批原图依次运行改进法和基线，写出 `outputs/`（改进法）、`outputs/baseline/`（基线）、
`outputs/evaluation/`（评估），完整控制台记录保存在 `outputs/run_demo_log.txt`。
输入目录按顺序取第一个存在且含图像的：`data/raw/` → `upload/` → `cracked/` 与 `uncracked/`（本仓库原图所在位置）。

处理其他目录（路径可含空格或中文）：

```matlab
run_demo({'D:\新建 文件夹\电池片'})                                   % 改进法 + 基线 + （有标签时）评估
run_batch({'D:\新建 文件夹\电池片'}, 'D:\结果')                         % 只跑改进法
run_batch('data/raw', 'outputs_base', 'Method', 'baseline')           % 只跑基线
run_batch('data/raw', 'out', 'Debug', {'*'})                          % 对每张图输出中间结果
```

单张图像调用（只用像素和参数，不读取文件名、目录名或标签）：

```matlab
addpath('src');
G   = read_gray('cracked/cracked_07.jpg');   % [0,1] 浮点灰度
cfg = crack_config();
res = detect_cracks(G, cfg);                 % 改进法；基线为 detect_baseline(G, cfg)
res.status, res.nCracks, res.cracks(1).bbox
```

## 项目结构

```
run_demo.m              演示入口：改进法 + 基线 + 评估
run_batch.m             扫描目录、逐图处理、导出 CSV/JSON/标注图/掩膜/调试图，单张出错不中断
src/
  crack_config.m        全部参数（单位与作用见下表）
  detect_cracks.m       改进法单图检测 = crack_response + segment_cracks
  crack_response.m      有效区/背景 → 亮度校正 → 栅线与横向结构抑制 → 细暗线响应 z
  segment_cracks.m      双阈值 → 骨架 → 断点连接 → 形状/方向筛选 → 判定
  detect_baseline.m     基线：max(B-I,0) 稳健阈值 + 连通域面积/长度筛选
  prepare_image.m       两种方法共用前端：栅线估计、工作尺度、对齐、有效区、带掩膜背景 B
  estimate_grid.m       Hough 长度加权方向 + 分块投影自相关求栅距
  block_profile.m       沿栅线方向分块稳健中值/分位数（重复纹理估计）
  dark_line_response.m  多方向 min(左,右)-中心 暗线响应
  link_segments.m       同片内共线断点连接
  skeleton_to_full.m    对齐坐标 → 原图坐标，原图上沿法向吸附到暗线中心
  make_overlay.m / save_debug.m / draw_text.m   标注图、中间结果、点阵字体
  evaluate_results.m    图像级与位置级评估（只在评估阶段读标签）
  其他                  缩放、平滑、JSON/CSV 读写等小工具
data/
  labels.csv            参考标签（文件名、推断的拍摄时间、标签来源、复核状态、拍摄组、样本条件）
  annotations.json      第一批有隐裂图的参考折线与区域框（人工目视标注）
cracked/ uncracked/     原始图片（保留原文件名，程序不修改）
outputs/                实测输出（见下）
docs/设计报告.md         中文设计报告
```

## 关键参数（`src/crack_config.m`）

长度类参数以**细栅间距 pitch** 为单位，程序对每张图从像素估计栅距（本批原图约 48–64 px），再换算成像素；
灰度类参数以 `[0,1]` 浮点灰度为单位；z 为局部稳健 z 分数（响应 / 分块残差的 1.4826·MAD）。

| 参数 | 默认值 | 单位 | 作用 |
| --- | --- | --- | --- |
| `targetPitchPx` | 28 | px | 工作图中的目标栅距，决定工作缩放比（本批原图约 0.5） |
| `brightThresh` / `bigBrightArea` / `seamMargin` | 0.90 / 4 / 0.8 | 灰度 / pitch² / pitch | 亮缝、过曝区判定及向外排除宽度 |
| `bgSigma` | 1.5 | pitch | 带掩膜高斯背景 B 的尺度 |
| `colBlock` / `rowBlock` | 2.5 / 4 | pitch | 沿细栅 / 沿主栅方向求稳健中值的分块长度 |
| `structQuantile` | 0.7 | — | 对 z 沿两个方向求分位数并减去，压制重复结构响应 |
| `smoothLen` | 1.0 | pitch | 暗线响应中沿候选方向平滑的长度 |
| `sideOffsets` | 0.08 / 0.13 / 0.20 | pitch | 法向两侧取样偏移（原图约 4 / 7 / 11 px） |
| `nOrient` | 12 | 个 | 候选方向数（15° 间隔） |
| `zHigh` / `zLow` | 4.5 / 2.5 | z | 滞后阈值的种子 / 生长阈值 |
| `minLength` / `minCross` | 3 / 2 | pitch / 根 | 斜向裂纹最短骨架长度、最少跨越细栅数 |
| `minLenParFinger` / `minLenParBusbar` | 8 / 5 | pitch | 近似平行细栅 / 主栅的裂纹的最短长度 |
| `maxWidth` / `minMeanZ` | 0.30 / 3.0 | pitch / z | 平均宽度上限（排除斑块）、骨架平均响应下限 |
| `maxBusbarFrac` | 0.5 | — | 候选落在汇流条带内的比例上限 |
| `linkGap` / `linkAngle` | 1.5 / 35 | pitch / ° | 近距离断点连接 |
| `linkGapLong` / `linkAngleLong` | 3.5 / 15 | pitch / ° | 共线断点（被汇流条隔开）连接 |
| `growIter` / `growDist` / `growSeedZ` | 3 / 2 / 3.5 | 次 / pitch / z | 已确认裂纹附近较弱分支的并入（只在已判定有裂纹时进行） |
| `minValidFrac` | 0.30 | — | 有效面积占比低于此值时判为待复核 |
| `base.k` / `base.minLength` | 3 / 2 | — / pitch | 基线阈值 = 中位数 + k·1.4826·MAD；连通域最短主轴 |

每次运行把实际使用的全部参数写入输出目录的 `run_config.json`。

## 输出与坐标规则

| 文件 | 内容 |
| --- | --- |
| `outputs/results.csv` | 每张原图一行：文件、判定（有隐裂 / 无隐裂 / 待复核 / 读取失败）、裂纹数、复核原因、备注、标注图与掩膜路径（相对 `outputs/`）、栅线方向、栅距、有效区比例、耗时、错误信息。UTF-8 带 BOM，可直接用 Excel 打开 |
| `outputs/overlays/*.jpg` | 原尺寸标注图：红色半透明中心线、黄色编号边界框、左上角状态 |
| `outputs/masks/*.png` | 原尺寸二值裂纹掩膜（255 = 裂纹） |
| `outputs/defects.json` | 每张图的判定、诊断信息和每条裂纹的位置 |
| `outputs/debug/<图名>/` | 代表样本的中间结果：01 原图、02 有效区、03 亮度校正、04 栅线抑制、05 暗线响应、06 候选、07 叠加，及 `00_montage.jpg` 总览 |
| `outputs/baseline/` | 基线方法的同结构输出 |
| `outputs/evaluation/` | `evaluation.md`（指标表）、`evaluation_per_image.csv`、`evaluation.json` |
| `run_log.txt` / `run_config.json` / `run_demo_log.txt` | 运行命令、环境版本、输入目录、参数、逐图结果与错误 |

坐标统一使用**原图像素坐标**：左上角像素为 `(1,1)`，`x` 为列（向右），`y` 为行（向下）；
`bbox = [x_min, y_min, x_max, y_max]`，两端都包含在框内；`points` 为中心线采样点 `[x, y]`，`endpoints` 为骨架端点。
检测在缩小并旋转对齐的工作图上进行，最终中心线经反旋转、反缩放映射回原图，并在原图上沿法向 ±3 px 吸附到局部最暗处。

## 评估口径

- 图像级：TP / FP / TN / FN、准确率、查准率、召回率、F1、无隐裂样本误报张数；待复核单独计数，并给出“待复核按有隐裂计”的口径。
- 位置级：参考折线（`data/annotations.json`）与预测掩膜的双向邻域覆盖率，容差 25 px 与 50 px（约 0.5 与 1 个栅距，对应人工标注精度）。
- 参考标签、文件名中的时间、目录名只在清点和评估阶段使用；检测函数只接收图像和参数。
- 全部 20 张图都参与了调参，指标描述的是本批样本上的表现，不代表对新组件的泛化精度（详见报告）。
