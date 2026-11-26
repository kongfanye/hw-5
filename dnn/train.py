"""训练裂纹分割 + 决策网络。

    python dnn/train.py --all                       用全部 20 张图训练部署模型 → dnn/models/crack_dnn.weights.h5
    python dnn/train.py --fold 0 --folds 5          交叉验证第 0 折（该折的 4 张图不参与训练）

训练数据：cracked/、uncracked/ 原图 + data/dnn_labels/ 中的半自动像素标签
（tools/make_dnn_labels.m 生成：0 背景、255 裂纹、128 忽略）。

与参考工程的主要区别：
  - 按整张图划分训练 / 测试（交叉验证），同一张图的小块不会同时出现在两边，避免数据泄漏；
  - 小块在训练时随机裁取（每步都不同），而不是预先切成固定的 608×608 块再复制增强；
  - 损失 = 加权 BCE + Dice（分割）+ 0.5 × BCE（决策），忽略区不计损失；
  - 不在测试图上挑选模型（固定训练步数，不做早停），测试结果不受挑选偏差影响。
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import threading
import queue
import time

import cv2
import numpy as np

os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")   # 不显示 TensorFlow 的启动提示
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
from common import TILE, list_images, preprocess, read_gray, relpath_key, resize_label  # noqa: E402


def dataset_files():
    cr = list_images([os.path.join(ROOT, "cracked")], recursive=False)
    un = list_images([os.path.join(ROOT, "uncracked")], recursive=False)
    return cr, un


def fold_split(fold: int, folds: int):
    """第 fold 折的测试图：有隐裂、无隐裂各按文件名顺序取 2 张（共 4 张）。"""
    cr, un = dataset_files()
    test = []
    for lst in (cr, un):
        k = len(lst) // folds
        test += lst[fold * k:(fold + 1) * k]
    train = [p for p in cr + un if p not in test]
    return train, test


def load_item(path: str, cache_dir: str):
    stem = os.path.splitext(os.path.basename(path))[0]
    cp = os.path.join(cache_dir, stem + ".npz")
    if os.path.exists(cp):
        d = np.load(cp)
        return {"x": d["x"], "pos": d["pos"], "ign": d["ign"], "name": stem}
    g = read_gray(path)
    prep = preprocess(g)
    lp = os.path.join(ROOT, "data", "dnn_labels", stem + ".png")
    lab = cv2.imdecode(np.fromfile(lp, np.uint8), cv2.IMREAD_GRAYSCALE)
    if lab is None or lab.shape != g.shape:
        raise IOError(f"缺少或尺寸不符的标签：{lp}（请先在 MATLAB/Octave 中运行 tools/make_dnn_labels）")
    pos, ign = resize_label(lab, prep.x.shape[:2])
    os.makedirs(cache_dir, exist_ok=True)
    np.savez_compressed(cp, x=prep.x.astype(np.float16), pos=pos, ign=ign)
    return {"x": prep.x.astype(np.float16), "pos": pos, "ign": ign, "name": stem}


class Sampler:
    """随机裁取训练小块并做数据增强。约一半样本以裂纹像素为中心（类别均衡）。"""

    def __init__(self, items, rng, p_pos=0.5):
        self.items = items
        self.rng = rng
        self.p_pos = p_pos
        self.pos_items = [i for i, it in enumerate(items) if it["pos"].any()]
        self.pos_idx = {i: np.flatnonzero(items[i]["pos"]) for i in self.pos_items}

    def crop(self, it, cy, cx, size):
        h, w = it["pos"].shape
        y0, x0 = int(cy - size // 2), int(cx - size // 2)
        pad = ((max(0, -y0), max(0, y0 + size - h)), (max(0, -x0), max(0, x0 + size - w)))
        ys, xs = slice(max(0, y0), min(h, y0 + size)), slice(max(0, x0), min(w, x0 + size))
        x = np.pad(it["x"][ys, xs].astype(np.float32), pad + ((0, 0),), mode="reflect")
        pos = np.pad(it["pos"][ys, xs], pad, mode="constant").astype(np.float32)
        wgt = np.pad((~it["ign"][ys, xs]).astype(np.float32), pad, mode="constant")
        return x, pos, wgt

    def sample(self):
        r = self.rng
        if self.pos_items and r.random() < self.p_pos:
            i = self.pos_items[r.integers(len(self.pos_items))]
            it = self.items[i]
            j = self.pos_idx[i][r.integers(len(self.pos_idx[i]))]
            cy, cx = np.unravel_index(j, it["pos"].shape)
            cy += r.integers(-TILE // 3, TILE // 3 + 1)
            cx += r.integers(-TILE // 3, TILE // 3 + 1)
        else:
            it = self.items[r.integers(len(self.items))]
            h, w = it["pos"].shape
            cy, cx = r.integers(0, h), r.integers(0, w)
        big = int(TILE * 1.5)
        x, pos, wgt = self.crop(it, cy, cx, big)
        # ---- 几何增强：小角度旋转 + 尺度抖动（栅距估计误差 ±15%）----
        ang = r.uniform(-12, 12) if r.random() < 0.6 else 0.0
        sc = r.uniform(0.87, 1.15) if r.random() < 0.5 else 1.0
        M = cv2.getRotationMatrix2D((big / 2, big / 2), ang, sc)
        M[:, 2] += (TILE - big) / 2
        x = cv2.warpAffine(x, M, (TILE, TILE), flags=cv2.INTER_LINEAR, borderMode=cv2.BORDER_REFLECT)
        pos = cv2.warpAffine(pos, M, (TILE, TILE), flags=cv2.INTER_LINEAR, borderValue=0) > 0.4
        wgt = cv2.warpAffine(wgt, M, (TILE, TILE), flags=cv2.INTER_NEAREST, borderValue=0)
        # ---- 90° 旋转与翻转：覆盖细栅竖直 / 水平两种情况 ----
        k = int(r.integers(4))
        x, pos, wgt = np.rot90(x, k), np.rot90(pos, k), np.rot90(wgt, k)
        if r.random() < 0.5:
            x, pos, wgt = x[:, ::-1], pos[:, ::-1], wgt[:, ::-1]
        # ---- 亮度增强 ----
        x = np.array(x, np.float32)
        x[..., 0] = np.clip(x[..., 0] * r.uniform(0.75, 1.25) + r.uniform(-0.08, 0.08), 0, 1.2)
        x[..., 1] *= r.uniform(0.85, 1.2)
        x += r.normal(0, r.uniform(0.0, 0.03), x.shape).astype(np.float32)
        pos = np.ascontiguousarray(pos, np.float32)
        wgt = np.ascontiguousarray(wgt, np.float32)
        npos = float((pos * wgt).sum())
        lab = 1.0 if npos >= 15 else 0.0
        cw = 1.0 if (lab == 1.0 or (wgt < 0.5).sum() < 200) else 0.0   # 含大片忽略区且无裂纹的块不参与决策损失
        return x, pos, wgt, lab, cw


def batches(sampler, bs, n, q):
    for _ in range(n):
        S = [sampler.sample() for _ in range(bs)]
        q.put(tuple(np.stack([s[i] for s in S]).astype(np.float32) for i in range(5)))
    q.put(None)


def train(train_files, out_path, steps=1600, bs=8, lr=2e-3, seed=0, log_every=50):
    import tensorflow as tf
    from model import build_model, cls_loss, seg_loss
    tf.keras.utils.set_random_seed(seed)
    cache = os.path.join(HERE, "cache")
    t0 = time.time()
    items = [load_item(p, cache) for p in train_files]
    print(f"载入 {len(items)} 张训练图（{time.time() - t0:.0f}s）：" + ", ".join(it["name"] for it in items), flush=True)
    model = build_model()
    sched = tf.keras.optimizers.schedules.CosineDecay(lr, steps, alpha=0.01)
    opt = tf.keras.optimizers.Adam(sched)

    @tf.function
    def step(x, y, w, yl, cw):
        with tf.GradientTape() as tape:
            seg, cls = model(x, training=True)
            ls, lb, ld = seg_loss(y, w, seg)
            lc = tf.reduce_sum(cw * tf.nn.sigmoid_cross_entropy_with_logits(labels=yl, logits=tf.squeeze(cls, -1))) \
                / (tf.reduce_sum(cw) + 1e-6)
            loss = ls + 0.5 * lc
        g = tape.gradient(loss, model.trainable_variables)
        opt.apply_gradients(zip(g, model.trainable_variables))
        return loss, lb, ld, lc

    q = queue.Queue(maxsize=6)
    th = threading.Thread(target=batches, args=(Sampler(items, np.random.default_rng(seed)), bs, steps, q), daemon=True)
    th.start()
    hist = []
    acc = np.zeros(4)
    t0 = time.time()
    for it in range(1, steps + 1):
        b = q.get()
        vals = step(*[tf.constant(a) for a in b])
        acc += np.array([float(v) for v in vals])
        if it % log_every == 0:
            m = acc / log_every
            acc[:] = 0
            hist.append({"step": it, "loss": m[0], "bce": m[1], "dice": m[2], "cls": m[3]})
            eta = (time.time() - t0) / it * (steps - it)
            print(f"  step {it:5d}/{steps}  loss {m[0]:.4f}  bce {m[1]:.4f}  dice {m[2]:.4f}  cls {m[3]:.4f}  "
                  f"剩余约 {eta / 60:.1f} 分钟", flush=True)
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    model.save_weights(out_path)
    meta = {"train_files": [relpath_key(p) for p in train_files], "steps": steps, "batch": bs, "lr": lr,
            "seed": seed, "tile": TILE, "history": hist, "seconds": round(time.time() - t0, 1)}
    with open(out_path.replace(".weights.h5", ".json"), "w", encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=False, indent=1)
    print(f"已保存 {out_path}（训练 {(time.time() - t0) / 60:.1f} 分钟）", flush=True)
    return model


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--all", action="store_true", help="用全部图像训练部署模型")
    ap.add_argument("--fold", type=int, default=None, help="交叉验证折号（从 0 开始）")
    ap.add_argument("--folds", type=int, default=5)
    ap.add_argument("--steps", type=int, default=1600)
    ap.add_argument("--batch", type=int, default=8)
    ap.add_argument("--lr", type=float, default=2e-3)
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--out", default=None)
    a = ap.parse_args()
    if a.all:
        cr, un = dataset_files()
        files = cr + un
        out = a.out or os.path.join(HERE, "models", "crack_dnn.weights.h5")
    elif a.fold is not None:
        files, test = fold_split(a.fold, a.folds)
        print("本折测试图（不参与训练）：" + ", ".join(relpath_key(p) for p in test), flush=True)
        out = a.out or os.path.join(HERE, "models", "cv", f"fold{a.fold}.weights.h5")
    else:
        ap.error("请指定 --all 或 --fold")
    train(files, out, steps=a.steps, bs=a.batch, lr=a.lr, seed=a.seed)


if __name__ == "__main__":
    main()
