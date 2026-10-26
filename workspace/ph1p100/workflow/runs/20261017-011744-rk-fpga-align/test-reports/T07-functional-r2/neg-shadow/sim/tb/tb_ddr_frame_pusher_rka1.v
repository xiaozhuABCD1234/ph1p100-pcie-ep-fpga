///////////////////////////////////////////////////////////////////////////////
//  tb_ddr_frame_pusher_rka1.v — T07.rk-align-backend 主功能测试台（ModelSim）
//
//  被测：fpga/csi2/pcie_integration/rtl/ep_side/ddr/ddr_frame_pusher.v（RKA1 版）
//  覆盖（与 task-T07 的 functional 判据一一对应）：
//    0) 复位默认：armed/busy/held/reject/draining 全 0，无 TLP；
//    1) 旧行为负例：CTRL[6]=1（push 模式）+ 帧发布但**不 ARM** ⇒ 一个 TLP 都不发
//       （错误码 5）；旧「自动连续推帧」被拒绝；
//    2) ARM 前置拒绝：session=0 / cap=0 / cap<frame / dst 非 128B 对齐 / dst+frame
//       64bit 回绕 / db=0 / db 非 4B 对齐 / db 落在传输区内 / link_up=0 / MPS 编码
//       非法 / frame_bytes 非 4KiB 倍数 / ddr_status 无效 / 活动期写配置被拒
//       ⇒ 全部错误码 6/10、不发送；
//    3) 单次授权：ARM → 源出新帧 → 恰好 NTLP 笔 128B MWr + 1 笔单 DW 门铃；
//       完成后 held=1、busy=0、armed=0；held 期间源继续出帧 ⇒ 不发（错误码 8）；
//    4) ACK：seq 错 / session 错 ⇒ 不释放（错误码 11，held 槽不变）；匹配 ⇒ 释放；
//       释放后必须重新 ARM，否则再出帧也不发（错误码 5）；
//    5) CANCEL：ARMED 时取消；TX 中途取消（已开始的包补完、不发门铃、成功序号不
//       加）；HELD 时取消（拆槽）；
//    6) 源所有权协议：每个被发布的帧恰好一个 release 事件；被 claim 的块在完成 +
//       ACK 之前绝不 release（写者端「发布即保护」依赖的契约）；
//    7) TL 长 stall + 多帧生产：口子/链路长时间不给，期间持续出帧（只允许写另一块），
//       被发出的每一拍逐拍持稳，恢复后整帧数据逐字节正确；
//    8) 超时：已开始包不截断（补完整包后停）、未开始的包直接放弃；都不发门铃、
//       不加成功序号、错误码 2，最后能回 IDLE（不卡死）；
//    9) 完整 1080p dma_bytes 边界一例：frame_bytes = 2,592,768 ⇒ 20,256 笔 MWr /
//       633 个 4KB 突发，逐字节与源一致，门铃序号正确；
//   10) 独立 TL 监视器（只读 TL 端口，不调用 DUT 任何 helper）检查：F0 头 / FF 载荷 /
//       F8 单 DW 门铃、4DW 地址、Length / BE / Tag / Requester、每包 5 拍（门铃 1 拍）、
//       地址每笔 +128、字节序（主机小端读等于源字节）、门铃在数据之后；
//   11) ERAM 源（src_sel=1）：同一 one-shot 流程 + fb_hold 冻结断言。
///////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps

