#!/usr/bin/env python3
"""P1 independent checker for T10.dual-core-resource-baseline.

Reads the frozen routed/synth reports again (own parser, no import of the
generator), validates resource-table.csv and dual-core-budget.csv, and runs
three negative controls. Exit 0 only if every check passes.

No TD, no synthesis, no hardware. Read-only except stdout.
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
    "b6": PROJ / "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b6-a1-htab-nw",
    "b10": PROJ / "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b10-b9-fix",
    "b11": PROJ / "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b11-aplus-read",
}
EXPECT_CORE = "6797db053cfc47497540d6345e3a46b7e79cc1d34fa25da5a4c501505fbf35bb"
EXPECT_MANIFEST = "2e9fd356824084813e3415af11757c1b56f774c9b6dd45f3b2a111647ad08880"
DEV = {"eram": 300, "lut6": 71680, "lut4": 129024, "reg": 143360,
       "dsp": 220, "pll": 12, "slice": 71680}
QUOTA = 210
TARGET = 270

RESULTS = []


class CheckError(RuntimeError):
    def __init__(self, code, detail=""):
        super().__init__(f"{code}: {detail}")
        self.code = code
        self.detail = detail


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def text_of(path):
    return path.read_text(encoding="utf-8", errors="replace")


def parse_area(path):
    stats, hier = {}, []
    model = device = None
    in_h = False
    for line in text_of(path).splitlines():
        if model is None:
            m = re.search(r"Report Model:\s*(\S+)\s+Device:\s*(\S+)\*\*\*", line)
            if m:
                model, device = m.group(1), m.group(2)
        s = line.strip()
        for key, pat in (("lut6", r"#lut6\s+(\d+)"), ("lut", r"#lut\s+(\d+)"),
                         ("reg", r"#reg\s+(\d+)"), ("slice", r"#slice\*?\s+(\d+)"),
                         ("eram", r"#eram\s+(\d+)"), ("dsp", r"#dsp\s+(\d+)"),
                         ("pll", r"#pll\s+(\d+)"), ("dram_lut", r"#dram lut\s+(\d+)"),
                         ("with_luts", r"#with luts\*?\s+(\d+)"),
                         ("with_adder", r"#with adder\s+(\d+)"),
                         ("shifter_lut", r"#shifter lut\s+(\d+)")):
            if key in stats:
                continue
            if key == "lut" and s.startswith("#lut6"):
                continue
            mm = re.match(pat, s)
            if mm:
                stats[key] = int(mm.group(1))
        if line.startswith("Report Hierarchy Area:"):
            in_h = True
            continue
        if not in_h or not line.startswith("|"):
            continue
        cells = line.split("|")
        if len(cells) < 17:
            continue
        inst_raw = cells[1]
        if not inst_raw.strip() or inst_raw.strip() == "Instance":
            continue
        try:
            n = [int(c.strip()) for c in cells[3:16]]
        except ValueError:
            continue
        hier.append({"indent": len(inst_raw) - len(inst_raw.lstrip(" ")),
                     "name": inst_raw.strip(), "module": cells[2].strip(),
                     "logic": n[0], "ripple": n[1], "seq": n[2], "eram": n[3],
                     "dsp": n[4], "dram_lut": n[5], "pll": n[9]})
    return {"model": model, "device": device, "stats": stats, "hier": hier}


def parse_qor(path):
    vals = {}
    for line in text_of(path).splitlines():
        m = re.match(r"\|\s*([^|]+?)\s*\|\s*(\d+)\s*\|", line)
        if m:
            vals[m.group(1).strip()] = int(m.group(2))
    return vals


def parse_timing(path):
    t = text_of(path)
    def f(pat):
        m = re.search(pat, t)
        if not m:
            raise CheckError("SOURCE_PARSE", f"{path}: {pat}")
        return float(m.group(1))
    mx = re.search(r"Max\s+:\s+SWNS\s+(-?[\d.]+)ns,\s+STNS\s+(-?[\d.]+)ns,\s+(\d+)\s+Viol Endpoints,\s+(\d+)\s+Total Endpoints", t)
    mn = re.search(r"Min\s+:\s+HWNS\s+(-?[\d.]+)ns,\s+HTNS\s+(-?[\d.]+)ns,\s+(\d+)\s+Viol Endpoints,\s+(\d+)\s+Total Endpoints", t)
    return {
        "wns": f(r"SWNS:\s*(-?[\d.]+)ns"), "stns": f(r"STNS:\s*(-?[\d.]+)ns"),
        "hold": f(r"HWNS:\s*(-?[\d.]+)ns"), "hold_tns": f(r"HTNS:\s*(-?[\d.]+)ns"),
        "period": f(r"Period Check WNS:\s*(-?[\d.]+)ns"),
        "viol_ep": int(mx.group(3)), "total_ep": int(mx.group(4)),
        "hold_viol_ep": int(mn.group(3)), "hold_total_ep": int(mn.group(4)),
        "has_187p5": ("187.500" in t and "clk_a1" in t),
    }


def find_h(hier, name, module):
    for r in hier:
        if r["name"] == name and r["module"] == module:
            return r
    raise CheckError("SOURCE_PARSE", f"hierarchy row {name}/{module} missing")


def ih(row, key, code="RESOURCE_VALUE_MISMATCH"):
    try:
        return int(row[key])
    except (KeyError, ValueError):
        raise CheckError(code, f"{row.get('source_id')}/{row.get('instance')} bad {key}={row.get(key)!r}")


def close(a, b, tol=1e-9):
    return abs(float(a) - float(b)) <= tol


def check(name, fn):
    try:
        detail = fn()
        RESULTS.append({"check": name, "status": "PASS", "detail": detail or ""})
        print(f"PASS {name} {detail or ''}".rstrip())
    except CheckError as e:
        RESULTS.append({"check": name, "status": "FAIL", "code": e.code, "detail": e.detail})
        print(f"FAIL {name} {e.code} {e.detail}")


# ---------------- checks ----------------

def verify_inputs():
    iv = json.loads(text_of(R0 / "input-verified.json"))
    if iv.get("mismatch_count") != 0:
        raise CheckError("INPUT_VERIFIED_MISMATCH", iv.get("mismatch_count"))
    by_id = {x["id"]: x for x in iv["inputs"]}
    if by_id["b6_core"]["sha256"] != EXPECT_CORE or by_id["b6_core"]["bytes"] != 80196:
        raise CheckError("INPUT_VERIFIED_MISMATCH", "b6 core")
    if by_id["b6_manifest"]["sha256"] != EXPECT_MANIFEST:
        raise CheckError("INPUT_VERIFIED_MISMATCH", "b6 manifest")
    drift = []
    for rec in iv["inputs"]:
        p = Path(rec["path"])
        if not p.exists() or p.stat().st_size != rec["bytes"] or sha256(p) != rec["sha256"]:
            drift.append(rec["id"])
    if drift:
        raise CheckError("INPUT_DRIFT", drift)
    return f"{len(iv['inputs'])} inputs re-hashed, 0 drift"


def parse_sources():
    src = {}
    for sid, base in B.items():
        src[sid] = {
            "area": parse_area(base / "r0/td/routed_area.rpt"),
            "qor": parse_qor(base / "r0/td/routed_qor.rpt"),
            "tim": parse_timing(base / "r0/td/routed_timing.rpt"),
            "syn": parse_area(base / "r0/td/syn_gate_area.rpt"),
        }
    return src


def load_csv(path):
    with open(path, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def check_resource_table(src):
    rows = load_csv(R0 / "resource-table.csv")
    if not rows:
        raise CheckError("RESOURCE_ROW_COUNT", "empty")
    required = ["source_id", "scope", "instance", "module", "top", "stage", "ERAM_logic",
                "DRAM_HARDCON", "DRAM_LUT", "ERAM_total", "LUT6", "REG", "SLICE",
                "DSP", "PLL", "WNS_ns", "HOLD_ns", "viol_ep", "total_ep",
                "clock_mhz", "logic_lut", "ripple", "notes"]
    missing = [c for c in required if c not in rows[0]]
    if missing:
        raise CheckError("RESOURCE_COLUMN_MISSING", missing)

    for sid in ("b6", "b10", "b11"):
        a = src[sid]["area"]
        q = src[sid]["qor"]
        t = src[sid]["tim"]
        sa = src[sid]["syn"]
        rt = [r for r in rows if r["source_id"] == sid and r["scope"] == "top" and r["stage"] == "routed"]
        st = [r for r in rows if r["source_id"] == sid and r["scope"] == "top" and r["stage"] == "synth"]
        if len(rt) != 1 or len(st) != 1:
            raise CheckError("RESOURCE_ROW_COUNT", f"{sid} routed={len(rt)} synth={len(st)}")
        r, s = rt[0], st[0]
        exp = {
            "top": a["model"], "ERAM_logic": a["stats"]["eram"],
            "DRAM_HARDCON": q["#DRAMHARDCON"], "DRAM_LUT": a["stats"]["dram_lut"],
            "ERAM_total": a["stats"]["eram"] + q["#DRAMHARDCON"],
            "LUT6": a["stats"]["lut6"], "REG": a["stats"]["reg"], "SLICE": a["stats"]["slice"],
            "DSP": a["stats"]["dsp"], "PLL": a["stats"]["pll"],
            "WNS_ns": t["wns"], "HOLD_ns": t["hold"],
            "viol_ep": t["viol_ep"], "total_ep": t["total_ep"],
        }
        for k, v in exp.items():
            if k in ("top",):
                if r[k] != v:
                    raise CheckError("RESOURCE_VALUE_MISMATCH", f"{sid} {k} {r[k]}!={v}")
            elif k in ("WNS_ns", "HOLD_ns"):
                if not close(r[k], v):
                    raise CheckError("RESOURCE_VALUE_MISMATCH", f"{sid} {k} {r[k]}!={v}")
            else:
                if ih(r, k) != int(v):
                    raise CheckError("RESOURCE_VALUE_MISMATCH", f"{sid} {k} {r[k]}!={v}")
        if not close(r["clock_mhz"], 187.5) or not t["has_187p5"]:
            raise CheckError("RESOURCE_VALUE_MISMATCH", f"{sid} clock")
        # synth row must be a pure checkpoint, no invented DRAMHARDCON / timing
        if s["DRAM_HARDCON"] != "" or s["WNS_ns"] != "" or s["HOLD_ns"] != "":
            raise CheckError("STAGE_MIX_SYNTH_IN_FIT", f"{sid} synth row carries routed-only fields")
        exp_s = {"ERAM_logic": sa["stats"]["eram"], "ERAM_total": sa["stats"]["eram"],
                 "LUT6": sa["stats"]["lut6"], "REG": sa["stats"]["reg"],
                 "SLICE": sa["stats"]["slice"], "DSP": sa["stats"]["dsp"],
                 "PLL": sa["stats"]["pll"]}
        for k, v in exp_s.items():
            if ih(s, k) != int(v):
                raise CheckError("RESOURCE_VALUE_MISMATCH", f"{sid} synth {k}")
        if ih(s, "ERAM_logic") != 72 or ih(r, "ERAM_logic") != 102:
            raise CheckError("STAGE_MIX_SYNTH_IN_FIT", f"{sid} synth/routed ERAM not 72/102")
        if ih(r, "ERAM_total") == ih(s, "ERAM_total"):
            raise CheckError("STAGE_MIX_SYNTH_IN_FIT", f"{sid} routed==synth total")
    # hierarchy rows: compare to report columns (logic/ripple/seq/eram/dram/pll/dsp)
    hrows = [r for r in rows if r["scope"] == "hierarchy"]
    if len(hrows) < 27:
        raise CheckError("RESOURCE_ROW_COUNT", f"hierarchy rows {len(hrows)}")
    for r in hrows:
        sid = r["source_id"]
        h = src[sid]["area"]["hier"]
        row = None
        for cand in h:
            if cand["name"] == r["instance"] and cand["module"] == r["module"]:
                row = cand
                break
        if row is None:
            raise CheckError("RESOURCE_VALUE_MISMATCH", f"{sid} unknown hierarchy {r['instance']}")
        pairs = [("logic_lut", row["logic"]), ("ripple", row["ripple"]),
                 ("REG", row["seq"]), ("ERAM_logic", row["eram"]),
                 ("DRAM_LUT", row["dram_lut"]), ("DSP", row["dsp"]), ("PLL", row["pll"])]
        for k, v in pairs:
            if ih(r, k) != int(v):
                raise CheckError("RESOURCE_VALUE_MISMATCH", f"{sid}/{r['instance']} {k}")
    # mandated attribution sanity
    for sid in ("b6", "b10", "b11"):
        core = find_h(src[sid]["area"]["hier"], "u_core", "a1_deflate_core")
        bridge = find_h(src[sid]["area"]["hier"], "u_bridge", "p2_ddr_bridge")
        mcu = find_h(src[sid]["area"]["hier"], "u_mcu_core", "usr_mcu_core")
        if (core["eram"], bridge["eram"], mcu["eram"]) != (23, 15, 28):
            raise CheckError("RESOURCE_VALUE_MISMATCH", f"{sid} u_core/u_bridge/u_mcu ERAM")
    return f"{len(rows)} rows; 3 routed + 3 synth tops; hierarchy attribution verified"


def check_closure(src):
    details = []
    for sid in ("b6", "b10", "b11"):
        a = src[sid]["area"]
        top = find_h(a["hier"], "top", a["model"])
        d1 = [r for r in a["hier"] if r["indent"] == 2]
        sums = {k: sum(x[k] for x in d1) for k in ("eram", "dram_lut", "pll", "dsp", "logic", "ripple", "seq")}
        for k in ("eram", "dram_lut", "pll", "dsp"):
            if sums[k] != top[k]:
                raise CheckError("HIERARCHY_CLOSURE_FAIL", f"{sid} {k} {sums[k]}!={top[k]}")
        for k in ("logic", "ripple", "seq"):
            resid = top[k] - sums[k]
            if resid < 0 or resid > math.ceil(0.02 * top[k]):
                raise CheckError("HIERARCHY_CLOSURE_FAIL", f"{sid} {k} residual {resid}")
        details.append(f"{sid}:ERAM {sums['eram']}/{top['eram']}")
    return "; ".join(details)


def check_lut6_identity(src):
    details = []
    for sid in ("b6", "b10", "b11"):
        st = src[sid]["area"]["stats"]
        ident = (st["with_luts"] + st["with_adder"] + st["dram_lut"] + st["shifter_lut"])
        if ident != st["lut6"]:
            raise CheckError("LUT6_IDENTITY_FAIL",
                             f"{sid} {st['with_luts']}+{st['with_adder']}+{st['dram_lut']}+"
                             f"{st['shifter_lut']}={ident} != #{st['lut6']}")
        details.append(f"{sid}:{ident}")
    return "TD identity #lut6 = with-luts + with-adder + dram lut + shifter lut holds for " + ", ".join(details)


def check_budget(src):
    rows = load_csv(R0 / "dual-core-budget.csv")
    cols = [r["column"] for r in rows]
    if cols.count("marginal") != 1 or cols.count("conservative") != 1:
        raise CheckError("BUDGET_TWO_COLUMN", cols)
    a = src["b10"]["area"]
    q = src["b10"]["qor"]
    h = a["hier"]
    base = {"eram": a["stats"]["eram"], "lut6": a["stats"]["lut6"],
            "reg": a["stats"]["reg"], "slice": a["stats"]["slice"]}
    top = find_h(h, "top", a["model"])
    core = find_h(h, "u_core", "a1_deflate_core")
    bridge = find_h(h, "u_bridge", "p2_ddr_bridge")
    frame = find_h(h, "u_a1", "a1_frame_top")
    fab = [find_h(h, "u_cam_fifo", "capture_async_fifo"), find_h(h, "u_arb", "a1_ddr_arb2"),
           find_h(h, "u_cmp_store", "a1_ddr_slot_store"), find_h(h, "u_crop", "a1_raw_crop"),
           find_h(h, "u_export", "a1_uart_export"), find_h(h, "u_raw_store", "a1_ddr_slot_store")]
    d_eram = core["eram"] + bridge["eram"] + (frame["eram"] - core["eram"]) + sum(x["eram"] for x in fab)
    d_logic = core["logic"] + bridge["logic"] + (frame["logic"] - core["logic"]) + sum(x["logic"] for x in fab)
    d_ripple = core["ripple"] + bridge["ripple"] + (frame["ripple"] - core["ripple"]) + sum(x["ripple"] for x in fab)
    d_seq = core["seq"] + bridge["seq"] + (frame["seq"] - core["seq"]) + sum(x["seq"] for x in fab)
    d_dram = core["dram_lut"] + bridge["dram_lut"] + (frame["dram_lut"] - core["dram_lut"]) + sum(x["dram_lut"] for x in fab)
    d_lut6 = d_logic + d_ripple + d_dram
    exp_m = {"ERAM_logic": base["eram"] + d_eram,
             "LUT6_total": base["lut6"] + d_lut6,
             "LUT6_logic_only_lower": base["lut6"] + d_logic,
             "REG_total": base["reg"] + d_seq}
    exp_m["SLICE_total"] = round(base["slice"] * (1 + (d_logic + d_ripple + d_seq) /
                                                  (top["logic"] + top["ripple"] + top["seq"])))
    exp_c = {"ERAM_logic": 2 * base["eram"], "LUT6_total": 2 * base["lut6"],
             "LUT6_logic_only_lower": 2 * base["lut6"],
             "REG_total": 2 * base["reg"], "SLICE_total": 2 * base["slice"]}
    for r in rows:
        if r["base_source"] != "b10_r1_routed":
            raise CheckError("BUDGET_ARITHMETIC", f"{r['column']} base")
        if r["timing_status"] != "unproven":
            raise CheckError("BUDGET_ARITHMETIC", f"{r['column']} claims dual-core timing")
        logic = ih(r, "ERAM_logic")
        ddr = ih(r, "ddr_controllers")
        per = ih(r, "DRAM_HARDCON_per_ddr")
        counted = ih(r, "DRAM_HARDCON_counted")
        total = ih(r, "ERAM_total")
        if per != q["#DRAMHARDCON"] or per != 85:
            raise CheckError("BUDGET_ARITHMETIC", f"{r['column']} DRAMHARDCON per ddr")
        if counted != per * ddr:
            raise CheckError("BUDGET_ARITHMETIC", f"{r['column']} ddr count")
        if total == logic and ddr >= 1:
            raise CheckError("MISSING_DRAMHARDCON", f"{r['column']} total==logic")
        if total != logic + counted:
            raise CheckError("MISSING_DRAMHARDCON", f"{r['column']} {total}!={logic}+{counted}")
        if ih(r, "ERAM_headroom") != DEV["eram"] - total:
            raise CheckError("BUDGET_ARITHMETIC", f"{r['column']} eram headroom")
        if not close(r["headroom_pct"], round(100.0 * (DEV["eram"] - total) / DEV["eram"], 2)):
            raise CheckError("BUDGET_ARITHMETIC", f"{r['column']} headroom pct")
        if ih(r, "ERAM_logic_quota_210") != QUOTA or ih(r, "logic_headroom_210") != QUOTA - logic:
            raise CheckError("BUDGET_ARITHMETIC", f"{r['column']} 210 quota")
        want300 = "pass" if total <= TARGET else ("conditional" if total <= DEV["eram"] else "fail")
        want210 = "pass" if logic <= QUOTA else ("conditional" if logic <= DEV["eram"] else "fail")
        if r["fit_300"] != want300 or r["fit_210_logic"] != want210:
            raise CheckError("BUDGET_ARITHMETIC", f"{r['column']} fit flags")
        if r["LUT_domain"] != "TD_LUT6":
            raise CheckError("LUT_DOMAIN_MIXED", f"{r['column']} domain {r['LUT_domain']}")
        lut6 = ih(r, "LUT6_total")
        lower = ih(r, "LUT6_logic_only_lower")
        if lower > lut6:
            raise CheckError("LUT6_IDENTITY_FAIL", f"{r['column']} lower {lower} > total {lut6}")
        if r["column"].startswith("marginal"):
            if lower != base["lut6"] + d_logic or lut6 - lower != d_ripple + d_dram:
                raise CheckError(
                    "LUT6_IDENTITY_FAIL",
                    f"{r['column']} lower={lower} total={lut6}; expected lower={base['lut6'] + d_logic} "
                    f"and total-lower={d_ripple + d_dram} (ripple+DRAM_LUT)")
        elif lower != lut6:
            raise CheckError("LUT6_IDENTITY_FAIL", f"{r['column']} conservative lower != total")
        if ih(r, "LUT6_device_total") != DEV["lut6"] or ih(r, "LUT6_headroom") != DEV["lut6"] - lut6:
            raise CheckError("LUT_DOMAIN_MIXED", f"{r['column']} LUT6 denominator")
        if ih(r, "LUT4_device_total") != DEV["lut4"] or ih(r, "LUT4_equiv_upper") != 2 * lut6:
            raise CheckError("LUT_DOMAIN_MIXED", f"{r['column']} LUT4 bound")
        if ih(r, "LUT4_headroom") != DEV["lut4"] - 2 * lut6:
            raise CheckError("LUT_DOMAIN_MIXED", f"{r['column']} LUT4 headroom")
        if "2 LUT4 per LUT6" not in r["LUT4_basis"]:
            raise CheckError("LUT_DOMAIN_MIXED", f"{r['column']} LUT4 basis")
        reg = ih(r, "REG_total")
        if ih(r, "REG_device_total") != DEV["reg"] or ih(r, "REG_headroom") != DEV["reg"] - reg:
            raise CheckError("BUDGET_ARITHMETIC", f"{r['column']} REG")
        sl = ih(r, "SLICE_total")
        if ih(r, "SLICE_device_total") != DEV["slice"] or ih(r, "SLICE_headroom") != DEV["slice"] - sl:
            raise CheckError("BUDGET_ARITHMETIC", f"{r['column']} SLICE")
        if ih(r, "DSP_total") > DEV["dsp"] or ih(r, "PLL_total") > DEV["pll"]:
            raise CheckError("DEVICE_OVERFLOW", f"{r['column']} DSP/PLL")
        if ih(r, "DSP_total") != a["stats"]["dsp"]:
            raise CheckError("BUDGET_ARITHMETIC", f"{r['column']} DSP != measured")
    m = next(r for r in rows if r["column"] == "marginal")
    c = next(r for r in rows if r["column"] == "conservative")
    for k, v in exp_m.items():
        if ih(m, k) != int(v):
            raise CheckError("BUDGET_ARITHMETIC", f"marginal {k} {m[k]}!={v}")
    for k, v in exp_c.items():
        if ih(c, k) != int(v):
            raise CheckError("BUDGET_ARITHMETIC", f"conservative {k} {c[k]}!={v}")
    m2 = next(r for r in rows if r["column"] == "marginal_2ddr")
    c2 = next(r for r in rows if r["column"] == "conservative_2ddr")
    for key in ("LUT6_total", "LUT6_logic_only_lower", "REG_total", "SLICE_total"):
        if ih(m2, key) != ih(m, key) or ih(c2, key) != ih(c, key):
            raise CheckError("BUDGET_ARITHMETIC", f"2ddr variant changes {key}")
    if not (ih(m, "ERAM_logic") < ih(c, "ERAM_logic")):
        raise CheckError("BUDGET_TWO_COLUMN", "marginal not below conservative")
    if ih(m, "ERAM_logic") == 2 * base["eram"]:
        raise CheckError("BUDGET_TWO_COLUMN", "marginal is just top102x2")
    if "measured" not in m["labels"] or "assumed" not in m["labels"]:
        raise CheckError("BUDGET_ARITHMETIC", "marginal label discipline")
    if "derived" not in c["labels"]:
        raise CheckError("BUDGET_ARITHMETIC", "conservative label discipline")
    # two-DDR variant must exceed the device
    v = next(r for r in rows if r["column"] == "conservative_2ddr")
    if ih(v, "ERAM_total") != 2 * base["eram"] + 2 * q["#DRAMHARDCON"] or v["fit_300"] != "fail":
        raise CheckError("BUDGET_ARITHMETIC", "2-ddr variant")
    return (f"marginal {m['ERAM_logic']}+{m['DRAM_HARDCON_counted']}={m['ERAM_total']} "
            f"({m['fit_300']}) LUT6 {m['LUT6_total']} (lower {m['LUT6_logic_only_lower']}), "
            f"conservative {c['ERAM_logic']}+{c['DRAM_HARDCON_counted']}="
            f"{c['ERAM_total']} ({c['fit_300']}) LUT6 {c['LUT6_total']}, "
            f"2ddr variant {v['ERAM_total']} (fail)")


def validate_fixture(fx):
    rows = fx["rows"]
    kind = fx["kind"]
    if kind == "resource_table_rows":
        for r in rows:
            if r.get("used_in_fit") and r.get("stage") != "routed":
                raise CheckError("STAGE_MIX_SYNTH_IN_FIT", r.get("stage"))
        return
    if kind == "budget_rows":
        cols = [r.get("column") for r in rows]
        if cols.count("marginal") != 1 or cols.count("conservative") != 1:
            raise CheckError("MISSING_TWO_COLUMN_BUDGET", cols)
        for r in rows:
            logic = r.get("ERAM_logic", 0)
            per = r.get("DRAM_HARDCON_per_ddr", 0)
            ddr = r.get("ddr_controllers", 0)
            total = r.get("ERAM_total", 0)
            if total == logic and ddr >= 1 and per > 0:
                raise CheckError("MISSING_DRAMHARDCON", r.get("column"))
        return
    raise CheckError("FIXTURE_SCHEMA", kind)


def check_negative_controls():
    files = sorted((R0 / "tests" / "negative").glob("*.json"))
    if len(files) != 3:
        raise CheckError("NEGCTL_COUNT", len(files))
    detail = []
    for f in files:
        fx = json.loads(text_of(f))
        want = fx["expected_reject"]
        try:
            validate_fixture(fx)
        except CheckError as e:
            if e.code != want:
                raise CheckError("NEGCTL_WRONG_REASON", f"{f.name}: {e.code} != {want}")
            detail.append(f"{fx['fixture_id']}->{e.code}")
            continue
        raise CheckError("NEGCTL_NOT_REJECTED", f.name)
    return ", ".join(detail)


def main():
    src = parse_sources()
    check("inputs_frozen_0_mismatch_no_drift", verify_inputs)
    check("resource_table_matches_reports", lambda: check_resource_table(src))
    check("lut6_identity_td", lambda: check_lut6_identity(src))
    check("hierarchy_sums_close_to_top", lambda: check_closure(src))
    check("dual_core_budget_arithmetic", lambda: check_budget(src))
    check("negative_controls_rejected", check_negative_controls)
    failed = [r for r in RESULTS if r["status"] != "PASS"]
    summary = {"status": "PASS" if not failed else "FAIL", "checks": RESULTS}
    print(json.dumps(summary, ensure_ascii=False))
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
