# -*- coding: utf-8 -*-
"""T10.a1-bm-eram r0 fix2: make the stored (BTYPE=00) replay path stall-safe.

Root cause (proved with an X probe on rand1920x16): S_SDATA_R emitted
op_value = bm_a_rd, i.e. bm[raddr(t-1)] with raddr = sdata_ptr+2.  As long as the
output FIFO keeps accepting, the emitted byte is bm[sdata_ptr]; but when opq is
full (P3 frame backpressure) the state holds, raddr holds, and the registered
read then presents bm[sdata_ptr+1] -- and at the last byte sdata_ptr+1 == blk_n,
an address the loader never wrote -> 8'hxx into the stream.  P2 never stalls
internally, which is why only P3 exposed it.

Fix: keep an explicit byte holding register sd_byte (op_value = sd_byte) and
advance the fetch address only when the byte is accepted.  The synchronous read
port stays "address issued two cycles before the byte is consumed", so the
symbol rate is unchanged (one stored byte per accepted cycle, no extra cycles).

Also removes the temporary X probe.  Exact-match replacements with assertions.
"""
import hashlib
import io
import sys

CORE = ("C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/"
        "upstream/ph1p100-pcie-ep-fpga/rtl/ep_side/codec/a1_deflate_core.v")

R = [
    # ---- remove the temporary probe -------------------------------------
    ("drop_probe",
     """    // TEMP X-PROBE (simulation only, removed before freeze)
    always @(posedge clk) begin
        if (opq_accept && (^op_value === 1'bx))
            $display("XOP st=%0d val=%b bank=%b raddr=%0d blk_n=%0d pos=%0d cwptr=%0d rb=%0d sdp=%0d",
                     state, op_value, enc_bank, raddr, blk_n, pos, cwptr, rb_word, sdata_ptr);
        if (p0_valid && (^p0_value === 1'bx))
            $display("XCP st=%0d cp=%b lval=%b w0=%b w1=%b w2=%b x1=%b",
                     state, p0_value, lval, w0, w1, w2, x1_r);
        if ((state == S_SDATA_R) && (sdata_ptr >= (blk_n - 13'd3)))
            $display("SDEND sdp=%0d raddr=%0d val=%b exp=%b rd=%b prev=%b",
                     sdata_ptr, raddr, op_value, bm_a[{enc_bank, sdata_ptr}],
                     bm_a[{enc_bank, raddr}], bm_a[{enc_bank, sdata_ptr - 13'd1}]);
    end
""", ""),

    # ---- declaration -----------------------------------------------------
    ("decl_sd_byte",
     """    // stored path
    reg [3:0]  hdr_idx;
    reg [3:0]  slen_idx;
    reg [12:0] sdata_ptr;
""",
     """    // stored path
    reg [3:0]  hdr_idx;
    reg [3:0]  slen_idx;
    reg [12:0] sdata_ptr;
    // Byte holding register: the synchronous bm read is issued two cycles ahead,
    // so the byte for the current cycle is kept here and only advanced when the
    // output FIFO accepts it (stall safe: a stalled cycle re-presents the same
    // byte instead of the next read word).
    reg [7:0]  sd_byte;
"""),

    # ---- reset / abort ---------------------------------------------------
    ("reset_sd_byte",
     """            sdata_ptr      <= 13'd0;
            tadler_idx     <= 4'd0;
""",
     """            sdata_ptr      <= 13'd0;
            sd_byte        <= 8'd0;
            tadler_idx     <= 4'd0;
"""),

    # ---- op_value --------------------------------------------------------
    ("op_sd_byte",
     """            S_SDATA_R: begin
                op_en    = 1'b1;
                op_value = bm_a_rd;
                op_bits  = 4'd8;
            end
""",
     """            S_SDATA_R: begin
                op_en    = 1'b1;
                op_value = sd_byte;
                op_bits  = 4'd8;
            end
"""),

    # ---- S_SLEN seeding --------------------------------------------------
    ("slen_seed2",
     """                        if (slen_idx == 4'd3) begin
                            sdata_ptr <= 13'd0;
                            raddr     <= 13'd1;   // bm[0] was issued at idx 2, bm[1] here
                            state     <= S_SDATA_R;
                        end else begin
                            // seed the synchronous bm_a read one cycle early so
                            // the first S_SDATA_R cycle already emits bm[0]
                            if (slen_idx == 4'd2) raddr <= 13'd0;
                            slen_idx <= slen_idx + 4'd1;
                        end
""",
     """                        if (slen_idx == 4'd3) begin
                            sdata_ptr <= 13'd0;
                            sd_byte   <= bm_a_rd;   // bm[0], fetched during idx 2
                            raddr     <= 13'd2;     // fetch stream stays two ahead
                            state     <= S_SDATA_R;
                        end else begin
                            // prime the synchronous read: bm[0] issued at idx 1,
                            // bm[1] at idx 2, so bm_a_rd is ready one byte ahead
                            if (slen_idx == 4'd1) raddr <= 13'd0;
                            if (slen_idx == 4'd2) raddr <= 13'd1;
                            slen_idx <= slen_idx + 4'd1;
                        end
"""),

    # ---- S_SDATA_R advance ----------------------------------------------
    ("sdata_adv",
     """                        end else begin
                            sdata_ptr <= sdata_ptr + 13'd1;
                            // the synchronous read must be issued one byte ahead
                            raddr     <= sdata_ptr + 13'd2;
                        end
""",
     """                        end else begin
                            sdata_ptr <= sdata_ptr + 13'd1;
                            sd_byte   <= bm_a_rd;      // next byte, stall safe
                            raddr     <= raddr + 13'd1;
                        end
"""),
]


def main():
    with io.open(CORE, "r", encoding="utf-8", newline="") as f:
        txt = f.read()
    print("before_sha=%s" % hashlib.sha256(txt.encode("utf-8")).hexdigest())
    for name, old, new in R:
        n = txt.count(old)
        want = 1
        if n != want:
            print("FAIL %-16s found %d (want %d)" % (name, n, want))
            return 3
        txt = txt.replace(old, new)
        print("ok   %s" % name)
    out = txt.encode("utf-8")
    print("after_sha=%s" % hashlib.sha256(out).hexdigest())
    print("lines=%d" % txt.count("\n"))
    if "--check" in sys.argv:
        print("CHECK_ONLY")
        return 0
    with io.open(CORE, "wb") as f:
        f.write(out)
    print("written")
    return 0


if __name__ == "__main__":
    sys.exit(main())
