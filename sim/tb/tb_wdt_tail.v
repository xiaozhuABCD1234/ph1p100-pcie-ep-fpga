`timescale 1ns/1ps
///////////////////////////////////////////////////////////////////////////////
//  tb_wdt_tail.v — 复现「B 路写者永久停在 S_TAIL + A_IDLE（dbg_fsm=0x18）」
//
//  板上事件链（一次 CTRL 写 0x165 → XCLR 拉低 134ms，两路相机同时停流）：
//    1) 相机帧中途停流，in_frame 掉下来 ⇒ 一个 EOF 标记进 FIFO；
//    2) 写者在 S_PAY 弹出该 EOF ⇒ 进 S_TAIL（ep_frozen=1，pay_ep « PAY_BYTES）；
//    3) S_TAIL 靠 tail_app 补尾零，tail_app = S_TAIL & hdr_room & data_ready & tail_need，
//       而 data_ready = ~beat_busy；
//    4) 此时 DDR 写口被另一路占住（awready 长期为 0）：本笔突发把最后一个 beat 收完之后
//       写者回 A_IDLE（mid_frame=1）发下一笔，拿不到端口；
//    5) 65535 拍后 aw_tmo_evt 生效：awvalid 撤销、a_st 回 A_IDLE，**同时把 mid_frame 清 0**；
//    6) A_IDLE 里只有 mid_frame=1 才会再发突发 ⇒ mid_frame=0 之后突发引擎永久停摆；
//    7) 于是 S_TAIL 里那个已经攒好的 beat 永远卡在 beat_vld=1
//         ⇒ data_ready 恒 0 ⇒ tail_app 恒 0 ⇒ apos 不再前进
//         ⇒ apos >= DMA_BYTES 永不成立 ⇒ 永久停在 S_TAIL（dbg_fsm=0x18）。
//    注：S_TAIL 下 burst_ok_ddr 恒 1（tail_phase_ddr），所以在 S_TAIL 等 tail_app
//        这条路径上旧看门狗（A_IDLE+mid_frame+!burst_ok_ddr）永远不计数。
//
//  本 TB 在 aw 超时之后**释放**写口再送 3 整帧，用来证明这是不可自愈的永久停。
//
//  几何：W=256,H=64 只为跑得快；BURST_BEATS=64 / BURST_GROUPS=410 与顶层一致。
//
//  ---------------------------------------------------------------------------
//  实测结果（iverilog 12，fpga/sim/tb/tb_wdt_tail.v）
//  ---------------------------------------------------------------------------
//  A) RTL = commit 52dcfc09（板上那版）：
//     [P1] aw 超时之后：dbg_fsm=058（= 0x18 | hdr_ready），a_st=0 s_state=3(S_TAIL)
//          mid_frame=0 rw_done_r=0 axi_err=1
//          tail_app=0 ← S_TAIL=1 & hdr_room=1 & data_ready=0 & tail_need=1
//          beat_vld=1 beat_busy=1 pop=0 word_take=0
//          apos=4132 (< DMA_BYTES=24576) cpos=4128 bcnt=4 beats_left=640
//          wdt=0  ← 旧看门狗（A_IDLE & mid_frame & !burst_ok_ddr）在此恒为 0
//     [P2] 写口完全释放 20000 拍：所有量一动不动（apos/beats/bursts 全冻结）
//     [P3/P4] 再送 3 整帧 + 空转 200000 拍：seq 仍为 0，s_state 仍 3，apos 仍 4132
//          ⇒ REPRO: STUCK（写口空闲、相机在出流，写者永不再动）
//     ※ 若 aw 超时发生在刚进 S_TAIL、尾零还没排出去的窗口里，cpos 还没跨过
//       128+pay_ep ⇒ 头 CRC 遍历不启动 ⇒ hdr_ready=0 ⇒ dbg_fsm 正好是 0x18
//       （板上读到的就是这个；本例超时略晚，读回 0x58，a_st/s_state 位完全一致）。
//
//  B) 最小修复（aw_tmo_evt 里加 self_flush_cnt <= 8'hFF）：
//     [P1] 一个 wdt 窗口后 s_state 回 S_SYNC，后续 3 帧正常发布（seq 0→2），
//          不再有永久停。代价：丢掉 aw 超时那一帧（本来就是坏帧）。
//  C) 现有工作副本（数据侧长看门狗通用化，WDT_LIMIT 调成 30000 便于观察）：
//     同样能自愈（seq 0→1，dbg_fsm 回 000），但代价是整整一个 WDT_LIMIT
//     （板上 0xC0_0000 @100MHz = 125.8ms ≈ 4 帧）+ 一次 FIFO 两端复位。
//     ⇒ 它兜住的是症状，不是根因。
//
//  复现命令（不改主 RTL，用临时副本）：
//     git -C fpga show HEAD:rtl/ep_side/ddr/cam_r10f_writer.v > /tmp/wdtail/base.v
//     iverilog -g2005 -I fpga/rtl/ep_side/ddr -o /tmp/tb_base \
//         fpga/sim/tb/tb_wdt_tail.v /tmp/wdtail/base.v && vvp /tmp/tb_base
///////////////////////////////////////////////////////////////////////////////
module tb_wdt_tail;

    localparam integer W = 256, H = 64;
    localparam integer PAY_BYTES = W*H*5/4;                          // 20480
    localparam integer DMA_BYTES = ((PAY_BYTES+128+4095)/4096)*4096;  // 24576
    localparam integer DMA_BEATS = DMA_BYTES/32;                      // 768
    localparam [31:0]  BASE0 = 32'h0010_0000, BASE1 = 32'h0090_0000;
    localparam [31:0]  SES   = 32'h2026_1028;
    localparam integer AW_TMO = 65535;      // m_aw_cur 饱和值（clk_ddr 拍）

    reg clk_cam = 0, clk_fb = 0, clk_ddr = 0;
    always #8  clk_cam = ~clk_cam;          // 16ns
    always #16 clk_fb  = ~clk_fb;
    always #5  clk_ddr = ~clk_ddr;          // 100MHz

    reg rst_cam_n = 0, rst_fb = 1, rst_ddr = 1;

    reg vs=0, in_frame=0, in_line=0, pv=0, good=0, abort=0;
    reg [39:0] pix = 40'd0;

    wire [31:0] seq, base, status, len;
    wire [15:0] lines, grp;  wire anom;  wire [95:0] drop, stall;
    wire [8:0]  fsm;

    wire [28:0] awaddr;  wire [7:0] awlen;  wire [2:0] awsize;  wire [1:0] awburst;
    wire awvalid, awready, wvalid, wready, wlast, bvalid, bready, busy;
    wire [255:0] wdata;  wire [31:0] wstrb;  wire [1:0] bresp;

    // ---------------- AXI4 从机模型（写通道 + 写响应）----------------
    reg        ax_gate = 1'b0;   // 1 = 写口被对端占住：只掐 awready（拿不到新突发）
    reg  [7:0] ax_bc   = 8'd0;
    reg        ax_bv   = 1'b0;
    integer    n_burst = 0, n_beat = 0, n_tmo = 0;

    assign awready = ~ax_gate;
    assign wready  = 1'b1;
    assign bvalid  = ax_bv;
    assign bresp   = 2'b00;

    always @(posedge clk_ddr) begin
        if (awvalid && awready) begin
            ax_bc   <= awlen + 8'd1;
            n_burst <= n_burst + 1;
        end
        if (wvalid && wready) begin
            n_beat <= n_beat + 1;
            if (ax_bc == 8'd1) begin ax_bv <= 1'b1; ax_bc <= 8'd0; end
            else if (ax_bc != 8'd0) ax_bc <= ax_bc - 8'd1;
        end
        if (bvalid && bready) ax_bv <= 1'b0;
        // aw 超时事件（m_aw_cur 饱和那一拍）
        if (dut.aw_tmo_evt) begin
            n_tmo <= n_tmo + 1;
            $display("[%0t] *** aw_tmo_evt fired: a_st=%0d mid_frame=%b m_aw_cur=%0d apos=%0d beat_vld=%b",
                     $time, dut.a_st, dut.mid_frame, dut.m_aw_cur, dut.apos, dut.beat_vld);
        end
    end

    cam_r10f_writer #(
        .W(W), .H(H), .X0(16'd0), .Y0(16'd0), .SKIP_ROWS(16'd0),
        .BASE0(BASE0), .BASE1(BASE1), .FIFO_AW(10), .BURST_BEATS(64),
        .CAMERA_ID(8'd1), .SRC_BAYER_PHASE(2'd0), .MODE_ID(32'd1),
        .WDT_LIMIT(24'd30000)
    ) dut (
        .cam_clk(clk_cam), .cam_rst_n(rst_cam_n),
        .cam_vsync(vs), .cam_in_frame(in_frame), .cam_in_line(in_line),
        .cam_pix(pix), .cam_pix_valid(pv),
        .cam_frame_good(good), .cam_frame_abort(abort),
        .prot_en(1'b0), .rel_tgl0(1'b0), .rel_tgl1(1'b0),
        .clk_fb(clk_fb), .rst_fb(rst_fb), .session_id(SES),
        .wr_frame_seq(seq), .wr_base(base), .wr_status(status), .wr_len(len),
        .dbg_lines_per_frame(lines), .dbg_max_grp_per_line(grp),
        .dbg_anomaly(anom), .dbg_drop(drop), .dbg_stall(stall), .dbg_frame(),
        .dbg_fsm(fsm),
        .clk_ddr(clk_ddr), .rst_ddr(rst_ddr), .ddr_cal_done(1'b1), .arm(1'b1),
        .axi_busy(busy),
        .cl_release(2'b00), .cl_pub_valid(), .cl_pub_seq(), .cl_pub_base(),
        .cl_pub_session(), .cl_pub_len(), .cl_good_count(), .cl_bad_count(),
        .m_axi_awaddr(awaddr), .m_axi_awlen(awlen), .m_axi_awsize(awsize),
        .m_axi_awburst(awburst), .m_axi_awvalid(awvalid), .m_axi_awready(awready),
        .m_axi_wdata(wdata), .m_axi_wstrb(wstrb), .m_axi_wlast(wlast),
        .m_axi_wvalid(wvalid), .m_axi_wready(wready),
        .m_axi_bresp(bresp), .m_axi_bvalid(bvalid), .m_axi_bready(bready)
    );

    // ---------------- 相机激励 ----------------
    reg [9:0] q0,q1,q2,q3;
    integer   r, g, k;

    task send_sof;
        begin
            @(negedge clk_cam); vs = 1'b1;
            @(negedge clk_cam); vs = 1'b0; in_frame = 1'b1;
        end
    endtask

    task send_row;
        begin
            @(negedge clk_cam); in_line = 1'b1;
            @(negedge clk_cam); in_line = 1'b0;
            for (g = 0; g < W/4; g = g + 1) begin
                q0 = (g*4+0)*3 + r*5; q1 = (g*4+1)*3 + r*5;
                q2 = (g*4+2)*3 + r*5; q3 = (g*4+3)*3 + r*5;
                @(negedge clk_cam); pix = {q3,q2,q1,q0}; pv = 1'b1;
                @(negedge clk_cam); pv = 1'b0;
            end
        end
    endtask

    task send_rows(input integer nrow);
        begin
            for (r = 0; r < nrow; r = r + 1) send_row;
        end
    endtask

    task send_full_frame;
        begin
            send_sof;
            send_rows(H);
            @(negedge clk_cam); good = 1'b1;
            @(negedge clk_cam); in_frame = 1'b0;
            @(negedge clk_cam); good = 1'b0;
        end
    endtask

    // ---------------- 证据打印 ----------------
    task dump;
        begin
            $display("   dbg_fsm=%h (a_st=%0d s_state=%0d) mid_frame=%b rw_done_r=%b axi_err=%b",
                     fsm, dut.a_st, dut.s_state, dut.mid_frame, dut.rw_done_r, dut.axi_err);
            $display("   tail_app=%b  <-- S_TAIL=%b & hdr_room=%b & data_ready=%b & tail_need=%b",
                     dut.tail_app, (dut.s_state == 3'd3), dut.hdr_room, dut.data_ready, dut.tail_need);
            $display("   beat_vld=%b beat_busy=%b beat_taken=%b  pop=%b word_take=%b  m_aw_cur=%0d",
                     dut.beat_vld, dut.beat_busy, dut.beat_taken, dut.pop, dut.word_take, dut.m_aw_cur);
            $display("   apos=%0d cpos=%0d (DMA_BYTES=%0d) bcnt=%0d beats_left=%0d beat_cnt=%0d/%0d gcnt=%0d",
                     dut.apos, dut.cpos, DMA_BYTES, dut.bcnt, dut.beats_left, dut.beat_cnt, DMA_BEATS, dut.gcnt);
            $display("   wdt=%0d self_flush_cnt=%0d | AXI bursts=%0d beats=%0d aw_tmo=%0d seq=%0d",
                     dut.wdt, dut.self_flush_cnt, n_burst, n_beat, n_tmo, seq);
        end
    endtask

    // ---------------- 主流程 ----------------
    integer apos_a, beats_a, seq_a, burst_a, rr, kk, bcnt_a, gcnt_a;
    reg [2:0] st_a;
    reg     gate_flag;
    initial begin
        repeat (20) @(negedge clk_cam);
        rst_cam_n = 1'b1; rst_fb = 1'b0; rst_ddr = 1'b0;
        repeat (50) @(negedge clk_cam);
        repeat (20) @(posedge clk_ddr);

        // ---- 帧 1：正常起流，只送 8 行（不足一帧），随后相机帧中途停流 ----
        // 注意：EOF 标记只有「突发还开着（data_ready=1）」时才弹得出来；停流后还要再喂一点
        // 像素把 FIFO 顶过 410 组门槛，写者才会继续发突发、走到 FIFO 头部的 EOF ⇒ 进 S_TAIL。
        // 板上同理：XCLR 期间 MIPI 包计数 0x120/0x128 还在涨，FIFO 不会立刻见底。
        send_sof;
        send_rows(8);
        @(negedge clk_cam); in_frame = 1'b0;     // EOF 标记（eof_evt）进 FIFO
        $display("=== phase 1: 帧中途 EOF（in_frame 掉）；继续喂像素直到写者进 S_TAIL ===");

        gate_flag = 1'b0;
        k = 0;
        for (rr = 0; (rr < 60) && !gate_flag; rr = rr + 1) begin
            send_row;
            for (kk = 0; kk < 10; kk = kk + 1) begin
                @(posedge clk_ddr);
                k = k + 1;
                if (dut.s_state == 3'd3) begin
                    gate_flag = 1'b1;
                    ax_gate   = 1'b1;   // 立刻占住写口（对端不退让）
                end
            end
        end
        $display("[%0t] S_TAIL seen after %0d clk_ddr (s_state=%0d apos=%0d beat_vld=%b ep_frozen=%b pay_ep=%0d gate=%b)",
                 $time, k, dut.s_state, dut.apos, dut.beat_vld, dut.ep_frozen, dut.pay_ep, ax_gate);

        // ---- 对端占住 DDR 写口（awready=0）----
        $display("=== phase 2: 写口被另一路占住（awready=0），等 %0d 拍 aw 超时 ===", AW_TMO);
        repeat (AW_TMO + 2000) @(posedge clk_ddr);
        $display("[%0t] P1: aw 超时之后（写口仍被占）", $time);
        dump;

        // ---- 释放写口 ----
        ax_gate = 1'b0;
        repeat (20000) @(posedge clk_ddr);
        $display("[%0t] P2: 写口已释放 20000 拍", $time);
        dump;

        // ---- 相机恢复，再送 3 整帧 ----
        $display("=== phase 3: 相机恢复，再送 3 整帧 ===");
        apos_a = dut.apos; beats_a = n_beat; seq_a = seq; burst_a = n_burst;
        send_full_frame;
        send_full_frame;
        send_full_frame;
        repeat (40000) @(posedge clk_ddr);
        $display("[%0t] P3: 3 整帧送完之后", $time);
        dump;
        $display("   delta: apos %0d -> %0d | beats %0d -> %0d | bursts %0d -> %0d | seq %0d -> %0d",
                 apos_a, dut.apos, beats_a, n_beat, burst_a, n_burst, seq_a, seq);
        bcnt_a = dut.beat_cnt; gcnt_a = dut.gcnt; st_a = dut.s_state;
        repeat (200000) @(posedge clk_ddr);
        $display("[%0t] P4: 再空转 200000 拍（稳定性检查）", $time);
        dump;
        $display("   stability: s_state %0d->%0d  beat_cnt %0d->%0d  gcnt %0d->%0d  seq %0d",
                 st_a, dut.s_state, bcnt_a, dut.beat_cnt, gcnt_a, dut.gcnt, seq);
        if ((dut.s_state == st_a) && (dut.beat_cnt == bcnt_a) && (dut.gcnt == gcnt_a) && (dut.a_st == 3'd0))
            $display("NOTE: 200000 拍内毫无前进（写口空闲、相机在出流）⇒ 又一个死状态");

        if ((dut.s_state == 3'd3) && (dut.a_st == 3'd0) && (dut.mid_frame == 1'b0))
            $display("REPRO: STUCK  dbg_fsm=%h (S_TAIL+A_IDLE) apos=%0d < DMA_BYTES=%0d ；写口已空闲、相机也在出流，仍永不再动",
                     fsm, dut.apos, DMA_BYTES);
        else
            $display("REPRO: NOT_STUCK dbg_fsm=%h a_st=%0d s_state=%0d seq=%0d",
                     fsm, dut.a_st, dut.s_state, seq);
        $finish;
    end
endmodule
