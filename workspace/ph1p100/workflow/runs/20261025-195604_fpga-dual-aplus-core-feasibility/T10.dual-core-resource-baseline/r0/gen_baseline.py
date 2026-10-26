#!/usr/bin/env python3
"""P1 generator for T10.dual-core-resource-baseline (offline, read-only inputs).

Writes only inside this task's r0/ directory:
  input-verified.json, resource-table.csv, dual-core-budget.csv,
  tests/negative/*.json

No TD, no synthesis, no place/route, no bitgen, no hardware.
All resource numbers are parsed from frozen routed reports; synth rows are
stage=synth checkpoints and are never added to routed values.
"""
import csv
import datetime
import hashlib
import json
import platform
import re
import sys
from pathlib import Path

PROJ = Path("D:/fpga/ph1p100")
RUN = PROJ / "workflow/runs/20261025-195604_fpga-dual-aplus-core-feasibility"
R0 = RUN / "T10.dual-core-resource-baseline" / "r0"
B6 = PROJ / "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b6-a1-htab-nw"
B10 = PROJ / "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b10-b9-fix"
B11 = PROJ / "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b11-aplus-read"
TR = PROJ / "workflow/runs/20261020-0209_singleA_aplus_closedloop/test-reports"

DEVICE = {"ERAM20K": 300, "LUT4": 129024, "DFF": 143360, "DSP": 220,
          "PLL": 12, "SLICE": 71680, "LUT6_SITES": 71680}
LOGIC_QUOTA = 210
MARGIN_TARGET = 270          # 300 * 0.90, run's frozen resource gate
CLOCK_MHZ = 187.5
EXPECT_CORE_SHA = "6797db053cfc47497540d6345e3a46b7e79cc1d34fa25da5a4c501505fbf35bb"
EXPECT_CORE_BYTES = 80196
EXPECT_B6_MANIFEST_SHA = "2e9fd356824084813e3415af11757c1b56f774c9b6dd45f3b2a111647ad08880"

INPUTS = [
    ("b6_core", "single A+ core RTL (frozen b6)", B6 / "r0/changed-src/a1_deflate_core.v"),
    ("b6_manifest", "b6 candidate manifest (frozen)", B6 / "CANDIDATE-MANIFEST-b6-a1-htab-nw-r0.json"),
    ("b6_routed_area", "b6 routed area report", B6 / "r0/td/routed_area.rpt"),
    ("b6_routed_qor", "b6 routed QoR report", B6 / "r0/td/routed_qor.rpt"),
    ("b6_routed_timing", "b6 routed timing report", B6 / "r0/td/routed_timing.rpt"),
    ("b6_syn_area", "b6 synthesized area report (checkpoint only)", B6 / "r0/td/syn_gate_area.rpt"),
    ("b6_build_console", "b6 TD build console", B6 / "r0/td/build_console_r0.log"),
    ("b6_report", "b6 independent integrated test report", TR / "T10.b6-a1-htab-nw-r0-integrated.md"),
    ("b10_routed_area", "b10 r1 routed area report", B10 / "r0/td/routed_area.rpt"),
    ("b10_routed_qor", "b10 r1 routed QoR report", B10 / "r0/td/routed_qor.rpt"),
    ("b10_routed_timing", "b10 r1 routed timing report", B10 / "r0/td/routed_timing.rpt"),
    ("b10_syn_area", "b10 r1 synthesized area report (checkpoint only)", B10 / "r0/td/syn_gate_area.rpt"),
    ("b10_build_console", "b10 r1 TD build console", B10 / "r0/td/build_console_b10_r1.log"),
    ("b10_result", "b10 r1 development result", B10 / "result-r1.md"),
    ("b10_manifest", "b10 r1 candidate manifest", B10 / "CANDIDATE-MANIFEST-b10-b9-fix-r1.json"),
    ("b11_routed_area", "b11 r0 routed area report (parallel, cross-check)", B11 / "r0/td/routed_area.rpt"),
    ("b11_routed_qor", "b11 r0 routed QoR report (parallel, cross-check)", B11 / "r0/td/routed_qor.rpt"),
    ("b11_routed_timing", "b11 r0 routed timing report (parallel, cross-check)", B11 / "r0/td/routed_timing.rpt"),
    ("b11_syn_area", "b11 r0 synthesized area report (checkpoint only)", B11 / "r0/td/syn_gate_area.rpt"),
    ("b11_build_console", "b11 r0 TD build console", B11 / "r0/td/build_console_b11.log"),
    ("b11_result", "b11 r0 development result (diagnosis_only)", B11 / "r0/result-r0.md"),
    ("p1_request", "this run's user request", RUN / "request.md"),
    ("p1_input_index", "this run's planner input index", RUN / "input-index.md"),
    ("p1_design_guide", "this run's frozen FPGA design guide", RUN / "fpga-design-guide.md"),
    ("p1_dev_plan", "this run's development/acceptance plan", RUN / "dev-plan.md"),
    ("p1_dispatch", "this task's dispatch record", RUN / "dispatch.json"),
    ("device_doc", "dual-camera link plan (device totals 300/129024/143360/220/12)",
     PROJ / "docs/双目首版_整链路方案与团队交付.md"),
]


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def read_text(path):
    return path.read_text(encoding="utf-8", errors="replace")


