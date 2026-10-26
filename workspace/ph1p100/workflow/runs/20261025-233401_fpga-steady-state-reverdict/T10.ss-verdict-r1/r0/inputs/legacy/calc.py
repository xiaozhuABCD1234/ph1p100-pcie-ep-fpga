"""Pure-function service-rate / DDR / resource model for T10.dual-aplus-service-verdict.

No file I/O, no randomness, no network, no clock reads.  Every function is a pure
function of its arguments; the frozen constants live in inputs/frozen-inputs.json and
the decision rules live in model/rules.json.  The model never stores a final answer:
verdicts are produced by classify() from computed margins and resource totals.

Units: MB = 10^6 bytes (decimal); MHz/Hz as named; percentages are fractions in the
Python API and are multiplied by 100 only in the CSV formatting layer.
"""
from math import ceil

PROFILE_OK = "RAW10_packed_20B32B"


class ModelRejected(Exception):
    """Raised by the validators used by the negative controls."""


# --------------------------------------------------------------------------- geometry
def check_geometry(w, h):
    if not isinstance(w, int) or not isinstance(h, int):
        raise ValueError("W/H must be integers")
    if w <= 0 or h <= 0:
        raise ValueError("W/H must be positive")
    # RAW10 packing needs whole 5-byte groups per row: W must be a multiple of 4.
    # H itself does not need to be a multiple of 4 (1440x810 is a frozen tier: 810 is not
    # divisible by 4 but W*5/4 = 1800 B stride and W*H/4 groups are integers).
    if w % 4:
        raise ValueError("W must be a multiple of 4 (one 5-byte group per 4 pixels)")
    if (w * h) % 4:
        raise ValueError("W*H must be divisible by 4")


def pixels(w, h):
    check_geometry(w, h)
    return w * h


def raw_bytes(w, h):
    return pixels(w, h) * 5 // 4


def groups(w, h):
    return pixels(w, h) // 4


def raw_slot_words(w, h):
    groups_per_word = 4
    return int(ceil(groups(w, h) / groups_per_word))


def raw_slot_bytes(w, h):
    return raw_slot_words(w, h) * 32


def raw_slot_expansion(w, h):
    return raw_slot_bytes(w, h) / raw_bytes(w, h)


def content_bytes(w, h, header=128):
    return raw_bytes(w, h) + header


