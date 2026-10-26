///////////////////////////////////////////////////////////////////////////////
//  tb_t07_src_release_probe_r2.v — T07 round2 system-dimension directed probe
//
//  复核 change-report §7.2 的接口变更：pusher 现在有 4 根 release 输出
//  （rel_tgl0/1 = A 路块 0/1；rel_tgl2/3 = B 路块 0/1）与 BASE0B/BASE1B 参数。
//  DUT 参数与顶层一致：BASE0/BASE1 = A 路 0x0010_0000/0x0090_0000，
//  BASE0B/BASE1B = B 路 0x0110_0000/0x0190_0000。
//
//  判据（与 r0 报告 F1 对应，按 §7.2 期望）：
//    · A 路对照：pass(未 ARM 发布) +1 on A0，claim→ACK 后再 +1 on A0（合计 2），
//      B 对全程 0；
//    · B 路：pass +1 on B0、claim 期间无提前 release、匹配 ACK 后 +1 on B0（合计 2），
//      A 对全程 0；
//    · 两例 claim 均真实完成（64 笔 MWr + HELD + err=0），证明"无 release"不再出现。
//
//  本 TB 为测试侧独立实现；只读生产 RTL；不修改任何冻结输入。
///////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps

module tb_t07_src_release_probe_r2;

    localparam integer W = 64;
    localparam integer H = 128;
    localparam integer FRAME_BYTES = W * H;         // 8192
    localparam integer NTLP = FRAME_BYTES / 128;    // 64
    localparam integer BB   = 128;
    localparam integer BEAT_BYTES = 32;

    localparam [31:0] BASE0  = 32'h0010_0000;   // A 路块 0（顶层）
    localparam [31:0] BASE1  = 32'h0090_0000;   // A 路块 1（顶层）
    localparam [31:0] BASE0B = 32'h0110_0000;   // B 路块 0（顶层）
    localparam [31:0] BASE1B = 32'h0190_0000;   // B 路块 1（顶层）

    localparam [63:0] DST = 64'h0000_0002_0000_0000;
    localparam [63:0] DB  = 64'h0000_0003_0000_0100;
    localparam [31:0] CAP = 32'h1000_0000;

    reg clk_fb = 0, clk_ddr = 0, rst_fb = 1, rst_ddr = 1;
    always #8 clk_fb  = ~clk_fb;
    always #5 clk_ddr = ~clk_ddr;

    reg         push_en = 0, src_sel = 0, cam_sel = 0;
    reg  [31:0] dst_lo = 0, dst_hi = 0, db_lo = 0, db_hi = 0;
    reg  [31:0] frame_bytes_r = FRAME_BYTES;
    reg  [31:0] ddr_seq_r = 0, ddr_base_r = BASE0, ddr_status_r = 0;
    reg  [31:0] fb_frame_cnt = 0, fb_rd_data = 0;
    wire [31:0] fb_rd_addr;
    wire        fb_req, fb_grant, fb_src_act, fb_hold;
    reg         arm_p = 0, ack_p = 0, cancel_p = 0;
    reg  [31:0] cap_r = 0, sess_r = 0, ack_seq_r = 0, ack_sess_r = 0;
    reg         cfg_rej_p = 0, link_up = 1;
    reg  [2:0]  mps_code = 0;
    wire [31:0] tx_status;
    wire        tx_block_cfg, rel_tgl0, rel_tgl1, rel_tgl2, rel_tgl3, tx_src_lock;
    wire        utx_req, utx_sop, utx_eop;
    wire [255:0] utx_data;
    wire [7:0]  utx_valid;
    reg         utx_sel = 0, tl_tx_wait = 0;
    wire [31:0] st_done, st_status, st_tlp_cnt;
    wire [7:0]  st_err;
    wire [3:0]  m_axi_arid, m_axi_rid;
    wire [28:0] m_axi_araddr;
    wire [7:0]  m_axi_arlen;
    wire [2:0]  m_axi_arsize;
    wire [1:0]  m_axi_arburst;
    wire        m_axi_arvalid, m_axi_arready, m_axi_rlast, m_axi_rvalid, m_axi_rready;
    wire [255:0] m_axi_rdata;
    wire [1:0]  m_axi_rresp;

    ddr_frame_pusher #(
        .W(W), .H(H), .PAY_DW(32), .FIFO_AW(7), .BURST_BEATS(BB),
        .WAIT_LIMIT(16'hFFFF),
        .BASE0(BASE0), .BASE1(BASE1),
        .BASE0B(BASE0B), .BASE1B(BASE1B),
        .MAX_FRAME_BYTES(3840*2160)
    ) dut (
        .clk_fb(clk_fb), .rst_fb(rst_fb),
        .push_en(push_en), .src_sel(src_sel),
        .fb_frame_cnt(fb_frame_cnt),
        .fb_rd_addr(fb_rd_addr), .fb_rd_data(fb_rd_data),
        .fb_req(fb_req), .fb_grant(fb_grant), .src_act(fb_src_act), .fb_hold(fb_hold),
        .dst_lo(dst_lo), .dst_hi(dst_hi), .db_lo(db_lo), .db_hi(db_hi),
        .st_done(st_done), .st_status(st_status), .st_err(st_err), .st_tlp_cnt(st_tlp_cnt),
        .frame_bytes(frame_bytes_r),
        .ddr_seq(ddr_seq_r), .ddr_base(ddr_base_r), .ddr_status(ddr_status_r),
        .utx_sel(utx_sel), .tl_tx_wait(tl_tx_wait),
        .utx_req(utx_req), .utx_data(utx_data), .utx_sop(utx_sop),
        .utx_eop(utx_eop), .utx_valid(utx_valid),
        .arm_pulse(arm_p), .ack_pulse(ack_p), .cancel_pulse(cancel_p),
        .cap_bytes(cap_r), .session_id(sess_r),
        .ack_seq_w(ack_seq_r), .ack_session_w(ack_sess_r),
        .cfg_reject(cfg_rej_p), .link_up(link_up), .mps_code(mps_code),
        .ddr_cap_bytes(CAP), .cam_sel_live(cam_sel),
        .tx_status(tx_status), .tx_block_cfg(tx_block_cfg),
        .rel_tgl0(rel_tgl0), .rel_tgl1(rel_tgl1),
        .rel_tgl2(rel_tgl2), .rel_tgl3(rel_tgl3),
        .tx_src_lock(tx_src_lock),
        .clk_ddr(clk_ddr), .rst_ddr(rst_ddr),
        .m_axi_arid(m_axi_arid), .m_axi_araddr(m_axi_araddr), .m_axi_arlen(m_axi_arlen),
        .m_axi_arsize(m_axi_arsize), .m_axi_arburst(m_axi_arburst),
        .m_axi_arvalid(m_axi_arvalid), .m_axi_arready(m_axi_arready),
        .m_axi_rid(m_axi_rid), .m_axi_rdata(m_axi_rdata), .m_axi_rresp(m_axi_rresp),
        .m_axi_rlast(m_axi_rlast), .m_axi_rvalid(m_axi_rvalid), .m_axi_rready(m_axi_rready)
    );

    assign fb_grant = fb_req;

    // ------------------------- 假 AXI4 读从机 -------------------------
    reg        sl_busy = 0;
    reg [28:0] sl_addr = 0;
    integer    sl_beat = 0;
    reg        sl_rvalid = 0, sl_rlast = 0;
    reg [255:0] sl_rdata = 0;
    assign m_axi_rdata  = sl_rdata;
    assign m_axi_rlast  = sl_rlast;
    assign m_axi_rvalid = sl_rvalid;
    assign m_axi_rid    = 4'd0;
    assign m_axi_rresp  = 2'b00;
    assign m_axi_arready = !sl_busy;

    always @(posedge clk_ddr) begin
        if (rst_ddr) begin
            sl_busy <= 0; sl_rvalid <= 0; sl_rlast <= 0; sl_beat <= 0;
        end else if (!sl_busy) begin
            if (m_axi_arvalid && m_axi_arready) begin
                sl_busy <= 1; sl_addr <= m_axi_araddr; sl_beat <= 0;
                sl_rvalid <= 0; sl_rlast <= 0;
            end
        end else if (sl_rvalid && m_axi_rready) begin
            if (sl_rlast) begin
                sl_busy <= 0; sl_rvalid <= 0; sl_rlast <= 0;
            end else begin
                sl_beat  <= sl_beat + 1;
                sl_rlast <= (sl_beat + 1 == BB-1);
                sl_rdata <= {sl_addr, sl_beat[2:0], 224'd0};
            end
        end else if (!sl_rvalid) begin
            sl_rvalid <= 1;
            sl_rlast  <= (sl_beat == BB-1);
            sl_rdata  <= {sl_addr, sl_beat[2:0], 224'd0};
        end
    end

    // ------------------------- 假引擎 TL 口（永远收） -------------------------
    always @(posedge clk_fb) begin
        if (rst_fb) begin
            utx_sel <= 0; tl_tx_wait <= 0;
        end else begin
            tl_tx_wait <= 0;
            if (!utx_sel) begin
                if (utx_req) utx_sel <= 1;
            end else if (utx_eop && (|utx_valid)) begin
                utx_sel <= 0;
            end
        end
    end

    // ------------------------- 4 根 release 脉冲监视 -------------------------
    reg r0_d = 0, r1_d = 0, r2_d = 0, r3_d = 0;
    integer rel0_cnt = 0, rel1_cnt = 0, rel2_cnt = 0, rel3_cnt = 0;
    always @(posedge clk_fb) begin
        r0_d <= rel_tgl0; r1_d <= rel_tgl1; r2_d <= rel_tgl2; r3_d <= rel_tgl3;
        if (rel_tgl0 !== r0_d) rel0_cnt = rel0_cnt + 1;
        if (rel_tgl1 !== r1_d) rel1_cnt = rel1_cnt + 1;
        if (rel_tgl2 !== r2_d) rel2_cnt = rel2_cnt + 1;
        if (rel_tgl3 !== r3_d) rel3_cnt = rel3_cnt + 1;
    end

    integer errors = 0;
    integer i;
    task check; input cond; input [255:0] msg;
        begin
            if (!cond) begin
                errors = errors + 1;
                $display("FAIL at %0t", $time);
            end else begin
                $display("ok");
            end
            $display("   check: %0s", msg);
        end
    endtask

    // A 路用例：cam=0, base=BASE0；B 路用例：cam=1, base=BASE0B
    task automatic run_case;
        input        cam;
        input [31:0] base;
        input [255:0] name;
        integer held_wait;
        begin
            rst_fb = 1; rst_ddr = 1;
            repeat (10) @(posedge clk_fb);
            rst_fb = 0; rst_ddr = 0;

            push_en = 0; src_sel = 0; cam_sel = cam;
            ddr_status_r = 32'h1; ddr_seq_r = 32'd10; ddr_base_r = base;
            dst_lo = DST[31:0]; dst_hi = DST[63:32];
            db_lo  = DB[31:0];  db_hi  = DB[63:32];
            frame_bytes_r = FRAME_BYTES;
            cap_r = CAP; sess_r = 32'h5A5A_0001;
            link_up = 1; mps_code = 0;
            rel0_cnt = 0; rel1_cnt = 0; rel2_cnt = 0; rel3_cnt = 0;
            repeat (5) @(posedge clk_fb);

            // 模式开 + 未 ARM 发布一帧：pass-release 必须出现在本相机自己的对
            push_en = 1;
            repeat (5) @(posedge clk_fb);
            ddr_seq_r = 32'd11;
            repeat (50) @(posedge clk_fb);
            check(st_tlp_cnt == 0, {name, " : no TLP before ARM"});
            if (cam == 0)
                check(rel0_cnt == 1 && rel1_cnt == 0 && rel2_cnt == 0 && rel3_cnt == 0,
                      {name, " : pass-release on A0 only"});
            else
                check(rel2_cnt == 1 && rel0_cnt == 0 && rel1_cnt == 0 && rel3_cnt == 0,
                      {name, " : pass-release on B0 only"});

            // ARM
            arm_p = 1; @(posedge clk_fb); arm_p = 0;
            repeat (5) @(posedge clk_fb);
            check(tx_status[0] == 1'b1, {name, " : armed after ARM"});
            check(st_err == 8'd0, {name, " : ARM accepted (err=0)"});

            // 发布新帧 ⇒ claim
            ddr_seq_r = 32'd12;
            held_wait = 0;
            while ((tx_status[2] != 1'b1) && (held_wait < 200000)) begin
                @(posedge clk_fb); held_wait = held_wait + 1;
            end
            check(tx_status[2] == 1'b1, {name, " : frame claimed+completed -> HELD"});
            check(st_tlp_cnt == NTLP, {name, " : TLP count = 64 data MWr"});
            // held 期间不得有本帧的提前 release（计数应与 pass 后一致）
            if (cam == 0)
                check(rel0_cnt == 1 && rel1_cnt == 0 && rel2_cnt == 0 && rel3_cnt == 0,
                      {name, " : no early release during claim/TX/HELD (A)"});
            else
                check(rel2_cnt == 1 && rel0_cnt == 0 && rel1_cnt == 0 && rel3_cnt == 0,
                      {name, " : no early release during claim/TX/HELD (B)"});

            // 匹配 ACK ⇒ 本相机本块恰好 +1，另一路不动
            ack_seq_r   = st_done;
            ack_sess_r  = sess_r;
            ack_p = 1; @(posedge clk_fb); ack_p = 0;
            repeat (30) @(posedge clk_fb);
            check(tx_status[2] == 1'b0, {name, " : released from HELD"});

            if (cam == 0)
                check(rel0_cnt == 2 && rel1_cnt == 0 && rel2_cnt == 0 && rel3_cnt == 0,
                      {name, " : A total=2 (pass+ACK), B pair untouched"});
            else
                check(rel2_cnt == 2 && rel0_cnt == 0 && rel1_cnt == 0 && rel3_cnt == 0,
                      {name, " : B total=2 (pass+ACK), A pair untouched"});

            $display("CASE %0d : rel0=%0d rel1=%0d rel2=%0d rel3=%0d held_wait=%0d st_err=%0d done=%0d",
                     cam, rel0_cnt, rel1_cnt, rel2_cnt, rel3_cnt, held_wait, st_err, st_done);
        end
    endtask

    initial begin
        $display("=== T07 r2 system probe: camera-aware source-block release ===");
        run_case(0, BASE0,  "A-path BASE0=0x00100000");
        run_case(1, BASE0B, "B-path BASE0B=0x01100000");
        if (errors == 0) $display("PROBE_RESULT: ALL PASS");
        else begin
            $display("PROBE_RESULT: %0d CHECK(S) FAILED", errors);
        end
        $display("PROBE_DONE");
        $finish;
    end

endmodule
