`timescale 1ns/1ps
// =============================================================================
// tb_b10_layout.sv -- T10.b10 B9-03 four-slot DDR layout, full size.
//
// Both real slot stores (MODE 0 raw / MODE 1 compressed) are driven through the
// real a1_ddr_arb2 into one flat 256-bit DDR model.  Each store fills BOTH of
// its slots at the frozen full size (RAW 129,600 words, CMP 81,085 words) at
// the same time, then all four slots are read back and compared word by word.
//
// Monitors:
//   * every write/read address of master 0 must stay inside
//     [RAW_BASE, RAW_BASE+2*RAW_WORDS) and master 1 inside
//     [CMP_BASE, CMP_BASE+2*CMP_WORDS);  a b9-layout run (+EXPECT_FAIL=1 with
//     -gCMP_BASE=131072) must trip this (old overlaps new).
//   * per-slot word counts (each slot must receive exactly SLOT_WORDS words).
//   * readback data must equal the generated pattern.
// =============================================================================
module b10_flat_ddr #(
    parameter integer WORDS = 524288
) (
    input  wire         clk,
    input  wire         rst_n,
    input  wire [31:0]  awaddr,
    input  wire         awvalid,
    output wire         awready,
    input  wire [255:0] wdata,
    input  wire         wvalid,
    output wire         wready,
    input  wire [31:0]  araddr,
    input  wire         arvalid,
    output wire         arready,
    output reg  [255:0] rdata,
    output reg          rvalid,
    input  wire         rready
);
    reg [255:0] mem [0:WORDS-1];
    reg         rpend;
    reg [3:0]   rwait;
    reg [31:0]  raddr_r;

    assign awready = rst_n;
    assign wready  = rst_n;
    assign arready = rst_n && !rpend && !rvalid;

    always @(posedge clk) begin
        if (!rst_n) begin
            rpend <= 1'b0; rwait <= 4'd0; rvalid <= 1'b0;
            rdata <= 256'd0; raddr_r <= 32'd0;
        end else begin
            if (rvalid && rready) rvalid <= 1'b0;
            if (arvalid && arready) begin
                raddr_r <= araddr;
                rpend   <= 1'b1;
                rwait   <= 4'd2;
            end else if (rpend) begin
                if (rwait == 4'd0) begin
                    rpend  <= 1'b0;
                    rdata  <= mem[raddr_r];
                    rvalid <= 1'b1;
                end else begin
                    rwait <= rwait - 4'd1;
                end
            end
        end
    end

    always @(posedge clk) begin
        if (rst_n && awvalid && awready && wvalid && wready)
            mem[awaddr] <= wdata;
    end
endmodule

module tb_b10_layout;
    parameter integer RAW_WORDS = 129600;
    parameter integer CMP_WORDS = 81085;
    parameter integer RAW_BASE  = 0;
    parameter integer CMP_BASE  = 262144;
    parameter integer DDR_WORDS = 524288;
    parameter integer EXPECT_FAIL = 0;   // 1 = old b9 layout negative control

    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    // -------------------------------------------------------------- raw master
    reg         raw_begin = 0, raw_valid = 0, raw_last = 0, raw_abort = 0;
    reg  [31:0] raw_bid = 0;
    reg  [39:0] raw_pix = 0;
    reg  [3:0]  raw_keep = 4'hF;
    wire        raw_begin_ready, raw_wr_ready;
    reg         raw_rd_open = 0, raw_rd_close = 0, raw_rd_take = 1;
    wire        raw_rd_open_ready, raw_rd_valid;
    wire [31:0] raw_rd_id, raw_rd_len;
    wire [255:0] raw_rd_data;
    wire [31:0] raw_awaddr, raw_araddr;
    wire        raw_awvalid, raw_awready, raw_wvalid, raw_wready;
    wire        raw_arvalid, raw_arready, raw_rvalid, raw_rready;
    wire [255:0] raw_wdata, raw_rdata;

    // -------------------------------------------------------------- cmp master
    reg         cmp_begin = 0, cmp_valid = 0, cmp_last = 0, cmp_abort = 0;
    reg  [31:0] cmp_bid = 0;
    reg  [31:0] cmp_wdat = 0;
    reg  [3:0]  cmp_keep = 4'hF;
    wire        cmp_begin_ready, cmp_wr_ready;
    reg         cmp_rd_open = 0, cmp_rd_close = 0, cmp_rd_take = 1;
    wire        cmp_rd_open_ready, cmp_rd_valid;
    wire [31:0] cmp_rd_id, cmp_rd_len;
    wire [255:0] cmp_rd_data;
    wire [31:0] cmp_awaddr, cmp_araddr;
    wire        cmp_awvalid, cmp_awready, cmp_wvalid, cmp_wready;
    wire        cmp_arvalid, cmp_arready, cmp_rvalid, cmp_rready;
    wire [255:0] cmp_wdata, cmp_rdata;

    // ---------------------------------------------------------------- arbiter
    wire [31:0]  s_awaddr, s_araddr;
    wire         s_awvalid, s_awready, s_wvalid, s_wready;
    wire [255:0] s_wdata, s_rdata;
    wire         s_arvalid, s_arready, s_rvalid, s_rready;

    a1_ddr_arb2 u_arb (
        .clk (clk), .rst_n (rst_n),
        .m0_awaddr (raw_awaddr), .m0_awvalid (raw_awvalid), .m0_awready (raw_awready),
        .m0_wdata (raw_wdata), .m0_wvalid (raw_wvalid), .m0_wready (raw_wready),
        .m0_araddr (raw_araddr), .m0_arvalid (raw_arvalid), .m0_arready (raw_arready),
        .m0_rdata (raw_rdata), .m0_rvalid (raw_rvalid), .m0_rready (raw_rready),
        .m1_awaddr (cmp_awaddr), .m1_awvalid (cmp_awvalid), .m1_awready (cmp_awready),
        .m1_wdata (cmp_wdata), .m1_wvalid (cmp_wvalid), .m1_wready (cmp_wready),
        .m1_araddr (cmp_araddr), .m1_arvalid (cmp_arvalid), .m1_arready (cmp_arready),
        .m1_rdata (cmp_rdata), .m1_rvalid (cmp_rvalid), .m1_rready (cmp_rready),
        .s_awaddr (s_awaddr), .s_awvalid (s_awvalid), .s_awready (s_awready),
        .s_wdata (s_wdata), .s_wvalid (s_wvalid), .s_wready (s_wready),
        .s_araddr (s_araddr), .s_arvalid (s_arvalid), .s_arready (s_arready),
        .s_rdata (s_rdata), .s_rvalid (s_rvalid), .s_rready (s_rready)
    );

    b10_flat_ddr #(.WORDS(DDR_WORDS)) u_ddr (
        .clk (clk), .rst_n (rst_n),
        .awaddr (s_awaddr), .awvalid (s_awvalid), .awready (s_awready),
        .wdata (s_wdata), .wvalid (s_wvalid), .wready (s_wready),
        .araddr (s_araddr), .arvalid (s_arvalid), .arready (s_arready),
        .rdata (s_rdata), .rvalid (s_rvalid), .rready (s_rready)
    );

    a1_ddr_slot_store #(
        .MODE (0), .SLOT_WORDS (RAW_WORDS), .BASE_WORD (RAW_BASE), .AWB (18),
        .EXPECT_BYTES (RAW_WORDS * 20)
    ) u_raw (
        .clk (clk), .rst_n (rst_n), .ddr_ready (1'b1),
        .wr_begin (raw_begin), .wr_begin_ready (raw_begin_ready), .wr_id (raw_bid),
        .wr_data (raw_pix), .wr_keep (raw_keep), .wr_valid (raw_valid),
        .wr_last (raw_last), .wr_ready (raw_wr_ready), .wr_abort (raw_abort),
        .rd_open (raw_rd_open), .rd_open_ready (raw_rd_open_ready), .rd_id (raw_rd_id),
        .rd_len_bytes (raw_rd_len), .rd_close (raw_rd_close), .rd_data (raw_rd_data),
        .rd_valid (raw_rd_valid), .rd_take (raw_rd_take),
        .ddr_awaddr (raw_awaddr), .ddr_awvalid (raw_awvalid), .ddr_awready (raw_awready),
        .ddr_wdata (raw_wdata), .ddr_wvalid (raw_wvalid), .ddr_wready (raw_wready),
        .ddr_araddr (raw_araddr), .ddr_arvalid (raw_arvalid), .ddr_arready (raw_arready),
        .ddr_rdata (raw_rdata), .ddr_rvalid (raw_rvalid), .ddr_rready (raw_rready),
        .st_published (), .st_dropped (), .st_errors (), .st_last_bytes (),
        .st_read_words (), .st_dup_words (),
        .st_wr_beats (), .st_wr_words (), .st_wr_ptr (), .st_wr_state (),
        .st_rd_state (), .st_slot_st (), .st_slot_len0 (), .st_slot_len1 (),
        .st_rd_idx (), .st_rd_words (), .st_ar_valid (), .st_ar_hs (),
        .st_rv_cnt (), .st_rd_open_ok (), .st_rd_close_cnt (), .st_abort_cnt (),
        .st_free_valid (), .st_wr_active_out ()
    );

    a1_ddr_slot_store #(
        .MODE (1), .SLOT_WORDS (CMP_WORDS), .BASE_WORD (CMP_BASE), .AWB (17)
    ) u_cmp (
        .clk (clk), .rst_n (rst_n), .ddr_ready (1'b1),
        .wr_begin (cmp_begin), .wr_begin_ready (cmp_begin_ready), .wr_id (cmp_bid),
        .wr_data ({8'd0, cmp_wdat}), .wr_keep (cmp_keep), .wr_valid (cmp_valid),
        .wr_last (cmp_last), .wr_ready (cmp_wr_ready), .wr_abort (cmp_abort),
        .rd_open (cmp_rd_open), .rd_open_ready (cmp_rd_open_ready), .rd_id (cmp_rd_id),
        .rd_len_bytes (cmp_rd_len), .rd_close (cmp_rd_close), .rd_data (cmp_rd_data),
        .rd_valid (cmp_rd_valid), .rd_take (cmp_rd_take),
        .ddr_awaddr (cmp_awaddr), .ddr_awvalid (cmp_awvalid), .ddr_awready (cmp_awready),
        .ddr_wdata (cmp_wdata), .ddr_wvalid (cmp_wvalid), .ddr_wready (cmp_wready),
        .ddr_araddr (cmp_araddr), .ddr_arvalid (cmp_arvalid), .ddr_arready (cmp_arready),
        .ddr_rdata (cmp_rdata), .ddr_rvalid (cmp_rvalid), .ddr_rready (cmp_rready),
        .st_published (), .st_dropped (), .st_errors (), .st_last_bytes (),
        .st_read_words (), .st_dup_words (),
        .st_wr_beats (), .st_wr_words (), .st_wr_ptr (), .st_wr_state (),
        .st_rd_state (), .st_slot_st (), .st_slot_len0 (), .st_slot_len1 (),
        .st_rd_idx (), .st_rd_words (), .st_ar_valid (), .st_ar_hs (),
        .st_rv_cnt (), .st_rd_open_ok (), .st_rd_close_cnt (), .st_abort_cnt (),
        .st_free_valid (), .st_wr_active_out ()
    );

    // ----------------------------------------------------------------- patterns
    function [39:0] group_pat(input integer slot, input integer g);
        group_pat = {8'hA0 + slot[7:0], ((g * 32'h9E37_79B1) ^ (slot * 32'h0123_4567))};
    endfunction

    function [31:0] word_pat(input integer slot, input integer i);
        word_pat = (i * 32'h9E37_79B1) ^ (slot * 32'h5A5A_0000) ^ 32'hC0DE_0000;
    endfunction

    // ------------------------------------------------------------- monitors
    integer raw0_wr = 0, raw1_wr = 0, cmp0_wr = 0, cmp1_wr = 0;
    integer addr_err = 0;
    integer ovl_err = 0;
    integer raw_rd_lo = 0, raw_rd_hi = 0, cmp_rd_lo = 0, cmp_rd_hi = 0;

    always @(posedge clk) begin
        if (rst_n) begin
            if (raw_awvalid && raw_awready) begin
                if (raw_awaddr < RAW_BASE || raw_awaddr > RAW_BASE + 2*RAW_WORDS - 1) begin
                    addr_err = addr_err + 1;
                    if (addr_err < 5) $display("B10_LAYOUT_ADDR_ERR raw_awaddr=%0d", raw_awaddr);
                end
                if (raw_awaddr < RAW_BASE + RAW_WORDS) raw0_wr = raw0_wr + 1;
                else                                    raw1_wr = raw1_wr + 1;
            end
            if (cmp_awvalid && cmp_awready) begin
                if (cmp_awaddr < CMP_BASE || cmp_awaddr > CMP_BASE + 2*CMP_WORDS - 1) begin
                    addr_err = addr_err + 1;
                    if (addr_err < 5) $display("B10_LAYOUT_ADDR_ERR cmp_awaddr=%0d", cmp_awaddr);
                end
                if ((cmp_awaddr >= RAW_BASE) && (cmp_awaddr <= RAW_BASE + 2*RAW_WORDS - 1)) begin
                    if (ovl_err < 5) $display("B10_LAYOUT_OVL cmp_awaddr=%0d inside RAW range", cmp_awaddr);
                    ovl_err = ovl_err + 1;
                end
                if (cmp_awaddr < CMP_BASE + CMP_WORDS) cmp0_wr = cmp0_wr + 1;
                else                                   cmp1_wr = cmp1_wr + 1;
            end
            if (raw_arvalid && raw_arready) begin
                if (raw_araddr < RAW_BASE || raw_araddr > RAW_BASE + 2*RAW_WORDS - 1) addr_err = addr_err + 1;
            end
            if (cmp_arvalid && cmp_arready) begin
                if (cmp_araddr < CMP_BASE || cmp_araddr > CMP_BASE + 2*CMP_WORDS - 1) addr_err = addr_err + 1;
            end
        end
    end

    // --------------------------------------------------------------- writers
    task raw_write(input integer slot);
        integer g;
        reg [39:0] gd;
        begin
            @(negedge clk); raw_begin = 1; raw_bid = slot;
            @(negedge clk); raw_begin = 0;
            for (g = 0; g < RAW_WORDS*4; g = g + 1) begin
                gd = group_pat(slot, g);
                raw_pix  = gd;
                raw_keep = 4'hF;
                raw_last = (g == (RAW_WORDS*4 - 1));
                raw_valid = 1'b1;
                @(posedge clk);
                while (!raw_wr_ready) @(posedge clk);
                @(negedge clk);
            end
            raw_valid = 0; raw_last = 0;
        end
    endtask

    task cmp_write(input integer slot);
        integer i;
        begin
            @(negedge clk); cmp_begin = 1; cmp_bid = 32'd1000 + slot;
            @(negedge clk); cmp_begin = 0;
            for (i = 0; i < CMP_WORDS; i = i + 1) begin
                cmp_wdat = word_pat(slot, i);
                cmp_keep = 4'hF;
                cmp_last = (i == CMP_WORDS - 1);
                cmp_valid = 1'b1;
                @(posedge clk);
                while (!cmp_wr_ready) @(posedge clk);
                @(negedge clk);
            end
            cmp_valid = 0; cmp_last = 0;
        end
    endtask

    // ---------------------------------------------------------------- readers
    integer raw_rd_slot = 0, raw_words_seen = 0, raw_data_err = 0;
    integer cmp_rd_slot = 0, cmp_words_seen = 0, cmp_data_err = 0;
    localparam integer CMP_BYTES = CMP_WORDS * 4;
    localparam integer CMP_RD_WORDS = (CMP_BYTES + 31) / 32;

    always @(posedge clk) begin
        if (rst_n && raw_rd_valid) begin
            if (raw_rd_data[159:0] !== {group_pat(raw_rd_slot, raw_words_seen*4+3),
                                       group_pat(raw_rd_slot, raw_words_seen*4+2),
                                       group_pat(raw_rd_slot, raw_words_seen*4+1),
                                       group_pat(raw_rd_slot, raw_words_seen*4+0)} ||
                raw_rd_data[255:160] !== 96'd0) begin
                if (raw_data_err < 5)
                    $display("B10_LAYOUT_DATA_ERR raw slot=%0d word=%0d got=%h",
                             raw_rd_slot, raw_words_seen, raw_rd_data[159:0]);
                raw_data_err = raw_data_err + 1;
            end
            raw_words_seen = raw_words_seen + 1;
        end
        if (rst_n && cmp_rd_valid) begin
            for (integer k = 0; k < 8; k = k + 1) begin
                if ((k*4) < (CMP_BYTES - cmp_words_seen*32)) begin
                    if (cmp_rd_data[k*32 +: 32] !== word_pat(cmp_rd_slot, cmp_words_seen*8 + k)) begin
                        if (cmp_data_err < 5)
                            $display("B10_LAYOUT_DATA_ERR cmp slot=%0d word=%0d lane=%0d",
                                     cmp_rd_slot, cmp_words_seen, k);
                        cmp_data_err = cmp_data_err + 1;
                    end
                end
            end
            cmp_words_seen = cmp_words_seen + 1;
        end
    end

    task raw_read(input integer slot);
        begin
            raw_rd_slot = slot; raw_words_seen = 0;
            wait (raw_rd_open_ready);
            @(negedge clk); raw_rd_open = 1;
            @(negedge clk); raw_rd_open = 0;
            wait (raw_words_seen == RAW_WORDS);
            @(negedge clk); raw_rd_close = 1;
            @(negedge clk); raw_rd_close = 0;
        end
    endtask

    task cmp_read(input integer slot);
        begin
            cmp_rd_slot = slot; cmp_words_seen = 0;
            wait (cmp_rd_open_ready);
            @(negedge clk); cmp_rd_open = 1;
            @(negedge clk); cmp_rd_open = 0;
            wait (cmp_words_seen == CMP_RD_WORDS);
            @(negedge clk); cmp_rd_close = 1;
            @(negedge clk); cmp_rd_close = 0;
        end
    endtask

    // ----------------------------------------------------------------- control
    integer pass;
    initial begin
        repeat (5) @(negedge clk);
        rst_n = 1;
        repeat (5) @(negedge clk);
        fork
            begin raw_write(0); raw_write(1); end
            begin cmp_write(0); cmp_write(1); end
        join
        repeat (20) @(negedge clk);
        $display("B10_LAYOUT_WR_DONE raw0=%0d raw1=%0d cmp0=%0d cmp1=%0d addr_err=%0d ovl=%0d",
                 raw0_wr, raw1_wr, cmp0_wr, cmp1_wr, addr_err, ovl_err);
        fork
            begin raw_read(0); raw_read(1); end
            begin cmp_read(0); cmp_read(1); end
        join
        repeat (20) @(negedge clk);
        pass = (raw0_wr == RAW_WORDS) && (raw1_wr == RAW_WORDS) &&
               (cmp0_wr == CMP_RD_WORDS) && (cmp1_wr == CMP_RD_WORDS) &&
               (addr_err == 0) && (raw_data_err == 0) && (cmp_data_err == 0);
        $display("B10_LAYOUT_DONE raw0=%0d raw1=%0d cmp0=%0d cmp1=%0d rd_raw=%0d rd_cmp=%0d addr_err=%0d ovl=%0d raw_data_err=%0d cmp_data_err=%0d",
                 raw0_wr, raw1_wr, cmp0_wr, cmp1_wr, raw_words_seen, cmp_words_seen,
                 addr_err, ovl_err, raw_data_err, cmp_data_err);
        if (EXPECT_FAIL)
            $display("B10_LAYOUT_NEG_CONFIRMED old_layout_detected=%0d",
                     (addr_err != 0) || (ovl_err != 0) ||
                     (raw_data_err != 0) || (cmp_data_err != 0));
        $display("B10_LAYOUT_RESULT pass=%0d", pass);
        $finish;
    end

    initial begin
        #60000000;
        $display("B10_LAYOUT_TIMEOUT raw_words=%0d cmp_words=%0d raw0=%0d raw1=%0d",
                 raw_words_seen, cmp_words_seen, raw0_wr, raw1_wr);
        $display("B10_LAYOUT_RESULT pass=0");
        $finish;
    end
endmodule
