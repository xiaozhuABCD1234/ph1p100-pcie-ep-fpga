#!/usr/bin/env python3
"""P3 comp-like content proxy preparation + byte-level self check.

Reads the frozen 1920x64 comp vector (transform-domain bytes, 32 x 4800 B),
tiles it per 2-ROI-row block (block b -> vector block b mod 32) over the full
1920x1080 frame, inverts the frozen A1 PREP/PRED transform to packed RAW10
pixels, and verifies forward(raw) == tiled vector byte for byte.

Writes:
  sim/caps/comp_raw.hex   518400 lines, 40-bit packed RAW10 group per line
  sim/caps/comp_vec.hex    30720 lines, 40-bit transform-domain group per line
  out/content-proxy.json  hashes/CRCs/lengths + mapping evidence

No project source is modified.  a1_ref.py is the frozen P1 format model.
"""
import hashlib
import json
import pathlib
import sys
import zlib

sys.dont_write_bytecode = True

HERE = pathlib.Path(__file__).resolve().parent
R0 = HERE.parent
RUN = R0.parent
ROOT = pathlib.Path(r"D:/fpga/ph1p100")
COMP = ROOT / "work" / "parallel-sim-20261024-2204" / "codec-throughput" / "comp"
sys.path.insert(0, str(HERE))
import ref_a1_ref as a1ref  # noqa: E402

W, H = 1920, 1080
STRIDE = W * 5 // 4          # 2400 B per row
BLOCK = STRIDE * 2           # 4800 B per 2-row block
NBLK = H // 2                # 540
VB = 32                      # frozen vector blocks


def sha(b):
    return hashlib.sha256(b).hexdigest()


def main():
    hex_text = (COMP / "in.hex").read_bytes()
    vec = bytes(int(x, 16) for x in hex_text.split())
    xform = (COMP / "in.xform").read_bytes()
    meta = (COMP / "in.meta").read_bytes()
    if vec != xform:
        raise SystemExit("in.hex does not decode to in.xform")
    if len(vec) != VB * BLOCK:
        raise SystemExit("vector length %d != %d" % (len(vec), VB * BLOCK))

    tiled = bytearray()
    for b in range(NBLK):
        o = (b % VB) * BLOCK
        tiled += vec[o:o + BLOCK]
    tiled = bytes(tiled)
    if len(tiled) != W * H * 5 // 4:
        raise SystemExit("tiled length mismatch")

    raw = a1ref.inverse_frame(tiled, W, H, 1, 1)
    back = a1ref.transform_frame(raw, W, H, 1, 1)
    mismatch = sum(1 for a, b in zip(back, tiled) if a != b) + abs(len(back) - len(tiled))
    if mismatch:
        raise SystemExit("forward(inverse(vec)) mismatch bytes=%d" % mismatch)

    caps = HERE / "caps"
    caps.mkdir(parents=True, exist_ok=True)
    with open(caps / "comp_raw.hex", "w", encoding="ascii") as f:
        for i in range(0, len(raw), 5):
            g = raw[i:i + 5]
            v = g[0] | (g[1] << 8) | (g[2] << 16) | (g[3] << 24) | (g[4] << 32)
            f.write("%010x\n" % v)
    with open(caps / "comp_vec.hex", "w", encoding="ascii") as f:
        for i in range(0, len(vec), 5):
            g = vec[i:i + 5]
            v = g[0] | (g[1] << 8) | (g[2] << 16) | (g[3] << 24) | (g[4] << 32)
            f.write("%010x\n" % v)

    # cross-band repeat distance vs the frozen core match window (13-bit = 8192 B)
    rep_dist = VB * BLOCK
    out = {
        "created": "2026-10-26",
        "role": "developer",
        "task": "T10.ss-g0-closure",
        "geometry": {"W": W, "H": H, "stride_bytes": STRIDE, "block_bytes": BLOCK,
                     "blocks_frame": NBLK, "vector_blocks": VB,
                     "rows_per_block": 2, "vector_rows": 64},
        "inputs": {
            "in.hex": {"path": str(COMP / "in.hex"), "bytes": len(hex_text),
                       "sha256": sha(hex_text)},
            "in.meta": {"path": str(COMP / "in.meta"), "bytes": len(meta),
                        "sha256": sha(meta)},
            "in.xform": {"path": str(COMP / "in.xform"), "bytes": len(xform),
                         "sha256": sha(xform)},
            "a1_ref_model": str(HERE / "ref_a1_ref.py"),
        },
        "transform": {
            "prep_en": 1, "pred_en": 1,
            "note": "A1 frozen PREP/PRED: per-plane modulo-1024 first difference, "
                    "2-row blocks, plane order row0/even,row0/odd,row1/even,row1/odd",
            "inverse": "a1_ref.inverse_frame(tiled,1920,1080,1,1)",
            "forward_check": "a1_ref.transform_frame(raw) == tiled",
            "mismatch_bytes": mismatch,
        },
        "tiling": {
            "rule": "block b (2 ROI rows) -> vector block b mod 32",
            "repeat_distance_bytes": rep_dist,
            "core_max_match_distance_bytes": 8192,
            "cross_band_repeat_in_match_window": bool(rep_dist <= 8192),
            "note": "identical blocks are 153600 B apart, far beyond the 8192 B "
                    "13-bit distance window; adjacent blocks differ, so tiling adds "
                    "no new in-window cross-band match",
        },
        "outputs": {
            "raw_bytes": len(raw), "raw_sha256": sha(raw),
            "tiled_xform_bytes": len(tiled), "tiled_xform_sha256": sha(tiled),
            "raw_crc32": zlib.crc32(raw) & 0xFFFFFFFF,
            "xform_crc32": zlib.crc32(tiled) & 0xFFFFFFFF,
        },
        "labels": {
            "content": "comp_like_proxy_not_worst",
            "why": "synthetic transform-domain ramp (comp anchor) tiled over 1080p; "
                   "not a natural-image corpus and not a worst-case proof",
        },
    }
    (R0 / "out").mkdir(parents=True, exist_ok=True)
    (R0 / "out" / "content-proxy.json").write_text(json.dumps(out, indent=2) + "\n")
    print(json.dumps(out["outputs"], indent=2))
    print("VEC_MATCH bad=0 checked=%d" % len(tiled))


if __name__ == "__main__":
    main()
