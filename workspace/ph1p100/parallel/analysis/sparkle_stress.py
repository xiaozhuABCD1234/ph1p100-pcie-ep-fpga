#!/usr/bin/env python3
"""闪点/物理层压力：用 TMDS 参考模型生成**码级**测试向量。

背景（见 parallel/docs/闪点候选原因排查_2026-10-14.md）：活动彩点与"高对比边缘"相关，
而输出物理层（LVDS33_E 1485Mbps / 串行 742.5MHz）超出本地手册保证范围，
根因未定。要做受控实验，最好能**绕开加密编码核**，直接在线上发送已知 TMDS 码。

本脚本产出：
  * 每个图样的 (ch0,ch1,ch2,clk) 10bit 码序列，打包成 40bit/行 hex（`$readmemh` 可读）；
  * 每条 lane 的跳变密度与串行失衡峰值；
  * JSON 摘要与可读样本。

**注意**：这只是"应发送的码"，不包含任何 RTL/位流。要真做实验，需要把码流装进一个
ROM/计数器并接到 `hdmi_tx_phy_wrapper`（绕过 `hdmi_tx_controller_wrapper`），
这是一个**新位流**，必须另行门禁与板测授权；本文不生成位流。
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

_HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(_HERE.parent / "tmds"))
import tmds_ref as T  # noqa: E402

REPO = _HERE.parents[1]
sys.path.insert(0, str(REPO / "parallel"))
import meta  # noqa: E402

OUT = REPO / "parallel" / "evidence" / "sparkle_stress_20261015"

WIDTH = 1920


def pattern_refbar():
    """项目参考色条：8 色等宽。"""
    rows = []
    per = WIDTH // len(T.REFERENCE_COLORS)
    for name, rgb in T.REFERENCE_COLORS:
        rows += [(name, rgb)] * per
    return rows


def pattern_ramp():
    return [("ramp%d" % v, (v, v, v)) for v in range(256)]


def pattern_extreme_alt():
    out = []
    for i in range(256):
        v = 0xFF if i % 2 else 0x00
        out.append(("ea%d" % i, (v, v, v)))
    return out


def pattern_max_toggle():
    """挑出使单 lane 跳变最多的字节对：0xAA / 0x55 交替。"""
    out = []
    for i in range(256):
        v = 0xAA if i % 2 else 0x55
        out.append(("mt%d" % i, (v, v, v)))
    return out


def pattern_worst_imbalance():
    """让三通道同时偏向同一极性、再整体翻转，尽量加大串行失衡。"""
    out = []
    for i in range(256):
        v = 0x00 if (i // 32) % 2 == 0 else 0xFF
        out.append(("wi%d" % i, (v, v, v)))
    return out


PATTERNS = {
    "refbar": pattern_refbar,
    "ramp": pattern_ramp,
    "extreme_alt": pattern_extreme_alt,
    "max_toggle": pattern_max_toggle,
    "worst_imbalance": pattern_worst_imbalance,
}


def encode_pattern(pixels):
    """返回 (codes[list of (c0,c1,c2,clk)], lanes[list of 3 bit-lists])。"""
    enc = T.TmdsEncoder()
    codes = []
    for _, rgb in pixels:
        codes.append(enc.encode(rgb[0], rgb[1], rgb[2], True))
    lanes = [[], [], []]
    for c0, c1, c2, _ in codes:
        lanes[0].extend(enc.serial_bits([c0]))
        lanes[1].extend(enc.serial_bits([c1]))
        lanes[2].extend(enc.serial_bits([c2]))
    return codes, lanes


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    summary = {}
    checks = []
    for name, fn in PATTERNS.items():
        pixels = fn()
        codes, lanes = encode_pattern(pixels)
        # 真实校验 1：每个发出的码必须能反解回源像素（证明码流有效，不是随便写的数）
        rt_ok = all(T.decode_channel(c[0], True)[1] == rgb[0]
                    and T.decode_channel(c[1], True)[1] == rgb[1]
                    and T.decode_channel(c[2], True)[1] == rgb[2]
                    for (_, rgb), c in zip(pixels, codes))
        checks.append(("roundtrip_%s" % name, rt_ok))
        # 真实校验 2：时钟通道固定图样
        checks.append(("clk_%s" % name, all(c[3] == T.CLOCK_PATTERN for c in codes)))
        packed = [((c[3] & 0x3FF) << 30) | ((c[2] & 0x3FF) << 20)
                  | ((c[1] & 0x3FF) << 10) | (c[0] & 0x3FF) for c in codes]
        (OUT / ("%s_codes.hex" % name)).write_text(
            "\n".join("%010X" % v for v in packed) + "\n", encoding="utf-8")
        (OUT / ("%s_codes.txt" % name)).write_text(
            "\n".join("ch0=%s ch1=%s ch2=%s clk=%s" % (
                T.format_msb(c[0], 10), T.format_msb(c[1], 10),
                T.format_msb(c[2], 10), T.format_msb(c[3], 10)) for c in codes[:16]) + "\n",
            encoding="utf-8")
        summary[name] = {
            "pixels": len(pixels),
            "lane_transition_density": [round(T.transition_density(l), 6) for l in lanes],
            "lane_serial_imbalance_peak": [T.serial_imbalance_peak(l) for l in lanes],
            "combined_transition_density": round(T.transition_density(
                [b for l in lanes for b in l]), 6),
        }

    # 真实校验 3：数值域与"图样确实有区别"
    dens = {k: v["combined_transition_density"] for k, v in summary.items()}
    checks.append(("density_in_range", all(0.0 <= d <= 1.0 for d in dens.values())))
    checks.append(("pattern_sensitivity",
                   dens["max_toggle"] > dens["refbar"] + 0.1))
    checks.append(("imbalance_bounded",
                   all(max(v["lane_serial_imbalance_peak"]) <= 32 for v in summary.values())))
    # 真实校验 4：码流文件行数与像素数一致（防止静默截断）
    checks.append(("file_lengths", all(
        len((OUT / ("%s_codes.hex" % k)).read_text(encoding="utf-8").strip().splitlines())
        == v["pixels"] for k, v in summary.items())))

    ok = all(c[1] for c in checks)
    (OUT / "summary.json").write_text(json.dumps(
        {"evidence_meta": meta.evidence_meta(__file__),
         "patterns": summary, "checks": [{"name": n, "ok": bool(o)} for n, o in checks],
         "result": "pass" if ok else "fail"}, indent=2, ensure_ascii=False), encoding="utf-8")
    for k, v in summary.items():
        print("SPARKLE_STRESS", k, "toggle=%.4f" % v["combined_transition_density"],
              "lane_toggle=%s" % v["lane_transition_density"],
              "lane_imbalance=%s" % v["lane_serial_imbalance_peak"])
    for n, o in checks:
        if not o:
            print("SPARKLE_STRESS_CHECK_FAIL", n)
    print("SPARKLE_STRESS_DIR", OUT)
    print("SPARKLE_STRESS", "PASS" if ok else "FAIL")
    if not ok:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
