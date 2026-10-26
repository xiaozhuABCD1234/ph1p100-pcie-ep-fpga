#!/usr/bin/env python3
"""check_merge_b18.py -- T10.b18-b17-b merge conformance (C01..C18).

Static, read-only.  Prints one line per check and exits non-zero on any
failure.  C18 needs the stub-top simulation (r0/sim/sim-results-b18-camsel.json);
before that run it reports PENDING without failing.
"""
import hashlib
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(r"D:\fpga\ph1p100")
RUN = ROOT / "workflow/runs/20261020-0209_singleA_aplus_closedloop"
PKG = RUN / "T10.b18-b17-b"
R0 = PKG / "r0"
CS = R0 / "changed-src"
TD = R0 / "td"
SIM = R0 / "sim"
B17 = RUN / "T10.b17-paxi-native"

fails = []
results = []


def chk(cid, ok, msg):
    results.append((cid, bool(ok), msg))
    print("%s %s %s" % (cid, "PASS" if ok else "FAIL", msg))
    if not ok:
        fails.append(cid)


def sha(p):
    p = pathlib.Path(p)
    return hashlib.sha256(p.read_bytes()).hexdigest() if p.exists() else "MISSING"


def cnt(text, sub):
    return text.count(sub)


top = (CS / "p2_a1_board_top.v").read_text(encoding="utf-8", errors="replace")
exp = (CS / "a1_uart_export.v").read_text(encoding="utf-8", errors="replace")
sdc = (TD / "p2_board.sdc").read_text(encoding="utf-8", errors="replace")

EXPECT = {
    "f9p_camera_display_core.v": "e17206fb2e15f7590ee55c2ccc072677356ab2cb8efa41fd95ad6d52ab080760",
    "p2_ddr_bridge.v": "790d8226ec69499c87b92b0e4a05ac0f26915f57b96bd541affdcdac8e740a61",
    "a1_uart_export.v": "b3d61597534aa0609c53634313e4d14f222839f8b9b8ed83afc140daa04c298d",
    "camera_a1_uart_top.v": "73d10388c4a802421563b5b4c66f9cc37d600e7ec49fc0fa94b3d3ea0cbd3ff2",
}
SHARED = {
    "a1_ddr_arb2.v": "b84019bda057afe82ff558e0848d6171fa12732bd8cdb7c6239cb71b3f81d6ba",
    "a1_ddr_slot_store.v": "6c619cf90e54385d667f1ec0f63cc87ee58aadd3c42143330ac4945eb47defe9",
    "a1_deflate_core.v": "a91c2ed82fbef654c4e065b64ae1cc268ca232feaa26fdd313c58d8740f81b3e",
    "a1_frame_top.v": "0064607aceb20ae3ef14133f0aaf5f8b3f489943011a66a1ddc005350dba7109",
    "a1_raw_crop.v": "33a6fee77fd1aa67a31cacf26dd5530e5e2ea474ee655cbd5f1d98d887c5d72d",
    "cam_diag_mailbox.v": "352af7c85094ea99b575e99da952af8d33871352140e4c6efddff9e6c2407278",
}

# ---- C01..C04 exact copies --------------------------------------------------
for i, name in enumerate(["f9p_camera_display_core.v", "p2_ddr_bridge.v",
                          "a1_uart_export.v", "camera_a1_uart_top.v"], start=1):
    got = sha(CS / name)
    chk("C%02d" % i, got == EXPECT[name], "%s %s" % (name, got))

# ---- C05 shared six ---------------------------------------------------------
bad = [n for n, h in SHARED.items() if sha(CS / n) != h]
chk("C05", not bad, "shared six byte-identical" if not bad else "drift=%s" % bad)

# ---- C06..C12 merged top shape ---------------------------------------------
chk("C06", cnt(top, "localparam CAM_SEL = 1'b1;") == 1,
    "CAM_SEL localparam count=%d" % cnt(top, "localparam CAM_SEL = 1'b1;"))
chk("C07", cnt(top, "g_cam_sel_b") == 1 and cnt(top, "g_cam_sel_a") == 1,
    "generate labels b=%d a=%d" % (cnt(top, "g_cam_sel_b"), cnt(top, "g_cam_sel_a")))
chk("C08", cnt(top, "{19'd0, CAM_SEL, sel_lane_sticky, 3'd0") == 1,
    "cam_sysstat bit12 packing count=%d" % cnt(top, "{19'd0, CAM_SEL, sel_lane_sticky, 3'd0"))
