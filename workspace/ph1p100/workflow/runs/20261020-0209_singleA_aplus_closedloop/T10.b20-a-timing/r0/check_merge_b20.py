#!/usr/bin/env python3
"""check_merge_b20.py -- T10.b20-a-timing merge conformance (C01..C19 + C20).

Static, read-only (except writing nothing).  One line per check, non-zero exit
on failure.  C18 needs the stub-top simulation (r0/sim/sim-results-b20-camsel.json)
and is reported as PENDING before that run.

Delta contract vs T10.b19-cam-a r0:
  * the other 10 changed-src files and td/{p2_board.sdc,board_p2.adc} hash-equal;
  * a1_frame_top.v is the ONLY changed file: one registered abort (abort_d) for
    the drain side (dstate/bank_busy/dblk teardown one cycle later), so the ERAM
    read-address cone is never launched from the raw abort input;
  * C20 = frozen-anchor equality (module ports, crc32b, frame_abort, proto_abort/
    core_abort, in_ready, frame_commit/out_*, u_core instance, output packing,
    dbg map, smem write port, st_* map, drain cadence, stat updates) plus a
    hunk whitelist and an ifdef/force/new-port rejection.
"""
import difflib
import hashlib
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(r"D:\fpga\ph1p100")
RUN = ROOT / "workflow/runs/20261020-0209_singleA_aplus_closedloop"
PKG = RUN / "T10.b20-a-timing"
R0 = PKG / "r0"
CS = R0 / "changed-src"
TD = R0 / "td"
SIM = R0 / "sim"
B19 = RUN / "T10.b19-cam-a"
B19CS = B19 / "r0/changed-src"
B17 = RUN / "T10.b17-paxi-native"

B19_SDC = "0888b6a705a039a6cbabebacf323244a36257b5f29fb51bab7d81ef003220f5e"
B19_ADC = "1cb30346fa17da6bb0e77802ca72c4b4bb4aecc1445711e19391cf4ee2271580"
B19_FRAME = "0064607aceb20ae3ef14133f0aaf5f8b3f489943011a66a1ddc005350dba7109"

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
fr_b19 = (B19CS / "a1_frame_top.v").read_text(encoding="utf-8", errors="replace")
fr_b20 = (CS / "a1_frame_top.v").read_text(encoding="utf-8", errors="replace")

EXPECT = {
    "f9p_camera_display_core.v": "e17206fb2e15f7590ee55c2ccc072677356ab2cb8efa41fd95ad6d52ab080760",
    "p2_ddr_bridge.v": "790d8226ec69499c87b92b0e4a05ac0f26915f57b96bd541affdcdac8e740a61",
    "a1_uart_export.v": "b3d61597534aa0609c53634313e4d14f222839f8b9b8ed83afc140daa04c298d",
    "camera_a1_uart_top.v": "73d10388c4a802421563b5b4c66f9cc37d600e7ec49fc0fa94b3d3ea0cbd3ff2",
}
# 10 of 11 files must stay byte-identical to b19 (a1_frame_top.v is the delta).
SHARED10 = {
    "a1_ddr_arb2.v": "b84019bda057afe82ff558e0848d6171fa12732bd8cdb7c6239cb71b3f81d6ba",
    "a1_ddr_slot_store.v": "6c619cf90e54385d667f1ec0f63cc87ee58aadd3c42143330ac4945eb47defe9",
    "a1_deflate_core.v": "a91c2ed82fbef654c4e065b64ae1cc268ca232feaa26fdd313c58d8740f81b3e",
    "a1_raw_crop.v": "33a6fee77fd1aa67a31cacf26dd5530e5e2ea474ee655cbd5f1d98d887c5d72d",
    "a1_uart_export.v": "b3d61597534aa0609c53634313e4d14f222839f8b9b8ed83afc140daa04c298d",
    "camera_a1_uart_top.v": "73d10388c4a802421563b5b4c66f9cc37d600e7ec49fc0fa94b3d3ea0cbd3ff2",
    "cam_diag_mailbox.v": "352af7c85094ea99b575e99da952af8d33871352140e4c6efddff9e6c2407278",
    "f9p_camera_display_core.v": "e17206fb2e15f7590ee55c2ccc072677356ab2cb8efa41fd95ad6d52ab080760",
    "p2_a1_board_top.v": "b08438e82adcb82726e6632a765e4ac134caea3bb79e0c0a3468274c135981d0",
    "p2_ddr_bridge.v": "790d8226ec69499c87b92b0e4a05ac0f26915f57b96bd541affdcdac8e740a61",
}

