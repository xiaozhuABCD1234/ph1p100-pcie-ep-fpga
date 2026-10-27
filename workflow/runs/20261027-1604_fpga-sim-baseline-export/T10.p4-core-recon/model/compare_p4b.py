#!/usr/bin/env python3
"""Independent reference model + comparator — T10.p4-core-recon round0 attempt2.

Frame-control contract = r2 `tb_img_algo_equiv_p4.v` (SHA 1350d75c..a639f), ported
unchanged into tb/tb_p4_equiv_golden.v (only a token dump tap was added):
    W=64, H=48, 4 px/beat, 768 beats/frame, frame 0 and 1 good, frame 2 aborted on
    purpose at its beat 200 (s_abort, no eof), LFSR ready patterns (+SEEDMODE=0/1/2,
    where 2 = always ready).

Checks (plan §4.3 as amended 2026-10-27, §4.5):
  * F1/F2 golden: candidate Y8 (Bayer demosaic -> Y8) and Gaussian (3x3 [1 2 1;2 4 2;1 2 1],
    (sum+8)>>4) recomputed from the same synthetic stimulus, compared pixel by pixel in
    EVERY ready mode: compared == W*H*2 and mismatch == 0.
  * F3 abort semantics: no abort marker inside the two good frames; exactly one abort
    marker per stream per run, at the same position as the base reference; the partial
    data of the intentionally aborted frame is a prefix of the reference frame 2.
  * F5(a): base (dut0, r2 frozen bytes) vs candidate (dut1) full token sequence equality
    per mode.  F5(b): no loss/duplication/reorder (token counts == expected) and exact
    pixels.  F5(c): cross-mode difference of the candidate must not exceed the base's.
  * E4: two runs of the same mode produce identical dumps.
  * negative control: a 1-LSB mutation must be caught.

Exit code 0 only when every check passes.
"""

import argparse
import glob
import json
import sys
from pathlib import Path

W, H, NF_GOOD = 64, 48, 2
MPW = W // 4
BEATS = MPW * H                      # 768 beats per frame
EXPECTED_PIXELS = W * H * NF_GOOD    # 6144 per stream
EXPECTED_TOKENS = BEATS * NF_GOOD    # 1536 per stream (frames 0 and 1)
PHASE = 0
KERNEL = ((-1, 1), (0, 2), (1, 1))
DUT_NAME = {0: "base", 1: "candidate"}
STREAM_NAME = {0: "y8", 1: "gau"}


# ----------------------------------------------------------------- reference model
def px(b, k):
    return (37 * b + 211 * k + 13 * (b >> 5) + 5) & 0x3FF


def raw_frame(fr):
    raw = [[0] * W for _ in range(H)]
    for inner in range(BEATS):
        b = fr * BEATS + inner
        y, j = divmod(inner, MPW)
        for k in range(4):
            raw[y][4 * j + k] = px(b, k)
    return raw


def color(x, y):
    tl, tr, bl, br = ((0, 1, 1, 2), (2, 1, 1, 0), (1, 0, 2, 1), (1, 2, 0, 1))[PHASE]
    if y & 1:
        return br if x & 1 else bl
    return tr if x & 1 else tl


def y8_frame(fr):
    raw = raw_frame(fr)
    out = [[0] * W for _ in range(H)]
    for y in range(H):
        ym1 = 1 if y == 0 else y - 1
        yp1 = H - 2 if y == H - 1 else y + 1
        r0, r1, r2 = raw[ym1], raw[y], raw[yp1]
        for x in range(W):
            xm1 = 1 if x == 0 else x - 1
            xp1 = W - 2 if x == W - 1 else x + 1
            own = r1[x]
            hl, hr = r1[xm1], r1[xp1]
            vu, vd = r0[x], r2[x]
            dul, dur = r0[xm1], r0[xp1]
            ddl, ddr = r2[xm1], r2[xp1]
            a2h = (hl + hr + 1) >> 1
            a2v = (vu + vd + 1) >> 1
            a4o = (hl + hr + vu + vd + 2) >> 2
            a4d = (dul + dur + ddl + ddr + 2) >> 2
            c = color(x, y)
            hc = color(x ^ 1, y)
            if c == 1:
                r, g, b = (a2h, own, a2v) if hc == 0 else (a2v, own, a2h)
            elif c == 0:
                r, g, b = own, a4o, a4d
            else:
                r, g, b = a4d, a4o, own
            r8, g8, b8 = (r >> 2) & 0xFF, (g >> 2) & 0xFF, (b >> 2) & 0xFF
            out[y][x] = ((77 * r8 + 150 * g8 + 29 * b8 + 128) >> 8) & 0xFF
    return out


