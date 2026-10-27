#!/usr/bin/env python3
"""生成三算法金参考的共享向量与证据（不访问硬件、不调用 TD、不改 RTL）。

产物（docs/evidence/image_algorithms_20261015/）：
  * <kind>_raw10.hex / _y8.hex / _gauss.hex   —— $readmemh 可直接读的 16bit hex
  * he_lut_after_ramp.hex                     —— 前帧 CDF-min LUT
  * he_frameB.hex                             —— 用前帧 LUT 得到的 HE 输出
  * summary.json                              —— 校验和、首行、语义检查结果
"""

from __future__ import annotations

import datetime
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import image_algorithms_ref as I  # noqa: E402

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "parallel"))
import meta  # noqa: E402
OUT = REPO / "parallel" / "evidence" / "image_algorithms_20261015"
W, H, PHASE = 16, 12, 0


def memh(name: str, values):
    (OUT / name).write_text("\n".join("%04X" % (v & 0xFFFF) for v in values) + "\n", encoding="utf-8")


def txt(name: str, rows, per_row=W):
    lines = []
    for r in range(0, len(rows), per_row):
        lines.append(" ".join("%4d" % v for v in rows[r:r + per_row]))
    (OUT / name).write_text("\n".join(lines) + "\n", encoding="utf-8")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    st = I.selftest(verbose=False)
    selftest_ok = all(x[1] for x in st)

    per_kind = {}
    for kind in ("flat", "ramp", "impulse", "checker", "extreme"):
        raw = I.synthetic_raw(W, H, kind)
        y8 = I.grayscale(raw, W, H, PHASE, 10)
        gau = I.gaussian3x3(y8, W, H)
        memh(kind + "_raw10.hex", raw)
        memh(kind + "_y8.hex", y8)
        memh(kind + "_gauss.hex", gau)
        txt(kind + "_raw10.txt", raw)
        txt(kind + "_y8.txt", y8)
        txt(kind + "_gauss.txt", gau)
        per_kind[kind] = {
            "raw_sum": sum(raw), "y8_sum": sum(y8), "gauss_sum": sum(gau),
            "y8_first_row": y8[:W], "gauss_first_row": gau[:W],
        }

    # HE 两帧序列：A=ramp（首帧用恒等 LUT），B=checker（用 A 的 LUT）
    rawA = I.synthetic_raw(W, H, "ramp")
    rawB = I.synthetic_raw(W, H, "checker")
    y8A = I.grayscale(rawA, W, H, PHASE, 10)
    y8B = I.grayscale(rawB, W, H, PHASE, 10)
    he = I.HeLut()
    lutA_used = he.begin_frame()
    heA = I.apply_lut(y8A, lutA_used)
    he.end_frame(y8A, valid=True)
    lutB_used = he.begin_frame()
    heB = I.apply_lut(y8B, lutB_used)
    memh("he_lut_after_ramp.hex", he.lut)
    memh("he_frameB.hex", heB)
    txt("he_lut_after_ramp.txt", he.lut, per_row=16)
    # 期望的 LUT：用独立路径从 frameA 重新算一次（不引用 he 的内部状态）
    expected_lutA = I.cdf_min_lut(I.banks4_histogram(y8A), len(y8A))
    he_info = {
        "first_frame_used_identity": lutA_used == list(range(256)),
        "frameB_uses_published_lut": lutB_used == expected_lutA and lutB_used != list(range(256)),
        "he_lut_matches_independent_recompute": he.lut == expected_lutA,
        "frameB_output_differs_from_source": heB != y8B,
        "lut_source_seq": he.lut_source_seq,
        "published": he.published, "rejected": he.rejected,
        "lut_first_16": he.lut[:16],
    }

    # 相位敏感性：同一 raw 四个相位应给出**逐像素不同**的 Y8
    # （求和可能因测试图对称而巧合相等，因此按数组比较）
    phase_sums = {}
    phase_arrays = {}
    raw = I.synthetic_raw(W, H, "extreme")   # 高对比，避免线性斜坡被 >>2 抹平
    for ph in range(4):
        y = I.grayscale(raw, W, H, ph, 10)
        phase_sums[I.PHASE_COLORS[ph]] = sum(y)
        phase_arrays[I.PHASE_COLORS[ph]] = tuple(y)
    distinct_phase_arrays = len(set(phase_arrays.values()))

    # 坏帧语义
    he2 = I.HeLut()
    he2.end_frame(y8A, valid=True)
    lut_before = list(he2.lut)
    he2.end_frame(y8B, valid=False)
    bad_frame = {"kept_lut": he2.lut == lut_before, "rejected": he2.rejected == 1,
                 "published": he2.published == 1}

    result = {
        "date": datetime.date.today().isoformat(),
        "evidence_meta": meta.evidence_meta(__file__),
        "kind": "image-algorithms-golden",
        "geometry": {"width": W, "height": H, "phase": I.PHASE_COLORS[PHASE]},
        "selftest": [{"name": n, "ok": bool(ok)} for n, ok, *_ in st],
        "per_kind": per_kind, "he_sequence": he_info, "bad_frame": bad_frame,
        "phase_sensitivity_y8_sum": phase_sums,
        "distinct_phase_arrays": distinct_phase_arrays,
    }
    ok = (selftest_ok and he_info["first_frame_used_identity"]
          and he_info["frameB_uses_published_lut"] and he_info["frameB_output_differs_from_source"]
          and he_info["he_lut_matches_independent_recompute"]
          and bad_frame["kept_lut"] and distinct_phase_arrays == 4)
    result["result"] = "pass" if ok else "fail"
    (OUT / "summary.json").write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding="utf-8")

    print("IMG_ALGO_DIR", OUT)
    print("IMG_ALGO_RUN", "PASS" if ok else "FAIL",
          "kinds=%d he_seq=%s" % (len(per_kind), he_info["lut_source_seq"]))
    if not ok:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
