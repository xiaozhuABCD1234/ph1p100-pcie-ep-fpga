#!/usr/bin/env python3
"""独立 DVI/HDMI TMDS 编码参考模型（纯 Python，仅标准库）。

用途
----
为项目的 HDMI 发送链路提供一份**独立于厂商 IP 的黄金参考**：
  * DVI 1.0 的 8b/10b TMDS 编码（数据 + 4 个控制令牌）；
  * 逐通道运行不等性（running disparity / DC balance）状态机；
  * 反解（decode）用于往返自检；
  * 已知输入序列的期望 10bit 码与串行位序；
  * DC 平衡 / 跳变密度统计与最坏情况图样生成（供物理层彩点排查）。

边界（必须与结论一起引用）
--------------------------
* 项目实际编码核 `hdmi_tx_controller_wrapper.enc.v` 是**安路加密黑盒**
  (`pragma protect ... AES128-CBC`)，本模型**没有**、也无法与其逐位对照。
  本模型只提供“标准应得的输出”，不证明该黑盒正确。
* 明文部分 `hdmi_tx_phy_wrapper.v` + `lane_lvds_10_1.v`（PH1P 原生 OSERDES）
  可以对照：约定为 **MSB-first**（bit9 先出）。
* 通道→颜色映射（本模型默认 ch0=R, ch1=G, ch2=B）是**假设**，黑盒未公开，
  引用时必须标注。

算法来源：DVI 1.0 规范；算法结构同时对照 Project F 的 MIT 模型
(projf/display_controller, model/tmds.py) 交叉核对，并用反解往返自检。
"""

from __future__ import annotations

import argparse
import random

# --------------------------------------------------------------------------
# 基本工具
# --------------------------------------------------------------------------

def lsb_bits(value: int, width: int):
    """返回 value 的 width 位，index 0 为最低位（LSB）。"""
    return [(value >> i) & 1 for i in range(width)]


def bits_to_int(bits) -> int:
    """bits[0] 为 LSB，组装为整数。"""
    value = 0
    for i, b in enumerate(bits):
        value |= (b & 1) << i
    return value


def format_msb(value: int, width: int) -> str:
    """按 MSB-first 打印，便于与示波器/串行位序对照。"""
    return format(value, "0{}b".format(width))


# DVI 1.0 控制令牌（c = 2bit 控制码 -> 10bit 码字，MSB-first 书写）
CONTROL_TOKENS = {
    0b00: 0b1101010100,
    0b01: 0b0010101011,
    0b10: 0b0101010100,
    0b11: 0b1010101011,
}
CONTROL_TOKENS_REV = {v: k for k, v in CONTROL_TOKENS.items()}

# TMDS 时钟通道固定图样（MSB-first：5 个 1 后 5 个 0）
CLOCK_PATTERN = 0b1111100000

# 默认通道→分量映射（假设；黑盒未公开）
CHANNEL_MAP_DEFAULT = ("R", "G", "B")


# --------------------------------------------------------------------------
# 单通道编码 / 解码
# --------------------------------------------------------------------------