def gau_frame(y8):
    out = [[0] * W for _ in range(H)]
    for y in range(H):
        for x in range(W):
            s = 0
            for dy, wy in KERNEL:
                yy = min(max(y + dy, 0), H - 1)
                for dx, wx in KERNEL:
                    xx = min(max(x + dx, 0), W - 1)
                    s += wy * wx * y8[yy][xx]
            out[y][x] = (s + 8) >> 4
    return out


def expected_stream(plane, frames):
    """(kind, data, sof, eol, eof) token list for the given frame indices."""
    toks = []
    for f in frames:
        for inner in range(BEATS):
            y, j = divmod(inner, MPW)
            row = plane[f][y]
            word = (row[4 * j] | (row[4 * j + 1] << 8) |
                    (row[4 * j + 2] << 16) | (row[4 * j + 3] << 24))
            toks.append(("D", word,
                         1 if inner == 0 else 0,
                         1 if inner % MPW == MPW - 1 else 0,
                         1 if inner == BEATS - 1 else 0))
    return toks


# ----------------------------------------------------------------- dump parsing
def parse(path):
    """-> {(dut, stream): [(kind, data, sof, eol, eof), ...]}, stats dict"""
    seqs = {(d, s): [] for d in (0, 1) for s in (0, 1)}
    stats = {}
    for line in Path(path).read_text(encoding="utf-8", errors="replace").splitlines():
        p = line.split()
        if not p:
            continue
        if p[0] == "STATS":
            for item in p[1:]:
                if "=" in item:
                    k, v = item.split("=", 1)
                    try:
                        stats[k] = int(v)
                    except ValueError:
                        stats[k] = v
            continue
        if len(p) != 7:
            continue
        d, s = int(p[0]), int(p[1])
        if (d, s) not in seqs:
            continue
        if p[2] == "A":
            seqs[(d, s)].append(("A", 0, 0, 0, 0))
        else:
            seqs[(d, s)].append(("D", int(p[3], 16), int(p[4]), int(p[5]), int(p[6])))
    return seqs, stats


# ----------------------------------------------------------------- comparisons
def golden(actual, exp, label):
    compared = mismatch = marker_bad = 0
    samples = []
    for i in range(min(len(actual), len(exp))):
        a = actual[i]
        e = exp[i]
        if a[0] != e[0]:
            marker_bad += 1
            if len(samples) < 5:
                samples.append({"token": i, "kind": "abort_marker_presence",
                                "actual": a[0], "expected": e[0]})
            continue
        if a[0] == "A":
            continue
        if (a[2], a[3], a[4]) != (e[2], e[3], e[4]):
            marker_bad += 1
            if len(samples) < 5:
                samples.append({"token": i, "kind": "marker",
                                "actual": [a[2], a[3], a[4]], "expected": [e[2], e[3], e[4]]})
        for k in range(4):
            av = (a[1] >> (8 * k)) & 0xFF
            ev = (e[1] >> (8 * k)) & 0xFF
            compared += 1
            if av != ev:
                mismatch += 1
                if len(samples) < 5:
                    samples.append({"token": i, "lane": k, "kind": "pixel",
                                    "actual": av, "expected": ev})
    ok = (mismatch == 0 and marker_bad == 0
          and compared == EXPECTED_PIXELS and len(actual) >= EXPECTED_TOKENS)
    return {"label": label, "compared": compared, "mismatch": mismatch,
            "marker_mismatch": marker_bad, "tokens": len(actual),
            "expected_pixels": EXPECTED_PIXELS, "first_mismatches": samples, "ok": ok}


def seq_equal(a, b, label):
    compared = 0
    mismatch = 0
    samples = []
    if len(a) != len(b):
        mismatch += 1
        samples.append({"token_count": [len(a), len(b)]})
    for i in range(min(len(a), len(b))):
        compared += 1
        if a[i] != b[i]:
            mismatch += 1
            if len(samples) < 5:
                samples.append({"token": i, "base": list(a[i]), "candidate": list(b[i])})
    return {"label": label, "compared": compared, "mismatch": mismatch,
            "first_mismatches": samples, "ok": mismatch == 0}


def diff_count(a, b):
    n = 0
    if len(a) != len(b):
        n += abs(len(a) - len(b))
    for i in range(min(len(a), len(b))):
        if a[i] != b[i]:
            n += 1
    return n