def parse_area(path):
    text = read_text(path)
    m = re.search(r"\*\*\*Report Model:\s*(\S+)\s+Device:\s*(\S+)\*\*\*", text)
    if not m:
        raise RuntimeError(f"no report model in {path}")
    stats = {}
    patterns = {
        "lut6": r"^\s*#lut6\s+(\d+)",
        "lut": r"^\s*#lut\s+(\d+)",
        "reg": r"^\s*#reg\s+(\d+)",
        "slice": r"^\s*#slice\*?\s+(\d+)",
        "eram": r"^\s*#eram\s+(\d+)",
        "dsp": r"^\s*#dsp\s+(\d+)",
        "pll": r"^\s*#pll\s+(\d+)",
        "dram_lut": r"^\s*#dram lut\s+(\d+)",
    }
    for line in text.splitlines():
        for key, pat in patterns.items():
            if key in stats:
                continue
            mm = re.match(pat, line)
            if mm:
                stats[key] = int(mm.group(1))
    hier = []
    in_hier = False
    for line in text.splitlines():
        if line.startswith("Report Hierarchy Area:"):
            in_hier = True
            continue
        if not in_hier or not line.startswith("|"):
            continue
        parts = line.split("|")
        if len(parts) < 17:
            continue
        raw_inst = parts[1]
        if raw_inst.strip() in ("Instance", ""):
            continue
        nums = []
        try:
            for cell in parts[3:16]:
                nums.append(int(cell.strip()))
        except ValueError:
            continue
        hier.append({
            "depth": (len(raw_inst) - len(raw_inst.lstrip(" "))) // 2,
            "instance": raw_inst.strip(),
            "module": parts[2].strip(),
            "logic": nums[0], "ripple": nums[1], "seq": nums[2], "eram": nums[3],
            "dsp": nums[4], "dram_lut": nums[5], "shifter": nums[6],
            "f7mux": nums[7], "f8mux": nums[8], "pll": nums[9],
            "hxt": nums[10], "pcie": nums[11], "ddr": nums[12],
        })
    return {"model": m.group(1), "device": m.group(2), "stats": stats, "hier": hier, "text": text}


def parse_qor(path):
    text = read_text(path)
    def grab(key):
        m = re.search(r"\|\s*" + re.escape(key) + r"\s*\|\s*(\d+)\s*\|", text)
        return int(m.group(1)) if m else None
    return {
        "setup_wns_ps": grab("Setup WNS"),
        "hold_wns_ps": grab("Hold WNS"),
        "viol_s": grab("Num of violated S-EP"),
        "viol_h": grab("Num of violated H-EP"),
        "slices": grab("#slices"),
        "rams": grab("#RAMs"),
        "dsps": grab("#DSPs"),
        "dramhardcon": grab("#DRAMHARDCON"),
    }


