# 太阳能电池片隐裂检测（MATLAB）

数字图像处理大作业：对太阳能电池片实拍图像逐张判断是否存在**可见内部隐裂**，并在原图上标出裂纹位置与坐标边界框。
方法为传统图像处理（不训练模型）：有效区域与背景估计 → 栅线方向/间距估计与双向纹理抑制 →
多方向细暗线增强与长程方向一致性桥接 → 双阈值、骨架化、测地切线多轮共线/T 型连接与双准则筛选 →
联合延伸生长 → 映射回原图并沿法向吸附到暗线中心。

完整的设计说明见 [`docs/设计报告.md`](docs/设计报告.md)。

## 运行环境

| 项目 | 说明 |
| --- | --- |
| MATLAB | 需要 MATLAB R2016b 及以上 + Image Processing Toolbox（本地桌面端支持图形化选图与双栏联动缩放查看器） |
| GNU Octave | 兼容 GNU Octave 8+ 与 `image` 包（无图形界面时自动以命令行批处理模式运行） |
| 不依赖 | Statistics Toolbox、Computer Vision Toolbox（百分位数、稳健统计、点阵字体绘制、JSON 写出均在 `src/` 中自行实现） |

用到的工具箱基础函数：`hough / houghpeaks / houghlines / imdilate / imreconstruct / bwmorph / bwlabel / bwareaopen / bwdist / regionprops / padarray / im2double / im2uint8 / ind2rgb`。

## 助教现场验收（全新图像测试，推荐入口）

验收时面对助教给出的全新太阳能电池片图像（任意分辨率、任意细栅方向、单张或混合文件夹），直接在 MATLAB 命令窗口运行：

```matlab
run_inspect
```

1. **零参数图形化导入**：不带参数运行 `run_inspect` 会弹出选择框，可直接点选**整个测试文件夹**（自动递归扫描子目录）或**单张/多张图片**；
2. **命令行直接传路径**（支持文件夹、单张图片或混合元胞数组，路径可含中文和空格）：
   ```matlab
   run_inspect('D:\助教测试样本')
   run_inspect('D:\助教测试样本\test_01.jpg')
   run_inspect({'D:\图1.jpg', 'D:\图2.bmp'})
   ```
3. **直观输出**：
   - 命令窗口直接打印**逐张判定结果（有缺陷 / 无缺陷 / 待复核）、检出裂纹条数与每条裂纹的像素边界框 `[x_min, y_min, x_max, y_max]`**；
   - 自动弹出**交互式双栏联动查看器**（左栏原图、右栏红线+黄框标注图，使用工具栏放大镜放大右侧裂纹时，左侧原图**同步放大到同一像素区域**以便核对原始暗纹；支持键盘 `←`/`→` 翻页及一键筛选有缺陷样本）；
   - 结果独立保存在 `outputs/inspect/`（含 `overlays/*.jpg`、`masks/*.png`、`results.csv`、`defects.json`），**不会覆盖** `outputs/` 中原有的实验基准结果。

## 完整实验复现（改进法 + 基线对照 + 定量评估）

在项目目录的 MATLAB 命令窗口：

```matlab
run_demo
```

或在终端（项目目录下）：

```bash
matlab -batch "run_demo"
```

`run_demo` 会对仓库样本依次运行改进法与基线法，写出 `outputs/`（改进法）、`outputs/baseline/`（基线）、`outputs/evaluation/`（图像级与位置级评估），完整控制台记录保存在 `outputs/run_demo_log.txt`。

更多批处理与单图调用示例：

```matlab
run_batch({'D:\电池片样本'}, 'D:\检测结果')                          % 只跑改进法批处理
run_batch('cracked/cracked_06.jpg', 'outputs/single_test')          % 单张图像导出
run_batch('data/raw', 'outputs_base', 'Method', 'baseline')         % 只跑基线
run_batch('data/raw', 'out', 'Debug', {'*'})                        % 输出 7 步中间结果拼图

% 纯函数调用（只接收像素矩阵和参数结构体，不读取文件名、目录名或标签）
addpath('src');
G   = read_gray('cracked/cracked_06.jpg');
cfg = crack_config();
res = detect_cracks(G, cfg);
res.status, res.nCracks, res.cracks(1).bbox
```

## 项目结构