# ----------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", required=True, help="directory holding tokens_sm*_t*.txt")
    ap.add_argument("--out", required=True, help="evidence output directory")
    args = ap.parse_args()
    outdir = Path(args.out)
    outdir.mkdir(parents=True, exist_ok=True)

    files = sorted(glob.glob(str(Path(args.dir) / "tokens_sm*_t*.txt")))
    runs = {}
    for f in files:
        seqs, stats = parse(f)
        runs[Path(f).stem] = {"seqs": seqs, "stats": stats, "file": f}
    if not runs:
        print("P4_CORE_RECON_R0B FAIL no dumps found in %s" % args.dir)
        return 1

    planes = [y8_frame(f) for f in range(NF_GOOD + 1)]
    exp = {0: expected_stream(planes, range(NF_GOOD)),
           1: expected_stream([gau_frame(p) for p in planes], range(NF_GOOD))}
    partial = {0: expected_stream(planes, [NF_GOOD]),
               1: expected_stream([gau_frame(p) for p in planes], [NF_GOOD])}

    ok = True
    golden_report = {}
    f5a_report = {}
    abort_report = {}
    repro_report = {}

    for name in sorted(runs):
        mode = runs[name]["stats"].get("sm", "?")
        tag = runs[name]["stats"].get("tag", "?")
        for dut in (0, 1):
            for stream in (0, 1):
                seq = runs[name]["seqs"][(dut, stream)]
                # split: good-frame tokens, then the intentionally aborted frame, then marker(s)
                good = [t for t in seq[:EXPECTED_TOKENS]]
                tail = seq[EXPECTED_TOKENS:]
                g = golden(good, exp[stream], "%s/%s/%s" % (name, DUT_NAME[dut], STREAM_NAME[stream]))
                # abort semantics
                in_good_markers = sum(1 for t in good if t[0] == "A")
                n_marker = sum(1 for t in tail if t[0] == "A")
                part = [t for t in tail if t[0] == "D"]
                part_cmp = 0
                part_bad = 0
                for i in range(min(len(part), len(partial[stream]))):
                    part_cmp += 4
                    a = part[i]
                    e = partial[stream][i]
                    if a[0] != e[0] or (a[2], a[3], a[4]) != (e[2], e[3], e[4]):
                        part_bad += 1
                    for k in range(4):
                        if ((a[1] >> (8 * k)) & 0xFF) != ((e[1] >> (8 * k)) & 0xFF):
                            part_bad += 1
                stats = runs[name]["stats"]
                cnt_key = {(0, 0): "y8_0", (0, 1): "gau_0", (1, 0): "y8_1", (1, 1): "gau_1"}[(dut, stream)]
                total_expected = EXPECTED_TOKENS + len(part) + n_marker
                abort_ok = (in_good_markers == 0 and n_marker == 1
                            and part_bad == 0 and stats.get(cnt_key) == total_expected)
                abort_report["%s/%s/%s" % (name, DUT_NAME[dut], STREAM_NAME[stream])] = {
                    "good_tokens": len(good), "partial_frame_tokens": len(part),
                    "abort_markers_in_good_frames": in_good_markers,
                    "abort_markers_total": n_marker,
                    "partial_prefix_compared": part_cmp, "partial_prefix_mismatch": part_bad,
                    "tb_reported_tokens": stats.get(cnt_key), "expected_total": total_expected,
                    "ok": abort_ok,
                }
                ok = ok and g["ok"] and abort_ok
                golden_report["%s/%s/%s" % (name, DUT_NAME[dut], STREAM_NAME[stream])] = g
                print("COMPARE mode=%s dut=%s stream=%s compared=%d mismatch=%d markers_bad=%d tokens=%d (expected>=%d)"
                      % (mode, DUT_NAME[dut], STREAM_NAME[stream], g["compared"], g["mismatch"],
                         g["marker_mismatch"], g["tokens"], EXPECTED_TOKENS))
        # F5(a): base vs candidate, full sequence, same mode
        for stream in (0, 1):
            r = seq_equal(runs[name]["seqs"][(0, stream)], runs[name]["seqs"][(1, stream)],
                          "%s/%s" % (name, STREAM_NAME[stream]))
            f5a_report["%s/%s" % (name, STREAM_NAME[stream])] = r
            print("F5A mode=%s stream=%s compared_tokens=%d mismatch=%d"
                  % (mode, STREAM_NAME[stream], r["compared"], r["mismatch"]))
            ok = ok and r["ok"]

    # F5(c): cross-mode difference of candidate must not exceed the base's
    names = sorted(n for n in runs if runs[n]["stats"].get("tag", 0) == 0)
    cross = {}
    for stream in (0, 1):
        base_d = {}
        cand_d = {}
        for i in range(len(names)):
            for j in range(i + 1, len(names)):
                key = "%s-vs-%s" % (names[i], names[j])
                base_d[key] = diff_count(runs[names[i]]["seqs"][(0, stream)],
                                         runs[names[j]]["seqs"][(0, stream)])
                cand_d[key] = diff_count(runs[names[i]]["seqs"][(1, stream)],
                                         runs[names[j]]["seqs"][(1, stream)])
                if cand_d[key] > base_d[key]:
                    ok = False
                print("F5C stream=%s pair=%s base_diff=%d candidate_diff=%d"
                      % (STREAM_NAME[stream], key, base_d[key], cand_d[key]))
        cross[STREAM_NAME[stream]] = {"base": base_d, "candidate": cand_d,
                                      "ok": all(cand_d[k] <= base_d[k] for k in base_d)}

    # E4: repeated run of the same mode must be byte-identical (token sequence)
    for stream in (0, 1):
        if "tokens_sm0_t0" in runs and "tokens_sm0_t1" in runs:
            e = seq_equal(runs["tokens_sm0_t0"]["seqs"][(0, stream)],
                          runs["tokens_sm0_t1"]["seqs"][(0, stream)], "E4/base/%s" % STREAM_NAME[stream])
            e2 = seq_equal(runs["tokens_sm0_t0"]["seqs"][(1, stream)],
                           runs["tokens_sm0_t1"]["seqs"][(1, stream)], "E4/candidate/%s" % STREAM_NAME[stream])
            repro_report[STREAM_NAME[stream]] = {"base": e, "candidate": e2,
                                                 "ok": e["ok"] and e2["ok"]}
            print("E4 stream=%s base_same=%s candidate_same=%s"
                  % (STREAM_NAME[stream], e["ok"], e2["ok"]))
            ok = ok and e["ok"] and e2["ok"]

    # negative control: 1-LSB mutation in the candidate must be caught
    ref_name = "tokens_sm2_t0" if "tokens_sm2_t0" in runs else sorted(runs)[0]
    mut = list(runs[ref_name]["seqs"][(1, 0)])
    tgt = 200
    if len(mut) > tgt and mut[tgt][0] == "D":
        _, d, sf, el, ef = mut[tgt]
        mut[tgt] = ("D", (d + (1 << 8)) & 0xFFFFFFFF, sf, el, ef)
        neg = golden(mut[:EXPECTED_TOKENS], exp[0], "negctl/%s/y8" % ref_name)
        detected = neg["mismatch"] >= 1 and neg["ok"] is False
    else:
        neg = {"label": "negctl", "compared": 0, "mismatch": 0, "ok": False}
        detected = False
    print("NEGCTL injected_1lsb=%d detected=%d mismatch=%d" % (1 if detected else 0, 1 if detected else 0, neg["mismatch"]))
    ok = ok and detected

    (outdir / "pixel-compare.json").write_text(json.dumps({
        "task_id": "T10.p4-core-recon", "attempt": "round0-attempt2",
        "candidate": "P4.core-recon-r0",
        "frame_control_contract": "r2 tb_img_algo_equiv_p4.v (1350d75c..a639f) verbatim; dump tap only",
        "stimulus": "synthetic px(b,k)=(37b+211k+13*(b>>5)+5)&0x3FF, W=64 H=48 phase=0, frames 0,1 good, frame 2 aborted at beat 200",
        "expected_pixels_per_stream": EXPECTED_PIXELS,
        "results": golden_report, "ok": all(v["ok"] for v in golden_report.values()),
    }, indent=2), encoding="utf-8")
    (outdir / "abort-semantics.json").write_text(json.dumps(
        {"per_run": abort_report, "ok": all(v["ok"] for v in abort_report.values())}, indent=2),
        encoding="utf-8")
    (outdir / "f5-ready-pattern.json").write_text(json.dumps({
        "a_same_mode_base_vs_candidate": f5a_report,
        "c_cross_mode": cross,
        "ok": all(v["ok"] for v in f5a_report.values()) and all(v["ok"] for v in cross.values()),
    }, indent=2), encoding="utf-8")
    (outdir / "e4-repro.json").write_text(json.dumps(
        {"runs": repro_report, "ok": all(v["ok"] for v in repro_report.values())}, indent=2),
        encoding="utf-8")
    (outdir / "negative-mutation.json").write_text(json.dumps({
        "control": "one +1 LSB on byte lane 1 of candidate y8 token 200, same comparator",
        "detected": bool(detected), "result": neg,
    }, indent=2), encoding="utf-8")

    print("P4_CORE_RECON_R0B %s" % ("PASS" if ok else "FAIL"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
