#!/usr/bin/env python3
"""P1 integrated verification: decode the captured UART bytes and compare with
the independent pattern reference.  Writes result.json next to the run.

Usage:  python verify_p1.py <run_dir>
"""
import json
import os
import sys
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from a1_pattern import expected_raw, expected_xform, GEOM_DEFAULT
from pc_decode import decode_stream, read_bytes, WORST_CASE_EXPANSION

GEOM_SMALL = dict(cam_w=128, cam_h=16, roi_x=0, roi_y=0, w=64, h=8)


def read_stats(path):
    st = {}
    if not os.path.exists(path):
        return st
    with open(path, "r") as f:
        for line in f:
            if not line.startswith("STAT"):
                continue
            for tok in line.split()[1:]:
                k, v = tok.split("=")
                st[k] = int(v)
    return st


def case(name, run_dir, pat, geom, nframes, mode, checks):
    bpath = os.path.join(run_dir, "captures", "%s.dec" % name)
    spath = os.path.join(run_dir, "captures", "%s.stats" % name)
    rec = dict(name=name, mode=mode, pattern=pat, geometry=geom,
               bytes_file=bpath, stats_file=spath)
    if not os.path.exists(bpath):
        rec.update(verdict="FAIL", error="missing capture file")
        return rec
    data = read_bytes(bpath)
    stats = read_stats(spath)
    rec["stats"] = stats
    rec["captured_bytes"] = len(data)
    exp = expected_raw(pat, geom)
    exp_xf = expected_xform(pat, 1, 1, geom)
    rec["expected_raw_len"] = len(exp)
    rec["expected_raw_crc"] = zlib.crc32(exp) & 0xFFFFFFFF
    rec["expected_xform_crc"] = zlib.crc32(exp_xf) & 0xFFFFFFFF
    try:
        frames, tail = decode_stream(data, os.path.join(run_dir, "decoded", name))
    except Exception as exc:
        rec.update(verdict="FAIL", error="decode: %s" % exc)
        return rec
    rec["frames"] = len(frames)
    rec["trailing"] = tail
    rec["frame_info"] = [{k: f[k] for k in
                          ("frame_id", "width", "height", "raw_len", "xform_len",
                           "stream_len", "prep", "pred", "stream_sha256",
                           "raw_sha256", "stream_crc_ok", "header_crc_ok",
                           "xform_crc_ok", "raw_crc_ok", "worstcase_ok")}
                         for f in frames]
    fails = []
    if tail != 0:
        fails.append("trailing_bytes=%d" % tail)
    if len(frames) != nframes:
        fails.append("frame_count=%d expected %d" % (len(frames), nframes))
    for f in frames:
        for k in ("header_crc_ok", "stream_crc_ok", "zlib_ok", "xform_len_ok",
                  "xform_crc_ok", "raw_len_ok", "raw_crc_ok", "worstcase_ok"):
            if not f[k]:
                fails.append("frame %d %s" % (f["frame_id"], k))
        if f["width"] != geom["w"] or f["height"] != geom["h"]:
            fails.append("frame %d geometry %dx%d" % (f["frame_id"], f["width"], f["height"]))
        if f["prep"] != 1 or f["pred"] != 1:
            fails.append("frame %d profile prep=%d pred=%d" % (f["frame_id"], f["prep"], f["pred"]))
        if f["stream_len"] > WORST_CASE_EXPANSION:
            fails.append("frame %d stream_len %d over bound" % (f["frame_id"], f["stream_len"]))
    # per-sample reconstruction check against the independent reference
    for f in frames:
        rawp = os.path.join(f.get("dir", ""), "raw.bin")
        if not os.path.exists(rawp):
            fails.append("frame %d raw.bin missing" % f["frame_id"])
            continue
        got = open(rawp, "rb").read()
        if got != exp:
            n_diff = sum(1 for a, b in zip(got, exp) if a != b) + abs(len(got) - len(exp))
            fails.append("frame %d raw mismatch bytes=%d first=%s" %
                         (f["frame_id"], n_diff,
                          next((i for i, (a, b) in enumerate(zip(got, exp)) if a != b), -1)))
    for key, op, val in checks:
        got = stats.get(key)
        if got is None:
            fails.append("stat %s missing" % key)
        elif op == "==" and got != val:
            fails.append("stat %s=%s expected %s" % (key, got, val))
        elif op == ">" and not (got > val):
            fails.append("stat %s=%s expected >%s" % (key, got, val))
        elif op == ">=" and not (got >= val):
            fails.append("stat %s=%s expected >=%s" % (key, got, val))
    rec["fails"] = fails
    rec["verdict"] = "PASS" if not fails else "FAIL"
    return rec


def main(argv):
    run_dir = argv[1] if len(argv) > 1 else "."
    res = dict(task="T10.b1-a1-uart-integ", run_dir=os.path.abspath(run_dir), cases=[])

    c0 = case("full_grad", run_dir, 0, dict(GEOM_DEFAULT), 1, 0,
              [("cap", ">=", 1), ("enc", ">=", 1), ("exported", "==", 1),
               ("geom", "==", 0), ("err", "==", 0)])
    if c0.get("frame_info"):
        c0["stream_len"] = c0["frame_info"][0]["stream_len"]
    res["cases"].append(c0)

    c1 = case("full_incomp", run_dir, 1, dict(GEOM_DEFAULT), 1, 1,
              [("cap", ">=", 1), ("enc", ">=", 1), ("exported", "==", 1),
               ("geom", "==", 0), ("err", "==", 0)])
    if c1.get("frame_info"):
        c1["stream_len"] = c1["frame_info"][0]["stream_len"]
        # stored-block fallback: exactly raw + 540*5 + 6 at the worst case
        c1["worst_case_exact"] = (c1["stream_len"] == WORST_CASE_EXPANSION)
        if not c1["worst_case_exact"]:
            c1["fails"].append("incompressible stream_len=%d != %d" %
                               (c1["stream_len"], WORST_CASE_EXPANSION))
            c1["verdict"] = "FAIL"
    res["cases"].append(c1)

    # The mid-frame reset in phase C clears the DUT export counter, so only the
    # post-reset export is counted there; both frames are still checked from the
    # captured byte stream (frames == 2 above).
    res["cases"].append(case("fault", run_dir, 0, GEOM_SMALL, 2, 2,
                             [("geom", ">", 0), ("raw_drop", ">", 0),
                              ("exported", ">=", 1), ("err", "==", 0),
                              ("cmp_drop", "==", 0)]))

    res["verdict"] = "PASS" if all(c["verdict"] == "PASS" for c in res["cases"]) else "FAIL"
    with open(os.path.join(run_dir, "result.json"), "w") as f:
        json.dump(res, f, indent=1)
    for c in res["cases"]:
        print("%-12s %s %s" % (c["name"], c["verdict"], c.get("fails", c.get("error", ""))))
        if c.get("frame_info"):
            for fi in c["frame_info"]:
                print("   frame %d %dx%d raw=%d xform=%d stream=%d crc=%s/%s/%s sha=%s"
                      % (fi["frame_id"], fi["width"], fi["height"], fi["raw_len"],
                         fi["xform_len"], fi["stream_len"], fi["stream_crc_ok"],
                         fi["xform_crc_ok"], fi["raw_crc_ok"], fi["raw_sha256"][:16]))
    print("VERDICT", res["verdict"])
    return 0 if res["verdict"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
