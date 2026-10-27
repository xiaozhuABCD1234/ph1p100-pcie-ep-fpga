#!/usr/bin/env python3
"""INT.P1 independent source-pixel verification.

Generates source pixels, packs them as RAW10, unpacks with an independent
oracle, runs the three preprocessing algorithms via image_algorithms_ref.py,
and writes a JSON report + golden samples.  Does not rely on CRC equality.
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ALGO_DIR = ROOT / "parallel" / "algorithms"
sys.path.insert(0, str(ALGO_DIR))
import image_algorithms_ref as ref  # noqa: E402

sys.path.insert(0, str(Path(__file__).resolve().parent))
import raw10_pack as pack  # noqa: E402

OUT = Path(__file__).resolve().parent / "evidence"
OUT.mkdir(parents=True, exist_ok=True)


def make_source(width, height, kind="ramp"):
    return ref.synthetic_raw(width, height, kind)


def main():
    width, height = 16, 12
    phase = 3
    raw = make_source(width, height, "ramp")
    # independent pack -> unpack
    words = pack.samples_to_packed_bytes(raw)
    unpacked = []
    for w in words:
        unpacked.extend(pack.unpack_packed(w))
    pack_ok = (unpacked == raw)

    # three algorithms
    gray = ref.grayscale(raw, width, height, phase, bits=10)
    gauss = ref.gaussian3x3(gray, width, height)
    he_state = ref.HeLut()
    he_state.begin_frame()
    he_out = ref.apply_lut(gray, he_state.lut)  # first frame identity LUT
    he_state.end_frame(gray, valid=True)

    # second frame uses first frame LUT
    raw2 = make_source(width, height, "checker")
    gray2 = ref.grayscale(raw2, width, height, phase, bits=10)
    lut2 = he_state.begin_frame()
    he_out2 = ref.apply_lut(gray2, lut2)

    # golden samples
    golden = {
        "width": width,
        "height": height,
        "phase": phase,
        "source_kind": "ramp",
        "raw_first_16": raw[:16],
        "gray_first_16": gray[:16],
        "gauss_first_16": gauss[:16],
        "he_first_16": he_out[:16],
        "packed_first_4_words": [hex(x) for x in words[:4]],
        "unpack_ok": pack_ok,
        "source_len": len(raw),
    }
    (OUT / "golden_input_processing.json").write_text(
        json.dumps(golden, indent=2), encoding="utf-8")

    # negative check: wrong (direct vector) packing differs
    direct = 0
    for i, v in enumerate(raw[:4]):
        direct |= (v & 0x3FF) << (i * 10)
    wrong_equal = (direct == words[0])

    report = {
        "task_id": "INT.P1",
        "pack_roundtrip_ok": pack_ok,
        "source_len": len(raw),
        "gray_len": len(gray),
        "gauss_len": len(gauss),
        "he_len": len(he_out),
        "he_second_frame_len": len(he_out2),
        "he_published_after_first": he_state.published == 1,
        "wrong_direct_packing_equal_to_packed": wrong_equal,
        "independent_oracle": "unpack_packed != pack bit layout assumptions",
        "negative_control": "direct 4x10 vector != packed word for sample lows",
    }
    (OUT / "verify_report.json").write_text(
        json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report, indent=2))
    ok = (pack_ok and len(gray) == len(raw) and len(gauss) == len(raw)
          and len(he_out) == len(raw) and not wrong_equal)
    print("INT.P1_VERIFY", "PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())