# ---- C01..C04 exact copies --------------------------------------------------
for i, name in enumerate(["f9p_camera_display_core.v", "p2_ddr_bridge.v",
                          "a1_uart_export.v", "camera_a1_uart_top.v"], start=1):
    got = sha(CS / name)
    chk("C%02d" % i, got == EXPECT[name], "%s %s" % (name, got))

# ---- C05 the ten unchanged changed-src files -------------------------------
bad = [n for n, h in SHARED10.items() if sha(CS / n) != h]
chk("C05", not bad and sha(CS / "a1_frame_top.v") != B19_FRAME,
    "10/11 byte-identical to b19 (drift=%s), a1_frame_top.v is the delta (%s)" %
    (bad, sha(CS / "a1_frame_top.v")[:16]))

# ---- C06..C12 merged top shape ---------------------------------------------
chk("C06", cnt(top, "localparam CAM_SEL = 1'b0;") == 1 and
    cnt(top, "localparam CAM_SEL = 1'b1;") == 0,
    "CAM_SEL=0 count=%d (1 count=%d)" % (cnt(top, "localparam CAM_SEL = 1'b0;"),
                                         cnt(top, "localparam CAM_SEL = 1'b1;")))
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


c14a = sdc_sha == B19_SDC
c14b = cnt(sdc, "-name {mipi_b_byte_clk}") == 1 and \
    cnt(sdc, "-source [get_ports {mipi_b_clk_hs_p}] -divide_by 4") == 1
c14c = cnt(sdc, "-group {mipi_a_clk_hs mipi_a_byte_clk}") == 1 and \
    cnt(sdc, "-group {mipi_b_clk_hs mipi_b_byte_clk}") == 0
c14d = fp_lines(sdc) == fp_lines(b17_sdc)
chk("C14", c14a and c14b and c14c and c14d,
    "sdc=%s genclk_b_kept=%s a_group_kept/b_group_removed=%s false/multicycle_unchanged=%s (n=%d)" %
    (sdc_sha[:16], c14b, c14c, c14d, len(fp_lines(sdc))))

# ---- C15 ADC ---------------------------------------------------------------
adc = sha(TD / "board_p2.adc")
chk("C15", adc == B19_ADC, "board_p2.adc %s" % adc)

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
    "pkg_paths": len(re.findall(r"T10\.b20-a-timing/r0/changed-src", build)),
    "stale_b19": cnt(build, "T10.b19-cam-a"),
    "stale_b18": cnt(build, "T10.b18-b17-b"),
    "stale_src": len([1 for n in ("f9p_camera_display_core.v", "p2_a1_board_top.v",
                                  "p2_ddr_bridge.v")
                      if (TD / "src" / n).exists()]),
    "stale_add": len([l for l in addlines if re.search(
        r"\./src/(f9p_camera_display_core|p2_a1_board_top|p2_ddr_bridge)\.v", l)]),
    "double_src": len([l for l in addlines if "src/src/" in l]),
}
ok16 = (c16["tcl_f9p"] == 1 and c16["tcl_top"] == 1 and c16["al_f9p"] == 1 and
        c16["al_top"] == 1 and c16["guard"] == 1 and c16["pkg_paths"] >= 10 and
        c16["stale_b19"] == 0 and c16["stale_b18"] == 0 and
        c16["stale_src"] == 0 and c16["stale_add"] == 0 and c16["double_src"] == 0)
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
diffs = sorted(set(dict(pairs).items()) ^ set(B13_A.items()))
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

