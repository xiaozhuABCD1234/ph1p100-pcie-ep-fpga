///////////////////////////////////////////////////////////////////////////////
//  tb_ep_bar_win_debug.v — T11.runB-debug-rtl 新 TB：dbg_bank 字库 + debug 默认使能
//
//  对齐冻结件（run 20261018-1631_runA_fpga_side_readchannel/debug-spec/）：
//   · probe-map.md §2：word0..word8 ↔ 0x040/0x118/0x11C/0x0A0/0x0A4/0x0AC/
//     0x120/0x124/0x044 逐位一致；只读、无副作用、字序固定；
//   · enable-state.md §2：仅 bit0 enable / bit5 ddr_en 复位默认开，且仅 debug
//     构建入口（生产/00_all 默认 0，行为不变）。
//
//  两实例对照：
//   · u_dbg ：DBG_CTRL_DEFAULT_EN=1（模拟 debug 顶层 ph1p_pcie_ep_top_dbg）；
//   · u_prod：不覆盖（默认 0，模拟生产 00_all）——负例：默认仍为 0。
//
//  覆盖：9 字逐位镜像（正常帧 + 3 组边界帧）+ 0x160==0x44 多次写 CTRL 后一致
//  （含 trigger 自清、bit4 保留位）+ 只读/无副作用（写 bank 无效、ptr/scratch/
//  last_wr/tap 不变、读不产生 req_wr、bank 读不推进 ptr）+ 负例（0x13C/0x164/
//  0x1F0=DEAD_BEEF；0x158 不得等于 csi_diag_b；u_prod 默认 0）。
//
//  打包/读回时序与基线 tb_ep_bar_win_rka1.v 逐条相同（sop 拍锁地址、下一拍组合出数）。
///////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps

