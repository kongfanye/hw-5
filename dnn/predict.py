"""用训练好的网络检测新图像，并可与传统方法（MATLAB 改进法）的结果融合。

    python dnn/predict.py cracked uncracked                       → outputs/dnn/
    python dnn/predict.py D:/新图片 --out outputs/dnn_new
    python dnn/predict.py cracked uncracked --fuse outputs        → 另写 outputs/fusion/（需已有传统方法结果）

输出格式与 MATLAB 的 run_batch 相同（results.csv、defects.json、overlays/、masks/），
因此 evaluate_results.m、crack_app 的“载入已有结果”都能直接读取；另存 prob/ 概率图（工作尺度）。

判定规则：
  有隐裂：分割概率经双阈值（0.6 / 0.35）、骨架化后，存在长度 ≥ 3 个栅距的裂纹段；
  待复核：没有达标的裂纹段，但有长度 ≥ 1.8 个栅距、平均概率 ≥ 0.6 的较短段，
          或决策网络对某一小块给出 ≥ 0.9 的“有裂纹”概率；
  无隐裂：其余情况。
融合（--fuse）：裂纹 = 传统方法裂纹 ∪ 网络裂纹中离传统裂纹超过 1 个栅距、且连续长度 ≥ 1.5 个栅距的
  部分（标为 source = dnn）；任一方法判为有隐裂即为有隐裂。网络补充的裂纹在标注图上用品红色画出。
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time

import cv2
import numpy as np

os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")   # 不显示 TensorFlow 的启动提示
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
from common import (STATUS_NAME, TARGET_PITCH, PostCfg, imwrite_unicode, list_images,  # noqa: E402
                    make_overlay, order_points, postprocess, predict_prob, preprocess, read_gray, relpath_key,
                    write_outputs)

DEFAULT_MODEL = os.environ.get("DNN_MODEL") or os.path.join(HERE, "models", "crack_dnn.weights.h5")


def load_model(path: str):
    from model import build_model
    m = build_model()
    m.load_weights(path)
    return m


def detect(model, path: str, pc: PostCfg = PostCfg()):
    t0 = time.time()
    g = read_gray(path)
    prep = preprocess(g)
    prob, tile_max = predict_prob(model, prep.x)
    cracks, weak, mask, center = postprocess(prob, prep, pc)
    reasons, notes = [], []
    if not prep.pitch_ok:
        notes.append("栅距估计不可靠，按图像尺寸取默认值")
    if cracks:
        code = "crack"
    elif weak:
        code = "review"
        reasons.append(f"有 {weak} 条接近阈值的较短裂纹候选")
    elif tile_max >= 0.9:
        code = "review"
        reasons.append(f"决策网络给出 {tile_max:.2f} 的有裂纹概率，但分割结果不足以确认")
    else:
        code = "no_crack"
    return {"gray": g, "prep": prep, "prob": prob, "tile_max": tile_max, "cracks": cracks,
            "mask": mask, "center": center, "code": code, "reasons": reasons, "notes": notes,
            "runtime": time.time() - t0}


def record(path, r, method, ov_rel, mk_rel, cracks=None, code=None, reasons=None, notes=None, extra_diag=None):
    H, W = r["gray"].shape
    cracks = r["cracks"] if cracks is None else cracks
    code = r["code"] if code is None else code
    reasons = r["reasons"] if reasons is None else reasons
    notes = r["notes"] if notes is None else notes
    diag = {"pitch_px": round(r["prep"].pitch, 2), "pitch_reliable": r["prep"].pitch_ok,
            "work_scale": round(r["prep"].scale, 4), "decision_max_prob": round(r["tile_max"], 3),
            "runtime_s": round(r["runtime"], 1)}
    if extra_diag:
        diag.update(extra_diag)
    detail = {"file": relpath_key(path), "status": STATUS_NAME[code], "status_code": code,
              "image_size": [W, H], "n_cracks": len(cracks), "review_reasons": reasons, "notes": notes,
              "diagnostics": diag, "overlay": ov_rel, "mask": mk_rel, "cracks": cracks, "error": ""}
    return {"file": relpath_key(path), "status": STATUS_NAME[code], "status_code": code,
            "n_cracks": len(cracks), "review_reason": "；".join(reasons), "notes": "；".join(notes),
            "overlay": ov_rel, "mask": mk_rel, "width": W, "height": H, "finger_angle_deg": "",
            "pitch_px": f"{r['prep'].pitch:.2f}", "valid_frac": "", "bright_frac": "",
            "runtime_s": f"{r['runtime']:.1f}", "error": "", "detail": detail}


def load_traditional(trad_dir: str):
    with open(os.path.join(trad_dir, "defects.json"), encoding="utf-8") as f:
        J = json.load(f)
    return {im["file"].lower(): im for im in J["images"]}


def far_pieces(c, far, pitch, min_len=1.5):
    """一条网络裂纹中远离传统裂纹的点（far）按空间邻近分组，返回长度 ≥ min_len 个栅距的各段。

    裂纹的 points 是沿骨架均匀抽取的采样点，每点代表 length_px / 点数 的长度；
    相邻采样点间距不超过 gap 即视为同一段（分叉裂纹也能正确分组）。
    """
    Q = np.asarray(c["points"], float)
    n = len(Q)
    if n == 0 or not far.any():
        return []
    if far.all():
        return [dict(c)]
    share = c["length_px"] / n
    gap = max(0.75 * pitch, 2.5 * share)
    F = Q[far]
    adj = np.hypot(F[:, None, 0] - F[None, :, 0], F[:, None, 1] - F[None, :, 1]) <= gap
    lab = -np.ones(len(F), int)
    k = 0
    for i in range(len(F)):            # 简单的广度优先连通分量
        if lab[i] >= 0:
            continue
        lab[i] = k
        stack = [i]
        while stack:
            j = stack.pop()
            for m in np.flatnonzero(adj[j] & (lab < 0)):
                lab[m] = k
                stack.append(m)
        k += 1
    out = []
    w = c.get("width_px", 4.0)
    for g in range(k):
        P = order_points(F[lab == g, 0], F[lab == g, 1])
        L = len(P) * share
        if L < min_len * pitch:
            continue
        d = np.linalg.eigh(np.cov(P.T))[1][:, -1] if len(P) > 2 else P[-1] - P[0]
        out.append({
            "id": 0, "bbox": [int(np.floor(P[:, 0].min() - w / 2)), int(np.floor(P[:, 1].min() - w / 2)),
                              int(np.ceil(P[:, 0].max() + w / 2)), int(np.ceil(P[:, 1].max() + w / 2))],
            "centroid": [round(float(P[:, 0].mean()), 1), round(float(P[:, 1].mean()), 1)],
            "length_px": round(float(L), 1), "width_px": w,
            "angle_deg": round(float(np.degrees(np.arctan2(d[1], d[0])) % 180), 1),
            "mean_prob": c.get("mean_prob"),
            "endpoints": [[int(P[0, 0]), int(P[0, 1])], [int(P[-1, 0]), int(P[-1, 1])]],
            "points": [[int(p[0]), int(p[1])] for p in P],
        })
    return out


def fuse(path, r, trad_im, trad_dir):
    """传统方法裂纹 ∪ 网络补充的裂纹段（远离传统裂纹 1 个栅距以上、连续长度 ≥ 1.5 个栅距）。"""
    H, W = r["gray"].shape
    tmask = np.zeros((H, W), np.uint8)
    if trad_im and trad_im.get("mask"):
        mp = os.path.join(trad_dir, trad_im["mask"])
        if os.path.exists(mp):
            m = cv2.imdecode(np.fromfile(mp, np.uint8), cv2.IMREAD_GRAYSCALE)
            if m is not None and m.shape == (H, W):
                tmask = (m > 0).astype(np.uint8) * 255
    tcr = list(trad_im.get("cracks", [])) if trad_im else []
    for c in tcr:
        c["source"] = "traditional"
    pitch = float(r["prep"].pitch)
    tol = int(round(pitch))
    near = cv2.dilate(tmask, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * tol + 1, 2 * tol + 1))) > 0
    add = []
    region = np.zeros((H, W), np.uint8)
    for c in r["cracks"]:
        P = np.array(c["points"]) - 1
        P[:, 0] = np.clip(P[:, 0], 0, W - 1)
        P[:, 1] = np.clip(P[:, 1], 0, H - 1)
        for piece in far_pieces(c, ~near[P[:, 1], P[:, 0]], pitch):
            piece["source"] = "dnn"
            add.append(piece)
            rad = int(round(max(0.75 * pitch, 2.5 * c["length_px"] / max(1, len(c["points"])))))
            for x, y in piece["points"]:
                cv2.circle(region, (int(x) - 1, int(y) - 1), rad, 255, -1)
    cracks = tcr + add
    for i, c in enumerate(cracks, 1):
        c["id"] = i
    tcode = trad_im["status_code"] if trad_im else "no_crack"
    codes = {tcode, r["code"]}
    code = "crack" if "crack" in codes else ("review" if "review" in codes else "no_crack")
    reasons = (list(trad_im.get("review_reasons", [])) if trad_im else []) + r["reasons"]
    if code == "crack":
        reasons = []
    notes = [f"传统方法：{STATUS_NAME.get(tcode, tcode)}；网络：{STATUS_NAME[r['code']]}；网络补充 {len(add)} 段"]
    # 网络补充部分的中心线 = 网络中心线中远离传统裂纹、且属于保留段的像素
    add_center = ((r["center"] > 0) & ~near & (region > 0)).astype(np.uint8) * 255
    mask = np.maximum(tmask, (cv2.dilate(add_center, np.ones((5, 5), np.uint8)) > 0).astype(np.uint8) * 255)
    return cracks, code, reasons, notes, mask, tmask, add_center, len(add)


def run(model, files, out_dir, fuse_dir=None, fuse_out=None, pc: PostCfg = PostCfg(), method="dnn"):
    for d in [out_dir] + ([fuse_out] if fuse_out else []):
        for sub in ("overlays", "masks", "prob"):
            os.makedirs(os.path.join(d, sub), exist_ok=True)
    trad = load_traditional(fuse_dir) if fuse_dir else None
    recs, frecs = [], []
    for i, p in enumerate(files, 1):
        stem = os.path.splitext(os.path.basename(p))[0]
        try:
            r = detect(model, p, pc)
        except Exception as e:  # 单张失败不影响其余
            print(f"[{i}/{len(files)}] {relpath_key(p)}  处理失败：{e}", flush=True)
            err = {"file": relpath_key(p), "status": "处理失败", "status_code": "error", "n_cracks": 0,
                   "error": str(e), "detail": {"file": relpath_key(p), "status": "处理失败",
                                                "status_code": "error", "cracks": [], "error": str(e)}}
            recs.append(err)
            if fuse_out:
                frecs.append(err)
            continue
        ov = make_overlay(r["gray"], r["center"], r["cracks"], r["code"], method)
        imwrite_unicode(os.path.join(out_dir, "overlays", stem + ".jpg"), ov, [cv2.IMWRITE_JPEG_QUALITY, 85])
        imwrite_unicode(os.path.join(out_dir, "masks", stem + ".png"), r["mask"])
        imwrite_unicode(os.path.join(out_dir, "prob", stem + ".png"), (r["prob"] * 255).astype(np.uint8))
        recs.append(record(p, r, method, f"overlays/{stem}.jpg", f"masks/{stem}.png"))
        msg = f"[{i}/{len(files)}] {relpath_key(p)}  网络：{STATUS_NAME[r['code']]}  裂纹数={len(r['cracks'])}  " \
              f"栅距={r['prep'].pitch:.1f}px  决策最大概率={r['tile_max']:.2f}  {r['runtime']:.1f}s"
        if fuse_out:
            ti = trad.get(relpath_key(p).lower())
            cracks, code, reasons, notes, mask, tmask, addc, nadd = fuse(p, r, ti, fuse_dir)
            ov = make_overlay(r["gray"], cv2.erode(tmask, np.ones((3, 3), np.uint8)) * 0, cracks, code, "fusion")
            ov[tmask > 0] = (40, 40, 255)
            addl = cv2.dilate(addc, np.ones((5, 5), np.uint8)) > 0
            ov[addl] = (216, 79, 255)
            imwrite_unicode(os.path.join(fuse_out, "overlays", stem + ".jpg"), ov, [cv2.IMWRITE_JPEG_QUALITY, 85])
            imwrite_unicode(os.path.join(fuse_out, "masks", stem + ".png"), mask)
            frecs.append(record(p, r, "fusion", f"overlays/{stem}.jpg", f"masks/{stem}.png", cracks=cracks,
                                code=code, reasons=reasons, notes=notes,
                                extra_diag={"traditional_status": ti["status_code"] if ti else "missing",
                                            "dnn_status": r["code"], "dnn_added_cracks": nadd}))
            msg += f"  | 融合：{STATUS_NAME[code]}（网络补充 {nadd} 段）"
        print(msg, flush=True)
    return recs, frecs


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("inputs", nargs="+", help="图像文件或文件夹（可多个）")
    ap.add_argument("--model", default=DEFAULT_MODEL)
    ap.add_argument("--out", default=os.path.join(ROOT, "outputs", "dnn"))
    ap.add_argument("--fuse", default=None, help="传统方法结果目录（含 defects.json 与 masks/），用于融合")
    ap.add_argument("--fuse-out", default=os.path.join(ROOT, "outputs", "fusion"))
    a = ap.parse_args()
    files = list_images(a.inputs)
    if not files:
        sys.exit("没有找到图像")
    print(f"模型：{a.model}\n图像：{len(files)} 张\n输出：{a.out}", flush=True)
    model = load_model(a.model)
    recs, frecs = run(model, files, a.out, a.fuse, a.fuse_out if a.fuse else None)
    write_outputs(a.out, recs, "dnn", {"model": os.path.relpath(a.model, ROOT)})
    if a.fuse:
        write_outputs(a.fuse_out, frecs, "fusion", {"model": os.path.relpath(a.model, ROOT),
                                                   "traditional": os.path.relpath(a.fuse, ROOT)})
    codes = [r["status_code"] for r in recs]
    print(f"完成：有隐裂 {codes.count('crack')}，无隐裂 {codes.count('no_crack')}，"
          f"待复核 {codes.count('review')}，失败 {codes.count('error')}", flush=True)


if __name__ == "__main__":
    main()