def encode_channel(d: int, control: int, de: bool, disparity: int):
    """编码一个 TMDS 通道。

    d:         8bit 数据（de=True 时使用）
    control:   2bit 控制码（de=False 时使用）
    de:        data enable
    disparity: 该通道此前的运行不等性
    返回 (q_out:10bit, 新 disparity)
    """
    if not de:
        return CONTROL_TOKENS[control & 0x3], 0

    db = lsb_bits(d, 8)
    n1d = sum(db)
    q_m = [0] * 9
    # 第 1 级：最少跳变（>4 个 1，或 ==4 且 d[0]==0 时用 XNOR）
    if n1d > 4 or (n1d == 4 and db[0] == 0):
        q_m[0] = db[0]
        for i in range(1, 8):
            q_m[i] = 1 ^ (q_m[i - 1] ^ db[i])  # XNOR
        q_m[8] = 0
    else:
        q_m[0] = db[0]
        for i in range(1, 8):
            q_m[i] = q_m[i - 1] ^ db[i]        # XOR
        q_m[8] = 1

    n1q = sum(q_m[0:8])
    n0q = 8 - n1q
    q_out = [0] * 10
    # 第 2 级：不等性控制（DC balance）
    if disparity == 0 or n1q == 4:
        q_out[9] = 1 - q_m[8]
        q_out[8] = q_m[8]
        if q_m[8] == 0:
            q_out[0:8] = [1 - b for b in q_m[0:8]]
            disparity = disparity + n0q - n1q
        else:
            q_out[0:8] = q_m[0:8]
            disparity = disparity + n1q - n0q
    else:
        if (disparity > 0 and n1q > n0q) or (disparity < 0 and n1q < n0q):
            q_out[9] = 1
            q_out[8] = q_m[8]
            q_out[0:8] = [1 - b for b in q_m[0:8]]
            disparity = disparity + 2 * q_m[8] + n0q - n1q
        else:
            q_out[9] = 0
            q_out[8] = q_m[8]
            q_out[0:8] = q_m[0:8]
            disparity = disparity - 2 * (1 - q_m[8]) + n1q - n0q

    return bits_to_int(q_out), disparity


def decode_channel(q_out: int, de: bool = True):
    """反解一个 TMDS 通道。返回 ('data', value) 或 ('control', c) 或 ('invalid', None)。"""
    if not de:
        return ("control", CONTROL_TOKENS_REV.get(q_out)) if q_out in CONTROL_TOKENS_REV else ("invalid", None)
    bits = lsb_bits(q_out, 10)
    inv = bits[9]
    xnor_flag = bits[8]
    p = bits[0:8]
    qmd = [1 - b for b in p] if inv else list(p)
    d = [0] * 8
    d[0] = qmd[0]
    for i in range(1, 8):
        if xnor_flag == 0:
            d[i] = 1 ^ (qmd[i - 1] ^ qmd[i])   # XNOR 路径
        else:
            d[i] = qmd[i - 1] ^ qmd[i]         # XOR 路径
    return ("data", bits_to_int(d))


# --------------------------------------------------------------------------
# 三数据通道 + 时钟通道
# --------------------------------------------------------------------------

class TmdsEncoder:
    """按通道维护运行不等性的 TMDS 三通道编码器（+ 固定时钟图样）。"""

    def __init__(self, channel_map=CHANNEL_MAP_DEFAULT):
        self.channel_map = channel_map
        self.disparity = [0, 0, 0]  # 每数据通道各一份

    def reset(self):
        self.disparity = [0, 0, 0]

    def encode(self, r: int, g: int, b: int, de: bool, ctl: int = 0):
        """编码一个像素/控制拍。

        de=True:  r,g,b 为 8bit 数据，ctl 忽略；返回 (ch0,ch1,ch2,clk)。
        de=False: 输出控制令牌（ctl 2bit），r,g,b 忽略。
        """
        comps = {name: val & 0xFF for name, val in zip("RGB", (r, g, b))}
        ch = []
        for i, name in enumerate(self.channel_map):
            q, disp = encode_channel(comps[name], ctl, de, self.disparity[i])
            self.disparity[i] = disp
            ch.append(q)
        clock = CLOCK_PATTERN if de else CLOCK_PATTERN
        return ch[0], ch[1], ch[2], clock

    def serial_bits(self, codes):
        """把一组 10bit 码按 MSB-first 展开成串行位流。"""
        stream = []
        for code in codes:
            bits = lsb_bits(code, 10)
            stream.extend(bits[9::-1])  # bit9..bit0
        return stream


# --------------------------------------------------------------------------
# 图样与度量
# --------------------------------------------------------------------------

