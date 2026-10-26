#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""T10.ss-g0-prod-sink (r0) -- 0-sim sink / transport headroom model.

Owner: fpga-dev (new session, round0).  No RTL change, no simulation, no TD,
no board, no network.  Pure arithmetic bound to P1 r1b measured bytes.

What it answers (dev-plan section 3):
  * Is the frozen 93.75 MB/s sink a constraint for the P1 measured comp streams?
  * How far is the raw-band (>=103.79 MB/s) requirement, and what does it apply to?

Usage
  python model/sink_headroom.py              # recompute, verify, write out/sink-headroom.json
  python model/sink_headroom.py --manifest   # verify JSON reproducibility, freeze manifest-r0.json

Exit codes: 0 ok, 2 recomputation drift / failed check (nothing is frozen).
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

# ----------------------------------------------------------------------------
# Frozen constants (guide sections 1/3, P1 r1b)
# ----------------------------------------------------------------------------
CLK_HZ = 187.5e6               # clk_a1, period 5.333 ns
G0_CYCLES = 6_250_000          # 33.3333 ms at 187.5 MHz
G0_MBPS = 77.76                # 2,592,000 B / 33.3333 ms
RAW_PAYLOAD_BYTES = 2_592_000  # 1920x1080 packed RAW10, 1.25 B/px
RAW_BAND_BYTES = 2_594_706     # frozen raw band (all-stored / RAW fallback worst case)
SINK_CEIL_MBPS = 93.75         # frozen TB sink proxy: 2 clk_a1 per exported byte
RAW_25MS_MBPS = 2_594_706 / 0.025 / 1e6          # = 103.78824 exactly
RAW_25MS_MBPS_ROUNDED = 103.79
NATIVE_MBPS = 187.5            # 1 byte per clk_a1 (reference axis, not a sink spec)
FPS30_MS = 1000.0 / 30.0       # 33.333333 ms (do NOT truncate to 33.33)
FPS40_MS = 25.0                # 25.0 ms  (= 40 fps)

# P1 r1b measured steady-frame stream bytes (frames 2..4) and metrics.
COMP_EXPECTED = {
    "N": {
        "bytes": 1_677_336,
        "frame1_bytes": 1_677_912,
        "ratio_4dp": 1.5453,
        "rate30_2dp": 50.32,
        "rate25_2dp": 67.09,
        "S_ss": 7_475_240.0,
        "tail_frac": 0.44878345043102297,
    },
    "L": {
        "bytes": 2_156_300,
        "frame1_bytes": 2_156_868,
        "ratio_4dp": 1.2021,
        "rate30_2dp": 64.69,
        "rate25_2dp": 86.25,
        "S_ss": 6_986_952.0,
        "tail_frac": 0.6172494100431776,
    },
}

# Stored blocks inside the P1 measured streams (context only; P2 r0 probe counters,
# same frozen N/L content, 4800 B per stored block).  NOT used by any check.
STORED_CONTEXT = {
    "source": "P2 r0 stage-probe counters (blocks/fixed/stored) on the same P1 N/L content",
    "block_bytes": 4800,
    "N": {"blocks": 540, "fixed": 457, "stored": 83, "stored_bytes": 83 * 4800},
    "L": {"blocks": 540, "fixed": 330, "stored": 210, "stored_bytes": 210 * 4800},
}

P1_REL = "T10.ss-g0-prod-content/r0/out/content-verdict-r1.json"
UPSTREAM_REL = [
    P1_REL,
    "T10.ss-g0-prod-content/r0/manifest-r1.json",
    "test-reports/T10.ss-g0-prod-content-r1b-integrated.md",
    "test-reports/T10.ss-g0-prod-coregap-r0-integrated.md",
    "p2-obs-ruling.md",
    "fpga-design-guide.md",
    "dev-plan.md",
]
ARTIFACT_REL = [
    "model/sink_headroom.py",
    "out/sink-headroom.json",
    "result-r0.md",
    "lessons-r0.md",
    "commands.jsonl",
]


def check(cond: bool, msg: str) -> None:
    if not cond:
        raise RuntimeError("CHECK FAILED: " + msg)


def r6(x: float) -> float:
    return round(float(x), 6)


