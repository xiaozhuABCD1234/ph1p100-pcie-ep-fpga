///////////////////////////////////////////////////////////////////////////////
//  tb_ep_bar_win_rka1.v — BAR0 窗口寄存器表 + RKA1 安全扩展冒烟测试（ModelSim）
//
//  基线：peer sim_do/tb_ep_bar_win.v（T03 冻结），本 TB 在其基础上：
//    · 用新端口表重新实例化 ep_bar_win（T07 加了 RKA1 扩展/诊断端口）；
//    · 保留基线全部旧寄存器检查（0x40/0x44/0x48/0x4C/0x50/0x54/0x58/0x64/0x68/
//      0x5C/0x6C/0x9C/0xD4/0xA0~0xAC/0xB0~0xCC/0xD0/0x60）；
//    · 新增 T07 检查（contract/registers.json 0x100..0x11C + 0x120..0x12C 诊断）：
//      0x100/0x104 staging、0x108 TX_CMD 单 bit 语义（读 0、多 bit/未知 bit 拒绝）、
//      0x10C/0x110、0x114 TX_STATUS、0x118 EXT_MAGIC=RKA1、0x11C EXT_VERSION=0x10000、
//      tx_block_cfg=1 时活动配置写被拒（值不变 + cfg_reject 脉冲 + 错误码 10 由安全门记）、
//      未实现偏移读 DEAD_BEEF（legacy 检测 fail-closed）。
//
//  打包方式与基线逐条相同（Fmt=rx_data_ff[255:253]、Type=[252:248]、地址=[191:160]、
//  写数据=[159:128] 且要倒序，读回 mrdata_rd_data[255:224] 再倒序还原）。
///////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps

