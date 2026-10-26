///////////////////////////////////////////////////////////////////////////////
//  tb_t07_src_release_probe.v — T07 system-dimension independent probe
//
//  目的（只做一件事，最小化、可复现）：
//    复核 top（ph1p_pcie_ep_top.v）里 ddr_frame_pusher 的源块 release 路由：
//      - 控制组：cam_sel=0（A 路），ddr_base = 顶层的 BASE0 参数（0x0010_0000）
//                ⇒ 期望 claim 后有且仅有一次对应块的 release。
//      - 关注组：cam_sel=1（B 路），ddr_base = 顶层 B 路块 0（0x0110_0000）
//                ⇒ 若 claim 仍发生（帧被推送并 held），却观测不到任何 release，
//                  则「推帧引擎对每个发布帧给且只给一个 release」的跨源所有权
//                  契约对 B 路不成立。
//
//  本 TB 独立编写（不复制生产 TB 的判据逻辑，也不调用 DUT helper）；
//  DUT 参数与顶层一致：BASE0=0x0010_0000, BASE1=0x0090_0000。
//  只读生产 RTL，不修改任何被冻结输入。
///////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps

module tb_t07_src_release_probe;

    localparam integer W = 64;
    localparam integer H = 128;
    localparam integer FRAME_BYTES = W * H;         // 8192
    localparam integer NTLP = FRAME_BYTES / 128;    // 64
    localparam integer BB   = 128;                  // beats per burst
    localparam integer BEAT_BYTES = 32;

    // 与顶层 ph1p_pcie_ep_top.v 完全一致的 A 路基址参数
    localparam [31:0] BASE0 = 32'h0010_0000;
    localparam [31:0] BASE1 = 32'h0090_0000;
    // 顶层 B 路基址（ph1p_pcie_ep_top.v 本地参数）
    localparam [31:0] B_BASE0 = 32'h0110_0000;
    localparam [31:0] B_BASE1 = 32'h0190_0000;

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
    wire        tx_block_cfg, rel_tgl0, rel_tgl1, tx_src_lock;
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
        .rel_tgl0(rel_tgl0), .rel_tgl1(rel_tgl1), .tx_src_lock(tx_src_lock),
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
                sl_rdata <= {sl_addr, sl_beat[2:0], 224'd0};   // 内容无关紧要
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

    // ------------------------- release 脉冲监视 -------------------------
    reg rel0_d = 0, rel1_d = 0;
    integer rel0_cnt = 0, rel1_cnt = 0;
    always @(posedge clk_fb) begin
        rel0_d <= rel_tgl0;
        rel1_d <= rel_tgl1;
        if (rel_tgl0 !== rel0_d) rel0_cnt = rel0_cnt + 1;
        if (rel_tgl1 !== rel1_d) rel1_cnt = rel1_cnt + 1;
    end

    integer errors = 0;
    task check; input cond; input [255:0] msg;
        begin
            if (!cond) begin
                errors = errors + 1;
                $display("FAIL: %0s  (time=%0t)", msg, $time);
            end else begin
                $display("ok  : %0s", msg);
            end
        end
    endtask

    // ------------------------- 定向测试任务 -------------------------
    // cam=0 用 BASE0；cam=1 用 B_BASE0（顶层 B 路块 0 实值）
    integer i;
    task automatic run_case;
        input        cam;
        input [31:0] base;
        input [255:0] name;
        integer held_wait;
        integer snaps_err;
        begin
            // 复位
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
            rel0_cnt = 0; rel1_cnt = 0;
            repeat (5) @(posedge clk_fb);

            // 模式开（只开模式，不 ARM 先验证默认不发）
            push_en = 1;
            repeat (5) @(posedge clk_fb);
            ddr_seq_r = 32'd11;                        // 发布一帧（未 ARM ⇒ 应不发）
            repeat (50) @(posedge clk_fb);
            check(st_tlp_cnt == 0, {name, " : no TLP before ARM"});

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
            check(rel0_cnt == 0 && rel1_cnt == 0, {name, " : no release before ACK"});

            // ACK 匹配释放
            ack_seq_r   = st_done;
            ack_sess_r  = sess_r;
            ack_p = 1; @(posedge clk_fb); ack_p = 0;
            repeat (30) @(posedge clk_fb);
            check(tx_status[2] == 1'b0, {name, " : released from HELD"});

            if (cam == 0) begin
                check(rel0_cnt == 1 && rel1_cnt == 0,
                      {name, " : A-path expected exactly 1 release on block0"});
            end else begin
                check(rel0_cnt == 1, {name, " : B-path expected 1 release on block0"});
            end
            snaps_err = 0;
            $display("CASE %0s : rel0_cnt=%0d rel1_cnt=%0d held_wait=%0d st_err=%0d done=%0d",
                     name, rel0_cnt, rel1_cnt, held_wait, st_err, st_done);
        end
    endtask

    initial begin
        $display("=== T07 system probe: source-block release routing ===");
        run_case(0, BASE0,  "A-path BASE0=0x00100000");
        run_case(1, B_BASE0, "B-path B_BASE0=0x01100000");
        if (errors == 0) $display("PROBE_RESULT: ALL PASS (no defect reproduced)");
        else begin
            $display("PROBE_RESULT: %0d CHECK(S) FAILED -> defect reproduced", errors);
        end
        $display("PROBE_DONE");
        $finish;
    end

endmodule