def parse_timing(path):
    text = read_text(path)
    def g(pat):
        m = re.search(pat, text)
        return float(m.group(1)) if m else None
    sw = g(r"SWNS:\s*(-?[\d.]+)ns")
    hw = g(r"HWNS:\s*(-?[\d.]+)ns")
    per = g(r"Period Check WNS:\s*(-?[\d.]+)ns")
    mm = re.search(
        r"Max\s+:\s+SWNS\s+(-?[\d.]+)ns,\s+STNS\s+(-?[\d.]+)ns,\s+(\d+)\s+Viol Endpoints,\s+(\d+)\s+Total Endpoints", text)
    mn = re.search(
        r"Min\s+:\s+HWNS\s+(-?[\d.]+)ns,\s+HTNS\s+(-?[\d.]+)ns,\s+(\d+)\s+Viol Endpoints,\s+(\d+)\s+Total Endpoints", text)
    return {
        "wns": sw, "hold": hw, "period": per,
        "stns": float(mm.group(2)) if mm else None,
        "viol_ep": int(mm.group(3)) if mm else None,
        "total_ep": int(mm.group(4)) if mm else None,
        "hold_viol_ep": int(mn.group(3)) if mn else None,
        "hold_total_ep": int(mn.group(4)) if mn else None,
        "has_187p5": "187.500" in text and "clk_a1" in text,
        "generated": (re.search(r"Generated\s+:\s*(.+)", text).group(1).strip()
                      if re.search(r"Generated\s+:\s*(.+)", text) else ""),
        "constraint": (re.search(r"Constraint File\s+:\s*(.+);", text).group(1).strip()
                       if re.search(r"Constraint File\s+:\s*(.+);", text) else ""),
    }


def find(hier, name, module=None, depth=None):
    for row in hier:
        if row["instance"] != name:
            continue
        if module is not None and row["module"] != module:
            continue
        if depth is not None and row["depth"] != depth:
            continue
        return row
    raise RuntimeError(f"hierarchy row not found: {name} module={module} depth={depth}")


def get_sources():
    out = {}
    for sid, base in (("b6", B6), ("b10", B10), ("b11", B11)):
        area = parse_area(base / "r0/td/routed_area.rpt")
        qor = parse_qor(base / "r0/td/routed_qor.rpt")
        tim = parse_timing(base / "r0/td/routed_timing.rpt")
        syn = parse_area(base / "r0/td/syn_gate_area.rpt")
        out[sid] = {"area": area, "qor": qor, "timing": tim, "syn": syn}
    return out


