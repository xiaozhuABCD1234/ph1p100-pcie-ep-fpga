#!/usr/bin/env python3
"""Independent tester re-parse / re-computation for P1 (round0).

Deliberately does NOT import gen_baseline.py or check_tables.py.
Read-only: writes nothing except stdout.
"""
import csv
import hashlib
import json
import math
import re
import sys
from pathlib import Path

PROJ = Path("D:/fpga/ph1p100")
RUN = PROJ / "workflow/runs/20261025-195604_fpga-dual-aplus-core-feasibility"
R0 = RUN / "T10.dual-core-resource-baseline" / "r0"
B = {
    "b6": PROJ / "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b6-a1-htab-nw/r0/td",
    "b10": PROJ / "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b10-b9-fix/r0/td",
    "b11": PROJ / "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b11-aplus-read/r0/td",
}
DEV = {"eram": 300, "lut6": 71680, "lut4": 129024, "reg": 143360,
       "dsp": 220, "pll": 12, "slice": 71680}
QUOTA = 210
TARGET = 270
CORE_SHA = "6797db053cfc47497540d6345e3a46b7e79cc1d34fa25da5a4c501505fbf35bb"
MANIFEST_SHA = "2e9fd356824084813e3415af11757c1b56f774c9b6dd45f3b2a111647ad08880"

FAIL = []