module tb_ddr_frame_pusher_rka1;

    localparam integer W = 64;
    localparam integer H = 128;                     // 8192 B/帧（4KiB 整数倍）
    localparam integer FRAME_BYTES = W * H;
    localparam integer NTLP = FRAME_BYTES / 128;    // 64
    localparam integer BB   = 128;
    localparam integer BEAT_BYTES = 32;
    localparam integer TLP_BYTES  = 128;

    localparam integer BIG_BYTES  = 2592768;
    localparam integer BIG_NTLP   = BIG_BYTES / 128;

    localparam [31:0] BASE0 = 32'h0010_0000;
    localparam [31:0] BASE1 = 32'h0090_0000;
    localparam [31:0] BASE0B = 32'h0110_0000;   // B 路双缓冲块（与顶层/写者参数一致）
    localparam [31:0] BASE1B = 32'h0190_0000;
    localparam [31:0] DDRCAP = 32'h1000_0000;

    localparam [63:0] DST0 = 64'h0000_0002_0000_0000;
    localparam [63:0] DB0  = 64'h0000_0003_0000_0100;
    localparam [15:0] WAIT_LIMIT = 16'h3FFF;

    reg clk_fb  = 0;
    reg clk_ddr = 0;
    reg rst_fb  = 1;
    reg rst_ddr = 1;
    always #8  clk_fb  = ~clk_fb;
    always #5  clk_ddr = ~clk_ddr;

    reg         push_en;
    reg  [31:0] dst_lo, dst_hi, db_lo, db_hi;
    reg  [31:0] frame_bytes_r;
    reg  [31:0] ddr_seq_r, ddr_base_r, ddr_status_r;
    reg         src_sel;
    reg  [31:0] fb_frame_cnt;
    reg  [31:0] fb_rd_data;
    wire [31:0] fb_rd_addr;
    wire        fb_req, fb_grant, fb_src_act, fb_hold;
    reg         arm_p, ack_p, cancel_p;
    reg  [31:0] cap_r, sess_r, ack_seq_r, ack_sess_r;
    reg         cfg_rej_p;
    reg         link_up;
    reg  [2:0]  mps_code;
    reg         cam_sel;
    wire [31:0] tx_status;
    wire        tx_block_cfg, rel_tgl0, rel_tgl1, rel_tgl2, rel_tgl3, tx_src_lock;
    wire        utx_req, utx_sop, utx_eop;
    wire [255:0] utx_data;
    wire [7:0]  utx_valid;
    reg         utx_sel;
    reg         tl_tx_wait;
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
        .WAIT_LIMIT(WAIT_LIMIT),
        .BASE0(BASE0), .BASE1(BASE1), .BASE0B(BASE0B), .BASE1B(BASE1B),
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
        .ddr_cap_bytes(DDRCAP), .cam_sel_live(cam_sel),
        .tx_status(tx_status), .tx_block_cfg(tx_block_cfg),
        .rel_tgl0(rel_tgl0), .rel_tgl1(rel_tgl1), .rel_tgl2(rel_tgl2), .rel_tgl3(rel_tgl3),
        .tx_src_lock(tx_src_lock),
        .clk_ddr(clk_ddr), .rst_ddr(rst_ddr),
        .m_axi_arid(m_axi_arid), .m_axi_araddr(m_axi_araddr), .m_axi_arlen(m_axi_arlen),
        .m_axi_arsize(m_axi_arsize), .m_axi_arburst(m_axi_arburst),
        .m_axi_arvalid(m_axi_arvalid), .m_axi_arready(m_axi_arready),
        .m_axi_rid(m_axi_rid), .m_axi_rdata(m_axi_rdata), .m_axi_rresp(m_axi_rresp),
        .m_axi_rlast(m_axi_rlast), .m_axi_rvalid(m_axi_rvalid), .m_axi_rready(m_axi_rready)
    );

    // ========================================================================
    //  假 DDR：数据 = 地址函数；检查端用同一函数（不建大数组）
    // ========================================================================
    function [31:0] ddr_word;
        input [31:0] a;
        begin
            // 每个字节都随地址变化（能抓出任何整拍/整字节错位）
            ddr_word = { a[31:24] ^ 8'h5A, a[23:16] ^ 8'hA5, a[15:8] ^ 8'h3C, a[7:2], 2'b00 };
        end
    endfunction

    function [7:0] ddr_byte;
        input [31:0] a;
        reg [31:0] w;
        begin
            w = ddr_word({a[31:2], 2'b00});
            case (a[1:0])
                2'd0: ddr_byte = w[7:0];
                2'd1: ddr_byte = w[15:8];
                2'd2: ddr_byte = w[23:16];
                default: ddr_byte = w[31:24];
            endcase
        end
    endfunction

    localparam integer EWORDS = FRAME_BYTES/4;
    reg [31:0] fbm [0:EWORDS-1];
    integer ii;
    always @(posedge clk_fb) fb_rd_data <= fbm[fb_rd_addr[31:2]];
    assign fb_grant = fb_req;

    // ========================================================================
    //  假 AXI4 从机
    // ========================================================================
    reg        sl_busy = 0;
    reg [28:0] sl_addr = 0;
    integer    sl_beat = 0;
    integer    sl_gap  = 0;
    reg        sl_rvalid = 0, sl_rlast = 0;
    reg [255:0] sl_rdata = 0;

    assign m_axi_rdata  = sl_rdata;
    assign m_axi_rlast  = sl_rlast;
    assign m_axi_rvalid = sl_rvalid;
    assign m_axi_rid    = 4'd0;
    assign m_axi_rresp  = 2'b00;
    assign m_axi_arready = !sl_busy;

    function [255:0] beat_data_of;
        input [28:0] a;
        begin
            beat_data_of = {ddr_word(a + 28), ddr_word(a + 24), ddr_word(a + 20), ddr_word(a + 16),
                            ddr_word(a + 12), ddr_word(a +  8), ddr_word(a +  4), ddr_word(a +  0)};
        end
    endfunction

    always @(posedge clk_ddr) begin
        if (rst_ddr) begin
            sl_busy <= 0; sl_rvalid <= 0; sl_rlast <= 0; sl_beat <= 0; sl_gap <= 0;
        end else if (!sl_busy) begin
            if (m_axi_arvalid && m_axi_arready) begin
                sl_busy <= 1; sl_addr <= m_axi_araddr; sl_beat <= 0; sl_gap <= 0;
                sl_rvalid <= 0; sl_rlast <= 0;
            end
        end else if (sl_rvalid && m_axi_rready) begin
            if (sl_rlast) begin
                sl_busy <= 0; sl_rvalid <= 0; sl_rlast <= 0;
            end else begin
                // 先推进到下一条，再决定要不要插空档（空档期间输出撤掉，
                // 下一拍把已推进地址的数据摆上；不能原地重复上一拍）
                sl_gap <= 0;
                sl_beat <= sl_beat + 1;
                sl_rlast <= (sl_beat + 1 == BB-1);
                sl_rdata <= beat_data_of(sl_addr + (sl_beat+1)*BEAT_BYTES);
                if ((sl_beat % 8) == 7) begin
                    sl_rvalid <= 0; sl_gap <= 1;
                end
            end
        end else if (!sl_rvalid) begin
            sl_rvalid <= 1;
            sl_rlast  <= (sl_beat == BB-1);
            sl_rdata  <= beat_data_of(sl_addr + sl_beat*BEAT_BYTES);
        end
    end

    // ========================================================================
    //  假引擎 TL 口
    // ========================================================================
    reg        stall_en = 0;
    reg        port_stall_en = 0;
    integer    stall_left = 0;
    integer    rnd = 32'h1234_5678;
    task automatic rstep; begin rnd = {rnd[30:0], rnd[31]^rnd[21]^rnd[1]}; end endtask

    always @(posedge clk_fb) begin
        if (rst_fb) begin
            utx_sel <= 0; tl_tx_wait <= 0;
        end else begin
            rstep;
            if (stall_en) begin
                utx_sel <= 1;
                if (stall_left > 0) begin
                    stall_left <= stall_left - 1;
                    tl_tx_wait <= 1;
                    if (stall_left == 1) stall_en <= 0;
                end else tl_tx_wait <= 1;
            end else if (port_stall_en) begin
                utx_sel <= 0; tl_tx_wait <= 0;
            end else begin
                tl_tx_wait <= (rnd[9:8] == 2'b11);
                if (!utx_sel) begin
                    if (utx_req) utx_sel <= 1;
                end else if (utx_eop && (|utx_valid) && !tl_tx_wait) begin
                    utx_sel <= 0;
                end
            end
        end
    end

    task automatic force_stall_n(input integer n);
        begin
            stall_left = n; stall_en = 1;
            while (stall_en) @(posedge clk_fb);
            @(posedge clk_fb);
        end
    endtask

    // ========================================================================
    //  独立 TL 监视器
    // ========================================================================
    integer errs = 0;
    integer pkt_idx = 0;
    integer beat_i = 0;
    integer nb = 0;
    reg [7:0] bytes [0:255];
    integer exp_ntlp = NTLP;
    reg [63:0] exp_dst = DST0;
    reg [63:0] exp_db  = DB0;
    reg [31:0] exp_base = BASE0;
    reg        expect_ddr_src = 1;
    integer    db_seen = 0;            // 本阶段收到的门铃数
    integer    db_count = 0;           // 全程累计门铃数（payload 应等于它）
    integer    pkt_started_cnt = 0, pkt_done_cnt = 0;
    integer    tot_tlp = 0;
    reg [31:0] last_db_val = 0;
    reg        saw_data_after_db = 0;
    integer    pay_ok = 1;
    integer    pay_dbg = 0;
    integer    pkt_dbg = 0;
    reg        dbg_en = 0;

    reg         prev_beat_up = 0, prev_sel = 0, prev_wait = 0;
    reg [255:0] prev_data = 0;
    reg         prev_sop = 0, prev_eop = 0;
    reg [7:0]   prev_valid = 0;

    task automatic chk(input cond, input [8*96-1:0] msg);
        begin
            if (!cond) begin
                errs = errs + 1;
                if (errs <= 25) $display("  ERROR #%0d @%0t : %s", errs, $time, msg);
            end
        end
    endtask

    task automatic push_beat(input [255:0] d, input [7:0] v);
        integer n;
        begin
            for (n = 7; n >= 0; n = n - 1) begin
                if (v[n]) begin
                    bytes[nb+0] = d[32*n + 31 -: 8];
                    bytes[nb+1] = d[32*n + 23 -: 8];
                    bytes[nb+2] = d[32*n + 15 -: 8];
                    bytes[nb+3] = d[32*n +  7 -: 8];
                    nb = nb + 4;
                end
            end
        end
    endtask

    function [31:0] be32; input integer o;
        begin be32 = {bytes[o], bytes[o+1], bytes[o+2], bytes[o+3]}; end
    endfunction
    function [31:0] le32; input integer o;
        begin le32 = {bytes[o+3], bytes[o+2], bytes[o+1], bytes[o]}; end
    endfunction

    integer kk;
    reg [31:0] dw0, dw1, dw2, dw3;
    reg [63:0] exp_addr64;

    always @(posedge clk_fb) begin
        if (!rst_fb) begin
            // ---- wait 持稳 ----
            if (prev_beat_up && !(prev_sel && !prev_wait)) begin
                chk((utx_data === prev_data) && (utx_sop === prev_sop) &&
                    (utx_eop === prev_eop) && (utx_valid === prev_valid),
                    "TL beat changed while waiting");
            end
            prev_beat_up <= (|utx_valid);
            prev_sel     <= utx_sel;
            prev_wait    <= tl_tx_wait;
            prev_data    <= utx_data;
            prev_sop     <= utx_sop;
            prev_eop     <= utx_eop;
            prev_valid   <= utx_valid;

            if (utx_sel && !tl_tx_wait && (|utx_valid)) begin
                if (utx_sop) begin
                    nb = 0; beat_i = 0;
                    pkt_started_cnt = pkt_started_cnt + 1;
                end
                push_beat(utx_data, utx_valid);
                beat_i = beat_i + 1;

                if (utx_eop) begin
                    pkt_done_cnt = pkt_done_cnt + 1;
                    tot_tlp = tot_tlp + 1;
                    dw0 = be32(0); dw1 = be32(4); dw2 = be32(8); dw3 = be32(12);
                    if (dbg_en) begin
                        $display("  DBG pkt=%0d addr=%08h:%08h beat=%0d p_st=%0d g_st=%0d err=%02h flush=%b tlp=%0d @%0t",
                                 pkt_idx, dw2, dw3, beat_i, dut.p_st, dut.g_st, dut.err_r, dut.flush, dut.tlp, $time);
                    end
                    if (pkt_idx < exp_ntlp) begin
                        chk(beat_i == 5, "frame MWr beat count != 5");
                        chk(dw0[31:29] == 3'b011, "Fmt != 4DW+data");
                        chk(dw0[28:24] == 5'b0_0000, "Type != MWR");
                        chk(dw0[9:0] == 32, "Length != 32");
                        chk(dw1[31:16] == 16'h0100, "RequesterID != 01:00.0");
                        chk(dw1[15:8] == 8'h00, "Tag != 0");
                        chk(dw1[7:4] == 4'hf, "LastDWBE != F");
                        chk(dw1[3:0] == 4'hf, "FirstDWBE != F");
                        exp_addr64 = exp_dst + pkt_idx * TLP_BYTES;
                        chk(dw2 == exp_addr64[63:32], "addr hi32 wrong");
                        chk(dw3 == {exp_addr64[31:2], 2'b00}, "addr lo30 wrong");
                        pay_ok = 1;
                        if (expect_ddr_src) begin
                            for (kk = 0; kk < TLP_BYTES; kk = kk + 1)
                                if (bytes[16+kk] !== ddr_byte(exp_base + pkt_idx*TLP_BYTES + kk)) begin
                                    if (pay_dbg < 6) begin
                                        pay_dbg = pay_dbg + 1;
                                        $display("  DBG mismatch pkt=%0d k=%0d got=%02h exp=%02h (frame_addr=%08h try=%0d)",
                                            pkt_idx, kk, bytes[16+kk],
                                            ddr_byte(exp_base + pkt_idx*TLP_BYTES + kk),
                                            exp_base + pkt_idx*TLP_BYTES + kk, tlp_snap);
                                    end
                                    pay_ok = 0;
                                end
                            if (pay_ok == 0)
                                $display("  DBG pkt=%0d pay0..7 = %02h %02h %02h %02h %02h %02h %02h %02h",
                                    pkt_idx, bytes[16], bytes[17], bytes[18], bytes[19],
                                    bytes[20], bytes[21], bytes[22], bytes[23]);
                        end else begin
                            for (kk = 0; kk < TLP_BYTES; kk = kk + 1)
                                if (bytes[16+kk] !== fbm[(pkt_idx*TLP_BYTES + kk) >> 2][8*(kk%4) +: 8]) begin
                                    if (pay_dbg < 6) begin
                                        pay_dbg = pay_dbg + 1;
                                        $display("  DBG eram pkt=%0d k=%0d got=%02h exp=%02h wi=%0d",
                                            pkt_idx, kk, bytes[16+kk],
                                            fbm[(pkt_idx*TLP_BYTES + kk) >> 2][8*(kk%4) +: 8],
                                            (pkt_idx*TLP_BYTES + kk) >> 2);
                                    end
                                    pay_ok = 0;
                                end
                            if (pay_ok == 0)
                                $display("  DBG eram pkt=%0d pay0..7 = %02h %02h %02h %02h %02h %02h %02h %02h",
                                    pkt_idx, bytes[16], bytes[17], bytes[18], bytes[19],
                                    bytes[20], bytes[21], bytes[22], bytes[23]);
                        end
                        chk(pay_ok == 1, "payload byte mismatch vs source");
                        if (db_seen != 0) saw_data_after_db = 1;
                    end else begin
                        chk(beat_i == 1, "doorbell not single beat");
                        chk(dw0[31:29] == 3'b011, "doorbell Fmt != 4DW");
                        chk(dw0[9:0] == 1, "doorbell Length != 1");
                        chk(dw1[7:4] == 4'h0, "doorbell LastDWBE != 0");
                        chk(dw1[3:0] == 4'hf, "doorbell FirstDWBE != F");
                        chk(dw2 == exp_db[63:32], "doorbell addr hi wrong");
                        chk(dw3 == {exp_db[31:2], 2'b00}, "doorbell addr lo wrong");
                        db_seen = db_seen + 1;
                        db_count = db_count + 1;
                        last_db_val = le32(16);
                        chk(last_db_val == db_count, "doorbell payload != seq");
                    end
                    pkt_idx = pkt_idx + 1;
                end
            end
        end
    end

    // release 协议监视（T07 round1：A/B 各一对 toggle 分开计数）
    reg prev_rel0 = 0, prev_rel1 = 0, prev_rel2 = 0, prev_rel3 = 0;
    integer rel0_cnt = 0, rel1_cnt = 0, rel2_cnt = 0, rel3_cnt = 0;
    integer claim_blk = -1;
    integer claim_cam = -1;      // 本次要检查的相机（0=A,1=B），与 claim_blk 配套
    integer early_rel = 0;
    always @(posedge clk_fb) begin
        if (!rst_fb) begin
            if (rel_tgl0 !== prev_rel0) begin rel0_cnt = rel0_cnt + 1;
                if ((claim_cam == 0) && (claim_blk == 0)) early_rel = early_rel + 1; end
            if (rel_tgl1 !== prev_rel1) begin rel1_cnt = rel1_cnt + 1;
                if ((claim_cam == 0) && (claim_blk == 1)) early_rel = early_rel + 1; end
            if (rel_tgl2 !== prev_rel2) begin rel2_cnt = rel2_cnt + 1;
                if ((claim_cam == 1) && (claim_blk == 0)) early_rel = early_rel + 1; end
            if (rel_tgl3 !== prev_rel3) begin rel3_cnt = rel3_cnt + 1;
                if ((claim_cam == 1) && (claim_blk == 1)) early_rel = early_rel + 1; end
            prev_rel0 <= rel_tgl0;
            prev_rel1 <= rel_tgl1;
            prev_rel2 <= rel_tgl2;
            prev_rel3 <= rel_tgl3;
        end
    end

    // 调试：AXI 突发地址（只打前若干笔）
    integer ar_dbg = 0;
    always @(posedge clk_ddr) begin
        if (!rst_ddr && m_axi_arvalid && m_axi_arready) begin
            if (ar_dbg < 12) begin
                ar_dbg = ar_dbg + 1;
                $display("  DBG AXI burst addr=%08h @%0t", {3'b0, m_axi_araddr}, $time);
            end
        end
    end

    // ========================================================================
    //  主流程
    // ========================================================================
    integer t, ok1, tlp_snap;
    integer rel_a_snap = 0, rel_b_snap = 0;
    integer pub_cnt = 0;
    reg [31:0] next_seq = 0;
    reg [31:0] done_before;

    task automatic arm_now; begin
            @(negedge clk_fb); arm_p = 1;
            @(negedge clk_fb); arm_p = 0;
            @(negedge clk_fb);
        end endtask
    task automatic ack_now; begin
            @(negedge clk_fb); ack_p = 1;
            @(negedge clk_fb); ack_p = 0;
            @(negedge clk_fb);
        end endtask
    task automatic cancel_now; begin
            @(negedge clk_fb); cancel_p = 1;
            @(negedge clk_fb); cancel_p = 0;
            @(negedge clk_fb);
        end endtask

    task automatic publish(input [31:0] base); begin
            @(negedge clk_fb);
            next_seq = next_seq + 1;
            ddr_base_r = base;
            ddr_seq_r  = next_seq;
            ddr_status_r = 32'h1;
            pub_cnt = pub_cnt + 1;
        end endtask

    task automatic wait_frame(input integer maxcyc, output integer ok);
        integer tc;
        begin
            tc = 0; ok = 0;
            while ((tx_status[1] == 0) && (tc < maxcyc)) begin @(posedge clk_fb); tc=tc+1; end
            if (tx_status[1]) begin
                while ((tx_status[1] == 1) && (tc < maxcyc)) begin @(posedge clk_fb); tc=tc+1; end
                ok = (tc < maxcyc);
            end
        end
    endtask

    initial begin
        errs = 0; pkt_idx = 0; nb = 0; beat_i = 0; tot_tlp = 0;
        push_en = 0; src_sel = 0; cam_sel = 0;
        dst_lo = 32'd0; dst_hi = 32'd0; db_lo = 32'd0; db_hi = 32'd0;
        frame_bytes_r = FRAME_BYTES;
        ddr_seq_r = 0; ddr_base_r = BASE0; ddr_status_r = 0;
        fb_frame_cnt = 0;
        cap_r = 0; sess_r = 0; ack_seq_r = 0; ack_sess_r = 0;
        arm_p = 0; ack_p = 0; cancel_p = 0; cfg_rej_p = 0;
        link_up = 1; mps_code = 3'd0;
        stall_en = 0; port_stall_en = 0; stall_left = 0;
        rst_fb = 1; rst_ddr = 1;
        for (ii = 0; ii < EWORDS; ii = ii + 1) fbm[ii] = 32'h5A5A_0000 + ii;
        #200; rst_fb = 0; rst_ddr = 0; #200;

        $display("=== PHASE0 reset defaults @%0t", $time);
        chk(tx_status == 32'd0, "reset: tx_status != 0");
        chk(st_done == 0, "reset: st_done != 0");
        chk(st_err == 0, "reset: st_err != 0");
        repeat (20) @(posedge clk_fb);
        chk(tot_tlp == 0, "reset: TLP emitted");

        $display("=== PHASE1 legacy negative (no ARM) @%0t", $time);
        push_en = 1; ddr_status_r = 32'h1; exp_base = BASE0;
        publish(BASE0);
        repeat (200) @(posedge clk_fb);
        chk(tot_tlp == 0, "PHASE1: transmitted without ARM");
        chk(st_err == 8'd5, "PHASE1: st_err != 5 (E_NOT_ARM)");
        chk(tx_status[0] == 0, "PHASE1: armed set");

        $display("=== PHASE2 ARM validation negatives @%0t", $time);
        cap_r = FRAME_BYTES; sess_r = 32'h11;
        dst_lo = DST0[31:0]; dst_hi = DST0[63:32];
        db_lo = DB0[31:0];   db_hi = DB0[63:32];
        link_up = 1; mps_code = 3'd0; frame_bytes_r = FRAME_BYTES;

        sess_r = 0; arm_now;
        chk(st_err == 8'd6, "a) session=0 not rejected");
        chk(tx_status[0] == 0, "a) armed after reject");
        sess_r = 32'h11; cap_r = 0; arm_now;
        chk(st_err == 8'd6, "b) cap=0 not rejected");
        cap_r = FRAME_BYTES - 4096; arm_now;
        chk(st_err == 8'd6, "c) cap<frame not rejected");
        cap_r = FRAME_BYTES; dst_lo = DST0[31:0] | 32'h40; arm_now;
        chk(st_err == 8'd6, "d) dst misaligned not rejected");
        dst_lo = DST0[31:0];
        dst_lo = 32'hFFFF_FF00; dst_hi = 32'hFFFF_FFFF; arm_now;
        chk(st_err == 8'd6, "e) dst wrap not rejected");
        dst_lo = DST0[31:0]; dst_hi = DST0[63:32];
        db_lo = 0; db_hi = 0; arm_now;
        chk(st_err == 8'd6, "f) db=0 not rejected");
        db_lo = DB0[31:0] | 32'h2; db_hi = DB0[63:32]; arm_now;
        chk(st_err == 8'd6, "g) db misaligned not rejected");
        db_lo = DST0[31:0] + 32'h1000; db_hi = DST0[63:32]; arm_now;
        chk(st_err == 8'd6, "h) db overlaps transfer not rejected");
        db_lo = DB0[31:0]; db_hi = DB0[63:32];
        link_up = 0; arm_now;
        chk(st_err == 8'd6, "i) link down not rejected");
        link_up = 1;
        mps_code = 3'd6; arm_now;
        chk(st_err == 8'd6, "j) bad MPS not rejected");
        mps_code = 3'd0;
        frame_bytes_r = FRAME_BYTES + 128; arm_now;
        chk(st_err == 8'd6, "k) non-4KiB frame not rejected");
        frame_bytes_r = FRAME_BYTES;
        ddr_status_r = 0; arm_now;
        chk(st_err == 8'd6, "l) ddr_status invalid not rejected");
        ddr_status_r = 32'h1;
        cfg_rej_p = 1; @(negedge clk_fb); cfg_rej_p = 0; @(negedge clk_fb);
        chk(st_err == 8'd10, "m) cfg_reject not flagged");
        chk(tx_status[3] == 1, "m) reject bit not sticky");
        chk(tot_tlp == 0, "PHASE2: TLP emitted");

        $display("=== PHASE3 one-shot + held + ACK @%0t", $time);
        exp_ntlp = NTLP; exp_dst = DST0; exp_db = DB0; exp_base = BASE0;
        expect_ddr_src = 1; pkt_idx = 0; db_seen = 0;
        sess_r = 32'hA5A5_0001;
        arm_now;
        chk(st_err == 8'd0, "PHASE3: arm not accepted");
        chk(tx_status[0] == 1, "PHASE3: armed not set");
        chk(tx_status[3] == 0, "PHASE3: reject not cleared");
        claim_blk = 0; claim_cam = 0; early_rel = 0;
        publish(BASE0);
        wait_frame(400000, ok1);
        chk(ok1 == 1, "PHASE3: frame did not finish");
        chk(pkt_idx == exp_ntlp+1, "PHASE3: TLP count != NTLP+1");
        chk(db_seen == 1, "PHASE3: no doorbell");
        chk(st_done == 1, "PHASE3: st_done != 1");
        chk(st_tlp_cnt == exp_ntlp, "PHASE3: st_tlp_cnt wrong");
        chk(st_err == 0, "PHASE3: st_err != 0");
        chk(tx_status[0] == 1'b0, "PHASE3: armed still set");
        chk(tx_status[2] == 1'b1, "PHASE3: held not set");
        chk(tx_status[1] == 1'b0, "PHASE3: busy still set");
        publish(BASE1);
        repeat (200) @(posedge clk_fb);
        chk(pkt_idx == exp_ntlp+1, "PHASE3: transmitted while held");
        chk(st_err == 8'd8, "PHASE3: held err != 8");
        ack_seq_r = 32'hFFFF; ack_sess_r = 32'hA5A5_0001; ack_now;
        chk(tx_status[2] == 1'b1, "PHASE3: bad seq ACK released");
        chk(st_err == 8'd11, "PHASE3: bad ACK err != 11");
        ack_seq_r = 32'd1; ack_sess_r = 32'hDEAD; ack_now;
        chk(tx_status[2] == 1'b1, "PHASE3: bad session ACK released");
        chk(early_rel == 0, "PHASE3: block released before ACK");
        claim_blk = -1;
        ack_seq_r = 32'd1; ack_sess_r = 32'hA5A5_0001; ack_now;
        chk(tx_status[2] == 1'b0, "PHASE3: matching ACK did not release");
        chk(tx_status[0] == 1'b0, "PHASE3: armed after release?");
        publish(BASE0);
        repeat (200) @(posedge clk_fb);
        chk(pkt_idx == exp_ntlp+1, "PHASE3: transmitted without re-arm");
        chk(st_err == 8'd5, "PHASE3: re-arm check err != 5");
        chk(rel0_cnt >= 1, "PHASE3: no release observed for blk0");

        $display("=== PHASE4 cancel paths @%0t", $time);
        sess_r = 32'hA5A5_0002; arm_now;
        chk(tx_status[0] == 1, "PHASE4a: arm failed");
        cancel_now;
        chk(tx_status[0] == 0, "PHASE4a: cancel did not disarm");
        chk(st_err == 8'd7, "PHASE4a: err != 7");
        pkt_idx = 0; db_seen = 0;
        arm_now;
        chk(tx_status[0] == 1, "PHASE4b: arm failed");
        exp_base = BASE1;
        publish(BASE1);
        t = 0;
        while ((pkt_idx < 5) && (t < 200000)) begin @(posedge clk_fb); t = t + 1; end
        done_before = st_done;
        cancel_now;
        t = 0;
        while ((tx_status[1] == 1) && (t < 200000)) begin @(posedge clk_fb); t = t + 1; end
        chk(tx_status[1] == 0, "PHASE4b: busy stuck after cancel");
        chk(pkt_idx < exp_ntlp+1, "PHASE4b: full frame sent after cancel");
        chk(st_done == done_before, "PHASE4b: st_done changed");
        chk(st_err == 8'd7, "PHASE4b: err != 7");
        repeat (50) @(posedge clk_fb);
        pkt_idx = 0; db_seen = 0;
        sess_r = 32'hA5A5_0003; arm_now;
        exp_base = BASE0;
        publish(BASE0);
        wait_frame(400000, ok1);
        chk(tx_status[2] == 1, "PHASE4c: not held");
        cancel_now;
        chk(tx_status[2] == 0, "PHASE4c: cancel did not clear held");
        chk(st_done == 2, "PHASE4c: st_done != 2");
        repeat (50) @(posedge clk_fb);

        $display("=== PHASE5 release protocol counting @%0t", $time);
        begin : p5
            integer r0, r1;
            r0 = rel0_cnt; r1 = rel1_cnt; tlp_snap = tot_tlp;
            publish(BASE0); repeat (100) @(posedge clk_fb);
            publish(BASE1); repeat (100) @(posedge clk_fb);
            chk(rel0_cnt == r0+1, "PHASE5: blk0 release count != 1 per publish");
            chk(rel1_cnt == r1+1, "PHASE5: blk1 release count != 1 per publish");
            chk(tot_tlp == tlp_snap, "PHASE5: stray TLP sent");
        end

        $display("=== PHASE6 long TL stall + multi-frame production @%0t", $time);
        pkt_idx = 0; db_seen = 0;
        sess_r = 32'hA5A5_0004; arm_now;
        claim_blk = 0; claim_cam = 0; early_rel = 0;
        publish(BASE0);
        t = 0;
        while ((pkt_idx < 3) && (t < 200000)) begin @(posedge clk_fb); t = t + 1; end
        fork
            force_stall_n(4000);
            begin
                repeat (10) @(posedge clk_fb);
                publish(BASE1); repeat (50) @(posedge clk_fb);
                publish(BASE1); repeat (50) @(posedge clk_fb);
                publish(BASE1);
            end
        join
        wait_frame(400000, ok1);
        chk(ok1 == 1, "PHASE6: frame did not finish after long stall");
        chk(pkt_idx == exp_ntlp+1, "PHASE6: TLP count wrong after stall");
        chk(st_err == 0, "PHASE6: st_err != 0 after stall");
        chk(early_rel == 0, "PHASE6: block released during in-flight frame");
        claim_blk = -1;
        ack_seq_r = st_done; ack_sess_r = 32'hA5A5_0004; ack_now;
        chk(tx_status[2] == 0, "PHASE6: ACK did not release");

        $display("=== PHASE7 timeout (open packet completed, no doorbell) @%0t", $time);
        publish(BASE0); repeat (20) @(posedge clk_fb);
        pkt_idx = 0;
        sess_r = 32'hA5A5_0005; arm_now;
        exp_base = BASE1;
        publish(BASE1);
        t = 0;
        while ((pkt_idx < 2) && (t < 200000)) begin @(posedge clk_fb); t = t + 1; end
        force_stall_n(WAIT_LIMIT + 2000);
        t = 0;
        while ((tx_status[1] == 1) && (t < 400000)) begin @(posedge clk_fb); t = t + 1; end
        chk(tx_status[1] == 0, "PHASE7: not idle after timeout");
        chk(st_err == 8'd2, "PHASE7: err != 2");
        chk(db_count == 3, "PHASE7: doorbell sent after timeout");
        chk(st_done == 3, "PHASE7: st_done changed after timeout");
        chk(pkt_started_cnt == pkt_done_cnt, "PHASE7: truncated TLP");
        repeat (50) @(posedge clk_fb);

        $display("=== PHASE8 hard stall before first beat: hold + complete + drain @%0t", $time);
        dbg_en = 1;
        pkt_started_cnt = 0; pkt_done_cnt = 0; tot_tlp = 0;
        pkt_idx = 0; db_seen = 0;
        sess_r = 32'hA5A5_0006;
        port_stall_en = 1;                 // 先完全不给口子：保证本帧一笔都没发
        arm_now;
        exp_base = BASE0;
        publish(BASE0);
        t = 0; while ((tx_status[1] == 0) && (t < 100000)) begin @(posedge clk_fb); t=t+1; end
        repeat (20) @(posedge clk_fb);
        chk(tot_tlp == 0, "PHASE8: TLP sent before stall");
        // 长硬 stall：口子给了但链路一直不收（valid 必须持稳，不许丢拍/半包）
        tlp_snap = tot_tlp;
        stall_left = WAIT_LIMIT + 2000; stall_en = 1;
        port_stall_en = 0;
        // stall 进行中就检查：这段时间一笔都不许被收走
        repeat (WAIT_LIMIT + 500) @(posedge clk_fb);
        chk(tot_tlp == tlp_snap, "PHASE8: TLP accepted during long stall window");
        while (stall_en) @(posedge clk_fb);
        repeat (100) @(posedge clk_fb);
        // 链路恢复：这一包必须补完（5 拍）→ 再排空，错误码 2、无门铃
        t = 0;
        while ((tx_status[1] == 1) && (t < 600000)) begin @(posedge clk_fb); t = t + 1; end
        chk(tx_status[1] == 0, "PHASE8: not idle after recovery");
        chk(st_err == 8'd2, "PHASE8: err != 2");
        chk(pkt_started_cnt == pkt_done_cnt, "PHASE8: truncated TLP");
        chk(pkt_done_cnt >= 1, "PHASE8: no packet completed after recovery");
        chk(db_count == 3, "PHASE8: doorbell sent");
        repeat (50) @(posedge clk_fb);

        $display("=== PHASE9 ERAM source (src_sel=1) + fb_hold @%0t", $time);
        dbg_en = 1;
        src_sel = 1; frame_bytes_r = FRAME_BYTES;
        fb_frame_cnt = 1;
        pkt_idx = 0; db_seen = 0;
        expect_ddr_src = 0;
        tot_tlp = 0;
        sess_r = 32'hA5A5_0007; arm_now;
        chk(tx_status[0] == 1, "PHASE9: arm failed (ERAM)");
        chk(tot_tlp == 0, "PHASE9: sent before new frame");
        fb_frame_cnt = 2;
        wait_frame(400000, ok1);
        chk(ok1 == 1, "PHASE9: ERAM frame did not finish");
        chk(pkt_idx == exp_ntlp+1, "PHASE9: ERAM TLP count wrong");
        chk(fb_hold == 1'b1, "PHASE9: fb_hold not asserted while held");
        ack_seq_r = st_done; ack_sess_r = 32'hA5A5_0007; ack_now;
        chk(tx_status[2] == 0, "PHASE9: ACK did not release");
        chk(fb_hold == 1'b0, "PHASE9: fb_hold not cleared after ACK");
        src_sel = 0; expect_ddr_src = 1; frame_bytes_r = FRAME_BYTES;

        $display("=== PHASE10 full 1080p dma_bytes length boundary @%0t", $time);
        dbg_en = 0;
        pkt_idx = 0; db_seen = 0; tot_tlp = 0;
        saw_data_after_db = 0;
        exp_ntlp = BIG_NTLP;
        exp_base = BASE1;
        frame_bytes_r = BIG_BYTES;
        cap_r = BIG_BYTES;
        exp_dst = 64'h0000_0005_0000_0000;
        dst_lo = exp_dst[31:0]; dst_hi = exp_dst[63:32];
        sess_r = 32'hA5A5_0008;
        arm_now;
        chk(st_err == 8'd0, "PHASE10: arm rejected");
        publish(BASE1);
        wait_frame(4000000, ok1);
        chk(ok1 == 1, "PHASE10: 1080p frame did not finish");
        chk(pkt_idx == exp_ntlp+1, "PHASE10: MWr count != 20257 (incl doorbell)");
        chk(st_tlp_cnt == BIG_NTLP, "PHASE10: st_tlp_cnt != 20256");
        chk(db_seen == 1, "PHASE10: doorbell count wrong");
        chk(saw_data_after_db == 0, "PHASE10: data TLP after doorbell");
        chk(st_err == 0, "PHASE10: st_err != 0");
        chk(st_done == 5, "PHASE10: st_done != 5");
        ack_seq_r = st_done; ack_sess_r = 32'hA5A5_0008; ack_now;
        chk(tx_status[2] == 0, "PHASE10: final ACK failed");

        $display("=== PHASE11 B-path one-shot + release (cam_sel=1) @%0t", $time);
        cam_sel = 1;                     // 相机 B：基址对换成 BASE0B/BASE1B
        exp_ntlp = NTLP; exp_dst = DST0; exp_db = DB0; exp_base = BASE0B;
        frame_bytes_r = FRAME_BYTES; cap_r = FRAME_BYTES;
        dst_lo = DST0[31:0]; dst_hi = DST0[63:32];
        db_lo = DB0[31:0];   db_hi = DB0[63:32];
        pkt_idx = 0; db_seen = 0;
        rel_a_snap = rel0_cnt + rel1_cnt;
        rel_b_snap = rel2_cnt + rel3_cnt;
        sess_r = 32'hB0B0_0001;
        arm_now;
        chk(tx_status[0] == 1, "PHASE11: B arm failed");
        claim_blk = 0; claim_cam = 1; early_rel = 0;
        publish(BASE0B);
        wait_frame(400000, ok1);
        chk(ok1 == 1, "PHASE11: B frame did not finish");
        chk(pkt_idx == exp_ntlp+1, "PHASE11: B TLP count wrong");
        chk(st_err == 0, "PHASE11: B st_err != 0");
        chk(tx_status[2] == 1'b1, "PHASE11: B not held");
        chk(early_rel == 0, "PHASE11: B block released before ACK");
        chk(rel2_cnt + rel3_cnt == rel_b_snap, "PHASE11: B released before ACK");
        ack_seq_r = st_done; ack_sess_r = 32'hB0B0_0001; ack_now;
        chk(tx_status[2] == 0, "PHASE11: B ACK did not release");
        claim_blk = -1; claim_cam = -1;
        // B 路 ASK 之后：B 的 toggle 恰好 +1，A 的 toggle 一个都不许动
        repeat (50) @(posedge clk_fb);
        chk(rel2_cnt + rel3_cnt == rel_b_snap + 1, "PHASE11: B release count != 1");
        chk(rel0_cnt + rel1_cnt == rel_a_snap, "PHASE11: A toggles moved during B frame");

        $display("=== PHASE12 A/B cross: A activity must not move B's release lines @%0t", $time);
        // B 路再推一帧并 held；随后只做 A 路的发布/pass 释放，
        // 检查 B 的 toggle 计数不受影响（round0 system F1 的交叉场景）。
        pkt_idx = 0; db_seen = 0;
        sess_r = 32'hB0B0_0002; arm_now;
        claim_blk = 0; claim_cam = 1;
        exp_base = BASE0B;
        publish(BASE0B);
        wait_frame(400000, ok1);
        chk(ok1 == 1, "PHASE12: B frame did not finish");
        rel_a_snap = rel0_cnt + rel1_cnt;
        rel_b_snap = rel2_cnt + rel3_cnt;
        // A 路连续发布（pass → A 自己的 release），不应动 B 的 toggle
        cam_sel = 0;
        exp_base = BASE0;
        publish(BASE0); repeat (100) @(posedge clk_fb);
        publish(BASE1); repeat (100) @(posedge clk_fb);
        chk(rel0_cnt + rel1_cnt >= rel_a_snap + 2, "PHASE12: A releases did not happen");
        chk(rel2_cnt + rel3_cnt == rel_b_snap, "PHASE12: B toggles moved by A activity");
        // 回到 B 并 ACK：B 自己的 toggle 恰好 +1
        cam_sel = 1;
        ack_seq_r = st_done; ack_sess_r = 32'hB0B0_0002; ack_now;
        repeat (50) @(posedge clk_fb);
        chk(rel2_cnt + rel3_cnt == rel_b_snap + 1, "PHASE12: B ACK release count != 1");
        chk(rel0_cnt + rel1_cnt >= rel_a_snap + 2, "PHASE12: A toggles changed by B ACK");
        claim_blk = -1; claim_cam = -1;
        cam_sel = 0;

        repeat (100) @(posedge clk_fb);
        if (errs == 0) $display("ALL PASS (%0d TLPs total, %0d accepted beats)", tot_tlp, pkt_done_cnt);
        else           $display("FAIL: %0d error(s)", errs);
        $finish;
    end

    initial begin
        #400_000_000;
        $display("FAIL: global timeout");
        $finish;
    end

endmodule