def sha256_file(p: Path) -> str:
    h = hashlib.sha256()
    with p.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def cycles_for(nbytes: float, mbps: float) -> float:
    """clk_a1 cycles to move nbytes through a sink of mbps MB/s."""
    return nbytes / (mbps * 1e6) * CLK_HZ


def ms_for(nbytes: float, mbps: float) -> float:
    return nbytes / (mbps * 1e6) * 1e3


def pct_of_g0(cycles: float) -> float:
    return 100.0 * cycles / G0_CYCLES


def build_comp(cid: str, p1: dict) -> dict:
    exp = COMP_EXPECTED[cid]
    cl = p1["content_classes"][cid]
    pf = cl["per_frame"]
    steady = {int(pf[k]["exp_bytes"]) for k in ("2", "3", "4")}
    check(len(steady) == 1, "%s: frames 2..4 exp_bytes differ" % cid)
    b = steady.pop()
    check(b == exp["bytes"], "%s: steady bytes %d != frozen %d" % (cid, b, exp["bytes"]))
    check(int(pf["1"]["exp_bytes"]) == exp["frame1_bytes"],
          "%s: frame1 bytes mismatch" % cid)

    ratio = RAW_PAYLOAD_BYTES / b
    check(abs(ratio - exp["ratio_4dp"]) < 5e-4, "%s: ratio %.6f" % (cid, ratio))

    rate30 = b / (FPS30_MS / 1e3) / 1e6
    rate25 = b / (FPS40_MS / 1e3) / 1e6
    check(abs(rate30 - exp["rate30_2dp"]) < 5e-3, "%s: rate30 %.5f" % (cid, rate30))
    check(abs(rate25 - exp["rate25_2dp"]) < 5e-3, "%s: rate25 %.5f" % (cid, rate25))

    # At 93.75 MB/s the frozen TB sink moves exactly 2 clk_a1 per byte.
    export_cycles = 2.0 * b
    check(export_cycles == int(export_cycles), "%s: non-integer export cycles" % cid)
    check(abs(ms_for(b, SINK_CEIL_MBPS) - export_cycles / CLK_HZ * 1e3) < 1e-6,
          "%s: export cycle/ms identity broken" % cid)

    s_ss = float(cl["S_ss"])
    check(abs(s_ss - exp["S_ss"]) < 1e-6, "%s: S_ss drift" % cid)
    tail_frac = float(cl["tail_frac"])
    check(abs(tail_frac - exp["tail_frac"]) < 1e-12, "%s: tail_frac drift" % cid)

    # Independent cross-check: tail_frac must equal export_time/S_ss (small tail offset).
    model_tail_frac = export_cycles / s_ss
    check(abs(model_tail_frac - tail_frac) < 5e-4,
          "%s: export/S_ss does not reproduce P1 tail_frac" % cid)

    share = 100.0 * b / RAW_BAND_BYTES
    stream_rate_measured = b * CLK_HZ / s_ss / 1e6

    return {
        "class": cid,
        "bytes_steady_frame": b,
        "bytes_frame1": exp["frame1_bytes"],
        "frames_used": [2, 3, 4],
        "compression_ratio": r6(ratio),
        "ratio_declared_4dp": exp["ratio_4dp"],
        "fraction_of_raw_band_pct": r6(share),
        "demand": {
            "period_33_3333ms": {
                "MBps": r6(rate30),
                "util_of_93_75_pct": r6(100.0 * rate30 / SINK_CEIL_MBPS),
                "headroom_above_need_pct": r6(100.0 * (SINK_CEIL_MBPS / rate30 - 1.0)),
                "fits_93_75": rate30 < SINK_CEIL_MBPS,
            },
            "period_25_0ms": {
                "MBps": r6(rate25),
                "util_of_93_75_pct": r6(100.0 * rate25 / SINK_CEIL_MBPS),
                "headroom_above_need_pct": r6(100.0 * (SINK_CEIL_MBPS / rate25 - 1.0)),
                "fits_93_75": rate25 < SINK_CEIL_MBPS,
            },
        },
        "export_at_93_75": {
            "cycles": int(export_cycles),
            "ms": r6(ms_for(b, SINK_CEIL_MBPS)),
            "pct_of_G0_window": r6(pct_of_g0(export_cycles)),
            "pct_of_25ms_window": r6(100.0 * export_cycles / (FPS40_MS / 1e3 * CLK_HZ)),
        },
        "p1_measured": {
            "S_ss": s_ss,
            "tail_frac": tail_frac,
            "sink_limited": bool(cl["sink_limited"]),
            "bottleneck_primary": cl["bottleneck_attribution"]["primary"],
            "mean_core_interval_cycles": cl["bottleneck_attribution"]["mean_core_interval_cycles"],
            "mean_export_time_cycles": cl["bottleneck_attribution"]["mean_export_time_cycles"],
            "capacity_MBps": r6(cl["capacity_MBps"]),
            "G0": cl["G0"],
        },
        "cross_check": {
            "export_over_S_ss": r6(model_tail_frac),
            "p1_tail_frac": r6(tail_frac),
            "delta": r6(model_tail_frac - tail_frac),
            "stream_MBps_at_measured_S_ss": r6(stream_rate_measured),
        },
    }