module tb_ep_bar_win_rka1;

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
    reg  [255:0] cam_stat_r = 256'h0;
    wire [1:0]   ctrl_pattern;
    wire         cam_ab_sel;
    wire [31:0]  push_dst_lo, push_dst_hi, push_db_lo, push_db_hi;
    wire         host_rd_prio;
    wire         host_grant = 1'b1;
    wire [31:0]  fb_raddr;
    wire [31:0]  fb_rdata = 32'hA5A5_5A5A;
    wire [31:0]  dbg_rd_idx;

    // ---- T07 新端口 ----
    wire [31:0]  tx_cap_bytes, tx_session_id, tx_ack_seq, tx_ack_session;
    wire         tx_cmd_arm, tx_cmd_ack, tx_cmd_cancel;
    wire [31:0]  tx_status_in;
    reg          tx_block_cfg = 0;
    wire         cfg_reject;
    reg  [31:0]  csi_diag_a = 32'h1122_3344, csi_diag_a2 = 32'h5566_7788;
    reg  [31:0]  csi_diag_b = 32'h99AA_BBCC, csi_diag_b2 = 32'hDDEE_FF00;

    localparam [31:0] D_LEN    = 32'h0004_B000;
    localparam [31:0] D_STATUS = 32'h0001_0018;
    localparam [31:0] D_BASE   = 32'h0018_0000;
    localparam [31:0] D_SEQ    = 32'h0000_1234;
    localparam [31:0] P_TLP    = 32'd2400;
    localparam [7:0]  P_ERR    = 8'h02;
    localparam [31:0] P_STATUS = 32'h0003_0007;
    localparam [31:0] P_DONE   = 32'd42;
    wire [127:0] ddr_ro  = {D_LEN, D_STATUS, D_BASE, D_SEQ};
    wire [127:0] push_ro = {P_TLP, 24'd0, P_ERR, P_STATUS, P_DONE};

    ep_bar_win #(
        .MAGIC(32'h5043_4946), .VERSION(32'h0002_0000),
        .PTR_BYTES(32'h0004_B000), .CLK_MHZ(9'd62)
    ) dut (
        .clk(clk), .rst(rst),
        .rx_sop_ff(rx_sop_ff), .rx_data_ff(rx_data_ff),
        .mrdata_rd_data(mrdata_rd_data), .memrd_addr_lo(memrd_addr_lo),
        .cam_tap_cfg(cam_tap_cfg),
        .cam_tap_b_cfg(cam_tap_b_cfg),
        .cam_ab_sel(cam_ab_sel),
        .ctrl_enable(ctrl_enable), .ctrl_trigger(ctrl_trigger),
        .ctrl_pattern(ctrl_pattern),
        .ctrl_ddr_en(ctrl_ddr_en), .ddr_ro(ddr_ro),
        .push_ro(push_ro), .ctrl_push_en(ctrl_push_en), .ctrl_push_src(ctrl_push_src),
        .push_dst_lo(push_dst_lo), .push_dst_hi(push_dst_hi),
        .push_db_lo(push_db_lo), .push_db_hi(push_db_hi),
        .host_rd_prio(host_rd_prio), .host_grant(host_grant),
        .st_ready(1'b1), .st_busy(1'b0), .st_frame_cnt(32'h0000_7004),
        .st_width(16'd640), .st_height(16'd480), .st_data_len(32'h0004_B000),
        .fb_raddr(fb_raddr), .fb_rdata(fb_rdata), .dbg_rd_idx(dbg_rd_idx),
        .cam_stat(cam_stat_r),
        // T07
        .tx_cap_bytes(tx_cap_bytes), .tx_session_id(tx_session_id),
        .tx_cmd_arm(tx_cmd_arm), .tx_cmd_ack(tx_cmd_ack), .tx_cmd_cancel(tx_cmd_cancel),
        .tx_ack_seq(tx_ack_seq), .tx_ack_session(tx_ack_session),
        .tx_status_in(tx_status_in), .tx_block_cfg(tx_block_cfg),
        .cfg_reject(cfg_reject),
        .csi_diag_a(csi_diag_a), .csi_diag_a2(csi_diag_a2),
        .csi_diag_b(csi_diag_b), .csi_diag_b2(csi_diag_b2)
    );

    function [31:0] bswap32;
        input [31:0] x;
        begin
            bswap32 = {x[7:0], x[15:8], x[23:16], x[31:24]};
        end
    endfunction

    integer errors = 0;

    task tlp_wr(input [11:0] off, input [31:0] val);
        begin
            @(negedge clk);
            rx_data_ff       = 256'd0;
            rx_data_ff[255:248] = 8'b0100_0000;
            rx_data_ff[191:160] = {20'd0, off};
            rx_data_ff[159:128] = bswap32(val);
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
            rx_data_ff[255:248] = 8'b0000_0000;
            rx_data_ff[191:160] = {20'd0, off};
            rx_sop_ff        = 1'b1;
            @(negedge clk);
            rx_sop_ff        = 1'b0;
            val = bswap32(mrdata_rd_data[255:224]);
            rx_data_ff       = 256'd0;
        end
    endtask

    task check(input [127:0] name, input [31:0] got, input [31:0] exp);
        begin
            if (got !== exp) begin
                $display("ERROR: %0s read %08h expected %08h", name, got, exp);
                errors = errors + 1;
            end else begin
                $display("  OK  %0s = %08h", name, got);
            end
        end
    endtask

    // TX_CMD / cfg_reject 脉冲捕获（单拍，必须粘滞住才能查）
    reg arm_seen = 0, ack_seen = 0, cancel_seen = 0, rej_seen = 0;
    always @(posedge clk) begin
        if (tx_cmd_arm)    arm_seen    <= 1'b1;
        if (tx_cmd_ack)    ack_seen    <= 1'b1;
        if (tx_cmd_cancel) cancel_seen <= 1'b1;
        if (cfg_reject)    rej_seen    <= 1'b1;
        if (arm_seen | ack_seen | cancel_seen | rej_seen)
            $display("  PULSE @%0t arm=%b ack=%b can=%b rej=%b", $time, arm_seen, ack_seen, cancel_seen, rej_seen);
    end
    task clear_pulses; begin
        @(negedge clk); arm_seen = 0; ack_seen = 0; cancel_seen = 0; rej_seen = 0;
        @(negedge clk);
    end endtask

    // 脉冲检查：等几个边沿让 posedge 采样器把单拍脉冲记下来再比
    //（注意：不能用「调用时传值」的形参——那会在等待前就把 0 拷进来）
    task chk_pulse(input [127:0] name, input [1:0] sel, input exp);
        reg g;
        begin
            repeat (4) @(negedge clk);
            case (sel)
                2'd0: g = arm_seen;
                2'd1: g = ack_seen;
                2'd2: g = cancel_seen;
                default: g = rej_seen;
            endcase
            check(name, {31'd0, g}, {31'd0, exp});
        end
    endtask

    reg [31:0] v;

    always @(posedge clk) if (dut.req_wr)
        $display("  DBG WR addr=%03h dw_s=%08h block_cfg=%b", dut.tlp_addr[11:0], dut.tlp_dw_s, tx_block_cfg);

    initial begin
        #50 rst = 0;
        repeat (5) @(negedge clk);

        $display("=== 旧寄存器表（基线检查，T07 不得破坏）===");
        tlp_rd(12'h40, v); check("0x40 MAGIC    ", v, 32'h5043_4946);
        tlp_rd(12'h48, v); check("0x48 STATUS   ", v, 32'h0000_0001);
        tlp_rd(12'h4C, v); check("0x4C FRAME_CNT", v, 32'h0000_7004);
        tlp_rd(12'h50, v); check("0x50 WIDTH    ", v, 32'd640);
        tlp_rd(12'h54, v); check("0x54 HEIGHT   ", v, 32'd480);
        tlp_rd(12'h58, v); check("0x58 DATA_LEN ", v, 32'h0004_B000);
        tlp_rd(12'h64, v); check("0x64 VERSION  ", v, 32'h0002_0000);
        tlp_rd(12'h68, v); check("0x68 CLK_MHZ  ", v, 32'd62);
        cam_stat_r[255:224] = 32'h1234_5678;
        #10;
        tlp_rd(12'hD0, v); check("0xD0 CAM_DDR_DIAG", v, 32'h1234_5678);
        cam_stat_r[255:224] = 32'h0;

        tlp_wr(12'h44, 32'h0000_00C1);
        tlp_rd(12'h44, v); check("0x44 CTRL      ", v, 32'h0000_00C1);
        if (ctrl_enable !== 1'b1)   begin $display("ERROR: CTRL bit0 没生效"); errors=errors+1; end
        if (ctrl_push_en !== 1'b1)  begin $display("ERROR: CTRL bit6 没生效"); errors=errors+1; end
        if (ctrl_push_src !== 1'b1) begin $display("ERROR: CTRL bit7 没生效"); errors=errors+1; end
        if (cam_ab_sel !== 1'b0)    begin $display("ERROR: CTRL bit8 默认应为 0"); errors=errors+1; end
        if (ctrl_ddr_en !== 1'b0)   begin $display("ERROR: CTRL bit5 应为 0"); errors=errors+1; end
        tlp_wr(12'h44, 32'h0000_01ED);
        tlp_rd(12'h44, v); check("0x44 CTRL pat  ", v, 32'h0000_01ED);
        if (ctrl_pattern[1:0] !== 2'b11) begin $display("ERROR: CTRL bit3:2 没送到"); errors=errors+1; end
        if (ctrl_ddr_en !== 1'b1)   begin $display("ERROR: CTRL bit5 没生效"); errors=errors+1; end
        if (cam_ab_sel !== 1'b1)    begin $display("ERROR: CTRL bit8 没送到"); errors=errors+1; end
        tlp_wr(12'h44, 32'h0000_00ED);
        tlp_rd(12'h44, v); check("0x44 CTRL clr  ", v, 32'h0000_00ED);
        if (cam_ab_sel !== 1'b0)    begin $display("ERROR: CTRL bit8 清不掉"); errors=errors+1; end
        tlp_wr(12'h44, 32'h0000_0019);
        tlp_rd(12'h44, v); check("0x44 CTRL rsvd ", v, 32'h0000_0009);
        tlp_wr(12'h44, 32'h0000_0042);
        tlp_rd(12'h44, v); check("0x44 CTRL trig ", v, 32'h0000_0040);
        if (ctrl_trigger !== 1'b0) begin $display("ERROR: CTRL bit1 没自动清"); errors=errors+1; end

        tlp_wr(12'h5C, 32'h0000_1000);
        tlp_rd(12'h5C, v); check("0x5C PTR      ", v, 32'h0000_1000);
        tlp_wr(12'h6C, 32'h1234_5678);
        tlp_rd(12'h6C, v); check("0x6C SCRATCH  ", v, 32'h1234_5678);
        tlp_wr(12'h9C, 32'h0000_0026);
        tlp_rd(12'h9C, v); check("0x9C CAM_TAP  ", v, 32'h0000_0026);
        tlp_wr(12'hD4, 32'h0000_0041);
        tlp_rd(12'hD4, v); check("0xD4 CAM_B_TAP", v, 32'h0000_0041);
        tlp_rd(12'h9C, v); check("0xD4 写后 A 路不变", v, 32'h0000_0026);
        if (cam_tap_cfg !== 7'h26)   begin $display("ERROR: cam_tap_cfg 应为 7'h26"); errors=errors+1; end
        if (cam_tap_b_cfg !== 7'h41) begin $display("ERROR: cam_tap_b_cfg 应为 7'h41"); errors=errors+1; end

        $display("---+ DDR 握手字");
        tlp_rd(12'hA0, v); check("0xA0 DDR_FRAME_SEQ", v, D_SEQ);
        tlp_rd(12'hA4, v); check("0xA4 DDR_BASE     ", v, D_BASE);
        tlp_rd(12'hA8, v); check("0xA8 DDR_STATUS   ", v, D_STATUS);
        tlp_rd(12'hAC, v); check("0xAC DDR_LEN      ", v, D_LEN);
        $display("---+ 推帧寄存器");
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
        tlp_wr(12'h5C, 32'h0000_0000);
        repeat (8) @(negedge clk);
        tlp_rd(12'h60, v);
        tlp_rd(12'h5C, v);
        if (v !== 32'd4) begin
            $display("ERROR: 读一次 0x60 后 PTR=%0d 期望 4", v); errors = errors + 1;
        end else $display("  OK  0x60 读一次后 PTR=4（自动前进）");

        $display("=== T07 RKA1 安全扩展（0x100..0x11C）===");
        tlp_rd(12'h118, v); check("0x118 EXT_MAGIC  ", v, 32'h3141_4B52);
        tlp_rd(12'h11C, v); check("0x11C EXT_VERSION", v, 32'h0001_0000);
        // 默认：cap/session=0（不授权）
        tlp_rd(12'h100, v); check("0x100 cap default", v, 32'd0);
        tlp_rd(12'h104, v); check("0x104 sess default", v, 32'd0);
        // staging 读写
        tlp_wr(12'h100, 32'h0027_9000);
        tlp_rd(12'h100, v); check("0x100 cap rw     ", v, 32'h0027_9000);
        if (tx_cap_bytes !== 32'h0027_9000) begin $display("ERROR: tx_cap_bytes 没送出"); errors=errors+1; end
        tlp_wr(12'h104, 32'hA5A5_0001);
        tlp_rd(12'h104, v); check("0x104 sess rw    ", v, 32'hA5A5_0001);
        if (tx_session_id !== 32'hA5A5_0001) begin $display("ERROR: tx_session_id 没送出"); errors=errors+1; end
        tlp_wr(12'h10C, 32'h0000_0011);
        tlp_rd(12'h10C, v); check("0x10C ack seq    ", v, 32'h0000_0011);
        tlp_wr(12'h110, 32'hA5A5_0001);
        tlp_rd(12'h110, v); check("0x110 ack sess   ", v, 32'hA5A5_0001);

        // TX_CMD：单 bit 语义 + 读回 0
        tlp_rd(12'h108, v); check("0x108 TX_CMD rd  ", v, 32'd0);
        clear_pulses;
        tlp_wr(12'h108, 32'h0000_0001);            // ARM
        chk_pulse("arm pulse seen  ", 2'd0, 1'b1);
        tlp_rd(12'h108, v); check("0x108 TX_CMD rd2 ", v, 32'd0);
        clear_pulses;
        tlp_wr(12'h108, 32'h0000_0002);            // ACK
        chk_pulse("ack pulse seen  ", 2'd1, 1'b1);
        clear_pulses;
        tlp_wr(12'h108, 32'h0000_0004);            // CANCEL
        chk_pulse("cancel pulse    ", 2'd2, 1'b1);
        clear_pulses;
        tlp_wr(12'h108, 32'h0000_0003);            // ARM|ACK：非法组合
        chk_pulse("multi-bit rej   ", 2'd3, 1'b1);
        chk_pulse("multi-bit noarm ", 2'd0, 1'b0);
        clear_pulses;
        tlp_wr(12'h108, 32'h0000_0008);            // 未知 bit
        chk_pulse("unknown bit rej ", 2'd3, 1'b1);
        clear_pulses;
        tlp_wr(12'h108, 32'h0000_0000);            // 0 bit
        chk_pulse("zero bit rej    ", 2'd3, 1'b1);

        // TX_STATUS 直通
        tlp_rd(12'h114, v); check("0x114 TX_STATUS ", v, tx_status_in);

        // 活动期（busy/held）配置写被拒：值不变 + cfg_reject 脉冲
        tx_block_cfg = 1;
        clear_pulses;
        tlp_wr(12'h100, 32'hDEAD_1234);
        tlp_rd(12'h100, v); check("busy: cap kept  ", v, 32'h0027_9000);
        chk_pulse("busy cfg_reject ", 2'd3, 1'b1);
        clear_pulses;
        tlp_wr(12'h104, 32'hDEAD_5678);
        tlp_rd(12'h104, v); check("busy: sess kept ", v, 32'hA5A5_0001);
        chk_pulse("busy cfg_rej 2  ", 2'd3, 1'b1);
        tx_block_cfg = 0;
        tlp_wr(12'h100, 32'h0027_9000);
        tlp_rd(12'h100, v); check("idle: cap rew   ", v, 32'h0027_9000);

        // 诊断寄存器（T07 附加，只读）
        tlp_rd(12'h120, v); check("0x120 CSI_A_CNT ", v, csi_diag_a);
        tlp_rd(12'h124, v); check("0x124 CSI_A_GEOM", v, csi_diag_a2);
        tlp_rd(12'h128, v); check("0x128 CSI_B_CNT ", v, csi_diag_b);
        tlp_rd(12'h12C, v); check("0x12C CSI_B_GEOM", v, csi_diag_b2);

        // legacy 检测 fail-closed：未实现偏移仍读 DEAD_BEEF
        tlp_rd(12'h1F0, v); check("0x1F0 unimplemented", v, 32'hDEAD_BEEF);

        if (errors == 0) $display("ALL PASS");
        else             $display("FAIL: %0d mismatches", errors);
        $finish;
    end

endmodule
