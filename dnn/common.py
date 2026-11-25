"""深度网络部分的公共函数：读图、栅距估计、预处理、分块推理、后处理与结果写出。

坐标约定与 MATLAB 部分一致：输出中的像素坐标以原图左上角像素为 (1,1)，x 为列、y 为行，
bbox = [x_min, y_min, x_max, y_max]（含两端）。
"""
from __future__ import annotations

import csv
import json
import math
import os
from dataclasses import dataclass

import cv2
import numpy as np
from skimage.filters import apply_hysteresis_threshold
from skimage.measure import label as cc_label
from skimage.morphology import skeletonize

IMG_EXTS = {".jpg", ".jpeg", ".png", ".bmp", ".tif", ".tiff"}
TARGET_PITCH = 28.0          # 网络工作尺度：细栅间距统一缩放到 28 px（与 MATLAB 改进法的工作图一致）
TILE = 256                   # 训练 / 推理小块边长（工作尺度像素，约 9 个栅距）


# ---------------------------------------------------------------- 读图与列举
def read_gray(path: str) -> np.ndarray:
    """读取图像为 [0,1] 浮点灰度；兼容中文路径、灰度/彩色/带 alpha/16 位图。"""
    data = np.fromfile(path, dtype=np.uint8)
    img = cv2.imdecode(data, cv2.IMREAD_UNCHANGED)
    if img is None:
        raise IOError(f"无法读取图像：{path}")
    if img.ndim == 3:
        if img.shape[2] == 4:
            img = img[:, :, :3]
        img = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    if img.dtype == np.uint16:
        return img.astype(np.float32) / 65535.0
    if img.dtype == np.uint8:
        return img.astype(np.float32) / 255.0
    img = img.astype(np.float32)
    return np.clip(img / max(1e-6, float(img.max())), 0, 1)


def list_images(inputs: list[str], recursive: bool = True) -> list[str]:
    """把文件 / 文件夹列表展开为图像路径（扩展名大小写不敏感，跳过程序输出目录）。"""
    skip = {"outputs", "overlays", "masks", "debug", "baseline", "prob", ".git"}
    out = []
    for p in inputs:
        if os.path.isfile(p):
            if os.path.splitext(p)[1].lower() in IMG_EXTS:
                out.append(p)
        elif os.path.isdir(p):
            for root, dirs, files in os.walk(p):
                dirs[:] = [d for d in dirs if d.lower() not in skip] if recursive else []
                for f in sorted(files):
                    if os.path.splitext(f)[1].lower() in IMG_EXTS:
                        out.append(os.path.join(root, f))
    return sorted(dict.fromkeys(out))


def relpath_key(path: str) -> str:
    """“上级目录名/文件名”，与 MATLAB 输出中的 file 字段一致。"""
    path = os.path.abspath(path)
    return os.path.basename(os.path.dirname(path)) + "/" + os.path.basename(path)


