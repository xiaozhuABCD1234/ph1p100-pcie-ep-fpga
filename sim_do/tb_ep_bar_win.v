///////////////////////////////////////////////////////////////
//  tb_ep_bar_win.v — BAR0 窗口寄存器表冒烟测试（iverilog）
//
//  为什么要有它：上一版主机照 ep_bar_win.v 头部那张表读寄存器，结果 0xA0~0xAC
//  （DDR 握手字，连常数 DDR_LEN=0x4B000）全读 0、0xC8 却读出推帧状态字。根因在
//  顶层那条写反的 assign（把 ddr_ro 当成源 ⇒ 整条 128bit 悬空，TD SYN-5013），
//  以及 img_push_ro 的拼接顺序与表不一致。本测试台用「合成的 MRd/MWr 包」直接
//  打这个模块，逐条核对：**表里写的偏移/位域 = RTL 真正译码出来的**。
//
//  跑法：
//      export PATH=$HOME/.local/ivl/bin:$PATH
//      IVL_B=$HOME/.local/ivl/lib/x86_64-linux-gnu/ivl
//      iverilog -B $IVL_B -g2005 -o /tmp/tb_ep_bar_win tb_ep_bar_win.v \
//               ../rtl/ep_side/img/ep_bar_win.v
//      vvp -M $IVL_B /tmp/tb_ep_bar_win        # 期望 "ALL PASS"
//
//  包怎么拼（照 ep_bar_win.v 头部与 pcie_ep_engine.v 的字段位置）：
//    Fmt  = rx_data_ff[255:253]（000=3DW 读，010=3DW 写）
//    Type = rx_data_ff[252:248]（0 = Memory）
//    地址 = rx_data_ff[191:160]（3DW 头）
//    写数据 = rx_data_ff[159:128]，且主机侧要**字节倒序**（模块内部再 bswap32）
//  读回：完成包第 0 个 dw 在 mrdata_rd_data[255:224]，同样要 bswap32 还原。
//
//  本 TB 只用行为级驱动，不碰 PCIe 核：ep_bar_win 是纯组合 mux + 小状态机。
///////////////////////////////////////////////////////////////
`timescale 1ns/1ps

module tb_ep_bar_win;

    reg         clk = 0;
    reg         rst = 1;
    always #8 clk = ~clk;          // 62.5MHz（tl_clk_user）

    // ---- 引擎 rx 流水线 ----
    reg          rx_sop_ff = 0;
    reg  [255:0] rx_data_ff = 0;
    wire [255:0] mrdata_rd_data;
    wire [6:0]   memrd_addr_lo;
    wire [6:0]   cam_tap_cfg;
    wire [6:0]   cam_tap_b_cfg;
    wire         ctrl_enable, ctrl_trigger, ctrl_ddr_en, ctrl_push_en, ctrl_push_src;
    reg  [255:0] cam_stat_r = 256'h0;   // 相机状态字（0xD0 读它的 [255:224]）
    wire [1:0]   ctrl_pattern;   // {CTRL[3], CTRL[2]}（测试图源图案，[0] 兼作重触发）
    // B 路推帧寄存器面（0x100~0x11C）：与 A 路同一套字段，另一组寄存器
    wire         ctrl_push_b_en;  // CTRL[8] = B 路推帧使能
    wire [31:0]  push_dst_lo_b, push_dst_hi_b, push_db_lo_b, push_db_hi_b;
    wire [31:0]  push_dst_lo, push_dst_hi, push_db_lo, push_db_hi;
    wire         host_rd_prio;
    wire         host_grant = 1'b1;
    wire [31:0]  fb_raddr;
    wire [31:0]  fb_rdata = 32'hA5A5_5A5A;
    wire [31:0]  dbg_rd_idx;

    // ---- 两个「只读字」总线的驱动值（顶层按这张表的顺序拼）----
    //   ddr_ro = {len, status, base, seq}  → 0xAC/0xA8/0xA4/0xA0
    //   push_ro = {tlp_cnt, err, status, done} → 0xCC/0xC8/0xC4/0xC0
    localparam [31:0] D_LEN    = 32'h0004_B000;   // 307200（常数）
    localparam [31:0] D_STATUS = 32'h0001_0018;   // err_cnt=1, cal_done|alive
    localparam [31:0] D_BASE   = 32'h0018_0000;
    localparam [31:0] D_SEQ    = 32'h0000_1234;
    localparam [31:0] P_TLP    = 32'd2400;
    localparam [7:0]  P_ERR    = 8'h02;          // 0xC8 只占 {24'd0, err} 里的低 8 位
    localparam [31:0] P_STATUS = 32'h0003_0007;   // err_cnt=3, cal|alive|db_sent|last_ok|busy
    localparam [31:0] P_DONE   = 32'd42;
    localparam [31:0] QB_DONE  = 32'd17;          // B 路已推帧数
    localparam [31:0] QB_STAT  = 32'h0005_0003;   // B 路状态（err_cnt=5, db_sent|last_ok）
    localparam [7:0]  QB_ERR   = 8'h04;           // B 路错误码 = 门铃地址未配置
    localparam [31:0] QB_TLP   = 32'd64800;       // B 路 4K 一帧的 MWr 数
    wire [127:0] ddr_ro    = {D_LEN, D_STATUS, D_BASE, D_SEQ};
    wire [127:0] push_ro   = {P_TLP, 24'd0, P_ERR, P_STATUS, P_DONE};
    wire [127:0] push_ro_b = {QB_TLP, 24'd0, QB_ERR, QB_STAT, QB_DONE};

    ep_bar_win #(
        .MAGIC(32'h5043_4946), .VERSION(32'h0002_0000),
        .PTR_BYTES(32'h0004_B000), .CLK_MHZ(9'd62)
    ) dut (
        .clk(clk), .rst(rst),
        .rx_sop_ff(rx_sop_ff), .rx_data_ff(rx_data_ff),
        .mrdata_rd_data(mrdata_rd_data), .memrd_addr_lo(memrd_addr_lo),
        .cam_tap_cfg(cam_tap_cfg),
        .cam_tap_b_cfg(cam_tap_b_cfg),
        .ctrl_enable(ctrl_enable), .ctrl_trigger(ctrl_trigger),
        .ctrl_pattern(ctrl_pattern),
        .ctrl_ddr_en(ctrl_ddr_en), .ddr_ro(ddr_ro),
        .push_ro(push_ro), .ctrl_push_en(ctrl_push_en), .ctrl_push_src(ctrl_push_src),
        .push_dst_lo(push_dst_lo), .push_dst_hi(push_dst_hi),
        .push_db_lo(push_db_lo), .push_db_hi(push_db_hi),
        .push_ro_b(push_ro_b), .ctrl_push_b_en(ctrl_push_b_en),
        .push_dst_lo_b(push_dst_lo_b), .push_dst_hi_b(push_dst_hi_b),
        .push_db_lo_b(push_db_lo_b), .push_db_hi_b(push_db_hi_b),
        .host_rd_prio(host_rd_prio), .host_grant(host_grant),
        .st_ready(1'b1), .st_busy(1'b0), .st_frame_cnt(32'h0000_7004),
        .st_width(16'd640), .st_height(16'd480), .st_data_len(32'h0004_B000),
        .fb_raddr(fb_raddr), .fb_rdata(fb_rdata), .dbg_rd_idx(dbg_rd_idx),
        .cam_stat(cam_stat_r)
    );

    function [31:0] bswap32;
        input [31:0] x;
        begin
            bswap32 = {x[7:0], x[15:8], x[23:16], x[31:24]};
        end
    endfunction

    integer errors = 0;
    integer i;

    // ---------------- 合成 TLP ----------------
    task tlp_wr(input [11:0] off, input [31:0] val);
        begin
            @(negedge clk);
            rx_data_ff       = 256'd0;
            rx_data_ff[255:248] = 8'b0100_0000;      // Fmt=010 3DW 写, Type=00000
            rx_data_ff[191:160] = {20'd0, off};
            rx_data_ff[159:128] = bswap32(val);      // 主机侧倒序放
            rx_sop_ff        = 1'b1;
            @(negedge clk);
            rx_sop_ff        = 1'b0;
            rx_data_ff       = 256'd0;
        end
    endtask

    task tlp_rd(input [11:0] off, output [31:0] val);
        begin
            @(negedge clk);
            rx_data_ff       = 256'd0;
            rx_data_ff[255:248] = 8'b0000_0000;      // Fmt=000 3DW 读, Type=00000
            rx_data_ff[191:160] = {20'd0, off};
            rx_sop_ff        = 1'b1;
            @(negedge clk);                          // 下一拍才取样完成包
            rx_sop_ff        = 1'b0;
            val = bswap32(mrdata_rd_data[255:224]);
            rx_data_ff       = 256'd0;
        end
    endtask

    task check(input [127:0] name, input [31:0] got, input [31:0] exp);
        begin
            if (got !== exp) begin
                $display("ERROR: %0s 读回 %08h 期望 %08h", name, got, exp);
                errors = errors + 1;
            end else begin
                $display("  OK  %0s = %08h", name, got);
            end
        end
    endtask

    reg [31:0] v;

    initial begin
        #50 rst = 0;
        repeat (5) @(negedge clk);

        $display("=== BAR0 寄存器表（以 ep_bar_win.v 头部那张表为准）===");
        tlp_rd(12'h40, v); check("0x40 MAGIC    ", v, 32'h5043_4946);
        tlp_rd(12'h48, v); check("0x48 STATUS   ", v, 32'h0000_0001);   // ready=1,busy=0
        tlp_rd(12'h4C, v); check("0x4C FRAME_CNT", v, 32'h0000_7004);
        tlp_rd(12'h50, v); check("0x50 WIDTH    ", v, 32'd640);
        tlp_rd(12'h54, v); check("0x54 HEIGHT   ", v, 32'd480);
        tlp_rd(12'h58, v); check("0x58 DATA_LEN ", v, 32'h0004_B000);
        tlp_rd(12'h64, v); check("0x64 VERSION  ", v, 32'h0002_0000);
        tlp_rd(12'h68, v); check("0x68 CLK_MHZ  ", v, 32'd62);
        // 0xD0 = cam_stat[255:224]（相机 4K 直通通路的诊断字）：先灌一个值再读回
        cam_stat_r[255:224] = 32'h1234_5678;
        #10;
        tlp_rd(12'hD0, v); check("0xD0 CAM_DDR_DIAG", v, 32'h1234_5678);
        cam_stat_r[255:224] = 32'h0;

        // ---- 0x44 CTRL：位域与读回 ----
        //  位义（见 ep_bar_win.v 头部表）：bit0 enable / bit1 trigger(自清) /
        //  [3:2] pattern / bit4 保留 / bit5 ddr_en / bit6 push_en(A 路) /
        //  bit7 push_src / bit8 push_b(B 路推帧使能)
        tlp_wr(12'h44, 32'h0000_00C1);                  // enable|push_en|push_src（不含 bit5 ddr_en）
        tlp_rd(12'h44, v); check("0x44 CTRL      ", v, 32'h0000_00C1);
        if (ctrl_enable !== 1'b1)    begin $display("ERROR: CTRL bit0 enable 没生效"); errors=errors+1; end
        if (ctrl_push_en !== 1'b1)   begin $display("ERROR: CTRL bit6 push_en 没生效"); errors=errors+1; end
        if (ctrl_push_src !== 1'b1)  begin $display("ERROR: CTRL bit7 push_src 没生效"); errors=errors+1; end
        if (ctrl_push_b_en !== 1'b0) begin $display("ERROR: CTRL bit8 默认应为 0（只推 A 路）"); errors=errors+1; end
        if (ctrl_ddr_en !== 1'b0)    begin $display("ERROR: CTRL bit5 ddr_en 应为 0"); errors=errors+1; end
        // CTRL[3:2] 原样送出（0x1E1 的 bit3:2 = 00）
        if (ctrl_pattern[1:0] !== 2'b00) begin $display("ERROR: CTRL bit3:2 没送到 ctrl_pattern"); errors=errors+1; end
        tlp_wr(12'h44, 32'h0000_01ED);                  // 再加 bit5 ddr_en + bit3:2=11 + bit8 push_b
        tlp_rd(12'h44, v); check("0x44 CTRL pat  ", v, 32'h0000_01ED);
        if (ctrl_pattern[1:0] !== 2'b11) begin $display("ERROR: CTRL bit3:2=11 没送到 ctrl_pattern"); errors=errors+1; end
        if (ctrl_ddr_en !== 1'b1)    begin $display("ERROR: CTRL bit5 ddr_en 没生效"); errors=errors+1; end
        if (ctrl_push_b_en !== 1'b1) begin $display("ERROR: CTRL bit8 push_b 没送到 ctrl_push_b_en"); errors=errors+1; end
        tlp_wr(12'h44, 32'h0000_00ED);                  // 清 bit8（只推 A 路）
        tlp_rd(12'h44, v); check("0x44 CTRL clr  ", v, 32'h0000_00ED);
        if (ctrl_push_b_en !== 1'b0) begin $display("ERROR: CTRL bit8 push_b 清不掉"); errors=errors+1; end
        // bit4 是保留位：写 1 不该读回 1（bit3 是 pattern 高位，读回应保留）
        tlp_wr(12'h44, 32'h0000_0019);
        tlp_rd(12'h44, v); check("0x44 CTRL rsvd ", v, 32'h0000_0009);

        tlp_wr(12'h44, 32'h0000_0042);                  // trigger + push_en
        tlp_rd(12'h44, v); check("0x44 CTRL trig ", v, 32'h0000_0040);
        if (ctrl_trigger !== 1'b0) begin $display("ERROR: CTRL bit1 trigger 没自动清"); errors=errors+1; end

        // ---- 0x5C / 0x6C / 0x9C / 0xD4 读写 ----
        tlp_wr(12'h5C, 32'h0000_1000);
        tlp_rd(12'h5C, v); check("0x5C PTR      ", v, 32'h0000_1000);
        tlp_wr(12'h6C, 32'h1234_5678);
        tlp_rd(12'h6C, v); check("0x6C SCRATCH  ", v, 32'h1234_5678);
        tlp_wr(12'h9C, 32'h0000_0026);
        tlp_rd(12'h9C, v); check("0x9C CAM_TAP  ", v, 32'h0000_0026);
        // 0xD4 = B 路 tap：与 A 路各自独立（A/B 眼图不同必须分开配）
        tlp_wr(12'hD4, 32'h0000_0041);
        tlp_rd(12'hD4, v); check("0xD4 CAM_B_TAP", v, 32'h0000_0041);
        tlp_rd(12'h9C, v); check("0xD4 写后 A 路不变", v, 32'h0000_0026);
        if (cam_tap_cfg !== 7'h26) begin $display("ERROR: cam_tap_cfg 应为 7'h26"); errors=errors+1; end
        if (cam_tap_b_cfg !== 7'h41) begin $display("ERROR: cam_tap_b_cfg 应为 7'h41"); errors=errors+1; end

        // ---- DDR 握手字（0xA0~0xAC）----
        $display("---+ DDR 握手字（顶层拼 ddr_ro = {len,status,base,seq}）");
        tlp_rd(12'hA0, v); check("0xA0 DDR_FRAME_SEQ", v, D_SEQ);
        tlp_rd(12'hA4, v); check("0xA4 DDR_BASE     ", v, D_BASE);
        tlp_rd(12'hA8, v); check("0xA8 DDR_STATUS   ", v, D_STATUS);
        tlp_rd(12'hAC, v); check("0xAC DDR_LEN      ", v, D_LEN);

        // ---- 推帧寄存器（0xB0~0xCC）----
        $display("---+ 推帧寄存器（顶层拼 push_ro = {tlp_cnt,err,status,done}）");
        tlp_wr(12'hB0, 32'hFFE0_0000);
        tlp_rd(12'hB0, v); check("0xB0 PUSH_DST_LO  ", v, 32'hFFE0_0000);
        tlp_wr(12'hB4, 32'h0000_0000);
        tlp_rd(12'hB4, v); check("0xB4 PUSH_DST_HI  ", v, 32'h0000_0000);
        tlp_wr(12'hB8, 32'hFFF3_0040);
        tlp_rd(12'hB8, v); check("0xB8 PUSH_DB_LO   ", v, 32'hFFF3_0040);
        tlp_wr(12'hBC, 32'h0000_0000);
        tlp_rd(12'hBC, v); check("0xBC PUSH_DB_HI   ", v, 32'h0000_0000);
        tlp_rd(12'hC0, v); check("0xC0 PUSH_DONE    ", v, P_DONE);
        tlp_rd(12'hC4, v); check("0xC4 PUSH_STATUS  ", v, P_STATUS);
        tlp_rd(12'hC8, v); check("0xC8 PUSH_ERR     ", v, P_ERR);
        tlp_rd(12'hCC, v); check("0xCC PUSH_TLP_CNT ", v, P_TLP);

        // ---- B 路推帧寄存器（0x100~0x11C）：与 A 路同一套字段、另一组寄存器 ----
        $display("---+ B 路推帧寄存器（0x100~0x11C）");
        tlp_wr(12'h100, 32'hFF7E_B000);
        tlp_rd(12'h100, v); check("0x100 PUSH_DST_LO_B  ", v, 32'hFF7E_B000);
        tlp_wr(12'h104, 32'h0000_0000);
        tlp_rd(12'h104, v); check("0x104 PUSH_DST_HI_B  ", v, 32'h0000_0000);
        tlp_wr(12'h108, 32'hFFFD_5020);
        tlp_rd(12'h108, v); check("0x108 PUSH_DB_LO_B   ", v, 32'hFFFD_5020);
        tlp_wr(12'h10C, 32'h0000_0000);
        tlp_rd(12'h10C, v); check("0x10C PUSH_DB_HI_B   ", v, 32'h0000_0000);
        tlp_rd(12'h110, v); check("0x110 PUSH_DONE_B    ", v, QB_DONE);
        tlp_rd(12'h114, v); check("0x114 PUSH_STATUS_B  ", v, QB_STAT);
        tlp_rd(12'h118, v); check("0x118 PUSH_ERR_B     ", v, QB_ERR);
        tlp_rd(12'h11C, v); check("0x11C PUSH_TLP_CNT_B ", v, QB_TLP);
        // 写 B 路不能动 A 路
        tlp_rd(12'hB0, v); check("写 B 后 A 路 0xB0 不变", v, 32'hFFE0_0000);

        // ---- 0x60 数据口：PTR 自动前进（一次读 +4）----
        tlp_wr(12'h5C, 32'h0000_0000);
        repeat (8) @(negedge clk);                       // 等预取刷齐
        tlp_rd(12'h60, v);
        tlp_rd(12'h5C, v);
        if (v !== 32'd4) begin
            $display("ERROR: 读一次 0x60 后 PTR=%0d 期望 4", v); errors = errors + 1;
        end else $display("  OK  0x60 读一次后 PTR=4（自动前进）");

        if (errors == 0) $display("ALL PASS");
        else             $display("FAIL: %0d 处不符", errors);
        $finish;
    end

endmodule