def build_resource_rows(src):
    rows = []
    top_notes = {
        "b6": ("Authority single-core routed evidence (core SHA 6797db05...35bb). "
               "102 ERAM closes as 72 synth fabric + 2x15 CWC debug RAMs inserted at routed. "
               "Thin routed margin; hierarchy top equals #eram."),
        "b10": ("Single-chain board baseline r1 (same p2_a1_board_top as b6/b11). "
                "102 ERAM + 85 DRAMHARDCON = 187/300 per QoR and b10 result-r1. "
                "Used as the P1 base for both dual-core columns."),
        "b11": ("Parallel b11 r0 diagnostic candidate, cross-check only (NOT this run's baseline). "
                "WNS_ns=+0.015 is the GLOBAL WNS (ddr_user 200 MHz domain); the clk_a1 187.5 MHz "
                "domain is +0.059, so do not read 0.015 as the A+ 187.5 MHz domain result. "
                "Global +0.015 < +0.05 gate; same 102+85 accounting."),
    }
    for sid in ("b6", "b10", "b11"):
        s = src[sid]
        a, q, t, h = s["area"], s["qor"], s["timing"], s["area"]["hier"]
        top = find(h, "top", depth=0)
        eram_logic = a["stats"]["eram"]
        rows.append({
            "source_id": sid, "scope": "top", "instance": "top", "module": a["model"],
            "top": a["model"], "stage": "routed",
            "ERAM_logic": eram_logic, "DRAM_HARDCON": q["dramhardcon"],
            "DRAM_LUT": a["stats"]["dram_lut"],
            "ERAM_total": eram_logic + q["dramhardcon"],
            "LUT6": a["stats"]["lut6"], "REG": a["stats"]["reg"], "SLICE": a["stats"]["slice"],
            "DSP": a["stats"]["dsp"], "PLL": a["stats"]["pll"],
            "WNS_ns": t["wns"], "HOLD_ns": t["hold"], "viol_ep": t["viol_ep"],
            "total_ep": t["total_ep"], "clock_mhz": CLOCK_MHZ,
            "logic_lut": top["logic"], "ripple": top["ripple"],
            "notes": top_notes[sid],
        })
        # synth rows: checkpoint only, never used for fit
        sa = s["syn"]
        stop = find(sa["hier"], "top", depth=0)
        rows.append({
            "source_id": sid, "scope": "top", "instance": "top", "module": sa["model"],
            "top": sa["model"], "stage": "synth",
            "ERAM_logic": sa["stats"]["eram"], "DRAM_HARDCON": "",
            "DRAM_LUT": sa["stats"]["dram_lut"], "ERAM_total": sa["stats"]["eram"],
            "LUT6": sa["stats"]["lut6"], "REG": sa["stats"]["reg"],
            "SLICE": sa["stats"]["slice"], "DSP": sa["stats"]["dsp"],
            "PLL": sa["stats"]["pll"], "WNS_ns": "", "HOLD_ns": "",
            "viol_ep": "", "total_ep": "", "clock_mhz": "",
            "logic_lut": stop["logic"], "ripple": stop["ripple"],
            "notes": ("stage=synth checkpoint only; NEVER added to routed. "
                      "Synth ERAM 72 excludes the 2x15 CWC RAMs added at routed (72+30=102). "
                      "Synth report has no #DRAMHARDCON line; blank is intentional."),
        })
        # hierarchy attribution rows (measured columns, not LUT6 increments)
        wanted = []
        for r in h:
            if r["depth"] == 1:
                wanted.append(r)
        for name, module in (("u_core", "a1_deflate_core"),
                             ("u_a1", "a1_frame_top"),
                             ("u_arb", "a1_ddr_arb2"),
                             ("u_cam_fifo", "capture_async_fifo"),
                             ("u_cmp_store", "a1_ddr_slot_store"),
                             ("u_crop", "a1_raw_crop"),
                             ("u_export", "a1_uart_export"),
                             ("u_raw_store", "a1_ddr_slot_store"),
                             ("u_mcu_core", "usr_mcu_core")):
            try:
                wanted.append(find(h, name, module=module))
            except RuntimeError:
                pass
        seen = set()
        for r in wanted:
            key = (r["depth"], r["instance"], r["module"])
            if key in seen:
                continue
            seen.add(key)
            rows.append({
                "source_id": sid, "scope": "hierarchy", "instance": r["instance"],
                "module": r["module"], "top": a["model"], "stage": "routed",
                "ERAM_logic": r["eram"], "DRAM_HARDCON": "", "DRAM_LUT": r["dram_lut"],
                "ERAM_total": r["eram"], "LUT6": "", "REG": r["seq"], "SLICE": "",
                "DSP": r["dsp"], "PLL": r["pll"], "WNS_ns": "", "HOLD_ns": "",
                "viol_ep": "", "total_ep": "", "clock_mhz": "",
                "logic_lut": r["logic"], "ripple": r["ripple"],
                "notes": ("routed u_camera contains ONLY u_csi_a (mipi_csi2_rx_ph1p); there is no "
                          "u_csi_b hierarchy row. u_csi_b is instantiated in the source but has no "
                          "routed resources, so a second full CSI RX is NOT implemented in this "
                          "routed baseline; its cost is tracked in dual-core-budget.csv marginal "
                          "notes (773 logic / 340 ripple / 1474 seq / 0 ERAM if added)."
                          if r["instance"] == "u_camera" else
                          "TD hierarchy column attribution (logic lut / ripple / seq / eram / "
                          "dram lut); NOT a LUT6 increment and not additive with routed totals."),
            })
    return rows


def sub(a, b, field):
    return a[field] - b[field]


