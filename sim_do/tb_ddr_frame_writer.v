///////////////////////////////////////////////////////////////
//  tb_ddr_frame_writer.v — ddr_frame_writer 冒烟测试（iverilog）
//
//  ★ 本机没有仿真器：本测试台「只写不跑」，结论里必须标注“未运行”。
//    在有 iverilog 的机器上跑：
//      iverilog -o tb_ddr_frame_writer tb_ddr_frame_writer.v \
//               ../../rtl/ep_side/ddr/ddr_frame_writer.v
//      ./tb_ddr_frame_writer          # 期望输出 "ALL PASS"
//
//  测什么：
//   1) 双缓冲：帧号奇偶 → BASE0/BASE1 交替；发布的 seq 单调递增、与 fb 字 0 一致；
//   2) 数据一致性：AXI 侧按 256bit 拍写进假 DDR 的字节，与 TB 里的 fb 逐字节相同
//      （证明「lane k 的字 → [32k +: 32]」这个字节序没搞反）；
//   3) AXI 突发切分：awlen = BURST_BEATS-1、awsize=5、INCR、地址 4KB 对齐、
//      wlast 只在每突发最后一拍（从机模型逐条检查，不符就报 error）；
//   4) 握手：只有整帧的写响应收齐后才发布 seq/base；搬运期间 fb 被新一帧写入
//      （fb_busy 拉高）→ 本帧不发布、err_cnt +1；
//   5) AXI 从机每 8 拍停 1 拍（backpressure），验证 FIFO/skid 不丢拍、不错位。
//
//  参数取小值以便跑得快：W=64,H=32 → 2048B/帧、512 字、64 拍、16 拍/突发 → 4 个突发。
///////////////////////////////////////////////////////////////
`timescale 1ns/1ps

module tb_ddr_frame_writer;

    localparam integer W  = 64;
    localparam integer H  = 32;
    localparam integer FRAME_BYTES = W * H;          // 2048
    localparam integer FB_WORDS    = FRAME_BYTES / 4;// 512
    localparam integer NBEATS      = FRAME_BYTES / 32;// 64
    localparam integer BB          = 16;             // BURST_BEATS
    localparam integer NBURST      = NBEATS / BB;    // 4

    localparam [31:0] BASE0 = 32'h0010_0000;
    localparam [31:0] BASE1 = 32'h0018_0000;

    // ---------------- 时钟 / 复位 ----------------
    reg clk_fb  = 0;      // 62.5MHz（tl_clk_user）
    reg clk_ddr = 0;      // 100MHz（usr_clk）
    reg rst_fb  = 1;
    reg rst_ddr = 1;
    always #8.0 clk_fb  = ~clk_fb;
    always #5.0 clk_ddr = ~clk_ddr;

    // ---------------- DUT 互连 ----------------
    reg  [31:0] fb_frame_cnt = 0;
    reg         fb_busy      = 0;
    reg         ddr_en       = 0;
    reg         ddr_cal_done = 0;
    wire [31:0] fb_rd_addr;
    wire [31:0] wr_seq, wr_base, wr_status, wr_len;

    wire [28:0]  awaddr;
    wire [7:0]   awlen;
    wire [2:0]   awsize;
    wire [1:0]   awburst;
    wire         awvalid;
    reg          awready = 0;
    wire [255:0] wdata;
    wire [31:0]  wstrb;
    wire         wlast, wvalid;
    reg          wready  = 0;
    reg  [1:0]   bresp   = 2'b00;
    reg          bvalid  = 0;
    wire         bready;

    // ---------------- 假帧缓存（TB 侧，布局与 img_frame_src 一致）----------------
    reg [31:0] fb_mem [0:FB_WORDS-1];
    reg [31:0] fb_rdata;
    wire       fb_req;
    always @(posedge clk_fb) fb_rdata <= fb_mem[fb_rd_addr[31:2]];   // 1 拍延迟

    // ---------------- 假 DDR（按字节存）----------------
    localparam DDR_BYTES = 32'h0020_0000;   // 2MB，足够装两块
    reg [7:0] ddr_mem [0:DDR_BYTES-1];

    // ---------------- AXI 从机模型 ----------------
    reg        w_active = 0;
    reg [28:0] aw_addr_r;
    reg [7:0]  w_idx;
    reg [2:0]  stall_cnt = 3'd0;
    integer    j;
    integer    nburst_done = 0;
    integer    err_cnt_tb  = 0;

    always @(posedge clk_ddr) stall_cnt <= stall_cnt + 3'd1;

    always @(posedge clk_ddr or posedge rst_ddr) begin
        if (rst_ddr) begin
            awready   <= 1'b0;
            wready    <= 1'b0;
            w_active  <= 1'b0;
            bvalid    <= 1'b0;
            bresp     <= 2'b00;
            w_idx     <= 8'd0;
            aw_addr_r <= 29'd0;
        end else begin
            // ---- AW ----
            awready <= 1'b0;
            if (awvalid && !w_active && !bvalid && !awready) begin
                awready   <= 1'b1;
                aw_addr_r <= awaddr;
                if (awlen !== BB - 1) begin
                    $display("ERROR: awlen=%0d 期望 %0d", awlen, BB - 1); err_cnt_tb = err_cnt_tb + 1;
                end
                if (awsize !== 3'd5) begin
                    $display("ERROR: awsize=%0d 期望 5", awsize); err_cnt_tb = err_cnt_tb + 1;
                end
                if (awburst !== 2'b01) begin
                    $display("ERROR: awburst=%b 期望 INCR", awburst); err_cnt_tb = err_cnt_tb + 1;
                end
                if (awaddr[11:0] !== 12'h000) begin
                    $display("ERROR: 突发地址 %h 没 4KB 对齐", awaddr); err_cnt_tb = err_cnt_tb + 1;
                end
                w_active <= 1'b1;
                w_idx    <= 8'd0;
            end

            // ---- W（每 8 拍停 1 拍，制造 backpressure）----
            wready <= 1'b0;
            if (w_active) begin
                wready <= (stall_cnt != 3'd3);
                if (wvalid && wready) begin
                    for (j = 0; j < 32; j = j + 1)
                        ddr_mem[aw_addr_r + w_idx * 32 + j] <= wdata[j*8 +: 8];
                    if (wlast !== (w_idx == BB - 1)) begin
                        $display("ERROR: 第 %0d 拍 wlast=%b 不对", w_idx, wlast); err_cnt_tb = err_cnt_tb + 1;
                    end
                    if (w_idx == BB - 1) begin
                        w_active <= 1'b0;
                        bvalid   <= 1'b1;      // 写响应
                        nburst_done = nburst_done + 1;
                    end else begin
                        w_idx <= w_idx + 8'd1;
                    end
                end
            end

            // ---- B ----
            if (bvalid && bready) bvalid <= 1'b0;
        end
    end

    // ---------------- DUT ----------------
    ddr_frame_writer #(
        .W(W), .H(H), .BASE0(BASE0), .BASE1(BASE1),
        .FIFO_AW(5), .BURST_BEATS(BB)
    ) u_dut (
        .clk_fb (clk_fb), .rst_fb (rst_fb), .ddr_en (ddr_en),
        .fb_frame_cnt (fb_frame_cnt), .fb_busy (fb_busy),
        .fb_rd_addr (fb_rd_addr), .fb_rd_data (fb_rdata),
        .fb_req (fb_req), .fb_grant (1'b1),   // 单机测试：读口一直给它（只测搬运通路本身）
        .clk_ddr (clk_ddr), .rst_ddr (rst_ddr), .ddr_cal_done (ddr_cal_done),
        .m_axi_awaddr (awaddr), .m_axi_awlen (awlen), .m_axi_awsize (awsize),
        .m_axi_awburst (awburst), .m_axi_awvalid (awvalid), .m_axi_awready (awready),
        .m_axi_wdata (wdata), .m_axi_wstrb (wstrb), .m_axi_wlast (wlast),
        .m_axi_wvalid (wvalid), .m_axi_wready (wready),
        .m_axi_bresp (bresp), .m_axi_bvalid (bvalid), .m_axi_bready (bready),
        .wr_frame_seq (wr_seq), .wr_base (wr_base), .wr_status (wr_status),
        .wr_len (wr_len)
    );

    // ---------------- 检查用 ----------------
    integer    errors = 0;
    reg [31:0] seq_expect;

    task fill_fb(input integer fno);
        integer k;
        begin
            fb_mem[0] = fno;                     // 字 0 = 帧号（与工程布局一致）
            for (k = 1; k < FB_WORDS; k = k + 1)
                fb_mem[k] = {8'hC0 + fno[7:0], 8'hB0 + k[7:0], 8'hA0 + k[15:8], 8'h90 + fno[7:0]};
        end
    endtask

    task check_block(input [31:0] base, input integer fno);
        integer b;
        begin
            for (b = 0; b < FRAME_BYTES; b = b + 1) begin
                if (ddr_mem[base + b] !== fb_mem[b/4][(b%4)*8 +: 8]) begin
                    $display("ERROR: 帧 %0d 基址 %h 第 %0d 字节不符：DDR=%02h fb=%02h",
                             fno, base, b, ddr_mem[base+b], fb_mem[b/4][(b%4)*8 +: 8]);
                    errors = errors + 1;
                    b = FRAME_BYTES;      // 一帧只报一次
                end
            end
        end
    endtask

    task wait_publish(input [31:0] seq, input [31:0] base);
        integer t;
        begin
            t = 0;
            while ((wr_seq !== seq || wr_base !== base) && t < 200000) begin
                @(posedge clk_fb);
                t = t + 1;
            end
            if (t >= 200000) begin
                $display("ERROR: 等第 %0d 帧发布超时（wr_seq=%0d base=%h）", seq, wr_seq, wr_base);
                errors = errors + 1;
            end
            if (wr_status[0] !== 1'b1) begin
                $display("ERROR: 发布后 wr_status.bit0(valid) 不是 1"); errors = errors + 1;
            end
            if (wr_len !== FRAME_BYTES) begin
                $display("ERROR: wr_len=%0d 期望 %0d", wr_len, FRAME_BYTES); errors = errors + 1;
            end
        end
    endtask

    // ---------------- 主流程 ----------------
    initial begin
        #100 rst_fb = 0; rst_ddr = 0;
        #200 ddr_cal_done = 1;
        #200 ddr_en = 1;

        // ---- 第 1 帧 → BASE0 ----
        fill_fb(1);
        @(posedge clk_fb); fb_frame_cnt = 1;
        @(posedge clk_fb);
        wait_publish(1, BASE0);
        check_block(BASE0, 1);

        // ---- 第 2 帧 → BASE1 ----
        fill_fb(2);
        @(posedge clk_fb); fb_frame_cnt = 2;
        @(posedge clk_fb);
        wait_publish(2, BASE1);
        check_block(BASE1, 2);

        // ---- 第 3 帧 → 又回 BASE0（双缓冲交替）----
        fill_fb(3);
        @(posedge clk_fb); fb_frame_cnt = 3;
        @(posedge clk_fb);
        wait_publish(3, BASE0);
        check_block(BASE0, 3);

        // ---- 撕裂：搬运中途 fb_busy 拉高 → 本帧不发布、err_cnt +1 ----
        fill_fb(4);
        @(posedge clk_fb); fb_frame_cnt = 4;
        repeat (40) @(posedge clk_fb);
        fb_busy = 1;                        // 新一帧开始写 fb
        repeat (10) @(posedge clk_fb);
        fb_busy = 0;
        repeat (4000) @(posedge clk_fb);    // 等搬运结束
        if (wr_seq !== 32'd3) begin
            $display("ERROR: 撕裂帧被错误发布了，wr_seq=%0d", wr_seq); errors = errors + 1;
        end
        if (wr_status[31:16] !== 16'd1) begin
            $display("ERROR: err_cnt=%0d 期望 1", wr_status[31:16]); errors = errors + 1;
        end

        // ---- AXI 侧突发总数：3 个成功帧 + 1 个撕裂帧，每帧 NBURST 个 ----
        if (err_cnt_tb != 0) errors = errors + err_cnt_tb;
        if (nburst_done !== NBURST * 4) begin
            $display("ERROR: 突发数=%0d 期望 %0d", nburst_done, NBURST * 4); errors = errors + 1;
        end

        if (errors == 0) $display("ALL PASS（%0d 个突发）", nburst_done);
        else             $display("FAIL: %0d 处不符", errors);
        $finish;
    end

endmodule
