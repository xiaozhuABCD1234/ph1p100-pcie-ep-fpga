#!/usr/bin/env python3
"""Independent reference model + comparator for task T10.p4-core-recon (candidate P4.core-recon-r0).

Recomputes the expected Y8 (Bayer RAW10 demosaic -> RGB888 -> Y8) and Gaussian (3x3
[1 2 1; 2 4 2; 1 2 1], (sum+8)>>4) pixel streams from the testbench's documented synthetic
stimulus and compares them, pixel by pixel, with the token dump produced by the DUT.

Stimulus (SYNTHETIC, not camera data; identical formula in tb/tb_p4_core_golden.v):
    px(b, k) = (37*b + 211*k + 13*(b >> 5) + 5) & 0x3FF
    b = global beat index 0 .. NF*BEATS-1, k = lane 0..3 (lane 0 = bits[9:0] = leftmost)
    W = 64, H = 48, phase = 0 (RGGB), NF = 2 good frames, no abort frame.

Reference semantics frozen from the candidate RTL (documented, not re-used code):
  * demosaic: CFA code from (phase, x&1, y&1); border clamp is CFA-parity preserving
    (x=-1 -> x=1, x=W -> x=W-2, y=-1 -> y=1, y=H -> y=H-2) for RAW10 (algo_rowwin3_p4
    PARITY_CLAMP=1); green pixels take the horizontal/vertical 2-tap means, red/blue
    pixels the 4-neighbour orthogonal mean and the 4-diagonal mean;
    10-bit channels truncated to 8 bit (>>2); Y = (77R + 150G + 29B + 128) >> 8.
  * gaussian: plain replicate borders (algo_rowwin3_p4 PARITY_CLAMP=0).
  * 4 pixels per beat, byte 0 = lane 0; sof at beat 0 of a frame, eol at the last beat of
    a row, eof at the last beat of the last row.

Usage:
    python compare_p4.py --bp0 tokens_bp0.txt --bp1 tokens_bp1.txt --out evidence_dir
Exit code 0 only when every check passes.
"""

import argparse
import json
import sys
from pathlib import Path

W, H, NF = 64, 48, 2
MPW = W // 4
BEATS = MPW * H
EXPECTED_PIXELS = W * H * NF          # per stream, all frames
EXPECTED_TOKENS = BEATS * NF          # per stream
PHASE = 0
KERNEL = ((-1, 1), (0, 2), (1, 1))


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


def expected_tokens(plane):
    toks = []
    for f in range(NF):
        for inner in range(BEATS):
            y, j = divmod(inner, MPW)
            row = plane[f][y]
            word = (row[4 * j] | (row[4 * j + 1] << 8) |
                    (row[4 * j + 2] << 16) | (row[4 * j + 3] << 24))
            toks.append((f, word,
                         1 if inner == 0 else 0,
                         1 if inner % MPW == MPW - 1 else 0,
                         1 if inner == BEATS - 1 else 0))
    return toks


def parse(path):
    y8, gau, stats = [], [], {}
    for line in Path(path).read_text(encoding="utf-8", errors="replace").splitlines():
        p = line.split()
        if not p:
            continue
        if p[0] in ("Y", "G"):
            rec = (int(p[1]), int(p[2], 16), int(p[3]), int(p[4]), int(p[5]))
            (y8 if p[0] == "Y" else gau).append(rec)
        elif p[0] == "STATS":
            for item in p[1:]:
                if "=" in item:
                    k, v = item.split("=", 1)
                    try:
                        stats[k] = int(v)
                    except ValueError:
                        stats[k] = v
    return y8, gau, stats


def compare(actual, exp, label):
    compared = 0
    mismatch = 0
    marker_bad = 0
    count_bad = abs(len(actual) - len(exp))
    samples = []
    for i in range(min(len(actual), len(exp))):
        afr, adata, asof, aeol, aeof = actual[i]
        efr, edata, esof, eeol, eeof = exp[i]
        if (afr, asof, aeol, aeof) != (efr, esof, eeol, eeof):
            marker_bad += 1
            if len(samples) < 5:
                samples.append({"token": i, "kind": "marker",
                                "actual": [afr, asof, aeol, aeof],
                                "expected": [efr, esof, eeol, eeof]})
        for k in range(4):
            a = (adata >> (8 * k)) & 0xFF
            e = (edata >> (8 * k)) & 0xFF
            compared += 1
            if a != e:
                mismatch += 1
                if len(samples) < 5:
                    samples.append({"token": i, "lane": k, "kind": "pixel",
                                    "actual": a, "expected": e})
    ok = (count_bad == 0 and marker_bad == 0 and mismatch == 0
          and compared == EXPECTED_PIXELS and len(actual) == EXPECTED_TOKENS)
    return {"label": label, "compared": compared, "mismatch": mismatch,
            "marker_mismatch": marker_bad, "token_count_mismatch": count_bad,
            "expected_pixels": EXPECTED_PIXELS, "expected_tokens": EXPECTED_TOKENS,
            "actual_tokens": len(actual), "first_mismatches": samples, "ok": ok}