REFERENCE_COLORS = [
    ("white", (0xFF, 0xFF, 0xFF)),
    ("red", (0xFF, 0x00, 0x00)),
    ("green", (0x00, 0xFF, 0x00)),
    ("blue", (0x00, 0x00, 0xFF)),
    ("cyan", (0x00, 0xFF, 0xFF)),
    ("magenta", (0xFF, 0x00, 0xFF)),
    ("yellow", (0xFF, 0xFF, 0x00)),
    ("black", (0x00, 0x00, 0x00)),
]


def grayscale_ramp(steps: int = 8):
    out = []
    for i in range(steps):
        v = 0 if steps == 1 else round(i * 255 / (steps - 1))
        out.append(("gray{}".format(v), (v, v, v)))
    return out


def encode_sequence(pixels, de=True, ctl=0):
    """对 (name, (r,g,b)) 列表编码，返回 [(name, rgb, (ch0,ch1,ch2,clk))]。"""
    enc = TmdsEncoder()
    out = []
    for name, rgb in pixels:
        codes = enc.encode(rgb[0], rgb[1], rgb[2], de, ctl)
        out.append((name, rgb, codes))
    return out


def transition_density(serial_bits):
    """相邻位跳变占比（0..1），用于评估物理层压力。"""
    if len(serial_bits) < 2:
        return 0.0
    toggles = sum(1 for a, b in zip(serial_bits, serial_bits[1:]) if a != b)
    return toggles / (len(serial_bits) - 1)


def serial_imbalance_peak(serial_bits):
    """串行位流上累计 (1 个数 - 0 个数) 的最大绝对值。

    这是**裸串行直流失衡**（与 AC 耦合/基线漂移相关），不是 TMDS 的
    running-disparity 界。TMDS disparity 界在 selftest 里单独检查（<=8）。
    """
    run = 0
    peak = 0
    for b in serial_bits:
        run += 1 if b else -1
        peak = max(peak, abs(run))
    return peak


def stress_pattern(kind: str, count: int = 64):
    """生成高/低跳变压力图样（用于彩点物理层排查）。

    返回 (name, (r,g,b)) 列表。
    """
    out = []
    if kind == "extreme_alt":          # 全黑/全白逐像素交替
        for i in range(count):
            v = 0xFF if i % 2 else 0x00
            out.append(("ea{}".format(i), (v, v, v)))
    elif kind == "checker":            # 每像素按位反转（高跳变密度）
        for i in range(count):
            v = 0xAA if i % 2 else 0x55
            out.append(("ck{}".format(i), (v, v, v)))
    elif kind == "gray_alt":           # 由标准图样表查出的最大跳变对之一
        for i in range(count):
            v = 0xFF if i % 2 else 0x00
            out.append(("ga{}".format(i), (v, v, v)))
    elif kind == "flat":               # 最小跳变：长 0 游程
        for i in range(count):
            out.append(("fl{}".format(i), (0x00, 0x00, 0x00)))
    else:
        raise ValueError("unknown stress kind: {}".format(kind))
    return out


# --------------------------------------------------------------------------
# 自检
# --------------------------------------------------------------------------