# ---- C18 TB-visible cam_sysstat + A select --------------------------------
j = SIM / "sim-results-b20-camsel.json"
if j.exists():
    r = json.loads(j.read_text())
    main = r.get("camsel_main", {})
    mk = " ".join(main.get("markers") or [])
    mm = re.search(r"sysstat=([0-9a-fA-F]{8})", mk)
    sysstat = int(mm.group(1), 16) if mm else None
    ok18 = (bool(main.get("ok")) and main.get("bit12") is True and
            main.get("a_selected") is True and not main.get("b_selected") and
            sysstat == 0x00000F1D)
    chk("C18", ok18, "tb cam_sysstat=%s bit12=%s a_selected=%s b_selected=%s" %
        (("0x%08x" % sysstat) if sysstat is not None else None,
         main.get("bit12"), main.get("a_selected"), main.get("b_selected")))
else:
    print("C18 PENDING tb stub-top cam_sysstat 0x00000F1D (run r0/sim/run_b20.py camsel)")

# ---- C19 SDC/ADC byte-identical to b19 (no new constraint edit) ------------
b19_sdc_txt = (B19 / "r0/td/p2_board.sdc").read_text(encoding="utf-8", errors="replace")
chk("C19", sdc_sha == B19_SDC and sdc == b19_sdc_txt and adc == B19_ADC and
    sha(B19 / "r0/td/board_p2.adc") == B19_ADC,
    "sdc byte-identical to b19 (%s) adc byte-identical (%s)" % (sdc_sha[:16], adc[:16]))

# ---- C20 frozen anchors + hunk whitelist ----------------------------------
def norm(t):
    return re.sub(r"[ \t\r\n]+", " ", t).strip()


N19, N20 = norm(fr_b19), norm(fr_b20)


def block(src, start, end, incl_end=True):
    i = src.find(start)
    if i < 0:
        return None
    j = src.find(end, i + len(start))
    if j < 0:
        return None
    return src[i:(j + len(end)) if incl_end else j]


ANCHORS = [
    ("A01_ports", block(fr_b19, "module a1_frame_top #(", "\n);")),
    ("A02_crc32b", block(fr_b19, "function [31:0] crc32b;", "endfunction")),
    ("A03_frame_abort", "assign frame_abort = frame_abort_r;"),
    ("A04_proto_abort", "wire proto_abort = frame_active && in_valid && in_sof;"),
    ("A05_core_abort", "wire core_abort = abort || proto_abort || core_flush;"),
    ("A06_in_ready", block(fr_b19, "assign in_ready = (istate == I_IDLE) && !abort &&",
                           ";")),
    ("A07_out_pack_assign", block(fr_b19, "assign out_valid    = svalid;",
                                  "assign frame_abort  = frame_abort_r;")),
    ("A08_u_core", block(fr_b19, "a1_deflate_core u_core (", ");")),
    ("A09_out_packing", block(fr_b19,
                              "// ------------------------------------------------- output packing",
                              "if (svalid && out_ready) begin", False)),
    ("A10_dbg", block(fr_b19, "assign dbg = {4'd0, in_ready, core_state, core_done, core_busy,",
                      "frame_active, istate, dstate};")),
    ("A11_smem_write", block(fr_b19, "if (smem_we_r)", "smem[smem_waddr_r] <= smem_wdata_r;")),
    ("A12_raddr_of", block(fr_b19, "function [15:0] raddr_of;", "endfunction")),
    ("A13_d_idle", block(fr_b19, "D_IDLE: begin", "D_GATH: begin", False)),
    ("A14_d_gath", block(fr_b19, "D_GATH: begin", "D_EMIT: begin", False)),
    ("A15_d_emit", block(fr_b19, "D_EMIT: begin", "default: ; // D_FIN", False)),
    ("A16_commit_block", block(fr_b19, "if (svalid && out_ready) begin",
                               "bank_busy    <= 2'b00;")),
    ("A17_st_map", block(fr_b19, "assign st_raw_len      = raw_len_r;",
                         "assign st_busy         = frame_active;")),
    ("A18_crc_updates", block(fr_b19, "raw_crc_r <= crc32b(raw_crc_r, b_t);",
                              "raw_len_r <= raw_len_r + 32'd1;")),
    ("A19_emit_updates", block(fr_b19,
                               "xf_crc_r   <= crc32b(xf_crc_r, core_in_data);",
                               "first_byte <= 1'b0;")),
    ("A20_str_updates", block(fr_b19,
                              "str_crc_r <= crc32b(str_crc_r, core_out_data);",
                              "slen_r    <= slen_r + 32'd1;")),
    ("A21_core_in_map", block(fr_b19, "assign core_in_data",
                              "assign core_out_ready     = !svalid;")),
    ("A22_iexp", block(fr_b19, "end else if (istate == I_EXP) begin",
                       "end else if (istate == I_ABORT) begin", False)),
]
anchor_bad = []
anchor_ok = 0
for aid, txt in ANCHORS:
    if txt is None:
        anchor_bad.append(aid + ":missing_in_b19")
        continue
    n = norm(txt)
    if n in N20:
        anchor_ok += 1
    else:
        anchor_bad.append(aid + ":changed")

