#!/usr/bin/env python3
"""gen_stubs.py -- generate T10.b18-b17-b structural stubs + stub-top TB.

The merged p2_a1_board_top cannot be elaborated for simulation with the real
PLL / DDR shell / MCU ROM / MIPI PHY, but the camera-select mux and the
cam_sysstat packing are pure structural code inside that top.  This script
emits behavioural stubs with the *exact* port lists of the real modules
(parsed from the frozen sources) and a TB that instantiates the real merged top
so the select mux and the status word can be observed port-by-port.

stub/  : p2_a1_pll, p2_ddrmc_shell, usr_mcu_wrapper, f9p_camera_display_core,
         camera_a1_uart_top, p2_ddr_bridge
tb_b18_camsel.sv : real top + stubs, checks cam_sysstat bit12 and the B tap.
"""
import pathlib
import re

HERE = pathlib.Path(__file__).resolve().parent
PKG = HERE.parent
CS = PKG / "changed-src"
TD = PKG / "td"
STUB = HERE / "stub"
STUB.mkdir(parents=True, exist_ok=True)

SRC = {
    "p2_a1_pll": TD / "src/p2_a1_pll.v",
    "p2_ddrmc_shell": TD / "src/p2_ddrmc_shell.v",
    "usr_mcu_wrapper": TD / "src/vendor/rtl/usr_mcu_srcs/usr_mcu_wrapper.v",
    "f9p_camera_display_core": CS / "f9p_camera_display_core.v",
    "camera_a1_uart_top": CS / "camera_a1_uart_top.v",
    "p2_ddr_bridge": CS / "p2_ddr_bridge.v",
}
TOP = CS / "p2_a1_board_top.v"


def strip_comments(t):
    t = re.sub(r"/\*.*?\*/", "", t, flags=re.S)
    return re.sub(r"//[^\n]*", "", t)


def split_top(t):
    out, depth, cur = [], 0, ""
    for ch in t:
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        if ch == "," and depth == 0:
            out.append(cur)
            cur = ""
        else:
            cur += ch
    if cur.strip():
        out.append(cur)
    return out


def parse_ports(path, name):
    t = strip_comments(pathlib.Path(path).read_text(encoding="utf-8", errors="replace"))
    m = re.search(r"\bmodule\s+%s\b(.*?)\bendmodule" % re.escape(name), t, re.S)
    if not m:
        raise SystemExit("module %s not found in %s" % (name, path))
    body = m.group(1)
    # optional parameter list
    params = ""
    pm = re.match(r"\s*#\s*\(", body)
    if pm:
        depth, i = 0, pm.end() - 1
        start = pm.end() - 1
        while i < len(body):
            if body[i] == "(":
                depth += 1
            elif body[i] == ")":
                depth -= 1
                if depth == 0:
                    break
            i += 1
        params = "#" + body[start:i + 1]
        body = body[i + 1:]
    pm2 = re.search(r"\(", body)
    depth, i = 0, pm2.end() - 1
    start = pm2.end() - 1
    while i < len(body):
        if body[i] == "(":
            depth += 1
        elif body[i] == ")":
            depth -= 1
            if depth == 0:
                break
        i += 1
    ports_txt = body[start + 1:i]
    ports = []
    direction = None
    for item in split_top(ports_txt):
        s = " ".join(item.split())
        if not s:
            continue
        dm = re.match(r"(input|output|inout)\b(.*)", s)
        if dm:
            direction = dm.group(1)
            s = dm.group(2).strip()
            s = re.sub(r"^(wire|reg|logic)\b", "", s).strip()
        rng = ""
        rm = re.match(r"(\[[^\]]+\])\s*(.*)$", s)
        if rm:
            rng, s = rm.group(1), rm.group(2)
        for n in [x.strip() for x in s.split(",") if x.strip()]:
            n = re.sub(r"\[[^\]]*\]", "", n).strip()
            if re.match(r"^[A-Za-z_]\w*$", n):
                ports.append((direction, rng, n))
    return params, ports


def emit(name, params, ports, overrides, header):
    hdr = "module %s " % name + (params.strip() + " (" if params.strip() else "(")
    lines = ["// %s" % header, hdr]
    decls = []
    for d, rng, n in ports:
        decls.append("    %-6s %-6s %s" % (d, rng or "      ", n))
    lines.append(",\n".join(decls))
    lines.append(");")
    for d, rng, n in ports:
        if d == "output":
            lines.append("    assign %s = %s;" % (n, overrides.get(n, "1'b0")))
        elif d == "inout":
            lines.append("    // inout %s left open in the stub" % n)
    lines.append("endmodule")
    return "\n".join(lines) + "\n"


