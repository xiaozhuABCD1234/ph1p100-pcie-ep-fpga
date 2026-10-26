///////////////////////////////////////////////////////////////////////////////
//  tb_csi_checked.v — T07.rk-align-backend：checked CSI + cam_ddr_writer 发布裁决
//
//  被测（真实例化，不是桩）：
//    · mipi_csi2_rx_ph1p_checked（本包新 wrapper：PHY 由 MIPI_PHY_SIM_STUB 旁路，
//      真实 csi_rx_packet_integrity + csi_rx_10bit_unpack_checked 全程参与）
//    · cam_ddr_writer（本包改造版：整帧 good/abort 参与发布裁决 + 缓冲区所有权保护）
//
//  覆盖（对应 task-T07 functional 判据）：
//    A) 好帧：FS + 64 行（每行 RAW10 长包 WC=80，ECC/CRC 全对）+ FE
//       ⇒ 发布序号 +1、逐字节 DDR 写数据与「独立像素模型」一致、40bit 四像素正确；
//    B) CRC 错：同一帧把某一行的 CRC 改坏 ⇒ **不发布**（序号不变）+ 错误计数上涨；
//    C) 行长 WC 不符：某行 WC 与 IMAGE_WC 不一致 ⇒ 不发布；
//    D) 没有 FE（帧内停住）⇒ 帧超时 abort ⇒ 不发布；
//    E) FE 排尽：packet_done 之后还有尾拍 → 不许把尾拍当新包头（END_PACKET 等 valid 落）；
//    F) 缓冲区所有权保护：prot_en=1 时发布即保护该块；轮到被保护的块 ⇒ 整帧跳过
//       （不写 DDR、不发布、err 计数）；收到该块 release toggle 后同一块又能写。
//
//  像素模型（TB 独立算，不复用 DUT 任何 helper）：
//    p(line,col) = ((line*64 + col) * 3 + 7) & 0x3FF；DDR 每像素 1 字节 = p>>2。
//  RAW10 打包：P0[9:2],P1[9:2],P2[9:2],P3[9:2],{P3[1:0],P2[1:0],P1[1:0],P0[1:0]}
//  ECC/CRC 由本 TB 按规范独立实现（与 RTL 不同写法，只保证数学等价）。
///////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps

