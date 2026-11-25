"""按图像做 K 折交叉验证：每折训练一个网络，只在该折未参与训练的图像上检测，再汇总评估。

    python dnn/cv.py                 # 5 折，每折 1600 步；结果写入 outputs/dnn_cv 与 outputs/fusion_cv
    python dnn/cv.py --final         # 交叉验证后再用全部图像训练部署模型并检测全部图像

每张图只被“没见过它的模型”检测一次，所以 outputs/dnn_cv 的指标反映的是对新图的效果
（仍受限于同一批拍摄条件，见设计报告）。
"""
from __future__ import annotations

import argparse
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
from common import relpath_key, write_outputs  # noqa: E402
from predict import load_model, run  # noqa: E402
from train import dataset_files, fold_split  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--folds", type=int, default=5)
    ap.add_argument("--steps", type=int, default=1600)
    ap.add_argument("--final", action="store_true")
    a = ap.parse_args()
    py = sys.executable
    out_d = os.path.join(ROOT, "outputs", "dnn_cv")
    out_f = os.path.join(ROOT, "outputs", "fusion_cv")
    recs, frecs = [], []
    for k in range(a.folds):
        w = os.path.join(HERE, "models", "cv", f"fold{k}.weights.h5")
        if not os.path.exists(w):
            print(f"==== 训练第 {k} 折 ====", flush=True)
            subprocess.run([py, os.path.join(HERE, "train.py"), "--fold", str(k), "--folds", str(a.folds),
                            "--steps", str(a.steps)], check=True)
        _, test = fold_split(k, a.folds)
        print(f"==== 第 {k} 折检测：" + ", ".join(relpath_key(p) for p in test), flush=True)
        r, fr = run(load_model(w), test, out_d, os.path.join(ROOT, "outputs"), out_f)
        recs += r
        frecs += fr
    order = lambda rr: sorted(rr, key=lambda x: x["file"])
    write_outputs(out_d, order(recs), "dnn", {"protocol": f"{a.folds} 折按图像交叉验证，每张图由未见过它的模型检测"})
    write_outputs(out_f, order(frecs), "fusion", {"protocol": f"{a.folds} 折按图像交叉验证；传统方法结果取自 outputs/"})
    if a.final:
        w = os.path.join(HERE, "models", "crack_dnn.weights.h5")
        if not os.path.exists(w):
            print("==== 用全部图像训练部署模型 ====", flush=True)
            subprocess.run([py, os.path.join(HERE, "train.py"), "--all", "--steps", str(a.steps)], check=True)
        cr, un = dataset_files()
        r, fr = run(load_model(w), cr + un, os.path.join(ROOT, "outputs", "dnn"), os.path.join(ROOT, "outputs"),
                    os.path.join(ROOT, "outputs", "fusion"))
        write_outputs(os.path.join(ROOT, "outputs", "dnn"), r, "dnn",
                      {"note": "部署模型用全部 20 张图训练，这里的结果是训练图上的表现，不能当作对新图的评估"})
        write_outputs(os.path.join(ROOT, "outputs", "fusion"), fr, "fusion",
                      {"note": "部署模型用全部 20 张图训练，这里的结果是训练图上的表现"})
    from evaluate import evaluate
    evaluate(["outputs", "outputs/baseline", "outputs/dnn_cv", "outputs/fusion_cv"])


if __name__ == "__main__":
    main()
