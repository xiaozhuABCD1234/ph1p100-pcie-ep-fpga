#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""T09.rk-align-algo vector generator for the ModelSim core testbench.

Scenarios are defined here; the expected streams come from the independent
oracle (tools/algo/oracle_algo.py) and are cross-checked against the frozen
reference (parallel/algorithms/image_algorithms_ref.py) before any vector file
is written.  RTL internals are never consulted.

Vector format consumed by tools/algo/tb/tb_img_algo_core.sv
-----------------------------------------------------------
  RESET                      - reset the DUT (counters/LUT state restart)
  CFG <w> <h> <phase>        - drive the configuration handshake
  SCEN <kind> <abort_at> <n> - start a scenario (kind 0 good, 1 abort,
                               2 bad-eof, 3 over-length, 4 sof-restart)
  IN <data40_hex> <sof> <eol> <eof> <abort>   - one input beat
  GAP <n>                    - n cycles with no input beat
  STALL <branch> <n>         - hold a branch ready low (0=y8, 1=gau, 2=he)
  SEG <branch> <mode> <n>    - expected segment (mode 0 exact, 1 prefix)
  EXP <data32_hex> <sof> <eol> <eof>          - one expected output beat
  TOTALS <good> <abort> <he_pub> <he_rej> <gau_ab>  - final counter check

Usage: python tools/algo/gen_algo_vectors.py --out <dir>
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import random
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import oracle_algo as orc  # noqa: E402