def build_budget(src):
    base = src["b10"]
    a, q, h = base["area"], base["qor"], base["area"]["hier"]
    base_eram = a["stats"]["eram"]
    base_lut6 = a["stats"]["lut6"]
    base_reg = a["stats"]["reg"]
    base_slice = a["stats"]["slice"]
    top = find(h, "top", depth=0)

    core = find(h, "u_core", module="a1_deflate_core")
    bridge = find(h, "u_bridge", module="p2_ddr_bridge")
    frame = find(h, "u_a1", module="a1_frame_top")
    fabric_rows = [find(h, "u_cam_fifo", module="capture_async_fifo"),
                   find(h, "u_arb", module="a1_ddr_arb2"),
                   find(h, "u_cmp_store", module="a1_ddr_slot_store"),
                   find(h, "u_crop", module="a1_raw_crop"),
                   find(h, "u_export", module="a1_uart_export"),
                   find(h, "u_raw_store", module="a1_ddr_slot_store")]
    d_core = {k: core[k] for k in ("eram", "logic", "ripple", "seq", "dram_lut")}
    d_bridge = {k: bridge[k] for k in ("eram", "logic", "ripple", "seq", "dram_lut")}
    d_frame_extra = {k: frame[k] - core[k] for k in ("eram", "logic", "ripple", "seq", "dram_lut")}
    d_fabric = {k: sum(r[k] for r in fabric_rows) for k in ("eram", "logic", "ripple", "seq", "dram_lut")}
    d_stream = {k: d_frame_extra[k] + d_fabric[k] for k in d_frame_extra}
    delta = {k: d_core[k] + d_bridge[k] + d_stream[k] for k in d_core}

    marg_eram = base_eram + delta["eram"]
    marg_lut6 = base_lut6 + delta["logic"] + delta["ripple"] + delta["dram_lut"]
    marg_lut6_logic_only = base_lut6 + delta["logic"]
    marg_reg = base_reg + delta["seq"]
    base_work = top["logic"] + top["ripple"] + top["seq"]
    delta_work = delta["logic"] + delta["ripple"] + delta["seq"]
    marg_slice = round(base_slice * (1.0 + delta_work / base_work))

    cons_eram = base_eram * 2
    cons_lut6 = base_lut6 * 2
    cons_reg = base_reg * 2
    cons_slice = base_slice * 2

    def fit300(v):
        if v <= MARGIN_TARGET:
            return "pass"
        if v <= DEVICE["ERAM20K"]:
            return "conditional"
        return "fail"

    def fit210(v):
        if v <= LOGIC_QUOTA:
            return "pass"
        if v <= DEVICE["ERAM20K"]:
            return "conditional"
        return "fail"

    def row(case_id, column, eram_logic, ddr, lut6, lut6_logic_only, reg, slice_, dsp, pll, timing, labels, notes,
            lut4_basis="assumed upper bound: <=2 LUT4 per LUT6 site (true LUT4 count not reported by TD)"):
        eram_total = eram_logic + ddr * q["dramhardcon"]
        headroom = DEVICE["ERAM20K"] - eram_total
        return {
            "case_id": case_id, "column": column, "base_source": "b10_r1_routed",
            "basis": "single-chain board baseline + second-chain delta (see notes)",
            "cores": 2, "streams": 2,
            "ERAM_logic": eram_logic,
            "DRAM_HARDCON_per_ddr": q["dramhardcon"],
            "ddr_controllers": ddr,
            "DRAM_HARDCON_counted": ddr * q["dramhardcon"],
            "ERAM_total": eram_total,
            "ERAM_device_total": DEVICE["ERAM20K"],
            "ERAM_headroom": headroom,
            "headroom_pct": round(100.0 * headroom / DEVICE["ERAM20K"], 2),
            "ERAM_logic_quota_210": LOGIC_QUOTA,
            "logic_headroom_210": LOGIC_QUOTA - eram_logic,
            "fit_300": fit300(eram_total),
            "fit_210_logic": fit210(eram_logic),
            "LUT_domain": "TD_LUT6",
            "LUT6_total": lut6, "LUT6_logic_only_lower": lut6_logic_only,
            "LUT6_device_total": DEVICE["LUT6_SITES"],
            "LUT6_headroom": DEVICE["LUT6_SITES"] - lut6,
            "LUT4_equiv_upper": 2 * lut6, "LUT4_device_total": DEVICE["LUT4"],
            "LUT4_headroom": DEVICE["LUT4"] - 2 * lut6, "LUT4_basis": lut4_basis,
            "REG_total": reg, "REG_device_total": DEVICE["DFF"],
            "REG_headroom": DEVICE["DFF"] - reg,
            "SLICE_total": slice_, "SLICE_device_total": DEVICE["SLICE"],
            "SLICE_headroom": DEVICE["SLICE"] - slice_,
            "DSP_total": dsp, "DSP_device_total": DEVICE["DSP"],
            "PLL_total": pll, "PLL_device_total": DEVICE["PLL"],
            "timing_status": timing,
            "labels": labels,
            "notes": notes,
        }

    rows = [
        row("marginal", "marginal", marg_eram, 1, marg_lut6, marg_lut6_logic_only,
            marg_reg, marg_slice, 0, 4, "unproven",
            "base=measured(b10); u_core/u_bridge/stream fabric=measured hierarchy; "
            "slice scaling & second-domain PLL=assumed; flow=derived",
            ("Second A+ core (u_core 23 ERAM, 1453 logic/783 ripple/1167 seq/32 dram lut) + "
             "second bridge 15 ERAM + second stream fabric 6 ERAM (frame-level 4 + cam FIFO 2) "
             "+ shared MCU/DDR PHY not duplicated; DRAMHARDCON 85 counted once. "
             "LUT6_total uses the TD identity #lut6 = with-luts(logic) + with-adder(ripple) + "
             "dram lut + shifter lut: 19695 + 3793 + 2077 + 144 = 25709. "
             f"Logic-only lower bound (not the fit value) = {marg_lut6_logic_only}. "
             f"Delta: eram {delta['eram']}, logic {delta['logic']}, ripple {delta['ripple']}, "
             f"seq {delta['seq']}, dram_lut {delta['dram_lut']}. "
             "Slice estimated by work-ratio scaling (assumed). "
             "Second CSI RX (u_csi_b) is NOT in routed (only u_csi_a); it is excluded here. "
             "If a full second CSI is required, add 773 logic/340 ripple/1474 seq/0 ERAM: "
             "LUT6 26822, REG 35815, still within device.")),
        row("conservative", "conservative", cons_eram, 1, cons_lut6, cons_lut6,
            cons_reg, cons_slice, 0, 8, "unproven",
            "base=measured(b10); full second-chain replication=derived/upper bound; "
            "CWC 2x15 ERAM also duplicated in this column",
            ("Full second chain replicated: 2 x 102 ERAM logic, 2 x LUT6/REG/SLICE, 2 x PLL; "
             "DRAMHARDCON 85 counted once (shared controller). Falls in 271-300 -> "
             "conditional per frozen rule; includes second copy of 30 debug CWC ERAM, "
             "so this is an upper bound, not a production estimate.")),
        row("marginal+second_ddr", "marginal_2ddr", marg_eram, 2, marg_lut6, marg_lut6_logic_only,
            marg_reg, marg_slice, 0, 4, "unproven",
            "base=measured(b10); same marginal fabric; ddr_controllers=2 (assumed variant)",
            ("Variant: second independent DDR port/controller required -> +85 DRAMHARDCON. "
             "Not the default architecture (shared 256-bit PAXI, one DDR MC). "
             "LUT6/REG/SLICE identical to marginal (25,709/34,341/30,733).")),
        row("conservative+second_ddr", "conservative_2ddr", cons_eram, 2, cons_lut6, cons_lut6,
            cons_reg, cons_slice, 0, 8, "unproven",
            "base=measured(b10); full replication; ddr_controllers=2 (assumed variant)",
            ("Variant: full second chain plus second DDR controller -> 204+170=374/300, "
             "infeasible. Single-listed so the shared-controller assumption is auditable.")),
    ]
    return rows, {"delta": delta, "marg_slice": marg_slice, "base_work": base_work,
                  "delta_work": delta_work, "marg_lut6": marg_lut6,
                  "marg_lut6_logic_only": marg_lut6_logic_only}


