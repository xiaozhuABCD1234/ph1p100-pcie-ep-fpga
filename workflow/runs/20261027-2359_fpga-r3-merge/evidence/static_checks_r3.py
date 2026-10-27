#!/usr/bin/env python3
"""T11.BRD.P1 r3 -- G0 (static) + G5 (binding) local checks. No TD, no hardware.

Every check is a file/string/hash fact.  This script never claims STA, CDC
engine results, synthesis, route, bitgen or board behaviour.

Sections
  A. G0 static: 43 top ports vs the reference top, R14/power-on reset, SDC six
     one-clock groups with clk_core alone, only the two allowed false paths,
     C8/C9 2FF, F2 slot-base offsets, x32 unit in the datapath and x8 in the
     bridge, ACK slice, seq start 1, release polarity, bswap256 kept.
  B. r3-vs-r2 delta: exactly the three intended RTL files change; the pusher
     delta is comment-only; the datapath delta is the two reset lines; the
     mailbox delta is the two ACK slice lines; a1_core_fix01/constraints/P4/
     top/other board files are byte-identical.
  C. freeze integrity: r0/r1/r2 manifests still byte-identical; no r3 path in
     any old manifest; no r3 changed-file SHA in any old manifest.
  D. G5: r3 handoff package guards (78 sources, repo-relative SHA json, no
     pre-generated .al), no bit/CWC, no old r3-era SHAs, b20 alias facts.
"""
import difflib
import hashlib
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
R3 = HERE.parent
REPO = R3.parents[2]
R2 = REPO / "workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r2"
R1 = REPO / "workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r1"
OLD = Path(r"D:/fpga/ph1p100")
PKG = REPO / "handoff" / "brd-p1-r3-20261027"
REF = OLD / "fpga/csi2/pcie_integration/rtl/ep_side/ph1p_pcie_ep_top.v"
TOP = R3 / "rtl/brd_integrated_top.v"
DP = R3 / "rtl/brd_board_datapath.v"
MB = R3 / "rtl/brd_cdc_mailboxes.v"
BR = R3 / "rtl/p2_ddr_bridge.v"
PU = R3 / "rtl/ref/ep_side/ddr/ddr_frame_pusher.v"
SDC = R3 / "constraints/brd_board.sdc"
ADC = R3 / "constraints/ph1p_pcie_case_ep.adc"
MAN_R0 = OLD / "workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/manifest-brd-p1-r0.json"
MAN_R1 = R1 / "manifest-brd-p1-r1.json"
MAN_R2 = R2 / "manifest-brd-p1-r2.json"
R1_MAN_SHA = "304A2FF08DA88B6F129577D710A5B077B9FCF0A71F205E72BFB03412616CCC05"
R2_MAN_SHA = "BD2B983F4734DA06211FF973B4165E043FD94A09D023A896E4846821AC037B4B"
REJECTED_SHA = {
    "863932B3D42FBB4F97AD2A6A9397E477A012B61B534CD4DBEAD1997AF73A44BC",
    "B8096430C060BE77BE408B1D4103DE87F543193F94E78DE418189EA32C412B64",
}
B20 = REPO / "handoff/fpga-sim-only-20261027/inputs/p4/workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b20-a-timing/r0/changed-src"

fails = []
checks = 0


def check(name, cond, detail=""):
    global checks
    checks += 1
    print(("PASS " if cond else "FAIL ") + name + (("  [" + detail + "]") if detail else ""))
    if not cond:
        fails.append(name)


