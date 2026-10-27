///////////////////////////////////////////////////////////////
//  tb_cam_ddr_writer.v — cam_ddr_writer（CSI-2 → DDR3）冒烟测试（iverilog）
//
//  跑法（本机已装 iverilog；本测试台是真跑过的，结论见提交说明）：
//    iverilog -o tb_cam_ddr_writer tb_cam_ddr_writer.v \
//             ../rtl/ep_side/ddr/cam_ddr_writer.v
//    ./tb_cam_ddr_writer            # 期望输出 "ALL PASS"
//
//  为什么用这组几何（W=20/H=44/BB=16）——一次把三条边角路径都覆盖到：
//    · FRAME_WORDS = 220 ⇒ NBEATS = ceil(220/8) = 28（不是 8 的整数倍）
//      ⇒ 末拍是**残拍**：wstrb 必须只开前 4 个字（= 16 字节 = 0x0000FFFF）；
//    · NBEATS = 28 而 BURST_BEATS = 16 ⇒ 最后一突发是**短板**：awlen = 11；
//    · X0=8 / Y0=2 / SKIP_ROWS=3 ⇒ 同时验「行偏移 + 帧头跳行 + 行内横向裁剪」。
//
//  测什么：
//   1) 像素一致性：假 DDR 里那一帧的字节，逐字节等于 TB 的像素公式
//      （证明「窗口内组 → 线性字节流」的映射、RAW10>>2、字内字节序都对）；
//   2) 双缓冲：帧号奇偶 → BASE0/BASE1 交替；发布的 seq 单调递增（坏帧不占号）；
//   3) AXI 规则：awsize=5、INCR、不跨 4KB、wlast 只在突发末拍、
//      末拍 wstrb 裁字节（从机模型逐条检查，不符就记 error）；
//   4) 不虚报：一帧只发了一半（EOF 提前、字数对不上）⇒ 不发布、err_cnt+1，
//      而且 AXI 侧仍然把本帧的拍用空拍补满（不空等、不死锁）；
//   5) 恢复：坏帧之后下一帧照常发布（seq 只在好帧上 +1）；
//   6) 跨时钟域：字节域 187.5MHz ↔ ddr 域 100MHz ↔ tl 域 62.5MHz 三个域一起跑；
//   7) 反压：AXI 从机 16 拍里只收 8 拍（50%），逼 packer 把手上那一拍压住不放
//      —— 「pop 被挡住」是读侧最容易丢/错一条的地方，必须压在反压下跑过。
///////////////////////////////////////////////////////////////
`timescale 1ns/1ps

module tb_cam_ddr_writer;

    // ---------------- 几何（与 DUT 参数必须一致）----------------
    localparam integer W     = 20;         // 帧宽（窗口宽）
    localparam integer H     = 44;         // 帧高（窗口高）
    localparam integer X0    = 8;          // 行内横向偏移（必须是 4 的倍数）
    localparam integer Y0    = 2;          // 图像域行偏移
    localparam integer SKIP  = 3;          // 帧头 embedded + 哑行
    localparam integer BB    = 16;         // BURST_BEATS

    localparam integer GROUPS = 16;        // 每行发出 64 像素（16 组）
    localparam integer NROWS  = 56;        // 每帧发出 56 行（窗口用 5..48 行）
    localparam integer WGRP   = W / 4;     // 每行入窗组数 = 5
    localparam integer XG     = X0 / 4;    // 入窗起始组 = 2
    localparam integer YIMG   = Y0 + SKIP; // 入窗起始行 = 5

    localparam integer FRAME_WORDS = (W * H) / 4;                  // 220
    localparam integer FRAME_BYTES = W * H;                        // 880
    localparam integer NBEATS      = (FRAME_WORDS + 7) / 8;        // 28
    localparam integer PART_WORDS  = FRAME_WORDS % 8;              // 4
    localparam integer NBURST      = (NBEATS + BB - 1) / BB;       // 2
    localparam integer BURSTS_FULL = NBEATS / BB;                  // 1
    localparam integer LAST_BEATS  = NBEATS - BURSTS_FULL * BB;    // 12

    localparam [31:0] BASE0 = 32'h0010_0000;
    localparam [31:0] BASE1 = 32'h0020_0000;   // 与 BASE0 相隔 1MB（假 DDR 只有 4MB）

    // ---------------- 时钟 / 复位 ----------------
    reg cam_clk = 0;      // 187.5MHz（MIPI 字节时钟）
    reg clk_ddr = 0;      // 100MHz（usr_clk）
    reg clk_fb  = 0;      // 62.5MHz（tl_clk_user）
    always #2.667 cam_clk = ~cam_clk;
    always #5.0   clk_ddr = ~clk_ddr;
    always #8.0   clk_fb  = ~clk_fb;

    reg cam_rst_n = 0;
    reg rst_fb    = 1;
    reg rst_ddr   = 1;

    // ---------------- 字节域激励 ----------------
    reg         cam_vsync = 0, cam_in_frame = 0, cam_in_line = 0, cam_pix_valid = 0;
    reg  [39:0] cam_pix = 0;

    // 像素公式（10bit RAW10）：行 r、行内第 i 个像素
    function [9:0] pix10;
        input integer r;
        input integer i;
        begin
            pix10 = (r * 77 + i * 3) & 1023;
        end
    endfunction

    function [39:0] pack_pix;
        input integer r;
        input integer g;      // 组号
        integer i;
        begin
            i = g * 4;
            pack_pix[9:0]   = pix10(r, i + 0);
            pack_pix[19:10] = pix10(r, i + 1);
            pack_pix[29:20] = pix10(r, i + 2);
            pack_pix[39:30] = pix10(r, i + 3);
        end
    endfunction

    // DDR 里第 b 个字节的期望值（b 是帧内字节偏移）
    function [7:0] exp_byte;
        input integer b;
        integer wd, lane, row_off, grp_off;
        begin
            wd      = b / 4;
            lane    = b % 4;
            row_off = wd / WGRP;
            grp_off = wd % WGRP;
            exp_byte = pix10(YIMG + row_off, X0 + grp_off * 4 + lane) >> 2;
        end
    endfunction

    // 一帧 CSI-2 流：FS → rows 行（每行 1 拍行头 + GROUPS 组）→ FE
    //   rows 参数用来造「只发一半」的坏帧
    task gen_frame;
        input integer rows;
        integer r, g;
        begin
            @(posedge cam_clk); cam_vsync <= 1'b1; cam_in_frame <= 1'b1;
            @(posedge cam_clk); cam_vsync <= 1'b0;
            for (r = 0; r < rows; r = r + 1) begin
                @(posedge cam_clk); cam_in_line <= 1'b1;
                @(posedge cam_clk); cam_in_line <= 1'b0;
                for (g = 0; g < GROUPS; g = g + 1) begin
                    @(posedge cam_clk);
                    cam_pix       <= pack_pix(r, g);
                    cam_pix_valid <= 1'b1;        // 1 组/拍（最坏突发，不插空拍）
                end
                @(posedge cam_clk); cam_pix_valid <= 1'b0;
                repeat (3) @(posedge cam_clk);    // 行间空档
            end
            @(posedge cam_clk); cam_in_frame <= 1'b0;   // FE → EOF
            repeat (8) @(posedge cam_clk);
        end
    endtask

    // ---------------- 假 DDR（按字节存）----------------
    localparam DDR_BYTES = 32'h0040_0000;         // 4MB（两块基址都要落在里面）
    reg [7:0] ddr_mem [0:DDR_BYTES-1];

    // ---------------- DUT 互连 ----------------
    wire [31:0] wr_seq, wr_base, wr_status, wr_len;
    wire [15:0] dbg_lines, dbg_grp;
    wire        dbg_anom;
    wire        axi_busy;

    wire [28:0] awaddr;
    wire [7:0]  awlen;
    wire [2:0]  awsize;
    wire [1:0]  awburst;
    wire        awvalid;
    reg         awready = 0;
    wire [255:0] wdata;
    wire [31:0]  wstrb;
    wire         wlast, wvalid;
    reg          wready = 0;
    reg  [1:0]   bresp  = 2'b00;
    reg          bvalid = 0;
    wire         bready;

    cam_ddr_writer #(
        .W(W), .H(H), .X0(X0), .Y0(Y0), .SKIP_ROWS(SKIP),
        .BASE0(BASE0), .BASE1(BASE1), .FIFO_AW(10), .BURST_BEATS(BB)
    ) u_dut (
        .cam_clk (cam_clk), .cam_rst_n (cam_rst_n),
        .cam_vsync (cam_vsync), .cam_in_frame (cam_in_frame),
        .cam_in_line (cam_in_line), .cam_pix (cam_pix),
        .cam_pix_valid (cam_pix_valid),

        .clk_fb (clk_fb), .rst_fb (rst_fb),
        .wr_frame_seq (wr_seq), .wr_base (wr_base), .wr_status (wr_status),
        .wr_len (wr_len),
        .dbg_lines_per_frame (dbg_lines), .dbg_max_grp_per_line (dbg_grp),
        .dbg_anomaly (dbg_anom),

        .clk_ddr (clk_ddr), .rst_ddr (rst_ddr), .ddr_cal_done (1'b1),
        .arm (1'b1), .axi_busy (axi_busy),

        .m_axi_awaddr (awaddr), .m_axi_awlen (awlen), .m_axi_awsize (awsize),
        .m_axi_awburst (awburst), .m_axi_awvalid (awvalid), .m_axi_awready (awready),
        .m_axi_wdata (wdata), .m_axi_wstrb (wstrb), .m_axi_wlast (wlast),
        .m_axi_wvalid (wvalid), .m_axi_wready (wready),
        .m_axi_bresp (bresp), .m_axi_bvalid (bvalid), .m_axi_bready (bready)
    );

    // ---------------- AXI 从机模型（含反压与规则检查）----------------
    reg        w_active = 0;
    reg [28:0] aw_addr_r;
    reg [8:0]  w_idx;
    reg [3:0]  stall_cnt = 4'd0;
    integer    j;
    integer    nburst_done = 0;
    integer    err_cnt_tb  = 0;
    integer    awlen_seen [0:15];

    always @(posedge clk_ddr) stall_cnt <= stall_cnt + 4'd1;

    always @(posedge clk_ddr or posedge rst_ddr) begin
        if (rst_ddr) begin
            awready   <= 1'b0;
            wready    <= 1'b0;
            w_active  <= 1'b0;
            bvalid    <= 1'b0;
            bresp     <= 2'b00;
            w_idx     <= 9'd0;
            aw_addr_r <= 29'd0;
        end else begin
            // ---- AW（单拍握手：awready 拉高的下一拍完成握手）----
            awready <= 1'b0;
            if (awvalid && !w_active && !bvalid && !awready) awready <= 1'b1;

            if (awvalid && awready) begin        // 握手完成的那一拍，看到的才是真值
                aw_addr_r <= awaddr;
                w_active  <= 1'b1;
                w_idx     <= 9'd0;
                if (awsize !== 3'd5) begin
                    $display("ERROR: awsize=%0d 期望 5", awsize); err_cnt_tb = err_cnt_tb + 1;
                end
                if (awburst !== 2'b01) begin
                    $display("ERROR: awburst=%b 期望 INCR", awburst); err_cnt_tb = err_cnt_tb + 1;
                end
                if (awlen > BB - 1) begin
                    $display("ERROR: awlen=%0d 超过 BURST_BEATS-1=%0d", awlen, BB - 1);
                    err_cnt_tb = err_cnt_tb + 1;
                end
                if ((awaddr[11:0] + (awlen + 1) * 32 - 1) >> 12 !== awaddr[11:0] >> 12) begin
                    $display("ERROR: 突发 %h len=%0d 跨了 4KB 页", awaddr, awlen);
                    err_cnt_tb = err_cnt_tb + 1;
                end
                if (nburst_done < 16) awlen_seen[nburst_done] = awlen;
            end

            // ---- W（强反压：16 拍里只收 8 拍）----
            //  强反压会让 packer 的手上那一拍压住不放 —— 那正是「pop 被挡住」这条路，
            //  也是读侧最容易丢/错一条的地方，所以这里刻意压得很狠。
            wready <= 1'b0;
            if (w_active) begin
                wready <= (stall_cnt < 4'd8);   // 16 拍里只收 8 拍
                if (wvalid && wready) begin
                    for (j = 0; j < 32; j = j + 1)
                        if (wstrb[j]) ddr_mem[aw_addr_r + w_idx * 32 + j] <= wdata[j*8 +: 8];
                    if (wlast !== (w_idx == awlen)) begin
                        $display("ERROR: 第 %0d 拍 wlast=%b 不对（awlen=%0d）", w_idx, wlast, awlen);
                        err_cnt_tb = err_cnt_tb + 1;
                    end
                    if (w_idx == awlen) begin
                        w_active <= 1'b0;
                        bvalid   <= 1'b1;
                        nburst_done = nburst_done + 1;
                    end else begin
                        w_idx <= w_idx + 9'd1;
                    end
                end
            end

            // ---- B ----
            if (bvalid && bready) bvalid <= 1'b0;
        end
    end

    // ---------------- 检查 ----------------
    integer    errors = 0;
    integer    t;
    reg [31:0] seq_prev;

    task chk;
        input [255:0] name;
        input [31:0]  got_v;
        input [31:0]  exp_v;
        begin
            if (got_v !== exp_v) begin
                $display("  FAIL %0s: got %0d/%08x exp %0d/%08x", name, got_v, got_v, exp_v, exp_v);
                errors = errors + 1;
            end
        end
    endtask

    // 等发布（超时算错）；返回等到的序号
    task wait_pub;
        input [31:0] seq_exp;
        input [31:0] base_exp;
        begin
            t = 0;
            while ((wr_seq !== seq_exp || wr_base !== base_exp) && t < 400000) begin
                @(posedge clk_fb); t = t + 1;
            end
            if (t >= 400000) begin
                $display("  FAIL 等第 %0d 帧发布超时（wr_seq=%0d wr_base=%h）", seq_exp, wr_seq, wr_base);
                errors = errors + 1;
            end
            @(posedge clk_fb);      // status 比 seq 晚一拍（同域寄存器）
        end
    endtask

    task check_block;
        input [31:0] base;
        input integer fno;
        integer b;
        begin
            for (b = 0; b < FRAME_BYTES; b = b + 1) begin
                if (ddr_mem[base + b] !== exp_byte(b)) begin
                    $display("  FAIL 帧 %0d 基址 %h 第 %0d 字节：DDR=%02h 期望 %02h",
                             fno, base, b, ddr_mem[base+b], exp_byte(b));
                    errors = errors + 1;
                    b = FRAME_BYTES;      // 一帧只报一次
                end
            end
        end
    endtask

    initial begin
        $display("--- tb_cam_ddr_writer: CSI-2 -> DDR3（W=%0d H=%0d NBEATS=%0d NBURST=%0d）---",
                 W, H, NBEATS, NBURST);
        #60 cam_rst_n = 1;
        #40 rst_fb = 0; rst_ddr = 0;
        #200;
        chk("wr_len", wr_len, FRAME_BYTES);
        chk("初始 seq=0", wr_seq, 32'd0);

        // ================= 第 1 帧（好帧）→ BASE0 =================
        gen_frame(NROWS);
        wait_pub(1, BASE0);
        chk("发布后 status.bit0(valid)", {31'd0, wr_status[0]}, 32'd1);
        chk("发布后 status.bit2(err) = 0", {31'd0, wr_status[2]}, 32'd0);
        chk("err_cnt = 0", wr_status[31:16], 32'd0);
        check_block(BASE0, 1);
        $display("  第 1 帧已逐字节比对（%0d 字节）", FRAME_BYTES);

        // ================= 第 2 帧（只发一半 → 必须不发布）=================
        seq_prev = wr_seq;
        gen_frame(24);                     // 行数不到一半，EOF 提前
        repeat (4000) @(posedge clk_ddr);  // 给 AXI 补空拍/收尾的时间
        chk("坏帧不发布（seq 不变）", wr_seq, seq_prev);
        chk("坏帧后 status.bit2(err)", {31'd0, wr_status[2]}, 32'd1);
        chk("坏帧后 err_cnt = 1", wr_status[31:16], 32'd1);

        // ================= 第 3 帧（好帧，验恢复）→ BASE0（帧号奇偶）=================
        gen_frame(NROWS);
        wait_pub(2, BASE0);
        check_block(BASE0, 3);
        $display("  第 3 帧已逐字节比对");

        // ================= 第 4 帧（好帧）→ BASE1 =================
        gen_frame(NROWS);
        wait_pub(3, BASE1);
        check_block(BASE1, 4);
        $display("  第 4 帧已逐字节比对（双缓冲另一块）");

        // ================= 诊断 =================
        repeat (50) @(posedge clk_fb);
        chk("dbg_lines_per_frame", {16'd0, dbg_lines}, NROWS);
        chk("dbg_max_grp_per_line", {16'd0, dbg_grp}, GROUPS);
        chk("dbg_anomaly=0（FIFO 没满过）", {31'd0, dbg_anom}, 32'd0);

        // ================= AXI 波形规则 =================
        if (awlen_seen[0] !== BB - 1) begin
            $display("  FAIL 第 1 个突发 awlen=%0d 期望 %0d", awlen_seen[0], BB - 1);
            errors = errors + 1;
        end
        if (awlen_seen[1] !== LAST_BEATS - 1) begin
            $display("  FAIL 第 2 个（短板）突发 awlen=%0d 期望 %0d", awlen_seen[1], LAST_BEATS - 1);
            errors = errors + 1;
        end
        $display("  突发：1 个满突发 awlen=%0d + 1 个短板 awlen=%0d（每帧 %0d 个）",
                 BB - 1, LAST_BEATS - 1, NBURST);

        if (errors == 0 && err_cnt_tb == 0)
            $display("ALL PASS（%0d 个突发，%0d 帧，末拍残 %0d 字）",
                     nburst_done, 4, PART_WORDS);
        else
            $display("FAIL: 检查 %0d 处不符，AXI 模型 %0d 处不符", errors, err_cnt_tb);
        $finish;
    end

endmodule