def build_input_verified(src):
    files = []
    assertions = []
    for iid, role, path in INPUTS:
        exists = path.exists()
        rec = {"id": iid, "role": role, "path": str(path), "exists": exists,
               "bytes": None, "sha256": None, "read_only": True}
        if exists:
            rec["bytes"] = path.stat().st_size
            rec["sha256"] = sha256(path)
        files.append(rec)
        if not exists:
            assertions.append({"id": f"{iid}_exists", "match": False, "detail": "missing input"})
    # hard assertions mandated by the P1 dispatch
    core = next(f for f in files if f["id"] == "b6_core")
    mani = next(f for f in files if f["id"] == "b6_manifest")
    assertions.append({
        "id": "b6_core_sha256", "path": core["path"],
        "expected_sha256": EXPECT_CORE_SHA, "actual_sha256": core["sha256"],
        "expected_bytes": EXPECT_CORE_BYTES, "actual_bytes": core["bytes"],
        "match": core["sha256"] == EXPECT_CORE_SHA and core["bytes"] == EXPECT_CORE_BYTES,
    })
    assertions.append({
        "id": "b6_manifest_sha256", "path": mani["path"],
        "expected_sha256": EXPECT_B6_MANIFEST_SHA, "actual_sha256": mani["sha256"],
        "expected_bytes": 24443, "actual_bytes": mani["bytes"],
        "match": mani["sha256"] == EXPECT_B6_MANIFEST_SHA and mani["bytes"] == 24443,
    })
    # cross-check: manifest node and independent report both carry the frozen hashes
    manifest = json.loads(read_text(Path(mani["path"])))
    node = manifest["single_rtl_change"]
    assertions.append({
        "id": "b6_manifest_node_matches_core",
        "expected_sha256": EXPECT_CORE_SHA, "actual_sha256": node["sha256"],
        "expected_bytes": EXPECT_CORE_BYTES, "actual_bytes": node["bytes"],
        "match": node["sha256"] == EXPECT_CORE_SHA and node["bytes"] == EXPECT_CORE_BYTES,
    })
    rep = read_text(Path(next(f for f in files if f["id"] == "b6_report")["path"]))
    assertions.append({
        "id": "b6_report_carries_manifest_sha",
        "expected_sha256": EXPECT_B6_MANIFEST_SHA,
        "match": EXPECT_B6_MANIFEST_SHA in rep,
    })
    assertions.append({
        "id": "b6_report_carries_core_sha_short_form",
        "expected_sha256": EXPECT_CORE_SHA,
        "match": "6797db05" in rep and "35bb" in rep and "80,196" in rep,
        "detail": "report prints the frozen core hash in abbreviated 6797db05...35bb form",
    })
    # report arithmetic cross-checks (parsed, not copied from reports)
    for sid in ("b6", "b10", "b11"):
        s = src[sid]
        a, q, t = s["area"], s["qor"], s["timing"]
        assertions.append({
            "id": f"{sid}_area_qor_consistent",
            "match": (q["slices"] == a["stats"]["slice"] and q["rams"] == a["stats"]["eram"]
                      and round(q["setup_wns_ps"] / 1000.0, 3) == round(t["wns"], 3)
                      and round(q["hold_wns_ps"] / 1000.0, 3) == round(t["hold"], 3)),
            "detail": {"slices": q["slices"], "rams": q["rams"],
                       "qor_wns_ps": q["setup_wns_ps"], "timing_wns_ns": t["wns"]},
        })
        assertions.append({
            "id": f"{sid}_timing_endpoints_consistent",
            "match": t["viol_ep"] == 0 and t["hold_viol_ep"] == 0
                     and t["total_ep"] == t["hold_total_ep"] and t["has_187p5"],
            "detail": {"viol": t["viol_ep"], "total": t["total_ep"],
                       "hold_viol": t["hold_viol_ep"], "hold_total": t["hold_total_ep"]},
        })
    mismatch = sum(1 for x in assertions if not x["match"])
    out = {
        "task_id": "T10.dual-core-resource-baseline",
        "run_id": "20261025-195604_fpga-dual-aplus-core-feasibility",
        "round": "r0",
        "generated_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
        "generator": "gen_baseline.py (read-only over inputs)",
        "tool_versions": {
            "python": platform.python_version(),
            "td_report_header": "Tang Dynasty Release_2026.2",
            "td_version_line": "TD V6.2.3.210850",
            "device": "PH1P100SBG484",
            "speed": "3",
            "sta_confidence": "Routed",
        },
        "report_read_time_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
        "hard_assertions": assertions,
        "mismatch_count": mismatch,
        "inputs": files,
        "constants": {
            "device_totals": DEVICE, "logic_quota_210": LOGIC_QUOTA,
            "margin_target_270": MARGIN_TARGET, "clock_mhz": CLOCK_MHZ,
        },
        "notes": [
            "All three routed reports have Report Model p2_a1_board_top (same top).",
            "ERAM_total = #eram + #DRAMHARDCON: 102 + 85 = 187 per QoR and b10 result-r1.",
            "Synth ERAM 72 excludes 2x15 CWC debug RAMs inserted at routed; synth is checkpoint only.",
        ],
    }
    return out