def dma_bytes(w, h, align=4096):
    c = content_bytes(w, h)
    return ((c + align - 1) // align) * align


def cmp_payload_bytes(w, h):
    return raw_bytes(w, h) + 5 * int(ceil(h / 2)) + 6


def cmp_total_bytes(w, h, header=44):
    return cmp_payload_bytes(w, h) + header


# --------------------------------------------------------------------------- rates
def cycles_per_byte(nbytes, cycles):
    if nbytes <= 0 or cycles <= 0:
        raise ValueError("bytes/cycles must be positive")
    return cycles / nbytes


def capacity_MBps(nbytes, cycles, clock_hz):
    if nbytes <= 0 or cycles <= 0 or clock_hz <= 0:
        raise ValueError("bytes/cycles/clock must be positive")
    return nbytes * clock_hz / cycles / 1e6


def capacity_from_cpb(cpb, clock_hz):
    if cpb <= 0 or clock_hz <= 0:
        raise ValueError("cpb/clock must be positive")
    return clock_hz / cpb / 1e6


def demand_MBps(nbytes, fps):
    if nbytes <= 0:
        raise ValueError("bytes must be positive")
    if fps <= 0:
        raise ValueError("fps must be positive")
    return nbytes * fps / 1e6


def per_stream_capacity(cap_MBps, cores, streams):
    if cores not in (1, 2) or streams not in (1, 2):
        raise ValueError("cores/streams must be 1 or 2")
    # 1 core serving 2 streams: frame-level round robin -> long-run 50% each.
    # 2 cores / 2 streams: one frozen core per stream -> C (never 2C).
    # 2 cores / 1 stream: second core idle -> C.
    return cap_MBps / 2.0 if (cores == 1 and streams == 2) else cap_MBps


def margin(cap_MBps, demand_MBps_):
    if demand_MBps_ <= 0:
        raise ValueError("demand must be positive")
    return cap_MBps / demand_MBps_ - 1.0


def required_clock_hz(cycles_per_frame, fps, margin_frac):
    if cycles_per_frame <= 0 or fps <= 0:
        raise ValueError("cycles/fps must be positive")
    return cycles_per_frame * fps * (1.0 + margin_frac)


def max_fps(cycles_per_frame, clock_hz, margin_frac=0.0):
    if cycles_per_frame <= 0 or clock_hz <= 0:
        raise ValueError("cycles/clock must be positive")
    return clock_hz / (cycles_per_frame * (1.0 + margin_frac))


def chain_cycles_for(w, h, cpb, overhead):
    return raw_bytes(w, h) * cpb + overhead


def max_pixels_for(clock_hz, cpb, overhead, fps, margin_frac, bytes_per_px=1.25):
    """Largest pixel count whose per-stream capacity meets fps*(1+margin)."""
    if cpb <= 0 or clock_hz <= 0 or fps <= 0 or bytes_per_px <= 0:
        raise ValueError("invalid model input")
    # capacity = px*bpc*clock/(px*bpc*cpb+overhead)  (MB/s)
    # requirement: capacity >= fps*bpc*px*(1+m)/1e6  ->  clock/(fps*(1+m)) >= px*bpc*cpb+overhead
    budget = clock_hz / (fps * (1.0 + margin_frac))  # cycles per frame, in cycles
    px = (budget - overhead) / (bytes_per_px * cpb)
    return px


def snap_tier(px, tiers):
    """Largest 16:9 tier whose pixel count does not exceed px (None if none fits)."""
    best = None
    for w, h in tiers:
        if w * h <= px + 1e-9:
            if best is None or w * h > best[0] * best[1]:
                best = (w, h)
    return best


def drop_rate_lb(cap_MBps, demand_MBps_):
    if demand_MBps_ <= 0:
        raise ValueError("demand must be positive")
    return max(0.0, 1.0 - cap_MBps / demand_MBps_)


# --------------------------------------------------------------------------- verdict
def gate_status(margin_frac, gate):
    if margin_frac >= gate:
        return "meets_25"
    if margin_frac >= 0.0:
        return "below_25"
    return "fails_30"


def classify(cores, margin_chain, marginal_eram, conservative_eram, timing_proven, rules):
    """Mechanical application of rules.json verdict_rules R1..R5 (R6 needs the grid)."""
    th = rules["thresholds"]
    eram_device = th["eram_device"]
    gate = th["design_margin"]
    if marginal_eram > eram_device:
        return "infeasible", "R1: marginal ERAM %d > %d" % (marginal_eram, eram_device)
    if margin_chain < 0.0:
        return "infeasible", "R2: per-stream full-chain margin %.2f%% < 0" % (100.0 * margin_chain)
    if cores == 2 and not timing_proven:
        return "conditional", "R3: dual-core Routed timing unproven"
    if margin_chain >= gate and conservative_eram <= th["eram_fit_pass_max"] and timing_proven:
        return "feasible", ("R4: chain %.2f%% >= 25%%, conservative ERAM %d <= 270, timing proven"
                            % (100.0 * margin_chain, conservative_eram))
    if margin_chain >= gate:
        # would be feasible except for the resource/timing bound
        return "conditional", ("R5: chain %.2f%% but conservative ERAM %d > 270/300 or timing unproven"
                               % (100.0 * margin_chain, conservative_eram))
    return "conditional", "R5: per-stream full-chain margin %.2f%% in [0,25)" % (100.0 * margin_chain)


def grid_not_viable(rows):
    return not any(float(r["fps"]) == 30 and _margin_frac(r) >= 0.0 for r in rows)


# --------------------------------------------------------------------------- DDR
def ddr_case(case_id, streams, fps, w, h, expansion, include_cmp, peak_MBps, notes,
             layout="20B_payload_per_32B_word"):
    raw = raw_bytes(w, h)
    d_total = raw * fps * streams / 1e6
    rw = d_total * expansion
    rr = rw
    sw = cmp_total_bytes(w, h) * fps * streams / 1e6 if include_cmp else 0.0
    sr = sw
    total = rw + rr + sw + sr
    gate = total * 1.25
    return {
        "case_id": case_id,
        "streams": streams,
        "fps": float(fps),
        "raw_write_MBps": rw,
        "raw_read_MBps": rr,
        "cmp_write_MBps": sw,
        "cmp_read_MBps": sr,
        "ddr_total_MBps": total,
        "ddr_gate_25_MBps": gate,
        "required_eff_pct": total / peak_MBps * 100.0,
        "peak_GBps": peak_MBps / 1000.0,
        "includes_cmp_ddr": "true" if include_cmp else "false",
        "notes": notes,
        "W": w,
        "H": h,
        "layout": layout,
        "sustained_eff_at_gate_pct": gate / peak_MBps * 100.0,
    }


# --------------------------------------------------------------------------- validators (negative controls)
def validate_packing(profile, w, h, raw_in, slot_in):
    """NEG-01: reject RAW12 / 1.0x slots and any non-frozen packing profile."""
    if profile != PROFILE_OK:
        raise ModelRejected("PACKING_PROFILE_REJECTED")
    if raw_in != raw_bytes(w, h) or slot_in != raw_slot_bytes(w, h):
        raise ModelRejected("PACKING_MISMATCH")
    return slot_in


def validate_per_stream_claim(cores, streams, capacity_used_MBps, basis_capacity_MBps,
                              demand_per_stream_MBps, claim, rules):
    """NEG-02: a per-stream claim may never use the aggregate 2C capacity."""
    cap_limit = per_stream_capacity(basis_capacity_MBps, cores, streams)
    if capacity_used_MBps > cap_limit + 1e-6:
        raise ModelRejected("AGGREGATE_CAPACITY_FOR_PER_STREAM")
    m = margin(capacity_used_MBps, demand_per_stream_MBps)
    if claim == "feasible" and m < rules["thresholds"]["design_margin"]:
        raise ModelRejected("FEASIBLE_CLAIM_BELOW_PER_STREAM_GATE")
    return m


def validate_resource_stage(stage):
    """NEG-03: only routed reports may be used for the resource fit."""
    if stage != "routed":
        raise ModelRejected("STAGE_MIX_SYNTH_IN_FIT")
    return True


# --------------------------------------------------------------------------- builders
SCENARIO_COLS = [
    "scenario_id", "cores", "streams", "W", "H", "fps", "clock_mhz",
    "cycles_core_per_frame", "cycles_chain_per_frame", "overhead_assumption",
    "capacity_core_MBps", "capacity_chain_MBps", "demand_per_stream_MBps",
    "margin_core_pct", "margin_chain_pct", "gate_25_core", "gate_25_chain",
    "drop_rate_lb_pct", "eram_bound", "eram_total", "eram_headroom",
    "verdict", "gate_status", "notes",
    "drop_rate_lb_basis", "per_stream_capacity_core_MBps", "per_stream_capacity_chain_MBps",
    "resource_conservative_eram", "timing_status", "verdict_reason",
    "required_clock_chain_25_mhz", "required_clock_core_25_mhz", "required_clock_chain_0_mhz",
]

CONTENT_COLS = [
    "case_id", "content_class", "basis", "W", "H", "bytes", "cycles", "clock_mhz",
    "capacity_MBps", "fps_1080p_equivalent", "demand_at_30_MBps", "margin_pct",
    "gate_25", "label", "notes",
]

DDR_COLS = [
    "case_id", "streams", "fps", "raw_write_MBps", "raw_read_MBps",
    "cmp_write_MBps", "cmp_read_MBps", "ddr_total_MBps", "ddr_gate_25_MBps",
    "required_eff_pct", "peak_GBps", "includes_cmp_ddr", "notes",
    "W", "H", "layout", "sustained_eff_at_gate_pct",
]

FRONTIER_COLS = [
    "family", "cores", "streams", "W", "H", "fps", "clock_mhz", "capacity_basis",
    "margin_pct", "margin_chain_pct", "margin_core_pct", "gate_25",
    "required_clock_chain_25_mhz", "required_clock_core_25_mhz",
    "worst_tier_margin_pct", "worst_tier_gate", "verdict", "is_recommended", "notes",
]

FORMATS = {
    "cycles_core_per_frame": ".3f", "cycles_chain_per_frame": ".3f",
    "capacity_core_MBps": ".6f", "capacity_chain_MBps": ".6f",
    "demand_per_stream_MBps": ".6f",
    "margin_core_pct": ".4f", "margin_chain_pct": ".4f", "drop_rate_lb_pct": ".4f",
    "per_stream_capacity_core_MBps": ".6f", "per_stream_capacity_chain_MBps": ".6f",
    "fps": ".10g", "clock_mhz": ".10g",
    "capacity_MBps": ".6f", "fps_1080p_equivalent": ".6f", "demand_at_30_MBps": ".6f",
    "margin_pct": ".4f",
    "raw_write_MBps": ".6f", "raw_read_MBps": ".6f", "cmp_write_MBps": ".6f",
    "cmp_read_MBps": ".6f", "ddr_total_MBps": ".6f", "ddr_gate_25_MBps": ".6f",
    "required_eff_pct": ".4f", "peak_GBps": ".1f", "sustained_eff_at_gate_pct": ".4f",
    "required_clock_chain_25_mhz": ".4f", "required_clock_core_25_mhz": ".4f",
    "required_clock_chain_0_mhz": ".4f",
    "worst_tier_margin_pct": ".4f",
}

INT_COLS = {"cores", "streams", "W", "H", "eram_total", "eram_headroom",
            "resource_conservative_eram", "bytes", "cycles", "overhead_tier_cycles"}


def cell(col, value):
    if col in FORMATS and isinstance(value, (int, float)):
        return format(float(value), FORMATS[col])
    if col in INT_COLS and isinstance(value, (int, float)):
        return str(int(round(value)))
    return str(value)


def _quote_cell(text):
    if any(ch in text for ch in ',"\r\n'):
        return '"' + text.replace('"', '""') + '"'
    return text


def row_to_csv(row, cols):
    return ",".join(_quote_cell(cell(c, row[c])) for c in cols)


def _scenario_id(w, h, fps, cores, streams, clock_mhz):
    return "%dx%d-%sfps-c%ds%d-%sMHz" % (w, h, format(float(fps), ".10g"), cores, streams,
                                         format(float(clock_mhz), ".10g"))


def make_scenario_row(frozen, rules, w, h, fps, cores, streams, clock_mhz):
    th = rules["thresholds"]
    gate = th["design_margin"]
    cpb = frozen["anchors"]["comp"]["cycles_per_byte"]
    anchor = frozen["anchors"]["full_grad"]
    clock_hz = clock_mhz * 1e6
    raw = raw_bytes(w, h)
    if (w, h) == (anchor["W"], anchor["H"]):
        cyc_core = raw * cpb
        cyc_chain = float(anchor["cycles"])
        overhead_note = "measured_full_grad_anchor_6421414"
    else:
        cyc_core = raw * cpb
        cyc_chain = cyc_core + frozen["overhead"]["primary_cycles"]
        overhead_note = "affine_+426385"
    cap_core = capacity_from_cpb(cpb, clock_hz)
    cap_chain = capacity_MBps(raw, cyc_chain, clock_hz)
    d = demand_MBps(raw, fps)
    cps_core = per_stream_capacity(cap_core, cores, streams)
    cps_chain = per_stream_capacity(cap_chain, cores, streams)
    m_core = margin(cps_core, d)
    m_chain = margin(cps_chain, d)
    if cores == 1:
        res = frozen["resources"]["single_chain_b10_r1_routed"]
        eram_bound = "single_chain_routed"
        eram_total = res["eram_total"]
        eram_headroom = res["eram_headroom"]
        cons = res["eram_total"]
        timing_proven = clock_mhz <= frozen["timing"]["single_core_proven_max_mhz"]
    else:
        marg = frozen["resources"]["dual_marginal"]
        consr = frozen["resources"]["dual_conservative"]
        eram_bound = "dual_marginal"
        eram_total = marg["eram_total"]
        eram_headroom = marg["eram_headroom"]
        cons = consr["eram_total"]
        timing_proven = False  # no dual-core Routed build exists
    verdict, reason = classify(cores, m_chain, eram_total, cons, timing_proven, rules)
    if cores == 1 and streams == 2:
        ps_note = ("per-stream=C/2 (frame-level round robin, 1 core serves 2 streams); "
                   "ERAM bound uses single-chain 187, a second stream bridge+fabric (+15+6=21 -> 208/300) is NOT added")
    elif cores == 2 and streams == 2:
        ps_note = "per-stream=C (one core per stream; 2C is aggregate and is NOT used)"
    elif cores == 2 and streams == 1:
        ps_note = "per-stream=C (second core idle)"
    else:
        ps_note = "per-stream=C (single core, single stream)"
    notes = ("core=comp fixed vector; chain=%s; %s" % (overhead_note, ps_note))
    req_chain_25 = cyc_chain * fps * (1.0 + gate) / 1e6
    req_core_25 = cyc_core * fps * (1.0 + gate) / 1e6
    req_chain_0 = cyc_chain * fps / 1e6
    return {
        "scenario_id": _scenario_id(w, h, fps, cores, streams, clock_mhz),
        "cores": cores, "streams": streams, "W": w, "H": h,
        "fps": float(fps), "clock_mhz": float(clock_mhz),
        "cycles_core_per_frame": cyc_core,
        "cycles_chain_per_frame": cyc_chain,
        "overhead_assumption": overhead_note,
        "capacity_core_MBps": cap_core,
        "capacity_chain_MBps": cap_chain,
        "demand_per_stream_MBps": d,
        "margin_core_pct": 100.0 * m_core,
        "margin_chain_pct": 100.0 * m_chain,
        "gate_25_core": "pass" if m_core >= gate else "fail",
        "gate_25_chain": "pass" if m_chain >= gate else "fail",
        "drop_rate_lb_pct": 100.0 * drop_rate_lb(cps_chain, d),
        "eram_bound": eram_bound,
        "eram_total": eram_total,
        "eram_headroom": eram_headroom,
        "verdict": verdict,
        "gate_status": gate_status(m_chain, gate),
        "notes": notes,
        "drop_rate_lb_basis": "per-stream chain capacity",
        "per_stream_capacity_core_MBps": cps_core,
        "per_stream_capacity_chain_MBps": cps_chain,
        "resource_conservative_eram": cons,
        "timing_status": "proven_at_187.5" if timing_proven else "unproven",
        "verdict_reason": reason,
        "required_clock_chain_25_mhz": req_chain_25,
        "required_clock_core_25_mhz": req_core_25,
        "required_clock_chain_0_mhz": req_chain_0,
    }


def scenario_rows(frozen, rules):
    grid = rules["grid"]
    rows = []
    seen = set()

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


def content_rows(frozen):
    clock = frozen["clock_hz"]
    a = frozen["anchors"]
    out = []
    for cid, cls, key, basis, label in [
        ("comp_core_1080p", "comp", "comp", "core_only", "measured"),
        ("rand_core_1080p", "rand", "rand", "core_only", "measured"),
    ]:
        n = a[key]["input_bytes"]
        cyc = a[key]["cycles"]
        cap = capacity_MBps(n, cyc, clock)
        d = demand_MBps(2592000, 30)
        m = margin(cap, d)
        out.append({
            "case_id": cid, "content_class": cls, "basis": basis,
            "W": 1920, "H": 1080, "bytes": n, "cycles": cyc,
            "clock_mhz": frozen["clock_mhz"], "capacity_MBps": cap,
            "fps_1080p_equivalent": cap / 2.592,
            "demand_at_30_MBps": d, "margin_pct": 100.0 * m,
            "gate_25": gate_status(m, frozen["design_margin"]),
            "label": label,
            "notes": ("fixed-vector core rate; input is %d B, not a 1080p frame" % n)
                     if basis == "core_only" else "chain anchor; full_grad content",
        })
    fg = a["full_grad"]
    cap = capacity_MBps(fg["raw_bytes"], fg["cycles"], clock)
    d = demand_MBps(2592000, 30)
    m = margin(cap, d)
    out.append({
        "case_id": "full_grad_chain_1080p", "content_class": "full_grad", "basis": "full_chain",
        "W": 1920, "H": 1080, "bytes": fg["raw_bytes"], "cycles": fg["cycles"],
        "clock_mhz": frozen["clock_mhz"], "capacity_MBps": cap,
        "fps_1080p_equivalent": cap / 2.592,
        "demand_at_30_MBps": d, "margin_pct": 100.0 * m,
        "gate_25": gate_status(m, frozen["design_margin"]),
        "label": "measured",
        "notes": "only full-frame chain anchor; content class is a synthetic gradient; overhead constancy across content is assumed",
    })
    return out


OVERHEAD_COLS = [
    "scenario_id", "overhead_tier_cycles", "chain_source", "applies",
    "cores", "streams", "W", "H", "fps", "clock_mhz",
    "cycles_core_per_frame", "cycles_chain_per_frame", "capacity_chain_MBps",
    "per_stream_capacity_chain_MBps", "demand_per_stream_MBps",
    "margin_chain_pct", "gate_25", "verdict", "notes",
]


def overhead_sensitivity_rows(rows, frozen, rules):
    """Design-guide 4.3/6.2 sensitivity: overhead in {0, 426385, 1,000,000}.

    1080p is fixed to the measured 6,421,414-cycle anchor, so the tier does not apply
    there (applies=false, identical values in all three tiers).  Every other geometry
    uses cycles_core(W,H) + tier.  The verdict is re-derived per tier with classify().
    """
    gate = rules["thresholds"]["design_margin"]
    tiers = frozen["overhead"]["sensitivity_tiers"]
    cpb = frozen["anchors"]["comp"]["cycles_per_byte"]
    anchor = frozen["anchors"]["full_grad"]
    out = []
    for r in rows:
        w, h = _int(r, "W"), _int(r, "H")
        fps, cores, streams = float(r["fps"]), _int(r, "cores"), _int(r, "streams")
        clk = float(r["clock_mhz"])
        raw = raw_bytes(w, h)
        cyc_core = raw * cpb
        is_anchor = (w, h) == (anchor["W"], anchor["H"])
        if cores == 1:
            et = frozen["resources"]["single_chain_b10_r1_routed"]["eram_total"]
            cons = et
            timing = clk <= frozen["timing"]["single_core_proven_max_mhz"]
        else:
            et = frozen["resources"]["dual_marginal"]["eram_total"]
            cons = frozen["resources"]["dual_conservative"]["eram_total"]
            timing = False
        for ov in tiers:
            if is_anchor:
                cyc_chain = float(anchor["cycles"])
                source, applies = "measured_anchor_6421414", "false"
                note = "1080p uses the measured anchor; overhead tier not applied"
            else:
                cyc_chain = cyc_core + float(ov)
                source, applies = "affine", "true"
                note = ""
            cap = capacity_MBps(raw, cyc_chain, clk * 1e6)
            ps = per_stream_capacity(cap, cores, streams)
            d = demand_MBps(raw, fps)
            m = margin(ps, d)
            verdict, _ = classify(cores, m, et, cons, timing, rules)
            out.append({
                "scenario_id": r["scenario_id"],
                "overhead_tier_cycles": ov,
                "chain_source": source,
                "applies": applies,
                "cores": cores, "streams": streams, "W": w, "H": h,
                "fps": fps, "clock_mhz": clk,
                "cycles_core_per_frame": cyc_core,
                "cycles_chain_per_frame": cyc_chain,
                "capacity_chain_MBps": cap,
                "per_stream_capacity_chain_MBps": ps,
                "demand_per_stream_MBps": d,
                "margin_chain_pct": 100.0 * m,
                "gate_25": gate_status(m, gate),
                "verdict": verdict,
                "notes": note,
            })
    return out


def ddr_rows(frozen):
    peak = frozen["ddr"]["peak_MBps"]
    exp = frozen["ddr"]["raw_slot_expansion"]
    cases = [
        ("dual_1080p30_main", 2, 30, 1920, 1080, exp, True,
         "main path: camera writes RAW slot, A+ reads RAW, writes CMP, UART/PCIe reads CMP (2R+2S); 20B/32B slot, CMP worst stored"),
        ("dual_1080p30_no_cmp_ddr", 2, 30, 1920, 1080, exp, False,
         "variant: CMP streamed directly, no CMP DDR write/read (S=0); not the adopted main path"),
        ("dual_1080p30_tight_1p0x", 2, 30, 1920, 1080, 1.0, True,
         "variant: 20261025-180900 T08/T10 tight packed layout (1.0x), NOT this run's adopted main layout"),
        ("single_1080p30_main", 1, 30, 1920, 1080, exp, True,
         "single-stream reference (one camera at 1080p30)"),
        ("dual_1600x900_30_main", 2, 30, 1600, 900, exp, True,
         "primary recommendation geometry (1600x900@30, two cameras)"),
        ("dual_1080p20_main", 2, 20, 1920, 1080, exp, True,
         "1080p at the 25%-margin grid fps (20 fps), two cameras"),
        ("dual_960x540_30_main", 2, 30, 960, 540, exp, True,
         "smallest 16:9 tier; single core time-sharing two streams meets 25%"),
    ]
    return [ddr_case(cid, st, fps, w, h, e, inc, peak, note,
                     layout=("packed_1.0x_tight" if "tight" in cid else "20B_payload_per_32B_word"))
            for (cid, st, fps, w, h, e, inc, note) in cases]


def _margin_frac(row):
    if "margin_chain" in row:
        return float(row["margin_chain"])
    return float(row["margin_chain_pct"]) / 100.0


def _int(row, key):
    return int(round(float(row[key])))


def _pick(rows, pred):
    cand = [r for r in rows if pred(r)]
    if not cand:
        return None
    return sorted(cand, key=lambda r: (-_int(r, "W") * _int(r, "H"), -float(r["fps"]),
                                       _int(r, "cores"), _int(r, "streams"), r["scenario_id"]))[0]


def chain_margin_at(row, frozen, overhead):
    w, h = _int(row, "W"), _int(row, "H")
    fps = float(row["fps"])
    raw = raw_bytes(w, h)
    cpb = frozen["anchors"]["comp"]["cycles_per_byte"]
    anchor = frozen["anchors"]["full_grad"]
    cyc_core = raw * cpb
    cyc_chain = float(anchor["cycles"]) if (w, h) == (anchor["W"], anchor["H"]) else cyc_core + float(overhead)
    cap = raw * (float(row["clock_mhz"]) * 1e6) / cyc_chain / 1e6
    ps = per_stream_capacity(cap, _int(row, "cores"), _int(row, "streams"))
    return margin(ps, raw * fps / 1e6)


def worst_tier_margin(row, frozen):
    return min(chain_margin_at(row, frozen, ov) for ov in frozen["overhead"]["sensitivity_tiers"])


def recommendations(rows, frozen=None):
    primary = _pick(rows, lambda r: float(r["fps"]) == 30 and _margin_frac(r) >= 0.25)
    alt_fps = _pick(rows, lambda r: _int(r, "W") == 1920 and _int(r, "H") == 1080
                    and _int(r, "cores") == 1 and _int(r, "streams") == 1 and _margin_frac(r) >= 0.25)
    if frozen is None:
        alt_res = _pick(rows, lambda r: float(r["fps"]) == 30 and _int(r, "cores") == 1
                        and _int(r, "streams") == 1 and 0.0 <= _margin_frac(r) < 0.25)
    else:
        # robust alternate: meets 25% in ALL frozen overhead tiers (0 / 426385 / 1000000)
        alt_res = _pick(rows, lambda r: float(r["fps"]) == 30 and _int(r, "cores") == 1
                        and _int(r, "streams") == 1 and _margin_frac(r) >= 0.25
                        and worst_tier_margin(r, frozen) >= 0.25)
    alts = [r for r in (alt_res, alt_fps) if r is not None and (primary is None or r["scenario_id"] != primary["scenario_id"])]
    return primary, alts[:2]


def frontier_rows(rows, frozen):
    """Grid-maximal frontier rows; every margin is same-source as its capacity_basis."""
    out = []

    def row_at(w, h, fps, cores, streams, clock=187.5):
        for r in rows:
            if (_int(r, "W"), _int(r, "H"), float(r["fps"]), _int(r, "cores"), _int(r, "streams"),
                    float(r["clock_mhz"])) == (w, h, float(fps), cores, streams, float(clock)):
                return r
        return None

    primary, alts = recommendations(rows, frozen)
    alt_ids = {r["scenario_id"] for r in alts}
    primary_ids = {primary["scenario_id"]} if primary else set()
    f = frozen["clock_hz"]
    cpb = frozen["anchors"]["comp"]["cycles_per_byte"]
    anchor = frozen["anchors"]["full_grad"]
    tiers = frozen["overhead"]["sensitivity_tiers"]
    gate = frozen["design_margin"]
    cont_chain_25 = max_fps(anchor["cycles"], f, 0.25)
    cont_chain_0 = max_fps(anchor["cycles"], f, 0.0)
    cont_core_25 = max_fps(raw_bytes(1920, 1080) * cpb, f, 0.25)

    def add(family, row, basis, recommended, note):
        m_chain = float(row["margin_chain_pct"])
        m_core = float(row["margin_core_pct"])
        cyc_chain = float(row["cycles_chain_per_frame"])
        cyc_core = float(row["cycles_core_per_frame"])
        fps = float(row["fps"])
        if basis.startswith("core_only"):
            margin = m_core
            gs = gate_status(margin / 100.0, gate)
            verdict = "core_only_upper_bound"
            worst, worst_gate = margin, gs
        else:
            margin = m_chain
            gs = row["gate_status"]
            verdict = row["verdict"]
            worst = min(chain_margin_at(row, frozen, ov) for ov in tiers) * 100.0
            worst_gate = gate_status(worst / 100.0, gate)
        out.append({
            "family": family, "cores": row["cores"], "streams": row["streams"],
            "W": row["W"], "H": row["H"], "fps": row["fps"], "clock_mhz": row["clock_mhz"],
            "capacity_basis": basis, "margin_pct": margin,
            "margin_chain_pct": m_chain, "margin_core_pct": m_core, "gate_25": gs,
            "required_clock_chain_25_mhz": cyc_chain * fps * (1.0 + gate) / 1e6,
            "required_clock_core_25_mhz": cyc_core * fps * (1.0 + gate) / 1e6,
            "worst_tier_margin_pct": worst, "worst_tier_gate": worst_gate,
            "verdict": verdict, "is_recommended": "true" if recommended else "false",
            "notes": note,
        })

    # 1080p fps family
    r20 = row_at(1920, 1080, 20, 1, 1)
    add("1080p_fps_chain", r20, "full_chain_anchor", r20["scenario_id"] in alt_ids,
        "max grid fps meeting 25%% at 1080p (continuous %.2f fps); alternate_fps (anchor fixed, tier-invariant)"
        % cont_chain_25)
    r30 = row_at(1920, 1080, 30, 1, 1)
    add("1080p_fps_chain", r30, "full_chain_anchor", False,
        "target row: chain cannot hold 30 fps (0%% max %.2f fps); core-only 0%% max %.2f fps"
        % (cont_chain_0, max_fps(raw_bytes(1920, 1080) * cpb, f, 0.0)))
    r2 = row_at(1920, 1080, 20, 2, 2)
    add("1080p_fps_chain", r2, "full_chain_anchor", False,
        "dual-core row is conditional (no dual-core Routed build); 2C=%.2f MB/s aggregate is not the per-stream capacity"
        % (2.0 * float(r2["capacity_chain_MBps"])))
    r2s = row_at(1920, 1080, 30, 2, 2)
    add("1080p_fps_chain", r2s, "full_chain_anchor", False,
        "2xC_core aggregate %.2f >= 155.52 would look OK, but per-stream chain %.2f < 77.76 and 2xC_chain %.2f < 155.52 (negative-control trap)"
        % (2.0 * float(r2s["capacity_core_MBps"]), float(r2s["per_stream_capacity_chain_MBps"]),
           2.0 * float(r2s["capacity_chain_MBps"])))
    rco = row_at(1920, 1080, 25, 1, 1)
    add("1080p_fps_core_only", rco, "core_only_comp", False,
        "optimistic core-only upper bound: max grid fps meeting 25%% (continuous %.2f fps); not a system basis; core margin is overhead-independent"
        % cont_core_25)
    add("1080p_fps_core_only", r30, "core_only_comp", False,
        "core-only margin %.2f%% is below the 25%% gate and ignores DDR/export" % float(r30["margin_core_pct"]))

    # 30 fps resolution family (single core, single stream)
    r1600 = row_at(1600, 900, 30, 1, 1)
    add("30fps_res_chain", r1600, "full_chain_affine", r1600["scenario_id"] in primary_ids,
        "primary recommendation at the main overhead tier 426385; conservative tier 1000000 drops to %.4f%% (below 25%%)"
        % (min(chain_margin_at(r1600, frozen, ov) for ov in tiers) * 100.0))
    r1440 = row_at(1440, 810, 30, 1, 1)
    add("30fps_res_chain", r1440, "full_chain_affine", r1440["scenario_id"] in alt_ids,
        "robust alternate: largest 30 fps tier meeting 25%% in all three overhead tiers (worst %.4f%%)"
        % (min(chain_margin_at(r1440, frozen, ov) for ov in tiers) * 100.0))
    r1728 = row_at(1728, 972, 30, 1, 1)
    add("30fps_res_chain", r1728, "full_chain_affine", False,
        "higher resolution but below 25%% at the main tier and worse at the conservative tier (worst %.4f%%); not recommended"
        % (min(chain_margin_at(r1728, frozen, ov) for ov in tiers) * 100.0))
    add("30fps_res_chain", r30, "full_chain_anchor", False,
        "1080p30 chain is 2.66% short; no resolution-tier rescue at this geometry")
    rco1728 = row_at(1728, 972, 30, 1, 1)
    add("30fps_res_core_only", rco1728, "core_only_comp", False,
        "core-only would allow 1728x972 (%.2f%%), but the same row fails at chain level (%.2f%%)"
        % (float(rco1728["margin_core_pct"]), float(rco1728["margin_chain_pct"])))
    add("30fps_res_core_only", r30, "core_only_comp", False,
        "core-only 1080p30 margin %.2f%% is below 25%%" % float(r30["margin_core_pct"]))

    # single core time-sharing two streams
    r960 = row_at(960, 540, 30, 1, 2)
    add("30fps_res_chain_1c2s", r960, "full_chain_affine", False,
        "max tier where one core time-sharing two streams still meets 25% per stream")
    r1152 = row_at(1152, 648, 30, 1, 2)
    add("30fps_res_chain_1c2s", r1152, "full_chain_affine", False,
        "next tier up; per-stream margin %.2f%% is below 25%%" % float(r1152["margin_chain_pct"]))
    r15 = row_at(1920, 1080, 15, 1, 2)
    add("1080p_fps_chain", r15, "full_chain_anchor", False,
        "single core serving two 1080p streams: best grid fps still short; continuous 25%% max %.2f fps per stream"
        % (max_fps(anchor["cycles"], f, 0.25) / 2.0))

    # dual-core 30 fps resolution family
    r1600_2 = row_at(1600, 900, 30, 2, 2)
    add("30fps_res_chain", r1600_2, "full_chain_affine", False,
        "dual-core does not raise per-stream capacity; same 1600x900 row is conditional (no dual-core Routed build, conservative ERAM 289)")
    return out


def write_header(cols):
    return ",".join(cols)