chk("C09", cnt(top, "20'd0, cam_lane_sticky") == 0,
    "b13 concat removed count=%d" % cnt(top, "20'd0, cam_lane_sticky"))
c10 = {
    "o_b_pixel": len(re.findall(r"\.o_b_pixel\s*\(", top)),
    "o_b_byte_clk": len(re.findall(r"\.o_b_byte_clk\s*\(", top)),
    "o_dbg_b_lane_sticky": len(re.findall(r"\.o_dbg_b_lane_sticky\s*\(", top)),
    "o_dbg_b_last_lines": len(re.findall(r"\.o_dbg_b_last_lines\s*\(\s*\)", top)),
}
chk("C10", all(v == 1 for v in c10.values()), "B port connections %s" % c10)
c11 = {".clk_cam             (sel_byte_clk)": cnt(top, ".clk_cam             (sel_byte_clk)"),
       ".i_a_pixel           (sel_pixel)": cnt(top, ".i_a_pixel           (sel_pixel)")}
chk("C11", all(v == 1 for v in c11.values()), "u_a1 selection %s" % c11)
chk("C12", cnt(top, "wire [511:0] dbg_bridge") == 1 and cnt(top, "wire [255:0] dbg_bridge") == 0,
    "512-bit dbg_bridge kept (511=%d 255=%d)" % (cnt(top, "wire [511:0] dbg_bridge"),
                                                 cnt(top, "wire [255:0] dbg_bridge")))

# ---- C13 v6 export constants ------------------------------------------------
c13 = {"STS_LEN 9'd273": cnt(exp, "STS_LEN  = 9'd273"),
       "STS_VER 8'd6": cnt(exp, "STS_VER  = 8'd6"),
       "allsnap [2143:0]": cnt(exp, "wire [2143:0] allsnap"),
       "extsnap 768": cnt(exp, "reg [767:0] extsnap")}
chk("C13", all(v == 1 for v in c13.values()), "v6 export constants %s" % c13)

# ---- C14 SDC ---------------------------------------------------------------
sdc_sha = sha(TD / "p2_board.sdc")
b17_sdc = (B17 / "r0/td/p2_board.sdc").read_text(encoding="utf-8", errors="replace")


def fp_lines(t):
    return [l.strip() for l in t.splitlines()
            if re.search(r"set_(false_path|multicycle_path)", l)]


c14a = sdc_sha == "3fe1641270eb0cd90a25a3d4724617f7f81103d83f8d364bb954cd41329cf2ed"
c14b = cnt(sdc, "-name {mipi_b_byte_clk}") == 1 and \
    cnt(sdc, "-source [get_ports {mipi_b_clk_hs_p}] -divide_by 4") == 1
c14c = cnt(sdc, "-group {mipi_b_clk_hs mipi_b_byte_clk}") == 1
c14d = fp_lines(sdc) == fp_lines(b17_sdc)
chk("C14", c14a and c14b and c14c and c14d,
    "sdc=%s genclk=%s group=%s false/multicycle_unchanged=%s (n=%d)" %
    (sdc_sha[:16], c14b, c14c, c14d, len(fp_lines(sdc))))

# ---- C15 ADC ---------------------------------------------------------------
adc = sha(TD / "board_p2.adc")
chk("C15", adc == "1cb30346fa17da6bb0e77802ca72c4b4bb4aecc1445711e19391cf4ee2271580",
    "board_p2.adc %s" % adc)

# ---- C16 build filelist guard ---------------------------------------------
build = (TD / "01_build.tcl").read_text(encoding="utf-8", errors="replace")
al = (TD / "a1_board.al").read_text(encoding="utf-8", errors="replace")
addlines = [l.strip() for l in build.splitlines() if l.strip().startswith("add_files")]
addtxt = "\n".join(addlines)
c16 = {
    "tcl_f9p": len([l for l in addlines if l.endswith("changed-src/f9p_camera_display_core.v")]),
    "tcl_top": len([l for l in addlines if l.endswith("changed-src/p2_a1_board_top.v")]),
    "al_f9p": len(re.findall(r"changed-src/f9p_camera_display_core\.v", al)),
    "al_top": len(re.findall(r"changed-src/p2_a1_board_top\.v", al)),
    "guard": cnt(build, "P2_PRJ_GUARD_PASS"),
    "stale_src": len([1 for n in ("f9p_camera_display_core.v", "p2_a1_board_top.v",
                                  "p2_ddr_bridge.v")
                      if (TD / "src" / n).exists()]),
    "stale_add": len([l for l in addlines if re.search(
        r"\./src/(f9p_camera_display_core|p2_a1_board_top|p2_ddr_bridge)\.v", l)]),
    "double_src": len([l for l in addlines if "src/src/" in l]),
}
ok16 = (c16["tcl_f9p"] == 1 and c16["tcl_top"] == 1 and c16["al_f9p"] == 1 and
        c16["al_top"] == 1 and c16["guard"] == 1 and c16["stale_src"] == 0 and
        c16["stale_add"] == 0 and c16["double_src"] == 0 and
        "T10.b18-b17-b/r0/changed-src" in addtxt)