# ---------------------------------------------------------------- 栅距估计
def estimate_pitch(g: np.ndarray) -> tuple[float, bool]:
    """用二维频谱估计细栅间距（原图像素）。返回 (栅距, 是否可靠)。

    细栅是整幅图里最强的等间距结构，高通滤波后的功率谱在“1/栅距”处有尖峰；
    细栅很细，二次谐波也很强，所以若半频处功率足够大，取半频（即更长的周期）。
    """
    H, W = g.shape
    k = 1024.0 / max(H, W)
    small = cv2.resize(g, (max(8, round(W * k)), max(8, round(H * k))), interpolation=cv2.INTER_AREA)
    small = np.minimum(small, np.percentile(small, 99))
    hp = small - cv2.GaussianBlur(small, (0, 0), 3)
    h, w = hp.shape
    win = np.outer(np.hanning(h), np.hanning(w)).astype(np.float32)
    F = np.abs(np.fft.fftshift(np.fft.fft2(hp * win))) ** 2
    F = cv2.GaussianBlur(F.astype(np.float32), (0, 0), 1.0)
    fy = (np.arange(h) - h // 2)[:, None] / h
    fx = (np.arange(w) - w // 2)[None, :] / w
    fr = np.sqrt(fx ** 2 + fy ** 2)
    band = (fr > 1 / 40.0) & (fr < 1 / 3.5)
    Fb = np.where(band, F, 0)
    iy, ix = np.unravel_index(np.argmax(Fb), Fb.shape)
    peak = Fb[iy, ix]
    f0 = fr[iy, ix]
    # 半频检查（基波 vs 二次谐波）
    hy, hx = h // 2 + round((iy - h // 2) / 2), w // 2 + round((ix - w // 2) / 2)
    y0, y1, x0, x1 = max(0, hy - 2), min(h, hy + 3), max(0, hx - 2), min(w, hx + 3)
    half = F[y0:y1, x0:x1].max() if y1 > y0 and x1 > x0 else 0
    if fr[hy, hx] > 1 / 40.0 and half >= 0.35 * peak:
        f0 = fr[hy, hx]
    reliable = peak > 20 * np.median(Fb[band])
    pitch = (1.0 / f0) / k
    if not reliable or not np.isfinite(pitch):
        return 0.0102 * max(H, W), False
    return float(pitch), True


# ---------------------------------------------------------------- 预处理
@dataclass
class Prepared:
    x: np.ndarray          # [h, w, 2] 网络输入
    scale: float           # 工作尺度 / 原图
    pitch: float           # 原图栅距
    pitch_ok: bool
    full_shape: tuple


def work_scale(pitch: float) -> float:
    return float(np.clip(TARGET_PITCH / pitch, 0.2, 1.6))


def preprocess(g: np.ndarray, pitch: float | None = None) -> Prepared:
    """缩放到统一栅距并生成两通道输入：[灰度, 亮度校正残差 (I-B)/B]。

    参考工程用“同态滤波”压掉大面积亮度不均；这里用带截断的大尺度高斯背景 B 做相除归一化，
    作用相同但不会因裁剪丢失细节。第一通道保留原始灰度，帮助网络识别亮缝、过曝等结构。
    """
    ok = True
    if pitch is None:
        pitch, ok = estimate_pitch(g)
    s = work_scale(pitch)
    H, W = g.shape
    interp = cv2.INTER_AREA if s < 1 else cv2.INTER_LINEAR
    I = cv2.resize(g, (max(16, round(W * s)), max(16, round(H * s))), interpolation=interp)
    Ic = np.minimum(I, np.percentile(I, 98))
    B = cv2.GaussianBlur(Ic, (0, 0), 1.5 * TARGET_PITCH)
    Dn = (I - B) / np.maximum(B, 0.05)
    x = np.stack([I, np.clip(Dn, -1.0, 1.0) * 2.0], axis=-1).astype(np.float32)
    return Prepared(x=x, scale=s, pitch=float(pitch), pitch_ok=bool(ok), full_shape=(H, W))


def resize_label(lab_full: np.ndarray, shape: tuple) -> tuple[np.ndarray, np.ndarray]:
    """原图尺寸标签（0/128/255）缩放到工作尺度：返回 (正样本, 忽略)。

    细线缩小时用面积平均再取阈值，避免最近邻采样把 1–2 像素宽的裂纹丢掉。
    """
    h, w = shape
    pos = cv2.resize((lab_full == 255).astype(np.float32), (w, h), interpolation=cv2.INTER_AREA) > 0.12
    ign = cv2.resize((lab_full == 128).astype(np.float32), (w, h), interpolation=cv2.INTER_AREA) > 0.3
    return pos, ign & ~pos


# ---------------------------------------------------------------- 分块推理
def predict_prob(model, x: np.ndarray, tile: int = TILE, overlap: int = 48, batch: int = 8):
    """全图分块推理并用余弦窗加权拼接，返回 (裂纹概率图, 各块“有裂纹”概率的最大值)。"""
    h, w, _ = x.shape
    step = tile - overlap
    ys = list(range(0, max(1, h - tile) + 1, step))
    xs = list(range(0, max(1, w - tile) + 1, step))
    if ys[-1] + tile < h:
        ys.append(h - tile)
    if xs[-1] + tile < w:
        xs.append(w - tile)
    pad_h, pad_w = max(0, tile - h), max(0, tile - w)
    xp = np.pad(x, ((0, pad_h), (0, pad_w), (0, 0)), mode="reflect") if (pad_h or pad_w) else x
    win1 = np.hanning(tile + 2)[1:-1].astype(np.float32)
    win = np.outer(win1, win1) + 1e-3
    acc = np.zeros(xp.shape[:2], np.float32)
    wsum = np.zeros(xp.shape[:2], np.float32)
    coords = [(yy, xx) for yy in ys for xx in xs]
    tile_max = 0.0
    for i in range(0, len(coords), batch):
        cb = coords[i:i + batch]
        X = np.stack([xp[yy:yy + tile, xx:xx + tile] for yy, xx in cb])
        seg, cls = model(X, training=False)
        p = 1 / (1 + np.exp(-np.asarray(seg)[..., 0]))
        pc = 1 / (1 + np.exp(-np.asarray(cls)[:, 0]))
        tile_max = max(tile_max, float(pc.max()))
        for (yy, xx), pp in zip(cb, p):
            acc[yy:yy + tile, xx:xx + tile] += pp * win
            wsum[yy:yy + tile, xx:xx + tile] += win
    prob = acc / np.maximum(wsum, 1e-6)
    return prob[:h, :w], tile_max


# ---------------------------------------------------------------- 后处理
@dataclass
class PostCfg:
    high: float = 0.6         # 种子阈值
    low: float = 0.35         # 生长阈值
    min_len: float = 3.0      # 最短裂纹（栅距）
    review_frac: float = 0.6  # 达到 min_len 该比例的弱候选 → 待复核


def postprocess(prob: np.ndarray, prep: Prepared, pc: PostCfg = PostCfg()):
    """概率图 → 双阈值 → 骨架 → 连通段筛选 → 原图坐标的裂纹列表与掩膜。"""
    s = prep.scale
    H, W = prep.full_shape
    binm = apply_hysteresis_threshold(prob, pc.low, pc.high)
    # 裂纹穿过亮细栅时概率会断成虚线：先做半径 2 的闭运算把相邻小段连起来，再骨架化
    binm = cv2.morphologyEx(binm.astype(np.uint8), cv2.MORPH_CLOSE,
                            cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))) > 0
    sk = skeletonize(binm)
    L = cc_label(sk, connectivity=2)
    n = int(L.max())
    cracks, weak = [], 0
    mask_full = np.zeros((H, W), np.uint8)
    center_full = np.zeros((H, W), np.uint8)
    min_px = pc.min_len * TARGET_PITCH
    kept = 0
    for k in range(1, n + 1):
        yy, xx = np.nonzero(L == k)
        length = skeleton_length(yy, xx)
        if length < min_px:
            if length >= pc.review_frac * min_px and prob[yy, xx].mean() >= pc.high:
                weak += 1
            continue
        kept += 1
        X = (xx + 0.5) / s + 0.5          # 工作图 0 起像素中心 → 原图 1 起坐标
        Y = (yy + 0.5) / s + 0.5
        pts = order_points(X, Y)
        width = float(np.clip(2.0 / s, 2, 12))
        draw_polyline_mask(center_full, pts, 1)
        draw_polyline_mask(mask_full, pts, max(2, int(round(width))))
        bx = [int(max(1, np.floor(X.min() - width / 2))), int(max(1, np.floor(Y.min() - width / 2))),
              int(min(W, np.ceil(X.max() + width / 2))), int(min(H, np.ceil(Y.max() + width / 2)))]
        cov = np.cov(np.vstack([X, Y])) if len(X) > 2 else np.eye(2)
        ev, evec = np.linalg.eigh(cov)
        d = evec[:, np.argmax(ev)]
        ang = math.degrees(math.atan2(d[1], d[0])) % 180
        step = max(1, int(np.ceil(len(pts) / 200)))
        cracks.append({
            "id": kept, "bbox": bx,
            "centroid": [round(float(X.mean()), 1), round(float(Y.mean()), 1)],
            "length_px": round(length / s, 1), "width_px": round(width, 1),
            "angle_deg": round(ang, 1),
            "mean_prob": round(float(prob[yy, xx].mean()), 3),
            "endpoints": [[int(round(pts[0][0])), int(round(pts[0][1]))],
                          [int(round(pts[-1][0])), int(round(pts[-1][1]))]],
            "points": [[int(round(p[0])), int(round(p[1]))] for p in pts[::step]],
        })
    cracks.sort(key=lambda c: -c["length_px"])
    for i, c in enumerate(cracks, 1):
        c["id"] = i
    return cracks, weak, mask_full, center_full


