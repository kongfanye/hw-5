"""按参考标签评估一个或多个结果目录（与 MATLAB evaluate_results.m 的口径一致）。

    python dnn/evaluate.py outputs outputs/baseline outputs/dnn_cv outputs/fusion_cv

图像级：TP / FP / TN / FN、待复核、准确率、查准率、召回率、F1（分母为已判定图像）。
位置级（有隐裂图像）：参考覆盖率 = 参考折线采样点中距预测掩膜 ≤ 容差的比例；
  预测精度 = 预测掩膜像素中距参考折线 ≤ 容差的比例；区域内比例 = 预测像素落在折线容差邻域或参考区域框内的比例。
按点 / 像素汇总后给出合计。结果同时写入 outputs/evaluation/dnn_comparison.md。
"""
from __future__ import annotations

import csv
import json
import os
import sys

import cv2
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)


def load_refs():
    labels = {r["file"].lower(): int(r["label"]) for r in csv.DictReader(open(os.path.join(ROOT, "data", "labels.csv"), encoding="utf-8-sig"))}
    A = json.load(open(os.path.join(ROOT, "data", "annotations.json"), encoding="utf-8"))
    ann = {a["file"].lower(): a for a in A["images"]}
    return labels, ann


def ref_points(a):
    pts = []
    for pl in a.get("polylines", []):
        P = np.array(pl["points"], float)
        for p0, p1 in zip(P[:-1], P[1:]):
            n = max(2, int(np.ceil(np.linalg.norm(p1 - p0) / 2)))
            t = np.linspace(0, 1, n)[:, None]
            pts.append(p0 + t * (p1 - p0))
    return np.round(np.vstack(pts)).astype(int) if pts else np.zeros((0, 2), int)


def loc_metrics(pm, a, tols=(25, 50)):
    H, W = pm.shape
    P = ref_points(a)
    P = P[(P[:, 0] >= 1) & (P[:, 0] <= W) & (P[:, 1] >= 1) & (P[:, 1] <= H)]
    ref = np.zeros((H, W), np.uint8)
    ref[P[:, 1] - 1, P[:, 0] - 1] = 1
    dpred = cv2.distanceTransform((pm == 0).astype(np.uint8), cv2.DIST_L2, 5)
    dref = cv2.distanceTransform((ref == 0).astype(np.uint8), cv2.DIST_L2, 5)
    reg = np.zeros((H, W), bool)
    for b in a.get("regions", []):
        reg[max(0, b[1] - 1):b[3], max(0, b[0] - 1):b[2]] = True
    dp = dpred[P[:, 1] - 1, P[:, 0] - 1]
    pp = pm > 0
    out = {"nref": len(P), "npred": int(pp.sum())}
    for t in tols:
        out[f"cov{t}"] = float((dp <= t).mean()) if len(P) else np.nan
        out[f"prec{t}"] = float((dref[pp] <= t).mean()) if pp.any() else np.nan
    out["inreg"] = float(((dref[pp] <= tols[-1]) | reg[pp]).mean()) if pp.any() else np.nan
    return out


def evaluate(dirs, write=True):
    """返回每个目录的汇总元组；write=False 时只计算，不写 dnn_comparison.md、不打印（供 plot_figures.py 调用）。"""
    labels, ann = load_refs()
    lines = ["# 方法对比（同一套参考标签与位置标注）", ""]
    summary = []
    for d in dirs:
        rows = list(csv.DictReader(open(os.path.join(ROOT, d, "results.csv"), encoding="utf-8-sig")))
        res = {r["file"].lower(): r for r in rows}
        tp = fp = tn = fn = rv = er = 0
        pooled = {"cov25": [0, 0], "cov50": [0, 0], "prec25": [0, 0], "prec50": [0, 0], "inreg": [0, 0]}
        per = []
        for f, y in sorted(labels.items()):
            r = res.get(f)
            code = r["status_code"] if r else "missing"
            if code == "crack":
                tp += y == 1; fp += y == 0
            elif code == "no_crack":
                fn += y == 1; tn += y == 0
            elif code == "review":
                rv += 1
            else:
                er += 1
            if y == 1 and r and code in ("crack", "no_crack", "review") and f in ann:
                mp = os.path.join(ROOT, d, r["mask"])
                m = cv2.imdecode(np.fromfile(mp, np.uint8), cv2.IMREAD_GRAYSCALE) if os.path.exists(mp) else None
                if m is None:
                    continue
                lm = loc_metrics(m, ann[f])
                per.append((f, lm))
                for k in ("cov25", "cov50"):
                    pooled[k][0] += lm[k] * lm["nref"]; pooled[k][1] += lm["nref"]
                for k in ("prec25", "prec50", "inreg"):
                    if lm["npred"]:
                        pooled[k][0] += lm[k] * lm["npred"]; pooled[k][1] += lm["npred"]
        dec = tp + fp + tn + fn
        acc = (tp + tn) / dec if dec else np.nan
        prec = tp / (tp + fp) if tp + fp else np.nan
        rec = tp / (tp + fn) if tp + fn else np.nan
        f1 = 2 * prec * rec / (prec + rec) if prec + rec else np.nan
        P = {k: (v[0] / v[1] if v[1] else np.nan) for k, v in pooled.items()}
        summary.append((d, tp, fp, tn, fn, rv, er, acc, prec, rec, f1, P))
        lines += [f"## `{d}`", "", "| 图像 | 参考覆盖率@25 | 参考覆盖率@50 | 预测精度@50 | 区域内比例@50 |", "|---|---|---|---|---|"]
        for f, lm in per:
            lines.append(f"| {f} | {pct(lm['cov25'])} | {pct(lm['cov50'])} | {pct(lm['prec50'])} | {pct(lm['inreg'])} |")
        lines.append("")
    head = ["## 汇总", "", "| 结果目录 | TP | FP | TN | FN | 待复核 | 准确率 | 查准率 | 召回率 | F1 | 参考覆盖率@25 | 参考覆盖率@50 | 预测精度@50 | 区域内比例@50 |",
            "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
    for d, tp, fp, tn, fn, rv, er, acc, prec, rec, f1, P in summary:
        head.append(f"| `{d}` | {tp} | {fp} | {tn} | {fn} | {rv} | {pct(acc)} | {pct(prec)} | {pct(rec)} | {pct(f1)} | "
                    f"{pct(P['cov25'])} | {pct(P['cov50'])} | {pct(P['prec50'])} | {pct(P['inreg'])} |")
    if not write:
        return summary
    text = "\n".join(lines[:2] + head + [""] + lines[2:])
    os.makedirs(os.path.join(ROOT, "outputs", "evaluation"), exist_ok=True)
    with open(os.path.join(ROOT, "outputs", "evaluation", "dnn_comparison.md"), "w", encoding="utf-8") as fo:
        fo.write(text)
    print("\n".join(head))
    return summary


def pct(x):
    return "—" if x is None or (isinstance(x, float) and np.isnan(x)) else f"{100 * x:.1f}%"


if __name__ == "__main__":
    evaluate(sys.argv[1:] or ["outputs"])