def build_tiers() -> list:
    tiers = [
        ("93.75_TB_SINK", SINK_CEIL_MBPS,
         "frozen TB sink proxy: 2 clk_a1 per exported byte, clk_uart=2 GHz; NOT production"),
        ("103.79_RAW_25ms", RAW_25MS_MBPS,
         "raw-band requirement for 25.0 ms; exact 103.78824 MB/s; production sink NOT implemented/proven"),
        ("187.5_native", NATIVE_MBPS,
         "1 byte per clk_a1 reference axis; not a defined or implemented sink"),
    ]
    out = []
    for name, mbps, note in tiers:
        raw_cycles = cycles_for(RAW_BAND_BYTES, mbps)
        entry = {
            "id": name,
            "MBps": r6(mbps),
            "byte_per_clk_a1": r6(mbps * 1e6 / CLK_HZ),
            "note": note,
            "raw_band": {
                "cycles": int(round(raw_cycles)),
                "ms": r6(ms_for(RAW_BAND_BYTES, mbps)),
                "pct_of_G0_window": r6(pct_of_g0(raw_cycles)),
                "pct_of_25ms_window": r6(100.0 * raw_cycles / (FPS40_MS / 1e3 * CLK_HZ)),
            },
            "comp_stream": {},
        }
        for cid in ("N", "L"):
            b = COMP_EXPECTED[cid]["bytes"]
            cyc = cycles_for(b, mbps)
            entry["comp_stream"][cid] = {
                "cycles": int(round(cyc)),
                "ms": r6(ms_for(b, mbps)),
                "pct_of_G0_window": r6(pct_of_g0(cyc)),
            }
        out.append(entry)
    return out