def selftest(verbose=True):
    """结构自检：控制令牌、全 256 往返、DC 界、参考色往返。"""
    results = []

    # 1) 控制令牌：与 DVI 1.0 规范**字面表**比较（而不是与自己的字典自比）
    #    字面值来自规范表；仓库内没有规范文件，因此这是"按规范抄写"的核对，
    #    不是独立来源验证（登记为已知边界）。
    SPEC_TOKENS = [0b1101010100, 0b0010101011, 0b0101010100, 0b1010101011]
    results.append(("control_tokens_match_spec_literals",
                    all(encode_channel(0, c, False, 0)[0] == SPEC_TOKENS[c] for c in range(4))))
    # 规范给出的四个令牌是两对**互补**码，且相邻跳变≥7（这正是控制期易于恢复的原因）。
    # 注：早前误设为"每码恰有 5 个 1"，实测 popcount 为 5/5/4/6 —— 是错误的假设，已改正。
    results.append(("control_tokens_pairwise_distinct", len(set(SPEC_TOKENS)) == 4))
    results.append(("control_tokens_complementary_pairs",
                    (SPEC_TOKENS[0] ^ SPEC_TOKENS[1]) == 0x3FF
                    and (SPEC_TOKENS[2] ^ SPEC_TOKENS[3]) == 0x3FF))
    results.append(("control_tokens_transitions_ge7",
                    all(sum(1 for a, b in zip(format(t, "010b"), format(t, "010b")[1:]) if a != b) >= 7
                        for t in SPEC_TOKENS)))
    results.append(("clock_pattern_property_5of10", bin(CLOCK_PATTERN).count("1") == 5))
    results.append(("control_tokens_dict_matches_literals", CONTROL_TOKENS == dict(enumerate(SPEC_TOKENS))))

    # 2) 全 256 数据、多种初始 disparity 往返
    rt_ok = True
    bad = []
    for disp0 in (-4, -3, -2, -1, 0, 1, 2, 3, 4):
        for d in range(256):
            q, _ = encode_channel(d, 0, True, disp0)
            kind, val = decode_channel(q, True)
            if kind != "data" or val != d:
                rt_ok = False
                bad.append((disp0, d, q, kind, val))
    results.append(("roundtrip_256x9disp", rt_ok))

    # 3) DC 平衡界：长随机序列后累计直流有界（标准界 <= 8）
    random.seed(1234)
    enc = TmdsEncoder()
    peak = 0
    for _ in range(20000):
        v = random.randrange(256)
        enc.encode(v, v, v, True)
        peak = max(peak, max(abs(x) for x in enc.disparity))
    results.append(("dc_balance_bound<=8", peak <= 8, peak))

    # 4) 参考色条往返
    seq = encode_sequence(REFERENCE_COLORS)
    color_ok = True
    for name, rgb, (c0, c1, c2, _) in seq:
        # 逐通道映射校验（R->ch0, G->ch1, B->ch2）
        if not (decode_channel(c0, True)[1] == rgb[0]
                and decode_channel(c1, True)[1] == rgb[1]
                and decode_channel(c2, True)[1] == rgb[2]):
            color_ok = False
    results.append(("reference_colors_roundtrip", color_ok))

    if verbose:
        for item in results:
            print("SELFTEST", item)
    return results


def _main():
    ap = argparse.ArgumentParser(description="独立 TMDS 参考模型")
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--colors", action="store_true", help="打印参考色条码字")
    ap.add_argument("--gray", type=int, default=0, help="打印 N 级灰阶码字")
    ap.add_argument("--stress", choices=["extreme_alt", "checker", "gray_alt", "flat"])
    args = ap.parse_args()

    if args.selftest:
        res = selftest()
        print("TMDS_SELFTEST", "PASS" if all(r[1] for r in res) else "FAIL")
    if args.colors or args.gray:
        pixels = REFERENCE_COLORS if args.colors else grayscale_ramp(args.gray)
        for name, rgb, (c0, c1, c2, clk) in encode_sequence(pixels):
            print("{:8} RGB={:02X}{:02X}{:02X} ch0={} ch1={} ch2={} clk={}".format(
                name, rgb[0], rgb[1], rgb[2],
                format_msb(c0, 10), format_msb(c1, 10), format_msb(c2, 10), format_msb(clk, 10)))
    if args.stress:
        pixels = stress_pattern(args.stress)
        enc = TmdsEncoder()
        stream = []
        for _, rgb in pixels:
            codes = enc.encode(rgb[0], rgb[1], rgb[2], True)
            stream.extend(enc.serial_bits(codes[:3]))
        print("STRESS {} density={:.4f} serial_imbalance_peak={}".format(
            args.stress, transition_density(stream), serial_imbalance_peak(stream)))


if __name__ == "__main__":
    _main()