RESOURCE_COLUMNS = ["source_id", "scope", "instance", "module", "top", "stage",
                    "ERAM_logic", "DRAM_HARDCON", "DRAM_LUT", "ERAM_total",
                    "LUT6", "REG", "SLICE", "DSP", "PLL", "WNS_ns", "HOLD_ns",
                    "viol_ep", "total_ep", "clock_mhz", "logic_lut", "ripple", "notes"]
BUDGET_COLUMNS = ["case_id", "column", "base_source", "basis", "cores", "streams",
                  "ERAM_logic", "DRAM_HARDCON_per_ddr", "ddr_controllers",
                  "DRAM_HARDCON_counted", "ERAM_total", "ERAM_device_total",
                  "ERAM_headroom", "headroom_pct", "ERAM_logic_quota_210",
                  "logic_headroom_210", "fit_300", "fit_210_logic",
                  "LUT_domain", "LUT6_total", "LUT6_logic_only_lower",
                  "LUT6_device_total", "LUT6_headroom",
                  "LUT4_equiv_upper", "LUT4_device_total", "LUT4_headroom", "LUT4_basis",
                  "REG_total", "REG_device_total", "REG_headroom",
                  "SLICE_total", "SLICE_device_total", "SLICE_headroom",
                  "DSP_total", "DSP_device_total", "PLL_total", "PLL_device_total",
                  "timing_status", "labels", "notes"]