chk("C16", ok16, "filelist guard %s" % c16)

# ---- C17 CAM_SEL=0 A-branch equivalence -----------------------------------
m = re.search(r"end else begin : g_cam_sel_a(.*?)end\n    endgenerate", top, re.S)
a_branch = m.group(1) if m else ""
pairs = re.findall(r"assign\s+(sel_\w+)\s*=\s*(\w+);", a_branch)
B13_A = {
    "sel_pixel": "a_pixel", "sel_pixel_valid": "a_pixel_valid",
    "sel_in_line": "a_in_line", "sel_in_frame": "a_in_frame",
    "sel_vsync": "a_vsync", "sel_byte_clk": "a_byte_clk",
    "sel_delay_tap": "cam_delay_tap", "sel_delay_done": "cam_delay_done",
    "sel_rst_out": "cam_rst_out", "sel_sync_wait": "cam_sync_wait",
    "sel_pkt_tgl": "cam_pkt_tgl", "sel_vs_tgl": "cam_vs_tgl",
    "sel_clk_tgl": "cam_clk_tgl", "sel_cfg_done": "cam_cfg_done",
    "sel_bus_err_lat": "cam_bus_err_lat", "sel_nack_cnt": "cam_nack_cnt",
    "sel_lane_sticky": "cam_lane_sticky",
}
diffs = sorted(set(dict(pairs).items()) ^ set(B13_A.items())) + \
    sorted(k for k, v in dict(pairs).items() if B13_A.get(k) != v and (k, v) in B13_A.items())
diffs = sorted(set(diffs))
# cam_sysstat: with CAM_SEL=0 the merged concat must equal the b13 word.
ONE_BIT = {"CAM_SEL", "cam_cfg_rst_n", "cam_pll_locked", "cam_xclr_n",
           "sel_bus_err_lat", "sel_cfg_done"}
WIDTH = {"sel_lane_sticky": 4}
c17_stat = None
ms = re.search(r"wire \[31:0\] cam_sysstat = \{(.*?)\};", top, re.S)
if ms:
    fields = [f.strip() for f in ms.group(1).split(",")]
    w = 0
    for f in fields:
        dm = re.match(r"(\d+)'d", f)
        if dm:
            w += int(dm.group(1))
        elif f in ONE_BIT:
            w += 1
        elif f in WIDTH:
            w += WIDTH[f]
    c17_stat = (w == 32 and fields[0] == "19'd0" and fields[1] == "CAM_SEL" and
                fields[2] == "sel_lane_sticky" and
                fields[-2:] == ["sel_bus_err_lat", "sel_cfg_done"])
ok17 = (len(pairs) == 17 and not diffs and c17_stat is True)
chk("C17", ok17, "A-branch pairs=%d diffs=%s cam_sysstat_b13_equal_camsel0=%s" %
    (len(pairs), diffs if diffs else 0, c17_stat))

# ---- C18 TB-visible cam_sysstat bit 12 ------------------------------------
j = SIM / "sim-results-b18-camsel.json"
if j.exists():
    r = json.loads(j.read_text())
    main = r.get("camsel_main", {})
    ok18 = bool(main.get("ok")) and bool(main.get("bit12")) and bool(main.get("b_selected"))
    chk("C18", ok18, "tb cam_sysstat[12]=%s b_selected=%s" %
        (main.get("bit12"), main.get("b_selected")))
else:
    print("C18 PENDING tb stub-top cam_sysstat bit12 (run r0/sim/run_b18.py camsel)")

# ---- summary ---------------------------------------------------------------
print("MERGE_SUMMARY checks=%d fail=%d %s" %
      (len(results), len(fails), "ALL_PASS" if not fails else "FAILED:" + ",".join(fails)))
sys.exit(0 if not fails else 1)
