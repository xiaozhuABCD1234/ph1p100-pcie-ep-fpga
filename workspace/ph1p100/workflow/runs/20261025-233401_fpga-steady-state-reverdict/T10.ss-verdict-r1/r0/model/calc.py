"""Corrected pure-function service-rate / DDR / UART / content-envelope model.

Task: T10.ss-verdict-r1 (run 20261025-233401_fpga-steady-state-reverdict, P2).

No file I/O, no randomness, no network, no clock reads.  Every function is a pure
function of its arguments.  Constants come from inputs/frozen-inputs.json, decision
rules from model/rules.json.  No final answer is stored here: verdicts are derived
by classify_row() from computed margins plus the frozen resource/timing labels.

Legacy (P2) code is NOT imported here; the byte-identical P2 copies live in
inputs/legacy/ and are used only by model/regress_legacy.py for the 43-row replay.

Units: MB = 10^6 bytes; cycles are clk_a1 cycles at clock_hz; margins are fractions
in the API and are multiplied by 100 only in the formatting layer.
"""
from math import ceil

MB = 1e6
PROFILE_OK = "RAW10_packed_20B32B"


class ModelRejected(Exception):
    """Raised by the negative-control validators."""


# ------------------------------------------------------------------ geometry / bytes
def check_geometry(w, h):
    if not isinstance(w, int) or not isinstance(h, int):
        raise ValueError("W/H must be integers")
    if w <= 0 or h <= 0:
        raise ValueError("W/H must be positive")
    if w % 4:
        raise ValueError("W must be a multiple of 4 (one 5-byte group per 4 pixels)")
    if (w * h) % 4:
        raise ValueError("W*H must be divisible by 4")


def pixels(w, h):
    check_geometry(w, h)
    return w * h


def raw_bytes(w, h):
    """RAW10 packed payload bytes: W*H*5/4."""
    return pixels(w, h) * 5 // 4