def write_csv(path, columns, rows):
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=columns)
        w.writeheader()
        for r in rows:
            w.writerow({k: r.get(k, "") for k in columns})


def write_json(path, obj):
    path.write_text(json.dumps(obj, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


FIXTURES = [
    {
        "fixture_id": "NEG-01-synth-mixed-into-routed-fit",
        "kind": "resource_table_rows",
        "description": "Synth-stage ERAM/LUT6 row is marked used_in_fit, mixing synth with routed.",
        "expected_reject": "STAGE_MIX_SYNTH_IN_FIT",
        "rows": [
            {"source_id": "b6", "scope": "top", "stage": "routed", "ERAM_logic": 102,
             "DRAM_HARDCON": 85, "used_in_fit": True},
            {"source_id": "b6", "scope": "top", "stage": "synth", "ERAM_logic": 72,
             "DRAM_HARDCON": "", "used_in_fit": True},
        ],
    },
    {
        "fixture_id": "NEG-02-missing-dramhardcon",
        "kind": "budget_rows",
        "description": "ERAM_total omits the 85 DRAM hard controllers (146 instead of 231).",
        "expected_reject": "MISSING_DRAMHARDCON",
        "rows": [
            {"case_id": "marginal", "column": "marginal", "ERAM_logic": 146,
             "DRAM_HARDCON_per_ddr": 85, "ddr_controllers": 1, "ERAM_total": 146},
            {"case_id": "conservative", "column": "conservative", "ERAM_logic": 204,
             "DRAM_HARDCON_per_ddr": 85, "ddr_controllers": 1, "ERAM_total": 289},
        ],
    },
    {
        "fixture_id": "NEG-03-top102x2-single-column",
        "kind": "budget_rows",
        "description": "Top-level 102x2=204 is used as the only dual-core column; marginal/conservative columns are absent.",
        "expected_reject": "MISSING_TWO_COLUMN_BUDGET",
        "rows": [
            {"case_id": "top102x2", "column": "top102x2", "ERAM_logic": 204,
             "DRAM_HARDCON_per_ddr": 85, "ddr_controllers": 1, "ERAM_total": 289},
        ],
    },
]


def main():
    R0.mkdir(parents=True, exist_ok=True)
    (R0 / "tests" / "negative").mkdir(parents=True, exist_ok=True)
    src = get_sources()
    iv = build_input_verified(src)
    write_json(R0 / "input-verified.json", iv)
    if iv["mismatch_count"] != 0:
        print(f"BLOCKED: mismatch_count={iv['mismatch_count']}")
        return 2
    rows = build_resource_rows(src)
    write_csv(R0 / "resource-table.csv", RESOURCE_COLUMNS, rows)
    budget, meta = build_budget(src)
    write_csv(R0 / "dual-core-budget.csv", BUDGET_COLUMNS, budget)
    for fx in FIXTURES:
        write_json(R0 / "tests" / "negative" / (fx["fixture_id"].lower() + ".json"), fx)
    print("P1_GEN_OK")
    print(f"inputs={len(iv['inputs'])} assertions={len(iv['hard_assertions'])} mismatch={iv['mismatch_count']}")
    print(f"resource_rows={len(rows)} budget_rows={len(budget)} fixtures={len(FIXTURES)}")
    print(f"delta={meta['delta']} marginal_slice={meta['marg_slice']}")
    for r in budget:
        print(f"{r['column']}: ERAM_logic={r['ERAM_logic']} total={r['ERAM_total']} "
              f"headroom={r['ERAM_headroom']} pct={r['headroom_pct']} fit300={r['fit_300']} "
              f"fit210={r['fit_210_logic']} LUT6={r['LUT6_total']} REG={r['REG_total']} "
              f"SLICE={r['SLICE_total']} PLL={r['PLL_total']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