def load_reference():
    ref_path = HERE.parents[1] / "parallel" / "algorithms" / "image_algorithms_ref.py"
    spec = importlib.util.spec_from_file_location("t09_ref", ref_path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


REF = load_reference()


# ---------------------------------------------------------------------------
# patterns
# ---------------------------------------------------------------------------

def pattern_raw(w, h, kind, seed=0):
    rng = random.Random(seed)
    if kind == "ramp":
        return [(y * 37 + x * 11) & 0x3FF for y in range(h) for x in range(w)]
    if kind == "random":
        return [rng.randrange(1024) for _ in range(w * h)]
    if kind == "constant":
        return [511] * (w * h)
    if kind == "black":
        return [0] * (w * h)
    if kind == "white":
        return [1023] * (w * h)
    if kind == "checker":
        return [1023 if (x + y) % 2 else 0 for y in range(h) for x in range(w)]
    if kind == "impulse":
        raw = [0] * (w * h)
        raw[(h // 2) * w + w // 2] = 1023
        return raw
    if kind == "extreme":
        raw = [(x * 41 + y * 17) & 0x3FF for y in range(h) for x in range(w)]
        raw[0], raw[-1] = 0, 1023
        return raw
    if kind == "runs":
        # long runs of one value: consecutive beats hit the same histogram bin
        # in the same lane, which is exactly what the 4-bank bypass must count
        raw = []
        for y in range(h):
            for x in range(w):
                raw.append(512 if x < (3 * w) // 4 else rng.randrange(1024))
        return raw
    raise ValueError(kind)


def sidebands(idx, w, h, kind, abort_at):
    """(sof, eol, eof, abort) for input beat idx of a scenario."""
    m = w // 4
    row, col = idx // m, idx % m
    sof = 1 if idx == 0 else 0
    eol = 1 if col == m - 1 else 0
    eof = 1 if (row == h - 1 and col == m - 1) else 0
    ab = 1 if (kind == 1 and idx == abort_at) else 0
    return sof, eol, eof, ab


def expected_seq(raw, w, h, phase, lut):
    """Raster-order expected output beats for the three branches."""
    gy = orc.grayscale(raw, w, h, phase)
    ga = orc.gaussian(gy, w, h)
    he = [lut[v] for v in gy]
    m = w // 4
    y8_seg, gau_seg, he_seg = [], [], []
    for y in range(h):
        for j in range(m):
            px = list(range(j * 4, j * 4 + 4))
            sb = (1 if (y == 0 and j == 0) else 0,
                  1 if j == m - 1 else 0,
                  1 if (y == h - 1 and j == m - 1) else 0)
            y8_seg.append((orc.pack_y8([gy[y * w + i] for i in px]), sb))
            gau_seg.append((orc.pack_y8([ga[y * w + i] for i in px]), sb))
            he_seg.append((orc.pack_y8([he[y * w + i] for i in px]), sb))
    return y8_seg, gau_seg, he_seg


# ---------------------------------------------------------------------------
# scenario table
# ---------------------------------------------------------------------------

def scenarios():
    """(geometry, kind, pattern, abort_at, extras) list.

    extras: list of (position, command) interleaved into the input beats,
    where command is ("GAP", n) or ("STALL", branch, n).
    """
    S = []
    # group A: 8x2 phase 0
    S.append(dict(w=8, h=2, phase=0, kind=0, pat="ramp", seed=1))
    S.append(dict(w=8, h=2, phase=0, kind=0, pat="random", seed=2,
                  extras=[(3, ("GAP", 5)), (6, ("STALL", 1, 7))]))
    S.append(dict(w=8, h=2, phase=0, kind=1, pat="random", seed=3, abort_at=2))
    S.append(dict(w=8, h=2, phase=0, kind=0, pat="impulse", seed=4))
    S.append(dict(w=8, h=2, phase=0, kind=0, pat="black", seed=5))
    # group B: 8x3 phase 1
    S.append(dict(w=8, h=3, phase=1, kind=0, pat="random", seed=6,
                  extras=[(7, ("STALL", 2, 11)), (11, ("STALL", 0, 5))]))
    S.append(dict(w=8, h=3, phase=1, kind=2, pat="checker", seed=7, send=5))
    S.append(dict(w=8, h=3, phase=1, kind=0, pat="white", seed=8))
    # group C: 12x4 phase 2
    S.append(dict(w=12, h=4, phase=2, kind=0, pat="random", seed=9,
                  extras=[(5, ("GAP", 3)), (9, ("STALL", 1, 9)), (14, ("GAP", 4))]))
    S.append(dict(w=12, h=4, phase=2, kind=3, pat="ramp", seed=10))
    S.append(dict(w=12, h=4, phase=2, kind=0, pat="extreme", seed=11))
    S.append(dict(w=12, h=4, phase=2, kind=4, pat="random", seed=12,
                  split_rows=2, pat2="impulse", seed2=13))
    # group D: 16x5 phase 3
    S.append(dict(w=16, h=5, phase=3, kind=0, pat="random", seed=14,
                  extras=[(9, ("STALL", 0, 13)), (10, ("STALL", 2, 6)), (16, ("GAP", 2))]))
    S.append(dict(w=16, h=5, phase=3, kind=0, pat="constant", seed=15))
    S.append(dict(w=16, h=5, phase=3, kind=1, pat="extreme", seed=16, abort_at=13))
    S.append(dict(w=16, h=5, phase=3, kind=0, pat="random", seed=17))
    # group E: 20x2 phase 0 (same-bin stress: constant then a following frame)
    S.append(dict(w=20, h=2, phase=0, kind=0, pat="ramp", seed=18))
    S.append(dict(w=20, h=2, phase=0, kind=0, pat="constant", seed=19))
    S.append(dict(w=20, h=2, phase=0, kind=0, pat="random", seed=20))
    S.append(dict(w=20, h=2, phase=0, kind=0, pat="runs", seed=24))
    S.append(dict(w=20, h=2, phase=0, kind=0, pat="random", seed=25))
    # group F: 8x2 phase 2
    S.append(dict(w=8, h=2, phase=2, kind=0, pat="random", seed=21))
    S.append(dict(w=8, h=2, phase=2, kind=2, pat="ramp", seed=22, send=3))
    S.append(dict(w=8, h=2, phase=2, kind=0, pat="checker", seed=23))
    return S


def emit(out_path: Path):
    lines = []
    meta = {"groups": [], "frames": []}
    he = orc.HeSeq()
    tot_good = tot_abort = 0
    frame_no = 0
    last_geom = None
    seg_count = [0, 0, 0]   # emitted SEG lines per branch

    def push_cfg(w, h, phase):
        lines.append("CFG %d %d %d" % (w, h, phase))

    lines.append("RESET")
    for sc in scenarios():
        geom = (sc["w"], sc["h"], sc["phase"])
        if geom != last_geom:
            if last_geom is not None:
                # geometry change -> drain the previous group's outputs first,
                # then reset; HE state and counters restart
                lines.append("DRAIN %d %d %d" % (seg_count[0], seg_count[1], seg_count[2]))
                lines.append("RESET")
                he = orc.HeSeq()
                tot_good = tot_abort = 0
                meta["groups"].append({"frame_start": frame_no, "w": geom[0],
                                       "h": geom[1], "phase": geom[2]})
            push_cfg(*geom)
            last_geom = geom

        w, h, phase, kind = sc["w"], sc["h"], sc["phase"], sc["kind"]
        m = w // 4
        raw = pattern_raw(w, h, sc["pat"], sc.get("seed", 0))
        beats = orc.frame_beats(raw, w)

        # ---- expected output of the (full) frame with the current LUT ----
        y8_seg, gau_seg, he_seg = expected_seq(raw, w, h, phase, he.lut)
        # cross-check against the frozen reference
        assert orc.grayscale(raw, w, h, phase) == REF.grayscale(raw, w, h, phase)
        assert orc.gaussian(orc.grayscale(raw, w, h, phase), w, h) == \
            REF.gaussian3x3(REF.grayscale(raw, w, h, phase), w, h)
        assert orc.hist4(orc.grayscale(raw, w, h, phase)) == \
            REF.histogram(REF.grayscale(raw, w, h, phase))

        # ---- input beats / scenario layout ----
        send = sc.get("send", len(beats))
        if kind == 2:                      # bad eof: truncated frame, eof early
            send = sc.get("send", max(m, len(beats) // 2))
        inp = []
        for i in range(send):
            sof, eol, eof, ab = sidebands(i, w, h, kind, sc.get("abort_at", -1))
            if kind == 2 and i == send - 1:
                eof, ab = 1, 0             # eof at a wrong position
            if kind == 3:
                sof, eol, eof, ab = sidebands(i, w, h, 0, -1)
                eof = 0                    # never eof
            if kind == 4:
                sof, eol, eof, ab = sidebands(i, w, h, 0, -1)
                eof = 0                    # old frame is cut by the restart
            inp.append((beats[i] if i < len(beats) else 0, sof, eol, eof, ab))

        restart = None
        if kind == 4:
            split = sc["split_rows"] * m
            raw2 = pattern_raw(w, h, sc["pat2"], sc.get("seed2", 0))
            beats2 = orc.frame_beats(raw2, w)
            y8b, gaub, heb = expected_seq(raw2, w, h, phase, he.lut)
            # restart beat = new frame row 0 word 0 with sof
            restart = (beats2[0], 1, 0, 0, 0)
            inp = inp[:split]
            inp.append(restart)
            for i in range(1, len(beats2)):
                sof, eol, eof, ab = sidebands(i, w, h, 0, -1)
                inp.append((beats2[i], sof, eol, eof, ab))

        if kind == 3:                      # over-length: 2 extra beats after the frame
            inp.append((0, 0, 0, 0, 0))
            inp.append((0, 0, 0, 0, 0))

        # ---- emit ----
        lines.append("SCEN %d %d %d" % (kind, sc.get("abort_at", -1), len(inp)))
        extras = {pos: cmd for pos, cmd in sc.get("extras", [])}
        for i, (data, sof, eol, eof, ab) in enumerate(inp):
            if i in extras:
                cmd = extras[i]
                if cmd[0] == "GAP":
                    lines.append("GAP %d" % cmd[1])
                else:
                    lines.append("STALL %d %d" % (cmd[1], cmd[2]))
            lines.append("IN %010x %d %d %d %d" % (data & ((1 << 40) - 1), sof, eol, eof, ab))

        def emit_seg(branch_id, seg, mode):
            seg_count[branch_id] += 1
            lines.append("SEG %d %d %d" % (branch_id, mode, len(seg)))
            for data, sb in seg:
                lines.append("EXP %08x %d %d %d" % (data, sb[0], sb[1], sb[2]))

        if kind in (1, 2, 3):
            # aborted frame: outputs before the marker are a prefix of the full
            # sequence; a marker closes the segment
            emit_seg(0, y8_seg, 1)
            emit_seg(1, gau_seg, 1)
            emit_seg(2, he_seg, 1)
            he.frame(orc.grayscale(raw, w, h, phase), good=False)
            tot_abort += 1
        elif kind == 4:
            # old frame prefix + marker, then the new frame exactly
            emit_seg(0, y8_seg, 1)
            emit_seg(1, gau_seg, 1)
            emit_seg(2, he_seg, 1)
            he.frame(orc.grayscale(raw, w, h, phase), good=False)
            tot_abort += 1
            emit_seg(0, y8b, 0)
            emit_seg(1, gaub, 0)
            emit_seg(2, heb, 0)
            he.frame(orc.grayscale(raw2, w, h, phase), good=True)
            tot_good += 1
        else:
            emit_seg(0, y8_seg, 0)
            emit_seg(1, gau_seg, 0)
            emit_seg(2, he_seg, 0)
            he.frame(orc.grayscale(raw, w, h, phase), good=True)
            tot_good += 1

        meta["frames"].append({
            "index": frame_no, "w": w, "h": h, "phase": phase, "kind": kind,
            "pattern": sc["pat"], "input_beats": len(inp),
            "y8_beats": len(y8_seg), "gau_beats": len(gau_seg), "he_beats": len(he_seg),
            "abort_at": sc.get("abort_at", -1), "send": send,
        })
        frame_no += 1

    lines.append("TOTALS %d %d %d %d %d" % (tot_good, tot_abort,
                                             tot_good, tot_abort, tot_abort))
    out_path.write_text("\n".join(lines) + "\n", encoding="ascii")
    # final published HE LUT (after the last reset) for the TB readback check
    lut_path = out_path.with_suffix(".lut.hex")
    lut_path.write_text("".join("%02x\n" % v for v in he.lut), encoding="ascii")
    meta["totals"] = {"good": tot_good, "abort": tot_abort}
    meta["final_lut_file"] = lut_path.name
    return meta


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True, help="output directory")
    args = ap.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    vec = out / "algo_core.vec"
    meta = emit(vec)
    (out / "algo_core.meta.json").write_text(json.dumps(meta, indent=2), encoding="utf-8")
    print("T09_VECTORS_WRITTEN", vec, "frames", len(meta["frames"]),
          "totals", meta["totals"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