def raw_slot_words(w, h):
    return int(ceil((pixels(w, h) // 4) / 4))


def raw_slot_bytes(w, h):
    return raw_slot_words(w, h) * 32


def raw_slot_expansion(w, h):
    return raw_slot_bytes(w, h) / raw_bytes(w, h)


def cmp_payload_bytes(w, h):
    """Worst stored zlib payload: raw + 5*ceil(H/2) + 6."""
    return raw_bytes(w, h) + 5 * int(ceil(h / 2)) + 6


def cmp_total_bytes(w, h, header=44):
    return cmp_payload_bytes(w, h) + header


# --------------------------------------------------------------------------- rates
def demand_MBps(nbytes, fps):
    if nbytes <= 0 or fps <= 0:
        raise ValueError("bytes/fps must be positive")
    return nbytes * fps / MB


def capacity_MBps(nbytes, cycles, clock_hz):
    if nbytes <= 0 or cycles <= 0 or clock_hz <= 0:
        raise ValueError("bytes/cycles/clock must be positive")
    return nbytes * clock_hz / cycles / MB


def capacity_from_cycles(cycles, clock_hz, frame_bytes=2592000):
    """Frame capacity in MB/s for a per-frame cycle count (clock-independent cycles)."""
    return capacity_MBps(frame_bytes, cycles, clock_hz)


def per_stream_capacity(cap_MBps, cores, streams):
    if cores not in (1, 2) or streams not in (1, 2):
        raise ValueError("cores/streams must be 1 or 2")
    # 1 core / 2 streams: frame-level round robin -> 50% each in the long run.
    # 2 cores / 2 streams: one frozen core per stream -> C (never 2C).
    # 2 cores / 1 stream: second core idle -> C.
    return cap_MBps / 2.0 if (cores == 1 and streams == 2) else cap_MBps


def margin_0(cap_MBps, demand):
    """Nominal headroom: capacity/demand - 1."""
    if demand <= 0:
        raise ValueError("demand must be positive")
    return cap_MBps / demand - 1.0


def margin_25(cap_MBps, demand):
    """Headroom against the 1.25x design gate: capacity/(1.25*demand) - 1."""
    if demand <= 0:
        raise ValueError("demand must be positive")
    return cap_MBps / (1.25 * demand) - 1.0


def gate_g0(cap_MBps, demand):
    return "pass" if cap_MBps >= demand else "fail"


def gate_g25(cap_MBps, demand):
    return "pass" if cap_MBps >= 1.25 * demand else "fail"


def required_clock_MHz(cycles_per_frame, fps, margin_frac):
    if cycles_per_frame <= 0 or fps <= 0:
        raise ValueError("cycles/fps must be positive")
    return cycles_per_frame * fps * (1.0 + margin_frac) / MB


def max_fps(cycles_per_frame, clock_hz, margin_frac=0.0):
    if cycles_per_frame <= 0 or clock_hz <= 0:
        raise ValueError("cycles/clock must be positive")
    return clock_hz / (cycles_per_frame * (1.0 + margin_frac))


def drop_rate_lb(cap_ps_MBps, demand):
    if demand <= 0:
        raise ValueError("demand must be positive")
    return max(0.0, 1.0 - cap_ps_MBps / demand)


# --------------------------------------------------------------------- anchors / tiers
def anchor_cycles(frozen, anchor_id):
    return float(frozen["anchors_1080p"][anchor_id]["cycles_per_frame"])


def anchor_metrics(frozen, anchor_id):
    """Capacity / fps / gate margins for a 1080p chain anchor at clock_hz."""
    raw = frozen["frame"]["raw_bytes"]
    cyc = anchor_cycles(frozen, anchor_id)
    cap = capacity_MBps(raw, cyc, frozen["clock_hz"])
    d = demand_MBps(raw, frozen["frame"]["fps_target"])
    return {
        "anchor_id": anchor_id,
        "cycles_per_frame": cyc,
        "capacity_MBps": cap,
        "fps_30_equiv": cap / (raw / MB),
        "demand_MBps": d,
        "margin_0_pct": 100.0 * margin_0(cap, d),
        "margin_25_pct": 100.0 * margin_25(cap, d),
        "gate_G0": gate_g0(cap, d),
        "gate_G25": gate_g25(cap, d),
    }


def tier_shift_1080p(frozen, tier_cycles):
    """1080p chain cycles under an overhead tier: S_ss + (tier - anchor_tier)."""
    s = float(frozen["p1_binding"]["S_ss_cycles"])
    anchor_tier = float(frozen["overhead"]["anchor_tier_cycles"])
    return s + (float(tier_cycles) - anchor_tier)


def chain_cycles_for(frozen, w, h, tier_cycles=None):
    """Chain cycles/frame for a geometry.  1080p: A1 measured anchor (+tier shift)."""
    if (w, h) == (frozen["frame"]["W"], frozen["frame"]["H"]):
        if tier_cycles is None:
            return float(frozen["p1_binding"]["S_ss_cycles"])
        return tier_shift_1080p(frozen, tier_cycles)
    cpb = frozen["core_anchors"]["comp"]["cycles_per_byte"]
    ov = frozen["overhead"]["primary_cycles"] if tier_cycles is None else float(tier_cycles)
    return raw_bytes(w, h) * cpb + float(ov)


def chain_anchor_id_for(frozen, w, h):
    if (w, h) == (frozen["frame"]["W"], frozen["frame"]["H"]):
        return "A1_grad_ss"
    return "affine_comp_tier"


def content_label_for(frozen, w, h):
    if (w, h) == (frozen["frame"]["W"], frozen["frame"]["H"]):
        return "grad_measured_single_content"
    return "comp_assumed_extrapolation"


# ------------------------------------------------------------------------- verdicts
def classify_row(frozen, rules, cores, streams, m0, m25, marginal_eram,
                 conservative_eram, timing_proven, paaxi_shared_unproven=None,
                 eram_device=None, eram_fit_pass_max=None):
    """Mechanical application of rules.json row_verdict_rules V1..V6."""
    ed = frozen["resources"]["eram_device"] if eram_device is None else eram_device
    fp = frozen["resources"]["eram_fit_pass_max"] if eram_fit_pass_max is None else eram_fit_pass_max
    if paaxi_shared_unproven is None:
        paaxi_shared_unproven = bool(rules["dual_core_rules"]["paaxi_shared_unproven"])
    if marginal_eram > ed:
        return "infeasible", "RESOURCE_MARGINAL_OVER_300"
    if m0 < 0.0:
        return "infeasible", "MISSES_NOMINAL"
    if cores == 2 and (paaxi_shared_unproven or not timing_proven):
        return "conditional", "DUAL_CORE_OR_PAAXI_UNPROVEN"
    if m25 < 0.0:
        return "conditional", "BELOW_25"
    if conservative_eram > fp or not timing_proven:
        return "conditional", "RESOURCE_OR_TIMING_UNPROVEN"
    return "feasible", "G25_MET_RESOURCE_TIMING_PROVEN"


def headline_1080p30(rules, a1_m0, a1_m25, a2_m0, a2_m25, resources_ok, cores=1, streams=1):
    """Claim-level 1080p30 headline: G0 / G25 / content, per rules headline_rules."""
    a1_g0 = a1_m0 >= 0.0
    a1_g25 = a1_m25 >= 0.0
    a2_g0 = a2_m0 >= 0.0
    a2_g25 = a2_m25 >= 0.0
    content = "not_proven_all_content"
    if not a1_g0 and not a2_g0:
        word, why = "infeasible", "both measured and conservative content miss G0"
    elif a1_g0 != a2_g0:
        word, why = "not_proven", "content crossing: measured content passes G0, conservative extrapolation misses"
    elif a1_g0 and a2_g0 and (not a1_g25 or not a2_g25):
        word, why = "conditional", "G0 met on both content bases but G25 missed"
    elif a1_g25 and a2_g25 and resources_ok:
        word, why = "feasible", "G0/G25 met on both content bases and resources/timing proven"
    else:
        word, why = "conditional", "G25 met on both content bases but resources/timing unproven"
    if cores == 2 or streams == 2:
        # per-stream for 1c2s is C/2 (not a content question) and dual-core capacity is
        # assumed_from_single_core with shared PAXI unproven -> never better than not_proven
        if word == "feasible":
            word, why = "not_proven", "dual-core/shared-PAXI capacity is assumed_from_single_core"
    return {
        "headline": word,
        "why": why,
        "gate_G0": "pass" if a1_g0 else "fail",
        "gate_G25": "pass" if a1_g25 else "fail",
        "A1": {"G0": a1_g0, "G25": a1_g25, "margin_0_pct": 100.0 * a1_m0, "margin_25_pct": 100.0 * a1_m25},
        "A2": {"G0": a2_g0, "G25": a2_g25, "margin_0_pct": 100.0 * a2_m0, "margin_25_pct": 100.0 * a2_m25},
        "content": content,
        "crossing": a1_g0 != a2_g0,
    }


# ------------------------------------------------------------------------- DDR model
def ddr_case(case_id, streams, fps, w, h, expansion, include_cmp, peak_MBps,
             notes, layout="20B_payload_per_32B_word"):
    raw = raw_bytes(w, h)
    d_total = raw * fps * streams / MB
    rw = d_total * expansion
    rr = rw
    sw = cmp_total_bytes(w, h) * fps * streams / MB if include_cmp else 0.0
    sr = sw
    total = rw + rr + sw + sr
    gate = total * 1.25
    return {
        "case_id": case_id,
        "streams": streams,
        "fps": float(fps),
        "W": w,
        "H": h,
        "raw_write_MBps": rw,
        "raw_read_MBps": rr,
        "cmp_write_MBps": sw,
        "cmp_read_MBps": sr,
        "ddr_total_MBps": total,
        "ddr_gate_25_MBps": gate,
        "peak_MBps": float(peak_MBps),
        "required_eff_pct": total / peak_MBps * 100.0,
        "gate_eff_pct": gate / peak_MBps * 100.0,
        "includes_cmp_ddr": "true" if include_cmp else "false",
        "layout": layout,
        "notes": notes,
    }


DDR_CASES = [
    ("dual_1080p30_main", 2, 30, 1920, 1080, True,
     "main path: camera writes RAW slot, A+ reads RAW, writes CMP, sink reads CMP (2R+2S); 20B/32B slot, CMP worst stored"),
    ("dual_1080p30_no_cmp_ddr", 2, 30, 1920, 1080, False,
     "variant: CMP streamed directly, no CMP DDR write/read (S=0); not the adopted main path"),
    ("dual_1080p30_tight_1p0x", 2, 30, 1920, 1080, True,
     "variant: 20261025-180900 T08/T10 tight 1.0x layout, NOT this run's adopted main layout"),
    ("single_1080p30_main", 1, 30, 1920, 1080, True,
     "single-stream reference (one camera at 1080p30)"),
    ("dual_1600x900_30_main", 2, 30, 1600, 900, True,
     "primary recommendation geometry (1600x900@30, two cameras)"),
    ("dual_1080p20_main", 2, 20, 1920, 1080, True,
     "1080p at 20 fps, two cameras (P2's 25%-margin grid fps under the comp anchor)"),
    ("dual_960x540_30_main", 2, 30, 960, 540, True,
     "smallest 16:9 tier; one core time-sharing two streams meets G25 per stream"),
]


def ddr_rows(frozen, peak_MBps):
    exp = frozen["ddr"]["raw_slot_expansion"]
    doc = frozen["ddr"]["doc1_section8_GBps"]
    main = float(frozen["ddr"]["peak_MBps_main"])
    fb = float(frozen["ddr"]["peak_MBps_fallback"])
    out = []
    for (cid, st, fps, w, h, inc, note) in DDR_CASES:
        layout = "packed_1.0x_tight" if "tight" in cid else frozen["ddr"]["layout_main"]
        row = ddr_case(cid, st, fps, w, h, exp, inc, peak_MBps, note, layout=layout)
        total, gate = row["ddr_total_MBps"], row["ddr_gate_25_MBps"]
        row["peak_main_1333_MBps"] = main
        row["required_eff_1333_pct"] = total / main * 100.0
        row["gate_eff_1333_pct"] = gate / main * 100.0
        row["peak_fallback_1600_MBps"] = fb
        row["required_eff_1600_pct"] = total / fb * 100.0
        row["gate_eff_1600_pct"] = gate / fb * 100.0
        row["doc1_s8_1333_GBps"] = doc[1]
        row["doc1_s8_1600_GBps"] = doc[2]
        row["doc1_s8_reproducible"] = "false"
        row["labels"] = "ddr_total/gate=derived; peak_1333=derived formula; peak_1600=fallback tier"
        row["notes"] = (note + "; DOC-1 s8 states 1.2/2.33/3.4 GB/s (800E/1333/1600), which does not "
                        "follow from data_rate*width/8 and is disclosed, never adopted")
        out.append(row)
    return out


# ------------------------------------------------------------------------- UART model
def uart_numbers(frozen):
    u = frozen["uart"]
    payload = 40032
    measured_bytes = 40034          # P1 exp_bytes 160,136 / 4 frames
    frame_payload = frozen["frame"]["cmp_payload_bytes"]   # 2,594,706 B (worst stored payload)
    frame_total = frozen["frame"]["cmp_total_bytes"]       # +44 B A1U1 header
    real_bps = u["real_bps"]
    period = frozen["frame"]["frame_period_s"]
    serial_measured = measured_bytes * 10
    return {
        "real_bps": real_bps,
        "payload_bytes": payload,
        "export_bytes_measured": measured_bytes,
        "frame_payload_bytes": frame_payload,
        "frame_total_bytes": frame_total,
        "export_s_payload": payload / real_bps,
        "export_s_frame": frame_payload / real_bps,
        "export_s_frame_total": frame_total / real_bps,
        "payload_vs_period_x": (payload / real_bps) / period,
        "frame_vs_period_x": (frame_payload / real_bps) / period,
        "b11_sink_cycles_40032": payload * 10,
        "b11_sink_ms_40032": payload * 10 / (frozen["clock_hz"] / 1e3),
        "b6_sink_ms_40032": payload / u["b6_sim_sink_bytes_per_s"] * 1e3,
        "sim_sink_vs_real_x": u["b11_sim_sink_bytes_per_s"] / real_bps,
        "tail_measured_cycles": u["export_tail_measured_cycles"],
        "tail_ideal_cycles": u["export_cost_ideal_cycles"],
        "serial_cost_measured_cycles": serial_measured,
        "tail_excess_cycles": u["export_tail_measured_cycles"] - serial_measured,
        "tail_excess_vs_design_cycles": u["export_tail_measured_cycles"] - u["export_cost_ideal_cycles"],
        "sink_limited": u["sink_limited"],
        "transport": u["transport"],
    }


# ------------------------------------------------------------------- negative controls
def validate_anchor_use(anchor_id, use):
    """NC1: a cold single-frame latency may never be used as throughput/capacity."""
    if anchor_id == "A4" and use in ("throughput", "capacity", "gate"):
        raise ModelRejected("COLD_LATENCY_AS_THROUGHPUT")
    return True


def validate_verdict(gate0, gate25, verdict):
    """NC2: a G25 miss may never be collapsed into infeasible."""
    g0 = gate0 in (True, "pass", "meets_nominal")
    g25 = gate25 in (True, "pass", "meets_25")
    if g0 and not g25 and verdict == "infeasible":
        raise ModelRejected("GATE_COLLAPSE")
    if verdict == "feasible" and not g25:
        raise ModelRejected("FEASIBLE_BELOW_25")
    return True


def validate_peak(platform, peak_MBps_used, label=None):
    """NC3: a 1333 platform must not be quoted with the 1600 peak as the primary basis."""
    expected = {"ddr1333": 5332, "ddr1600": 6400}[platform]
    if abs(float(peak_MBps_used) - expected) > 1e-9 and label != "fallback_disclosed":
        raise ModelRejected("PEAK_MISMATCH")
    return True


def validate_sink(sink, claim):
    """NC4: a sim fast sink / real UART may never be a production realtime transport."""
    if claim == "production_realtime" and sink in ("sim_fast_b6", "sim_fast_b11", "uart_115200"):
        raise ModelRejected("SINK_MISMATCH")
    return True


def validate_per_stream_claim(cores, streams, capacity_used_MBps, basis_capacity_MBps,
                              demand_per_stream_MBps, claim=""):
    """NC5: a per-stream claim may never use aggregate 2C capacity."""
    limit = per_stream_capacity(basis_capacity_MBps, cores, streams)
    if capacity_used_MBps > limit + 1e-6:
        raise ModelRejected("AGGREGATE_CAPACITY_FOR_PER_STREAM")
    if claim == "feasible" and margin_0(capacity_used_MBps, demand_per_stream_MBps) < 0.25:
        raise ModelRejected("FEASIBLE_CLAIM_BELOW_PER_STREAM_GATE")
    return True


def validate_tier_applied(w, h, applies, robust_claimed=False):
    """NC6: 1080p must participate in the overhead-tier sensitivity."""
    if (w, h) == (1920, 1080) and applies is False:
        raise ModelRejected("TIER_NOT_APPLIED")
    if robust_claimed and applies is False:
        raise ModelRejected("TIER_NOT_APPLIED")
    return True


def validate_anchor_mix(cycles_anchor_id, demand_anchor_id):
    """Extra guard: numerator and denominator must come from the same anchor."""
    if cycles_anchor_id != demand_anchor_id:
        raise ModelRejected("CONTENT_ANCHOR_MIX")
    return True


# ---------------------------------------------------------------------------- rows
SCENARIO_COLS = [
    "scenario_id", "cores", "streams", "W", "H", "fps", "clock_mhz",
    "cycles_core_per_frame", "cycles_chain_per_frame", "chain_anchor_id",
    "content_label", "capacity_chain_MBps", "per_stream_capacity_chain_MBps",
    "demand_per_stream_MBps", "margin_chain_pct", "margin_gate25_pct",
    "gate_G0", "gate_G25", "verdict", "verdict_reason", "claim_status",
    "content_envelope", "drop_rate_lb_pct", "eram_bound", "eram_total",
    "eram_headroom", "resource_conservative_eram", "timing_status",
    "required_clock_0_mhz", "required_clock_25_mhz", "capacity_is_lower_bound",
    "notes",
]

ANCHOR_COLS = [
    "anchor_id", "name", "W", "H", "cycles_per_frame", "capacity_MBps",
    "fps_30_equiv", "demand_MBps", "margin_G0_pct", "margin_G25_pct",
    "gate_G0", "gate_G25", "label", "is_throughput_anchor", "notes",
]

GATE_MATRIX_COLS = [
    "anchor_id", "cores", "streams", "gate", "capacity_chain_MBps",
    "per_stream_capacity_chain_MBps", "demand_per_stream_MBps",
    "gate_demand_per_stream_MBps", "margin_vs_gate_pct", "gate_result",
    "margin_G0_pct", "margin_G25_pct", "row_verdict", "row_verdict_reason",
    "label", "claim_status", "notes",
]

OVERHEAD_COLS = [
    "scenario_id", "tier_cycles", "chain_anchor_id", "chain_source", "applies",
    "cores", "streams", "W", "H", "fps", "clock_mhz",
    "cycles_core_per_frame", "cycles_chain_per_frame", "capacity_chain_MBps",
    "per_stream_capacity_chain_MBps", "demand_per_stream_MBps",
    "margin_chain_pct", "margin_gate25_pct", "gate_G0", "gate_G25", "verdict",
    "claim_status", "tier_delta_from_primary_cycles", "tier_robust_G25",
    "notes",
]

DDR_COLS = [
    "case_id", "streams", "fps", "W", "H", "raw_write_MBps", "raw_read_MBps",
    "cmp_write_MBps", "cmp_read_MBps", "ddr_total_MBps", "ddr_gate_25_MBps",
    "peak_main_1333_MBps", "required_eff_1333_pct", "gate_eff_1333_pct",
    "peak_fallback_1600_MBps", "required_eff_1600_pct", "gate_eff_1600_pct",
    "includes_cmp_ddr", "layout", "doc1_s8_1333_GBps", "doc1_s8_1600_GBps",
    "doc1_s8_reproducible", "labels", "notes",
]

CORRECTION_COLS = [
    "id", "p2_claim", "p2_value", "p2_rule", "corrected_value",
    "corrected_rule", "impact_on_verdict", "evidence_path", "label",
]

FRONTIER_COLS = [
    "family", "cores", "streams", "W", "H", "fps", "clock_mhz",
    "chain_anchor_id", "capacity_chain_MBps", "per_stream_capacity_chain_MBps",
    "margin_chain_pct", "margin_gate25_pct", "gate_G0", "gate_G25",
    "worst_tier_margin_pct", "worst_tier_gate_G25", "verdict", "claim_status",
    "is_recommended", "notes",
]

FORMATS = {
    "cycles_core_per_frame": ".3f", "cycles_chain_per_frame": ".3f",
    "capacity_MBps": ".6f", "capacity_chain_MBps": ".6f",
    "per_stream_capacity_chain_MBps": ".6f", "demand_MBps": ".6f",
    "demand_per_stream_MBps": ".6f", "gate_demand_per_stream_MBps": ".6f",
    "margin_chain_pct": ".4f", "margin_gate25_pct": ".4f",
    "margin_G0_pct": ".4f", "margin_G25_pct": ".4f",
    "margin_vs_gate_pct": ".4f", "drop_rate_lb_pct": ".4f",
    "fps_30_equiv": ".6f", "fps": ".10g", "clock_mhz": ".10g",
    "required_clock_0_mhz": ".4f", "required_clock_25_mhz": ".4f",
    "worst_tier_margin_pct": ".4f",
    "raw_write_MBps": ".6f", "raw_read_MBps": ".6f", "cmp_write_MBps": ".6f",
    "cmp_read_MBps": ".6f", "ddr_total_MBps": ".6f", "ddr_gate_25_MBps": ".6f",
    "peak_main_1333_MBps": ".1f", "required_eff_1333_pct": ".4f",
    "gate_eff_1333_pct": ".4f", "peak_fallback_1600_MBps": ".1f",
    "required_eff_1600_pct": ".4f", "gate_eff_1600_pct": ".4f",
    "tier_cycles": ".10g",
}

INT_COLS = {
    "cores", "streams", "W", "H", "eram_total", "eram_headroom",
    "resource_conservative_eram", "tier_cycles", "tier_delta_from_primary_cycles",
}


def fmt_pct(x, nd=4):
    """Report/check formatting shared by render_report.py and check_outputs.py."""
    return ("+" if x >= 0 else "-") + format(abs(float(x)), ".%df" % nd) + "%"


def fmt_num(x, nd=4):
    return format(float(x), ".%df" % nd)


def fmt_int(x):
    return format(int(round(float(x))), ",d")


def fmt_cyc(x):
    x = float(x)
    if abs(x - round(x)) < 1e-9:
        return fmt_int(x)
    return format(x, ",.3f")


def cell(col, value):
    if col in FORMATS and isinstance(value, (int, float)) and not isinstance(value, bool):
        return format(float(value), FORMATS[col])
    if col in INT_COLS and isinstance(value, (int, float)) and not isinstance(value, bool):
        return str(int(round(value)))
    return str(value)


def _quote(text):
    if any(ch in text for ch in ',"\r\n'):
        return '"' + text.replace('"', '""') + '"'
    return text


def row_to_csv(row, cols):
    return ",".join(_quote(cell(c, row[c])) for c in cols)


def csv_text(rows, cols):
    return "\n".join([",".join(cols)] + [row_to_csv(r, cols) for r in rows]) + "\n"


def scenario_id(w, h, fps, cores, streams, clock_mhz):
    return "%dx%d-%sfps-c%ds%d-%sMHz" % (w, h, format(float(fps), ".10g"), cores, streams,
                                         format(float(clock_mhz), ".10g"))


def make_scenario_row(frozen, rules, w, h, fps, cores, streams, clock_mhz):
    raw = raw_bytes(w, h)
    cpb = frozen["core_anchors"]["comp"]["cycles_per_byte"]
    clock_hz = clock_mhz * MB
    cyc_core = raw * cpb
    cyc_chain = chain_cycles_for(frozen, w, h)
    cap = capacity_MBps(raw, cyc_chain, clock_hz)
    d = demand_MBps(raw, fps)
    ps = per_stream_capacity(cap, cores, streams)
    m0 = margin_0(ps, d)
    m25 = margin_25(ps, d)
    if cores == 1:
        res = frozen["resources"]["single_chain_b10_r1_routed"]
        eram_bound, eram_total = "single_chain_routed", res["eram_total"]
        eram_headroom, cons = res["eram_headroom"], res["eram_total"]
        timing_proven = clock_mhz <= frozen["timing"]["single_core_proven_max_mhz"]
    else:
        marg = frozen["resources"]["dual_marginal"]
        consr = frozen["resources"]["dual_conservative"]
        eram_bound, eram_total = "dual_marginal", marg["eram_total"]
        eram_headroom, cons = marg["eram_headroom"], consr["eram_total"]
        timing_proven = False
    verdict, reason = classify_row(frozen, rules, cores, streams, m0, m25,
                                   eram_total, cons, timing_proven)
    validate_verdict(gate_g0(ps, d), gate_g25(ps, d), verdict)
    if cores == 2 and verdict == "feasible":
        raise ModelRejected("DUAL_CORE_FEASIBLE")
    is_1080p = (w, h) == (frozen["frame"]["W"], frozen["frame"]["H"])
    if is_1080p:
        claim = "not_proven_all_content"
        envelope = "crosses_G0_A1pass_A2fail"
        notes = ("chain=A1_grad_ss measured (single smooth-content class, b11 geometry, sim-only 18.75 MB/s sink, "
                 "behavioral DDR); A2 comp extrapolation misses both gates -> content crossing; "
                 "export_tail=480,930 constant, sink_limited=false; per-stream only, not extrapolable to dual-stream/natural images")
    else:
        claim = "not_proven_all_content"
        envelope = "assumed_comp_anchor_single_class"
        notes = ("chain=cycles_core(comp)+%d affine (assumed; no full-frame comp measurement); "
                 "not a measured anchor" % frozen["overhead"]["primary_cycles"])
    if cores == 1 and streams == 2:
        notes += "; per-stream=C/2 (frame-level round robin, 1 core serves 2 streams); ERAM bound uses single-chain 187"
    elif cores == 2 and streams == 2:
        notes += "; per-stream=C (one frozen core per stream; 2C aggregate is NOT used); paaxi_shared_unproven=true; dual_core_capacity=assumed_from_single_core"
    elif cores == 2 and streams == 1:
        notes += "; per-stream=C (second core idle); paaxi_shared_unproven=true; dual_core_capacity=assumed_from_single_core"
    gate = frozen["gates"]["design_margin"]
    row = {
        "scenario_id": scenario_id(w, h, fps, cores, streams, clock_mhz),
        "cores": cores, "streams": streams, "W": w, "H": h,
        "fps": float(fps), "clock_mhz": float(clock_mhz),
        "cycles_core_per_frame": cyc_core,
        "cycles_chain_per_frame": cyc_chain,
        "chain_anchor_id": chain_anchor_id_for(frozen, w, h),
        "content_label": content_label_for(frozen, w, h),
        "capacity_chain_MBps": cap,
        "per_stream_capacity_chain_MBps": ps,
        "demand_per_stream_MBps": d,
        "margin_chain_pct": 100.0 * m0,
        "margin_gate25_pct": 100.0 * m25,
        "gate_G0": gate_g0(ps, d),
        "gate_G25": gate_g25(ps, d),
        "verdict": verdict,
        "verdict_reason": reason,
        "claim_status": claim,
        "content_envelope": envelope,
        "drop_rate_lb_pct": 100.0 * drop_rate_lb(ps, d),
        "eram_bound": eram_bound,
        "eram_total": eram_total,
        "eram_headroom": eram_headroom,
        "resource_conservative_eram": cons,
        "timing_status": "proven_at_187.5" if timing_proven else "unproven",
        "required_clock_0_mhz": required_clock_MHz(cyc_chain, fps, 0.0),
        "required_clock_25_mhz": required_clock_MHz(cyc_chain, fps, gate),
        "capacity_is_lower_bound": "false" if is_1080p else "n/a",
        "notes": notes,
    }
    return row


def scenario_rows(frozen, rules):
    """The frozen 43-row grid (same grid/order as the legacy P2 model, dedupe included)."""
    grid = rules["grid"]
    rows, seen = [], set()

    def add(w, h, fps, cores, streams, clock_mhz):
        key = (w, h, float(fps), cores, streams, float(clock_mhz))
        if key in seen:
            return
        seen.add(key)
        rows.append(make_scenario_row(frozen, rules, w, h, fps, cores, streams, clock_mhz))

    for (w, h) in grid["geometry_30fps"]:
        for cores in grid["cores"]:
            for streams in grid["streams"]:
                add(w, h, 30, cores, streams, frozen["clock_mhz"])
    for fps in grid["fps_1080p"]:
        for cores in grid["cores"]:
            add(1920, 1080, fps, cores, 2, frozen["clock_mhz"])
    for fps in grid["fps_1080p_single_core_single_stream"]:
        add(1920, 1080, fps, 1, 1, frozen["clock_mhz"])
    for clk in grid["clock_1080p30_mhz"]:
        add(1920, 1080, 30, 2, 2, clk)
    return rows


def anchor_rows(frozen):
    out = []
    for aid in ("A1", "A2", "A3", "A4"):
        a = frozen["anchors_1080p"][aid]
        m = anchor_metrics(frozen, aid)
        eligible = bool(a["is_throughput_anchor"])
        out.append({
            "anchor_id": aid,
            "name": a["name"],
            "W": frozen["frame"]["W"],
            "H": frozen["frame"]["H"],
            "cycles_per_frame": m["cycles_per_frame"],
            "capacity_MBps": m["capacity_MBps"],
            "fps_30_equiv": m["fps_30_equiv"],
            "demand_MBps": m["demand_MBps"],
            "margin_G0_pct": m["margin_0_pct"],
            "margin_G25_pct": m["margin_25_pct"],
            "gate_G0": m["gate_G0"] if eligible else "not_applicable",
            "gate_G25": m["gate_G25"] if eligible else "not_applicable",
            "label": a["label"],
            "is_throughput_anchor": "true" if eligible else "false",
            "notes": a["notes"] if eligible else "cold single-frame latency reference only; NOT a throughput anchor (NC1)",
        })
    return out


def gate_matrix_rows(frozen, rules):
    """4 core/stream combos x 3 throughput anchors x 2 gates = 24 rows."""
    raw = frozen["frame"]["raw_bytes"]
    d = demand_MBps(raw, frozen["frame"]["fps_target"])
    out = []
    for aid in ("A1", "A2", "A3"):
        m = anchor_metrics(frozen, aid)
        cap = m["capacity_MBps"]
        for cores in (1, 2):
            for streams in (1, 2):
                ps = per_stream_capacity(cap, cores, streams)
                m0, m25 = margin_0(ps, d), margin_25(ps, d)
                if cores == 1:
                    eram_total = frozen["resources"]["single_chain_b10_r1_routed"]["eram_total"]
                    cons = eram_total
                    timing_proven = True
                else:
                    eram_total = frozen["resources"]["dual_marginal"]["eram_total"]
                    cons = frozen["resources"]["dual_conservative"]["eram_total"]
                    timing_proven = False
                verdict, reason = classify_row(frozen, rules, cores, streams, m0, m25,
                                               eram_total, cons, timing_proven)
                for gate_name, gate_demand, mg in (
                        ("G0", d, m0), ("G25", 1.25 * d, m25)):
                    out.append({
                        "anchor_id": aid,
                        "cores": cores, "streams": streams,
                        "gate": gate_name,
                        "capacity_chain_MBps": cap,
                        "per_stream_capacity_chain_MBps": ps,
                        "demand_per_stream_MBps": d,
                        "gate_demand_per_stream_MBps": gate_demand,
                        "margin_vs_gate_pct": 100.0 * mg,
                        "gate_result": "pass" if mg >= 0.0 else "fail",
                        "margin_G0_pct": 100.0 * m0,
                        "margin_G25_pct": 100.0 * m25,
                        "row_verdict": verdict,
                        "row_verdict_reason": reason,
                        "label": frozen["anchors_1080p"][aid]["label"],
                        "claim_status": "not_proven_all_content" if aid == "A1" else "not_proven_all_content",
                        "notes": ("A1 measured single-content gradient" if aid == "A1"
                                  else ("A2 comp extrapolation, circular with A4 via the overhead definition"
                                        if aid == "A2" else "A3 rand extrapolation, optimistic bound")),
                    })
    return out


def overhead_rows(rows, frozen, rules):
    tiers = frozen["overhead"]["sensitivity_tiers"]
    anchor_tier = float(frozen["overhead"]["anchor_tier_cycles"])
    gate = frozen["gates"]["design_margin"]
    cpb = frozen["core_anchors"]["comp"]["cycles_per_byte"]
    out = []
    for r in rows:
        w, h = int(r["W"]), int(r["H"])
        fps, cores, streams = float(r["fps"]), int(r["cores"]), int(r["streams"])
        clk = float(r["clock_mhz"])
        raw = raw_bytes(w, h)
        is_1080p = (w, h) == (frozen["frame"]["W"], frozen["frame"]["H"])
        for tier in tiers:
            if is_1080p:
                cyc = tier_shift_1080p(frozen, tier)
                source, applies = "A1_grad_ss_tier_shift", "true"
                note = "1080p participates: S_ss + (tier - %d)" % int(anchor_tier)
            else:
                cyc = raw * cpb + float(tier)
                source, applies = "affine_comp", "true"
                note = "cycles_core(comp) + tier"
            validate_tier_applied(w, h, applies == "true")
            cap = capacity_MBps(raw, cyc, clk * MB)
            ps = per_stream_capacity(cap, cores, streams)
            d = demand_MBps(raw, fps)
            m0, m25 = margin_0(ps, d), margin_25(ps, d)
            if cores == 1:
                et = frozen["resources"]["single_chain_b10_r1_routed"]["eram_total"]
                cons = et
                timing = clk <= frozen["timing"]["single_core_proven_max_mhz"]
            else:
                et = frozen["resources"]["dual_marginal"]["eram_total"]
                cons = frozen["resources"]["dual_conservative"]["eram_total"]
                timing = False
            verdict, reason = classify_row(frozen, rules, cores, streams,
                                           m0, m25, et, cons, timing)
            out.append({
                "scenario_id": r["scenario_id"],
                "tier_cycles": tier,
                "chain_anchor_id": r["chain_anchor_id"] + ("_tier" if is_1080p else ""),
                "chain_source": source,
                "applies": applies,
                "cores": cores, "streams": streams, "W": w, "H": h,
                "fps": fps, "clock_mhz": clk,
                "cycles_core_per_frame": raw * cpb,
                "cycles_chain_per_frame": cyc,
                "capacity_chain_MBps": cap,
                "per_stream_capacity_chain_MBps": ps,
                "demand_per_stream_MBps": d,
                "margin_chain_pct": 100.0 * m0,
                "margin_gate25_pct": 100.0 * m25,
                "gate_G0": gate_g0(ps, d),
                "gate_G25": gate_g25(ps, d),
                "verdict": verdict,
                "claim_status": r["claim_status"],
                "tier_delta_from_primary_cycles": int(round(float(tier) - anchor_tier)),
                "tier_robust_G25": "",  # filled below
                "notes": note,
            })
    # mark per-scenario tier robustness
    by_id = {}
    for row in out:
        by_id.setdefault(row["scenario_id"], []).append(row)
    for sid, group in by_id.items():
        robust = all(g["gate_G25"] == "pass" for g in group)
        for g in group:
            g["tier_robust_G25"] = "true" if robust else "false"
    return out


# --------------------------------------------------------------------- corrections
def corrections_rows(frozen):
    a1 = anchor_metrics(frozen, "A1")
    a2 = anchor_metrics(frozen, "A2")
    a3 = anchor_metrics(frozen, "A3")
    t0 = capacity_from_cycles(tier_shift_1080p(frozen, 0), frozen["clock_hz"])
    t1 = capacity_from_cycles(tier_shift_1080p(frozen, 1000000), frozen["clock_hz"])
    d = demand_MBps(frozen["frame"]["raw_bytes"], 30)
    u = uart_numbers(frozen)
    ddr5332 = ddr_case("main", 2, 30, 1920, 1080, 1.6, True, 5332, "")
    ddr6400 = ddr_case("main", 2, 30, 1920, 1080, 1.6, True, 6400, "")
    return [
        {
            "id": "C1", "p2_claim": "1080p30 chain capacity = cold single-frame latency 6,421,414 cycles",
            "p2_value": "75.684 MB/s / 29.199 fps / margin -2.6694% / verdict infeasible",
            "p2_rule": "R2 uses the b6 one-frame cold completion time as the per-frame service time",
            "corrected_value": "A1 measured steady-state S_ss=4,677,535 cycles -> 103.9009 MB/s / 40.0852 fps / G0 +33.6174% / G25 +6.8939%",
            "corrected_rule": "steady-state frame interval S_ss=(S_23+S_34)/2, never L_cold; startup_pct=44.66%",
            "impact_on_verdict": "G0 -2.6694% -> +33.6174%; G25 -22.1355% -> +6.8939% (A1 content basis)",
            "evidence_path": "T10.ss-steady-anchor/r0/out/steady-state.json (a0945e1f...); out/steady-state.md",
            "label": "measured",
        },
        {
            "id": "C2", "p2_claim": "0% nominal and the 25% design margin are one verdict",
            "p2_value": "chain margin < 0 -> infeasible; 25% folded into the same word",
            "p2_rule": "R2/R5 collapse nominal and design margin",
            "corrected_value": "two separate gates G0 (0%) and G25 (1.25x); below_25 -> conditional, never infeasible",
            "corrected_rule": "rules row_verdict_rules V2/V4; GATE_COLLAPSE is a negative control (NC2)",
            "impact_on_verdict": "1080p30 A1 passes both gates; A2 misses both; headline decided by the content envelope, not by the 25% gate",
            "evidence_path": "out/scenarios.csv (1080p30 c1s1 row); out/gate-matrix.csv",
            "label": "derived",
        },
        {
            "id": "C3", "p2_claim": "DDR peak = 6,400 MB/s (x32 @1600)",
            "p2_value": "required_eff 12.6412% / gate_eff 15.8014%",
            "p2_rule": "ddr peak_MBps=6400 as the primary basis",
            "corrected_value": "mainline DDR1333 = 5,332 MB/s (1333 MT/s x 32 bit / 8): required_eff 15.1732% / gate_eff 18.9665%; 6,400 kept as a labelled fallback column",
            "corrected_rule": "peak_main=5332, fallback=6400; PEAK_MISMATCH is NC3",
            "impact_on_verdict": "average bandwidth is still not the bottleneck (15.17% of peak; gate 18.97%), but DDR sustained/arbitration stays unproven",
            "evidence_path": "out/ddr-budget.csv; docs/DDR1333集成与1333vs1600对比_2026-10-17.md (3f273ee4...)",
            "label": "derived",
        },
        {
            "id": "C4", "p2_claim": "1080p is a fixed anchor and does not take part in the overhead tiers",
            "p2_value": "overhead-sensitivity applies=false for 1080p; identical values in all three tiers",
            "p2_rule": "overhead_sensitivity anchor_note: 1080p tier does not apply",
            "corrected_value": "1080p cycles(tier)=S_ss+(tier-426,385): tier0 4,251,150 (G25 +17.6154%), primary 4,677,535 (+6.8939%), 1e6 5,251,150 (-4.7827%)",
            "corrected_rule": "1080p participates via tier-shift; TIER_NOT_APPLIED is NC6",
            "impact_on_verdict": "1080p30 is not tier-robust at 25%: it only passes in the 0 and primary tiers",
            "evidence_path": "out/overhead-sensitivity.csv (1080p rows)",
            "label": "assumed",
        },
        {
            "id": "C5", "p2_claim": "chain anchor exported through UART; production path implied",
            "p2_value": "no qualification of the sink; export cost not separated from the frame interval",
            "p2_rule": "full_grad anchor described as UART export without a transport label",
            "corrected_value": "sim-only sink 18.75 MB/s (UART_DIV=1, clk_uart=clk_a1); real 115200 = 11,520 B/s -> 3.475 s per 40,032 B (104.2x frame period) and 225.235 s per 2,594,750 B (6,757x); export_tail=480,930 cycles constant, sink_limited=false",
            "corrected_rule": "constant tail cancels in S_ss and is not subtracted; transport=not_proven; SINK_MISMATCH is NC4",
            "impact_on_verdict": "1080p30 realtime is only claimed up to the CMP slot/fast sink; a real UART cannot carry the stream",
            "evidence_path": "out/scenarios.csv notes; verdict-r1.md Q5; docs/项目成果整合与进度复核_2026-10-25.md (2bec1a83...)",
            "label": "measured",
        },
        {
            "id": "C6", "p2_claim": "overhead 426,385 cycles is an independent measured quantity and A2 is a second full-frame anchor",
            "p2_value": "overhead := 6,421,414 - 5,995,029.375; A2 = 6,421,414.375",
            "p2_rule": "overhead anchor_implied = 426,384.625 treated as measured",
            "corrected_value": "overhead is assumed/definitional and circular with A4 (A2 differs from A4 by 0.375 cycle); only the tier difference is used",
            "corrected_rule": "A2 label=assumed; A4 label=measured_but_not_throughput; circularity disclosed",
            "impact_on_verdict": "A2 may bound the content envelope but may never be quoted as independent evidence for 6.42M",
            "evidence_path": "out/content-anchors.csv (A2/A4 rows); verdict-r1.md Q1/Q2",
            "label": "assumed",
        },
        {
            "id": "C7", "p2_claim": "dual-core rows are evaluated with per-stream C but the report reads like 2C",
            "p2_value": "c2s1/c2s2 both C; aggregate 2xC_core=162.13 MB/s quoted",
            "p2_rule": "capacity_rules 2core_2streams=C",
            "corrected_value": "c2s2 per-stream = C (assumed_from_single_core); paaxi_shared_unproven=true; dual-core headline capped at not_proven",
            "corrected_rule": "dual_core_rules; AGGREGATE_CAPACITY_FOR_PER_STREAM is NC5; DUAL_CORE_FEASIBLE forbidden",
            "impact_on_verdict": "no dual-core row can be feasible; 2C is only used for DDR/total volume",
            "evidence_path": "out/gate-matrix.csv (c2s1/c2s2 rows); out/scenarios.csv",
            "label": "assumed",
        },
        {
            "id": "C8", "p2_claim": "content coverage is one class (comp strip treated as the 1080p core anchor)",
            "p2_value": "content-sensitivity 3 rows; no content envelope / no claim_status",
            "p2_rule": "core_basis=comp fixed vector only",
            "corrected_value": "content envelope A1 (grad measured) / A2 (comp extrapolated, assumed) / A3 (rand, optimistic); claim_status=not_proven_all_content on every row",
            "corrected_rule": "content_anchors + claim_status separate from the row verdict",
            "impact_on_verdict": "1080p30 headline = not_proven (A1 crosses A2); natural images/low light/noise remain unproven",
            "evidence_path": "out/content-anchors.csv; out/gate-matrix.csv; verdict-r1.md headline",
            "label": "assumed",
        },
        {
            "id": "C9", "p2_claim": "frontier: 1080p30 fails_30; 25% max 23.36 fps; required clock 240.803 MHz; primary 1600x900",
            "p2_value": "1080p 25% max fps 23.359 (A2), f_req_25 240.803 MHz, 1080p30 infeasible",
            "p2_rule": "frontier/recommendation derived from the cold-latency anchor",
            "corrected_value": "A1: 25% max 32.068 fps, f_req_25 175.408 MHz; A2: 23.359 fps / 240.803 MHz; primary stays the comp-basis 1600x900 (content-basis consistency), robust alternate 1440x810, alt2 960x540 1c2s; 1080p30 listed separately as measured-content-only / not_proven_all_content",
            "corrected_rule": "recommendation_rules content_basis_consistency; A1 may not displace comp-basis rows unless A2 also passes G25",
            "impact_on_verdict": "1080p30 is neither a primary recommendation nor declared infeasible: it is not_proven across content",
            "evidence_path": "out/frontier.csv; verdict-r1.md section 6",
            "label": "derived",
        },
    ]


# --------------------------------------------------------------------- frontier / rec
def _row_lookup(rows, w, h, fps, cores, streams, clock=187.5):
    for r in rows:
        if (int(r["W"]), int(r["H"]), float(r["fps"]), int(r["cores"]), int(r["streams"]),
                float(r["clock_mhz"])) == (w, h, float(fps), cores, streams, float(clock)):
            return r
    return None


def _anchor_row(frozen, rules, anchor_id, w, h, fps, cores, streams):
    """Row computed from an explicit 1080p anchor (A2/A3 envelope rows, not grid rows)."""
    raw = raw_bytes(w, h)
    cyc = anchor_cycles(frozen, anchor_id)
    cap = capacity_MBps(raw, cyc, frozen["clock_hz"])
    d = demand_MBps(raw, fps)
    ps = per_stream_capacity(cap, cores, streams)
    m0, m25 = margin_0(ps, d), margin_25(ps, d)
    return {
        "anchor_id": anchor_id,
        "W": w, "H": h, "fps": float(fps), "cores": cores, "streams": streams,
        "clock_mhz": frozen["clock_mhz"], "cycles": cyc,
        "capacity_chain_MBps": cap, "per_stream_capacity_chain_MBps": ps,
        "demand_per_stream_MBps": d,
        "margin_chain_pct": 100.0 * m0, "margin_gate25_pct": 100.0 * m25,
        "gate_G0": gate_g0(ps, d), "gate_G25": gate_g25(ps, d),
    }


def worst_tier_margin(overhead, scenario_id_):
    vals = [r["margin_chain_pct"] for r in overhead if r["scenario_id"] == scenario_id_]
    return min(vals) if vals else float("nan")


def recommendations(rows, frozen, overhead):
    """Primary + <=2 alternates, content-basis consistent (comp-affine only)."""
    comp = [r for r in rows if r["chain_anchor_id"] == "affine_comp_tier"]
    elig = [r for r in comp if float(r["fps"]) == 30.0 and r["gate_G25"] == "pass"
            and r["verdict"] in ("feasible", "conditional")]
    elig.sort(key=lambda r: (-int(r["W"]) * int(r["H"]), int(r["cores"]), int(r["streams"])))
    primary = elig[0] if elig else None
    robust = [r for r in comp if float(r["fps"]) == 30.0 and int(r["cores"]) == 1
              and int(r["streams"]) == 1 and r["gate_G25"] == "pass"
              and worst_tier_margin(overhead, r["scenario_id"]) >= 25.0]
    robust.sort(key=lambda r: (-int(r["W"]) * int(r["H"]), r["scenario_id"]))
    alt1 = robust[0] if robust else None
    c1s2 = [r for r in comp if float(r["fps"]) == 30.0 and int(r["cores"]) == 1
            and int(r["streams"]) == 2 and r["gate_G25"] == "pass"
            and worst_tier_margin(overhead, r["scenario_id"]) >= 25.0]
    c1s2.sort(key=lambda r: (-int(r["W"]) * int(r["H"]), r["scenario_id"]))
    alt2 = c1s2[0] if c1s2 else None
    alts = []
    for r in (alt1, alt2):
        if r is not None and (primary is None or r["scenario_id"] != primary["scenario_id"]) \
                and r["scenario_id"] not in [a["scenario_id"] for a in alts]:
            alts.append(r)
    if len(alts) > 2:
        alts = alts[:2]
    return primary, alts


def nominal_only_rows(rows):
    return [r for r in rows if r["gate_G0"] == "pass" and r["gate_G25"] == "fail"]


def frontier_rows(rows, frozen, rules, overhead):
    primary, alts = recommendations(rows, frozen, overhead)
    alt_ids = {r["scenario_id"] for r in alts}
    prim_id = primary["scenario_id"] if primary else None
    out = []

    def add(family, r, anchor_id, recommended, note, verdict=None, claim="not_proven_all_content"):
        out.append({
            "family": family,
            "cores": r["cores"], "streams": r["streams"], "W": r["W"], "H": r["H"],
            "fps": r["fps"], "clock_mhz": r["clock_mhz"],
            "chain_anchor_id": anchor_id,
            "capacity_chain_MBps": r["capacity_chain_MBps"],
            "per_stream_capacity_chain_MBps": r["per_stream_capacity_chain_MBps"],
            "margin_chain_pct": r["margin_chain_pct"],
            "margin_gate25_pct": r["margin_gate25_pct"],
            "gate_G0": r["gate_G0"], "gate_G25": r["gate_G25"],
            "worst_tier_margin_pct": (worst_tier_margin(overhead, r["scenario_id"])
                                      if r.get("scenario_id") else r["margin_chain_pct"]),
            "worst_tier_gate_G25": "",
            "verdict": verdict if verdict else r.get("verdict", ""),
            "claim_status": claim,
            "is_recommended": "true" if recommended else "false",
            "notes": note,
        })

    # A1 measured anchor boundary rows
    r30 = _row_lookup(rows, 1920, 1080, 30, 1, 1)
    r25 = _row_lookup(rows, 1920, 1080, 25, 1, 1)
    r20 = _row_lookup(rows, 1920, 1080, 20, 1, 1)
    r30_2s = _row_lookup(rows, 1920, 1080, 30, 2, 2)
    add("1080p_A1_measured", r30, "A1_grad_ss", False,
        "max nominal fps on the measured gradient anchor; meets G0+G25 but claim_status=not_proven_all_content (A2 misses both)")
    add("1080p_A1_measured", r25, "A1_grad_ss", False,
        "next grid fps down; still G25 on A1; f_req_25 %.3f MHz" % float(r25["required_clock_25_mhz"]))
    add("1080p_A1_measured", r30_2s, "A1_grad_ss", False,
        "dual-core 1080p30: per-stream C (assumed_from_single_core) meets both gates arithmetically, but dual_core/PAXI unproven -> conditional and headline not_proven; never feasible")

    # A2 comp envelope boundary rows (not grid rows)
    a2_30 = _anchor_row(frozen, rules, "A2", 1920, 1080, 30, 1, 1)
    a2_20 = _anchor_row(frozen, rules, "A2", 1920, 1080, 20, 1, 1)
    a2_15 = _anchor_row(frozen, rules, "A2", 1920, 1080, 15, 1, 1)
    add("1080p_A2_comp_envelope", a2_30, "A2_comp_assumed", False,
        "conservative content envelope at 30 fps: misses G0 and G25 -> content crossing vs A1",
        verdict="content_envelope_only")
    add("1080p_A2_comp_envelope", a2_20, "A2_comp_assumed", False,
        "highest grid fps under the comp envelope still misses G25 (max 25%% fps %.3f)" %
        max_fps(anchor_cycles(frozen, "A2"), frozen["clock_hz"], 0.25),
        verdict="content_envelope_only")
    add("1080p_A2_comp_envelope", a2_15, "A2_comp_assumed", False,
        "first grid fps meeting G25 under the comp envelope", verdict="content_envelope_only")

    # 30 fps resolution family (comp basis)
    r1728 = _row_lookup(rows, 1728, 972, 30, 1, 1)
    r1600 = _row_lookup(rows, 1600, 900, 30, 1, 1)
    r1440 = _row_lookup(rows, 1440, 810, 30, 1, 1)
    r1280 = _row_lookup(rows, 1280, 720, 30, 1, 1)
    r960 = _row_lookup(rows, 960, 540, 30, 1, 2)
    r1152 = _row_lookup(rows, 1152, 648, 30, 1, 2)
    add("30fps_res_comp", r1728, "affine_comp_tier", False,
        "largest tier above the primary that still misses G25 (nominal-only); required clock %.3f MHz" %
        float(r1728["required_clock_25_mhz"]))
    add("30fps_res_comp", r1600, "affine_comp_tier", r1600["scenario_id"] == prim_id,
        "primary recommendation: largest 30 fps comp-basis geometry meeting G25 at the primary tier; "
        "conservative tier 1e6 falls to %.4f%% (below 25%%) -> primary feasible / conservative conditional" %
        worst_tier_margin(overhead, r1600["scenario_id"]))
    add("30fps_res_comp", r1440, "affine_comp_tier", r1440["scenario_id"] in alt_ids,
        "robust alternate: largest 30 fps single-core/single-stream tier meeting G25 in all three tiers (worst %.4f%%)" %
        worst_tier_margin(overhead, r1440["scenario_id"]))
    add("30fps_res_comp", r1280, "affine_comp_tier", False,
        "next tier down, also tier-robust (worst %.4f%%)" % worst_tier_margin(overhead, r1280["scenario_id"]))
    add("30fps_res_comp_1c2s", r960, "affine_comp_tier", r960["scenario_id"] in alt_ids,
        "alt2: one core time-sharing two 30 fps streams still meets G25 per stream in all tiers (worst %.4f%%)" %
        worst_tier_margin(overhead, r960["scenario_id"]))
    add("30fps_res_comp_1c2s", r1152, "affine_comp_tier", False,
        "next tier up fails G25 at the conservative tier (worst %.4f%%)" %
        worst_tier_margin(overhead, r1152["scenario_id"]))

    # core-only upper bound (never a system basis)
    cpb = frozen["core_anchors"]["comp"]["cycles_per_byte"]
    core_30 = raw_bytes(1920, 1080) * cpb
    core_cap = capacity_from_cycles(core_30, frozen["clock_hz"])
    ps = per_stream_capacity(core_cap, 1, 1)
    d = demand_MBps(2592000, 30)
    out.append({
        "family": "core_only_comp_upper_bound", "cores": 1, "streams": 1,
        "W": 1920, "H": 1080, "fps": 30, "clock_mhz": frozen["clock_mhz"],
        "chain_anchor_id": "core_only_comp", "capacity_chain_MBps": core_cap,
        "per_stream_capacity_chain_MBps": ps,
        "margin_chain_pct": 100.0 * margin_0(ps, d),
        "margin_gate25_pct": 100.0 * margin_25(ps, d),
        "gate_G0": gate_g0(ps, d), "gate_G25": gate_g25(ps, d),
        "worst_tier_margin_pct": 100.0 * margin_0(ps, d),
        "worst_tier_gate_G25": gate_g25(ps, d),
        "verdict": "core_only_upper_bound", "claim_status": "not_proven_all_content",
        "is_recommended": "false",
        "notes": "core-only is an optimistic upper bound that ignores DDR/export and the chain; it is never a system basis",
    })
    for r in out:
        if r["worst_tier_gate_G25"] == "":
            r["worst_tier_gate_G25"] = ("pass" if r["worst_tier_margin_pct"] >= 25.0 else "fail")
    return out
