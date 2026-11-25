"""分割网络 + 决策网络（参考 Tabernik 等 2019 与参考工程的结构，并做了改进）。

参考工程：编码器（5×5 卷积、3 次池化、1024 通道末层）输出 1/8 分辨率掩膜，
再接上采样解码器得到全分辨率掩膜；决策网络把末层特征与掩膜拼接，经卷积和
全局最大 / 平均池化后由全连接层给出“有无缺陷”。

本实现的改动（适应 20 张图的小数据和 CPU 训练）：
  - 输入先缩放到统一栅距（28 px），所以不需要 15×15 大卷积核也能覆盖约 3 个栅距的范围；
  - 编码器 4 级（16/32/64/128 通道，3×3 卷积 + BatchNorm + ReLU），解码器带跳连接（U-Net）；
  - 决策网络同时使用最深层特征与分割概率的全局最大 / 平均池化（与原论文一致）；
  - 两个输出都给 logit，损失在外部计算，便于做“忽略像素”与类别加权。
参数量约 0.53 M，权重文件约 2 MB。
"""
from __future__ import annotations

import tensorflow as tf
from tensorflow import keras
from tensorflow.keras import layers


def conv_block(x, ch, name):
    for i in range(2):
        x = layers.Conv2D(ch, 3, padding="same", use_bias=False, kernel_initializer="he_normal",
                          name=f"{name}_conv{i + 1}")(x)
        x = layers.BatchNormalization(name=f"{name}_bn{i + 1}")(x)
        x = layers.ReLU(name=f"{name}_relu{i + 1}")(x)
    return x


def build_model(in_ch: int = 2, widths=(16, 32, 64, 128)) -> keras.Model:
    inp = keras.Input(shape=(None, None, in_ch), name="image")
    skips = []
    x = inp
    for i, w in enumerate(widths[:-1]):
        x = conv_block(x, w, f"enc{i + 1}")
        skips.append(x)
        x = layers.MaxPooling2D(2, name=f"pool{i + 1}")(x)
    x = conv_block(x, widths[-1], "bottleneck")
    deep = x
    for i, (w, sk) in enumerate(zip(reversed(widths[:-1]), reversed(skips))):
        x = layers.UpSampling2D(2, interpolation="bilinear", name=f"up{i + 1}")(x)
        x = layers.Concatenate(name=f"cat{i + 1}")([x, sk])
        x = conv_block(x, w, f"dec{i + 1}")
    seg = layers.Conv2D(1, 1, name="seg_logit",
                        bias_initializer=keras.initializers.Constant(-2.0))(x)
    # ---- 决策网络 ----
    prob = layers.Activation("sigmoid", name="seg_prob")(seg)
    d = layers.Conv2D(32, 3, padding="same", activation="relu", name="dec_conv")(deep)
    feats = layers.Concatenate(name="dec_feats")([
        layers.GlobalMaxPooling2D(name="gmax_feat")(d),
        layers.GlobalAveragePooling2D(name="gavg_feat")(d),
        layers.GlobalMaxPooling2D(name="gmax_prob")(prob),
        layers.GlobalAveragePooling2D(name="gavg_prob")(prob),
    ])
    cls = layers.Dense(1, name="cls_logit")(feats)
    return keras.Model(inp, [seg, cls], name="crack_seg_dec")


def seg_loss(y, w, logits, dice_weight: float = 1.0, pos_weight: float = 3.0):
    """加权二元交叉熵 + Soft Dice；w = 0 的像素（忽略区）不计损失。

    参考工程只用 BCE，裂纹像素不到 1%，网络容易学成“全判背景”；
    这里给裂纹像素加权并加 Dice 项，直接优化预测与标签的重叠程度。
    """
    logits = tf.squeeze(logits, -1)
    wt = w * (1.0 + (pos_weight - 1.0) * y)
    bce = tf.nn.sigmoid_cross_entropy_with_logits(labels=y, logits=logits)
    l_bce = tf.reduce_sum(bce * wt) / (tf.reduce_sum(wt) + 1e-6)
    p = tf.sigmoid(logits)
    inter = tf.reduce_sum(w * p * y)
    union = tf.reduce_sum(w * p) + tf.reduce_sum(w * y)
    l_dice = 1.0 - (2.0 * inter + 1.0) / (union + 1.0)
    return l_bce + dice_weight * l_dice, l_bce, l_dice


def cls_loss(ylab, logits):
    return tf.reduce_mean(tf.nn.sigmoid_cross_entropy_with_logits(labels=ylab, logits=tf.squeeze(logits, -1)))
