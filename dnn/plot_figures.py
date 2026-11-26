"""画报告用的两张图：深度网络训练曲线、四种方法对比柱状图。

    python dnn/plot_figures.py                  两张都画，写到 docs/images/
    python dnn/plot_figures.py --only curves    只画训练曲线（只读 dnn/models/ 下的 json，不需要 OpenCV）
    python dnn/plot_figures.py --only compare   只画方法对比（用 dnn/evaluate.py 现场复算指标）

数据来源：
  - 训练曲线：dnn/models/cv/fold*.json 和 dnn/models/crack_dnn.json 中的 history
    （train.py 每 50 步记录一次这 50 步的平均损失）。训练时固定 1600 步、不做早停、
    不在测试折上评估，所以只有训练损失，没有“验证曲线”；泛化表现看方法对比图中的交叉验证结果。
  - 方法对比：outputs/baseline、outputs、outputs/dnn_cv、outputs/fusion_cv 的 results.csv 与掩膜，
    指标口径与 outputs/evaluation/dnn_comparison.md 完全相同（同一个 evaluate() 函数）。

依赖：matplotlib、numpy；方法对比另需 opencv-python-headless（均已列在 dnn/requirements.txt）。
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import sys

import numpy as np
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
from matplotlib import font_manager  # noqa: E402
from matplotlib.lines import Line2D  # noqa: E402
from matplotlib.patches import PathPatch, Patch  # noqa: E402
from matplotlib.path import Path  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

# ---------------------------------------------------------------- 样式
# 1 个“设计像素” = 1/100 英寸；以 200 dpi 输出，网页按一半大小显示时正好清晰。
PX = 1 / 100
DPI = 200

SURFACE = "#ffffff"
INK = "#191919"          # 主文字
INK2 = "#666666"         # 坐标轴、图例、副标题
GRID = "#e7e7e7"         # 网格细线
BASE = "#c2c2c2"         # 基线 / 坐标轴

# 分类色（固定顺序，已用色觉缺陷模拟校验相邻对比）：基线、改进法、深度网络、融合
SERIES = ["#257de0", "#f47230", "#00b894", "#f2a600"]
# 状态色：判对 / 待复核 / 误报 / 漏检（总配文字图例，不单靠颜色）
GOOD, WARN, SERIOUS, CRITICAL = "#0aac23", "#fbb315", "#f18a59", "#dc3c3d"

METHODS = [  # (结果目录, 名称)
    ("outputs/baseline", "基线"),
    ("outputs", "改进法 v1.1"),
    ("outputs/dnn_cv", "深度网络（交叉验证）"),
    ("outputs/fusion_cv", "融合（交叉验证）"),
]

CJK_FONTS = ["Microsoft YaHei", "PingFang SC", "Hiragino Sans GB", "Noto Sans CJK SC", "Noto Sans SC",
             "Source Han Sans SC", "WenQuanYi Zen Hei", "SimHei", "Arial Unicode MS"]


def setup_style():
    import logging
    logging.getLogger("matplotlib.font_manager").setLevel(logging.ERROR)  # 中文字体无粗体时不刷屏
    have ={f.name for f in font_manager.fontManager.ttflist}
    cjk = [f for f in CJK_FONTS if f in have]
    if not cjk:
        print("提示：没有找到中文字体，图中汉字可能显示为方框。Windows 自带“Microsoft YaHei”，"
              "Linux 可安装 fonts-wqy-zenhei 或 fonts-noto-cjk。", file=sys.stderr)
    plt.rcParams.update({
        "font.family": "sans-serif",
        "font.sans-serif": cjk + ["DejaVu Sans"],
        "axes.unicode_minus": False,
        "font.size": 9.5,
        "text.color": INK,
        "axes.edgecolor": BASE,
        "axes.labelcolor": INK2,
        "xtick.color": INK2,
        "ytick.color": INK2,
        "xtick.labelcolor": INK2,
        "ytick.labelcolor": INK2,
        "figure.facecolor": SURFACE,
        "axes.facecolor": SURFACE,
        "savefig.facecolor": SURFACE,
    })


def quiet_axes(ax, grid_axis="y"):
    """坐标区只留一条基线（数值从它长出）和浅色网格细线。"""
    for s in ax.spines.values():
        s.set_visible(False)
    base = ax.spines["bottom" if grid_axis == "y" else "left"]
    base.set_visible(True)
    base.set_color(BASE)
    ax.tick_params(length=0, pad=4)
    ax.grid(axis=grid_axis, color=GRID, linewidth=0.8)
    ax.set_axisbelow(True)


def header(fig, title, subtitle, top=0.975, left=0.035):
    fig.text(left, top, title, fontsize=13.5, fontweight="bold", color=INK, va="top")
    fig.text(left, top - 0.045, subtitle, fontsize=9, color=INK2, va="top", linespacing=1.5)


# ---------------------------------------------------------------- 圆角条形
def _data_per_inch(ax):
    bb = ax.get_window_extent()
    x0, x1 = ax.get_xlim()
    y0, y1 = ax.get_ylim()
    return abs(x1 - x0) / (bb.width / ax.figure.dpi), abs(y1 - y0) / (bb.height / ax.figure.dpi)


def rounded_bar(ax, x0, x1, yc, height_px, color, r_px=4, left=False, right=True):
    """横向条形：高度、圆角半径按“设计像素”给出，只有指定的一端是圆角（基线端保持直角）。"""
    if x1 <= x0:
        return
    ux, uy = _data_per_inch(ax)
    h = height_px * PX * uy
    n_round = int(left) + int(right)
    rx = min(r_px * PX * ux, (x1 - x0) / max(n_round, 1))
    ry = min(r_px * PX * uy, h / 2)
    y0, y1 = yc - h / 2, yc + h / 2
    k = 0.5523
    rl = (rx if left else 0.0, ry if left else 0.0)
    rr = (rx if right else 0.0, ry if right else 0.0)
    V = [(x0 + rl[0], y0), (x1 - rr[0], y0),
         (x1 - rr[0] + k * rr[0], y0), (x1, y0 + rr[1] - k * rr[1]), (x1, y0 + rr[1]),
         (x1, y1 - rr[1]),
         (x1, y1 - rr[1] + k * rr[1]), (x1 - rr[0] + k * rr[0], y1), (x1 - rr[0], y1),
         (x0 + rl[0], y1),
         (x0 + rl[0] - k * rl[0], y1), (x0, y1 - rl[1] + k * rl[1]), (x0, y1 - rl[1]),
         (x0, y0 + rl[1]),
         (x0, y0 + rl[1] - k * rl[1]), (x0 + rl[0] - k * rl[0], y0), (x0 + rl[0], y0),
         (x0 + rl[0], y0)]
    C = [Path.MOVETO, Path.LINETO, Path.CURVE4, Path.CURVE4, Path.CURVE4, Path.LINETO,
         Path.CURVE4, Path.CURVE4, Path.CURVE4, Path.LINETO, Path.CURVE4, Path.CURVE4, Path.CURVE4,
         Path.LINETO, Path.CURVE4, Path.CURVE4, Path.CURVE4, Path.CLOSEPOLY]
    ax.add_patch(PathPatch(Path(V, C), facecolor=color, edgecolor="none", zorder=3))


def text_width_in(fig, s, size):
    r = fig.canvas.get_renderer()
    t = fig.text(0, 0, s, fontsize=size)
    w = t.get_window_extent(renderer=r).width / fig.dpi
    t.remove()
    return w


# ---------------------------------------------------------------- 图 1：训练曲线
def load_histories():
    folds = []
    for p in sorted(glob.glob(os.path.join(HERE, "models", "cv", "fold*.json"))):
        folds.append(json.load(open(p, encoding="utf-8")))
    final_p = os.path.join(HERE, "models", "crack_dnn.json")
    final = json.load(open(final_p, encoding="utf-8")) if os.path.exists(final_p) else None
    if not folds:
        raise FileNotFoundError("dnn/models/cv/ 下没有 fold*.json，请先运行 python dnn/cv.py")
    return folds, final


def plot_curves(out_path):
    folds, final = load_histories()
    steps = np.array([h["step"] for h in folds[0]["history"]])
    panels = [
        ("loss", "总损失", "分割 BCE + Dice + 0.5 × 决策 BCE"),
        ("bce", "分割：加权 BCE", "裂纹像素权重 3，忽略区不计"),
        ("dice", "分割：Soft Dice 损失", "1 - Dice，越低表示预测与标签重合越多"),
        ("cls", "决策：BCE", "“这一小块有没有裂纹”的分类损失"),
    ]
    fig = plt.figure(figsize=(10, 6.9), dpi=DPI)
    every = int(steps[1] - steps[0]) if len(steps) > 1 else int(steps[0])
    ntrain = sorted({len(f["train_files"]) for f in folds})
    header(fig, "深度网络训练损失",
           f"每点为 {every} 步的平均训练损失；{len(folds)} 折交叉验证各训练 {steps[-1]} 步"
           f"（每折 {'/'.join(map(str, ntrain))} 张训练图），学习率 {folds[0]['lr']:g} 余弦衰减。\n"
           "训练时不做早停、不在测试折上评估，因此没有验证曲线；泛化表现见方法对比图中的交叉验证结果。")
    # 图例（两条序列）
    leg_y = 0.835
    handles = [
        (Line2D([], [], color=SERIES[0], lw=2), Patch(facecolor=SERIES[0], alpha=0.14, edgecolor="none")),
    ]
    labels = [f"交叉验证 {len(folds)} 折：均值（阴影为最小–最大）"]
    if final:
        handles.append(Line2D([], [], color=SERIES[1], lw=2))
        labels.append(f"部署模型：全部 {len(final['train_files'])} 张图训练")
    from matplotlib.legend_handler import HandlerTuple
    fig.legend(handles, labels, loc="upper left", bbox_to_anchor=(0.035, leg_y + 0.02), ncol=2, frameon=False,
               fontsize=9, labelcolor=INK2, handlelength=2.2, columnspacing=2.2,
               handler_map={tuple: HandlerTuple(ndivide=None, pad=0)})

    L, R, B, T = 0.07, 0.975, 0.075, 0.71
    gx, gy = 0.085, 0.135
    w = (R - L - gx) / 2
    h = (T - B - gy) / 2
    for i, (key, title, note) in enumerate(panels):
        r, c = divmod(i, 2)
        ax = fig.add_axes([L + c * (w + gx), B + (1 - r) * (h + gy), w, h])
        Y = np.array([[e[key] for e in f["history"]] for f in folds])
        mean = Y.mean(0)
        ax.fill_between(steps, Y.min(0), Y.max(0), color=SERIES[0], alpha=0.14, lw=0, zorder=2)
        if final:
            yf = np.array([e[key] for e in final["history"]])
            ax.plot(steps, yf, color=SERIES[1], lw=1.6, solid_capstyle="round", solid_joinstyle="round", zorder=3)
        ax.plot(steps, mean, color=SERIES[0], lw=2, solid_capstyle="round", solid_joinstyle="round", zorder=4)
        top = float(max(Y.max(), yf.max() if final else 0))
        ax.set_ylim(0, nice_ceiling(top))
        ax.set_xlim(0, steps[-1] * 1.02)
        ax.set_xticks(np.arange(0, steps[-1] + 1, 400))
        quiet_axes(ax, "y")
        ax.set_title(title, loc="left", fontsize=10.5, fontweight="bold", color=INK, pad=20)
        ax.text(0, 1.035, note, transform=ax.transAxes, fontsize=8.5, color=INK2, va="bottom")
        if r == 1:
            ax.set_xlabel("训练步数", fontsize=9)
        # 只标末端：折均值的最后一个值
        ax.annotate(f"{mean[-1]:.3f}", (steps[-1], mean[-1]), xytext=(0, 7), textcoords="offset points",
                    ha="right", va="bottom", fontsize=8.5, color=INK)
        ax.plot([steps[-1]], [mean[-1]], "o", ms=5, mfc=SERIES[0], mec=SURFACE, mew=1.5, zorder=5)
    fig.savefig(out_path, dpi=DPI)
    plt.close(fig)
    print("已写出", out_path)


def nice_ceiling(v):
    for step in (0.01, 0.02, 0.05, 0.1, 0.2, 0.25, 0.5, 1.0):
        if v / step <= 6:
            return float(np.ceil(v / step) * step)
    return float(np.ceil(v))


# ---------------------------------------------------------------- 图 2：方法对比
def compute_metrics():
    import evaluate as ev   # dnn/evaluate.py（需要 OpenCV）
    labels, _ = ev.load_refs()
    npos = sum(1 for y in labels.values() if y == 1)
    nneg = sum(1 for y in labels.values() if y == 0)
    dirs = [d for d, _ in METHODS if os.path.exists(os.path.join(ROOT, d, "results.csv"))]
    rows = {}
    for d, tp, fp, tn, fn, rv, er, acc, prec, rec, f1, P in ev.evaluate(dirs, write=False):
        rows[d] = dict(tp=tp, fp=fp, tn=tn, fn=fn, rv=rv, er=er, **P)
    return rows, npos, nneg


def plot_compare(out_path):
    rows, npos, nneg = compute_metrics()
    methods = [(d, n, SERIES[i]) for i, (d, n) in enumerate(METHODS) if d in rows]
    n = len(methods)
    total = npos + nneg

    fig = plt.figure(figsize=(11, 7.6), dpi=DPI)
    header(fig, "四种方法对比",
           f"同一套参考标签：{npos} 张有隐裂、{nneg} 张无隐裂。基线和改进法的参数在这批图上确定；"
           "深度网络和融合为 5 折按整图交叉验证，\n每张图只由没见过它的模型检测。"
           "数值与 outputs/evaluation/dnn_comparison.md 相同（同一个 evaluate() 计算）。")

    # ---- A. 图像级判定：每种方法一条分段条
    fig.text(0.035, 0.835, f"图像级判定（{total} 张）", fontsize=11, fontweight="bold", color=INK, va="top")
    seg_def = [("判对", GOOD, "#ffffff"), ("待复核", WARN, "#0b0b0b"),
               ("误报（无隐裂判为有）", SERIOUS, "#ffffff"), ("漏检（有隐裂判为无）", CRITICAL, "#ffffff")]
    fig.legend([Patch(facecolor=c, edgecolor="none") for _, c, _ in seg_def], [s for s, _, _ in seg_def],
               loc="upper left", bbox_to_anchor=(0.03, 0.81), ncol=4, frameon=False, fontsize=9,
               labelcolor=INK2, handlelength=1.1, handleheight=1.1, columnspacing=1.8)
    axA = fig.add_axes([0.175, 0.515, 0.52, 0.235])
    axA.set_xlim(0, total)
    axA.set_ylim(-0.6, n - 0.4)
    axA.axis("off")
    ux, _ = _data_per_inch(axA)
    gap = 2 * PX * ux
    for i, (d, name, _) in enumerate(methods):
        r = rows[d]
        yc = n - 1 - i
        parts = [r["tp"] + r["tn"], r["rv"], r["fp"], r["fn"]]
        x = 0.0
        nz = [k for k, v in enumerate(parts) if v > 0]
        for k, v in enumerate(parts):
            if v <= 0:
                continue
            a = x + (gap / 2 if k != nz[0] else 0)
            b = x + v - (gap / 2 if k != nz[-1] else 0)
            rounded_bar(axA, a, b, yc, 26, seg_def[k][1], r_px=4, left=True, right=True)
            lab = str(v)
            if text_width_in(fig, lab, 9) + 12 * PX < (b - a) / ux:
                axA.text(a + 6 * PX * ux, yc, lab, ha="left", va="center", fontsize=9,
                         fontweight="bold", color=seg_def[k][2], zorder=4)
            x += v
        axA.text(-0.3, yc, name, ha="right", va="center", fontsize=9.5, color=INK)
        detail = f"有隐裂判对 {r['tp']}/{npos} · 无隐裂判对 {r['tn']}/{nneg}"
        if r["rv"]:
            detail += f" · 待复核 {r['rv']}"
        if r["er"]:
            detail += f" · 未出结果 {r['er']}"
        axA.text(total + 0.5, yc, detail, ha="left", va="center", fontsize=8.8, color=INK2)

    # ---- B. 位置指标：4 个小图，每图 4 条横向条
    fig.text(0.035, 0.445, f"裂纹位置（{npos} 张有隐裂图，按全部参考点 / 预测像素合计；越高越好）",
             fontsize=11, fontweight="bold", color=INK, va="top")
    fig.legend([Patch(facecolor=c, edgecolor="none") for _, _, c in methods], [nm for _, nm, _ in methods],
               loc="upper left", bbox_to_anchor=(0.03, 0.42), ncol=n, frameon=False, fontsize=9,
               labelcolor=INK2, handlelength=1.1, handleheight=1.1, columnspacing=1.8)
    metrics = [("cov25", "参考覆盖率 ±25 px", "参考裂纹被找到的比例"),
               ("cov50", "参考覆盖率 ±50 px", "同上，容差放宽"),
               ("prec50", "预测精度 ±50 px", "预测落在参考裂纹附近的比例"),
               ("inreg", "区域内比例 ±50 px", "另计入参考区域框内的预测")]
    L, R, B, T = 0.175, 0.975, 0.065, 0.285
    gx = 0.035
    w = (R - L - 3 * gx) / 4
    for j, (key, title, note) in enumerate(metrics):
        ax = fig.add_axes([L + j * (w + gx), B, w, T - B])
        ax.set_xlim(0, 125)          # 右侧留出数值标签的位置，刻度只到 100%
        ax.set_ylim(-0.6, n - 0.4)
        ax.set_xticks([0, 50, 100])
        ax.set_xticklabels(["0", "50%", "100%"], fontsize=8.5)
        ax.set_yticks([])
        quiet_axes(ax, "x")
        ax.set_title(title, loc="left", fontsize=9.8, fontweight="bold", color=INK, pad=17)
        ax.text(0, 1.03, note, transform=ax.transAxes, fontsize=8.3, color=INK2, va="bottom")
        for i, (d, name, col) in enumerate(methods):
            yc = n - 1 - i
            v = rows[d][key]
            if v is None or np.isnan(v):
                ax.text(1.5, yc, "—", ha="left", va="center", fontsize=8.5, color=INK2)
                continue
            rounded_bar(ax, 0, 100 * v, yc, 16, col, r_px=4, left=False, right=True)
            ax.text(100 * v + 2, yc, f"{100 * v:.1f}%", ha="left", va="center", fontsize=8.5, color=INK, zorder=4)
            if j == 0:
                ax.text(-5, yc, name, ha="right", va="center", fontsize=9.5, color=INK, clip_on=False)
    fig.savefig(out_path, dpi=DPI)
    plt.close(fig)
    print("已写出", out_path)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default=os.path.join(ROOT, "docs", "images"), help="输出目录（默认 docs/images）")
    ap.add_argument("--only", choices=["curves", "compare"], help="只画其中一张")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    setup_style()
    if a.only in (None, "curves"):
        plot_curves(os.path.join(a.out, "dnn_training_curves.png"))
    if a.only in (None, "compare"):
        plot_compare(os.path.join(a.out, "method_comparison.png"))


if __name__ == "__main__":
    main()