```
run_inspect.m           助教现场验收专用入口：GUI 选图/文件夹 + 坐标汇总表 + 双栏联动查看器
run_demo.m              完整实验演示入口：改进法 + 基线 + 参考集定量评估
run_batch.m             扫描目录或文件、逐图检测并导出 CSV/JSON/标注图/掩膜/调试图
src/
  crack_config.m        全部参数定义（以实测细栅间距 pitch 为几何单位）
  detect_cracks.m       改进法单图检测 = crack_response + segment_cracks
  crack_response.m      有效区/背景 → 亮度校正 → 栅线/横向结构抑制 → 暗线响应 → 方向一致性增强
  coherent_line_enhance.m 双侧长程方向一致性跨细栅桥接与淡裂纹增强
  segment_cracks.m      双阈值 → 骨架 → 断点连接 → 双准则筛选 → 联合延伸生长与次生淡裂纹回收
  link_segments.m       沿骨架测地切线估计 + 两轮共线断点连接 + T/X 型交点连接
  detect_baseline.m     基线：max(B-I,0) 稳健阈值 + 连通域面积/主轴长度筛选
  prepare_image.m       共用前端：栅线估计、自适应工作尺度、旋转对齐、亮缝/黑框排除、掩膜背景 B
  estimate_grid.m       Hough 线段长度加权方向 + 3×3 分块投影自相关求栅距
  dark_line_response.m  多方向两侧取样 min(左,右)-中心 细暗线响应
  skeleton_to_full.m    对齐坐标 → 原图坐标映射，原图沿法向吸附到暗线中心
  show_results_viewer.m MATLAB 桌面端双栏同步缩放结果浏览器
  make_overlay.m / save_debug.m / draw_text.m   醒目标注图、中间结果拼图、内置点阵字体
  evaluate_results.m    图像级与位置级评估（仅在评估阶段读取参考标签）
  disk_dilate.m 等      基于精确欧氏距离变换的快速圆盘形态学、抗混叠重采样、JSON/CSV 读写工具
tools/
  param_sensitivity.m   关键参数单因素敏感性实验
data/
  labels.csv            参考类别与样本条件标签
  annotations.json      有隐裂样本的人工参考折线与区域框
cracked/ uncracked/     仓库原始样本图像（只读）
outputs/                实验输出（标注叠加图、二值掩膜、CSV/JSON、中间结果与评估报告）
docs/设计报告.md         课程设计报告
```

## 关键参数（`src/crack_config.m`）

长度类参数以**细栅间距 `pitch`** 为单位，程序对每张图从像素自动估计栅距并换算，自适应不同分辨率与拍摄距离。

| 参数 | 默认值 | 单位 | 作用 |
| --- | --- | --- | --- |
| `targetPitchPx` / `maxWorkScale` | 28 / 1.6 | px / — | 工作图目标栅距及低分辨率图适度上采样上限 |
| `brightThresh` / `bigBrightArea` / `seamMargin` | 0.90 / 4 / 0.8 | 灰度 / pitch² / pitch | 亮缝、过曝区（及外圈黑框）判定与向外排除宽度 |
| `bgSigma` | 1.5 | pitch | 带掩膜高斯背景 `B` 的尺度 |
| `colBlock` / `rowBlock` / `rowBlockZ` | 2.5 / 4 / 10 | pitch | 沿细栅、主栅方向稳健抑制的分块尺度 |
| `structQuantile` | 0.7 | — | 对 `z` 沿两个方向求分位数并减去，压制重复结构残影 |
| `smoothLen` / `sideOffsets` | 1.0 / 0.08,0.13,0.20 | pitch | 单尺度暗线平滑长度与法向两侧取样偏移 |
| `cohHalfLen` / `cohBridgeGain` / `cohBoostGain` | 1.25 / 1.90 / 1.00 | pitch / — / — | 长程方向一致性跨细栅桥接半径与增益 |
| `zHigh` / `zLow` | 4.5 / 2.5 | z | 标准滞后阈值的峰值与生长下限 |
| `minLength` / `minCross` / `minMeanZ` | 3.0 / 2.0 / 3.0 | pitch / 根 / z | 标准裂纹最短长度、最少跨细栅数与平均响应下限 |
| `minFaintLen` / `minFaintCross` / `minFaintMeanZ` | 5.5 / 4.0 / 2.70 | pitch / 根 / z | 长程共线淡裂纹筛选下限 |
| `maxWidth` / `maxBusbarFrac` | 0.30 / 0.50 | pitch / — | 平均宽度上限（排除斑块）与汇流条带占比上限 |
| `linkGap` / `linkAngle` | 1.5 / 35 | pitch / ° | 近距离断点共线连接阈值 |
| `linkGapLong` / `linkAngleLong` | 3.5 / 15 | pitch / ° | 跨汇流条长距离共线连接阈值 |
| `growIter` / `growDist` / `growSeedZ` | 3 / 2.5 / 3.3 | 次 / pitch / z | 已确认有裂纹图像的联合延伸生长参数 |

## 输出与坐标规则

坐标统一使用**原图像素坐标**：左上角像素为 `(1,1)`，`x` 为列（向右），`y` 为行（向下）；
`bbox = [x_min, y_min, x_max, y_max]`（两端均包含在框内）；`points` 为中心线采样点 `[x, y]`，`endpoints` 为骨架端点。