def skeleton_length(yy, xx) -> float:
    """骨架长度：像素数按主方向做对角修正（与 MATLAB 部分的长度统计一致）。"""
    n = len(yy)
    if n < 3:
        return float(n)
    P = np.stack([xx, yy], 1).astype(np.float64)
    ev, evec = np.linalg.eigh(np.cov(P.T))
    d = evec[:, np.argmax(ev)]
    return n / max(abs(d[0]), abs(d[1]), 1e-6)


def order_points(X, Y):
    """按主方向投影排序中心线点，供写出折线采样点。"""
    P = np.stack([X, Y], 1)
    c = P.mean(0)
    u, s_, vt = np.linalg.svd(P - c, full_matrices=False)
    t = (P - c) @ vt[0]
    return P[np.argsort(t)]


def draw_polyline_mask(M, pts, thickness):
    p = np.round(pts - 1).astype(np.int32)       # 1 起坐标 → 0 起
    for (x0, y0), (x1, y1) in zip(p[:-1], p[1:]):
        if abs(x1 - x0) + abs(y1 - y0) <= 3 * max(2, thickness):   # 只连相邻点，分叉处不乱连
            cv2.line(M, (int(x0), int(y0)), (int(x1), int(y1)), 255, thickness, cv2.LINE_8)
    for x0, y0 in p:
        if thickness > 1:
            cv2.circle(M, (int(x0), int(y0)), max(1, thickness // 2), 255, -1)
        elif 0 <= y0 < M.shape[0] and 0 <= x0 < M.shape[1]:
            M[y0, x0] = 255


# ---------------------------------------------------------------- 结果写出
STATUS_NAME = {"crack": "有隐裂", "no_crack": "无隐裂", "review": "待复核", "error": "处理失败"}


def make_overlay(gray: np.ndarray, center: np.ndarray, cracks: list, status: str, method: str) -> np.ndarray:
    img = cv2.cvtColor((np.clip(gray, 0, 1) * 255).astype(np.uint8), cv2.COLOR_GRAY2BGR)
    H, W = gray.shape
    lw = max(2, round(max(H, W) / 1800))
    line = cv2.dilate(center, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * lw + 1, 2 * lw + 1))) > 0
    img[line] = (40, 40, 255)
    fs = max(0.8, max(H, W) / 2400)
    for c in cracks:
        x0, y0, x1, y1 = c["bbox"]
        pad = 6 * lw
        cv2.rectangle(img, (max(0, x0 - pad - 1), max(0, y0 - pad - 1)),
                      (min(W - 1, x1 + pad - 1), min(H - 1, y1 + pad - 1)), (0, 200, 255), lw + 1)
        cv2.putText(img, f"#{c['id']}", (max(0, x0 - pad), max(20, y0 - pad - 8)),
                    cv2.FONT_HERSHEY_SIMPLEX, fs, (0, 200, 255), 2 * lw, cv2.LINE_AA)
    col = {"crack": (60, 60, 255), "no_crack": (80, 220, 80), "review": (0, 190, 255)}.get(status, (220, 220, 220))
    text = f"{method.upper()}: " + {"crack": f"CRACK N={len(cracks)}", "no_crack": "NO CRACK",
                                    "review": "REVIEW"}.get(status, status.upper())
    cv2.rectangle(img, (8, 8), (int(30 + 34 * fs * len(text) * 0.55), int(26 + 52 * fs)), (0, 0, 0), -1)
    cv2.putText(img, text, (16, int(16 + 44 * fs)), cv2.FONT_HERSHEY_SIMPLEX, 1.6 * fs, col, 3 * lw, cv2.LINE_AA)
    return img