F9P = {
    "o_a_pixel": "40'hA5_A5A5_A5A5",
    "o_b_pixel": "40'hB1_8B18_B18B",
    "o_a_pixel_valid": "1'b0",
    "o_b_pixel_valid": "1'b1",
    "o_a_in_line": "1'b0",
    "o_b_in_line": "1'b1",
    "o_a_in_frame": "1'b0",
    "o_b_in_frame": "1'b1",
    "o_a_vsync": "1'b0",
    "o_b_vsync": "1'b1",
    "o_a_byte_clk": "sys_clk50m",
    "o_b_byte_clk": "sys_clk50m",
    "o_dbg_a_cfg_done": "1'b0",
    "o_dbg_b_cfg_done": "1'b1",
    "o_dbg_a_bus_err_lat": "1'b0",
    "o_dbg_b_bus_err_lat": "1'b0",
    "o_dbg_a_nack_cnt": "32'h0000_00A1",
    "o_dbg_b_nack_cnt": "32'h0000_00B1",
    "o_dbg_a_lane_sticky": "4'hF",
    "o_dbg_b_lane_sticky": "4'h1",
    "o_dbg_a_delay_tap": "6'd46",
    "o_dbg_b_delay_tap": "6'd46",
    "o_dbg_b_delay_done": "1'b1",
    "o_dbg_xclr_n": "1'b1",
    "o_dbg_pll_locked": "1'b1",
    "o_dbg_cfg_rst_n": "1'b1",
}
PL = {"clk_out": "refclk", "lock": "1'b1"}
DDRMC = {"dhi_clk": "ref_clk", "cfg_clk": "ref_clk",
         "ddrphy_rst_n": "1'b1", "ddrphy_rdy": "1'b1"}

for name, path in SRC.items():
    params, ports = parse_ports(path, name)
    ov = {"f9p_camera_display_core": F9P, "p2_a1_pll": PL,
          "p2_ddrmc_shell": DDRMC}.get(name, {})
    (STUB / (name + "_stub.v")).write_text(
        emit(name, params, ports, ov,
             "T10.b18-b17-b structural stub of %s (ports copied verbatim)" % name),
        encoding="ascii")

# ---- TB around the real merged top -----------------------------------------
tparams, tports = parse_ports(TOP, "p2_a1_board_top")
decl, conn = [], []
for d, rng, n in tports:
    w = (" " + rng) if rng else ""
    if d == "input":
        decl.append("    reg  %s %s = 1'b0;" % (w, n))
        if n in ("sys_rst_n",):
            decl[-1] = "    reg  %s %s;" % (w, n)
        if n in ("sys_clk50m",):
            decl[-1] = "    reg  %s %s = 1'b0;" % (w, n)
    else:
        decl.append("    wire %s %s;" % (w, n))

TB = """`timescale 1ns/1ps
// =============================================================================
// tb_b18_camsel.sv -- T10.b18-b17-b CAM_SEL=1 structural test (C18 / T5 bit12).
// Instantiates the REAL merged p2_a1_board_top; only the PLL, DDR shell, MCU
// ROM, MIPI camera core, A1 chain and PAXI bridge are stubbed (their port lists
// are copied verbatim from the frozen sources).  A and B taps carry different
// signatures, so a wrong mux is a hard failure, not a coincidence.
// =============================================================================
module tb_b18_camsel;
%s

    always #10 sys_clk50m = ~sys_clk50m;   // 50 MHz board clock

    p2_a1_board_top u_top (.*);

    integer     errs = 0;
    integer     bclk_edges = 0;
    reg [31:0]  sysstat;
    reg [3:0]   lane;
    reg [39:0]  pix;

    always @(posedge sys_clk50m) bclk_edges = bclk_edges + 1;

    task fail(input [1023:0] why);
        begin
            errs = errs + 1;
            $display("B18_CAMSEL_FAIL %%0s", why);
        end
    endtask

    initial begin
        #50 sys_rst_n = 1'b0;
        #500 sys_rst_n = 1'b1;
        repeat (40) @(posedge sys_clk50m);
        sysstat = u_top.u_dbg_sys_mail.i_data[63:32];
        lane    = u_top.u_dbg_sys_mail.i_data[43:40];
        $display("B18_CAMSEL_SYSSTAT=%%h NACK=%%h", sysstat,
                 u_top.u_dbg_sys_mail.i_data[31:0]);
        $display("B18_CAMSEL_U_A1_PIXEL=%%h CLK_EDGES=%%0d I_VALID=%%b",
                 u_top.u_a1.i_a_pixel, bclk_edges, u_top.u_a1.i_a_pixel_valid);
        if (sysstat[12] !== 1'b1)      fail("cam_sysstat[12] (CAM_SEL) != 1");
        if (lane !== 4'h1)             fail("sel_lane_sticky is not the B value");
        if (sysstat !== 32'h0000_111d) fail("cam_sysstat word mismatch");
        pix = u_top.u_a1.i_a_pixel;
        if (pix !== 40'hB1_8B18_B18B)  fail("u_a1 sees the A tap, not B");
        if (bclk_edges < 10)           fail("selected byte clock not toggling");
        if (u_top.u_a1.i_a_pixel_valid !== 1'b1) fail("i_a_pixel_valid not B");
        $display("B18_CAMSEL_RESULT pass=%%0d bit12=%%0d b_selected=%%0d sysstat=%%h",
                 (errs == 0), sysstat[12], (pix === 40'hB1_8B18_B18B), sysstat);
        $finish;
    end

    initial begin
        #2000000;
        $display("B18_CAMSEL_TIMEOUT");
        $finish;
    end
endmodule
""" % "\n".join(decl)

(HERE / "tb_b18_camsel.sv").write_text(TB, encoding="ascii")
print("STUBS_OK files=%d tb=%s" % (len(SRC), (HERE / "tb_b18_camsel.sv")))
