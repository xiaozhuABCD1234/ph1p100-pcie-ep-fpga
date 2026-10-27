///////////////////////////////////////////////////////////////////////////////
//  tb_t11_r10f_e2e.v — T11.rk-align-raw G1：全链路端到端（真实 RTL，合成源）
//
//  链路（全部真实例化，除厂商 serdes PHY 用 MIPI_PHY_SIM_STUB 旁路）：
//    CSI 注入（FS + 4 行长包 WC=10 + FE，独立 ECC/CRC16 实现）
//      → mipi_csi2_rx_ph1p_checked（checked 完整性/解包）
//      → cam_r10f_writer（packed RAW10 → R10F 内容 → AXI 写 DDR 模型）
//      → 假 DDR（同一内存阵列：写侧由 AXI 写从机更新，读侧供推帧引擎）
//      → ddr_frame_pusher（one-shot 发送：32 笔 128B MWr + 1 门铃）
//      → 独立 TL 监视器（F0/FF/F8、4DW 地址、Length/BE、地址递增、字节序）
//      → host 模型（按目标地址装配），逐字节 vs 模型（头按 seq 参数化）+ CRC 复核
//
//  相位（单次仿真）：
//    E0  未 ARM：出帧 #1 → 发布但 **0 个 TLP**（错误码 5）＋ 该块 release；
//    E1  ARM → 出帧 #2（block1，seq=2）→ 发送 → held；
//        错 seq / 错 session 的 ACK 都不释放 → 匹配 ACK 才释放（block1 release +1）；
//    E2  再 ARM → 出帧 #3（block0，seq=3）→ 发送（st_done=2、门铃值=2）→ 匹配 ACK；
//    E3  慢消费：TL 口长 wait（已开包逐拍持稳；监视器断言）→ 完成后 held；
//        held 期间源继续出帧 ⇒ 不发送（错误码 8）且该块仍被保护 → ACK 释放；
//    E4  reset 隔离：held 未 ACK 时复位 → 旧会话不清账、不发成功门铃；
//        新 session 重走「出帧 → ARM → 出帧 → 发送」→ 头里是新 session，ACK 释放。
//
//  说明：ARM 前置条件沿用 T07 语义（DDR 源必须有「已发布过的完整帧」，
//        pusher 只 claim **ARM 之后新发布**的帧）；因此每段先出一帧热身。
//        监视器在每个发送段开始前显式复位按帧计数（tlp_idx/db_cnt）。
///////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps

