`timescale 1ns/1ps
// tb_wdt_stall_general.v — 数据侧「通用停滞看门狗」定向验证（半帧停流 → 自愈 → 下一帧发布）
//
// 场景（板测 B 路卡死的等价形态）：第 1 帧只送半帧，在「写者已经把 FIFO 排到
// < 410 组突发门槛、正停在 A_IDLE 等数据」的那一拍断流（相机中途 XCLR/停流，
// 不发 EOF/good）。此时帧内 tmo 被 mid_frame 清零，帧内没有任何超时能收口 →
// 全靠数据侧长看门狗。看门狗超限 → axi_err + self_flush 255 拍
// （两侧指针归零 + 回 S_SYNC）→ 第 2 帧完整送达时必须能重新发布（seq>=1）。
//
// 改 TB 前务必了解的四个约束（都是踩过的坑）：
//  1) 写者消费上限 = 1 个 32bit 字 / clk_ddr 拍 = 4B/拍 = 400MB/s @100MHz。
//     相机若按 1 组(5B)/2 cam 拍 = 416MB/s 硬喂，会稳定溢出 FIFO
//     （fr_drop≈1e4/帧），帧尾永远凑不满 410 组 —— 那是「喂太快」的假死锁，
//     不是看门狗要覆盖的场景。本 TB 按 FIFO 占用反压供数（occ > 700 暂停，
//     等价于真实 sensor/CSI 背压），既不过溢也不会在正常帧尾饿死 410 门槛。
//  2) BURST_BEATS 必须与板上一致取 128：64 拍 = 2048B = 409.6 组，与
//     BURST_GROUPS(410) + 帧尾整除关系对不上，会踩已知的 64 拍尾死锁。
//  3) 断流点必须落在 A_IDLE（spec 的判据就是 a_st==A_IDLE）。若断流时 FIFO 里
//     还有 410~819 组，写者会先起一笔 128 拍突发、中途断粮 → 停在 A_W，
//     那种「突发在飞」的停滞不在本轮看门狗的判据内（见交付说明）。
//     所以这里在「a_st==A_IDLE && mid_frame && !burst_ok_ddr」时精确断流。
//  4) 断流后要等「WDT_LIMIT + flush 窗口」走完、写者真正回到 S_SYNC 再发第 2 帧；
//     注意 s_state 回 S_SYNC 是在 flush 的**第一拍**发生的，self_flush 还要再拉 255 拍，
//     cam 域 2 级同步后更晚。这个窗口里发 vs 会被 self_flush_cam 直接吞掉
//     （SOF 写指针被扣住 + frame_armed 被清），下一帧就整帧丢了 —— 必须等 self_flush 落下。
//     且 in_frame 必须在自愈之后才掉（自愈会清 frame_armed，EOF 标记才不会把
//     第 1 帧「优雅收口」，否则看门狗根本没机会触发）。
module tb_wdt2;
    reg clk_cam = 0, clk_fb = 0, clk_ddr = 0;
    always #3 clk_cam = ~clk_cam;    // 166MHz
    always #8 clk_fb  = ~clk_fb;     // 62.5MHz
    always #5 clk_ddr = ~clk_ddr;    // 100MHz
    reg rst_cam_n = 0, wr_rst = 1;

    localparam integer WDT_LIM = 4000;   // 与 .WDT_LIMIT 一致（ddr 拍）
    localparam integer FEED_HI  = 700;   // 供数反压水位（组）
    localparam integer W=1920, H=64;
    localparam [31:0] BASE0 = 32'h0010_0000, BASE1 = 32'h0090_0000;
    localparam [31:0] SES = 32'h2026_1028;

    reg vs=0, in_frame=0, in_line=0, pv=0, good=0, abort=0;
    reg [39:0] pix=0;
    wire [31:0] seq, base, status, len;
    wire [15:0] lines, grp; wire anom; wire [95:0] drop;
    wire awvalid, awready, wvalid, wready, bvalid, bready, wlast;
    wire [28:0] awaddr; wire [7:0] awlen; wire [2:0] awsize; wire [1:0] awburst;
    wire [255:0] wdata; wire [31:0] wstrb; wire [1:0] bresp;

    reg [7:0] bcnt3 = 0; reg bpend = 0;
    integer beats = 0, bursts = 0;
    assign awready = wr_rst ? 1'b0 : 1'b1;
    assign wready  = wr_rst ? 1'b0 : 1'b1;
    assign bvalid  = bpend && (bcnt3 == 8'd0);
    assign bready  = 1'b1;
    assign bresp   = 2'b00;

    always @(posedge clk_ddr) begin
        if (awvalid && awready) begin bursts = bursts + 1; bcnt3 <= awlen + 8'd1; bpend <= 1'b1; end
        if (wvalid && wready) begin beats = beats + 1; if (bcnt3 != 8'd0) bcnt3 <= bcnt3 - 8'd1; end
        if (bvalid && bready) bpend <= 1'b0;
    end

    cam_r10f_writer #(
        .W(W), .H(H), .X0(16'd0), .Y0(16'd0), .SKIP_ROWS(16'd0),
        .BASE0(BASE0), .BASE1(BASE1), .FIFO_AW(10), .BURST_BEATS(128),
        .CAMERA_ID(8'd0), .SRC_BAYER_PHASE(2'd0), .MODE_ID(32'd1),
        .WDT_LIMIT(WDT_LIM)
    ) dut (
        .cam_clk(clk_cam), .cam_rst_n(rst_cam_n),
        .cam_vsync(vs), .cam_in_frame(in_frame), .cam_in_line(in_line),
        .cam_pix(pix), .cam_pix_valid(pv),
        .cam_frame_good(good), .cam_frame_abort(abort),
        .prot_en(1'b0), .rel_tgl0(1'b0), .rel_tgl1(1'b0),
        .clk_fb(clk_fb), .rst_fb(wr_rst), .session_id(SES),
        .wr_frame_seq(seq), .wr_base(base), .wr_status(status), .wr_len(len),
        .dbg_lines_per_frame(lines), .dbg_max_grp_per_line(grp),
        .dbg_anomaly(anom), .dbg_drop(drop),
        .clk_ddr(clk_ddr), .rst_ddr(wr_rst), .ddr_cal_done(1'b1), .arm(1'b1),
        .axi_busy(),
        .m_axi_awaddr(awaddr), .m_axi_awlen(awlen), .m_axi_awsize(awsize),
        .m_axi_awburst(awburst), .m_axi_awvalid(awvalid), .m_axi_awready(awready),
        .m_axi_wdata(wdata), .m_axi_wstrb(wstrb), .m_axi_wlast(wlast),
        .m_axi_wvalid(wvalid), .m_axi_wready(wready),
        .m_axi_bresp(bresp), .m_axi_bvalid(bvalid), .m_axi_bready(bready)
    );

    integer wdt_hits = 0, flush_cycles = 0, frame_closes = 0, wdt_at_idle = 0;
    always @(posedge clk_ddr) begin
        if (dut.wdt_hit) begin
            wdt_hits = wdt_hits + 1;
            if (dut.a_st == 3'd0) wdt_at_idle = wdt_at_idle + 1;   // 命中的应是 spec 要求的 A_IDLE
        end
        if (dut.self_flush) flush_cycles = flush_cycles + 1;
        if (dut.frame_close) frame_closes = frame_closes + 1;
    end

    integer r, g, x, struck;
    reg [9:0] q0,q1,q2,q3;
    // 1 组 = 4 像素 = 40bit = 5B；按 FIFO 占用反压供数（occ > FEED_HI 就等）
    // stop_mode=1 时，在「写者停在 A_IDLE 等 410 组门槛」的那一拍停流并提前返回。
    task drive_rows(input integer nrow, input integer do_good, input integer stop_mode);
        begin
            struck = 0;
            for (r = 0; (r < nrow) && !struck; r = r + 1) begin
                if (!struck) begin @(negedge clk_cam); in_line = 1; end
                if (!struck) begin @(negedge clk_cam); in_line = 0; end
                for (g = 0; (g < W/4) && !struck; g = g + 1) begin
                    while (dut.fifo_occ_ddr > FEED_HI) @(negedge clk_cam);
                    if (stop_mode && (r >= 4) && (dut.a_st == 3'd0) &&
                        dut.mid_frame && !dut.burst_ok_ddr) begin
                        struck = 1;      // 相机就在这一拍断流
                        pv = 0;
                    end else begin
                        q0 = (g*4+0)*3 + r*5; q1 = (g*4+1)*3 + r*5;
                        q2 = (g*4+2)*3 + r*5; q3 = (g*4+3)*3 + r*5;
                        @(negedge clk_cam); pix = {q3,q2,q1,q0}; pv = 1;
                        @(negedge clk_cam); pv = 0;
                    end
                end
                if (!struck) repeat (40) @(negedge clk_cam);
            end
            if (!struck && do_good) begin
                @(negedge clk_cam); good = 1;
                @(negedge clk_cam); in_frame = 0;
                @(negedge clk_cam); good = 0;
            end
        end
    endtask

    // 等写者回到 S_SYNC（帧收口/自愈完成），带超时
    task wait_sync(input integer maxc);
        begin
            x = 0;
            while ((dut.s_state != 3'd0) && (x < maxc)) begin
                @(negedge clk_cam); x = x + 1;
            end
            if (x >= maxc) $display("WARN: wait_sync timeout (s_state=%0d)", dut.s_state);
        end
    endtask

    // 等自愈窗口彻底结束（self_flush 落下 + cam 域同步 + 余量），否则下一帧的 SOF 会被吞
    task wait_flush_done;
        begin
            x = 0;
            while (dut.self_flush && (x < 20000)) begin
                @(negedge clk_cam); x = x + 1;
            end
            repeat (200) @(negedge clk_cam);
            if (dut.self_flush) $display("WARN: self_flush still high");
        end
    endtask

    // 一帧完整帧（vs 上升沿 + 行驱动 + good/EOF）
    task run_frame(input integer nrow, input integer do_good);
        begin
            @(negedge clk_cam); vs = 1;
            @(negedge clk_cam); vs = 0; in_frame = 1;
            drive_rows(nrow, do_good, 0);
            wait_sync(80000);
            repeat (4000) @(negedge clk_cam);
        end
    endtask

    initial begin
        repeat (20) @(negedge clk_cam);
        rst_cam_n = 1; wr_rst = 0;
        repeat (20) @(negedge clk_cam);

        // ---- 帧 1：送半帧，在写者等 410 门槛的那一拍断流（相机中途停流）----
        @(negedge clk_cam); vs = 1;
        @(negedge clk_cam); vs = 0; in_frame = 1;
        drive_rows(H/2, 0, 1);
        $display("NOTE: feed stopped mid-frame (struck=%0d, s_state=%0d a_st=%0d apos=%0d occ=%0d)",
                 struck, dut.s_state, dut.a_st, dut.apos, dut.fifo_occ_ddr);
        // 断流后 in_frame 一直保持 1：相机死了，不会有 EOF 标记来「优雅收口」。
        // 没有看门狗的话写者就永久停在这里（这正是板上 B 路的形态）。
        // 有自愈：wait_sync 在 flush 第一拍照返回；无自愈：这里超时 → 后面必然 FAIL。
        wait_sync(60000);
        @(negedge clk_cam); in_frame = 0;
        wait_flush_done;                       // ★ 必须等 255 拍自愈窗口真正结束

        // ---- 帧 2 / 帧 3：完整帧，必须重新发布（seq 递增）----
        run_frame(H, 1);
        $display("NOTE: after frame2 seq=%0d status=%08h", seq, status);
        run_frame(H, 1);

        $display("=== WDT seq=%0d bursts=%0d beats=%0d status=%08h wdt_hits=%0d(at_idle=%0d) flush_cycles=%0d closes=%0d",
                 seq, bursts, beats, status, wdt_hits, wdt_at_idle, flush_cycles, frame_closes);
        if ((wdt_hits == 1) && (wdt_at_idle == 1) && (flush_cycles > 0) &&
            (seq >= 1) && (status[0] == 1'b1) && (status[2] == 1'b0))
            $display("PASS: watchdog fired in A_IDLE, self-flushed, next %0d full frames published (seq=%0d)",
                     seq, seq);
        else if (wdt_hits == 0)
            $display("FAIL: watchdog never fired");
        else if (flush_cycles == 0)
            $display("FAIL: wdt_hit but no self_flush");
        else
            $display("FAIL: recovered but next frame not published (seq=%0d, status=%08h)", seq, status);
        $finish;
    end
endmodule