def sha256(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def txt(p):
    raw = Path(p).read_bytes()
    if raw.startswith(b"\xff\xfe") or raw.startswith(b"\xfe\xff"):
        return raw.decode("utf-16")
    return raw.decode("utf-8", errors="replace")


def parse_area(path):
    t = txt(path)
    m = re.search(r"\*\*\*Report Model:\s*(\S+)\s+Device:\s*(\S+)\*\*\*", t)
    model, device = (m.group(1), m.group(2)) if m else (None, None)
    stats = {}
    pats = {
        "lut6": r"^\s*#lut6\s+(\d+)",
        "lut": r"^\s*#lut\s+(\d+)",
        "reg": r"^\s*#reg\s+(\d+)",
        "slice": r"^\s*#slice\*?\s+(\d+)",
        "used_ram": r"^\s*#used ram\s+(\d+)",
        "dram_lut": r"^\s*#dram lut\s+(\d+)",
        "shifter_lut": r"^\s*#shifter lut\s+(\d+)",
        "with_luts": r"^\s*#with luts\*?\s+(\d+)",
        "with_adder": r"^\s*#with adder\s+(\d+)",
        "reg_only": r"^\s*#reg only\*?\s+(\d+)",
        "eram": r"^\s*#eram\s+(\d+)",
        "dsp": r"^\s*#dsp\s+(\d+)",
        "pll": r"^\s*#pll\s+(\d+)",
    }
    for key, pat in pats.items():
        m = re.search(pat, t, re.M)
        if m:
            stats[key] = int(m.group(1))
    hier = []
    in_h = False
    for line in t.splitlines():
        if line.startswith("Report Hierarchy Area:"):
            in_h = True
            continue
        if not in_h or not line.startswith("|"):
            continue
        cells = line.split("|")
        if len(cells) < 17:
            continue
        inst = cells[1]
        if not inst.strip() or inst.strip() == "Instance":
            continue
        nums = []
        ok = True
        for c in cells[3:16]:
            try:
                nums.append(int(c.strip()))
            except ValueError:
                ok = False
                break
        if not ok:
            continue
        hier.append({
            "indent": len(inst) - len(inst.lstrip(" ")),
            "name": inst.strip(), "module": cells[2].strip(),
            "logic": nums[0], "ripple": nums[1], "seq": nums[2], "eram": nums[3],
            "dsp": nums[4], "dram_lut": nums[5], "shifter_lut": nums[6],
            "pll": nums[9], "ddr": nums[12],
        })
    return {"model": model, "device": device, "stats": stats, "hier": hier}


def parse_qor(path):
    vals = {}
    for line in txt(path).splitlines():
        m = re.match(r"\|\s*([^|]+?)\s*\|\s*(\d+)\s*\|", line)
        if m:
            vals[m.group(1).strip()] = int(m.group(2))
    return vals


def parse_timing(path):
    t = txt(path)
    def f(pat):
        m = re.search(pat, t)
        return float(m.group(1)) if m else None
    hdr = {
        "swms": f(r"SWNS:\s*(-?[\d.]+)ns"),
        "hwns": f(r"HWNS:\s*(-?[\d.]+)ns"),
        "period_check_wns": f(r"Period Check WNS:\s*(-?[\d.]+)ns"),
    }
    mx = re.search(r"Max\s+:\s+SWNS\s+(-?[\d.]+)ns,\s+STNS\s+(-?[\d.]+)ns,\s+(\d+)\s+Viol Endpoints,\s+(\d+)\s+Total Endpoints", t)
    mn = re.search(r"Min\s+:\s+HWNS\s+(-?[\d.]+)ns,\s+HTNS\s+(-?[\d.]+)ns,\s+(\d+)\s+Viol Endpoints,\s+(\d+)\s+Total Endpoints", t)
    clk = {}
    for line in t.splitlines():
        s = line.strip()
        if s.startswith("clk0 "):
            tok = s.split()
            # clk0 Type Rise Fall C-P C-F R-P R-F SWNS STNS HWNS HTNS Skew Fanout MaxLevel ...
            clk = {"name": tok[1], "c_freq": float(tok[6]), "r_freq": float(tok[8]),
                   "swms": float(tok[9]), "hwns": float(tok[11])}
            break
    name_m = re.search(r"clk0:\s+([\d.]+)\s+\d+\s+(\S+)", t)
    clk_name = name_m.group(2) if name_m else None
    return {"header": hdr, "max": mx.groups() if mx else None,
            "min": mn.groups() if mn else None, "clk0": clk, "clk_name": clk_name,
            "confidence": "Routed" if "Confidence          : Routed" in t else "?",
            "top": re.search(r"Top Model\s+:\s+(\S+)", t).group(1) if re.search(r"Top Model\s+:\s+(\S+)", t) else None}


def hier_find(hier, name, module):
    for r in hier:
        if r["name"] == name and r["module"] == module:
            return r
    return None


def main():
    src = {}
    for sid in B:
        a = parse_area(B[sid] / "routed_area.rpt")
        q = parse_qor(B[sid] / "routed_qor.rpt")
        tm = parse_timing(B[sid] / "routed_timing.rpt")
        sy = parse_area(B[sid] / "syn_gate_area.rpt")
        src[sid] = {"area": a, "qor": q, "tim": tm, "syn": sy}

    # ---- 1. top-level routed facts, independent ----
    print("== 1. routed top-level ==")
    for sid in ("b6", "b10", "b11"):
        a, q, t = src[sid]["area"], src[sid]["qor"], src[sid]["tim"]
        st = a["stats"]
        print(f"{sid}: model={a['model']} dev={a['device']} lut6={st['lut6']} reg={st['reg']} "
              f"slice={st['slice']} eram={st['eram']} dramlut={st['dram_lut']} dsp={st['dsp']} pll={st['pll']} "
              f"qor_wns={q['Setup WNS']}ps qor_hold={q['Hold WNS']}ps dramhardcon={q['#DRAMHARDCON']} "
              f"tim_swms={t['header']['swms']} tim_hwns={t['header']['hwns']} "
              f"ep={t['max'][3]}/{t['min'][3]} viol={t['max'][2]}/{t['min'][2]} "
              f"clk0={t['clk_name']}@{t['clk0'].get('c_freq')}MHz swms={t['clk0'].get('swms')} "
              f"periodchk={t['header']['period_check_wns']}")
        # identity #lut6 = logic + ripple + dram_lut + shifter_lut
        ident = st["with_luts"] + st["with_adder"] + st["dram_lut"] + st["shifter_lut"]
        print(f"   LUT6 identity: {st['with_luts']}+{st['with_adder']}+{st['dram_lut']}+{st['shifter_lut']}="
              f"{ident} vs #lut6={st['lut6']} -> {'OK' if ident == st['lut6'] else 'MISMATCH'}")
        if ident != st["lut6"]:
            FAIL.append(f"{sid}_lut6_identity")
        if st["eram"] + q["#DRAMHARDCON"] != 187:
            FAIL.append(f"{sid}_eram187")
        # hierarchy closure
        top = hier_find(a["hier"], "top", a["model"])
        d1 = [r for r in a["hier"] if r["indent"] == 2]
        sums = {k: sum(r[k] for r in d1) for k in ("eram", "dram_lut", "pll", "dsp", "logic", "ripple", "seq")}
        print(f"   closure depth1: ERAM {sums['eram']}/{top['eram']} dram_lut {sums['dram_lut']}/{top['dram_lut']} "
              f"PLL {sums['pll']}/{top['pll']} DSP {sums['dsp']}/{top['dsp']} "
              f"logic res {top['logic']-sums['logic']} ripple res {top['ripple']-sums['ripple']} "
              f"seq res {top['seq']-sums['seq']}")
        for k in ("eram", "dram_lut", "pll", "dsp"):
            if sums[k] != top[k]:
                FAIL.append(f"{sid}_closure_{k}")
        for k in ("logic", "ripple", "seq"):
            res = top[k] - sums[k]
            if res < 0 or res > math.ceil(0.02 * top[k]):
                FAIL.append(f"{sid}_closure_{k}_residual")
        core = hier_find(a["hier"], "u_core", "a1_deflate_core")
        bridge = hier_find(a["hier"], "u_bridge", "p2_ddr_bridge")
        mcu = hier_find(a["hier"], "u_mcu_core", "usr_mcu_core")
        print(f"   u_core={core} | u_bridge ERAM={bridge['eram']} | u_mcu_core ERAM={mcu['eram']}")
        if (core["eram"], bridge["eram"], mcu["eram"]) != (23, 15, 28):
            FAIL.append(f"{sid}_attrib")

    # ---- 2. synth rows ----
    print("== 2. synth checkpoint ==")
    for sid in ("b6", "b10", "b11"):
        a, sy = src[sid]["area"], src[sid]["syn"]
        print(f"{sid} synth: model={sy['model']} eram={sy['stats']['eram']} lut6={sy['stats']['lut6']} "
              f"reg={sy['stats']['reg']} slice={sy['stats']['slice']} dsp={sy['stats']['dsp']} pll={sy['stats']['pll']} "
              f"dramhardcon_line={'yes' if '#DRAMHARDCON' in txt(B[sid]/'syn_gate_area.rpt') else 'no'}")
        if sy["stats"]["eram"] + 2 * 15 != a["stats"]["eram"]:
            FAIL.append(f"{sid}_synth_routed_eram")
        if sy["stats"]["lut6"] == a["stats"]["lut6"]:
            FAIL.append(f"{sid}_synth_eq_routed")

    # ---- 3. resource-table.csv vs reports ----
    print("== 3. resource-table.csv ==")
    rows = list(csv.DictReader(open(R0 / "resource-table.csv", newline="", encoding="utf-8")))
    print("rows:", len(rows))
    if len(rows) != 64:
        FAIL.append("csv_row_count")
    by = {}
    for r in rows:
        by.setdefault((r["source_id"], r["scope"], r["instance"], r["module"], r["stage"]), []).append(r)
    def one(**kw):
        out = [r for r in rows if all(r[k] == v for k, v in kw.items())]
        return out[0] if len(out) == 1 else None
    for sid in ("b6", "b10", "b11"):
        a, q, t, sy = src[sid]["area"], src[sid]["qor"], src[sid]["tim"], src[sid]["syn"]
        r = one(source_id=sid, scope="top", stage="routed")
        if r is None:
            FAIL.append(f"{sid}_top_routed_row"); continue
        checks = {
            "top": a["model"], "ERAM_logic": a["stats"]["eram"],
            "DRAM_HARDCON": q["#DRAMHARDCON"], "DRAM_LUT": a["stats"]["dram_lut"],
            "ERAM_total": a["stats"]["eram"] + q["#DRAMHARDCON"],
            "LUT6": a["stats"]["lut6"], "REG": a["stats"]["reg"], "SLICE": a["stats"]["slice"],
            "DSP": a["stats"]["dsp"], "PLL": a["stats"]["pll"],
            "WNS_ns": f"{t['header']['swms']:.3f}", "HOLD_ns": f"{t['header']['hwns']:.3f}",
            "viol_ep": str(t["max"][2]), "total_ep": str(t["max"][3]), "clock_mhz": "187.5",
        }
        for k, v in checks.items():
            if k in ("WNS_ns", "HOLD_ns"):
                same = abs(float(r[k]) - float(v)) < 1e-9
            else:
                same = str(r[k]) == str(v)
            if not same:
                print(f"  MISMATCH {sid} routed {k}: csv={r[k]!r} report={v!r}")
                FAIL.append(f"{sid}_csv_{k}")
        s = one(source_id=sid, scope="top", stage="synth")
        if s is None:
            FAIL.append(f"{sid}_top_synth_row")
        else:
            for k, v in {"ERAM_logic": sy["stats"]["eram"], "ERAM_total": sy["stats"]["eram"],
                         "DRAM_LUT": sy["stats"]["dram_lut"], "LUT6": sy["stats"]["lut6"],
                         "REG": sy["stats"]["reg"], "SLICE": sy["stats"]["slice"],
                         "DSP": sy["stats"]["dsp"], "PLL": sy["stats"]["pll"]}.items():
                if str(s[k]) != str(v):
                    print(f"  MISMATCH {sid} synth {k}: csv={s[k]!r} report={v!r}")
                    FAIL.append(f"{sid}_csv_synth_{k}")
            if s["DRAM_HARDCON"] or s["WNS_ns"] or s["HOLD_ns"]:
                print(f"  synth row {sid} carries routed-only field")
                FAIL.append(f"{sid}_synth_carries_routed")
        # hierarchy rows
        for r in [x for x in rows if x["source_id"] == sid and x["scope"] == "hierarchy"]:
            h = hier_find(a["hier"], r["instance"], r["module"])
            if h is None:
                print(f"  hierarchy row not found in report: {sid}/{r['instance']}/{r['module']}")
                FAIL.append(f"{sid}_hier_missing")
                continue
            for k, v in {"logic_lut": h["logic"], "ripple": h["ripple"], "REG": h["seq"],
                         "ERAM_logic": h["eram"], "ERAM_total": h["eram"],
                         "DRAM_LUT": h["dram_lut"], "DSP": h["dsp"], "PLL": h["pll"]}.items():
                if str(r[k]) != str(v):
                    print(f"  MISMATCH {sid}/{r['instance']} {k}: csv={r[k]!r} report={v!r}")
                    FAIL.append(f"{sid}_hier_{k}")
            if r["DRAM_HARDCON"] or r["LUT6"] or r["SLICE"] or r["WNS_ns"] or r["HOLD_ns"]:
                print(f"  hierarchy row {sid}/{r['instance']} carries top-only field")
                FAIL.append(f"{sid}_hier_top_field")
    print("  report-vs-csv mismatches: see lines above (none printed = clean)")

    # ---- 4. dual-core budget independent recomputation ----
    print("== 4. dual-core budget ==")
    a10, q10 = src["b10"]["area"], src["b10"]["qor"]
    h10 = a10["hier"]
    base = {"eram": a10["stats"]["eram"], "lut6": a10["stats"]["lut6"],
            "reg": a10["stats"]["reg"], "slice": a10["stats"]["slice"],
            "dsp": a10["stats"]["dsp"], "pll": a10["stats"]["pll"]}
    core = hier_find(h10, "u_core", "a1_deflate_core")
    bridge = hier_find(h10, "u_bridge", "p2_ddr_bridge")
    frame = hier_find(h10, "u_a1", "a1_frame_top")
    fab = [hier_find(h10, n, m) for n, m in [
        ("u_cam_fifo", "capture_async_fifo"), ("u_arb", "a1_ddr_arb2"),
        ("u_cmp_store", "a1_ddr_slot_store"), ("u_crop", "a1_raw_crop"),
        ("u_export", "a1_uart_export"), ("u_raw_store", "a1_ddr_slot_store")]]
    d_eram = core["eram"] + bridge["eram"] + (frame["eram"] - core["eram"]) + sum(x["eram"] for x in fab)
    d_logic = core["logic"] + bridge["logic"] + (frame["logic"] - core["logic"]) + sum(x["logic"] for x in fab)
    d_ripple = core["ripple"] + bridge["ripple"] + (frame["ripple"] - core["ripple"]) + sum(x["ripple"] for x in fab)
    d_seq = core["seq"] + bridge["seq"] + (frame["seq"] - core["seq"]) + sum(x["seq"] for x in fab)
    d_dram = core["dram_lut"] + sum(x["dram_lut"] for x in fab)
    top = hier_find(h10, "top", a10["model"])
    print(f"delta: eram={d_eram} logic={d_logic} ripple={d_ripple} seq={d_seq} dram_lut={d_dram}")
    if (d_eram, d_logic, d_ripple, d_seq, d_dram) != (44, 3793, 2077, 6337, 144):
        FAIL.append("budget_delta")
    marg_logic = base["eram"] + d_eram
    marg_total = marg_logic + q10["#DRAMHARDCON"]
    marg_lut6_dev = base["lut6"] + d_logic
    marg_lut6_td = base["lut6"] + d_logic + d_ripple + d_dram
    marg_reg = base["reg"] + d_seq
    marg_slice = round(base["slice"] * (1 + (d_logic + d_ripple + d_seq) / (top["logic"] + top["ripple"] + top["seq"])))
    cons_logic = 2 * base["eram"]
    cons_total = cons_logic + q10["#DRAMHARDCON"]
    cons_lut6 = 2 * base["lut6"]
    cons_reg = 2 * base["reg"]
    cons_slice = 2 * base["slice"]
    cons_pll = 2 * base["pll"]
    print(f"marginal: logic={marg_logic} total={marg_total} headroom={300-marg_total} "
          f"pct={100*(300-marg_total)/300:.2f} LUT6_dev={marg_lut6_dev} LUT6_TD={marg_lut6_td} "
          f"REG={marg_reg} SLICE={marg_slice}")
    print(f"conservative: logic={cons_logic} total={cons_total} headroom={300-cons_total} "
          f"pct={100*(300-cons_total)/300:.2f} LUT6={cons_lut6} REG={cons_reg} SLICE={cons_slice} PLL={cons_pll}")
    print(f"2ddr variants: marginal={marg_logic+2*q10['#DRAMHARDCON']} "
          f"conservative={cons_logic+2*q10['#DRAMHARDCON']}")
    # round1: the marginal LUT6 must be the TD LUT6-equivalent (25,709), not the
    # round0 logic-only 23,488.  The old pre-fix expectation was updated here.
    if (marg_logic, marg_total, marg_lut6_td, marg_reg, marg_slice) != (146, 231, 25709, 34341, 30733):
        FAIL.append("budget_marginal_expected")
    if marg_lut6_td != 25709:
        FAIL.append("budget_marginal_td_lut6")
    if (cons_logic, cons_total, cons_lut6, cons_reg, cons_slice, cons_pll) != (204, 289, 39390, 56008, 48736, 8):
        FAIL.append("budget_conservative")
    # compare every budget CSV row
    brows = list(csv.DictReader(open(R0 / "dual-core-budget.csv", newline="", encoding="utf-8")))
    cols = [r["column"] for r in brows]
    print("budget columns:", cols)
    if cols.count("marginal") != 1 or cols.count("conservative") != 1:
        FAIL.append("budget_two_column")
    if len(brows) != 4:
        FAIL.append("budget_row_count")
    for r in brows:
        exp = {
            "marginal": (marg_logic, marg_total, marg_lut6_td, marg_reg, marg_slice, base["pll"]),
            "conservative": (cons_logic, cons_total, cons_lut6, cons_reg, cons_slice, cons_pll),
            "marginal_2ddr": (marg_logic, marg_logic + 2 * q10["#DRAMHARDCON"], marg_lut6_td, marg_reg, marg_slice, base["pll"]),
            "conservative_2ddr": (cons_logic, cons_logic + 2 * q10["#DRAMHARDCON"], cons_lut6, cons_reg, cons_slice, cons_pll),
        }[r["column"]]
        got = (int(r["ERAM_logic"]), int(r["ERAM_total"]), int(r["LUT6_total"]),
               int(r["REG_total"]), int(r["SLICE_total"]), int(r["PLL_total"]))
        if got != exp:
            print(f"  BUDGET MISMATCH {r['column']}: {got} != {exp}")
            FAIL.append(f"budget_{r['column']}")
        want300 = "pass" if int(r["ERAM_total"]) <= TARGET else ("conditional" if int(r["ERAM_total"]) <= 300 else "fail")
        want210 = "pass" if int(r["ERAM_logic"]) <= QUOTA else ("conditional" if int(r["ERAM_logic"]) <= 300 else "fail")
        if r["fit_300"] != want300 or r["fit_210_logic"] != want210:
            print(f"  FIT FLAG MISMATCH {r['column']}: {r['fit_300']}/{r['fit_210_logic']} want {want300}/{want210}")
            FAIL.append(f"fit_{r['column']}")
        if r["LUT_domain"] != "TD_LUT6" or int(r["LUT4_equiv_upper"]) != 2 * int(r["LUT6_total"]):
            FAIL.append(f"lut_domain_{r['column']}")
        if int(r["LUT6_headroom"]) != 71680 - int(r["LUT6_total"]):
            FAIL.append(f"lut6_headroom_{r['column']}")
        if int(r["LUT4_headroom"]) != 129024 - int(r["LUT4_equiv_upper"]):
            FAIL.append(f"lut4_headroom_{r['column']}")
        if r["timing_status"] != "unproven":
            FAIL.append(f"timing_status_{r['column']}")
        if int(r["ERAM_headroom"]) != 300 - int(r["ERAM_total"]):
            FAIL.append(f"eram_headroom_{r['column']}")
        if int(r["logic_headroom_210"]) != 210 - int(r["ERAM_logic"]):
            FAIL.append(f"logic210_{r['column']}")
        # round1 F1: TD LUT6 total + separately labelled logic-only lower bound
        if "LUT6_logic_only_lower" not in r:
            FAIL.append(f"lut6_lower_missing_{r['column']}")
        else:
            low = int(r["LUT6_logic_only_lower"])
            want_low = 23488 if r["column"].startswith("marginal") else 39390
            if low != want_low or low > int(r["LUT6_total"]):
                print(f"  LUT6 LOWER MISMATCH {r['column']}: lower={low} total={r['LUT6_total']} want_low={want_low}")
                FAIL.append(f"lut6_lower_{r['column']}")
            if r["column"].startswith("marginal") and int(r["LUT6_total"]) - low != 2077 + 144:
                FAIL.append(f"lut6_lower_gap_{r['column']}")
    # round1 F3: camera/CSI + b11 domain notes must match routed evidence
    rt_rows = rows  # resource-table rows from section 3
    cam = next((r for r in rt_rows if r["source_id"] == "b10" and r["scope"] == "hierarchy"
                and r["instance"] == "u_camera"), None)
    b11top = next((r for r in rt_rows if r["source_id"] == "b11" and r["scope"] == "top"
                   and r["stage"] == "routed"), None)
    mn = next(r for r in brows if r["column"] == "marginal")["notes"]
    if cam is None or not ("ONLY u_csi_a" in cam["notes"] and "u_csi_b" in cam["notes"]
                           and "773" in cam["notes"]):
        print(f"  F3 camera note missing/insufficient: {cam['notes'] if cam else None}")
        FAIL.append("f3_camera_row_note")
    if b11top is None or not ("ddr_user" in b11top["notes"] and "0.059" in b11top["notes"]):
        print(f"  F3 b11 domain note missing: {b11top['notes'] if b11top else None}")
        FAIL.append("f3_b11_domain_note")
    if not ("u_csi_b" in mn and "773" in mn and ("26822" in mn or "26,822" in mn)):
        print(f"  F3 marginal note missing CSI add-on: {mn}")
        FAIL.append("f3_budget_note")
    rb = txt(R0 / "resource-baseline.md")
    for tok in ("25,709", "51,418", "45,971", "77,606", "u_csi_a", "u_csi_b", "773",
                "ddr_user", "0.059"):
        if tok not in rb:
            print(f"  resource-baseline.md missing token: {tok}")
            FAIL.append(f"doc_missing_{tok}")
    if "26,822" not in rb and "26822" not in rb:
        FAIL.append("doc_missing_csi_addon")
    ct = txt(R0 / "check_tables.py")
    if "LUT6_logic_only_lower" not in ct or "check_lut6_identity" not in ct:
        FAIL.append("checker_missing_td_identity")
    cklog = txt(R0 / "logs/check_tables.out.txt")
    for name in ("inputs_frozen_0_mismatch_no_drift", "resource_table_matches_reports",
                 "lut6_identity_td", "hierarchy_sums_close_to_top",
                 "dual_core_budget_arithmetic", "negative_controls_rejected"):
        if f"PASS {name}" not in cklog:
            print(f"  check_tables log missing PASS {name}")
            FAIL.append(f"cklog_{name}")
    mrow = next(r for r in brows if r["column"] == "marginal")
    if int(mrow["LUT6_total"]) != marg_lut6_td:
        print(f"  FINDING marginal LUT6_total CSV={mrow['LUT6_total']} but TD LUT6-equivalent="
              f"{marg_lut6_td} (missing ripple {d_ripple} + DRAM_LUT {d_dram})")
        FAIL.append("marginal_lut6_understated")
    print(f"  marginal TD LUT6={marg_lut6_td} (logic-only lower={marg_lut6_dev}); "
          f"LUT4 upper=2*{marg_lut6_td}={2*marg_lut6_td}; CSV LUT6={mrow['LUT6_total']} "
          f"lower={mrow.get('LUT6_logic_only_lower')}")

    # ---- 5. negative controls, tester's own rules ----
    print("== 5. negative fixtures ==")
    nfiles = sorted((R0 / "tests" / "negative").glob("*.json"))
    print("fixtures:", [p.name for p in nfiles])
    if len(nfiles) != 3:
        FAIL.append("neg_count")
    for p in nfiles:
        fx = json.loads(txt(p))
        kind, rows = fx["kind"], fx["rows"]
        code = None
        if kind == "resource_table_rows":
            if any(r.get("used_in_fit") and r.get("stage") != "routed" for r in rows):
                code = "STAGE_MIX_SYNTH_IN_FIT"
        elif kind == "budget_rows":
            cols = [r.get("column") for r in rows]
            if cols.count("marginal") != 1 or cols.count("conservative") != 1:
                code = "MISSING_TWO_COLUMN_BUDGET"
            else:
                for r in rows:
                    if r.get("ERAM_total") == r.get("ERAM_logic") and r.get("ddr_controllers", 0) >= 1 and r.get("DRAM_HARDCON_per_ddr", 0) > 0:
                        code = "MISSING_DRAMHARDCON"
                        break
        print(f"  {fx['fixture_id']}: expected={fx['expected_reject']} tester_reject={code}")
        if code != fx["expected_reject"]:
            FAIL.append(f"neg_{p.name}")

    # ---- 6. manifest / input integrity ----
    print("== 6. manifest / inputs ==")
    man = json.loads(txt(R0 / "manifest-r0.json"))
    print("manifest: status", man["status"], "stopped", man["stopped_modifying"],
          "active", man["active_commands"], "artifacts", len(man["artifacts"]),
          "inputs", len(man["inputs"]), "commands", len(man["commands"]))
    if not (man["stopped_modifying"] is True and man["active_commands"] == 0):
        FAIL.append("manifest_not_stopped")
    if man["status"] != "ready_for_test":
        FAIL.append("manifest_status")
    # artifacts
    art_bad = []
    for a in man["artifacts"]:
        p = Path(a["path"])
        if not p.exists() or p.stat().st_size != a["bytes"] or sha256(p) != a["sha256"]:
            art_bad.append(a["rel"])
    print("artifact hash mismatches:", art_bad or "none")
    if art_bad:
        FAIL.append("artifact_hash")
    # artifact set = all files under r0 except exclusions
    excluded = {"manifest-r0.json", "logs/mk_manifest.out.txt"}
    actual = set()
    for p in R0.rglob("*"):
        if p.is_file():
            rel = p.relative_to(R0).as_posix()
            if rel in excluded or "__pycache__" in rel:
                continue
            actual.add(rel)
    listed = {a["rel"] for a in man["artifacts"]}
    print("files not in manifest:", sorted(actual - listed) or "none")
    print("manifest entries missing on disk:", sorted(listed - actual) or "none")
    if actual != listed:
        FAIL.append("artifact_set")
    # inputs
    iv = json.loads(txt(R0 / "input-verified.json"))
    print("input-verified: mismatch_count", iv["mismatch_count"], "inputs", len(iv["inputs"]),
          "assertions", len(iv["hard_assertions"]))
    if iv["mismatch_count"] != 0:
        FAIL.append("iv_mismatch")
    by_id = {x["id"]: x for x in iv["inputs"]}
    if by_id["b6_core"]["sha256"] != CORE_SHA or by_id["b6_core"]["bytes"] != 80196:
        FAIL.append("b6_core_assert")
    if by_id["b6_manifest"]["sha256"] != MANIFEST_SHA:
        FAIL.append("b6_manifest_assert")
    drift = []
    for rec in iv["inputs"]:
        p = Path(rec["path"])
        if not p.exists() or p.stat().st_size != rec["bytes"] or sha256(p) != rec["sha256"]:
            drift.append(rec["id"])
    print("input drift:", drift or "none")
    if drift:
        FAIL.append("input_drift")
    man_ids = {x["id"]: x for x in man["inputs"]}
    if set(man_ids) != set(by_id):
        FAIL.append("manifest_input_set")
    for k, v in by_id.items():
        m = man_ids.get(k)
        if not m or m["path"] != v["path"] or m["sha256"] != v["sha256"] or m["bytes"] != v["bytes"]:
            FAIL.append(f"manifest_input_{k}")
    # commands
    cmds = [json.loads(line) for line in txt(R0 / "commands.jsonl").splitlines() if line.strip()]
    print("commands.jsonl:", len(cmds), "manifest commands:", len(man["commands"]))
    if len(cmds) != len(man["commands"]):
        FAIL.append("command_count")
    # manifest self-hash vs mk_manifest log
    raw = (R0 / "logs" / "mk_manifest.out.txt").read_bytes()
    mklog = None
    for enc in ("utf-8", "utf-16", "utf-16-le", "latin-1"):
        try:
            mklog = raw.decode(enc)
            break
        except UnicodeDecodeError:
            continue
    m = re.search(r"sha256=([0-9a-f]{64})", mklog or "")
    cur = sha256(R0 / "manifest-r0.json")
    print(f"manifest current sha={cur}")
    print(f"mk_manifest log sha={m.group(1) if m else None} -> {'MATCH' if m and m.group(1)==cur else 'STALE/DIFFERENT'}")
    if not m or m.group(1) != cur:
        FAIL.append("manifest_log_stale")
    # tools no TD/hardware
    tools = man["tools"]
    zero = {k: tools[k] for k in ("td_invocations", "synthesis", "place_route", "bitgen", "cwc", "download", "board", "modelsim")}
    print("tools:", zero)
    if any(v != 0 for v in zero.values()):
        FAIL.append("tools_nonzero")
    # no TD/bit artifacts in task dir
    bad = [p.name for p in R0.rglob("*") if p.is_file() and p.suffix.lower() in (".bit", ".cwc", ".sdc", ".sv", ".v")]
    print("TD-like files in task dir:", bad or "none")
    if bad:
        FAIL.append("td_like_files")

    # ---- 7. b11 domain caveat ----
    print("== 7. b11 WNS domain ==")
    t11 = src["b11"]["tim"]
    print(f"b11 global SWNS={t11['header']['swms']} clk_a1={t11['clk0'].get('swms')} "
          f"(clk0 name={t11['clk_name']}); global 0.015 is ddr_user 200MHz, clk_a1 187.5MHz is 0.059")

    print("== RESULT ==")
    print("FAIL_ITEMS:", FAIL if FAIL else "none")
    print(json.dumps({"status": "PASS" if not FAIL else "FAIL", "fail_items": FAIL}, ensure_ascii=False))
    return 0 if not FAIL else 1


if __name__ == "__main__":
    sys.exit(main())
