`timescale 1ns/1ps
// =============================================================================
// tb_b17_paxi_native.sv -- T10.b17 native PAXI boundary test.
//
// CASE=main (default): 16 distinct 256-bit words -> internal word indices
//   0..15, stop >= 32 clk_ddr, read back 16/16.  Asserts the model sees native
//   addresses 0,8,...,120, mask=0, no low3/OOB/same-cycle request, and the
//   bridge's last_issued_ar_addr == 120.
// CASE=mask : direct model, full-word write then all-ones-mask overwrite must
//   leave the first value intact.
// CASE=addr : direct model, low3!=0 and word>424313 writes/reads must be
//   counted, must not alias, and must return poison without hanging.
// CASE=conc : ALLOW_CONCURRENT=1 bridge + permissive model must show same-cycle
//   AW/AR (and W/AR) requests/handshakes.  Comparison only.
// CASE=b15  : frozen b15 bridge against this model must fail (address + mask).
// =============================================================================
module tb_b17_paxi_native;
    reg clk_a1  = 1'b0;
    reg clk_ddr = 1'b0;
    reg rst_n   = 1'b0;
    initial begin #1.7000; forever #2.6665 clk_a1  = ~clk_a1;  end
    initial begin #0.4000; forever #2.5000 clk_ddr = ~clk_ddr; end

    // ------------------------------------------------------------- main bridge
    reg  [31:0]  m_awaddr = 32'd0;
    reg          m_awvalid = 1'b0;
    wire         m_awready;
    reg  [255:0] m_wdata = 256'd0;
    reg          m_wvalid = 1'b0;
    wire         m_wready;
    reg  [31:0]  m_araddr = 32'd0;
    reg          m_arvalid = 1'b0;
    wire         m_arready;
    wire [255:0] m_rdata;
    wire         m_rvalid;
    wire [511:0] m_dbg;

    wire [26:0]  p_awaddr, p_araddr;
    wire         p_awvalid, p_awready, p_wvalid, p_wlast, p_wready;
    wire [255:0] p_wdata;
    wire [31:0]  p_wstrb;
    wire         p_arvalid, p_arready, p_rlast, p_rvalid;
    wire         p_rready;
    wire [255:0] p_rdata;

    p2_ddr_bridge #(.ALLOW_CONCURRENT(0)) u_main_bridge (
        .clk_a1 (clk_a1), .rst_n (rst_n),
        .s_awaddr (m_awaddr), .s_awvalid (m_awvalid), .s_awready (m_awready),
        .s_wdata (m_wdata), .s_wvalid (m_wvalid), .s_wready (m_wready),
        .s_araddr (m_araddr), .s_arvalid (m_arvalid), .s_arready (m_arready),
        .s_rdata (m_rdata), .s_rvalid (m_rvalid), .s_rready (1'b1),
        .rd_abort (1'b0),
        .clk_ddr (clk_ddr), .ddr_rdy (1'b1),
        .paxi_awaddr (p_awaddr), .paxi_awvalid (p_awvalid), .paxi_awready (p_awready),
        .paxi_wdata (p_wdata), .paxi_wstrb (p_wstrb), .paxi_wvalid (p_wvalid),
        .paxi_wlast (p_wlast), .paxi_wready (p_wready),
        .paxi_araddr (p_araddr), .paxi_arvalid (p_arvalid), .paxi_arready (p_arready),
        .paxi_rdata (p_rdata), .paxi_rlast (p_rlast), .paxi_rvalid (p_rvalid),
        .paxi_rready (p_rready),
        .dbg_a1 (m_dbg)
    );

    wire [31:0] n_ar, n_aw, n_w, n_r, n_bad_low3, n_oob, n_mask, n_sreq, n_shs, n_commit;

    p2_paxi_model_b17 #(.WORDS(524288), .AR_GAP(3), .R_GAP(3)) u_model (
        .clk (clk_ddr), .rst_n (rst_n), .rdy (1'b1),
        .awaddr (p_awaddr), .awvalid (p_awvalid), .awready (p_awready),
        .wdata (p_wdata), .wstrb (p_wstrb), .wvalid (p_wvalid), .wlast (p_wlast),
        .wready (p_wready),
        .araddr (p_araddr), .arvalid (p_arvalid), .arready (p_arready),
        .rdata (p_rdata), .rlast (p_rlast), .rvalid (p_rvalid), .rready (p_rready),
        .n_ar_hs (n_ar), .n_aw_hs (n_aw), .n_whs (n_w), .n_r_hs (n_r),
        .n_bad_low3 (n_bad_low3), .n_oob (n_oob), .n_mask_nonzero (n_mask),
        .n_same_req (n_sreq), .n_same_hs (n_shs), .n_write_commit (n_commit)
    );

    // ------------------------------------------------------- direct model test
    reg  [26:0]  d_awaddr = 27'd0;
    reg          d_awvalid = 1'b0;
    wire         d_awready;
    reg  [255:0] d_wdata = 256'd0;
    reg  [31:0]  d_wstrb = 32'd0;
    reg          d_wvalid = 1'b0;
    wire         d_wready;
    reg  [26:0]  d_araddr = 27'd0;
    reg          d_arvalid = 1'b0;
    wire         d_arready;
    wire [255:0] d_rdata;
    wire         d_rlast, d_rvalid;
    wire         d_rready = 1'b1;
    wire [31:0]  dn_ar, dn_aw, dn_w, dn_r, dn_bad_low3, dn_oob, dn_mask,
                 dn_sreq, dn_shs, dn_commit;

    p2_paxi_model_b17 #(.WORDS(524288), .AR_GAP(1), .R_GAP(1)) u_dir_model (
        .clk (clk_ddr), .rst_n (rst_n), .rdy (1'b1),
        .awaddr (d_awaddr), .awvalid (d_awvalid), .awready (d_awready),
        .wdata (d_wdata), .wstrb (d_wstrb), .wvalid (d_wvalid), .wlast (1'b1),
        .wready (d_wready),
        .araddr (d_araddr), .arvalid (d_arvalid), .arready (d_arready),
        .rdata (d_rdata), .rlast (d_rlast), .rvalid (d_rvalid), .rready (d_rready),
        .n_ar_hs (dn_ar), .n_aw_hs (dn_aw), .n_whs (dn_w), .n_r_hs (dn_r),
        .n_bad_low3 (dn_bad_low3), .n_oob (dn_oob), .n_mask_nonzero (dn_mask),
        .n_same_req (dn_sreq), .n_same_hs (dn_shs), .n_write_commit (dn_commit)
    );

    // ------------------------------------------------------------ concurrency
    reg  [31:0]  c_awaddr = 32'd0;
    reg          c_awvalid = 1'b0;
    wire         c_awready;
    reg  [255:0] c_wdata = 256'd0;
    reg          c_wvalid = 1'b0;
    wire         c_wready;
    reg  [31:0]  c_araddr = 32'd0;
    reg          c_arvalid = 1'b0;
    wire         c_arready;
    wire [255:0] c_rdata;
    wire         c_rvalid;
    wire [511:0] c_dbg;

    wire [26:0]  q_awaddr, q_araddr;
    wire         q_awvalid, q_awready, q_wvalid, q_wlast, q_wready;
    wire [255:0] q_wdata;
    wire [31:0]  q_wstrb;
    wire         q_arvalid, q_arready, q_rlast, q_rvalid;
    wire         q_rready;
    wire [255:0] q_rdata;
    wire [31:0]  cn_ar, cn_aw, cn_w, cn_r, cn_bad_low3, cn_oob, cn_mask,
                 cn_sreq, cn_shs, cn_commit;

    p2_ddr_bridge #(.ALLOW_CONCURRENT(1)) u_conc_bridge (
        .clk_a1 (clk_a1), .rst_n (rst_n),
        .s_awaddr (c_awaddr), .s_awvalid (c_awvalid), .s_awready (c_awready),
        .s_wdata (c_wdata), .s_wvalid (c_wvalid), .s_wready (c_wready),
        .s_araddr (c_araddr), .s_arvalid (c_arvalid), .s_arready (c_arready),
        .s_rdata (c_rdata), .s_rvalid (c_rvalid), .s_rready (1'b1),
        .rd_abort (1'b0),
        .clk_ddr (clk_ddr), .ddr_rdy (1'b1),
        .paxi_awaddr (q_awaddr), .paxi_awvalid (q_awvalid), .paxi_awready (q_awready),
        .paxi_wdata (q_wdata), .paxi_wstrb (q_wstrb), .paxi_wvalid (q_wvalid),
        .paxi_wlast (q_wlast), .paxi_wready (q_wready),
        .paxi_araddr (q_araddr), .paxi_arvalid (q_arvalid), .paxi_arready (q_arready),
        .paxi_rdata (q_rdata), .paxi_rlast (q_rlast), .paxi_rvalid (q_rvalid),
        .paxi_rready (q_rready),
        .dbg_a1 (c_dbg)
    );

    p2_paxi_model_b17 #(.WORDS(524288), .AR_GAP(4), .R_GAP(3),
                        .ALLOW_BOTH_READY(1)) u_conc_model (
        .clk (clk_ddr), .rst_n (rst_n), .rdy (1'b1),
        .awaddr (q_awaddr), .awvalid (q_awvalid), .awready (q_awready),
        .wdata (q_wdata), .wstrb (q_wstrb), .wvalid (q_wvalid), .wlast (q_wlast),
        .wready (q_wready),
        .araddr (q_araddr), .arvalid (q_arvalid), .arready (q_arready),
        .rdata (q_rdata), .rlast (q_rlast), .rvalid (q_rvalid), .rready (q_rready),
        .n_ar_hs (cn_ar), .n_aw_hs (cn_aw), .n_whs (cn_w), .n_r_hs (cn_r),
        .n_bad_low3 (cn_bad_low3), .n_oob (cn_oob), .n_mask_nonzero (cn_mask),
        .n_same_req (cn_sreq), .n_same_hs (cn_shs), .n_write_commit (cn_commit)
    );

    // ------------------------------------------------------------ b15 negative
    reg  [31:0]  b_awaddr = 32'd0;
    reg          b_awvalid = 1'b0;
    wire         b_awready;
    reg  [255:0] b_wdata = 256'd0;
    reg          b_wvalid = 1'b0;
    wire         b_wready;
    reg  [31:0]  b_araddr = 32'd0;
    reg          b_arvalid = 1'b0;
    wire         b_arready;
    wire [255:0] b_rdata;
    wire         b_rvalid;
    wire [26:0]  r_awaddr, r_araddr;
    wire         r_awvalid, r_awready, r_wvalid, r_wlast, r_wready;
    wire [255:0] r_wdata;
    wire [31:0]  r_wstrb;
    wire         r_arvalid, r_arready, r_rlast, r_rvalid;
    wire         r_rready;
    wire [255:0] r_rdata;
    wire [255:0] b_dbg;
    wire [31:0]  bn_ar, bn_aw, bn_w, bn_r, bn_bad_low3, bn_oob, bn_mask,
                 bn_sreq, bn_shs, bn_commit;

    p2_ddr_bridge_b15 u_b15_bridge (
        .clk_a1 (clk_a1), .rst_n (rst_n),
        .s_awaddr (b_awaddr), .s_awvalid (b_awvalid), .s_awready (b_awready),
        .s_wdata (b_wdata), .s_wvalid (b_wvalid), .s_wready (b_wready),
        .s_araddr (b_araddr), .s_arvalid (b_arvalid), .s_arready (b_arready),
        .s_rdata (b_rdata), .s_rvalid (b_rvalid), .s_rready (1'b1),
        .rd_abort (1'b0),
        .clk_ddr (clk_ddr), .ddr_rdy (1'b1),
        .paxi_awaddr (r_awaddr), .paxi_awvalid (r_awvalid), .paxi_awready (r_awready),
        .paxi_wdata (r_wdata), .paxi_wstrb (r_wstrb), .paxi_wvalid (r_wvalid),
        .paxi_wlast (r_wlast), .paxi_wready (r_wready),
        .paxi_araddr (r_araddr), .paxi_arvalid (r_arvalid), .paxi_arready (r_arready),
        .paxi_rdata (r_rdata), .paxi_rlast (r_rlast), .paxi_rvalid (r_rvalid),
        .paxi_rready (r_rready),
        .dbg_a1 (b_dbg)
    );

    p2_paxi_model_b17 #(.WORDS(524288), .AR_GAP(3), .R_GAP(3)) u_b15_model (
        .clk (clk_ddr), .rst_n (rst_n), .rdy (1'b1),
        .awaddr (r_awaddr), .awvalid (r_awvalid), .awready (r_awready),
        .wdata (r_wdata), .wstrb (r_wstrb), .wvalid (r_wvalid), .wlast (r_wlast),
        .wready (r_wready),
        .araddr (r_araddr), .arvalid (r_arvalid), .arready (r_arready),
        .rdata (r_rdata), .rlast (r_rlast), .rvalid (r_rvalid), .rready (r_rready),
        .n_ar_hs (bn_ar), .n_aw_hs (bn_aw), .n_whs (bn_w), .n_r_hs (bn_r),
        .n_bad_low3 (bn_bad_low3), .n_oob (bn_oob), .n_mask_nonzero (bn_mask),
        .n_same_req (bn_sreq), .n_same_hs (bn_shs), .n_write_commit (bn_commit)
    );

    // ----------------------------------------------------------- observations
    reg [26:0] aw_seen_addr [0:15];
    reg [26:0] ar_seen_addr [0:15];
    integer    aw_seen_n = 0, ar_seen_n = 0, wstrb_bad = 0;
    always @(posedge clk_ddr) begin
        if (rst_n && p_awvalid && p_awready) begin
            if (aw_seen_n < 16) aw_seen_addr[aw_seen_n] = p_awaddr;
            aw_seen_n = aw_seen_n + 1;
        end
        if (rst_n && p_arvalid && p_arready) begin
            if (ar_seen_n < 16) ar_seen_addr[ar_seen_n] = p_araddr;
            ar_seen_n = ar_seen_n + 1;
        end
        if (rst_n && p_wvalid && p_wready && (p_wstrb !== 32'h0)) wstrb_bad = wstrb_bad + 1;
    end

    integer nerr = 0;
    reg [255:0] pat [0:15];
    reg [255:0] rdv;
    integer i, j;

    initial begin
        #2000000;
        $display("B17_TIMEOUT nerr=%0d", nerr);
        $fatal(1, "tb_b17_paxi_native watchdog");
    end

    task automatic fail;
        input [255:0] msg;
        begin
            nerr = nerr + 1;
            $display("B17_NATIVE_ERROR %0s", msg);
        end
    endtask

    // ------------------------------------------------------------ main sequence
    task automatic main_write;
        input [31:0]  widx;
        input [255:0] wdat;
        begin
            @(negedge clk_a1);
            m_awaddr = widx; m_wdata = wdat; m_awvalid = 1'b1; m_wvalid = 1'b1;
            @(posedge clk_a1);
            while (!(m_awready && m_wready)) @(posedge clk_a1);
            @(negedge clk_a1);
            m_awvalid = 1'b0; m_wvalid = 1'b0;
        end
    endtask

    task automatic main_read;
        input  [31:0]  widx;
        output [255:0] rdat;
        begin
            @(negedge clk_a1);
            m_araddr = widx; m_arvalid = 1'b1;
            @(posedge clk_a1);
            while (!m_arready) @(posedge clk_a1);
            @(negedge clk_a1);
            m_arvalid = 1'b0;
            while (!m_rvalid) @(posedge clk_a1);
            rdat = m_rdata;
            @(negedge clk_a1);
        end
    endtask

    // -------------------------------------------------------- direct model I/O
    task automatic dir_write;
        input [26:0]  addr;
        input [255:0] dat;
        input [31:0]  strb;
        begin
            @(negedge clk_ddr);
            d_awaddr = addr; d_wdata = dat; d_wstrb = strb;
            d_awvalid = 1'b1; d_wvalid = 1'b1;
            $display("B17_DIR_W_START addr=%0d strb=%h t=%0t", addr, strb, $time);
            @(posedge clk_ddr);
            while (!(d_awready && d_wready)) @(posedge clk_ddr);
            $display("B17_DIR_W_HS addr=%0d awr=%b wr=%b commit=%0d t=%0t",
                     addr, d_awready, d_wready, dn_commit, $time);
            @(negedge clk_ddr);
            d_awvalid = 1'b0; d_wvalid = 1'b0;
            repeat (3) @(negedge clk_ddr);
        end
    endtask

    task automatic dir_read;
        input  [26:0]  addr;
        output [255:0] dat;
        begin
            @(negedge clk_ddr);
            d_araddr = addr; d_arvalid = 1'b1;
            $display("B17_DIR_R_START addr=%0d t=%0t", addr, $time);
            @(posedge clk_ddr);
            while (!d_arready) @(posedge clk_ddr);
            $display("B17_DIR_R_HS addr=%0d ar_hs=%0d t=%0t", addr, dn_ar, $time);
            @(negedge clk_ddr);
            d_arvalid = 1'b0;
            while (!d_rvalid) @(posedge clk_ddr);
            $display("B17_DIR_R_DATA addr=%0d r_hs=%0d t=%0t", addr, dn_r, $time);
            dat = d_rdata;
            @(negedge clk_ddr);
        end
    endtask

    initial begin : main
        integer k, aw_ok, ar_ok;
        reg [255:0] d1, d2;
        string case_name;
        if (!$value$plusargs("CASE=%s", case_name)) case_name = "main";

        repeat (30) @(negedge clk_a1);
        rst_n = 1'b1;
        repeat (20) @(negedge clk_a1);

        if (case_name == "main") begin
            for (i = 0; i < 16; i = i + 1) begin
                for (j = 0; j < 32; j = j + 1)
                    pat[i][j*8 +: 8] = (i * 16 + j) & 8'hff;
                main_write(i[31:0], pat[i]);
            end
            // stop >= 32 clk_ddr cycles and wait until every write committed
            k = 0;
            while ((n_commit < 16) && (k < 20000)) begin
                @(negedge clk_ddr);
                k = k + 1;
            end
            repeat (40) @(negedge clk_ddr);

            for (i = 0; i < 16; i = i + 1) begin
                main_read(i[31:0], rdv);
                if (rdv !== pat[i]) begin
                    $display("B17_NATIVE_MISMATCH word=%0d exp=%h got=%h", i, pat[i], rdv);
                    fail("16-word readback mismatch");
                end
            end

            aw_ok = (n_aw == 16) && (n_w == 16) && (n_commit == 16);
            ar_ok = (n_ar == 16) && (n_r == 16);
            if (!aw_ok) fail("AW/W/commit count mismatch");
            if (!ar_ok) fail("AR/R count mismatch");
            if (n_bad_low3 != 0) fail("n_bad_low3 nonzero");
            if (n_oob != 0) fail("n_oob nonzero");
            if (n_mask != 0) fail("n_mask_nonzero nonzero");
            if (n_sreq != 0) fail("n_same_req nonzero");
            if (n_shs != 0) fail("n_same_hs nonzero");
            if (wstrb_bad != 0) fail("paxi_wstrb nonzero on a write handshake");
            if (aw_seen_n < 16 || ar_seen_n < 16) fail("address monitor missed a handshake");
            for (i = 0; i < 16; i = i + 1) begin
                if (aw_seen_addr[i] !== (i * 8)) begin
                    $display("B17_NATIVE_AW_ADDR i=%0d got=%0d exp=%0d", i, aw_seen_addr[i], i*8);
                    fail("AW native address sequence");
                end
                if (ar_seen_addr[i] !== (i * 8)) begin
                    $display("B17_NATIVE_AR_ADDR i=%0d got=%0d exp=%0d", i, ar_seen_addr[i], i*8);
                    fail("AR native address sequence");
                end
            end
            if (u_main_bridge.last_issued_ar_addr !== 27'd120) fail("last_issued_ar_addr != 120");
            if (u_main_bridge.last_issued_ar_addr[2:0] !== 3'b000) fail("last_issued_ar low3 != 0");
            if (m_dbg[511:480] !== 32'd0) begin
                $display("B17_NATIVE_DIAG_FLAGS %h", m_dbg[511:480]);
                fail("diag_flags nonzero on a clean run");
            end
            $display("B17_NATIVE_RESULT pass=%0d words=16 aw_hs=%0d w_hs=%0d commit=%0d ar_hs=%0d r_hs=%0d bad_low3=%0d oob=%0d mask=%0d same_req=%0d same_hs=%0d last_ar=%0d low3=%0d wstrb_bad=%0d",
                     (nerr == 0), n_aw, n_w, n_commit, n_ar, n_r, n_bad_low3, n_oob,
                     n_mask, n_sreq, n_shs, u_main_bridge.last_issued_ar_addr,
                     u_main_bridge.last_issued_ar_addr[2:0], wstrb_bad);
        end

        if (case_name == "mask") begin
            d1 = 256'h1111_2222_3333_4444_5555_6666_7777_8888_9999_AAAA_BBBB_CCCC_DDDD_EEEE_FFFF_0000;
            d2 = 256'hDEAD_DEAD_DEAD_DEAD_DEAD_DEAD_DEAD_DEAD_DEAD_DEAD_DEAD_DEAD_DEAD_DEAD_DEAD_DEAD;
            dir_write(27'd2048, d1, 32'h0000_0000);
            dir_write(27'd2048, d2, 32'hFFFF_FFFF);
            dir_read (27'd2048, rdv);
            if (rdv !== d1) begin
                $display("B17_MASK_READBACK exp=%h got=%h", d1, rdv);
                fail("all-ones mask modified memory");
            end
            if (dn_mask != 1) fail("n_mask_nonzero != 1");
            if (dn_commit != 2) fail("n_write_commit != 2");
            $display("B17_MASK_RESULT pass=%0d mask_nonzero=%0d commit=%0d value_kept=%0d",
                     (nerr == 0), dn_mask, dn_commit, (rdv === d1));
        end

        if (case_name == "addr") begin
            d1 = 256'h0123_4567_89AB_CDEF_0123_4567_89AB_CDEF_0123_4567_89AB_CDEF_0123_4567_89AB_CDEF;
            dir_write(27'd4, d1, 32'h0000_0000);             // bad low3
            dir_read (27'd4, rdv);
            if (rdv !== 256'hBAD0_BAD0_BAD0_BAD0_BAD0_BAD0_BAD0_BAD0_BAD0_BAD0_BAD0_BAD0_BAD0_BAD0_BAD0_BAD0) begin
                $display("B17_ADDR_LOW3_RD got=%h r_hs=%0d ar_hs=%0d", rdv, dn_r, dn_ar);
                fail("low3 read did not return poison");
            end
            dir_write(27'd3394512, d1, 32'h0000_0000);       // word 424314 > max
            dir_read (27'd3394512, rdv);
            if (rdv !== 256'hBAD0_BAD0_BAD0_BAD0_BAD0_BAD0_BAD0_BAD0_BAD0_BAD0_BAD0_BAD0_BAD0_BAD0_BAD0_BAD0) begin
                $display("B17_ADDR_OOB_RD got=%h r_hs=%0d ar_hs=%0d", rdv, dn_r, dn_ar);
                fail("OOB read did not return poison");
            end
            if (dn_bad_low3 != 2) fail("n_bad_low3 != 2");
            if (dn_oob != 2) fail("n_oob != 2");
            if (dn_commit != 2) fail("n_write_commit != 2");
            $display("B17_ADDR_RESULT pass=%0d bad_low3=%0d oob=%0d commit=%0d",
                     (nerr == 0), dn_bad_low3, dn_oob, dn_commit);
        end

        if (case_name == "conc") begin
            // Push several writes and reads; the ALLOW_CONCURRENT=1 bridge must
            // present AW/AR (or W/AR) in the same cycle to the permissive model.
            for (i = 0; i < 12; i = i + 1) begin
                for (j = 0; j < 32; j = j + 1) pat[0][j*8 +: 8] = (i + j) & 8'hff;
                @(negedge clk_a1);
                c_awaddr = i[31:0]; c_wdata = pat[0]; c_awvalid = 1'b1; c_wvalid = 1'b1;
                @(posedge clk_a1);
                while (!(c_awready && c_wready)) @(posedge clk_a1);
                @(negedge clk_a1);
                c_awvalid = 1'b0; c_wvalid = 1'b0;
                // Interleave an AR request so the write engine is still busy.
                @(negedge clk_a1);
                c_araddr = i[31:0]; c_arvalid = 1'b1;
                @(posedge clk_a1);
                while (!c_arready) @(posedge clk_a1);
                @(negedge clk_a1);
                c_arvalid = 1'b0;
            end
            k = 0;
            while (((cn_sreq == 0) || (cn_shs == 0) || (cn_ar < 12)) && (k < 50000)) begin
                @(negedge clk_ddr);
                k = k + 1;
            end
            if (cn_sreq == 0) fail("ALLOW_CONCURRENT=1 produced no same-cycle request");
            if (cn_shs == 0)  fail("ALLOW_CONCURRENT=1 produced no same-cycle handshake");
            $display("B17_CONC_RESULT pass=%0d same_req=%0d same_hs=%0d aw=%0d ar=%0d r=%0d",
                     (nerr == 0), cn_sreq, cn_shs, cn_aw, cn_ar, cn_r);
        end

        if (case_name == "b15") begin
            d1 = 256'hAAAA_5555_AAAA_5555_AAAA_5555_AAAA_5555_AAAA_5555_AAAA_5555_AAAA_5555_AAAA_5555;
            @(negedge clk_a1);
            b_awaddr = 32'd0; b_wdata = d1; b_awvalid = 1'b1; b_wvalid = 1'b1;
            @(posedge clk_a1);
            while (!(b_awready && b_wready)) @(posedge clk_a1);
            @(negedge clk_a1);
            b_awvalid = 1'b0; b_wvalid = 1'b0;
            d2 = 256'hBBBB_6666_BBBB_6666_BBBB_6666_BBBB_6666_BBBB_6666_BBBB_6666_BBBB_6666_BBBB_6666;
            @(negedge clk_a1);
            b_awaddr = 32'd1; b_wdata = d2; b_awvalid = 1'b1; b_wvalid = 1'b1;
            @(posedge clk_a1);
            while (!(b_awready && b_wready)) @(posedge clk_a1);
            @(negedge clk_a1);
            b_awvalid = 1'b0; b_wvalid = 1'b0;
            repeat (40) @(negedge clk_ddr);
            @(negedge clk_a1);
            b_araddr = 32'd0; b_arvalid = 1'b1;
            @(posedge clk_a1);
            while (!b_arready) @(posedge clk_a1);
            @(negedge clk_a1);
            b_arvalid = 1'b0;
            while (!b_rvalid) @(posedge clk_a1);
            rdv = b_rdata;
            @(negedge clk_a1);
            if (rdv === d1) fail("b15 bridge unexpectedly read back word 0");
            if (bn_bad_low3 == 0) fail("b15 bridge low3 violation not counted");
            if (bn_mask == 0) fail("b15 bridge all-ones mask not counted");
            $display("B17_B15NEG_RESULT pass=%0d bad_low3=%0d mask=%0d commit=%0d word0_ok=%0d",
                     (nerr == 0), bn_bad_low3, bn_mask, bn_commit, (rdv === d1));
        end

        $display("B17_CASE_DONE case=%0s errors=%0d", case_name, nerr);
        $finish;
    end
endmodule