def sha(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest().upper()


def ports(path: Path) -> dict:
    txt = path.read_text(errors="replace")
    m = re.search(r"module\s+\w+\s*\((.*?)\);", txt, re.S)
    if not m:
        return {}
    out = {}
    for line in m.group(1).splitlines():
        line = line.split("//", 1)[0]
        pm = re.match(r"\s*(input|output|inout)\s+wire\s*(\[[^\]]+\])?\s*(\w+)", line)
        if pm:
            out[pm.group(3)] = (pm.group(1), pm.group(2) or "")
    return out


def strip_comments(txt: str) -> str:
    txt = re.sub(r"/\*.*?\*/", "", txt, flags=re.S)
    lines = []
    for line in txt.splitlines():
        line = line.split("//", 1)[0].strip()
        if line:
            lines.append(line)
    return "\n".join(lines)


def diff_lines(a: Path, b: Path):
    da = strip_comments(a.read_text(errors="replace")).splitlines()
    db = strip_comments(b.read_text(errors="replace")).splitlines()
    return [l for l in difflib.unified_diff(da, db, lineterm="") if l[:1] in "+-" and not l.startswith(("+++", "---"))]


print("== A. G0 static ==")
pt, pr = ports(TOP), ports(REF)
check("top_port_count_43", len(pt) == 43, str(len(pt)))
check("reference_port_count_43", len(pr) == 43, str(len(pr)))
check("top_port_set_matches_reference", set(pt) == set(pr), str(sorted(set(pt) ^ set(pr))))
check("top_port_dirs_widths_match", all(pt[k] == pr[k] for k in pt if k in pr))

adc = ADC.read_text(errors="replace")
check("adc_r14_once", adc.count("R14") == 1, f"count={adc.count('R14')}")
check("adc_r14_is_power_on_rst", any(("R14" in l and "pcie_power_on_rst" in l) for l in adc.splitlines()))
check("top_power_on_rst_one_port",
      len(re.findall(r"pcie_power_on_rst", TOP.read_text(errors='replace').split(");", 1)[0])) == 1)

sdc_all = SDC.read_text(errors="replace")
sdc = "\n".join(l for l in sdc_all.splitlines() if not l.strip().startswith("#"))
groups = re.findall(r"-group\s+\[get_clocks\s+\{([^}]+)\}\]", sdc)
gset = [set(g.split()) for g in groups]
check("sdc_clk_core_own_group", any(g == {"clk_core"} for g in gset), str(groups))
check("sdc_clk_core_not_with_tl", not any("clk_core" in g and "tl_clk_user" in g for g in gset))
check("sdc_all_six_groups", len(groups) == 6, str(len(groups)))
check("sdc_no_group_mixes_cam_a_and_b",
      not any(any(c.startswith("cam_a_") for c in g) and any(c.startswith("cam_b_") for c in g)
              for g in gset), str(groups))


def clock_source(c: str) -> str:
    c = c.lstrip("*")
    if c.startswith("cam_a_"):
        return "cam_a"
    if c.startswith("cam_b_"):
        return "cam_b"
    if c.startswith("clk_core"):
        return "core"
    if c.startswith("tl_clk"):
        return "tl"
    if c.startswith("sys_clk"):
        return "sys"
    if c.startswith("usr_clk"):
        return "usr"
    return c


check("sdc_single_source_per_group",
      all(len({clock_source(c) for c in g}) == 1 for g in gset), str(groups))
fp = re.findall(r"set_false_path\s+-from\s+\[get_ports\s+\{(\w+)\}\]", sdc)
check("sdc_only_two_false_paths", sorted(fp) == ["pcie_power_on_rst", "user_int_trigger"], str(fp))
check("sdc_no_multicycle", "set_multicycle_path" not in sdc)
check("sdc_no_internal_false_path", len(re.findall(r"set_false_path", sdc)) == 2)
check("sdc_n1_second_derive_clocks_documented", sdc_all.count("derive_clocks") >= 1,
      f"derive_clocks lines={sdc_all.count('derive_clocks')} (N1 unchanged, teammate STA item)")

dp = DP.read_text(errors="replace")
check("u_p4_mps_synced", ".mps_code(c_mps_code)" in dp)
check("u_p4_link_synced", ".link_up(c_link_up)" in dp)
check("c8_2ff_regs", "mps_s1" in dp and "mps_s2" in dp)
check("c9_2ff_regs", "lnk_s1" in dp and "lnk_s2" in dp)
check("f2_aw_offset", "p4_ddr_awaddr + SLOT_BASE_WORD" in dp)
check("f2_ar_offset", "p4_ddr_araddr + SLOT_BASE_WORD" in dp)
check("f1_export_seq", "brd_export_seq u_export_seq" in dp)
check("pusher_arm_from_seq", ".arm_pulse(pu_arm)" in dp)
check("pusher_seq_from_board", ".ddr_seq(pu_seq)" in dp)
check("desc_release_by_cam", "if (rel_camera_id) b_desc_active" in dp)
check("seq_starts_at_one", "a_seq <= 32'd1" in dp and "b_seq <= 32'd1" in dp)
check("slot_base_x32", "{m_slot_base_word[26:0], 5'b0}" in dp)
check("no_slot_base_x128", "{m_slot_base_word[24:0], 7'b0}" not in dp)
check("push_base_x32", "PUSH_BASE0 = SLOT_BASE_WORD * 32" in dp and
      "PUSH_BASE1 = (SLOT_BASE_WORD + SLOT_WORDS) * 32" in dp)
check("no_push_base_x128", "* 128" not in dp)

mb = MB.read_text(errors="replace")
check("ack_seq_high_half", "o_ack_seq     <= out_bus[63:32];" in mb)
check("ack_session_low_half", "o_ack_session <= out_bus[31:0];" in mb)
check("ack_old_slice_absent", "o_ack_seq     <= out_bus[31:0];" not in mb)

br = BR.read_text(errors="replace")
check("bridge_aw_x8", "{wf_rdata[279:256], 3'b000}" in br)
check("bridge_ar_x8", "{af_rdata[23:0], 3'b000}" in br)
check("bridge_no_x32", "wf_rdata[276:256], 5'b00000" not in br and "af_rdata[20:0], 5'b00000" not in br)

pu = PU.read_text(errors="replace")
check("pusher_bswap256_kept", "wire [255:0] data_beat = bswap256(beat_data);" in pu)
check("no_sta_claim", True, "static only: no synthesis/route/STA/CDC engine was run")

print("\n== B. r3 vs r2 delta ==")
def tree(base: Path):
    return {str(p.relative_to(base)).replace("\\", "/"): p for p in base.rglob("*") if p.is_file()}

a, b = tree(R2 / "rtl"), tree(R3 / "rtl")
changed = sorted([k for k in set(a) | set(b)
                  if k not in a or k not in b or sha(a[k]) != sha(b[k])])
expected = sorted([
    "brd_cdc_mailboxes.v",
    "brd_board_datapath.v",
    "ref/ep_side/ddr/ddr_frame_pusher.v",
])
check("rtl_changed_set_is_exactly_three", changed == expected, str(changed))
check("rtl_other_files_identical", all(k not in changed for k in a if k not in expected))

d_dp = diff_lines(R2 / "rtl/brd_board_datapath.v", DP)
rem_dp = [l for l in d_dp if l.startswith("-")]
add_dp = [l for l in d_dp if l.startswith("+")]
check("datapath_delta_is_two_reset_lines",
      len(rem_dp) == 2 and len(add_dp) == 2 and
      all(("a_seq <= 32'd0" in l) or ("b_seq <= 32'd0" in l) for l in rem_dp) and
      all(("a_seq <= 32'd1" in l) or ("b_seq <= 32'd1" in l) for l in add_dp),
      " | ".join(d_dp))
d_mb = diff_lines(R2 / "rtl/brd_cdc_mailboxes.v", MB)
rem_mb = [l for l in d_mb if l.startswith("-")]
add_mb = [l for l in d_mb if l.startswith("+")]
check("mailbox_delta_is_two_ack_slices",
      len(rem_mb) == 2 and len(add_mb) == 2 and
      any("o_ack_seq" in l and "out_bus[31:0]" in l for l in rem_mb) and
      any("o_ack_session" in l and "out_bus[63:32]" in l for l in rem_mb) and
      any("o_ack_seq" in l and "out_bus[63:32]" in l for l in add_mb) and
      any("o_ack_session" in l and "out_bus[31:0]" in l for l in add_mb),
      " | ".join(d_mb))
d_pu = diff_lines(R2 / PU, PU)
check("pusher_delta_comment_only", len(d_pu) == 0, " | ".join(d_pu[:4]))

for sub in ("constraints",):
    a, b = tree(R2 / sub), tree(R3 / sub)
    bad = [k for k in set(a) | set(b) if k not in a or k not in b or sha(a[k]) != sha(b[k])]
    check(f"{sub}_delta_zero", not bad, str(bad))

alias_bad = []
for n in ("a1_frame_top.v", "a1_deflate_core.v", "a1_ddr_slot_store.v", "a1_ddr_arb2.v"):
    if sha(R3 / "rtl" / "a1_core_fix01" / n) != sha(B20 / n):
        alias_bad.append(n)
check("a1_core_fix01_alias_of_b20", not alias_bad, str(alias_bad))

print("\n== C. freeze integrity (nothing rewritten) ==")
check("r1_manifest_sha_unchanged", MAN_R1.exists() and sha(MAN_R1) == R1_MAN_SHA,
      sha(MAN_R1) if MAN_R1.exists() else "missing")
check("r2_manifest_sha_unchanged", MAN_R2.exists() and sha(MAN_R2) == R2_MAN_SHA,
      sha(MAN_R2) if MAN_R2.exists() else "missing")

m1 = json.loads(MAN_R1.read_text(encoding="utf-8"))
bad1 = []
for row in m1["files"]:
    p = REPO / row["path"]
    if not p.exists():
        bad1.append("missing " + row["path"])
    elif sha(p) != row["sha256"].upper():
        bad1.append("drift " + row["path"])
check("r1_manifest_files_unchanged", not bad1, f"{len(m1['files'])} files, bad={bad1[:3]}")

m0 = json.loads(MAN_R0.read_text(encoding="utf-8"))
bad0 = []
for row in m0["files"]:
    p = OLD / row["path"]
    if not p.exists():
        bad0.append("missing " + row["path"])
    elif sha(p) != row["sha256"].upper():
        bad0.append("drift " + row["path"])
check("r0_manifest_files_unchanged", not bad0, f"{len(m0['files'])} files, bad={bad0[:3]}")

m2 = json.loads(MAN_R2.read_text(encoding="utf-8"))
bad2 = []
for row in m2["files"]:
    p = REPO / row["path"]
    if not p.exists():
        bad2.append("missing " + row["path"])
    elif sha(p) != row["sha256"].upper():
        bad2.append("drift " + row["path"])
check("r2_manifest_files_unchanged", not bad2, f"{len(m2['files'])} files, bad={bad2[:3]}")

r3_prefixes = ("workflow/runs/20261027-2359_fpga-r3-merge/", "handoff/brd-p1-r3-20261027/")
mixed = []
for name, man in (("r0", m0), ("r1", m1), ("r2", m2)):
    for row in man["files"]:
        if row["path"].startswith(r3_prefixes):
            mixed.append(f"{name}:{row['path']}")
check("no_r3_path_in_old_manifests", not mixed, str(mixed[:3]))

old_hashes = set()
for man in (m0, m1, m2):
    old_hashes |= {row["sha256"].upper() for row in man["files"]}
changed_hashes = {sha(R3 / "rtl" / k) for k in expected}
check("no_r3_changed_sha_in_old_manifests", not (changed_hashes & old_hashes),
      str(sorted(changed_hashes & old_hashes)))

print("\n== D. G5 package + binding ==")
flj = PKG / "build" / "filelist-sha256.json"
fl = json.loads(flj.read_text(encoding="utf-8"))
check("source_count_78", fl["source_count"] == 78, str(fl["source_count"]))
check("filelist_count_78", len(fl["files"]) == 78, str(len(fl["files"])))
abs_paths = [r["path"] for r in fl["files"] if re.match(r"^[A-Za-z]:/", r["path"])]
check("n2_filelist_json_repo_relative", not abs_paths, str(abs_paths[:3]))
check("n2_filelist_json_hash_matches_tcl", fl["filelist_tcl_sha256"] == sha(PKG / "filelist.tcl"))
bad = []
for r in fl["files"]:
    p = REPO / r["path"]
    if not p.exists():
        bad.append("missing " + r["path"])
    elif sha(p) != r["sha256"].upper():
        bad.append("drift " + r["path"])
check("sources_present_and_hashed", not bad, str(bad[:3]))

check("n3_no_absolute_al_in_package", not (PKG / "build" / "brd_board.al").exists())
tmpl = (PKG / "build" / "brd_board.al.tmpl").read_text(errors="replace")
check("n3_tmpl_has_placeholder", "@REPO_ROOT@" in tmpl and not re.search(r"[A-Za-z]:/fpga", tmpl))
genal = (PKG / "build" / "gen_al.py").read_text(errors="replace")
check("n3_gen_al_present", "brd_board.al" in genal and "@REPO_ROOT@" in genal)

bits = [p for p in list(R3.rglob("*.bit")) + list(R3.rglob("*.cwc")) +
        list(PKG.rglob("*.bit")) + list(PKG.rglob("*.cwc"))]
check("no_bit_or_cwc", not bits, str([str(b) for b in bits]))

rej_hits = []
for p in list(R3.rglob("*")) + list(PKG.rglob("*")):
    if p.is_file() and p.suffix.lower() in (".v", ".tcl", ".json", ".md"):
        if sha(p) in REJECTED_SHA:
            rej_hits.append(str(p.relative_to(REPO)))
check("no_rejected_r3_sha_anywhere", not rej_hits, str(rej_hits))

rej_paths = [str(p.relative_to(REPO)) for p in PKG.rglob("*")
             if p.name in ("algo_rowwin3_p4.v", "gray8_gaussian3x3_stream_p4.v")]
check("no_rejected_r3_files_in_package", not rej_paths, str(rej_paths))

if (R3 / "manifest-r3.json").exists():
    print("\nNOTE: manifest-r3.json exists; its hash binding and metadata are checked by "
          "evidence/verify_manifest_r3.py (post-freeze).")
else:
    print("\nNOTE: manifest-r3.json not built yet (expected before freezing).")

print(f"\nCHECKS={checks} FAILS={len(fails)}")
print("STATIC_CHECKS_R3=" + ("PASS" if not fails else "FAIL " + ",".join(fails)))
sys.exit(0 if not fails else 1)
