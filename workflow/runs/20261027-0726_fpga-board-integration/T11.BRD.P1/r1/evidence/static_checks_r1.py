#!/usr/bin/env python3
"""T11.BRD.P1 r1 G0/G5 local static checks (no TD, no hardware).

Prints one PASS/FAIL line per check and exits non-zero on any failure.
Also verifies the r0 run's frozen files are byte-identical (no rewrite).
"""
import hashlib
import json
import re
import sys
from pathlib import Path

R1 = Path(__file__).resolve().parent.parent
REPO_ROOT = R1.parents[4]
PKG = REPO_ROOT / "handoff" / "brd-p1-r1-20261027"
OLD = Path(r"D:/fpga/ph1p100")
REF = OLD / "fpga/csi2/pcie_integration/rtl/ep_side/ph1p_pcie_ep_top.v"
TOP = R1 / "rtl/brd_integrated_top.v"
DP = R1 / "rtl/brd_board_datapath.v"
SDC = R1 / "constraints/brd_board.sdc"
ADC = R1 / "constraints/ph1p_pcie_case_ep.adc"

fails = []
def check(name, cond, detail=""):
    print(("PASS " if cond else "FAIL ") + name + ((" " + detail) if detail else ""))
    if not cond:
        fails.append(name)

def ports(path):
    txt = path.read_text(errors="replace")
    m = re.search(r"module\s+\w+\s*\((.*?)\);", txt, re.S)
    if not m:
        return {}
    out = {}
    for line in m.group(1).splitlines():
        line = line.split("//", 1)[0]
        pm = re.match(r"\s*(input|output|inout)\s+wire\s*(\[[^\]]+\])?\s*(\w+)", line)
        if pm:
            out[pm.group(3)] = (pm.group(1), pm.group(2) or "", )
    return out

pt, pr = ports(TOP), ports(REF)
check("top_port_count_43", len(pt) == 43, str(len(pt)))
check("reference_port_count_43", len(pr) == 43, str(len(pr)))
check("top_port_set_matches_reference", set(pt) == set(pr), str(sorted(set(pt) ^ set(pr))))
check("top_port_dirs_widths_match", all(pt[k] == pr[k] for k in pt if k in pr))

# reset pin: only one R14 assignment and one pcie_power_on_rst port
adc = ADC.read_text(errors="replace")
check("adc_r14_once", adc.count("R14") == 1, f"count={adc.count('R14')}")
check("adc_r14_is_power_on_rst", any(("R14" in l and "pcie_power_on_rst" in l) for l in adc.splitlines()))
check("top_power_on_rst_one_port", len(re.findall(r"pcie_power_on_rst", TOP.read_text(errors='replace').split(");", 1)[0])) == 1)

sdc_all = SDC.read_text(errors="replace")
sdc = "\n".join(l for l in sdc_all.splitlines() if not l.strip().startswith("#"))
groups = re.findall(r"-group\s+\[get_clocks\s+\{([^}]+)\}\]", sdc)
gset = [set(g.split()) for g in groups]
check("sdc_clk_core_own_group", any(g == {"clk_core"} for g in gset), str(groups))
check("sdc_clk_core_not_with_tl", not any("clk_core" in g and "tl_clk_user" in g for g in gset))
check("sdc_all_six_groups", len(groups) == 6, str(len(groups)))
fp = re.findall(r"set_false_path\s+-from\s+\[get_ports\s+\{(\w+)\}\]", sdc)
check("sdc_only_two_false_paths", sorted(fp) == ["pcie_power_on_rst", "user_int_trigger"], str(fp))
check("sdc_no_multicycle", "set_multicycle_path" not in sdc)
check("sdc_no_internal_false_path", len(re.findall(r"set_false_path", sdc)) == 2)

dp = DP.read_text(errors="replace")
# only the u_p4 instance must use the synchronised copies
check("u_p4_mps_synced", ".mps_code(c_mps_code)" in dp)
check("u_p4_link_synced", ".link_up(c_link_up)" in dp)
check("u_p4_no_raw_mps", dp.count(".mps_code(mps_code)") == 1)
check("u_p4_no_raw_link", dp.count(".link_up(link_up)") == 1 and ".link_up(p_link_up)" not in dp)
check("c8_2ff_regs", "mps_s1" in dp and "mps_s2" in dp)
check("c9_2ff_regs", "lnk_s1" in dp and "lnk_s2" in dp)
check("f2_aw_offset", "p4_ddr_awaddr + SLOT_BASE_WORD" in dp)
check("f2_ar_offset", "p4_ddr_araddr + SLOT_BASE_WORD" in dp)
check("f1_export_seq", "brd_export_seq u_export_seq" in dp)
check("pusher_arm_from_seq", ".arm_pulse(pu_arm)" in dp)
check("pusher_seq_from_board", ".ddr_seq(pu_seq)" in dp)
check("desc_release_by_cam", "if (rel_camera_id) b_desc_active" in dp)

# no bitstream / CWC anywhere in r1 or the package
bits = list(R1.rglob("*.bit")) + list(R1.rglob("*.cwc")) + list(PKG.rglob("*.bit")) + list(PKG.rglob("*.cwc"))
check("no_bit_or_cwc", len(bits) == 0, str([str(b) for b in bits]))

# r0 frozen files unchanged (manifest paths are relative to the old workspace)
r0 = json.loads((OLD / "workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/manifest-brd-p1-r0.json").read_text(encoding="utf-8"))
bad = []
for row in r0["files"]:
    p = OLD / row["path"]
    if not p.exists():
        bad.append("missing " + row["path"])
    elif hashlib.sha256(p.read_bytes()).hexdigest().upper() != row["sha256"].upper():
        bad.append("drift " + row["path"])
check("r0_manifest_files_unchanged", not bad, str(bad[:4]))

print("STATIC_CHECKS=" + ("PASS" if not fails else "FAIL " + ",".join(fails)))
sys.exit(0 if not fails else 1)
