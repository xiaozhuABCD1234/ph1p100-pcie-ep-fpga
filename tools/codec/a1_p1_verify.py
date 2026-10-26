#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""T10 A+ v1 P1 verifier: three-way independent round-trip + negative rejection.

For every frame vector:
  1. strict parser (a1_inflate_strict)  -> xform bytes
  2. Python zlib (standard decoder)     -> xform bytes
  3. record checker (a1_sample_check)   -> strict + inverse + CRCs
Then inverse-transform both xform copies and compare with the original raw
bytes. Mismatch count must be 0.

For every negative vector, the expected stable reason code must be raised.
Stream-level negatives are also fed to zlib: they must fail (or leave
unused_data for the trailing-byte case).

Exit 0 only if all checks pass; prints ROUNDTRIP_PASS mismatch=0.
"""
import argparse
import json
import platform
import sys
import time
import zlib
from pathlib import Path

sys.dont_write_bytecode = True

import a1_ref
import a1_inflate_strict as strict
import a1_sample_check as checker


def zlib_decode_exact(data):
    d = zlib.decompressobj()
    out = d.decompress(data)
    out += d.flush()
    if not d.eof:
        raise ValueError("zlib stream incomplete (eof=False)")
    if d.unused_data:
        raise ValueError("zlib unused_data=%d" % len(d.unused_data))
    if d.unconsumed_tail:
        raise ValueError("zlib unconsumed_tail=%d" % len(d.unconsumed_tail))
    return out


def zlib_outcome(data):
    try:
        d = zlib.decompressobj()
        out = d.decompress(data)
        out += d.flush()
        if not d.eof:
            return "incomplete", None, ""
        if d.unused_data:
            return "unused_data", out, ""
        if d.unconsumed_tail:
            return "unconsumed_tail", out, ""
        return "ok", out, ""
    except zlib.error as e:
        return "error", None, str(e)


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--vectors", required=True)
    ap.add_argument("--report", required=True)
    args = ap.parse_args(argv)
    vdir = Path(args.vectors)
    doc = json.loads((vdir / "vectors.json").read_text(encoding="utf-8"))

    cases = []
    failures = []
    positive_passed = 0
    three_way = 0
    mismatch_count = 0
    t0 = time.time()

    for p in doc["positives"]:
        name = p["name"]
        try:
            if p["kind"] == "frame":
                raw = (vdir / p["files"]["raw"]).read_bytes()
                xform = (vdir / p["files"]["xform"]).read_bytes()
                stream = (vdir / p["files"]["stream"]).read_bytes()
                rec = (vdir / p["files"]["record"]).read_bytes()
                if a1_ref.sha256(raw) != p["sha256"]["raw"]:
                    raise AssertionError("raw sha mismatch")
                if a1_ref.sha256(xform) != p["sha256"]["xform"]:
                    raise AssertionError("xform sha mismatch")
                if a1_ref.sha256(stream) != p["sha256"]["stream"]:
                    raise AssertionError("stream sha mismatch")
                if a1_ref.sha256(rec) != p["sha256"]["record"]:
                    raise AssertionError("record sha mismatch")
                if len(raw) != p["raw_len"] or len(xform) != p["xform_len"] or len(stream) != p["stream_len"]:
                    raise AssertionError("declared length mismatch")
                s_out, s_st = strict.inflate(stream, expected_len=len(xform))
                z_out = zlib_decode_exact(stream)
                info = checker.check_record(rec, p["w"], p["h"])
                raw_direct = a1_ref.inverse_frame(xform, p["w"], p["h"], p["prep_en"], p["pred_en"])
                if s_out != xform:
                    raise AssertionError("strict xform mismatch")
                if z_out != xform:
                    raise AssertionError("zlib xform mismatch")
                if raw_direct != raw:
                    mismatch_count += 1
                    raise AssertionError("inverse(raw) mismatch")
                if info["raw"] != raw:
                    mismatch_count += 1
                    raise AssertionError("record-check raw mismatch")
                if s_st["blocks"] != p["block_count"]:
                    raise AssertionError("block_count strict=%d meta=%d" % (s_st["blocks"], p["block_count"]))
                if s_st["fixed_blocks"] != p["fixed_blocks"] or s_st["stored_blocks"] != p["stored_blocks"]:
                    raise AssertionError("block type counts differ")
                if a1_ref.crc32(raw) != p["raw_crc32"]:
                    raise AssertionError("raw crc mismatch")
                if a1_ref.crc32(xform) != p["xform_crc32"]:
                    raise AssertionError("xform crc mismatch")
                if a1_ref.crc32(stream) != p["stream_crc32"]:
                    raise AssertionError("stream crc mismatch")
                if s_out != z_out or s_out != info["xform"]:
                    raise AssertionError("three-way xform mismatch")
                three_way += 1
                positive_passed += 1
                cases.append({
                    "name": name, "kind": "frame", "ok": True,
                    "w": p["w"], "h": p["h"], "prep_en": p["prep_en"], "pred_en": p["pred_en"],
                    "raw_len": len(raw), "xform_len": len(xform), "stream_len": len(stream),
                    "block_count": s_st["blocks"], "fixed_blocks": s_st["fixed_blocks"],
                    "stored_blocks": s_st["stored_blocks"], "literals": s_st["literals"],
                    "matches": s_st["matches"], "max_match_len": p["max_match_len"],
                    "max_match_dist": p["max_match_dist"], "tail_bit_offset": p["tail_bit_offset"],
                    "ratio_raw_over_stream": p["ratio_raw_over_stream"],
                    "raw_sha256": p["sha256"]["raw"], "stream_sha256": p["sha256"]["stream"],
                    "three_way": True,
                })
                print("POS OK %-38s %dx%d prep=%d pred=%d raw=%d stream=%d blocks=%d fixed=%d stored=%d ratio=%.4f"
                      % (name, p["w"], p["h"], p["prep_en"], p["pred_en"], len(raw), len(stream),
                         s_st["blocks"], s_st["fixed_blocks"], s_st["stored_blocks"],
                         p["ratio_raw_over_stream"]), flush=True)
            else:
                stream = (vdir / p["files"]["stream"]).read_bytes()
                expected = (vdir / p["files"]["out"]).read_bytes()
                if a1_ref.sha256(stream) != p["sha256"]["stream"]:
                    raise AssertionError("stream sha mismatch")
                if a1_ref.sha256(expected) != p["sha256"]["out"]:
                    raise AssertionError("out sha mismatch")
                s_out, s_st = strict.inflate(stream, expected_len=len(expected))
                z_out = zlib_decode_exact(stream)
                if s_out != expected:
                    raise AssertionError("strict boundary output mismatch")
                if z_out != expected:
                    raise AssertionError("zlib boundary output mismatch")
                three_way += 1
                positive_passed += 1
                cases.append({
                    "name": name, "kind": "stream_only", "ok": True,
                    "out_len": len(expected), "stream_len": len(stream),
                    "tail_bit_offset": p["tail_bit_offset"],
                    "literals": s_st["literals"], "matches": s_st["matches"],
                    "three_way": True,
                })
                print("POS OK %-38s stream_only out=%d tail=%d literals=%d matches=%d"
                      % (name, len(expected), p["tail_bit_offset"], s_st["literals"], s_st["matches"]),
                      flush=True)
        except Exception as e:
            positive_fail = {"name": name, "ok": False, "error": "%s: %s" % (type(e).__name__, e)}
            cases.append(positive_fail)
            failures.append(positive_fail)
            print("POS FAIL %-38s %s" % (name, e), flush=True)

    neg_rejected = 0
    for n in doc["negatives"]:
        name = n["name"]
        data = (vdir / n["file"]).read_bytes()
        if a1_ref.sha256(data) != n["sha256"]:
            failures.append({"name": name, "ok": False, "error": "sha mismatch"})
            print("NEG FAIL %-32s sha mismatch" % name, flush=True)
            continue
        actual = None
        ok = False
        zl = "n/a"
        try:
            if n["kind"] == "stream":
                try:
                    strict.inflate(data)
                    actual = "ACCEPTED"
                except strict.A1Error as e:
                    actual = e.code
                zl, _zout, zerr = zlib_outcome(data)
                if n["zlib_expectation"] == "must_fail":
                    zok = zl in ("error", "incomplete")
                elif n["zlib_expectation"] == "unused_data":
                    zok = zl == "unused_data"
                else:
                    zok = True
                ok = (actual == n["expected_reason"]) and zok
            else:
                try:
                    checker.check_record(data, n["w"], n["h"])
                    actual = "ACCEPTED"
                except checker.RecordError as e:
                    actual = e.code
                ok = actual == n["expected_reason"]
        except Exception as e:
            actual = "EXCEPTION_%s" % type(e).__name__
            ok = False
        if ok:
            neg_rejected += 1
        else:
            failures.append({"name": name, "ok": False,
                             "expected": n["expected_reason"], "actual": actual,
                             "zlib": zl})
        cases.append({"name": name, "kind": n["kind"], "ok": ok,
                      "expected_reason": n["expected_reason"], "actual": actual,
                      "zlib": zl, "mutation": n["mutation"]})
        print("NEG %s %-30s expected=%-22s actual=%-22s zlib=%-12s"
              % ("OK  " if ok else "FAIL", name, n["expected_reason"], actual, zl), flush=True)

    elapsed = time.time() - t0
    total_pos = len(doc["positives"])
    total_neg = len(doc["negatives"])
    verdict = "PASS" if (positive_passed == total_pos and neg_rejected == total_neg and not failures) else "FAIL"
    report = {
        "schema": "a1t1-p1-verify-v1",
        "task_id": "T10.a1-format-ref",
        "verdict": verdict,
        "positives": total_pos,
        "positives_passed": positive_passed,
        "mismatch_count": mismatch_count,
        "negatives": total_neg,
        "negatives_rejected": neg_rejected,
        "three_way_equal_vectors": three_way,
        "python": platform.python_version(),
        "zlib_version": zlib.ZLIB_VERSION,
        "elapsed_seconds": round(elapsed, 3),
        "cases": cases,
        "failures": failures,
    }
    Path(args.report).parent.mkdir(parents=True, exist_ok=True)
    Path(args.report).write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    if verdict == "PASS":
        print("ROUNDTRIP_PASS mismatch=0 positives=%d negatives=%d three_way=%d elapsed=%.2fs"
              % (total_pos, total_neg, three_way, elapsed), flush=True)
        return 0
    print("ROUNDTRIP_FAIL positives=%d/%d negatives=%d/%d failures=%d elapsed=%.2fs"
          % (positive_passed, total_pos, neg_rejected, total_neg, len(failures), elapsed), flush=True)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
