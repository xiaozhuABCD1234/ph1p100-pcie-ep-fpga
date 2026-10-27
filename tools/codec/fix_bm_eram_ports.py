# -*- coding: utf-8 -*-
"""Fix-up for patch_bm_eram.py: ModelSim requires declarations before use, so
the bm write/read port blocks move below all net declarations (after the
`assign busy` line).  Exact match + assertion; writes only when all pass.
"""
import hashlib
import io
import sys

CORE = ("C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/"
        "upstream/ph1p100-pcie-ep-fpga/rtl/ep_side/codec/a1_deflate_core.v")

R = []

R.append(("remove_write_port",
    """    // Block loader write port: one enable/address/data per clock, no reset
    // (ERAM template).  Same structure frame_top uses for smem.  The loader
    // bank and the encoding bank are always different while enc_busy, so a
    // read and a write never target the same word during encoding.
    wire        bm_we_w    = in_acc;
    wire [13:0] bm_waddr_w = in_sop ? 14'd0 : {ld_bank, ld_ptr};
    always @(posedge clk) begin
        if (bm_we_w)
            bm_a[bm_waddr_w] <= in_data;
    end
    always @(posedge clk) begin
        if (bm_we_w)
            bm_b[bm_waddr_w] <= in_data;
    end

""", ""))

R.append(("trim_read_port",
    """    reg  [7:0] bm_a_rd;
    reg  [7:0] bm_b_rd;
    wire       bm_hit_a = (state == S_SCAN) && hit2;
    wire [12:0] bm_raddr_a = bm_hit_a ? (p3_r + 13'd1)
                            : (state == S_EXT) ? ext_raddr
                            : ((state == S_SLEN) || (state == S_SDATA_R)) ? raddr
                            : praddr;
    wire [12:0] bm_raddr_b = bm_hit_a ? hf_r
                            : (state == S_EXT) ? ext_faddr
                            : raddr;
    always @(posedge clk) begin
        bm_a_rd <= bm_a[{enc_bank, bm_raddr_a}];
        bm_b_rd <= bm_b[{enc_bank, bm_raddr_b}];
    end
""",
    """    reg  [7:0] bm_a_rd;
    reg  [7:0] bm_b_rd;
"""))

R.append(("add_ports_after_busy",
    """    assign busy      = stream_active | enc_busy;
""",
    """    assign busy      = stream_active | enc_busy;

    // ------------------------------------------------------------- bm ports
    // Block loader write port: one enable/address/data per clock, no reset
    // (ERAM template, same structure frame_top uses for smem).  The loader bank
    // and the encoding bank are always different while enc_busy, so a read and
    // a write never target the same word during encoding.
    wire        bm_we_w    = in_acc;
    wire [13:0] bm_waddr_w = in_sop ? 14'd0 : {ld_bank, ld_ptr};
    always @(posedge clk) begin
        if (bm_we_w)
            bm_a[bm_waddr_w] <= in_data;
    end
    always @(posedge clk) begin
        if (bm_we_w)
            bm_b[bm_waddr_w] <= in_data;
    end

    // Read port: one registered address and one registered data word per array.
    wire        bm_hit_a   = (state == S_SCAN) && hit2;
    wire [12:0] bm_raddr_a = bm_hit_a ? (p3_r + 13'd1)
                           : (state == S_EXT) ? ext_raddr
                           : ((state == S_SLEN) || (state == S_SDATA_R)) ? raddr
                           : praddr;
    wire [12:0] bm_raddr_b = bm_hit_a ? hf_r
                           : (state == S_EXT) ? ext_faddr
                           : raddr;
    always @(posedge clk) begin
        bm_a_rd <= bm_a[{enc_bank, bm_raddr_a}];
        bm_b_rd <= bm_b[{enc_bank, bm_raddr_b}];
    end
"""))


def main():
    with io.open(CORE, "r", encoding="utf-8", newline="") as f:
        txt = f.read()
    print("cwd_sha256=%s" % hashlib.sha256(txt.encode("utf-8")).hexdigest())
    for name, old, new in R:
        n = txt.count(old)
        if n != 1:
            print("FAIL %-24s found %d" % (name, n))
            return 3
        txt = txt.replace(old, new)
        print("ok   %s" % name)
    out = txt.encode("utf-8")
    print("new_sha256=%s" % hashlib.sha256(out).hexdigest())
    print("lines=%d" % txt.count("\n"))
    with io.open(CORE, "wb") as f:
        f.write(out)
    print("written")
    return 0


if __name__ == "__main__":
    sys.exit(main())
