#!/usr/bin/env python3
"""生成"HDMI 已知色 → 期望 TMDS 码"记录模板（供上板对照填写）。

用途：现有参考色条探针只回答"看到的颜色对不对"（主观、无仪器）。本模板把
**期望的 10bit TMDS 码**算出来，让"输入已知色 → 期望码 → 实际观测"三段可追溯。

要点：同一颜色**连续多拍**时码字会因 DC 平衡而交替（见输出里的 run0..run3），
所以"只看几个像素"不足以证明编码正确。

产物：`parallel/evidence/hdmi_known_color_20261015/expected_codes.csv`（可直接填表）
"""

from __future__ import annotations

import csv
import json
import sys
from pathlib import Path

_HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(_HERE))
import tmds_ref as T  # noqa: E402

REPO = _HERE.parents[1]
sys.path.insert(0, str(REPO / "parallel"))
import meta  # noqa: E402

OUT = REPO / "parallel" / "evidence" / "hdmi_known_color_20261015"

RUNS = 4


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    rows = []
    for name, rgb in T.REFERENCE_COLORS:
        # 每个颜色用**全新编码器**（disparity=0 起）编码连续 RUNS 拍：
        #   run0 给出"从零不等性开始"的期望码；run1.. 展示 DC 平衡造成的交替
        enc = T.TmdsEncoder()
        for i in range(RUNS):
            c0, c1, c2, clk = enc.encode(rgb[0], rgb[1], rgb[2], True)
            rows.append({
                "color": name,
                "rgb_hex": "%02X%02X%02X" % rgb,
                "run": i,
                "ch0_exp": T.format_msb(c0, 10),
                "ch1_exp": T.format_msb(c1, 10),
                "ch2_exp": T.format_msb(c2, 10),
                "clk_exp": T.format_msb(clk, 10),
                "observed_color": "",
                "observed_ok": "",
                "notes": "",
            })
    path = OUT / "expected_codes.csv"
    with path.open("w", newline="", encoding="utf-8-sig") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)

    (OUT / "meta.json").write_text(
        json.dumps(meta.evidence_meta(__file__), indent=2, ensure_ascii=False), encoding="utf-8")

    # 第一拍（run=0）的八色表，便于直接放进文档
    first = [r for r in rows if r["run"] == 0]
    (OUT / "reference_colors_first_run.txt").write_text(
        "\n".join("%-8s %s ch0=%s ch1=%s ch2=%s" % (
            r["color"], r["rgb_hex"], r["ch0_exp"], r["ch1_exp"], r["ch2_exp"]) for r in first) + "\n",
        encoding="utf-8")

    # 自证：码字与"历史"的关系必须成立，否则模板会误导人
    e1 = T.TmdsEncoder(); white_fresh = e1.encode(0xFF, 0xFF, 0xFF, True)[0]
    red_fresh = T.TmdsEncoder().encode(0xFF, 0x00, 0x00, True)[0]
    e2 = T.TmdsEncoder(); white_seq = e2.encode(0xFF, 0xFF, 0xFF, True)[0]
    red_seq = e2.encode(0xFF, 0x00, 0x00, True)[0]
    checks = [
        ("white_first_symbol_history_independent", white_fresh == white_seq),
        ("red_after_white_differs", red_fresh != red_seq),
        ("red_fresh_equals_template_run0",
         red_fresh == next(int(r["ch0_exp"], 2) for r in rows if r["color"] == "red" and r["run"] == 0)),
        ("all_codes_10bit", all(0 <= int(r["ch0_exp"], 2) < 1024 for r in rows)),
    ]
    ok = all(c[1] for c in checks)
    for n, o in checks:
        if not o:
            print("HDMI_KNOWN_COLOR_CHECK_FAIL", n)
    print("HDMI_KNOWN_COLOR_DIR", OUT)
    print("HDMI_KNOWN_COLOR rows=%d colors=%d runs=%d" % (len(rows), len(T.REFERENCE_COLORS), RUNS))
    print("HDMI_KNOWN_COLOR", "PASS" if ok else "FAIL")
    if not ok:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
