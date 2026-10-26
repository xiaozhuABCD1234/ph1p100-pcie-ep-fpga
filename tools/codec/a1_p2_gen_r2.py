#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""P2 input-case generator for tb_a1_deflate_core.

Reads the frozen P1 positive xform files (independent of the ref encoder) and
adds synthetic P2 boundary/throughput cases.  Emits, per case:
  <name>.hex   one input byte per line (DUT input, transform-domain)
  <name>.meta  hex words: [nblocks, len0, len1, ...]
  <name>.xform raw expected transform-domain bytes (binary)
plus cases/index.json.

This script only prepares inputs; it does not decode or judge outputs.
"""
import hashlib
import json
import os
import struct
import sys

sys.dont_write_bytecode = True

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))
P1 = os.path.join(ROOT, "workflow", "runs", "20261020-0209_singleA_aplus_closedloop",
                  "T10.a1-format-ref", "p1")
RUN = os.path.join(ROOT, "workflow", "runs", "20261020-0209_singleA_aplus_closedloop",
                   "T10.a1-eng-freeze", "r2", "p2")
CASES = os.path.join(RUN, "cases")


def sha256(b):
    return hashlib.sha256(b).hexdigest()


def write_case(name, data, blocks, meta):
    os.makedirs(CASES, exist_ok=True)
    with open(os.path.join(CASES, name + ".hex"), "w", encoding="ascii") as f:
        for b in data:
            f.write("%02x\n" % b)
    with open(os.path.join(CASES, name + ".meta"), "w", encoding="ascii") as f:
        f.write("%08x\n" % len(blocks))
        for n in blocks:
            f.write("%08x\n" % n)
    with open(os.path.join(CASES, name + ".xform"), "wb") as f:
        f.write(data)
    rec = dict(meta)
    rec.update({
        "name": name,
        "blocks": blocks,
        "nblocks": len(blocks),
        "total_bytes": len(data),
        "sha256": sha256(data),
        "hex": os.path.join(CASES, name + ".hex"),
        "meta": os.path.join(CASES, name + ".meta"),
        "xform": os.path.join(CASES, name + ".xform"),
    })
    return rec


def split_2row(xform, stride, h):
    blocks = []
    y = 0
    while y < h:
        rows = 2 if (y + 1) < h else 1
        n = rows * stride
        blocks.append(n)
        y += 2
    if sum(blocks) != len(xform):
        raise SystemExit("split mismatch %d vs %d" % (sum(blocks), len(xform)))
    return blocks


def lcg_bytes(n, seed):
    x = seed & 0xFFFFFFFF
    out = bytearray(n)
    for i in range(n):
        x = (1103515245 * x + 12345) & 0x7FFFFFFF
        out[i] = (x >> 16) & 0xFF
    return bytes(out)


def main():
    os.makedirs(CASES, exist_ok=True)
    index = []
    vj = json.load(open(os.path.join(P1, "vectors", "vectors.json"), "r", encoding="utf-8"))
    for v in vj.get("positives", []):
        if v.get("kind") != "frame" or "xform" not in v.get("files", {}):
            continue
        xp = os.path.join(P1, "vectors", v["files"]["xform"])
        rawp = os.path.join(P1, "vectors", v["files"]["raw"])
        xform = open(xp, "rb").read()
        if len(xform) > 200000:
            # full 1080p vectors are frame-level (P3); P2 module TB uses the
            # small/mid vectors plus the 1920x64 throughput cases.
            continue
        w, h = int(v["w"]), int(v["h"])
        stride = w * 5 // 4
        if len(xform) != stride * h:
            raise SystemExit("bad xform length for " + v["name"])
        blocks = split_2row(xform, stride, h)
        meta = {
            "kind": "p1_positive",
            "source": xp,
            "raw": rawp,
            "w": w, "h": h,
            "prep_en": int(v["prep_en"]), "pred_en": int(v["pred_en"]),
            "synthetic": True,
            "expected_fixed": int(v.get("fixed_blocks", 0)),
            "expected_stored": int(v.get("stored_blocks", 0)),
            "expected_matches": int(v.get("match_count", 0)),
        }
        index.append(write_case("p1_" + v["name"], xform, blocks, meta))

    # --- P2 synthetic boundary cases (transform-domain bytes, no Bayer) -----
    rnd = lcg_bytes(4800, 0x1A2B3C4D)
    index.append(write_case(
        "p2_random_4800", rnd, [4800],
        {"kind": "synthetic_random", "source": "lcg", "w": 0, "h": 0,
         "prep_en": 0, "pred_en": 0, "synthetic": True,
         "expected_stored": 1, "expect_cand_abort": True,
         "expect_matches": 0}))

    a = bytearray(b"\x55" * 4800)
    a[0:3] = b"\xAA\xBB\xCC"
    a[2048:2048 + 258] = a[0:258]
    index.append(write_case(
        "p2_dist2048_len258", bytes(a), [4800],
        {"kind": "synthetic_boundary", "source": "unique3+run+copy", "w": 0, "h": 0,
         "prep_en": 0, "pred_en": 0, "synthetic": True,
         "expect_max_dist": 2048, "expect_max_match": 258,
         "expect_matches_min": 1}))

    pat = b"AAABAAAC"
    d = (pat * (4800 // len(pat) + 1))[:4800]
    index.append(write_case(
        "p2_len3_dist4", d, [4800],
        {"kind": "synthetic_boundary", "source": "pattern", "w": 0, "h": 0,
         "prep_en": 0, "pred_en": 0, "synthetic": True,
         "expect_matches_min": 1, "expect_min_match": 3}))

    # 8x5 frame, prep=0: two full blocks + one-row tail block
    stride8 = 10
    tailraw = bytes((i * 7 + 3) & 0xFF for i in range(stride8 * 5))
    index.append(write_case(
        "p2_frame_8x5_tail", tailraw, split_2row(tailraw, stride8, 5),
        {"kind": "synthetic_tail", "source": "pattern", "w": 8, "h": 5,
         "prep_en": 0, "pred_en": 0, "synthetic": True,
         "expect_tail_block": True}))

    # 16x8 multi-block compressible
    stride16 = 20
    multi = bytearray()
    for y in range(8):
        for x in range(stride16):
            multi.append((x * 5 + (y // 2) * 13) & 0xFF)
    index.append(write_case(
        "p2_frame_16x8", bytes(multi), split_2row(bytes(multi), stride16, 8),
        {"kind": "synthetic_multiblock", "source": "ramp", "w": 16, "h": 8,
         "prep_en": 0, "pred_en": 0, "synthetic": True,
         "expect_matches_min": 1}))

    # 1920x64 throughput cases (30 blocks of 4800 B = 144000 B)
    stride19 = 2400
    comp = bytearray()
    for y in range(64):
        for x in range(stride19):
            comp.append(((x >> 3) + (y >> 1) * 7) & 0xFF)
    comp = bytes(comp)
    index.append(write_case(
        "p2_perf_1920x64_comp", comp, split_2row(comp, stride19, 64),
        {"kind": "synthetic_perf", "source": "ramp", "w": 1920, "h": 64,
         "prep_en": 0, "pred_en": 0, "synthetic": True,
         "expect_matches_min": 1}))

    rndp = lcg_bytes(stride19 * 64, 0xC0FFEE11)
    index.append(write_case(
        "p2_perf_1920x64_rand", rndp, split_2row(rndp, stride19, 64),
        {"kind": "synthetic_perf", "source": "lcg", "w": 1920, "h": 64,
         "prep_en": 0, "pred_en": 0, "synthetic": True,
         "expect_stored": 30, "expect_cand_abort": True}))

    with open(os.path.join(CASES, "index.json"), "w", encoding="utf-8") as f:
        json.dump({"marker": "synthetic", "cases": index}, f, indent=1)
    print("cases=%d" % len(index))
    for c in index:
        print("%-34s blocks=%3d bytes=%7d" % (c["name"], c["nblocks"], c["total_bytes"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())