module tb_ep_bar_win_debug;

    reg         clk = 0;
    reg         rst = 1;
    reg         dbg_por_rst = 1;        // T11 r3：调试快照复位（与链路无关，上电后释放）
    always #8 clk = ~clk;              // 62.5MHz（tl_clk_user）

    integer errors = 0;

    // 只读激励源（两实例同源；本 TB 仅改这些输入）
    reg  [127:0] ddr_ro_r    = 128'd0;
    reg  [31:0]  csi_a_r     = 32'h1122_3344;
    reg  [31:0]  csi_a2_r    = 32'h5566_7788;
    reg  [31:0]  csi_b_r     = 32'h99AA_BBCC;
    reg  [31:0]  csi_b2_r    = 32'hDDEE_FF00;
    reg  [255:0] cam_stat_r  = 256'd0;
    reg  [31:0]  tx_status_r = 32'd0;

    // ================= u_dbg：debug 构建等效（参数覆盖为 1） =================
    reg          rx_sop_d = 0;
    reg  [255:0] rx_data_d = 0;
    wire [255:0] mrdata_d;
    wire [6:0]   memrd_lo_d;
    wire         ctrl_en_d, ctrl_trg_d, ctrl_ddr_d, ctrl_pu_en_d, ctrl_pu_src_d, cam_ab_d;
    wire [1:0]   ctrl_pat_d;
    wire [6:0]   tap_d, tapb_d;
    wire [31:0]  pdstl_d, pdsth_d, pbl_d, pbh_d;
    wire         host_prio_d;
    wire [31:0]  fb_raddr_d;
    wire [31:0]  dcap_d, dses_d, aseq_d, ases_d;
    wire         arm_d, ack_d, can_d, rej_d;

    ep_bar_win #(
        .MAGIC(32'h5043_4946), .VERSION(32'h0002_0000),
        .PTR_BYTES(32'h0004_B000), .CLK_MHZ(9'd62),
        .DBG_CTRL_DEFAULT_EN(1'b1)
    ) u_dbg (
        .clk(clk), .rst(rst), .dbg_por_rst(dbg_por_rst),
        .rx_sop_ff(rx_sop_d), .rx_data_ff(rx_data_d),
        .mrdata_rd_data(mrdata_d), .memrd_addr_lo(memrd_lo_d),
        .ddr_ro_b(128'd0), .cam_diag_b(32'd0),
        .cam_tap_cfg(tap_d), .cam_tap_b_cfg(tapb_d), .cam_ab_sel(cam_ab_d),
        .cam_drop_a(96'd0),
        .ctrl_enable(ctrl_en_d), .ctrl_trigger(ctrl_trg_d), .ctrl_pattern(ctrl_pat_d),
        .ctrl_ddr_en(ctrl_ddr_d), .ddr_ro(ddr_ro_r),
        .push_ro(128'd0), .ctrl_push_en(ctrl_pu_en_d), .ctrl_push_src(ctrl_pu_src_d),
        .push_dst_lo(pdstl_d), .push_dst_hi(pdsth_d),
        .push_db_lo(pbl_d), .push_db_hi(pbh_d),
        .host_rd_prio(host_prio_d), .host_grant(1'b1),
        .st_ready(1'b1), .st_busy(1'b0), .st_frame_cnt(32'h0000_7004),
        .st_width(16'd640), .st_height(16'd480), .st_data_len(32'h0004_B000),
        .fb_raddr(fb_raddr_d), .fb_rdata(32'hA5A5_5A5A), .dbg_rd_idx(32'd0),
        .cam_stat(cam_stat_r),
        .tx_cap_bytes(dcap_d), .tx_session_id(dses_d),
        .tx_cmd_arm(arm_d), .tx_cmd_ack(ack_d), .tx_cmd_cancel(can_d),
        .tx_ack_seq(aseq_d), .tx_ack_session(ases_d),
        .tx_status_in(tx_status_r), .tx_block_cfg(1'b0), .cfg_reject(rej_d),
        .csi_diag_a(csi_a_r), .csi_diag_a2(csi_a2_r),
        .csi_diag_b(csi_b_r), .csi_diag_b2(csi_b2_r)
    );

    // ================= u_prod：生产默认等效（参数默认 0） =================
    reg          rx_sop_p = 0;
    reg  [255:0] rx_data_p = 0;
    wire [255:0] mrdata_p;
    wire [6:0]   memrd_lo_p;
    wire         ctrl_en_p, ctrl_trg_p, ctrl_ddr_p, ctrl_pu_en_p, ctrl_pu_src_p, cam_ab_p;
    wire [1:0]   ctrl_pat_p;
    wire [6:0]   tap_p, tapb_p;
    wire [31:0]  pdstl_p, pdsth_p, pbl_p, pbh_p;
    wire         host_prio_p;
    wire [31:0]  fb_raddr_p;
    wire [31:0]  dcap_p, dses_p, aseq_p, ases_p;
    wire         arm_p, ack_p, can_p, rej_p;

    ep_bar_win #(
        .MAGIC(32'h5043_4946), .VERSION(32'h0002_0000),
        .PTR_BYTES(32'h0004_B000), .CLK_MHZ(9'd62)
    ) u_prod (
        .clk(clk), .rst(rst), .dbg_por_rst(1'b0),
        .rx_sop_ff(rx_sop_p), .rx_data_ff(rx_data_p),
        .mrdata_rd_data(mrdata_p), .memrd_addr_lo(memrd_lo_p),
        .ddr_ro_b(128'd0), .cam_diag_b(32'd0),
        .cam_tap_cfg(tap_p), .cam_tap_b_cfg(tapb_p), .cam_ab_sel(cam_ab_p),
        .cam_drop_a(96'd0),
        .ctrl_enable(ctrl_en_p), .ctrl_trigger(ctrl_trg_p), .ctrl_pattern(ctrl_pat_p),
        .ctrl_ddr_en(ctrl_ddr_p), .ddr_ro(ddr_ro_r),
        .push_ro(128'd0), .ctrl_push_en(ctrl_pu_en_p), .ctrl_push_src(ctrl_pu_src_p),
        .push_dst_lo(pdstl_p), .push_dst_hi(pdsth_p),
        .push_db_lo(pbl_p), .push_db_hi(pbh_p),
        .host_rd_prio(host_prio_p), .host_grant(1'b1),
        .st_ready(1'b1), .st_busy(1'b0), .st_frame_cnt(32'h0000_7004),
        .st_width(16'd640), .st_height(16'd480), .st_data_len(32'h0004_B000),
        .fb_raddr(fb_raddr_p), .fb_rdata(32'hA5A5_5A5A), .dbg_rd_idx(32'd0),
        .cam_stat(cam_stat_r),
        .tx_cap_bytes(dcap_p), .tx_session_id(dses_p),
        .tx_cmd_arm(arm_p), .tx_cmd_ack(ack_p), .tx_cmd_cancel(can_p),
        .tx_ack_seq(aseq_p), .tx_ack_session(ases_p),
        .tx_status_in(tx_status_r), .tx_block_cfg(1'b0), .cfg_reject(rej_p),
        .csi_diag_a(csi_a_r), .csi_diag_a2(csi_a2_r),
        .csi_diag_b(csi_b_r), .csi_diag_b2(csi_b2_r)
    );

    function [31:0] bswap32;
        input [31:0] x;
        begin
            bswap32 = {x[7:0], x[15:8], x[23:16], x[31:24]};
        end
    endfunction

    task chk(input [127:0] nm, input [31:0] got, input [31:0] exp);
        begin
            if (got !== exp) begin
                $display("ERROR: %0s read %08h expected %08h", nm, got, exp);
                errors = errors + 1;
            end else begin
                $display("  OK  %0s = %08h", nm, got);
            end
        end
    endtask

    task chk_ne(input [127:0] nm, input [31:0] got, input [31:0] badv);
        begin
            if (got === badv) begin
                $display("ERROR: %0s == forbidden %08h", nm, got);
                errors = errors + 1;
            end else begin
                $display("  OK  %0s != %08h (got %08h)", nm, badv, got);
            end
        end
    endtask

    task rd_dbg(input [11:0] off, output [31:0] val);
        begin
            @(negedge clk);
            rx_data_d = 256'd0;
            rx_data_d[191:160] = {20'd0, off};
            rx_sop_d = 1'b1;
            @(negedge clk);
            rx_sop_d = 1'b0;
            val = bswap32(mrdata_d[255:224]);
        end
    endtask

    task wr_dbg(input [11:0] off, input [31:0] val);
        begin
            @(negedge clk);
            rx_data_d = 256'd0;
            rx_data_d[255:248] = 8'b0100_0000;
            rx_data_d[191:160] = {20'd0, off};
            rx_data_d[159:128] = bswap32(val);
            rx_sop_d = 1'b1;
            @(negedge clk);
            rx_sop_d = 1'b0;
            rx_data_d = 256'd0;
        end
    endtask

    task rd_prod(input [11:0] off, output [31:0] val);
        begin
            @(negedge clk);
            rx_data_p = 256'd0;
            rx_data_p[191:160] = {20'd0, off};
            rx_sop_p = 1'b1;
            @(negedge clk);
            rx_sop_p = 1'b0;
            val = bswap32(mrdata_p[255:224]);
        end
    endtask

    task wr_prod(input [11:0] off, input [31:0] val);
        begin
            @(negedge clk);
            rx_data_p = 256'd0;
            rx_data_p[255:248] = 8'b0100_0000;
            rx_data_p[191:160] = {20'd0, off};
            rx_data_p[159:128] = bswap32(val);
            rx_sop_p = 1'b1;
            @(negedge clk);
            rx_sop_p = 1'b0;
            rx_data_p = 256'd0;
        end
    endtask

    // 字库镜像成对检查：bank 值 == 期望（逐位）且 == 原偏移读回复现值
    task rd_pair(input [11:0] off_orig, input [11:0] off_bank, input [127:0] nm, input [31:0] exp);
        reg [31:0] a, b;
        begin
            rd_dbg(off_orig, a);
            rd_dbg(off_bank, b);
            chk(nm, b, exp);       // 字库字 == 期望值（逐位）
            chk(nm, b, a);         // 且逐位 == 原偏移读回
        end
    endtask

    // 无副作用检查：bank 只读阶段不得引入任何 req_wr（写脉冲）
    integer wr_cnt_d = 0;
    always @(posedge clk) if (u_dbg.req_wr) wr_cnt_d = wr_cnt_d + 1;

    reg [31:0] v1, v2, v3, v4, v5;
    reg [31:0] ptr0, s0, lw0, c0, tap0;
    integer    wmark;

    localparam [31:0] MAGIC_V = 32'h5043_4946;
    localparam [31:0] RKA1_V  = 32'h3141_4B52;
    localparam [31:0] VER_V   = 32'h0001_0000;

    initial begin
        // ---------- 0) 无链路复位场景（issue-02）：rst 恒 1 时 CWC 探针仍可读 ----------
        $display("=== 0) 无 PCIe 链路（rst 恒 1）：常量/CTRL 快照非零、计数可动 ===");
        #50 dbg_por_rst = 0;                 // 上电复位释放（与链路无关）
        repeat (4) @(negedge clk);
        chk("no-link word0 MAGIC ", u_dbg.g_dbg_mark.dbg_mark_word0, MAGIC_V);
        chk("no-link word1 RKA1  ", u_dbg.g_dbg_mark.dbg_mark_word1, RKA1_V);
        chk("no-link word2 VER   ", u_dbg.g_dbg_mark.dbg_mark_word2, VER_V);
        chk("no-link word8 CTRL  ", u_dbg.g_dbg_mark.dbg_mark_word8, 32'h0000_0021);
        ddr_ro_r = {32'h0027_9000, 32'h0001_0018, 32'h0010_0000, 32'h0000_0007};
        csi_a_r  = 32'hA1B2_C3D4;  csi_a2_r = 32'h0000_0438;
        repeat (2) @(negedge clk);
        chk("no-link word3 SEQ   ", u_dbg.g_dbg_mark.dbg_mark_word3, 32'h0000_0007);
        chk("no-link word4 BASE  ", u_dbg.g_dbg_mark.dbg_mark_word4, 32'h0010_0000);
        chk("no-link word5 LEN   ", u_dbg.g_dbg_mark.dbg_mark_word5, 32'h0027_9000);
        chk("no-link word6 CSI   ", u_dbg.g_dbg_mark.dbg_mark_word6, 32'hA1B2_C3D4);
        chk("no-link word7 CSI2  ", u_dbg.g_dbg_mark.dbg_mark_word7, 32'h0000_0438);
        // 负例（DBG 关）：u_prod 无快照逻辑，ctrl 复位值仍为 0（生产行为不变）
        if (ctrl_en_p !== 1'b0) begin $display("ERROR: DBG-off u_prod ctrl_enable 应保持 0"); errors=errors+1; end
        // 释放 tl_rst_user，进入既有全量检查
        rst = 0;
        repeat (5) @(negedge clk);

        // ---------- 1) debug-only CTRL 默认：u_dbg bit0/bit5=1、其余 0；u_prod 全 0 ----------
        $display("=== 1) debug-only CTRL 默认 ===");
        if (ctrl_en_d !== 1'b1)  begin $display("ERROR: u_dbg ctrl_enable 复位应=1"); errors=errors+1; end
        if (ctrl_ddr_d !== 1'b1) begin $display("ERROR: u_dbg ctrl_ddr_en 复位应=1"); errors=errors+1; end
        if ((ctrl_trg_d !== 1'b0) || (ctrl_pu_en_d !== 1'b0) || (ctrl_pu_src_d !== 1'b0) || (cam_ab_d !== 1'b0))
            begin $display("ERROR: u_dbg TX/push/cam_ab 域应保持 0"); errors=errors+1; end
        rd_dbg(12'h44,  v1); chk("u_dbg 0x044         ", v1, 32'h0000_0021);
        rd_dbg(12'h160, v2); chk("u_dbg 0x160==0x044  ", v2, 32'h0000_0021);
        if ((ctrl_en_p !== 1'b0) || (ctrl_ddr_p !== 1'b0))
            begin $display("ERROR: u_prod 默认应保持 0（生产行为不变）"); errors=errors+1; end
        rd_prod(12'h44,  v1); chk("u_prod 0x044        ", v1, 32'h0000_0000);
        rd_prod(12'h160, v2); chk("u_prod 0x160        ", v2, 32'h0000_0000);
        rd_prod(12'h140, v3); chk("u_prod 0x140 MAGIC  ", v3, MAGIC_V);

        // ---------- 2) 正常帧：9 字逐位镜像 ----------
        $display("=== 2) 正常帧：0x140..0x160 == 原偏移逐位镜像 ===");
        ddr_ro_r = {32'h0027_9000, 32'h0001_0018, 32'h0010_0000, 32'h0000_1234};
        csi_a_r  = 32'h1122_3344;  csi_a2_r = 32'h5566_7788;
        repeat (2) @(negedge clk);
        rd_pair(12'h040, 12'h140, "0x140<-0x040 MAGIC  ", MAGIC_V);
        rd_pair(12'h118, 12'h144, "0x144<-0x118 EXT_MG ", RKA1_V);
        rd_pair(12'h11C, 12'h148, "0x148<-0x11C EXT_VR ", VER_V);
        rd_pair(12'h0A0, 12'h14C, "0x14C<-0x0A0 SEQ_A  ", 32'h0000_1234);
        rd_pair(12'h0A4, 12'h150, "0x150<-0x0A4 BASE_A ", 32'h0010_0000);
        rd_pair(12'h0AC, 12'h154, "0x154<-0x0AC LEN_A  ", 32'h0027_9000);
        rd_pair(12'h120, 12'h158, "0x158<-0x120 CSI_A  ", 32'h1122_3344);
        rd_pair(12'h124, 12'h15C, "0x15C<-0x124 CSI_A2 ", 32'h5566_7788);
        rd_dbg(12'h128, v1); chk("0x128 CSI_B 直读    ", v1, csi_b_r);
        rd_dbg(12'h158, v2); chk_ne("0x158 != csi_diag_b ", v2, csi_b_r);

        // ---------- 3) 边界帧 ----------
        $display("=== 3) 边界帧：全 F / 全 0 / 交叉模式 ===");
        ddr_ro_r = {32'hFFFF_FFFF, 32'hFFFF_FFFF, 32'hFFFF_FF80, 32'hFFFF_FFFF};
        csi_a_r  = 32'hFFFF_FFFF;  csi_a2_r = 32'h0000_0000;
        repeat (2) @(negedge clk);
        rd_pair(12'h0A0, 12'h14C, "b1 0x14C SEQ_F      ", 32'hFFFF_FFFF);
        rd_pair(12'h0A4, 12'h150, "b1 0x150 BASE_FF80  ", 32'hFFFF_FF80);
        rd_pair(12'h0AC, 12'h154, "b1 0x154 LEN_F      ", 32'hFFFF_FFFF);
        rd_pair(12'h120, 12'h158, "b1 0x158 CSI_F      ", 32'hFFFF_FFFF);
        rd_pair(12'h124, 12'h15C, "b1 0x15C CSI2_0     ", 32'h0000_0000);
        ddr_ro_r = 128'd0; csi_a_r = 32'd0; csi_a2_r = 32'd0;
        repeat (2) @(negedge clk);
        rd_pair(12'h0A0, 12'h14C, "b2 0x14C SEQ_0      ", 32'd0);
        rd_pair(12'h0A4, 12'h150, "b2 0x150 BASE_0     ", 32'd0);
        rd_pair(12'h0AC, 12'h154, "b2 0x154 LEN_0      ", 32'd0);
        rd_pair(12'h120, 12'h158, "b2 0x158 CSI_0      ", 32'd0);
        rd_pair(12'h124, 12'h15C, "b2 0x15C CSI2_0     ", 32'd0);
        ddr_ro_r = {32'hA5A5_A5A5, 32'h5A5A_5A5A, 32'hA5A5_5A5A, 32'h5A5A_A5A5};
        csi_a_r = 32'hAAAA_5555; csi_a2_r = 32'h5555_AAAA;
        repeat (2) @(negedge clk);
        rd_pair(12'h0A0, 12'h14C, "b3 0x14C SEQ_X      ", 32'h5A5A_A5A5);
        rd_pair(12'h0A4, 12'h150, "b3 0x150 BASE_X     ", 32'hA5A5_5A5A);
        rd_pair(12'h0AC, 12'h154, "b3 0x154 LEN_X      ", 32'hA5A5_A5A5);
        rd_pair(12'h120, 12'h158, "b3 0x158 CSI_X      ", 32'hAAAA_5555);
        rd_pair(12'h124, 12'h15C, "b3 0x15C CSI2_X     ", 32'h5555_AAAA);

        // ---------- 4) CTRL 读回字：多次写后 0x160 == 0x44 ----------
        $display("=== 4) CTRL(0x044) 写后 0x160 逐位一致 ===");
        wr_dbg(12'h44, 32'h0000_0000); rd_dbg(12'h44, v1); rd_dbg(12'h160, v2);
        chk("w0 0x044            ", v1, 32'h0000_0000); chk("w0 0x160==0x044     ", v2, 32'h0000_0000);
        wr_dbg(12'h44, 32'h0000_00ED); rd_dbg(12'h44, v1); rd_dbg(12'h160, v2);
        chk("w1 0x044 (pat3:2=3) ", v1, 32'h0000_00ED); chk("w1 0x160==0x044     ", v2, 32'h0000_00ED);
        wr_dbg(12'h44, 32'hFFFF_FFFF); rd_dbg(12'h44, v1); rd_dbg(12'h160, v2);
        chk("w2 0x044(bit4/9+=0) ", v1, 32'h0000_01ED); chk("w2 0x160==0x044     ", v2, 32'h0000_01ED);
        if (ctrl_trg_d !== 1'b0) begin $display("ERROR: trigger 未自清"); errors=errors+1; end
        wr_dbg(12'h44, 32'h0000_0002); rd_dbg(12'h44, v1); rd_dbg(12'h160, v2);
        chk("w3 0x044(trig 自清) ", v1, 32'h0000_0000); chk("w3 0x160==0x044     ", v2, 32'h0000_0000);
        wr_dbg(12'h44, 32'h0000_0021); rd_dbg(12'h44, v1); rd_dbg(12'h160, v2);
        chk("w4 0x044(恢复默认)  ", v1, 32'h0000_0021); chk("w4 0x160==0x044     ", v2, 32'h0000_0021);

        // ---------- 5) 只读 / 无副作用 ----------
        $display("=== 5) 只读/无副作用：写 bank 无效、状态不变、读不产生写、ptr 不前进 ===");
        wr_dbg(12'h5C, 32'h0000_1000);
        wr_dbg(12'h6C, 32'h1234_5678);
        wr_dbg(12'h74, 32'hCAFE_F00D);
        rd_dbg(12'h5C, ptr0); rd_dbg(12'h6C, s0); rd_dbg(12'h74, lw0);
        rd_dbg(12'h44, c0);  rd_dbg(12'h9C, tap0);
        wmark = wr_cnt_d;
        wr_dbg(12'h140, 32'hDEAD_1234);   // 负例：对 bank 写必须无效
        wr_dbg(12'h144, 32'hDEAD_5678);
        wr_dbg(12'h160, 32'hFFFF_FFFF);
        rd_dbg(12'h140, v1); chk("bank 写后 0x140     ", v1, MAGIC_V);
        rd_dbg(12'h144, v2); chk("bank 写后 0x144     ", v2, RKA1_V);
        rd_dbg(12'h160, v3); chk("bank 写后 0x160     ", v3, c0);
        rd_dbg(12'h5C, v1); chk("bank 写/读后 ptr    ", v1, ptr0);
        rd_dbg(12'h6C, v2); chk("bank 写/读后 scratch", v2, s0);
        rd_dbg(12'h74, v3); chk("bank 写/读后 last_wr", v3, lw0);
        rd_dbg(12'h44, v4); chk("bank 写/读后 0x044  ", v4, c0);
        rd_dbg(12'h9C, v5); chk("bank 写/读后 tap    ", v5, tap0);
        if (wr_cnt_d != wmark + 3) begin
            $display("ERROR: bank 读写阶段 req_wr 计数 %0d != %0d+3（读不得产生写）", wr_cnt_d, wmark);
            errors = errors + 1;
        end else $display("  OK  req_wr 计数 = %0d+3（仅 3 次显式写，读 0 写）", wmark);

        // ---------- 6) 负例：未占用相邻偏移 / legacy ----------
        $display("=== 6) 负例：0x13C/0x164/0x1F0 仍 DEAD_BEEF ===");
        rd_dbg(12'h13C, v1); chk("0x13C (bank 前一字) ", v1, 32'hDEAD_BEEF);
        rd_dbg(12'h164, v2); chk("0x164 (bank 后一字) ", v2, 32'hDEAD_BEEF);
        rd_dbg(12'h1F0, v3); chk("0x1F0 (legacy)      ", v3, 32'hDEAD_BEEF);
        rd_prod(12'h13C, v4); chk("u_prod 0x13C        ", v4, 32'hDEAD_BEEF);

        // ---------- 7) u_prod：写 CTRL 后语义不变 ----------
        $display("=== 7) u_prod 写 CTRL 后 0x044/0x160 正常回读 ===");
        wr_prod(12'h44, 32'h0000_0021);
        rd_prod(12'h44, v1);  chk("u_prod w 0x044      ", v1, 32'h0000_0021);
        rd_prod(12'h160, v2); chk("u_prod w 0x160      ", v2, 32'h0000_0021);

        if (errors == 0) $display("*** ALL PASS ***");
        else             $display("FAIL: %0d mismatches", errors);
        $finish;
    end

endmodule