module tb_t11_r10f_e2e;

    // ---------------- 时钟 / 复位 ----------------
    reg clk_cam = 0, clk_fb = 0, clk_ddr = 0;
    always #3  clk_cam = ~clk_cam;
    always #8  clk_fb  = ~clk_fb;
    always #5  clk_ddr = ~clk_ddr;
    reg rst_cam_n = 0;
    reg wr_rst    = 1;

    localparam integer W = 8, H = 4, GPR = 2, WC_LINE = 10, LINES = 4;
    localparam integer DMA = 4096, NTLP = DMA/128;
    localparam [31:0] BASE0 = 32'h0010_0000, BASE1 = 32'h0010_2000;
    localparam [31:0] SES   = 32'h2026_1017;
    localparam [31:0] SES2  = 32'h2026_1018;      // E4 新会话
    localparam [63:0] DST   = 64'h0000_0002_0000_0080;
    localparam [63:0] DB    = 64'h0000_0003_0000_0100;

    integer errors = 0;
    task chk(input cond, input [8*96-1:0] msg);
        begin
            if (!cond) begin
                errors = errors + 1;
                if (errors <= 40) $display("  ERROR #%0d @%0t : %s", errors, $time, msg);
            end
        end
    endtask

    function [31:0] crc32_b;
        input [31:0] c; input [7:0] b;
        reg [31:0] v; integer k; reg fb;
        begin
            v = c ^ {24'd0, b};
            for (k = 0; k < 8; k = k + 1) begin
                fb = v[0]; v = v >> 1;
                if (fb) v = v ^ 32'hEDB88320;
            end
            crc32_b = v;
        end
    endfunction

    // ---------------- CSI 注入（32bit 字/拍）----------------
    reg        sim_valid = 0, sim_pktdone = 0;
    reg [31:0] sim_data = 0;
    wire        o_byte_clk, o_rst_out;
    wire        o_sync_wait, o_packet_done, o_vsync, o_in_frame, o_in_line;
    wire [39:0] o_pixel; wire o_pixel_valid;
    wire        o_frame_end, o_frame_good, o_frame_abort;
    wire [31:0] o_crc_err, o_hdr_err, o_pkt_to, o_frm_to, o_good_frm, o_bad_frm;
    wire [15:0] o_last_wc, o_last_lines;
    wire [31:0] o_payload; wire [3:0] o_keep; wire o_payload_v;

    mipi_csi2_rx_ph1p_checked #(
        .LANE_NUM(4), .IMAGE_DT(6'h2b), .IMAGE_WC(WC_LINE), .EXPECTED_LINES(LINES),
        .VC_ID(2'd0), .CHECK_FRAME_ID(1'b0),
        .PACKET_IDLE_CYCLES(32'd32), .FRAME_TIMEOUT_CYCLES(32'd50000)
    ) u_csi (
        .I_ref_clk(clk_cam), .I_rst_n(rst_cam_n), .I_rx_en(rst_cam_n),
        .I_clk_pad_hs_p(1'b0), .I_clk_pad_hs_n(1'b0),
        .I_data_pad_hs_p(4'd0), .I_data_pad_hs_n(4'd0),
        .I_manual_delay(6'd0), .I_manual_en(1'b0),
        .O_byte_clk(o_byte_clk), .O_rst_out(o_rst_out),
        .O_lane_valid(), .O_delay_tap(), .O_auto_delay_done(),
        .O_sync_wait(o_sync_wait), .O_packet_done(o_packet_done),
        .O_vsync(o_vsync), .O_in_frame(o_in_frame), .O_in_line(o_in_line),
        .O_pixel_data(o_pixel), .O_pixel_valid(o_pixel_valid),
        .O_frame_end(o_frame_end), .O_frame_good(o_frame_good), .O_frame_abort(o_frame_abort),
        .O_crc_errors(o_crc_err), .O_header_errors(o_hdr_err),
        .O_packet_timeouts(o_pkt_to), .O_frame_timeouts(o_frm_to),
        .O_good_frames(o_good_frm), .O_bad_frames(o_bad_frm),
        .O_last_wc(o_last_wc), .O_last_lines(o_last_lines),
        .O_payload_out(o_payload), .O_payload_keep(o_keep), .O_payload_valid(o_payload_v),
        .I_sim_word_valid(sim_valid), .I_sim_word_data(sim_data), .I_sim_packet_done(sim_pktdone)
    );

    function [7:0] hdr_ecc;
        input [23:0] d;
        integer i;
        reg [7:0] e, m;
        begin
            e = 8'h00;
            for (i = 0; i < 24; i = i + 1) begin
                case (i)
                    0:  m = 8'h07; 1:  m = 8'h0B; 2:  m = 8'h0D; 3:  m = 8'h0E;
                    4:  m = 8'h13; 5:  m = 8'h15; 6:  m = 8'h16; 7:  m = 8'h19;
                    8:  m = 8'h1A; 9:  m = 8'h1C; 10: m = 8'h23; 11: m = 8'h25;
                    12: m = 8'h26; 13: m = 8'h29; 14: m = 8'h2A; 15: m = 8'h2C;
                    16: m = 8'h31; 17: m = 8'h32; 18: m = 8'h34; 19: m = 8'h38;
                    20: m = 8'h1F; 21: m = 8'h2F; 22: m = 8'h37; default: m = 8'h3B;
                endcase
                if (d[i]) e = e ^ m;
            end
            hdr_ecc = e;
        end
    endfunction

    function [15:0] crc16_b;
        input [15:0] c; input [7:0] b;
        reg [15:0] v; integer k; reg fb;
        begin
            v = c ^ {8'd0, b};
            for (k = 0; k < 8; k = k + 1) begin
                fb = v[0]; v = v >> 1;
                if (fb) v = v ^ 16'h8408;
            end
            crc16_b = v;
        end
    endfunction

    task send_word(input [31:0] w);
        begin
            @(negedge clk_cam); sim_data = w; sim_valid = 1'b1;
            @(negedge clk_cam); sim_valid = 1'b0; sim_pktdone = 1'b1;
            @(negedge clk_cam); sim_pktdone = 1'b0;
        end
    endtask
    task gap(input integer n);
        begin
            sim_valid = 0; repeat (n) @(negedge clk_cam);
        end
    endtask
    task send_short(input [5:0] dt, input [15:0] fid);
        reg [23:0] d; reg [7:0] e;
        begin
            d = {fid, 2'b00, dt}; e = hdr_ecc(d);
            send_word({e, d});
        end
    endtask
    // 长包：WC=10（2 组 4 像素 = 10 字节）+ 2 字节 CRC → 12 字节 = 3 字
    task send_long(input integer first_pix);
        integer i, wi;
        reg [7:0] byt [0:15];
        reg [15:0] crc;
        reg [23:0] hd; reg [7:0] he;
        reg [31:0] word;
        reg [9:0] pp [0:3];
        integer pidx;
        begin
            for (i = 0; i < GPR; i = i + 1) begin
                for (wi = 0; wi < 4; wi = wi + 1) begin
                    pidx = first_pix + i*4 + wi;
                    pp[wi] = (pidx % 4 == 0) ? 10'd0 :
                             (pidx % 4 == 1) ? 10'd1 :
                             (pidx % 4 == 2) ? 10'd1022 : 10'd1023;
                end
                byt[i*5+0] = pp[0][9:2]; byt[i*5+1] = pp[1][9:2];
                byt[i*5+2] = pp[2][9:2]; byt[i*5+3] = pp[3][9:2];
                byt[i*5+4] = {pp[3][1:0], pp[2][1:0], pp[1][1:0], pp[0][1:0]};
            end
            crc = 16'hFFFF;
            for (i = 0; i < WC_LINE; i = i + 1) crc = crc16_b(crc, byt[i]);
            byt[WC_LINE] = crc[7:0]; byt[WC_LINE+1] = crc[15:8];
            hd = {WC_LINE[15:0], 2'b00, 6'h2b};
            he = hdr_ecc(hd);
            send_word({he, hd});
            for (wi = 0; wi < 3; wi = wi + 1) begin
                word = 32'd0;
                for (i = 0; i < 4; i = i + 1) begin
                    if ((wi*4+i) < WC_LINE+2) word[i*8 +: 8] = byt[wi*4+i];
                end
                send_word(word);
            end
        end
    endtask
    task send_frame;
        integer ln;
        begin
            sim_pktdone = 0;
            send_short(6'h00, 16'h0001); gap(4);
            for (ln = 0; ln < LINES; ln = ln + 1) begin
                send_long(ln*W);
                gap(3);
            end
            send_short(6'h01, 16'h0001); gap(4);
        end
    endtask

    // ---------------- writer（真实 R10F 写者）----------------
    wire [31:0] w_seq, w_base, w_status, w_len;
    wire        w_awvalid, w_awready, w_wvalid, w_wready, w_bvalid, w_bready, w_wlast;
    wire [28:0] w_awaddr; wire [7:0] w_awlen; wire [2:0] w_awsize; wire [1:0] w_awburst;
    wire [255:0] w_wdata; wire [31:0] w_wstrb; wire [1:0] w_bresp;
    wire        rel0, rel1;
    reg  [31:0] sess_live = SES;          // 写者采样的会话号（E4 切新会话）

    cam_r10f_writer #(
        .W(W), .H(H), .X0(16'd0), .Y0(16'd0), .SKIP_ROWS(16'd0),
        .BASE0(BASE0), .BASE1(BASE1), .FIFO_AW(10), .BURST_BEATS(128),
        .CAMERA_ID(8'd0), .SRC_BAYER_PHASE(2'd3), .MODE_ID(32'd1), .TMO_LIMIT(21'd4095)
    ) u_wr (
        .cam_clk(o_byte_clk), .cam_rst_n(o_rst_out),
        .cam_vsync(o_vsync), .cam_in_frame(o_in_frame), .cam_in_line(o_in_line),
        .cam_pix(o_pixel), .cam_pix_valid(o_pixel_valid),
        .cam_frame_good(o_frame_good), .cam_frame_abort(o_frame_abort),
        .prot_en(1'b1), .rel_tgl0(rel0), .rel_tgl1(rel1),
        .clk_fb(clk_fb), .rst_fb(wr_rst), .session_id(sess_live),
        .wr_frame_seq(w_seq), .wr_base(w_base), .wr_status(w_status), .wr_len(w_len),
        .dbg_lines_per_frame(), .dbg_max_grp_per_line(), .dbg_anomaly(), .dbg_drop(),
        .clk_ddr(clk_ddr), .rst_ddr(wr_rst), .ddr_cal_done(1'b1), .arm(1'b1),
        .axi_busy(),
        .m_axi_awaddr(w_awaddr), .m_axi_awlen(w_awlen), .m_axi_awsize(w_awsize),
        .m_axi_awburst(w_awburst), .m_axi_awvalid(w_awvalid), .m_axi_awready(w_awready),
        .m_axi_wdata(w_wdata), .m_axi_wstrb(w_wstrb), .m_axi_wlast(w_wlast),
        .m_axi_wvalid(w_wvalid), .m_axi_wready(w_wready),
        .m_axi_bresp(w_bresp), .m_axi_bvalid(w_bvalid), .m_axi_bready(w_bready)
    );

    // ---------------- 假 DDR（写侧更新 / 读侧供推帧）----------------
    reg [7:0] ddrm [0:16383];      // addr[13:0]（BASE0→0、BASE1→0x2000）
    integer   dd_wr_beats = 0, dd_rd_beats = 0, dd_4k_err = 0;
    reg [28:0] dd_awq = 0; reg [7:0] dd_awlenq = 0; integer dd_bib = 0; integer di;
    reg        dd_bpend = 0; reg [7:0] dd_bcnt = 0;
    assign w_awready = wr_rst ? 1'b0 : 1'b1;
    assign w_wready  = wr_rst ? 1'b0 : 1'b1;
    assign w_bresp   = 2'b00;
    assign w_bvalid  = dd_bpend && (dd_bcnt == 8'd0);
    assign w_bready  = 1'b1;

    always @(posedge clk_ddr) begin
        if (w_awvalid && w_awready) begin
            dd_awq    <= w_awaddr;
            dd_awlenq <= w_awlen;
            dd_bib     = 0;
            dd_bcnt   <= w_awlen + 8'd1;
            dd_bpend  <= 1'b1;
            if (((w_awaddr & 29'd4095) + (w_awlen + 29'd1)*29'd32) > 29'd4096) dd_4k_err = dd_4k_err + 1;
        end
        if (w_wvalid && w_wready) begin
            dd_wr_beats = dd_wr_beats + 1;
            for (di = 0; di < 32; di = di + 1)
                if (w_wstrb[di]) ddrm[(dd_awq[13:0] + dd_bib*32 + di)] <= w_wdata[di*8 +: 8];
            dd_bib = dd_bib + 1;
            if (dd_bcnt != 8'd0) dd_bcnt <= dd_bcnt - 8'd1;
        end
        if (w_bvalid && w_bready) dd_bpend <= 1'b0;
    end

    // ---------------- pusher（真实 one-shot 发送）----------------
    reg         push_en = 0;
    reg         arm_p = 0, ack_p = 0, cancel_p = 0;
    reg  [31:0] cap_r = 0, sess_r = 0, ack_seq_r = 0, ack_sess_r = 0;
    wire [31:0] st_done, st_status, st_tlp_cnt;
    wire [7:0]  st_err;
    wire        utx_req, utx_sop, utx_eop;
    wire [255:0] utx_data;
    wire [7:0]  utx_valid;
    reg         utx_sel = 0, tl_tx_wait = 0;
    wire [31:0] tx_status;
    wire        tx_block_cfg, tx_src_lock;
    wire [3:0]  p_arid, p_rid;
    wire [28:0] p_araddr;
    wire [7:0]  p_arlen;
    wire [2:0]  p_arsize;
    wire [1:0]  p_arburst;
    wire        p_arvalid, p_arready, p_rlast, p_rvalid, p_rready;
    wire [255:0] p_rdata;
    wire [1:0]  p_rresp;

    ddr_frame_pusher #(
        .W(W), .H(H), .PAY_DW(32), .FIFO_AW(7), .BURST_BEATS(128),
        .WAIT_LIMIT(16'hFFFF),
        .BASE0(BASE0), .BASE1(BASE1), .BASE0B(BASE0), .BASE1B(BASE1),
        .MAX_FRAME_BYTES(3840*2160)
    ) u_push (
        .clk_fb(clk_fb), .rst_fb(wr_rst),
        .push_en(push_en), .src_sel(1'b0),
        .fb_frame_cnt(32'd0), .fb_rd_addr(), .fb_rd_data(32'd0),
        .fb_req(), .fb_grant(1'b0), .src_act(), .fb_hold(),
        .dst_lo(DST[31:0]), .dst_hi(DST[63:32]),
        .db_lo(DB[31:0]), .db_hi(DB[63:32]),
        .st_done(st_done), .st_status(st_status), .st_err(st_err), .st_tlp_cnt(st_tlp_cnt),
        .frame_bytes(w_len),
        .ddr_seq(w_seq), .ddr_base(w_base), .ddr_status(w_status),
        .utx_sel(utx_sel), .tl_tx_wait(tl_tx_wait),
        .utx_req(utx_req), .utx_data(utx_data), .utx_sop(utx_sop),
        .utx_eop(utx_eop), .utx_valid(utx_valid),
        .arm_pulse(arm_p), .ack_pulse(ack_p), .cancel_pulse(cancel_p),
        .cap_bytes(cap_r), .session_id(sess_r),
        .ack_seq_w(ack_seq_r), .ack_session_w(ack_sess_r),
        .cfg_reject(1'b0), .link_up(1'b1), .mps_code(3'd0),
        .ddr_cap_bytes(32'h1000_0000), .cam_sel_live(1'b0),
        .tx_status(tx_status), .tx_block_cfg(tx_block_cfg),
        .rel_tgl0(rel0), .rel_tgl1(rel1), .rel_tgl2(), .rel_tgl3(),
        .tx_src_lock(tx_src_lock),
        .clk_ddr(clk_ddr), .rst_ddr(wr_rst),
        .m_axi_arid(p_arid), .m_axi_araddr(p_araddr), .m_axi_arlen(p_arlen),
        .m_axi_arsize(p_arsize), .m_axi_arburst(p_arburst),
        .m_axi_arvalid(p_arvalid), .m_axi_arready(p_arready),
        .m_axi_rid(p_rid), .m_axi_rdata(p_rdata), .m_axi_rresp(p_rresp),
        .m_axi_rlast(p_rlast), .m_axi_rvalid(p_rvalid), .m_axi_rready(p_rready)
    );

    // AXI 读从机：4KB 突发，从 ddrm 取数
    reg         rd_busy = 0;
    reg [28:0]  rd_addr = 0;
    integer     rd_beat = 0;
    reg         rd_vld = 0, rd_last = 0;
    reg [255:0] rd_data = 0;
    assign p_arready = ~rd_busy & ~wr_rst;
    assign p_rvalid  = rd_vld;
    assign p_rlast   = rd_last;
    assign p_rdata   = rd_data;
    assign p_rid     = 4'd0;
    assign p_rresp   = 2'b00;

    function [255:0] ddr_beat;
        input [28:0] byte_addr;
        integer q;
        begin
            ddr_beat = 256'd0;
            for (q = 0; q < 32; q = q + 1)
                ddr_beat[q*8 +: 8] = ddrm[byte_addr[13:0] + q];
        end
    endfunction

    always @(posedge clk_ddr) begin
        if (wr_rst) begin
            rd_busy <= 0; rd_vld <= 0; rd_last <= 0; rd_beat = 0;
        end else if (!rd_busy) begin
            if (p_arvalid && p_arready) begin
                rd_busy <= 1; rd_addr <= p_araddr; rd_beat = 0; rd_vld <= 1;
                rd_data <= ddr_beat({p_araddr[28:5], 5'd0} + 0);
                rd_last <= (p_arlen == 8'd0);
            end
        end else if (rd_vld && p_rready) begin
            dd_rd_beats = dd_rd_beats + 1;
            if (rd_last) begin
                rd_busy <= 0; rd_vld <= 0; rd_last <= 0;
            end else begin
                // 注意：rd_beat 是阻塞赋值 ⇒ 必须先用旧值算 rd_data/rd_last 再自增
                rd_data <= ddr_beat({rd_addr[28:5], 5'd0} + rd_beat*32 + 32);
                rd_last <= (rd_beat + 1 == {23'd0, p_arlen});
                rd_beat = rd_beat + 1;
            end
        end
    end

    // ---------------- TL 口仿真（引擎让路逻辑，与 pusher TB 相同口径）----------------
    always @(posedge clk_fb) begin
        if (wr_rst) utx_sel <= 0;
        else if (!utx_sel) begin
            if (utx_req) utx_sel <= 1;
        end else if (utx_eop && (|utx_valid)) begin
            utx_sel <= 0;
        end
    end

    // ---------------- 独立 TL 监视器 + host 模型 ----------------
    // 每个发送段开始前由主流程复位（tlp_idx/db_cnt/db_exp），段内单调。
    reg [7:0]  tbytes [0:255];
    integer    nb = 0, beat_cnt_tlp = 0, tlp_idx = 0, db_cnt = 0;
    integer    tlp_total = 0;
    integer    db_exp = 1;
    reg [7:0]  host [0:4095];
    reg [255:0] prev_data = 0; reg prev_sel = 0, prev_wait = 0, prev_eop = 0;
    reg [7:0]   prev_valid = 0; reg prev_up = 0;
    integer     mon_mismatch = 0;

    task mon_reset(input integer exp_db);
        begin
            tlp_idx = 0; db_cnt = 0; db_exp = exp_db;
        end
    endtask

    task push_beat(input [255:0] d, input [7:0] v);
        integer n;
        begin
            for (n = 7; n >= 0; n = n - 1) begin
                if (v[n]) begin
                    tbytes[nb+0] = d[32*n + 31 -: 8];
                    tbytes[nb+1] = d[32*n + 23 -: 8];
                    tbytes[nb+2] = d[32*n + 15 -: 8];
                    tbytes[nb+3] = d[32*n +  7 -: 8];
                    nb = nb + 4;
                end
            end
        end
    endtask

    integer kk, pi;
    reg [31:0] dw0, dw1, dw2, dw3;
    reg [63:0] exp_addr;
    always @(posedge clk_fb) begin
        if (!wr_rst) begin
            if (prev_up && !(prev_sel && !prev_wait)) begin
                chk((utx_data === prev_data) && (utx_eop === prev_eop) &&
                    (utx_valid === prev_valid), "TL beat not held during wait");
            end
            prev_up <= (|utx_valid); prev_sel <= utx_sel; prev_wait <= tl_tx_wait;
            prev_data <= utx_data; prev_eop <= utx_eop; prev_valid <= utx_valid;

            if (utx_sel && !tl_tx_wait && (|utx_valid)) begin
                if (utx_sop) begin nb = 0; beat_cnt_tlp = 0; end
                push_beat(utx_data, utx_valid);
                beat_cnt_tlp = beat_cnt_tlp + 1;
                if (utx_eop) begin
                    dw0 = {tbytes[0],tbytes[1],tbytes[2],tbytes[3]};
                    dw1 = {tbytes[4],tbytes[5],tbytes[6],tbytes[7]};
                    dw2 = {tbytes[8],tbytes[9],tbytes[10],tbytes[11]};
                    dw3 = {tbytes[12],tbytes[13],tbytes[14],tbytes[15]};
                    tlp_total = tlp_total + 1;
                    if (tlp_idx < NTLP) begin
                        // 数据 MWr：5 拍
                        chk(beat_cnt_tlp == 5, "data MWr beat count != 5");
                        chk(dw0[31:29] == 3'b011, "Fmt != 4DW+data");
                        chk(dw0[28:24] == 5'b0_0000, "Type != MWR");
                        chk(dw0[9:0] == 32, "Length != 32");
                        chk(dw1[31:16] == 16'h0100, "RequesterID != 01:00.0");
                        chk(dw1[15:8] == 8'h0, "Tag != 0");
                        chk(dw1[7:4] == 4'hf, "LastDWBE != F");
                        chk(dw1[3:0] == 4'hf, "FirstDWBE != F");
                        exp_addr = DST + tlp_idx*128;
                        chk(dw2 == exp_addr[63:32], "addr hi32 wrong");
                        chk(dw3 == {exp_addr[31:2], 2'b00}, "addr lo30 wrong");
                        // 装配 host 模型
                        for (kk = 0; kk < 128; kk = kk + 1)
                            host[tlp_idx*128 + kk] = tbytes[16+kk];
                    end else begin
                        // 门铃：4DW 头 + 单 DW（与 peer 格式一致）
                        chk(beat_cnt_tlp == 1, "doorbell beat count != 1");
                        chk(dw0[31:29] == 3'b011, "doorbell Fmt != 4DW");
                        chk(dw0[9:0] == 1, "doorbell length != 1");
                        chk(dw1[7:4] == 4'h0, "doorbell LastDWBE != 0");
                        chk(dw1[3:0] == 4'hf, "doorbell FirstDWBE != F");
                        chk(dw2 == DB[63:32], "doorbell hi32 wrong");
                        chk(dw3 == {DB[31:2], 2'b00}, "doorbell lo30 wrong");
                        chk({tbytes[19],tbytes[18],tbytes[17],tbytes[16]} == (db_exp + db_cnt),
                            "doorbell value wrong");
                        db_cnt = db_cnt + 1;
                    end
                    tlp_idx = tlp_idx + 1;
                end
            end
        end
    end

    // ---------------- 期望内容模型（按相位参数化：头随 seq/session 变）----------------
    // 冻结向量（r10f-small-synthetic.dma）的像素模式：每组重复 [0,1,1022,1023]
    // 载荷字节模型（b = 载荷内字节 0..39）
    function [7:0] exp_pay_byte;
        input integer b;
        integer g, r;
        begin
            g = b / 5; r = b % 5;
            case (r)
                0: exp_pay_byte = 8'h00;   // P0=0     → [9:2]=0x00
                1: exp_pay_byte = 8'h00;   // P1=1     → [9:2]=0x00
                2: exp_pay_byte = 8'hFF;   // P2=1022  → [9:2]=0xFF
                3: exp_pay_byte = 8'hFF;   // P3=1023  → [9:2]=0xFF
                default: exp_pay_byte = 8'hE4; // {P3,P2,P1,P0}低2bit = {11,10,01,00}
            endcase
        end
    endfunction

    reg [7:0] ehdr [0:127];
    integer   q;
    task build_hdr(input [31:0] seq, input [31:0] sess, input [7:0] cam_id);
        reg [31:0] pc;
        begin
            for (q = 0; q < 128; q = q + 1) ehdr[q] = 8'h00;
            ehdr[0]=8'h52; ehdr[1]=8'h31; ehdr[2]=8'h30; ehdr[3]=8'h46;     // "R10F"
            ehdr[4]=8'h01; ehdr[5]=8'h00;                                   // version 1.0
            ehdr[8]=8'h80; ehdr[9]=8'h00;                                   // header_bytes=128
            ehdr[10]=cam_id; ehdr[11]=8'h00;                                // camera_id / format=0
            // codec_id(0x0C)=0
            ehdr[16]=sess[7:0];  ehdr[17]=sess[15:8];  ehdr[18]=sess[23:16]; ehdr[19]=sess[31:24];
            ehdr[20]=seq[7:0];   ehdr[21]=seq[15:8];   ehdr[22]=seq[23:16];  ehdr[23]=seq[31:24];
            ehdr[24]=8'h01;                                                 // mode_id=1
            ehdr[28]=W[7:0]; ehdr[29]=W[15:8];                              // width
            ehdr[30]=H[7:0]; ehdr[31]=H[15:8];                              // height
            ehdr[32]=8'd10;                                                 // stride_bytes=10
            // roi_x/roi_y=0（0x24..0x27）
            ehdr[40]=8'h03; ehdr[41]=8'h00; ehdr[42]=8'h0A; ehdr[43]=8'h00;// phase=3/dir=0/bits=10/pack=0
            ehdr[44]=8'd40;                                                 // raw_bytes=40
            ehdr[48]=8'd40;                                                 // payload_bytes=40
            ehdr[52]=8'h01;                                                 // block_count=1
            // flags(0x4C)=0；exposure/gain/ts 全 0
            pc = 32'hFFFF_FFFF;
            for (q = 0; q < 40; q = q + 1) pc = crc32_b(pc, exp_pay_byte(q));
            pc = ~pc;
            ehdr[80]=pc[7:0]; ehdr[81]=pc[15:8]; ehdr[82]=pc[23:16]; ehdr[83]=pc[31:24]; // raw_crc32
            ehdr[84]=pc[7:0]; ehdr[85]=pc[15:8]; ehdr[86]=pc[23:16]; ehdr[87]=pc[31:24]; // payload_crc32
            ehdr[88]=0; ehdr[89]=0; ehdr[90]=0; ehdr[91]=0;                 // header_crc 自清
            pc = 32'hFFFF_FFFF;
            for (q = 0; q < 128; q = q + 1) pc = crc32_b(pc, ehdr[q]);
            pc = ~pc;
            ehdr[88]=pc[7:0]; ehdr[89]=pc[15:8]; ehdr[90]=pc[23:16]; ehdr[91]=pc[31:24];
            $display("  [model] seq=%0d sess=%08h hdrcrc=%08h paycrc=%08h",
                     seq, sess, pc, {ehdr[83],ehdr[82],ehdr[81],ehdr[80]});
        end
    endtask

    function [7:0] exp_byte;
        input integer b;
        begin
            if (b < 128)          exp_byte = ehdr[b];
            else if (b < 168)     exp_byte = exp_pay_byte(b-128);
            else                  exp_byte = 8'h00;
        end
    endfunction

    // ---------------- 主流程 ----------------
    integer t2, mm, fd;
    reg [31:0] hc32;
    integer rel0_cnt = 0, rel1_cnt = 0;
    integer tl_total_before = 0;
    reg prev_rel0 = 0, prev_rel1 = 0;
    always @(posedge clk_ddr) begin
        if (rel0 !== prev_rel0) rel0_cnt = rel0_cnt + 1;   // toggle：数边沿（每次事件翻转一次）
        if (rel1 !== prev_rel1) rel1_cnt = rel1_cnt + 1;
        prev_rel0 <= rel0; prev_rel1 <= rel1;
    end

    task arm_now;
        begin
            @(negedge clk_fb); arm_p = 1;
            @(negedge clk_fb); arm_p = 0;
            repeat (20) @(posedge clk_fb);
        end
    endtask
    task ack_now(input [31:0] seq, input [31:0] sess);
        begin
            ack_seq_r = seq; ack_sess_r = sess;
            @(negedge clk_fb); ack_p = 1;
            @(negedge clk_fb); ack_p = 0;
            repeat (40) @(posedge clk_fb);
        end
    endtask
    task wait_wr_idle(input integer limit);
        begin
            t2 = 0;
            while ((u_wr.s_state != 3'd0) && (t2 < limit)) begin @(posedge clk_fb); t2 = t2 + 1; end
        end
    endtask
    task wait_done(input [31:0] n, input integer limit);
        begin
            t2 = 0;
            while ((st_done != n) && (t2 < limit)) begin @(posedge clk_fb); t2 = t2 + 1; end
            repeat (40) @(posedge clk_fb);
        end
    endtask
    task host_check(input [8*96-1:0] tag);
        begin
            mm = 0;
            for (kk = 0; kk < DMA; kk = kk + 1)
                if (host[kk] !== exp_byte(kk)) begin
                    if (mm < 6) $display("  HOSTMIS[%0s] k=%0d got=%02h exp=%02h", tag, kk, host[kk], exp_byte(kk));
                    mm = mm + 1;
                end
            chk(mm == 0, {tag, ": host content != model"});
            // 载荷 CRC 独立重算（对收到的 host 内容）
            hc32 = 32'hFFFF_FFFF;
            for (kk = 128; kk < 168; kk = kk + 1) hc32 = crc32_b(hc32, host[kk]);
            chk(~hc32 == {host[8'h57],host[8'h56],host[8'h55],host[8'h54]},
                {tag, ": payload crc field != recompute"});
            // 头 CRC 独立重算（0x58..5B 清 0）
            hc32 = 32'hFFFF_FFFF;
            for (kk = 0; kk < 128; kk = kk + 1)
                hc32 = crc32_b(hc32, ((kk >= 8'h58) && (kk <= 8'h5B)) ? 8'h00 : host[kk]);
            chk(~hc32 == {host[8'h5B],host[8'h5A],host[8'h59],host[8'h58]},
                {tag, ": header crc field != recompute"});
        end
    endtask

    initial begin
        rst_cam_n = 0; wr_rst = 1; push_en = 0;
        #100; rst_cam_n = 1; #400; wr_rst = 0; #400;
        repeat (30) @(negedge clk_cam);

        // ---------- E0：未 ARM 出一帧 → 发布但 0 TLP（错误码 5）+ 块 release ----------
        $display("=== E0 未 ARM：出帧 → 无 TLP + E_NOT_ARM + release ===");
        push_en = 1;
        mon_reset(1);
        send_frame;
        repeat (400) @(negedge clk_cam);
        wait_wr_idle(2000000);
        repeat (60) @(posedge clk_fb);
        chk(w_seq == 1, "E0: writer did not publish frame 1");
        chk(w_base == BASE0, "E0: frame1 base != BASE0");
        chk(w_len == DMA, "E0: wr_len != 4096");
        chk(tx_status[0] == 1'b0, "E0: armed without ARM");
        chk(tlp_total == 0, "E0: TLP sent without ARM");
        chk(st_err == 8'd5, "E0: st_err != 5 (E_NOT_ARM)");
        repeat (20) @(posedge clk_ddr);
        chk(rel0_cnt == 1, "E0: block0 not released exactly once");
        chk(rel1_cnt == 0, "E0: block1 released spuriously");

        // ---------- E1：ARM → 帧2（block1，seq=2）→ 发送 → held → 错 ACK → 匹配 ACK ----------
        $display("=== E1 ARM → 帧2（block1）→ 32 MWr + 1 门铃 → held → ACK ===");
        cap_r = DMA; sess_r = SES;
        arm_now;
        chk(tx_status[0] == 1'b1, "E1: not armed after ARM");
        mon_reset(1);
        build_hdr(32'd2, SES, 8'd0);
        send_frame;
        repeat (400) @(negedge clk_cam);
        wait_wr_idle(2000000);
        repeat (60) @(posedge clk_fb);
        chk(w_seq == 2, "E1: writer seq != 2");
        chk(w_base == BASE1, "E1: writer base != BASE1");
        chk(o_good_frm == 2, "E1: CSI good_frames != 2");
        wait_done(32'd1, 400000);
        chk(st_done == 1, "E1: st_done != 1");
        chk(st_err == 8'd0, "E1: push err != 0");
        chk(st_tlp_cnt == NTLP, "E1: MWr count != 32");
        chk(tx_status[2] == 1'b1, "E1: not held after completion");
        chk(tlp_total == NTLP + 1, "E1: TLP total != 33 (32 data + 1 doorbell)");
        chk(db_cnt == 1, "E1: doorbell count != 1");
        host_check("E1");
        // 错 seq ACK ⇒ 不释放
        ack_now(32'd7, SES);
        chk(tx_status[2] == 1'b1, "E1: wrong-seq ACK released held");
        // 错 session ACK ⇒ 不释放
        ack_now(32'd1, SES + 32'd1);
        chk(tx_status[2] == 1'b1, "E1: wrong-session ACK released held");
        chk(st_err == 8'd11, "E1: bad ack not flagged (err != 11)");
        // 匹配 ACK ⇒ 释放 + 块1 release 恰好 +1
        ack_now(32'd1, SES);
        chk(tx_status[2] == 1'b0, "E1: matched ACK did not release");
        repeat (20) @(posedge clk_ddr);
        chk(rel1_cnt == 1, "E1: block1 not released on ACK");
        chk(rel0_cnt == 1, "E1: block0 released again");

        // ---------- E2：再 ARM → 帧3（block0，seq=3）→ 发送（门铃=2）→ ACK ----------
        $display("=== E2 再 ARM → 帧3（block0，seq=3）→ 发送 → ACK ===");
        arm_now;
        chk(tx_status[0] == 1'b1, "E2: not armed after re-ARM");
        mon_reset(2);
        build_hdr(32'd3, SES, 8'd0);
        send_frame;
        repeat (400) @(negedge clk_cam);
        wait_wr_idle(2000000);
        repeat (60) @(posedge clk_fb);
        chk(w_seq == 3, "E2: writer seq != 3");
        chk(w_base == BASE0, "E2: writer base != BASE0");
        wait_done(32'd2, 400000);
        chk(st_done == 2, "E2: st_done != 2");
        chk(st_err == 8'd0, "E2: push err != 0");
        chk(tlp_total == 2*(NTLP+1), "E2: TLP total != 66");
        chk(db_cnt == 1, "E2: doorbell count != 1");
        host_check("E2");
        ack_now(32'd2, SES);
        chk(tx_status[2] == 1'b0, "E2: matched ACK did not release");
        repeat (20) @(posedge clk_ddr);
        $display("  E2 RELDBG rel0=%0d rel1=%0d", rel0_cnt, rel1_cnt);
        chk(rel0_cnt == 2, "E2: block0 not released on ACK");

        // ---------- E3：慢消费（TL 长 wait）→ held 期间新帧不发（错误码 8）→ ACK ----------
        $display("=== E3 慢消费长 wait → held 保护 → 新帧拒绝(8) → ACK ===");
        arm_now;
        chk(tx_status[0] == 1'b1, "E3: not armed");
        mon_reset(3);
        build_hdr(32'd4, SES, 8'd0);
        send_frame;
        repeat (60) @(negedge clk_cam);
        tl_tx_wait = 1;                       // 拉长 wait：已开包必须逐拍持稳
        repeat (700) @(posedge clk_fb);
        tl_tx_wait = 0;
        repeat (400) @(negedge clk_cam);
        wait_wr_idle(3000000);
        wait_done(32'd3, 400000);
        chk(st_done == 3, "E3: st_done != 3");
        chk(st_err == 8'd0, "E3: push err != 0");
        chk(tlp_total == 3*(NTLP+1), "E3: TLP total != 99");
        host_check("E3");
        // held 期间该块仍被写者保护（block1），且 release 未提前
        repeat (30) @(posedge clk_ddr);
        chk(u_wr.protect1 == 1'b1, "E3: held block not protected");
        chk(rel1_cnt == 1, "E3: block1 released while held");
        // held 期间源继续出帧 ⇒ 不发（错误码 8），也不覆盖 held 槽
        send_frame;
        repeat (400) @(negedge clk_cam);
        wait_wr_idle(3000000);
        repeat (60) @(posedge clk_fb);
        chk(w_seq == 5, "E3: frame5 not published");
        chk(tlp_total == 3*(NTLP+1), "E3: frame sent while held");
        chk(st_err == 8'd8, "E3: held rejection not flagged (err != 8)");
        chk(tx_status[2] == 1'b1, "E3: held lost");
        ack_now(32'd3, SES);
        chk(tx_status[2] == 1'b0, "E3: matched ACK did not release");
        repeat (30) @(posedge clk_ddr);
        $display("  E3 RELDBG rel0=%0d rel1=%0d", rel0_cnt, rel1_cnt);
        chk(rel1_cnt == 2, "E3: block1 not released on ACK");

        // ---------- E4：held 未 ACK 时复位 → 旧会话不清账；新 session 全流程 ----------
        $display("=== E4 reset 隔离 + 新 session 全流程 ===");
        arm_now;
        chk(tx_status[0] == 1'b1, "E4: not armed");
        mon_reset(4);
        build_hdr(32'd6, SES, 8'd0);
        send_frame;
        repeat (400) @(negedge clk_cam);
        wait_wr_idle(3000000);
        wait_done(32'd4, 400000);
        chk(st_done == 4, "E4: st_done != 4");
        chk(tx_status[2] == 1'b1, "E4: not held before reset");
        host_check("E4a");
        // 复位：held/armed 清、源回 SYNC、旧 hold 不产生门铃；复位后无 TLP
        tl_total_before = tlp_total;
        wr_rst = 1;
        repeat (60) @(posedge clk_fb);
        repeat (60) @(posedge clk_ddr);
        wr_rst = 0;
        repeat (100) @(posedge clk_fb);
        chk(tx_status == 32'd0, "E4: TX_STATUS not cleared by reset");
        chk(st_done == 0, "E4: st_done not cleared by reset");
        chk(tlp_total == tl_total_before, "E4: TLP after reset without new ARM");
        chk(w_seq == 0, "E4: writer seq not cleared by reset");
        chk(rel1_cnt == 2, "E4: reset produced release event");
        // 新会话：先出一帧（热身）→ ARM（要求已发布帧）→ 帧2 → 发送
        sess_live = SES2;
        push_en = 1;
        repeat (40) @(negedge clk_cam);
        send_frame;
        repeat (400) @(negedge clk_cam);
        wait_wr_idle(3000000);
        repeat (60) @(posedge clk_fb);
        chk(w_seq == 1, "E4: new-session frame1 not published");
        sess_r = SES2;
        arm_now;
        chk(tx_status[0] == 1'b1, "E4: not armed (new session)");
        mon_reset(1);
        build_hdr(32'd2, SES2, 8'd0);
        send_frame;
        repeat (400) @(negedge clk_cam);
        wait_wr_idle(3000000);
        repeat (60) @(posedge clk_fb);
        chk(w_seq == 2, "E4: new-session frame2 not published");
        wait_done(32'd1, 400000);
        chk(st_done == 1, "E4: new-session st_done != 1");
        chk(st_err == 8'd0, "E4: new-session push err != 0");
        chk(tlp_total == tl_total_before + (NTLP+1), "E4: new-session TLP total wrong");
        host_check("E4b");
        // 头里的 session 必须是新会话（0x10..0x13）
        chk({host[19],host[18],host[17],host[16]} == SES2, "E4: header session != new session");
        ack_now(32'd1, SES2);
        chk(tx_status[2] == 1'b0, "E4: new-session ACK did not release");

        // host 内容落盘（证据）
        fd = $fopen("t11_e2e_e4_host.bin", "wb");
        for (kk = 0; kk < DMA; kk = kk + 1) $fwrite(fd, "%c", host[kk]);
        $fclose(fd);

        repeat (100) @(posedge clk_fb);
        if (errors == 0) $display("ALL PASS");
        else             $display("FAIL: %0d errors", errors);
        $finish;
    end

    initial begin
        #400_000_000;
        $display("FAIL: watchdog timeout");
        $finish;
    end

endmodule
