#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""P3 round1 verifier for T10.a1-frame-top (offline, test-only).

Modes: 0/5 clean, 1-4 abort/reset/proto/stall recovery, 6 multi-frame,
7 abort-with-final-word-pending, 8 illegal geometry (reset-only recovery),
9 pred-without-prep then valid recovery.

Each committed stream is decoded twice (Python zlib + independent strict parser),
compared byte-for-byte with the reference Bayer transform, inverted back to raw,
and checked against the DUT length/CRC fields.  No board, no production path.
"""
import binascii
import hashlib
import json
import sys
import zlib
from pathlib import Path

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import a1_ref as ref            # noqa: E402
import a1_inflate_strict as strict  # noqa: E402

CLK_HZ = 187_500_000.0
GATE_MBS = 77.76
MARGIN_MBS = 97.2


def crc32(b):
    return binascii.crc32(bytes(b)) & 0xFFFFFFFF


def parse_stats(path):
    d = {}
    for line in Path(path).read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.strip()
        if not line:
            continue
        parts = line.split()
        if len(parts) != 2:
            continue
        k, v = parts
        try:
            d[k] = int(v, 16) if (len(v) == 8 and all(c in "0123456789abcdefABCDEF" for c in v)) else int(v)
        except ValueError:
            d[k] = v
    return d


def decode_compare(data, raw, w, h, prep, pred, res, tag):
    """Decode with zlib + strict, compare to the reference transform, invert."""
    xform = ref.transform_frame(raw, w, h, prep, pred)
    ok = True
    zout = None
    sout = None
    try:
        d = zlib.decompressobj()
        zout = d.decompress(data) + d.flush()
        if not d.eof or d.unused_data != b"" or d.unconsumed_tail != b"":
            res.append("%s zlib_not_exact" % tag)
            ok = False
    except Exception as e:
        res.append("%s zlib_error:%s" % (tag, e))
        ok = False
    try:
        sout, sst = strict.inflate(data, expected_len=len(xform))
    except Exception as e:
        res.append("%s strict_error:%s" % (tag, e))
        sst = {}
        ok = False
    if zout is not None and zout != xform:
        res.append("%s zlib_xform_mismatch(%d)" % (tag, len(zout) ^ len(xform)))
        ok = False
    if sout is not None and sout != xform:
        bad = sum(1 for a, b in zip(sout, xform) if a != b) + abs(len(sout) - len(xform))
        res.append("%s strict_xform_mismatch(%d)" % (tag, bad))
        ok = False
    if zout is not None and sout is not None and zout != sout:
        res.append("%s decoders_disagree" % tag)
        ok = False
    if sout is not None:
        if ref.inverse_frame(sout, w, h, prep, pred) != raw:
            res.append("%s raw_mismatch" % tag)
            ok = False
    return {
        "ok": ok, "stream_len": len(data), "raw_len": len(raw),
        "sha256_stream": hashlib.sha256(data).hexdigest(),
        "sha256_xform": hashlib.sha256(xform).hexdigest(),
        "ratio": (len(raw) / len(data)) if data else 0.0,
        "expansion_pct": (len(data) / len(raw) - 1.0) * 100.0 if raw else 0.0,
        "strict_blocks": sst.get("blocks", 0),
        "stored_blocks": sst.get("stored_blocks", 0),
        "fixed_blocks": sst.get("fixed_blocks", 0),
        "literals": sst.get("literals", 0),
        "matches": sst.get("matches", 0),
    }


def check_stream(hex_path, raw, w, h, prep, pred, stats, tag, res):
    txt = Path(hex_path).read_text(encoding="ascii").strip()
    data = bytes.fromhex(txt) if txt else b""
    r = decode_compare(data, raw, w, h, prep, pred, res, tag)
    stride = w * 5 // 4
    nblk = (h + 1) // 2
    checks = [
        ("raw_len", stats.get(tag + "_raw_len"), stride * h),
        ("xform_len", stats.get(tag + "_xform_len"), stride * h),
        ("stream_len", stats.get(tag + "_stream_len"), len(data)),
        ("raw_crc", stats.get(tag + "_raw_crc"), crc32(raw)),
        ("xform_crc", stats.get(tag + "_xform_crc"), crc32(ref.transform_frame(raw, w, h, prep, pred))),
        ("stream_crc", stats.get(tag + "_stream_crc"), crc32(data)),
        ("blocks", stats.get(tag + "_blocks"), nblk),
    ]
    for name, got, want in checks:
        if got != want:
            res.append("%s %s got=%s want=%s" % (tag, name, got, want))
            r["ok"] = False
    return r


def main(argv):
    run = Path(argv[1]).resolve() if len(argv) > 1 else (
        HERE.parents[4] / "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.a1-frame-top/p3")
    idx = json.loads((run / "cases/index.json").read_text(encoding="utf-8"))
    results = []
    failures = []

    for c in idx["cases"]:
        name = c["name"]
        w, h = c["w"], c["h"]
        mode = c["mode"]
        sd = run / "runs" / name
        stats = parse_stats(sd / "stats.txt")
        problems = []
        info = {"name": name, "w": w, "h": h, "mode": mode,
                "prep": c["prep"], "pred": c["pred"]}

        if stats.get("errs", 0) != 0:
            problems.append("tb_errs=%s" % stats.get("errs"))
        for tag in ("p1", "p2", "p3"):
            if stats.get(tag + "_xerr", 0) != 0:
                problems.append("%s_xerr" % tag)
            if stats.get(tag + "_stab_err", 0) != 0:
                problems.append("%s_stab_err" % tag)

        raw = (run / c["raw"]).read_bytes()
        if c["raw_len"] != len(raw):
            problems.append("raw_file_len")
        if hashlib.sha256(raw).hexdigest() != c["raw_sha256"]:
            problems.append("raw_sha256")

        if mode in (0, 5):
            if stats.get("p1_commit", 0) != 1:
                problems.append("p1_no_commit")
            if stats.get("p1_last", 0) != 1:
                problems.append("p1_no_last")
            if stats.get("p1_abort", 0) != 0:
                problems.append("p1_abort")
            r = check_stream(sd / "out.hex", raw, w, h, c["prep"], c["pred"],
                             stats, "p1", problems)
            info["p1"] = r
            nblk = (h + 1) // 2
            info["worst_stored_bytes"] = len(raw) + 5 * nblk + 6
            info["worst_expansion_pct"] = (info["worst_stored_bytes"] / len(raw) - 1.0) * 100.0
            cyc = stats.get("p1_cycles", 0)
            if cyc > 0:
                mbs = len(raw) * CLK_HZ / cyc / 1e6
                info.update({"cycles": cyc, "cycles_per_byte": cyc / len(raw),
                             "mbps_187p5": mbs, "gate_77_76": mbs >= GATE_MBS,
                             "margin_97_2": mbs >= MARGIN_MBS})

        elif mode in (1, 2, 3, 4):
            if stats.get("p1_commit", 0) != 0:
                problems.append("p1_committed")
            if stats.get("p1_last", 0) != 0:
                problems.append("p1_last_set")
            info["p1_partial_words"] = stats.get("p1_outbytes", 0)
            info["p1_abort_seen"] = stats.get("p1_abort", 0)
            if mode in (1, 3, 4) and stats.get("p1_abort", 0) != 1:
                problems.append("p1_abort_not_seen")
            if mode == 4:
                if stats.get("p1_pending_after_abort", 0) != 1:
                    problems.append("p1_no_pending_word")
                if stats.get("p1_commit_after_release", 0) != 0:
                    problems.append("p1_commit_after_release")
                if stats.get("p1_last_after_release", 0) != 0:
                    problems.append("p1_last_after_release")
            raw2 = (run / c["raw2"]).read_bytes()
            if stats.get("p2_commit", 0) != 1:
                problems.append("p2_no_commit")
            if stats.get("p2_last", 0) != 1:
                problems.append("p2_no_last")
            if stats.get("p2_abort", 0) != 0:
                problems.append("p2_abort")
            info["p2"] = check_stream(sd / "out2.hex", raw2, w, h, c["prep2"],
                                      c["pred2"], stats, "p2", problems)

        elif mode == 6:
            n = stats.get("multi_n", 0)
            if n != c.get("nframes", 2):
                problems.append("multi_n")
            data = bytes.fromhex((sd / "out.hex").read_text(encoding="ascii").strip())
            off = 0
            frames = []
            for i in range(1, n + 1):
                if stats.get("m%d_commit" % i, 0) != 1:
                    problems.append("m%d_no_commit" % i)
                if stats.get("m%d_last" % i, 0) != 1:
                    problems.append("m%d_no_last" % i)
                ln = stats.get("m%d_stream_len" % i, 0)
                if ln <= 0 or off + ln > len(data):
                    problems.append("m%d_stream_len" % i)
                    continue
                r = decode_compare(data[off:off + ln], raw, w, h, c["prep"], c["pred"],
                                   problems, "m%d" % i)
                frames.append(r)
                off += ln
            if off != len(data):
                problems.append("multi_trailing_bytes")
            tc = stats.get("multi_total_cycles", 0)
            mb = stats.get("multi_bytes", 0)
            if tc > 0 and mb > 0:
                mbs = mb * CLK_HZ / tc / 1e6
                info.update({"multi_n": n, "multi_total_cycles": tc,
                             "multi_bytes": mb, "cycles_per_byte": tc / mb,
                             "mbps_187p5": mbs, "gate_77_76": mbs >= GATE_MBS,
                             "margin_97_2": mbs >= MARGIN_MBS,
                             "frames": frames})
            else:
                problems.append("multi_cycles")

        elif mode == 7:
            # phase 1 = clean reference stream
            if stats.get("p1_commit", 0) != 1:
                problems.append("p1_no_commit")
            info["p1"] = check_stream(sd / "out.hex", raw, w, h, c["prep"], c["pred"],
                                      stats, "p1", problems)
            # phase 2 = abort while the final word is held
            if stats.get("p2_pending_last", 0) != 1:
                problems.append("p2_no_pending_last")
            if stats.get("p2_abort_lvl", 0) != 1:
                problems.append("p2_no_abort_level")
            if stats.get("p2_last_after_abort", 1) != 0:
                problems.append("p2_out_last_after_abort")
            if stats.get("p2_commit_after_abort", 1) != 0:
                problems.append("p2_commit_after_abort")
            if stats.get("p2_last_after_release", 1) != 0:
                problems.append("p2_out_last_after_release")
            if stats.get("p2_commit_after_release", 1) != 0:
                problems.append("p2_commit_after_release")
            if stats.get("p2_valid_after_release", 1) != 0:
                problems.append("p2_pending_not_consumed")
            raw2 = (run / c["raw2"]).read_bytes()
            if stats.get("p3_commit", 0) != 1:
                problems.append("p3_no_commit")
            if stats.get("p3_last", 0) != 1:
                problems.append("p3_no_last")
            info["p3"] = check_stream(sd / "out2.hex", raw2, w, h, c["prep2"],
                                      c["pred2"], stats, "p3", problems)
            info["abort_last"] = {
                "pending_last": stats.get("p2_pending_last"),
                "last_after_abort": stats.get("p2_last_after_abort"),
                "last_after_release": stats.get("p2_last_after_release"),
                "commit_after_release": stats.get("p2_commit_after_release"),
            }

        elif mode == 8:
            if stats.get("p1_abort_lvl", 0) != 1:
                problems.append("p1_no_abort")
            if stats.get("p1_commit", 1) != 0:
                problems.append("p1_commit")
            if stats.get("p1_busy", 0) != 0:
                problems.append("p1_busy")
            if stats.get("after_rst_abort", 1) != 0:
                problems.append("after_rst_abort")
            if stats.get("p2_abort_lvl", 0) != 1:
                problems.append("p2_no_abort")
            if stats.get("p2_commit", 1) != 0:
                problems.append("p2_commit")
            info["illegal"] = {"p1_abort": stats.get("p1_abort_lvl"),
                               "after_rst_abort": stats.get("after_rst_abort"),
                               "p2_abort": stats.get("p2_abort_lvl")}

        elif mode == 9:
            if stats.get("p1_abort_lvl", 0) != 1:
                problems.append("p1_no_abort")
            if stats.get("p1_commit", 1) != 0:
                problems.append("p1_commit")
            raw2 = (run / c["raw2"]).read_bytes()
            if stats.get("p2_commit", 0) != 1:
                problems.append("p2_no_commit")
            info["p2"] = check_stream(sd / "out2.hex", raw2, w, h, c["prep2"],
                                      c["pred2"], stats, "p2", problems)

        info["problems"] = problems
        info["verdict"] = "PASS" if not problems else "FAIL"
        if problems:
            failures.append({"case": name, "problems": problems})
        results.append(info)

    # backpressure equivalence
    try:
        a = (run / "runs/odd20x5_p1d1/out.hex").read_text(encoding="ascii").strip()
        b = (run / "runs/bp20x5/out.hex").read_text(encoding="ascii").strip()
        same = (a == b)
    except Exception:
        same = False
    if not same:
        failures.append({"case": "bp20x5", "problems": ["bp_stream_differs"]})
        for r in results:
            if r["name"] == "bp20x5":
                r["verdict"] = "FAIL"
                r["problems"].append("bp_stream_differs")

    verdict = "PASS" if not failures else "FAIL"
    out = {
        "verdict": verdict,
        "clock_hz": CLK_HZ,
        "gate_mbs": GATE_MBS,
        "margin_mbs": MARGIN_MBS,
        "cases": results,
        "failures": failures,
        "bp_equivalence": bool(same),
        "note": ("synthetic only; no board; declared RGGB phase-0; throughput is "
                 "content-dependent and is not a guaranteed 97.2 MB/s"),
    }
    (run / "result.json").write_text(json.dumps(out, indent=2), encoding="utf-8")
    print(json.dumps({"verdict": verdict, "failures": failures}, indent=2))
    return 0 if verdict == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
