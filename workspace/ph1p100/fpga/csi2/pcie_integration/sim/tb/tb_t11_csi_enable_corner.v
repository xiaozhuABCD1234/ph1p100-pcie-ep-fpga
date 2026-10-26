///////////////////////////////////////////////////////////////////////////////
//  tb_t11_csi_enable_corner.v — T11.rk-align-raw：T07 遗留用例（functional r2 §6.1）
//
//  被测：fpga/csi2/pcie_integration/rtl/checked/csi_rx_packet_integrity.v
//  目的：覆盖「I_enable 在**包尾后第 1 拍**（END_PACKET 首拍）撤销」的角落。
//
//  背景（T07 r2 报告 §6.1，未改 RTL、只补用例）：
//    · round2 把坏 CRC 的计数从「包尾同拍」挪到「END_PACKET 首拍」；
//    · 若 I_enable 恰在该拍落下，`if(!I_enable)` 分支先执行（清 crc_bad_q）⇒
//      **crc_errors 少计 1**（诊断计数级）；控制路径仍走 disable 分支：
//      frame_bad/abort/坏帧计数照常，不会把坏包当好包发布。
//
//  本 TB 把该角落**钉成回归**（不是放宽判据）：
//    P1 好帧（enable 全程 1）                      → good=1、crc=0（基线）
//    P2 坏 CRC 包 + 包尾第 1 拍撤 enable（角落）   → abort=1、bad=1、crc=**0**（少计 1）
//    P3 坏 CRC 包 + enable 全程 1（对照）          → crc=1、bad=2（正常路径计数正确）
//    P4 好帧（enable 全程 1）                      → good=2、crc/bad 不变（恢复正常）
//  判定：三条诊断量 + abort 计数与上表逐项一致；数据流（payload keep）不出现假发布。
///////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps
module tb_t11_csi_enable_corner;

    localparam VC = 2'd0;
    localparam DT_IMG = 6'h2b;
    localparam P_IDLE = 32'd4;
    localparam F_TMO  = 32'd2000;

    reg clk = 0; always #4 clk = ~clk;   // 与真实字节时钟域无差别（纯逻辑比对）
    reg rst_n = 0;
    reg en = 1;
    reg [31:0] data = 0;
    reg valid = 0;

    wire        o_pkt_done, o_sync_wait, o_vsync, o_in_frame, o_in_line;
    wire [31:0] o_payload; wire [3:0] o_keep; wire o_payload_v;
    wire        o_frame_end, o_frame_good, o_frame_abort;
    wire [31:0] o_crc_err, o_hdr_err, o_pkt_to, o_frm_to, o_good, o_bad;
    wire [15:0] o_last_wc, o_last_lines;

    csi_rx_packet_integrity #(
        .VC_ID(VC), .IMAGE_DT(DT_IMG), .IMAGE_WC(16'd80), .EXPECTED_LINES(16'd4),
        .CHECK_FRAME_ID(1'b0), .PACKET_IDLE_CYCLES(P_IDLE), .FRAME_TIMEOUT_CYCLES(F_TMO)
    ) u_dut (
        .I_clock(clk), .I_reset_n(rst_n), .I_enable(en), .I_data(data), .I_data_valid(valid),
        .O_packet_done(o_pkt_done), .O_sync_wait(o_sync_wait),
        .O_payload_out(o_payload), .O_payload_valid(o_payload_v), .O_payload_keep(o_keep),
        .O_vsync_out(o_vsync), .O_in_frame(o_in_frame), .O_in_line(o_in_line),
        .O_frame_end(o_frame_end), .O_frame_good(o_frame_good), .O_frame_abort(o_frame_abort),
        .O_crc_errors(o_crc_err), .O_header_errors(o_hdr_err), .O_packet_timeouts(o_pkt_to),
        .O_frame_timeouts(o_frm_to), .O_good_frames(o_good), .O_bad_frames(o_bad),
        .O_last_wc(o_last_wc), .O_last_lines(o_last_lines)
    );

    integer errors = 0;
    task chk(input cond, input [8*96-1:0] msg);
        begin
            if (!cond) begin
                errors = errors + 1;
                if (errors <= 20) $display("  ERROR #%0d @%0t : %s", errors, $time, msg);
            end
        end
    endtask

    function [7:0] hdr_ecc;
        input [23:0] d;
        integer i; reg [7:0] e; reg [7:0] m;
        begin
            e = 8'h00;
            for (i = 0; i < 24; i = i + 1) begin
                case (i)
                    0: m=8'h07; 1: m=8'h0B; 2: m=8'h0D; 3: m=8'h0E; 4: m=8'h13;
                    5: m=8'h15; 6: m=8'h16; 7: m=8'h19; 8: m=8'h1A; 9: m=8'h1C;
                    10: m=8'h23; 11: m=8'h25; 12: m=8'h26; 13: m=8'h29; 14: m=8'h2A;
                    15: m=8'h2C; 16: m=8'h31; 17: m=8'h32; 18: m=8'h34; 19: m=8'h38;
                    20: m=8'h1F; 21: m=8'h2F; 22: m=8'h37; default: m=8'h3B;
                endcase
                if (d[i]) e = e ^ m;
            end
            hdr_ecc = e;
        end
    endfunction

    function [15:0] crc_byte_f;
        input [15:0] c; input [7:0] b;
        reg [15:0] v; integer k;
        begin
            v = c ^ {8'd0, b};
            for (k = 0; k < 8; k = k + 1) v = (v >> 1) ^ ({16{v[0]}} & 16'h8408);
            crc_byte_f = v;
        end
    endfunction

    task send_word(input [31:0] w, input integer gap_after);
        begin
            @(negedge clk); data = w; valid = 1'b1;
            @(negedge clk); valid = 1'b0; data = 32'h0;
            repeat (gap_after) @(negedge clk);
        end
    endtask

    task send_short(input [5:0] dt, input [15:0] fid, input integer gap_after);
        reg [23:0] d; reg [7:0] e;
        begin
            d = {fid, VC, dt}; e = hdr_ecc(d);
            send_word({e, d}, gap_after);
        end
    endtask

    // 长包：WC=80；bad_crc=1 时 CRC 字节故意错（→ 包尾 crc_bad_q=1）
    task send_long(input integer first, input bad_crc, input integer gap_after);
        integer i, wi, nwords;
        reg [7:0] byt [0:83];
        reg [15:0] crc;
        reg [23:0] hd; reg [7:0] he; reg [31:0] w;
        begin
            for (i = 0; i < 80; i = i + 1) byt[i] = (first + i) & 8'hFF;
            crc = 16'hFFFF;
            for (i = 0; i < 80; i = i + 1) crc = crc_byte_f(crc, byt[i]);
            if (bad_crc) crc = crc ^ 16'h0040;
            byt[80] = crc[7:0]; byt[81] = crc[15:8];
            hd = {16'd80, VC, DT_IMG}; he = hdr_ecc(hd);
            send_word({he, hd}, 0);
            nwords = (82 + 3) / 4;
            for (wi = 0; wi < nwords; wi = wi + 1) begin
                w = 32'd0;
                for (i = 0; i < 4; i = i + 1)
                    if ((wi*4+i) < 82) w[i*8 +: 8] = byt[wi*4+i];
                send_word(w, (wi == nwords-1) ? gap_after : 0);
            end
        end
    endtask

    // 坏 CRC 包的「最后一拍」后立刻撤 enable（= END_PACKET 首拍）
    task send_long_bad_recorner;
        integer i, wi, nwords;
        reg [7:0] byt [0:83];
        reg [15:0] crc;
        reg [23:0] hd; reg [7:0] he; reg [31:0] w;
        begin
            for (i = 0; i < 80; i = i + 1) byt[i] = (200 + i) & 8'hFF;
            crc = 16'hFFFF;
            for (i = 0; i < 80; i = i + 1) crc = crc_byte_f(crc, byt[i]);
            crc = crc ^ 16'h0040;                       // 坏 CRC
            byt[80] = crc[7:0]; byt[81] = crc[15:8];
            hd = {16'd80, VC, DT_IMG}; he = hdr_ecc(hd);
            send_word({he, hd}, 0);
            nwords = (82 + 3) / 4;
            for (wi = 0; wi < nwords; wi = wi + 1) begin
                w = 32'd0;
                for (i = 0; i < 4; i = i + 1)
                    if ((wi*4+i) < 82) w[i*8 +: 8] = byt[wi*4+i];
                if (wi == nwords-1) begin
                    // 最后一拍：吃完这拍后 state 已进 END_PACKET；在下个 negedge 落 enable
                    @(negedge clk); data = w; valid = 1'b1;
                    @(negedge clk); valid = 1'b0; data = 32'h0; en = 1'b0;  // ← 角落
                end else begin
                    send_word(w, 0);
                end
            end
        end
    endtask

    // abort / good / crc 事件计数（独立于 DUT 内部）
    integer abort_cnt = 0, good_cnt = 0, endreq_cnt = 0;
    reg prev_abort = 0, prev_good = 0;
    always @(posedge clk) begin
        if (rst_n) begin
            if (o_frame_abort && !prev_abort) abort_cnt = abort_cnt + 1;
            if (o_frame_good && !prev_good)   good_cnt  = good_cnt + 1;
            prev_abort <= o_frame_abort; prev_good <= o_frame_good;
        end
    end

    integer pi;
    initial begin
        rst_n = 0; en = 0; valid = 0; data = 0;
        repeat (6) @(negedge clk);
        rst_n = 1; repeat (4) @(negedge clk);
        en = 1; repeat (4) @(negedge clk);

        // ---- P1：好帧基线（4 行 WC=80）----
        $display("=== P1 好帧 → good=1 / crc=0 ===");
        send_short(6'h00, 16'h0001, 3);
        for (pi = 0; pi < 4; pi = pi + 1) send_long(pi*80, 1'b0, 3);
        send_short(6'h01, 16'h0001, 3);
        repeat (8) @(posedge clk);
        chk(o_good === 32'd1, "P1: good_frames != 1");
        chk(o_bad  === 32'd0, "P1: bad_frames != 0");
        chk(o_crc_err === 32'd0, "P1: crc_errors != 0");
        chk(good_cnt == 1, "P1: good pulse count != 1");

        // ---- P2：坏 CRC 包 + 包尾第 1 拍撤 enable（角落）----
        $display("=== P2 角落：包尾首拍撤 enable（应 abort、crc 少计 1）===");
        send_short(6'h00, 16'h0002, 3);
        send_long(1000, 1'b0, 3);                       // 一行好
        send_long_bad_recorner;                         // 坏 CRC 行 + 角落撤 enable
        repeat (8) @(posedge clk);
        chk(abort_cnt == 1, "P2: abort pulse count != 1");
        chk(o_bad === 32'd1, "P2: bad_frames != 1");
        chk(o_crc_err === 32'd0, "P2: corner should UNDER-count crc (documented gap)");
        chk(o_good === 32'd1, "P2: good_frames changed");
        chk(o_in_frame === 1'b0, "P2: frame not closed by disable");
        en = 1; repeat (8) @(posedge clk);

        // ---- P3：对照：坏 CRC 包 + enable 全程 1（正常路径计数）----
        $display("=== P3 对照：enable 不撤 → crc=1 / bad=2 ===");
        send_short(6'h00, 16'h0003, 3);
        send_long(2000, 1'b1, 3);                       // 坏 CRC 行
        repeat (8) @(posedge clk);
        chk(o_crc_err === 32'd1, "P3: crc_errors != 1 (normal path undercounts)");
        chk(o_bad === 32'd2, "P3: bad_frames != 2");
        chk(abort_cnt == 2, "P3: abort pulse count != 2");

        // ---- P4：恢复：好帧（enable 全程 1）----
        $display("=== P4 恢复：好帧 → good=2 / crc 不变 ===");
        en = 0; repeat (4) @(posedge clk); en = 1; repeat (4) @(posedge clk);
        send_short(6'h00, 16'h0004, 3);
        for (pi = 0; pi < 4; pi = pi + 1) send_long(3000 + pi*80, 1'b0, 3);
        send_short(6'h01, 16'h0004, 3);
        repeat (8) @(posedge clk);
        chk(o_good === 32'd2, "P4: good_frames != 2");
        chk(o_crc_err === 32'd1, "P4: crc_errors changed after recovery");
        chk(o_bad === 32'd2, "P4: bad_frames != 2");
        chk(o_last_wc === 16'd80, "P4: last_wc != 80");

        $display("  [summary] good=%0d bad=%0d crc=%0d abort_pulses=%0d good_pulses=%0d",
                 o_good, o_bad, o_crc_err, abort_cnt, good_cnt);
        if (errors == 0) $display("ALL PASS");
        else             $display("FAIL: %0d errors", errors);
        $finish;
    end

    initial begin
        #10_000_000;
        $display("FAIL: watchdog timeout");
        $finish;
    end

endmodule