def cross(a, b, label):
    compared = 0
    mismatch = 0
    samples = []
    if len(a) != len(b):
        mismatch += 1
        samples.append({"token_count": [len(a), len(b)]})
    for i in range(min(len(a), len(b))):
        compared += 4
        if a[i] != b[i]:
            mismatch += 1
            if len(samples) < 5:
                samples.append({"token": i, "a": list(a[i]), "b": list(b[i])})
    return {"label": label, "compared": compared, "mismatch": mismatch,
            "first_mismatches": samples, "ok": mismatch == 0}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bp0", required=True)
    ap.add_argument("--bp1", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()
    outdir = Path(args.out)
    outdir.mkdir(parents=True, exist_ok=True)

    exp_y8 = expected_tokens([y8_frame(f) for f in range(NF)])
    exp_gau = expected_tokens([gau_frame(y8_frame(f)) for f in range(NF)])

    dumps = {}
    for tag, path in (("bp0", args.bp0), ("bp1", args.bp1)):
        y8, gau, stats = parse(path)
        dumps[tag] = {"y8": y8, "gau": gau, "stats": stats}

    results = {}
    ok = True
    stats_checks = {}
    for tag in ("bp0", "bp1"):
        d = dumps[tag]
        r_y8 = compare(d["y8"], exp_y8, "%s/y8" % tag)
        r_gau = compare(d["gau"], exp_gau, "%s/gau" % tag)
        st = d["stats"]
        stats_ok = (st.get("xerr", -1) == 0 and st.get("abt_ev", -1) == 0
                    and st.get("diff", -1) == 0 and st.get("good_p", -1) == 2
                    and st.get("abt_p", -1) == 0 and st.get("gauabt", -1) == 0
                    and st.get("y8", -1) == EXPECTED_TOKENS
                    and st.get("gau", -1) == EXPECTED_TOKENS)
        stats_checks[tag] = {"stats": st, "ok": stats_ok}
        print("COMPARE stream=y8 mode=%s compared=%d mismatch=%d markers_bad=%d tokens=%d/%d"
              % (tag, r_y8["compared"], r_y8["mismatch"], r_y8["marker_mismatch"],
                 r_y8["actual_tokens"], r_y8["expected_tokens"]))
        print("COMPARE stream=gau mode=%s compared=%d mismatch=%d markers_bad=%d tokens=%d/%d"
              % (tag, r_gau["compared"], r_gau["mismatch"], r_gau["marker_mismatch"],
                 r_gau["actual_tokens"], r_gau["expected_tokens"]))
        ok = ok and r_y8["ok"] and r_gau["ok"] and stats_ok
        results[tag] = {"y8": r_y8, "gau": r_gau}

    (outdir / "pixel-compare.json").write_text(json.dumps({
        "task_id": "T10.p4-core-recon",
        "candidate": "P4.core-recon-r0",
        "stimulus": "synthetic px(b,k)=(37b+211k+13*(b>>5)+5)&0x3FF, W=64 H=48 phase=0 NF=2",
        "reference_model": "model/compare_p4.py (independent recompute)",
        "expected_pixels_per_stream": EXPECTED_PIXELS,
        "results": results,
        "stats_checks": stats_checks,
        "ok": ok,
    }, indent=2), encoding="utf-8")

    marker_report = {}
    for tag in ("bp0", "bp1"):
        for stream in ("y8", "gau"):
            toks = dumps[tag][stream]
            marker_report["%s/%s" % (tag, stream)] = {
                "sof": sum(t[2] for t in toks),
                "eol": sum(t[3] for t in toks),
                "eof": sum(t[4] for t in toks),
                "tokens": len(toks),
                "tokens_per_frame": [len(toks) // NF if toks else 0],
            }
    (outdir / "token-markers.json").write_text(json.dumps({
        "expected": {"sof_per_frame": 1, "eol_per_frame": H, "eof_per_frame": 1,
                     "abort_markers": 0, "frames": NF},
        "observed": marker_report,
        "status_counters": {t: dumps[t]["stats"] for t in ("bp0", "bp1")},
        "ok": ok,
    }, indent=2), encoding="utf-8")

    bp_y8 = cross(dumps["bp0"]["y8"], dumps["bp1"]["y8"], "y8 bp0-vs-bp1")
    bp_gau = cross(dumps["bp0"]["gau"], dumps["bp1"]["gau"], "gau bp0-vs-bp1")
    print("CROSS stream=y8 compared=%d mismatch=%d" % (bp_y8["compared"], bp_y8["mismatch"]))
    print("CROSS stream=gau compared=%d mismatch=%d" % (bp_gau["compared"], bp_gau["mismatch"]))
    ok = ok and bp_y8["ok"] and bp_gau["ok"]
    (outdir / "backpressure.json").write_text(json.dumps({
        "normal_mode": "+BP=0 (ready always high)",
        "backpressure_mode": "+BP=1 (pseudo-random ready >=30% stall + one 80-cycle stall at beat 300)",
        "y8": bp_y8, "gau": bp_gau, "ok": bp_y8["ok"] and bp_gau["ok"],
    }, indent=2), encoding="utf-8")

    # negative control: inject a 1-LSB error into one pixel of the bp0 y8 dump
    mut = list(dumps["bp0"]["y8"])
    tgt = 123
    fr, data, sof, eol, eof = mut[tgt]
    mut[tgt] = (fr, (data + (1 << 16)) & 0xFFFFFFFF, sof, eol, eof)
    neg = compare(mut, exp_y8, "bp0/y8/mutated-lane2")
    detected = neg["mismatch"] >= 1 and neg["ok"] is False
    print("NEGCTL injected_1lsb=1 detected=%d mismatch=%d" % (1 if detected else 0, neg["mismatch"]))
    (outdir / "negative-mutation.json").write_text(json.dumps({
        "control": "mutate one Y8 pixel lane by +1 LSB in the bp0 dump, re-run the same comparator",
        "target_token": tgt, "target_lane": 2,
        "detected": bool(detected), "result": neg,
        "purpose": "reject a broken/self-confirming comparator",
    }, indent=2), encoding="utf-8")
    ok = ok and detected

    print("P4_CORE_RECON_COMPARE %s" % ("PASS" if ok else "FAIL"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
