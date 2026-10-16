///////////////////////////////////////////////////////////////
//  tb_ddr_chain.v — 「主机寄存器面 → fb 读口仲裁 → DDR 搬运」整条链冒烟测试
//
//  本 TB 把顶层这三段按真实连法接起来（顶层里 ep_bar_win 在引擎内部、另两个在顶层，
//  组合关系一样）：
//    ep_bar_win（寄存器窗口 + 0x60 预取 + host_rd_prio）
//      ↕ fb 唯一读口（img_frame_src 内仲裁：主机预取优先，其余时间给 DMA）
//    ddr_frame_writer（读 fb → 拼 256bit → 异步 FIFO → AXI4 写突发）
//      ↕ 行为级 AXI 从机（按 AXI4 规则握手、可制造 W 反压）
//  并把它照顶层修好后的方向拼成寄存器字：ddr_ro = {len, status, base, seq}。
//
//  验证什么（对应任务书的验收前提）：
//   1) 主机能经 TLP 写 CTRL[5]=ddr_en、开测试图源；一帧写好 → DMA 搬进「DDR」；
//   2) 主机读 0xA0/0xA4/0xA8/0xAC 拿到的帧号/基址/状态/长度与实测一致
//      （上一版这几个字在板上全读 0，因为顶层 assign 方向写反）；
//   3) DDR 里的字节与 img_frame_src 里 fb[] 逐字节相同（整块都是像素）；
//   4) 搬运进行中主机仍然能读 0x60（读口仲裁不给主机饿死），且第二帧照常发布。
//
//  跑法（$HOME/.local/ivl/bin 已在 PATH）：
//      IVL_B=$HOME/.local/ivl/lib/x86_64-linux-gnu/ivl
//      iverilog -B $IVL_B -g2005 -o /tmp/tb_chain tb_ddr_chain.v \
//        ../rtl/ep_side/img/ep_bar_win.v ../rtl/ep_side/img/img_frame_src.v \
//        ../rtl/ep_side/ddr/ddr_frame_writer.v
//      vvp -M $IVL_B /tmp/tb_chain          # 期望 "ALL PASS"
///////////////////////////////////////////////////////////////
`timescale 1ns/1ps

module tb_ddr_chain;

    localparam integer W   = 640;
    localparam integer H   = 480;
    localparam integer FB_WORDS = (W*H)/4;      // 76800
    localparam integer NBEATS   = (W*H)/32;     // 9600
    localparam integer BB       = 128;          // 每突发拍数（与工程一致）
    localparam integer NBURST   = NBEATS/BB;    // 75
    localparam [31:0]  BASE0 = 32'h0010_0000;
    localparam [31:0]  BASE1 = 32'h0018_0000;

    reg clk_fb  = 0;      // 62.5MHz
    reg clk_ddr = 0;      // 100MHz
    reg rst_fb  = 1, rst_ddr = 1;
    always #8 clk_fb  = ~clk_fb;
    always #5 clk_ddr = ~clk_ddr;

    integer errors = 0;

    // ================= 主机侧：合成 TLP 打 ep_bar_win =================
    reg          rx_sop_ff = 0;
    reg  [255:0] rx_data_ff = 0;
    wire [255:0] mrdata_rd_data;
    wire [6:0]   memrd_addr_lo, cam_tap_cfg;
    wire         ctrl_enable, ctrl_trigger, ctrl_ddr_en, ctrl_push_en, ctrl_push_src;
    wire [1:0]   ctrl_pattern;
    wire [31:0]  push_dst_lo, push_dst_hi, push_db_lo, push_db_hi;
    wire         host_rd_prio, host_grant;
    wire [31:0]  fb_raddr, fb_rdata, dbg_rd_idx;
    wire [31:0]  img_frame_cnt, img_data_len, img_fb_rd2_addr, img_fb_rd2_data;
    wire [15:0]  img_width, img_height;
    wire         img_ready, img_busy, img_dma_req, img_dma_grant;
    wire [31:0]  wr_seq, wr_base, wr_status, wr_len;

    // 顶层修好后的拼接方向：ddr_ro = {len, status, base, seq}
    wire [127:0] ddr_ro = {wr_len, wr_status, wr_base, wr_seq};

    ep_bar_win #(
        .MAGIC(32'h5043_4946), .VERSION(32'h0002_0000),
        .PTR_BYTES(32'h0004_B000), .CLK_MHZ(9'd62)
    ) u_bar (
        .clk(clk_fb), .rst(rst_fb),
        .rx_sop_ff(rx_sop_ff), .rx_data_ff(rx_data_ff),
        .mrdata_rd_data(mrdata_rd_data), .memrd_addr_lo(memrd_addr_lo),
        .cam_tap_cfg(cam_tap_cfg),
        .ctrl_enable(ctrl_enable), .ctrl_trigger(ctrl_trigger),
        .ctrl_pattern(ctrl_pattern),
        .ctrl_ddr_en(ctrl_ddr_en), .ddr_ro(ddr_ro),
        .push_ro(128'd0), .ctrl_push_en(ctrl_push_en), .ctrl_push_src(ctrl_push_src),
        .push_dst_lo(push_dst_lo), .push_dst_hi(push_dst_hi),
        .push_db_lo(push_db_lo), .push_db_hi(push_db_hi),
        .host_rd_prio(host_rd_prio), .host_grant(host_grant),
        .st_ready(img_ready), .st_busy(img_busy), .st_frame_cnt(img_frame_cnt),
        .st_width(img_width), .st_height(img_height), .st_data_len(img_data_len),
        .fb_raddr(fb_raddr), .fb_rdata(fb_rdata), .dbg_rd_idx(dbg_rd_idx),
        .cam_stat(256'h0)
    );

    img_frame_src #(
        .W(W), .H(H), .IDLE_CYCLE(200000)   // 帧间空闲 3.2ms：模拟真实的「行读出很短、消隐很长」
    ) u_src (
        .clk(clk_fb), .rst(rst_fb),
        .enable(ctrl_enable), .trigger(ctrl_trigger),
        .rd_addr(fb_raddr), .rd_data(fb_rdata),
        .host_rd_prio(host_rd_prio), .dma_rd_req(img_dma_req),
        .host_grant(host_grant), .dma_grant(img_dma_grant),
        .rd2_addr(img_fb_rd2_addr), .rd2_data(img_fb_rd2_data),
        .dbg_rd_idx(dbg_rd_idx),
        .frame_cnt(img_frame_cnt), .width(img_width), .height(img_height),
        .data_len(img_data_len), .ready(img_ready), .busy(img_busy),
        .cam_sel(1'b0),
        .cam_wr_en(1'b0), .cam_wr_addr(32'd0), .cam_wr_data(32'd0),
        .cam_frame_cnt(32'd0), .cam_data_len(32'd0),
        .cam_ready(1'b0), .cam_busy(1'b0)
    );

    ddr_frame_writer #(
        .W(W), .H(H), .BASE0(BASE0), .BASE1(BASE1),
        .BURST_BEATS(BB)
    ) u_wr (
        .clk_fb(clk_fb), .rst_fb(rst_fb), .ddr_en(ctrl_ddr_en),
        .fb_frame_cnt(img_frame_cnt), .fb_busy(img_busy),
        .fb_rd_addr(img_fb_rd2_addr), .fb_rd_data(img_fb_rd2_data),
        .fb_req(img_dma_req), .fb_grant(img_dma_grant),
        .clk_ddr(clk_ddr), .rst_ddr(rst_ddr), .ddr_cal_done(1'b1),
        .m_axi_awaddr(awaddr), .m_axi_awlen(awlen), .m_axi_awsize(awsize),
        .m_axi_awburst(awburst), .m_axi_awvalid(awvalid), .m_axi_awready(awready),
        .m_axi_wdata(wdata), .m_axi_wstrb(wstrb), .m_axi_wlast(wlast),
        .m_axi_wvalid(wvalid), .m_axi_wready(wready),
        .m_axi_bresp(bresp), .m_axi_bvalid(bvalid), .m_axi_bready(bready),
        .wr_frame_seq(wr_seq), .wr_base(wr_base), .wr_status(wr_status), .wr_len(wr_len)
    );

    // ================= 行为级 AXI 从机 + 假 DDR =================
    wire [28:0]  awaddr;
    wire [7:0]   awlen;
    wire [2:0]   awsize;
    wire [1:0]   awburst;
    wire         awvalid;
    reg          awready = 0;
    wire [255:0] wdata;
    wire [31:0]  wstrb;
    wire         wlast, wvalid;
    reg          wready = 0;
    reg  [1:0]   bresp = 2'b00;
    reg          bvalid = 0;
    wire         bready;

    localparam DDR_BYTES = 32'h0020_0000;
    reg [7:0] ddr_mem [0:DDR_BYTES-1];

    reg        w_active = 0;
    reg [28:0] aw_addr_r;
    reg [7:0]  w_idx;
    reg [2:0]  stall_cnt = 3'd0;
    integer    nburst_done = 0;
    integer    j;

    always @(posedge clk_ddr) stall_cnt <= stall_cnt + 3'd1;

    always @(posedge clk_ddr or posedge rst_ddr) begin
        if (rst_ddr) begin
            awready <= 0; wready <= 0; w_active <= 0; bvalid <= 0;
            w_idx <= 0; aw_addr_r <= 0;
        end else begin
            awready <= 1'b0;
            if (awvalid && !w_active && !bvalid && !awready) begin
                awready   <= 1'b1;
                aw_addr_r <= awaddr;
                if (awlen !== BB-1) begin $display("ERROR: awlen=%0d 期望 %0d", awlen, BB-1); errors=errors+1; end
                if (awsize !== 3'd5) begin $display("ERROR: awsize=%0d 期望 5", awsize); errors=errors+1; end
                if ((awaddr[11:0] + (BB*32) - 1) >> 12 !== awaddr[11:0] >> 12) begin
                    $display("ERROR: 突发 %h 跨了 4KB 页", awaddr); errors=errors+1; end
                w_active <= 1'b1;
                w_idx    <= 8'd0;
            end

            wready <= 1'b0;
            if (w_active) begin
                wready <= (stall_cnt != 3'd3);            // 每 8 拍停 1 拍：制造 W 反压
                if (wvalid && wready) begin
                    for (j = 0; j < 32; j = j + 1)
                        ddr_mem[aw_addr_r + w_idx*32 + j] <= wdata[j*8 +: 8];
                    if (wlast !== (w_idx == BB-1)) begin
                        $display("ERROR: 第 %0d 拍 wlast=%b 不对", w_idx, wlast); errors=errors+1; end
                    if (w_idx == BB-1) begin
                        w_active <= 1'b0;
                        bvalid   <= 1'b1;
                        nburst_done = nburst_done + 1;
                    end else w_idx <= w_idx + 8'd1;
                end
            end

            if (bvalid && bready) bvalid <= 1'b0;
        end
    end

    // ================= 主机 TLP 任务 =================
    function [31:0] bswap32;
        input [31:0] x;
        begin bswap32 = {x[7:0], x[15:8], x[23:16], x[31:24]}; end
    endfunction

    task tlp_wr(input [11:0] off, input [31:0] val);
        begin
            @(negedge clk_fb);
            rx_data_ff = 256'd0;
            rx_data_ff[255:248] = 8'b0100_0000;
            rx_data_ff[191:160] = {20'd0, off};
            rx_data_ff[159:128] = bswap32(val);
            rx_sop_ff = 1'b1;
            @(negedge clk_fb);
            rx_sop_ff = 1'b0;
            rx_data_ff = 256'd0;
        end
    endtask

    task tlp_rd(input [11:0] off, output [31:0] val);
        begin
            @(negedge clk_fb);
            rx_data_ff = 256'd0;
            rx_data_ff[255:248] = 8'b0000_0000;
            rx_data_ff[191:160] = {20'd0, off};
            rx_sop_ff = 1'b1;
            @(negedge clk_fb);
            rx_sop_ff = 1'b0;
            val = bswap32(mrdata_rd_data[255:224]);
            rx_data_ff = 256'd0;
        end
    endtask

    task check(input [255:0] name, input [31:0] got, input [31:0] exp);
        begin
            if (got !== exp) begin
                $display("ERROR: %0s = %08h 期望 %08h", name, got, exp);
                errors = errors + 1;
            end else $display("  OK  %0s = %08h", name, got);
        end
    endtask

    // ================= 主流程 =================
    reg [31:0] v, v_seq, v_base;
    integer    t, k, bad;

    initial begin
        #100 rst_fb = 0; rst_ddr = 0;
        repeat (20) @(negedge clk_fb);

        // ---- 开测试图源（CTRL[0]=1），等第一帧写好 ----
        tlp_wr(12'h44, 32'h0000_0001);
        v = 0;
        while (img_ready !== 1'b1 && v < 600000) begin @(negedge clk_fb); v = v + 1; end  // 测试图源 4 拍写 1 字 ⇒ 一帧 307200 拍
        if (img_ready !== 1'b1) begin $display("ERROR: 测试图源没出帧"); errors=errors+1; end
        else $display("  OK  测试图源出帧，frame_cnt=%0d", img_frame_cnt);

        // ---- 开 DDR 搬运（CTRL[5]=1）----
        tlp_wr(12'h44, 32'h0000_0021);
        t = 0;
        while (wr_seq === 32'd0 && t < 900000) begin @(negedge clk_fb); t = t + 1; end  // 帧周期≈507200 拍
        if (wr_seq === 32'd0) begin
            $display("ERROR: 等第一次发布超时（wr_seq 仍为 0）"); errors = errors + 1;
        end else begin
            $display("  OK  第一帧已发布：seq=%0d base=%h 用时 %0d fb 拍", wr_seq, wr_base, t);
            // ---- 主机读握手字（这就是板上全读 0 的那四个）----
            tlp_rd(12'hA0, v); check("0xA0 DDR_FRAME_SEQ", v, wr_seq);
            tlp_rd(12'hA4, v); check("0xA4 DDR_BASE     ", v, wr_base);
            tlp_rd(12'hA8, v);
            if (v[0] !== 1'b1) begin $display("ERROR: 0xA8 bit0 valid 不是 1（=%08h）", v); errors=errors+1; end
            else $display("  OK  0xA8 DDR_STATUS = %08h（bit0 valid=1）", v);
            tlp_rd(12'hAC, v); check("0xAC DDR_LEN      ", v, 32'h0004_B000);
            tlp_rd(12'h4C, v); $display("  --  0x4C FRAME_CNT = %0d", v);

            // ---- DDR 内容 vs fb[] 逐字节 ----
            bad = 0;
            for (k = 0; k < FB_WORDS; k = k + 1)
                if (ddr_mem[wr_base + k*4 + 0] !== u_src.fb[k][7:0]  ||
                    ddr_mem[wr_base + k*4 + 1] !== u_src.fb[k][15:8] ||
                    ddr_mem[wr_base + k*4 + 2] !== u_src.fb[k][23:16]||
                    ddr_mem[wr_base + k*4 + 3] !== u_src.fb[k][31:24]) begin
                    if (bad == 0)
                        $display("ERROR: DDR 第 %0d 字不符：DDR=%02h%02h%02h%02h fb=%08h",
                                 k, ddr_mem[wr_base+k*4+3], ddr_mem[wr_base+k*4+2],
                                 ddr_mem[wr_base+k*4+1], ddr_mem[wr_base+k*4+0], u_src.fb[k]);
                    bad = bad + 1;
                end
            if (bad != 0) begin $display("ERROR: DDR 内容与 fb 有 %0d 个字不符", bad); errors = errors + 1; end
            else $display("  OK  DDR 内容与 fb[] 逐字节一致（%0d 字）", FB_WORDS);
        end

        // ---- 搬运进行中主机读 0x60：仲裁不许把主机饿死 ----
        tlp_wr(12'h5C, 32'h0000_0000);
        repeat (20) @(negedge clk_fb);
        tlp_rd(12'h5C, v); check("0x5C PTR readback", v, 32'd0);
        tlp_rd(12'h60, v); check("0x60 di1=fb[0]", v, u_src.fb[0]);
        repeat (12) @(negedge clk_fb);   // RTL 约定：两次 0x60 读间隔要 ≥6 拍
        tlp_rd(12'h60, v);
        if (v !== u_src.fb[1]) begin
            $display("ERROR: 0x60 2nd word = %08h exp %08h", v, u_src.fb[1]);
            errors = errors + 1;
        end else $display("  OK  0x60 2nd word == fb[1]（预取 + 仲裁正常）");

        // ---- 第二帧照常发布 ----
        v_seq = wr_seq;
        t = 0;
        while (wr_seq === v_seq && t < 600000) begin @(negedge clk_fb); t = t + 1; end
        if (wr_seq === v_seq) begin
            $display("ERROR: 第二帧没发布（%0d 拍没等到）", t); errors = errors + 1;
        end else $display("  OK  第二帧发布 seq=%0d base=%h（双缓冲交替）", wr_seq, wr_base);

        if (nburst_done === 0) begin $display("ERROR: AXI 侧一个突发都没收到"); errors=errors+1; end
        else $display("  OK  AXI 突发数 = %0d", nburst_done);

        if (errors == 0) $display("ALL PASS");
        else             $display("FAIL: %0d 处不符", errors);
        $finish;
    end

endmodule