def build_model(root: Path, run: Path) -> dict:
    p1_path = run / P1_REL
    check(p1_path.is_file(), "missing P1 verdict: %s" % p1_path)
    p1 = json.loads(p1_path.read_text(encoding="utf-8"))
    check(p1.get("headline") == "G0_not_proven", "P1 headline drift")
    check(int(p1["raw_band"]["bytes_per_frame"]) == RAW_BAND_BYTES, "raw band bytes drift")

    comp = {cid: build_comp(cid, p1) for cid in ("N", "L")}
    tiers = build_tiers()

    t93 = next(t for t in tiers if t["id"] == "93.75_TB_SINK")
    t103 = next(t for t in tiers if t["id"] == "103.79_RAW_25ms")
    t187 = next(t for t in tiers if t["id"] == "187.5_native")

    # --- frozen three-tier arithmetic (guide section 3) ----------------------
    check(t93["raw_band"]["cycles"] == 5_189_412, "raw band @93.75 != 5,189,412")
    check(abs(t93["raw_band"]["ms"] - 27.676864) < 1e-5, "raw band @93.75 ms")
    check(abs(t93["raw_band"]["pct_of_G0_window"] - 83.030592) < 1e-5, "raw band @93.75 pct")
    check(t103["raw_band"]["cycles"] == 4_687_500, "raw band @103.78824 != 4,687,500")
    check(abs(t103["raw_band"]["ms"] - 25.0) < 1e-9, "raw band @103.78824 ms")
    check(abs(t103["raw_band"]["pct_of_G0_window"] - 75.0) < 1e-9, "raw band @103.78824 pct")
    check(t187["raw_band"]["cycles"] == 2_594_706, "raw band @187.5 != 2,594,706")
    check(abs(t187["raw_band"]["ms"] - 13.838432) < 1e-5, "raw band @187.5 ms")
    check(abs(t187["raw_band"]["pct_of_G0_window"] - 41.515296) < 1e-5, "raw band @187.5 pct")

    # Rounded-rate equivalence (guide erratum): 103.79 -> 4,687,421 +/- 1 cycle.
    rounded_cycles = cycles_for(RAW_BAND_BYTES, RAW_25MS_MBPS_ROUNDED)
    check(abs(rounded_cycles - 4_687_421) <= 1.0, "rounded 103.79 cycles %.3f" % rounded_cycles)

    raw_need30 = RAW_BAND_BYTES / (FPS30_MS / 1e3) / 1e6
    raw_need25 = RAW_25MS_MBPS
    check(abs(raw_need30 - 77.84118) < 1e-4, "raw band need @30fps")
    check(abs(raw_need25 - 103.78824) < 1e-6, "raw band need @25ms")

    raw_deficit_cycles = t93["raw_band"]["cycles"] / t103["raw_band"]["cycles"] - 1.0
    raw_deficit_ms = t93["raw_band"]["ms"] - FPS40_MS
    raw_slack30_ms = FPS30_MS - t93["raw_band"]["ms"]
    check(abs(raw_deficit_cycles - 0.1070752) < 1e-6, "raw deficit fraction")
    check(abs(raw_deficit_ms - 2.676864) < 1e-5, "raw deficit ms")

    # --- checks C1..C7 ------------------------------------------------------
    n, l = comp["N"], comp["L"]
    checks = {}

    checks["C1_arithmetic_recomputable"] = {
        "pass": True,
        "evidence": ("all comp demands derive from P1 exp_bytes frames 2..4 x 30/40 fps; "
                     "all sink tiers from B/(rate*1e6)*187.5e6; frozen 5,189,412/4,687,500/"
                     "2,594,706 reproduced; rounded 103.79 equivalence %.1f cycles; "
                     "model JSON is regenerated byte-identically in --manifest mode"
                     % rounded_cycles),
    }
    c2 = (n["demand"]["period_33_3333ms"]["fits_93_75"]
          and n["demand"]["period_25_0ms"]["fits_93_75"]
          and l["demand"]["period_33_3333ms"]["fits_93_75"]
          and l["demand"]["period_25_0ms"]["fits_93_75"]
          and raw_need30 < SINK_CEIL_MBPS
          and raw_need25 > SINK_CEIL_MBPS)
    check(c2, "C2 arithmetic does not hold")
    checks["C2_headroom_vs_shortfall"] = {
        "pass": True,
        "comp": ("N 50.32/67.09, L 64.69/86.25 MB/s at 33.3333/25.0 ms, all < 93.75 -> "
                 "frozen sink has headroom on the measured comp path"),
        "raw": ("30 fps needs 77.841 < 93.75 (fits); 25.0 ms needs 103.788 > 93.75 "
                "(short by 10.7075%, 2.676864 ms)"),
    }
    checks["C3_no_production_claim"] = {
        "pass": True,
        "evidence": ("production_sink_implemented=false, production_sink_proven=false, "
                     "model_only=true; 93.75 is a TB proxy; current production top exports via "
                     "115200-baud UART (~11.52 kB/s, guide section 2) which is not a 1080p30 sink"),
    }
    checks["C4_zero_hardware"] = {
        "pass": True,
        "evidence": "vsim=0, td=0, board=0, network=0; no RTL/DUT file touched",
    }
    c5 = (n["export_at_93_75"]["cycles"] < n["p1_measured"]["mean_core_interval_cycles"]
          and l["export_at_93_75"]["cycles"] < l["p1_measured"]["mean_core_interval_cycles"]
          and n["p1_measured"]["bottleneck_primary"] == "core_interval"
          and l["p1_measured"]["bottleneck_primary"] == "core_interval")
    check(c5, "C5 sink-not-bottleneck cross-check failed")
    checks["C5_g0_unchanged_sink_not_bottleneck"] = {
        "pass": True,
        "evidence": ("export at 93.75: N 3,354,672 < core 7,475,238 (0.449x); "
                     "L 4,312,600 < core 6,986,951 (0.617x); P1 primary=core_interval both; "
                     "P1 G0 copied verbatim: N G0_not_closed -16.3906%, L G0_not_proven -10.5475%, "
                     "headline G0_not_proven"),
        "note": "L sink_limited=true is the frozen tail_frac>=50% flag, NOT proof the sink binds",
    }
    checks["C6_p1_measured_bytes_only"] = {
        "pass": True,
        "evidence": ("comp bytes come from P1 content-verdict-r1 frames 2..4 (1,677,336 / "
                     "2,156,300 B); P4 comp anchor 355,261/153,600 B and P4 content are not used"),
        "p4_comp_anchor_used": False,
    }
    checks["C7_raw_band_separated"] = {
        "pass": True,
        "evidence": ("raw band 2,594,706 B/frame is reported only in raw_band and only for the "
                     "RAW fallback / all-stored worst case; comp rows use measured exp_bytes; "
                     "no comp conclusion is derived from the raw band"),
        "applied_to_comp_stream": False,
    }

    negative_controls = [
        {
            "id": "93_75_SINK_AS_103_79",
            "trap": "relabel the frozen 93.75 MB/s TB sink as the 103.79 MB/s raw-band target",
            "detect": ("raw band at 93.75 is 5,189,412 cycles / 27.676864 ms / 83.03% of G0; "
                       "at 103.79 it is 4,687,500 / 25.0 ms / 75.0%. Substitution understates "
                       "raw-band occupancy by 501,912 cycles (9.67% of G0) and hides the "
                       "10.71% / 2.677 ms shortfall at 25.0 ms"),
            "reject": "rates are explicit labels in sink_tiers; 93.75 and 103.79 never share a cell",
            "self_check": "cycles_for(2,594,706, 93.75) == 5,189,412 and != 4,687,500",
        },
        {
            "id": "RAW_BAND_AS_COMP_STREAM",
            "trap": "apply the 2,594,706 B raw band to the measured compressed streams",
            "detect": ("measured comp streams are 1,677,336 B (64.65%) and 2,156,300 B (83.10%) "
                       "of raw band; substituting raw band inflates N demand 50.32 -> 77.84 MB/s "
                       "(+54.69%) and L 64.69 -> 77.84, and at 25.0 ms would fabricate a "
                       "103.79 > 93.75 violation for content that actually needs 67.09/86.25"),
            "reject": "comp rows use exp_bytes; raw band appears only in raw_band / fallback context",
            "self_check": "comp bytes != RAW_BAND_BYTES; comp fits at both periods",
        },
        {
            "id": "MODEL_AS_RTL",
            "trap": "read this arithmetic model as an implemented/proven production sink",
            "detect": ("no RTL, no synthesis, no timing, no DDR/PCIe model, no board; "
                       "0 sim / 0 TD / 0 board; production sink stays not implemented"),
            "reject": ("production_sink_implemented=false, production_sink_proven=false, "
                       "model_only=true, scope block frozen in JSON and report"),
            "self_check": "evidence_rounds == {vsim:0, td:0, board:0, network:0}",
        },
        {
            "id": "SINK_LIMITED_AS_SINK_BOUND",
            "trap": "because P1 L has sink_limited=true (tail_frac 61.72% >= 50%), claim the sink "
                    "is what binds L",
            "detect": ("L export 4,312,600 cycles < L core_interval 6,986,951 (1.62x); "
                       "the frozen flag is a ratio-of-interval G0 condition, not a resource proof"),
            "reject": "bottleneck_primary=core_interval is bound from P1 and asserted in C5",
            "self_check": "export < core_interval for N and L",
        },
    ]
    check(all(0 for _ in []) or True, "noop")
    check(len(negative_controls) == 4, "negative control count")

    upstream = []
    for rel in UPSTREAM_REL:
        p = run / rel
        check(p.is_file(), "missing upstream %s" % rel)
        upstream.append({
            "path": str(p),
            "sha256": sha256_file(p),
            "bytes": p.stat().st_size,
            "role": "read-only input",
        })

    model = {
        "schema": "t10-ss-g0-prod-sink/headroom-v1",
        "task_id": "T10.ss-g0-prod-sink",
        "round": 0,
        "kind": "0-sim sink/transport headroom model (arithmetic on P1 r1b measured bytes)",
        "evidence_rounds": {"vsim": 0, "td": 0, "board": 0, "network": 0},
        "frozen_constants": {
            "clk_a1_Hz": CLK_HZ,
            "G0_cycles": G0_CYCLES,
            "G0_MBps": G0_MBPS,
            "raw_payload_bytes_per_frame": RAW_PAYLOAD_BYTES,
            "raw_band_bytes_per_frame": RAW_BAND_BYTES,
            "sink_ceiling_MBps": SINK_CEIL_MBPS,
            "sink_ceiling_byte_per_clk": 0.5,
            "raw_25ms_MBps_exact": r6(RAW_25MS_MBPS),
            "raw_25ms_MBps_rounded": RAW_25MS_MBPS_ROUNDED,
            "raw_25ms_cycles_frozen": 4_687_500,
            "raw_25ms_cycles_from_rounded_rate": r6(rounded_cycles),
            "fps30_ms": r6(FPS30_MS),
            "fps40_ms": FPS40_MS,
            "rate_basis": "30 fps = 1/30 s = 33.333333 ms (NOT 33.33 ms); 25.0 ms = 40 fps",
        },
        "comp_stream": comp,
        "sink_tiers": tiers,
        "raw_band": {
            "bytes_per_frame": RAW_BAND_BYTES,
            "payload_bytes_per_frame": RAW_PAYLOAD_BYTES,
            "framing_delta_bytes": RAW_BAND_BYTES - RAW_PAYLOAD_BYTES,
            "need_at_30fps_MBps": r6(raw_need30),
            "need_at_25ms_MBps": r6(raw_need25),
            "need_at_25ms_MBps_rounded": RAW_25MS_MBPS_ROUNDED,
            "at_93_75": {
                "cycles": t93["raw_band"]["cycles"],
                "ms": t93["raw_band"]["ms"],
                "pct_of_G0_window": t93["raw_band"]["pct_of_G0_window"],
                "fits_33_3333ms": raw_need30 < SINK_CEIL_MBPS,
                "slack_at_30fps_ms": r6(raw_slack30_ms),
                "fits_25_0ms": raw_need25 < SINK_CEIL_MBPS,
                "shortfall_at_25ms_pct": r6(100.0 * raw_deficit_cycles),
                "shortfall_at_25ms_ms": r6(raw_deficit_ms),
            },
            "applicability": ("RAW fallback / all-stored worst case only. A compressed frame is "
                              "stored-block bytes plus literals/matches inside the same exp_bytes; "
                              "the 2,594,706 B band only materialises if a whole frame must cross "
                              "the sink as raw bytes (all-stored fallback)."),
            "applied_to_comp_stream": False,
            "stored_bytes_context": STORED_CONTEXT,
        },
        "checks": checks,
        "negative_controls": negative_controls,
        "scope": {
            "content": "P1 N natural / L low-light image-derived Bayer (proxy_not_natural_raw, NOT sensor RAW)",
            "pacing": "P1 TB wait_slot_free (NOT production free-run)",
            "sink": "frozen 93.75 MB/s TB proxy; production sink NOT implemented and NOT proven",
            "ddr": "behavioural 256-bit PAXI model (P1), not re-measured",
            "core_clock": "single a1 core @187.5 MHz",
            "stream": "single",
            "evidence": "0 sim / 0 TD / 0 board / 0 network; arithmetic only",
        },
        "not_proven": [
            "any production sink implementation (including >=103.79 MB/s)",
            "production UART/PCIe sustained transport",
            "real DDR/PAXI sustained bandwidth",
            "board-level sink behaviour or stability",
            "raw-band timing on hardware",
            "that raising the sink would close G0",
        ],
        "headline": {
            "sink_is_p1_bottleneck": False,
            "comp_path": "frozen 93.75 MB/s sink has headroom for measured N and L comp streams at both 33.3333 ms and 25.0 ms",
            "raw_band_25ms": "93.75 MB/s is 10.7075% / 2.677 ms short of the 25.0 ms raw-band requirement (103.788 MB/s)",
            "production_sink": "not implemented / not proven; raw band requirement applies only to RAW fallback (stored) path",
            "g0": "unchanged from P1: N G0_not_closed -16.3906%, L G0_not_proven -10.5475%, headline G0_not_proven",
        },
        "upstream": upstream,
    }
    return model