module tb_csi_checked;

    localparam integer W = 64, H = 64;
    localparam integer LINES = H;
    localparam integer GPR = W/4;              // 每行组数 16
    localparam integer WC_LINE = GPR*5;        // 80
    localparam integer FRAME_BYTES = W*H;      // 4096
    localparam integer NBEATS_F = FRAME_BYTES/32;
    localparam [15:0]  IMG_WC = WC_LINE;

    // ---------------- 时钟 ----------------
    reg clk_cam = 0;    // 字节域（stub 下 = wrapper 的 I_ref_clk）
    reg clk_fb  = 0;    // tl_clk_user
    reg clk_ddr = 0;    // AXI 域
    always #5  clk_cam = ~clk_cam;   // 100MHz
    always #8  clk_fb  = ~clk_fb;    // 62.5MHz
    always #5  clk_ddr = ~clk_ddr;   // 100MHz

    reg rst_n = 0;
    reg wr_rst = 1;      // cam_ddr_writer 的 tl/ddr 域复位（TB 必须给脉冲！）

    // ---------------- 注入包层输入（stub 端口）----------------
    reg        sim_valid = 0;
    reg [31:0] sim_data  = 0;
    reg        sim_pktdone = 0;

    // ---------------- DUT: checked CSI wrapper ----------------
    wire        o_byte_clk, o_rst_out;
    wire        o_sync_wait, o_packet_done, o_vsync, o_in_frame, o_in_line;
    wire [39:0] o_pixel;
    wire        o_pixel_valid;
    wire        o_frame_end, o_frame_good, o_frame_abort;
    wire [31:0] o_crc_err, o_hdr_err, o_pkt_to, o_frm_to, o_good_frm, o_bad_frm;
    wire [15:0] o_last_wc, o_last_lines;
    wire [31:0] o_payload; wire [3:0] o_keep; wire o_payload_v;

    mipi_csi2_rx_ph1p_checked #(
        .LANE_NUM(4), .IMAGE_DT(6'h2b), .IMAGE_WC(IMG_WC), .EXPECTED_LINES(LINES),
        .VC_ID(2'd0), .CHECK_FRAME_ID(1'b0),
        .PACKET_IDLE_CYCLES(32'd32), .FRAME_TIMEOUT_CYCLES(32'd50000)
    ) u_csi (
        .I_ref_clk(clk_cam), .I_rst_n(rst_n), .I_rx_en(rst_n),
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

    // ---------------- DUT: cam_ddr_writer ----------------
    wire        w_seq, w_status;
    wire [31:0] wr_frame_seq, wr_base, wr_status;
    wire [15:0] dbg_lines, dbg_grp;
    wire        dbg_anom;
    wire [95:0] dbg_drop;
    reg         prot_en = 0;
    reg         rel_tgl0 = 0, rel_tgl1 = 0;
    wire        axi_busy;
    wire [28:0] m_awaddr;
    wire [7:0]  m_awlen;
    wire [2:0]  m_awsize;
    wire [1:0]  m_awburst;
    wire        m_awvalid, m_awready;
    wire [255:0] m_wdata;
    wire [31:0] m_wstrb;
    wire        m_wlast, m_wvalid, m_wready;
    wire [1:0]  m_bresp;
    wire        m_bvalid, m_bready;

    cam_ddr_writer #(
        .W(W), .H(H), .X0(16'd0), .Y0(16'd0), .SKIP_ROWS(16'd0),
        .BASE0(32'h0010_0000), .BASE1(32'h0090_0000),
        .FIFO_AW(10), .BURST_BEATS(128)
    ) u_wr (
        .cam_clk(clk_cam), .cam_rst_n(o_rst_out),
        .cam_vsync(o_vsync), .cam_in_frame(o_in_frame), .cam_in_line(o_in_line),
        .cam_pix(o_pixel), .cam_pix_valid(o_pixel_valid),
        .cam_frame_good(o_frame_good), .cam_frame_abort(o_frame_abort),
        .prot_en(prot_en), .rel_tgl0(rel_tgl0), .rel_tgl1(rel_tgl1),
        .clk_fb(clk_fb), .rst_fb(wr_rst),
        .wr_frame_seq(wr_frame_seq), .wr_base(wr_base), .wr_status(wr_status), .wr_len(),
        .dbg_lines_per_frame(dbg_lines), .dbg_max_grp_per_line(dbg_grp),
        .dbg_anomaly(dbg_anom), .dbg_drop(dbg_drop),
        .clk_ddr(clk_ddr), .rst_ddr(wr_rst), .ddr_cal_done(1'b1), .arm(1'b1),
        .axi_busy(axi_busy),
        .m_axi_awaddr(m_awaddr), .m_axi_awlen(m_awlen), .m_axi_awsize(m_awsize),
        .m_axi_awburst(m_awburst), .m_axi_awvalid(m_awvalid), .m_axi_awready(m_awready),
        .m_axi_wdata(m_wdata), .m_axi_wstrb(m_wstrb), .m_axi_wlast(m_wlast),
        .m_axi_wvalid(m_wvalid), .m_axi_wready(m_wready),
        .m_axi_bresp(m_bresp), .m_axi_bvalid(m_bvalid), .m_axi_bready(m_bready)
    );

    // ========================================================================
    //  独立像素模型 + 期望字节
    // ========================================================================
    function [9:0] pixv;
        input integer line, col;
        begin pixv = (((line*W + col) * 3) + 7) & 10'h3FF; end
    endfunction

    // 帧内第 b 字节（1 字节 1 像素，行优先）
    function [7:0] exp_byte;
        input integer b;
        begin exp_byte = pixv(b / W, b % W) >> 2; end
    endfunction

    // ========================================================================
    //  假 AXI4 写从机：接受 AW/W/B，并把 DDR 数据与期望逐字节比
    // ========================================================================
    reg  [7:0]   aw_expected_addr_lo;
    integer      wr_beats = 0;
    integer      wr_bytes_total = 0;
    integer      ddr_errs = 0;
    reg          slave_aw_done = 0;
    integer      beat_in_burst = 0;
    reg  [28:0]  cur_base = 0;
    integer      bi;

    assign m_awready = 1'b1;
    assign m_wready  = 1'b1;
    assign m_bresp   = 2'b00;

    always @(posedge clk_ddr) begin
        if (m_awvalid && m_awready) begin
            cur_base  <= m_awaddr[28:0];
            beat_in_burst <= 0;
            wr_beats = wr_beats; // no-op
        end
        if (m_wvalid && m_wready) begin
            // 逐字节比较：本拍 32 字节 = 帧内偏移 (beat_addr - BASE0) + k
            for (bi = 0; bi < 32; bi = bi + 1) begin
                if (m_wstrb[bi]) begin
                    if (m_wdata[bi*8 +: 8] !== exp_byte({cur_base[11:0], 5'd0} + beat_in_burst*32 + bi)) begin
                        if (ddr_errs < 24)
                            $display("  DDRMISMATCH base=%06h beat=%0d k=%0d got=%02h exp=%02h @%0t",
                                cur_base[23:0], beat_in_burst, bi, m_wdata[bi*8 +: 8],
                                exp_byte({cur_base[11:0], 5'd0} + beat_in_burst*32 + bi), $time);
                        ddr_errs = ddr_errs + 1;
                    end
                    wr_bytes_total = wr_bytes_total + 1;
                end
            end
            wr_beats = wr_beats + 1;
            beat_in_burst = beat_in_burst + 1;
        end
        if (m_bvalid && m_bready) ;
        if (m_wvalid && m_wready && m_wlast) ;
    end

    // B 通道：AW 收到后给一个 B
    reg b_pend = 0;
    always @(posedge clk_ddr) begin
        if (m_awvalid && m_awready) b_pend <= 1'b1;
        else if (b_pend && m_bvalid && m_bready) b_pend <= 1'b0;
    end
    assign m_bvalid = (b_pend && (m_wvalid && m_wready)) ? 1'b1 : ((b_pend && !m_wvalid) ? 1'b1 : 1'b0);

    // ========================================================================
    //  像素/包生成
    // ========================================================================
    integer errors = 0;
    integer pix_chk = 0, pix_err = 0;

    task chk(input cond, input [8*96-1:0] msg);
        begin
            if (!cond) begin
                errors = errors + 1;
                if (errors <= 25) $display("  ERROR #%0d @%0t : %s", errors, $time, msg);
            end
        end
    endtask

    // 独立 ECC（CSI-2 头 24bit）：用「数据位→校验位掩码」表的循环写法
    // （与 RTL 的并行 XOR 写法不同；掩码即规范里各校验位覆盖的数据位集合）
    function [7:0] hdr_ecc;
        input [23:0] d;
        integer i;
        reg [7:0] e;
        reg [7:0] m;
        begin
            e = 8'h00;
            for (i = 0; i < 24; i = i + 1) begin
                case (i)
                    0:  m = 8'h07;
                    1:  m = 8'h0B;
                    2:  m = 8'h0D;
                    3:  m = 8'h0E;
                    4:  m = 8'h13;
                    5:  m = 8'h15;
                    6:  m = 8'h16;
                    7:  m = 8'h19;
                    8:  m = 8'h1A;
                    9:  m = 8'h1C;
                    10: m = 8'h23;
                    11: m = 8'h25;
                    12: m = 8'h26;
                    13: m = 8'h29;
                    14: m = 8'h2A;
                    15: m = 8'h2C;
                    16: m = 8'h31;
                    17: m = 8'h32;
                    18: m = 8'h34;
                    19: m = 8'h38;
                    20: m = 8'h1F;
                    21: m = 8'h2F;
                    22: m = 8'h37;
                    default: m = 8'h3B;
                endcase
                if (d[i]) e = e ^ m;
            end
            hdr_ecc = e;
        end
    endfunction

    // 独立 CRC16（reflected，poly 0x8408，init/final 全 1）——按位循环写法
    function [15:0] crc16_b;
        input [15:0] c;
        input [7:0]  b;
        reg [15:0] v;
        integer k;
        reg fb;
        begin
            v = c ^ {8'd0, b};
            for (k = 0; k < 8; k = k + 1) begin
                fb = v[0];
                v = v >> 1;
                if (fb) v = v ^ 16'h8408;
            end
            crc16_b = v;
        end
    endfunction

    // 发送一个 32bit 字（valid 1 拍）
    task send_word(input [31:0] w);
        begin
            @(negedge clk_cam); sim_data = w; sim_valid = 1'b1;
            @(negedge clk_cam); sim_valid = 1'b0;
        end
    endtask

    task gap(input integer n);
        begin
            sim_valid = 1'b0; sim_data = 32'd0;
            repeat (n) @(negedge clk_cam);
        end
    endtask

    // 短包（FS/FE）：1 个字
    task send_short(input [5:0] dt, input [15:0] wcv, input corrupt_ecc);
        reg [23:0] d;
        reg [7:0]  e;
        begin
            d = {wcv, 2'b00, dt};
            e = hdr_ecc(d);
            if (corrupt_ecc) e = e ^ 8'h01;
            send_word({e, d});
        end
    endtask

    // 长包：header + (WC+2) 字节（body+CRC），尾部 0 填充到 4 字节
    task send_long(input [5:0] dt, input [15:0] wcv, input integer first_pix, input bad_crc);
        integer nb, i, wi;
        reg [7:0]  byt [0:255];
        reg [15:0] crc;
        reg [23:0] hd;
        reg [7:0]  he;
        reg [31:0] word;
        reg [9:0]  p0, p1, p2, p3;
        integer pidx;
        begin
            // 打包 RAW10：按像素序号 first_pix.. 生成 wcv 字节
            for (i = 0; i < (wcv/5); i = i + 1) begin
                pidx = first_pix + i*4;
                p0 = pixv(pidx / W, pidx % W);
                p1 = pixv((pidx+1) / W, (pidx+1) % W);
                p2 = pixv((pidx+2) / W, (pidx+2) % W);
                p3 = pixv((pidx+3) / W, (pidx+3) % W);
                byt[i*5+0] = p0[9:2];
                byt[i*5+1] = p1[9:2];
                byt[i*5+2] = p2[9:2];
                byt[i*5+3] = p3[9:2];
                byt[i*5+4] = {p3[1:0], p2[1:0], p1[1:0], p0[1:0]};
            end
            crc = 16'hFFFF;
            for (i = 0; i < wcv; i = i + 1) crc = crc16_b(crc, byt[i]);
            // 与 RTL 一致：比较的是**未取反**的余数（规范 CRC-16 的 init 0xFFFF /
            // poly 0x8408（reflected）/ 无 final XOR）
            if (bad_crc) crc = crc ^ 16'h0100;
            byt[wcv+0] = crc[7:0];
            byt[wcv+1] = crc[15:8];
            // header
            hd = {wcv, 2'b00, dt};
            he = hdr_ecc(hd);
            send_word({he, hd});
            // body + CRC，4 字节一字（不足补 0）
            nb = wcv + 2;
            for (wi = 0; wi < ((nb+3)/4); wi = wi + 1) begin
                word = 32'd0;
                for (i = 0; i < 4; i = i + 1)
                    if ((wi*4+i) < nb) word[i*8 +: 8] = byt[wi*4+i];
                send_word(word);
            end
        end
    endtask

    // 生成一整帧；bad_line >= 0 时把该行 CRC 改坏；missing_fe=1 时不发 FE
    task send_frame(input integer bad_line, input integer bad_wc_line,
                    input integer missing_fe, input [15:0] frame_id);
        integer ln;
        begin
            send_short(6'h00, frame_id, 1'b0);      // FS
            gap(4);
            for (ln = 0; ln < LINES; ln = ln + 1) begin
                if (ln == bad_line)
                    send_long(6'h2b, WC_LINE, ln*W, 1'b1);
                else if (ln == bad_wc_line)
                    send_long(6'h2b, WC_LINE + 4, ln*W, 1'b0);
                else
                    send_long(6'h2b, WC_LINE, ln*W, 1'b0);
                gap(3);
            end
            if (!missing_fe) begin
                send_short(6'h01, frame_id, 1'b0);  // FE
                gap(4);
            end
        end
    endtask

    // 帧裁决监视（调试 + 证据）：每次 FE/abort 打印一次
    reg [1:0] prev_state = 2'd0;
    integer hdr_dbg = 0;
    integer dbg_pk = 0;
    reg [1:0] prev_cst = 2'd0;
    always @(posedge clk_cam) begin
        if (u_wr.f_wr && (dbg_pk < 12)) begin
            dbg_pk = dbg_pk + 1;
            $display("  FIFO wr sof=%b eof=%b eofb=%b wptr=%0d @%0t",
                     u_wr.push_sof, u_wr.push_eof, u_wr.f_din[32], u_wr.wptr_bin, $time);
        end
    end
    always @(posedge clk_ddr) begin
        if (u_wr.c_st !== prev_cst) begin
            prev_cst <= u_wr.c_st;
            $display("  PK c_st=%0d ent=%b rempty=%b pop=%b beat_vld=%b @%0t",
                     u_wr.c_st, u_wr.ent_vld, u_wr.rempty, u_wr.pop, u_wr.beat_vld, $time);
        end
    end
    always @(posedge o_byte_clk) begin
        if (o_frame_end | o_frame_abort)
            $display("  CSI @%0t end=%b good=%b abort=%b lines=%0d wc=%0d good_cnt=%0d bad_cnt=%0d crc=%0d frm_to=%0d pkt_to=%0d",
                     $time, o_frame_end, o_frame_good, o_frame_abort,
                     o_last_lines, o_last_wc, o_good_frm, o_bad_frm, o_crc_err, o_frm_to, o_pkt_to);
        if (u_csi.u_integrity.state !== prev_state) begin
            prev_state <= u_csi.u_integrity.state;
            $display("  INT state=%0d open=%b bad=%b lines=%0d wc=%0d hdrs=%0d @%0t",
                     u_csi.u_integrity.state, u_csi.u_integrity.frame_open,
                     u_csi.u_integrity.frame_bad, u_csi.u_integrity.line_count,
                     u_csi.u_integrity.wc, u_csi.u_integrity.O_header_errors, $time);
        end
        if (u_csi.u_integrity.O_header_errors != 0 && hdr_dbg == 0) begin
            hdr_dbg = 1;
            $display("  INT first hdr error: last data=%08h @%0t", u_csi.u_integrity.I_data, $time);
        end
    end

    // ========================================================================
    //  主流程
    // ========================================================================
    integer i, t;
    reg [31:0] seq_before;
    integer err_cnt_before;

    task wait_frame_done(input integer maxcyc);
        begin
            t = 0;
            while ((u_wr.c_st != 2'd0) && (t < maxcyc)) begin @(posedge clk_fb); t = t + 1; end
        end
    endtask

    initial begin
        rst_n = 0; sim_valid = 0; sim_data = 0; sim_pktdone = 0;
        wr_rst = 1;
        #100; rst_n = 1; #200; wr_rst = 0; #100;
        repeat (20) @(negedge clk_cam);

        $display("=== PHASE A 好帧：发布 + DDR 逐字节 ===");
        wr_beats = 0; wr_bytes_total = 0; ddr_errs = 0;
        seq_before = wr_frame_seq;
        send_frame(-1, -1, 0, 16'h0001);
        gap(200);
        wait_frame_done(200000);
        repeat (50) @(posedge clk_fb);
        chk(wr_frame_seq == seq_before + 1, "A: good frame did not publish");
        chk((wr_status[2] == 1'b0), "A: published frame flagged err");
        chk(ddr_errs == 0, "A: DDR byte mismatch");
        $display("  DBG A beats=%0d bytes=%0d ddr_errs=%0d seq=%0d status=%08h",
                 wr_beats, wr_bytes_total, ddr_errs, wr_frame_seq, wr_status);
        chk(wr_bytes_total == FRAME_BYTES, "A: written bytes != 4096");
        chk(o_good_frm == 1, "A: good_frames != 1");
        chk(o_last_lines == LINES, "A: last_lines != 64");
        chk(o_last_wc == WC_LINE, "A: last_wc != 80");

        $display("=== PHASE B CRC 错：不发布 ===");
        seq_before = wr_frame_seq;
        err_cnt_before = wr_status[31:16];
        send_frame(5, -1, 0, 16'h0002);
        gap(200);
        wait_frame_done(200000);
        repeat (50) @(posedge clk_fb);
        chk(wr_frame_seq == seq_before, "B: bad-CRC frame published");
        chk(wr_status[31:16] > err_cnt_before, "B: err count did not rise");
        chk(o_crc_err >= 1, "B: crc error counter == 0");

        $display("=== PHASE C 行 WC 不符：不发布 ===");
        seq_before = wr_frame_seq;
        err_cnt_before = wr_status[31:16];
        send_frame(-1, 7, 0, 16'h0003);
        gap(200);
        wait_frame_done(200000);
        repeat (50) @(posedge clk_fb);
        chk(wr_frame_seq == seq_before, "C: wrong-WC frame published");
        chk(wr_status[31:16] > err_cnt_before, "C: err count did not rise");

        $display("=== PHASE D 没有 FE：帧超时 abort，不发布 ===");
        seq_before = wr_frame_seq;
        err_cnt_before = wr_status[31:16];
        send_frame(-1, -1, 1, 16'h0004);
        gap(200);
        repeat (150000) @(posedge clk_cam);      // 等 CSI 帧超时（50000 拍）先到
        $display("  DBG D frm_to=%0d bad=%0d open=%b c_st=%0d", o_frm_to, o_bad_frm,
                 u_csi.u_integrity.frame_open, u_wr.c_st);
        chk(o_frm_to >= 1, "D: frame timeout counter == 0");
        // 再等 writer 自己的收口（它没有 EOF，走 c_run_tmo 兜底）
        wait_frame_done(4000000);
        repeat (200) @(posedge clk_fb);
        chk(wr_frame_seq == seq_before, "D: fragment published");
        chk(wr_status[31:16] > err_cnt_before, "D: err count did not rise");

        $display("=== PHASE E FE 排尽：尾拍不当新包头 ===");
        seq_before = wr_frame_seq;
        send_frame(-1, -1, 0, 16'h0005);
        gap(200);
        wait_frame_done(200000);
        repeat (50) @(posedge clk_fb);
        chk(wr_frame_seq == seq_before + 1, "E: frame did not publish");
        chk(o_hdr_err == 0, "E: header error (tail treated as header?)");
        chk(o_pkt_to == 0, "E: packet timeout");

        $display("=== PHASE F 缓冲区所有权保护 ===");
        prot_en = 1;
        seq_before = wr_frame_seq;
        err_cnt_before = wr_status[31:16];
        // 先发一帧（frame_idx 偶数 → BASE0）；随后该块应被保护
        send_frame(-1, -1, 0, 16'h0006);
        gap(200);
        wait_frame_done(200000);
        repeat (50) @(posedge clk_fb);
        chk(wr_frame_seq == seq_before + 1, "F: frame0 did not publish");
        // 直接检查保护位（发布即保护）
        chk((u_wr.protect0 == 1'b1) || (u_wr.protect1 == 1'b1), "F: publish did not protect a block");
        // 再发一帧：轮到另一块 → 正常发布（不覆盖被保护块）
        seq_before = wr_frame_seq;
        send_frame(-1, -1, 0, 16'h0007);
        gap(200);
        wait_frame_done(200000);
        repeat (50) @(posedge clk_fb);
        chk(wr_frame_seq == seq_before + 1, "F: second block frame did not publish");
        // 第三帧轮到被保护块 → 必须整帧跳过（不写 DDR、不发布、err 涨）
        err_cnt_before = wr_status[31:16];
        seq_before = wr_frame_seq;
        send_frame(-1, -1, 0, 16'h0008);
        gap(200);
        wait_frame_done(200000);
        repeat (50) @(posedge clk_fb);
        chk(wr_frame_seq == seq_before, "F: protected-block frame published");
        chk(wr_status[31:16] > err_cnt_before, "F: skip did not count err");
        chk(u_wr.c_bad >= 1, "F: c_bad did not rise");
        $display("  DBG F protect0=%b protect1=%b frame_idx=%0d c_st=%0d rel0=%b rel1=%b",
                 u_wr.protect0, u_wr.protect1, u_wr.frame_idx, u_wr.c_st, rel_tgl0, rel_tgl1);
        // 释放两块（模拟推帧引擎 ACK/取消后的 release toggle）：两块都放掉后下
        // 一帧无论落在哪个块都必须能发布
        rel_tgl0 = ~rel_tgl0;
        rel_tgl1 = ~rel_tgl1;
        repeat (40) @(posedge clk_ddr);
        $display("  DBG F2 protect0=%b protect1=%b", u_wr.protect0, u_wr.protect1);
        chk((u_wr.protect0 == 1'b0) && (u_wr.protect1 == 1'b0), "F: release did not clear protect");
        // 释放后再发一帧：应该又能发布
        seq_before = wr_frame_seq;
        send_frame(-1, -1, 0, 16'h0009);
        gap(200);
        wait_frame_done(200000);
        repeat (50) @(posedge clk_fb);
        chk(wr_frame_seq == seq_before + 1, "F: post-release frame did not publish");

        if (errors == 0) $display("ALL PASS");
        else             $display("FAIL: %0d error(s)", errors);
        $finish;
    end

    initial begin
        #100_000_000;
        $display("FAIL: global timeout");
        $finish;
    end

endmodule
