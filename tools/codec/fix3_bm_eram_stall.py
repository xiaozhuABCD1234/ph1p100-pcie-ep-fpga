# -*- coding: utf-8 -*-
"""T10.a1-bm-eram r0 fix3: stored-path stall drift.

Proved with a probe (rand1920x16): in S_SDATA_R the synchronous read data
bm_a_rd is bm[raddr(t-1)].  While the output FIFO keeps accepting, that is
bm[sdata_ptr+1] (correct "next byte"), but a stalled cycle does not advance the
address, so one cycle later bm_a_rd has drifted to bm[sdata_ptr+2] and the byte
captured on the following accept is one too far -- which at the block tail is
the unwritten address blk_n (8'hxx).

Fix: latch the correct next byte in sd_hold on the FIRST stall cycle of an
episode and take it on the next accept.  Throughput is unchanged (1 stored byte
per accepted cycle, no extra cycles, no bubbles).
"""
import hashlib
import io
import sys

CORE = ("C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/"
        "upstream/ph1p100-pcie-ep-fpga/rtl/ep_side/codec/a1_deflate_core.v")

R = [
    ("drop_probe",
     """    // TEMP X-PROBE (simulation only, removed before freeze)
    always @(posedge clk) begin
        if ((state == S_SDATA_R) && ((sdata_ptr < 13'd4) || (sdata_ptr >= (blk_n - 13'd4))))
            $display("SD sdp=%0d raddr=%0d sd=%b rd=%b exp=%b acc=%b bank=%b bn=%0d",
                     sdata_ptr, raddr, sd_byte, bm_a_rd, bm_a[{enc_bank, sdata_ptr}],
                     opq_accept, enc_bank, blk_n);
    end
""", ""),

    ("decl",
     """    reg [7:0]  sd_byte;
""",
     """    reg [7:0]  sd_byte;
    // Stall hold: the registered read data is bm[raddr(t-1)], i.e. correct in a
    // continuously advancing stream.  On the first stalled cycle the address
    // stops moving, so latch that cycle's value here and use it for the next
    // accepted byte instead of the (one too far) drifted read data.
    reg [7:0]  sd_hold;
    reg        sd_in_q;    // previous cycle was S_SDATA_R
    reg        sd_acc_q;   // previous S_SDATA_R cycle accepted
"""),

    ("reset",
     """            sd_byte        <= 8'd0;
""",
     """            sd_byte        <= 8'd0;
            sd_hold        <= 8'd0;
            sd_in_q        <= 1'b0;
            sd_acc_q       <= 1'b0;
"""),

    ("track",
     """            // -------------------------------------------------- input loader
            if (in_acc) begin
""",
     """            // stored-path stall tracking (see sd_hold declaration)
            sd_in_q  <= (state == S_SDATA_R);
            sd_acc_q <= (state == S_SDATA_R) && opq_accept;
            if ((state == S_SDATA_R) && !opq_accept && !(sd_in_q && !sd_acc_q))
                sd_hold <= bm_a_rd;

            // -------------------------------------------------- input loader
            if (in_acc) begin
"""),

    ("advance",
     """                        end else begin
                            sdata_ptr <= sdata_ptr + 13'd1;
                            sd_byte   <= bm_a_rd;      // next byte, stall safe
                            raddr     <= raddr + 13'd1;
""",
     """                        end else begin
                            sdata_ptr <= sdata_ptr + 13'd1;
                            sd_byte   <= (sd_in_q && !sd_acc_q) ? sd_hold : bm_a_rd;
                            raddr     <= raddr + 13'd1;
"""),
]


def main():
    with io.open(CORE, "r", encoding="utf-8", newline="") as f:
        txt = f.read()
    print("before_sha=%s" % hashlib.sha256(txt.encode("utf-8")).hexdigest())
    for name, old, new in R:
        n = txt.count(old)
        if n != 1:
            print("FAIL %-12s found %d" % (name, n))
            return 3
        txt = txt.replace(old, new)
        print("ok   %s" % name)
    out = txt.encode("utf-8")
    print("after_sha=%s" % hashlib.sha256(out).hexdigest())
    if "--check" in sys.argv:
        print("CHECK_ONLY")
        return 0
    with io.open(CORE, "wb") as f:
        f.write(out)
    print("written")
    return 0


if __name__ == "__main__":
    sys.exit(main())