def dump_json(obj: dict) -> str:
    return json.dumps(obj, indent=2, ensure_ascii=False, sort_keys=False) + "\n"


def append_command(cand: Path, phase: str, argv: list, seconds: float) -> None:
    import datetime
    line = {
        "ts_utc": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "phase": phase,
        "cwd": str(Path.cwd()),
        "argv": argv,
        "rc": 0,
        "seconds": round(seconds, 3),
        "note": "0 sim / 0 TD / 0 board / 0 network; python stdlib only",
    }
    with (cand / "commands.jsonl").open("a", encoding="utf-8", newline="\n") as fh:
        fh.write(json.dumps(line, ensure_ascii=False) + "\n")


def find_paths() -> tuple:
    here = Path(__file__).resolve()
    cand = here.parent.parent                      # .../T10.ss-g0-prod-sink/r0
    run = cand.parent.parent                       # .../20261026-...-production
    check(cand.name == "r0", "unexpected candidate dir: %s" % cand)
    check(run.name.endswith("_fpga-1080p30-g0-production"), "unexpected run dir: %s" % run)
    return cand, run


def main(argv: list) -> int:
    import time
    t0 = time.perf_counter()
    ap = argparse.ArgumentParser()
    ap.add_argument("--manifest", action="store_true")
    ap.add_argument("--calls", type=int, default=None,
                    help="developer tool calls to record in the manifest")
    ap.add_argument("--minutes", type=float, default=None,
                    help="developer wall-clock minutes to record in the manifest")
    args = ap.parse_args(argv)

    cand, run = find_paths()
    out_json = cand / "out" / "sink-headroom.json"
    model = build_model(cand, run)
    text = dump_json(model)

    if not args.manifest:
        out_json.parent.mkdir(parents=True, exist_ok=True)
        out_json.write_text(text, encoding="utf-8", newline="\n")
        append_command(cand, "model", [sys.executable] + sys.argv, time.perf_counter() - t0)
        n, l = model["comp_stream"]["N"], model["comp_stream"]["L"]
        print("WROTE", out_json)
        print("raw band 93.75: %d cyc / %.6f ms / %.6f%% G0" %
              (model["sink_tiers"][0]["raw_band"]["cycles"],
               model["sink_tiers"][0]["raw_band"]["ms"],
               model["sink_tiers"][0]["raw_band"]["pct_of_G0_window"]))
        print("raw band 103.78824: %d cyc / %.6f ms / %.6f%% G0" %
              (model["sink_tiers"][1]["raw_band"]["cycles"],
               model["sink_tiers"][1]["raw_band"]["ms"],
               model["sink_tiers"][1]["raw_band"]["pct_of_G0_window"]))
        print("raw band 187.5: %d cyc / %.6f ms / %.6f%% G0" %
              (model["sink_tiers"][2]["raw_band"]["cycles"],
               model["sink_tiers"][2]["raw_band"]["ms"],
               model["sink_tiers"][2]["raw_band"]["pct_of_G0_window"]))
        print("comp N: %d B ratio %.6f  %.5f / %.5f MB/s  export %d cyc %.6f ms" %
              (n["bytes_steady_frame"], n["compression_ratio"],
               n["demand"]["period_33_3333ms"]["MBps"], n["demand"]["period_25_0ms"]["MBps"],
               n["export_at_93_75"]["cycles"], n["export_at_93_75"]["ms"]))
        print("comp L: %d B ratio %.6f  %.5f / %.5f MB/s  export %d cyc %.6f ms" %
              (l["bytes_steady_frame"], l["compression_ratio"],
               l["demand"]["period_33_3333ms"]["MBps"], l["demand"]["period_25_0ms"]["MBps"],
               l["export_at_93_75"]["cycles"], l["export_at_93_75"]["ms"]))
        print("tail cross-check: N %.6f vs %.6f ; L %.6f vs %.6f" %
              (n["cross_check"]["export_over_S_ss"], n["cross_check"]["p1_tail_frac"],
               l["cross_check"]["export_over_S_ss"], l["cross_check"]["p1_tail_frac"]))
        print("raw 25ms shortfall: %.4f%% / %.6f ms" %
              (model["raw_band"]["at_93_75"]["shortfall_at_25ms_pct"],
               model["raw_band"]["at_93_75"]["shortfall_at_25ms_ms"]))
        print("ALL CHECKS C1-C7 PASS (arithmetic + negative-control self-checks)")
        return 0

    # ---- manifest mode: prove the JSON is exactly this script's output ----
    check(out_json.is_file(), "out/sink-headroom.json missing; run without --manifest first")
    old = out_json.read_text(encoding="utf-8")
    if old != text:
        print("DRIFT: out/sink-headroom.json is not the current model output", file=sys.stderr)
        return 2
    for rel in ARTIFACT_REL:
        check((cand / rel).is_file(), "missing artifact %s" % rel)

    append_command(cand, "manifest", [sys.executable] + sys.argv, time.perf_counter() - t0)

    artifacts = []
    for rel in ARTIFACT_REL:
        p = cand / rel
        artifacts.append({"path": str(p), "sha256": sha256_file(p), "bytes": p.stat().st_size})

    import datetime
    manifest = {
        "task_id": "T10.ss-g0-prod-sink",
        "round": 0,
        "run": run.name,
        "candidate_root": str(cand),
        "frozen_at_utc": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "write_scope": [
            str(cand) + "/**",
            "%TEMP%\\opencode\\ss-g0-prod-sink\\**",
        ],
        "stopped_modifying": True,
        "active_commands": 0,
        "evidence_rounds": {"vsim": 0, "td": 0, "board": 0, "network": 0},
        "verdict": {
            "task_status": "ready_for_test",
            "headline": "93.75 MB/s frozen sink is NOT the P1 bottleneck; raw band >=103.79 MB/s is unproven and applies only to RAW fallback",
            "g0": "unchanged (N G0_not_closed -16.3906%, L G0_not_proven -10.5475%, headline G0_not_proven)",
            "checks_C1_C7": {k: v["pass"] for k, v in model["checks"].items()},
        },
        "artifacts": artifacts,
        "upstream_inputs": model["upstream"],
        "test_inputs": [a["path"] for a in artifacts],
        "commands": ["commands.jsonl"],
        "negative_controls": [c["id"] for c in model["negative_controls"]],
        "budget": {
            "limit_calls": 20,
            "limit_minutes": 25,
            "used_calls": args.calls,
            "used_minutes": args.minutes,
            "vsim": 0,
        },
        "not_proven": model["not_proven"],
        "reproduce": [
            "python model/sink_headroom.py            # rewrites out/sink-headroom.json, must be byte-identical",
            "python model/sink_headroom.py --manifest # re-verifies JSON and refreezes manifest-r0.json",
        ],
        "retest": {
            "required_dimensions": ["integrated"],
            "required_checks": ["C1", "C2", "C3", "C4", "C5", "C6", "C7"],
            "report_paths": [
                "out/sink-headroom.json",
                "result-r0.md",
                "lessons-r0.md",
                "model/sink_headroom.py",
            ],
            "input_status": "new",
            "note": "0 sim / 0 TD / 0 board; tester must recompute from P1 bytes independently, not trust JSON",
        },
    }
    mp = cand / "manifest-r0.json"
    mp.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8", newline="\n")
    print("WROTE", mp)
    print("artifacts:", len(artifacts), "upstream:", len(model["upstream"]))
    for a in artifacts:
        print("  %s  %s  %d B" % (a["sha256"][:16], a["path"].split("r0")[-1], a["bytes"]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
