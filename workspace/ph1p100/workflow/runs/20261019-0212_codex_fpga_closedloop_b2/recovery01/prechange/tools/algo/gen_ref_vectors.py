#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""T09.rk-align-algo vectors for the two retained worktree candidate testbenches.

gray_mod.vec      -> tools/algo/tb/tb_rgb8_gray_stream.sv
gauss_frame.vec   -> tools/algo/tb/tb_gray8_gaussian3x3_frame.sv

Expected values come from the independent oracle (tools/algo/oracle_algo.py).
"""

from __future__ import annotations

import argparse
import random
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import oracle_algo as orc  # noqa: E402


def gen_gray_mod(out: Path):
    rng = random.Random(0x20261017)
    lines = []
    # literals first
    for (r, g, b) in [(0, 0, 0), (255, 255, 255), (255, 0, 0), (0, 255, 0),
                      (0, 0, 255), (1, 2, 3), (254, 255, 0)]:
        y = (77 * r + 150 * g + 29 * b + 128) >> 8
        lines.append("V %d %d %d %d %d %d" % (r, g, b, 1, 1, y))
    lines.append("STALL 7")
    for i in range(300):
        r, g, b = (rng.randrange(256) for _ in range(3))
        y = (77 * r + 150 * g + 29 * b + 128) >> 8
        lines.append("V %d %d %d %d %d %d" % (r, g, b, int(i % 31 == 0), int(i % 17 == 16), y))
        if i == 50:
            lines.append("GAP 9")
        if i == 120:
            lines.append("RESET")
        if i == 150:
            lines.append("STALL 23")
        if i == 200:
            lines.append("GAP 3")
        if i == 250:
            lines.append("STALL 11")
    out.write_text("\n".join(lines) + "\n", encoding="ascii")
    return len(lines)


def gen_gauss_frame(out: Path):
    rng = random.Random(0x20261018)
    lines = []

    def frame(w, h, kind, abort_at, image=None):
        if kind == 1:
            lines.append("F %d %d %d %d 0" % (w, h, kind, abort_at))
            return
        img = image if image is not None else [rng.randrange(256) for _ in range(w * h)]
        exp = orc.gaussian(img, w, h)
        lines.append("F %d %d %d %d %d" % (w, h, kind, abort_at, w * h))
        for i in range(w * h):
            lines.append("%d %d" % (img[i], exp[i]))

    frame(8, 3, 0, 0)
    imp = [0] * 25
    imp[2 * 5 + 2] = 255
    frame(5, 5, 0, 0, imp)
    frame(1, 1, 0, 0, [200])
    frame(1, 4, 0, 0, [0, 16, 0, 32])
    frame(4, 1, 0, 0, [0, 16, 0, 32])
    frame(64, 3, 0, 0)
    frame(65, 1, 1, 0)
    frame(0, 3, 1, 0)
    frame(8, 3, 2, 20)
    frame(8, 3, 3, 5)
    frame(8, 3, 0, 0)
    frame(6, 4, 0, 0)
    out.write_text("\n".join(lines) + "\n", encoding="ascii")
    return len(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    args = ap.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    n1 = gen_gray_mod(out / "gray_mod.vec")
    n2 = gen_gauss_frame(out / "gauss_frame.vec")
    print("T09_REF_VECTORS_WRITTEN gray_mod.vec lines=%d gauss_frame.vec lines=%d" % (n1, n2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
