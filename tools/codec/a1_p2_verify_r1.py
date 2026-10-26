#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""P2 independent verifier: DUT stream -> zlib and strict parser -> Bayer inverse.

The DUT output is judged by:
  1. Python zlib (third-party standard decoder), requiring eof and no trailing;
  2. tools/codec/a1_inflate_strict.py (independent self-written parser);
  3. byte equality of both decoded outputs with the case xform;
  4. for P1 frames, a1_ref.inverse_frame + byte equality with the raw frame.
It also runs negative cases on the DUT stream (truncation, bad Adler, bad
stored NLEN, dynamic BTYPE, trailing bytes), checks abort/reset runs publish no
complete stream, and converts TB cycle counts into MB/s at 187.5 MHz.

Writes result.json / result.md / CANDIDATE-MANIFEST.json.  Test-only.
"""
import binascii
import hashlib
import json
import os
import sys
import zlib

sys.dont_write_bytecode = True

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))
UP = os.path.join(PROJECT, "upstream", "ph1p100-pcie-ep-fpga")
RUN = os.path.join(PROJECT, "workflow", "runs", "20261020-0209_singleA_aplus_closedloop",
                   "T10.a1-eng-freeze", "r1", "p2")
CASES = os.path.join(RUN, "cases")
sys.path.insert(0, HERE)
import a1_inflate_strict as strict  # noqa: E402
import a1_ref  # noqa: E402

CLK_HZ = 187_500_000


def sha256_file(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def read_hex_bytes(p):
    out = bytearray()
    with open(p, "r", encoding="ascii") as f:
        for ln, line in enumerate(f, 1):
            s = line.strip()
            if not s:
                continue
            if len(s) != 2 or any(c not in "0123456789abcdefABCDEF" for c in s):
                raise ValueError("non-byte token at %s:%d (%r)" % (p, ln, s))
            out.append(int(s, 16))
    return bytes(out)


def read_stats(p):
    st = {}
    for line in open(p, "r", encoding="ascii", errors="replace"):
        parts = line.split()
        if len(parts) == 2:
            try:
                st[parts[0]] = int(parts[1], 0)
            except ValueError:
                st[parts[0]] = parts[1]
    return st


def zlib_decode(stream):
    try:
        d = zlib.decompressobj(15)
        out = d.decompress(stream)
        out += d.flush()
        ok = bool(d.eof) and d.unused_data == b"" and d.unconsumed_tail == b""
        return ok, out, ""
    except Exception as e:  # noqa: BLE001
        return False, b"", "%s: %s" % (type(e).__name__, e)


def decode_case(name, stream, expected):
    """Return dict with both decoder results and mismatch counts."""
    zok, zout, zerr = zlib_decode(stream)
    smsg = ""
    sout = b""
    try:
        sout, sstats = strict.inflate(stream, expected_len=len(expected))
    except strict.A1Error as e:
        smsg = e.code
        sstats = {}
    s_ok = smsg == ""
    mism = 0
    if zok:
        mism = sum(1 for a, b in zip(zout, expected) if a != b) + abs(len(zout) - len(expected))
    return {
        "zlib_ok": zok, "zlib_err": zerr,
        "strict_ok": s_ok, "strict_err": smsg,
        "strict_stats": sstats,
        "zlib_mismatch": mism,
        "mismatch": 0 if (s_ok and zok and zout == expected == sout) else max(mism, 1),
    }


def negative_tests(case_name, stream, stats):
    res = []

    def expect(label, data, wanted, want_zlib_fail=True):
        zok, _, zerr = zlib_decode(data)
        try:
            strict.inflate(data)
            code = ""
        except strict.A1Error as e:
            code = e.code
        passed = (code == wanted) and (zok is (not want_zlib_fail))
        res.append({"name": label, "expect": wanted, "strict_reason": code,
                    "zlib_ok": zok, "zlib_err": zerr, "pass": bool(passed)})

    if len(stream) > 10:
        for cut in (1, 2, 5):
            expect("truncate_%d" % cut, stream[:-cut], "E_TRUNCATED")
    bad = bytearray(stream)
    bad[-1] ^= 0xFF
    expect("bad_adler", bytes(bad), "E_BAD_ADLER")
    expect("trailing_byte", stream + b"\x00", "E_TRAILING_BYTES")
    if len(stream) > 8:
        b2 = bytearray(stream)
        b2[2] = (b2[2] & 0xF9) | 0x04  # BTYPE=10, BFINAL preserved
        expect("dynamic_btype", bytes(b2), "E_BAD_BTYPE_DYNAMIC")
    if stats.get("stat_stored", 0) > 0 and len(stream) > 8:
        b3 = bytearray(stream)
        b3[5] ^= 0xFF  # NLEN low byte of the first stored block
        expect("bad_stored_nlen", bytes(b3), "E_BAD_STORED_NLEN")
    return res


def main():
    idx = json.load(open(os.path.join(CASES, "index.json"), "r", encoding="utf-8"))
    cases = idx["cases"]
    results = []
    tok_fixed = 0
    tok_stored = 0
    tok_matches = 0
    tok_literals = 0

    for c in cases:
        name = c["name"]
        rd = os.path.join(RUN, "runs", name)
        outp = os.path.join(rd, "out.hex")
        statp = os.path.join(rd, "stats.txt")
        rec = {"name": name, "kind": c["kind"], "pass": False, "reasons": []}
        if not (os.path.isfile(outp) and os.path.isfile(statp)):
            rec["reasons"].append("missing run output")
            results.append(rec)
            continue
        try:
            stream = read_hex_bytes(outp)
        except ValueError as e:
            rec["reasons"].append(str(e))
            results.append(rec)
            continue
        st = read_stats(statp)
        expected = open(c["xform"], "rb").read()
        dec = decode_case(name, stream, expected)
        rec.update(dec)
        rec["stream_len"] = len(stream)
        rec["stream_sha256"] = hashlib.sha256(stream).hexdigest()
        rec["stats"] = st

        ok = dec["strict_ok"] and dec["zlib_ok"] and dec["mismatch"] == 0
        if not ok:
            rec["reasons"].append("decoder/mismatch failure")
        if st.get("done") != 1:
            ok = False
            rec["reasons"].append("done != 1")
        if st.get("out_last") != 1:
            ok = False
            rec["reasons"].append("out_last != 1")
        if st.get("in_bytes") != c["total_bytes"]:
            ok = False
            rec["reasons"].append("in_bytes != case bytes")
        if dec["strict_ok"] and dec["strict_stats"].get("blocks") != c["nblocks"]:
            ok = False
            rec["reasons"].append("block count mismatch")
        if dec["strict_ok"]:
            ss = dec["strict_stats"]
            tok_fixed += ss.get("fixed_blocks", 0)
            tok_stored += ss.get("stored_blocks", 0)
            tok_matches += ss.get("matches", 0)
            tok_literals += ss.get("literals", 0)
            if ss.get("blocks") != ss.get("fixed_blocks", 0) + ss.get("stored_blocks", 0):
                ok = False
                rec["reasons"].append("non fixed/stored block")

        # Bayer inverse -> raw, sample-exact (P1 frames only)
        if c["kind"] == "p1_positive" and c.get("raw"):
            try:
                xf = a1_ref.inverse_frame(strict.inflate(stream)[0],
                                          c["w"], c["h"], c["prep_en"], c["pred_en"])
                raw = open(c["raw"], "rb").read()
                mism = sum(1 for a, b in zip(xf, raw) if a != b) + abs(len(xf) - len(raw))
                rec["bayer_inverse_mismatch"] = mism
                rec["raw_sha256"] = hashlib.sha256(raw).hexdigest()
                if mism != 0:
                    ok = False
                    rec["reasons"].append("Bayer inverse raw mismatch=%d" % mism)
            except Exception as e:  # noqa: BLE001
                ok = False
                rec["reasons"].append("Bayer inverse error %s" % e)

        # case-specific expectations
        ss = dec["strict_stats"]
        if c.get("expect_stored") and ss.get("stored_blocks", 0) < 1:
            ok = False
            rec["reasons"].append("expected stored block missing")
        if c.get("expect_matches_min") and ss.get("matches", 0) < c["expect_matches_min"]:
            ok = False
            rec["reasons"].append("expected real matches missing")
        if c.get("expect_max_dist") and st.get("stat_max_dist") != c["expect_max_dist"]:
            ok = False
            rec["reasons"].append("max dist != %s" % c["expect_max_dist"])
        if c.get("expect_max_match") and st.get("stat_max_match") != c["expect_max_match"]:
            ok = False
            rec["reasons"].append("max match != %s" % c["expect_max_match"])
        if c.get("expect_cand_abort") and st.get("stat_cand_aborts", 0) < 1:
            ok = False
            rec["reasons"].append("candidate early-abort not observed")
        if c["kind"] == "synthetic_random" and ss.get("matches", 0) != 0:
            ok = False
            rec["reasons"].append("random block unexpectedly has matches")

        neg = negative_tests(name, stream, st)
        rec["negative"] = neg
        if not all(n["pass"] for n in neg):
            ok = False
            rec["reasons"].append("negative test failure")

        rec["pass"] = bool(ok)
        results.append(rec)

    # backpressure / gap reruns
    extra = []
    for name in ("p2_frame_16x8_bp", "p2_frame_16x8_gapbp"):
        rd = os.path.join(RUN, "runs", name)
        outp = os.path.join(rd, "out.hex")
        statp = os.path.join(rd, "stats.txt")
        base = name.replace("_bp", "").replace("_gapbp", "")
        c = next((x for x in cases if x["name"] == base), None)
        rec = {"name": name, "pass": False, "reasons": []}
        if c is None or not os.path.isfile(outp):
            rec["reasons"].append("missing rerun")
            extra.append(rec)
            continue
        stream = read_hex_bytes(outp)
        st = read_stats(statp)
        expected = open(c["xform"], "rb").read()
        dec = decode_case(name, stream, expected)
        rec.update(dec)
        rec["stats"] = st
        ok = dec["mismatch"] == 0 and dec["strict_ok"] and dec["zlib_ok"]
        if st.get("done") != 1 or st.get("out_last") != 1:
            ok = False
            rec["reasons"].append("backpressure run did not complete cleanly")
        rec["pass"] = bool(ok)
        extra.append(rec)

    # abort / reset: no complete stream may be published
    harmful = []
    for name in ("abort_midblock", "reset_midblock"):
        rd = os.path.join(RUN, "runs", name)
        outp = os.path.join(rd, "out.hex")
        statp = os.path.join(rd, "stats.txt")
        rec = {"name": name, "pass": False, "reasons": []}
        if not os.path.isfile(outp) or not os.path.isfile(statp):
            rec["reasons"].append("missing run")
            harmful.append(rec)
            continue
        stream = read_hex_bytes(outp)
        st = read_stats(statp)
        zok, _, zerr = zlib_decode(stream)
        try:
            strict.inflate(stream)
            code = ""
        except strict.A1Error as e:
            code = e.code
        rec.update({"bytes": len(stream), "zlib_ok": zok, "zlib_err": zerr,
                    "strict_reason": code, "stats": st})
        ok = (st.get("done") == 0 and st.get("out_last") == 0
              and not zok and code != "")
        if not ok:
            rec["reasons"].append("aborted/reset run published a complete stream")
        rec["pass"] = bool(ok)
        harmful.append(rec)

    # throughput (no output backpressure, 187.5 MHz)
    perf = []
    for name in ("p2_perf_1920x64_comp", "p2_perf_1920x64_rand"):
        rec = next((r for r in results if r["name"] == name), None)
        if not rec or "stats" not in rec:
            perf.append({"name": name, "pass": False, "reason": "missing"})
            continue
        st = rec["stats"]
        cyc = st.get("run_cycles", 0)
        nbytes = st.get("in_bytes", 0)
        mbs = (nbytes / cyc * CLK_HZ / 1e6) if cyc else 0.0
        perf.append({
            "name": name, "in_bytes": nbytes, "run_cycles": cyc,
            "cycles_per_byte": (cyc / nbytes) if nbytes else 0,
            "mb_per_s_at_187p5MHz": mbs,
            "gate_77p76": mbs >= 77.76,
            "margin_target_97p2": mbs >= 97.2,
            "frame_1080p_ms_equiv": (2_592_000 / (mbs * 1e6) * 1e3) if mbs else 0,
        })

    all_ok = (all(r["pass"] for r in results) and all(r["pass"] for r in extra)
              and all(r["pass"] for r in harmful)
              and all(p.get("gate_77p76", False) for p in perf)
              and tok_matches > 0 and tok_fixed > 0 and tok_stored > 0)

    out = {
        "task_id": "T10.a1-enc-rtl",
        "verdict": "PASS" if all_ok else "FAIL",
        "marker": "synthetic",
        "decoder_independence": {
            "third_party": "Python zlib %s" % zlib.ZLIB_VERSION,
            "self_written": "tools/codec/a1_inflate_strict.py",
            "shared_core": False,
        },
        "cases": results,
        "backpressure_gap": extra,
        "abort_reset": harmful,
        "throughput": perf,
        "token_totals_decoded": {
            "fixed_blocks": tok_fixed, "stored_blocks": tok_stored,
            "literals": tok_literals, "matches": tok_matches,
        },
        "clock_hz": CLK_HZ,
    }
    with open(os.path.join(RUN, "result.json"), "w", encoding="utf-8") as f:
        json.dump(out, f, indent=1)

    # manifest: every artifact + source, absolute paths and hashes
    files = []
    for base, dirs, fns in os.walk(RUN):
        dirs[:] = [d for d in dirs if not d.startswith("work")]
        for fn in fns:
            if fn in ("CANDIDATE-MANIFEST.json",) or fn.startswith("dbg"):
                continue
            files.append(os.path.join(base, fn))
    for src in (
        os.path.join(UP, "upstream", "ph1p100-pcie-ep-fpga", "rtl", "ep_side", "codec", "a1_deflate_core.v"),
        os.path.join(UP, "upstream", "ph1p100-pcie-ep-fpga", "sim", "tb", "codec", "tb_a1_deflate_core.v"),
        os.path.join(HERE, "a1_p2_gen.py"),
        os.path.join(HERE, "a1_p2_verify.py"),
        os.path.join(HERE, "run_p2.ps1"),
    ):
        if os.path.isfile(src):
            files.append(src)
    files = sorted(set(files))
    man = {"task_id": "T10.a1-enc-rtl", "kind": "unique-candidate",
           "files": [{"path": p, "sha256": sha256_file(p),
                      "bytes": os.path.getsize(p)} for p in files]}
    man["file_count"] = len(files)
    with open(os.path.join(RUN, "CANDIDATE-MANIFEST.json"), "w", encoding="utf-8") as f:
        json.dump(man, f, indent=1)

    lines = ["# T10.a1-enc-rtl / P2 verification", "",
             "鍒ゅ畾: **%s** (synthetic, offline RTL simulation)" % out["verdict"], "",
             "| case | blocks | stream B | zlib | strict | mismatch | pass |",
             "|---|---:|---:|---|---|---:|---|"]
    for r in results:
        lines.append("| %s | %s | %s | %s | %s | %s | %s |" % (
            r["name"], r.get("stats", {}).get("stat_blocks", "?"),
            r.get("stream_len", "?"), r.get("zlib_ok"), r.get("strict_ok"),
            r.get("mismatch"), r["pass"]))
    lines += ["", "## Negative cases", "",
              "| case | expected | got | pass |", "|---|---|---|---|"]
    for r in results:
        for n in r.get("negative", []):
            lines.append("| %s/%s | %s | %s | %s |" % (
                r["name"], n["name"], n["expect"], n["strict_reason"], n["pass"]))
    lines += ["", "## Backpressure / abort / reset", "",
              "| run | result |", "|---|---|"]
    for r in extra + harmful:
        lines.append("| %s | %s |" % (r["name"], "PASS" if r["pass"] else "FAIL"))
    lines += ["", "## Throughput (simulation cycles, out_ready=1, 187.5 MHz)", "",
              "| case | bytes | cycles | cycles/B | MB/s | >=77.76 | >=97.2 |",
              "|---|---:|---:|---:|---:|---|---|"]
    for p in perf:
        lines.append("| %s | %s | %s | %.3f | %.2f | %s | %s |" % (
            p["name"], p.get("in_bytes"), p.get("run_cycles"),
            p.get("cycles_per_byte", 0), p.get("mb_per_s_at_187p5MHz", 0),
            p.get("gate_77p76"), p.get("margin_target_97p2")))
    lines += ["", "token totals (decoded): %s" % json.dumps(out["token_totals_decoded"]),
              "", "Note: all inputs are synthetic; no board, PCIe/RK, Flash or download."]
    with open(os.path.join(RUN, "result.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")

    print(json.dumps({"verdict": out["verdict"], "cases": len(results),
                      "extra": len(extra), "harmful": len(harmful),
                      "throughput": perf, "manifest_files": man["file_count"]}, indent=1))
    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main())