forbidden = []
for pat in ("`ifdef", "`ifndef", "`define", "`force", " force ", "$force"):
    if pat in fr_b20:
        forbidden.append(pat)
if re.search(r"\babort_d\b", fr_b20) is None:
    forbidden.append("abort_d_missing")

# hunk whitelist: every added/removed line must be one of the approved shapes
ADD_OK = [
    r"^\s*//",
    r".*abort_d.*",
    r"^\s*first_byte\s*<=\s*1'b0;\s*(//.*)?$",
    r"^\s*dstate\s*<=\s*D_IDLE;\s*$",
    r"^\s*dblk\s*<=\s*16'd0;\s*$",
    r"^\s*bank_busy\s*<=\s*2'b00;\s*$",
    r"^\s*if \(abort_d\) begin\s*$",
    r"^\s*end else case \(dstate\)\s*$",
    r"^\s*!\(svalid && out_ready && slast && !killed\);\s*$",
    r"^\s*end\s*$",
]
DEL_OK = [
    r"^\s*//",
    r"^\s*dstate\s*<=\s*D_IDLE;\s*$",
    r"^\s*dblk\s*<=\s*16'd0;\s*$",
    r"^\s*bank_busy\s*<=\s*2'b00;\s*$",
    r"^\s*case \(dstate\)\s*$",
]
diff_lines = list(difflib.unified_diff(fr_b19.splitlines(), fr_b20.splitlines(),
                                       "b19/a1_frame_top.v", "b20/a1_frame_top.v",
                                       n=0, lineterm=""))
bad_hunks = []
nadd = ndel = 0
for l in diff_lines:
    if l.startswith("+++") or l.startswith("---") or l.startswith("@@"):
        continue
    if l.startswith("+"):
        nadd += 1
        if not any(re.match(r, l[1:]) for r in ADD_OK):
            bad_hunks.append(l)
    elif l.startswith("-"):
        ndel += 1
        if not any(re.match(r, l[1:]) for r in DEL_OK):
            bad_hunks.append(l)
chk("C20", anchor_ok == len(ANCHORS) and not anchor_bad and not forbidden and
    nadd <= 30 and ndel <= 20 and not bad_hunks,
    "anchors=%d/%d bad=%s forbidden=%s diff(+%d/-%d) nonwhitelisted=%s" %
    (anchor_ok, len(ANCHORS), anchor_bad, forbidden, nadd, ndel, bad_hunks[:6]))

# ---- summary ---------------------------------------------------------------
print("MERGE_SUMMARY checks=%d fail=%d %s" %
      (len(results), len(fails), "ALL_PASS" if not fails else "FAILED:" + ",".join(fails)))
sys.exit(0 if not fails else 1)