def imwrite_unicode(path: str, img, params=None):
    ext = os.path.splitext(path)[1]
    ok, buf = cv2.imencode(ext, img, params or [])
    if not ok:
        raise IOError(f"无法写入 {path}")
    buf.tofile(path)


def write_outputs(out_dir: str, records: list, method: str, extra: dict | None = None):
    """写出与 MATLAB run_batch 相同格式的 results.csv 与 defects.json。"""
    os.makedirs(out_dir, exist_ok=True)
    cols = ["file", "status", "status_code", "n_cracks", "review_reason", "notes", "overlay", "mask",
            "width", "height", "finger_angle_deg", "pitch_px", "valid_frac", "bright_frac", "runtime_s", "error"]
    with open(os.path.join(out_dir, "results.csv"), "w", newline="", encoding="utf-8-sig") as f:
        wr = csv.writer(f)
        wr.writerow(cols)
        for r in records:
            wr.writerow([str(r.get(c, "")).replace(",", "；").replace("\n", " ") for c in cols])
    J = {
        "method": method,
        "coordinate_system": "原图像素坐标：左上角像素中心为 (1,1)，x 为列向右，y 为行向下；"
                             "bbox = [x_min, y_min, x_max, y_max]（含两端）；points 为中心线采样点 [x, y]",
        "images": [r["detail"] for r in records],
    }
    if extra:
        J.update(extra)
    with open(os.path.join(out_dir, "defects.json"), "w", encoding="utf-8") as f:
        json.dump(J, f, ensure_ascii=False, indent=1)
