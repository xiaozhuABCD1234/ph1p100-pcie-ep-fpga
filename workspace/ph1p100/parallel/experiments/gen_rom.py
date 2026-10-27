#!/usr/bin/env python3
"""生成闪点受控实验用的 ROM 与期望文件（B3 实现侧）。

链路与位序约定（关键，别搞反）
------------------------------
* Python 模型给出**自然形式**的 TMDS 码：bit9 = 符号 MSB = 线上**先发**的位。
* `hdmi_tx_phy_wrapper` 会把 10bit 字段反转一次，`lane_lvds_10_1`(PH1P) 再反转一次，
  连 OSERDES「bit0 先出」→ 净效果是**线上先发 ROM 字的 bit0**。
* 因此要正确发送自然码，ROM 里必须存**位反转后的字段**：`rom = reverse10(natural)`。
  这样线上先发 rom[0] = natural[9] = TMDS MSB ✓。

产物（`--out DIR`）：
  `<name>_rom.hex`      ROM 内容：每行 40bit = {clk,ch2,ch1,ch0}，各字段已反转
  `<name>_expect_ch0/1/2/clk.hex`  自然形式 10bit 码（TB 的期望，**非** ROM 内容）
  `<name>_meta.json`    长度、约定、跳变密度等

注意：**本脚本不生成位流**；ROM 内容只是让实验可复现的输入。
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

_HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(_HERE.parent / "tmds"))
sys.path.insert(0, str(_HERE.parent / "analysis"))
sys.path.insert(0, str(_HERE.parent / "algorithms"))
import tmds_ref as T  # noqa: E402


def rev10(v: int) -> int:
    r = 0
    for i in range(10):
        r |= ((v >> i) & 1) << (9 - i)
    return r & 0x3FF


def patterns(length: int):
    """实验图样：默认给一个"验证用"的短序列（8 色各 5 拍，按需截断）。

    压力图样（max_toggle / ramp 等）由 `parallel/analysis/sparkle_stress.py` 产出；
    本脚本只负责把它换算成 ROM 的位反转形式。
    """
    short = []
    for name, rgb in T.REFERENCE_COLORS:          # 8 色各若干拍
        short += [(name, rgb)] * 5
    return {"short": short[:length] if 0 < length < len(short) else short}


def build(pixels):
    enc = T.TmdsEncoder()
    words = []
    for _, rgb in pixels:
        c0, c1, c2, clk = enc.encode(rgb[0], rgb[1], rgb[2], True)
        words.append((c0, c1, c2, clk))
    return words


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--name", default="short")
    ap.add_argument("--length", type=int, default=20)
    a = ap.parse_args()

    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    table = patterns(a.length)
    pixels = table.get(a.name, table["short"])
    words = build(pixels)
    n = len(words)

    rom_lines, exp = [], {"ch0": [], "ch1": [], "ch2": [], "clk": []}
    for (c0, c1, c2, clk) in words:
        rom = (rev10(clk) << 30) | (rev10(c2) << 20) | (rev10(c1) << 10) | rev10(c0)
        rom_lines.append("%010X" % rom)
        exp["ch0"].append("%03X" % c0)
        exp["ch1"].append("%03X" % c1)
        exp["ch2"].append("%03X" % c2)
        exp["clk"].append("%03X" % clk)

    (out / ("%s_rom.hex" % a.name)).write_text("\n".join(rom_lines) + "\n", encoding="utf-8")
    for k, vals in exp.items():
        (out / ("%s_expect_%s.hex" % (a.name, k))).write_text("\n".join(vals) + "\n", encoding="utf-8")

    # 校验 1：ROM 字段反转两次必须还原自然码（防止反转写错）
    ok_rev = all(rev10(rev10(w[i])) == w[i] for w in words for i in range(4))
    # 校验 2：ROM 字的 bit0..bit9 必须等于各自字段的"自然码 MSB 先发"
    ok_bus = all((((int(rom_lines[i], 16)) >> 0) & 0x3FF) == rev10(words[i][0]) for i in range(n))
    meta = {
        "name": a.name, "words": n,
        "convention": "rom_field = reverse10(natural); wire sends rom bit0 first == natural bit9 (TMDS MSB)",
        "reverse_roundtrip_ok": ok_rev, "rom_bus_form_ok": ok_bus,
    }
    (out / ("%s_meta.json" % a.name)).write_text(json.dumps(meta, indent=2, ensure_ascii=False), encoding="utf-8")

    ok = ok_rev and ok_bus and n > 0
    print("ROM_GEN_DIR", out, "words=%d" % n)
    print("ROM_GEN", "PASS" if ok else "FAIL")
    if not ok:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
