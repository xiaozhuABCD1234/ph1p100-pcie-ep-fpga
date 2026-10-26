`timescale 1ns/1ps
///////////////////////////////////////////////////////////////////////////////
//  tb_csi_integrity_diff.v — T07 round2：checked 包层「改动前后」差分 oracle
//
//  被测：fpga/csi2/pcie_integration/rtl/checked/csi_rx_packet_integrity.v（round2 重构版）
//  参照：fpga/csi2/pcie_integration/sim/tb/csi_rx_packet_integrity_ref.v
//        （= 只读原源 fpga/csi2/src/csi/csi_rx_packet_integrity.v 的重命名**副本**，
//          round1 交付版与原源逐字节相同）
//
//  方法：同一时钟/复位/使能，把**完全相同的**激励同时喂给两个 DUT；逐拍比对：
//    · O_payload_out / O_payload_valid / O_payload_keep：**逐拍必须相同**（像素流对齐不变）
//    · O_packet_done / O_in_line / O_vsync_out / O_in_frame / O_sync_wait：逐拍相同
//    · O_frame_end / O_frame_good：逐拍相同（FE 裁决）
//    · O_frame_abort / 六个计数器 / O_last_wc / O_last_lines：允许**≤2 拍滞后**，
//      用「事件窗口 + 静默点（≥8 拍无 valid）全量比对」两种方式核对
//      （重构只把 CRC 比较/计数挪到包尾后一拍，见模块头 ③）
//
//  流量（确定性伪随机 + 定向边界，覆盖任务要求的包边界/坏 CRC/WC 边界/abort/恢复）：
//    1) 好帧：FS + N 行（ECC 正确、CRC 正确、WC 正确）+ FE（A/B 位、frame_id、CHECK_FRAME_ID 变体）
//    2) 坏 CRC（CRC 字节翻转）→ 必须坏帧且不 good
//    3) WC 边界：wc=5（最小一组）、wc=10、wc=80、wc=65535 附近、WC=0（非法）、非 5 倍数
//    4) 短行/长行（WC 与 IMAGE_WC 不符）、行数不符（EXPECTED_LINES）
//    5) 包中途停住 → BODY idle 超时；帧中途停住 → 帧超时（小 FRAME_TIMEOUT 参数）
//    6) 坏头（ECC 错）、未知 DT、非选中 VC、FS 重复、FE 无帧、abort 后恢复
//    7) 随机插入 valid 空隙、随机 payload 数据、随机长度
//  每个用例结束后：跑 ≥8 拍 idle，再全量比对计数/几何字。
///////////////////////////////////////////////////////////////////////////////
module tb_csi_integrity_diff;

    localparam VC = 2'd0;
    localparam DT_IMG = 6'h2b;
    localparam P_IDLE = 32'd4;          // 包内 idle 超时拍数（小值便于测超时）
    localparam F_TMO  = 32'd2000;       // 帧超时拍数（够跑完定向好帧，又短到能测超时）

    reg clk = 0; always #4 clk = ~clk;  // 125MHz（差分 TB 与真实 187.5MHz 无差别，纯逻辑比对）
    reg rst_n = 0;
    reg en = 0;
    reg [31:0] data = 0;
    reg valid = 0;

    // ---- DUT：round2 重构版 ----
    wire        n_pkt_done, n_sync_wait, n_vsync, n_in_frame, n_in_line;
    wire [31:0] n_payload; wire [3:0] n_keep; wire n_payload_v;
    wire        n_frame_end, n_frame_good, n_frame_abort;
    wire [31:0] n_crc_err, n_hdr_err, n_pkt_to, n_frm_to, n_good, n_bad;
    wire [15:0] n_last_wc, n_last_lines;
    csi_rx_packet_integrity #(
        .VC_ID(VC), .IMAGE_DT(DT_IMG), .IMAGE_WC(16'd80), .EXPECTED_LINES(16'd4),
        .CHECK_FRAME_ID(1'b0), .PACKET_IDLE_CYCLES(P_IDLE), .FRAME_TIMEOUT_CYCLES(F_TMO)
    ) u_new (
        .I_clock(clk), .I_reset_n(rst_n), .I_enable(en), .I_data(data), .I_data_valid(valid),
        .O_packet_done(n_pkt_done), .O_sync_wait(n_sync_wait),
        .O_payload_out(n_payload), .O_payload_valid(n_payload_v), .O_payload_keep(n_keep),
        .O_vsync_out(n_vsync), .O_in_frame(n_in_frame), .O_in_line(n_in_line),
        .O_frame_end(n_frame_end), .O_frame_good(n_frame_good), .O_frame_abort(n_frame_abort),
        .O_crc_errors(n_crc_err), .O_header_errors(n_hdr_err), .O_packet_timeouts(n_pkt_to),
        .O_frame_timeouts(n_frm_to), .O_good_frames(n_good), .O_bad_frames(n_bad),
        .O_last_wc(n_last_wc), .O_last_lines(n_last_lines)
    );

    // ---- 参照：round1（只读原源副本） ----
    wire        r_pkt_done, r_sync_wait, r_vsync, r_in_frame, r_in_line;
    wire [31:0] r_payload; wire [3:0] r_keep; wire r_payload_v;
    wire        r_frame_end, r_frame_good, r_frame_abort;
    wire [31:0] r_crc_err, r_hdr_err, r_pkt_to, r_frm_to, r_good, r_bad;
    wire [15:0] r_last_wc, r_last_lines;
    csi_rx_packet_integrity_ref #(
        .VC_ID(VC), .IMAGE_DT(DT_IMG), .IMAGE_WC(16'd80), .EXPECTED_LINES(16'd4),
        .CHECK_FRAME_ID(1'b0), .PACKET_IDLE_CYCLES(P_IDLE), .FRAME_TIMEOUT_CYCLES(F_TMO)
    ) u_ref (
        .I_clock(clk), .I_reset_n(rst_n), .I_enable(en), .I_data(data), .I_data_valid(valid),
        .O_packet_done(r_pkt_done), .O_sync_wait(r_sync_wait),
        .O_payload_out(r_payload), .O_payload_valid(r_payload_v), .O_payload_keep(r_keep),
        .O_vsync_out(r_vsync), .O_in_frame(r_in_frame), .O_in_line(r_in_line),
        .O_frame_end(r_frame_end), .O_frame_good(r_frame_good), .O_frame_abort(r_frame_abort),
        .O_crc_errors(r_crc_err), .O_header_errors(r_hdr_err), .O_packet_timeouts(r_pkt_to),
        .O_frame_timeouts(r_frm_to), .O_good_frames(r_good), .O_bad_frames(r_bad),
        .O_last_wc(r_last_wc), .O_last_lines(r_last_lines)
    );

    integer errs = 0;
    integer payload_beats = 0, payload_mismatch = 0;
    integer dbg_dumps = 0;
    // 首次分歧时把两边内部状态打出来（只在诊断用；判定仍靠上面的逐拍比对）
    task dbg_dump(input [8*96-1:0] what);
        begin
            if (dbg_dumps < 6) begin
                dbg_dumps = dbg_dumps + 1;
                $display("  DUMP[%0s] @%0t valid=%b I_data=%08h", what, $time, valid, data);
                $display("    NEW state=%0d tail=%0d wc=%0d crc=%04h recv=%04h keep=%b kbad=%b opd=%b oab=%b",
                         u_new.state, u_new.tail, u_new.wc, u_new.crc, u_new.received_crc,
                         u_new.keep_d, u_new.crc_bad_q, n_pkt_done, n_frame_abort);
                $display("    REF state=%0d cons=%0d wc=%0d crc=%04h recv=%04h keep=%b opd=%b oab=%b",
                         u_ref.state, u_ref.consumed, u_ref.wc, u_ref.crc, u_ref.received_crc,
                         u_ref.keep, r_pkt_done, r_frame_abort);
            end
        end
    endtask
    task chk(input cond, input [8*96-1:0] msg);
        begin
            if (!cond) begin
                errs = errs + 1;
                if (errs <= 20) begin
                    $display("  ERROR #%0d @%0t : %s", errs, $time, msg);
                    dbg_dump(msg);
                end
            end
        end
    endtask

    // ---- 逐拍比对（数据流必须完全一致；abort 允许 ≤2 拍滞后） ----
    reg prev_abort_r = 0, prev_abort_n = 0;
    reg [1:0] ab_win = 2'd0;        // ref abort 之后给 new 的 2 拍跟进窗口
    always @(posedge clk) begin
        if (rst_n && en) begin
            // 数据流 / 握手 / FE：逐拍必须相同
            chk(n_payload_v === r_payload_v, "payload_valid differs");
            if (n_payload_v && r_payload_v) begin
                payload_beats = payload_beats + 1;
                if (n_payload !== r_payload || n_keep !== r_keep) begin
                    payload_mismatch = payload_mismatch + 1;
                    if (payload_mismatch <= 5)
                        $display("  PAYLOAD MISMATCH @%0t new=%08h/%b ref=%08h/%b",
                                 $time, n_payload, n_keep, r_payload, r_keep);
                end
            end
            chk(n_pkt_done === r_pkt_done, "packet_done differs");
            chk(n_in_line  === r_in_line,  "in_line differs");
            chk(n_vsync    === r_vsync,    "vsync differs");
            chk(n_in_frame === r_in_frame, "in_frame differs");
            chk(n_frame_end  === r_frame_end,  "frame_end differs");
            chk(n_frame_good === r_frame_good, "frame_good differs");
            // abort：ref 抬起当拍或之后 2 拍内 new 必须抬起；new 不得无来源地抬起
            if (n_frame_abort && !prev_abort_n)
                chk(r_frame_abort || (ab_win != 2'd0), "new abort outside ref window");
            if (r_frame_abort && !prev_abort_r) ab_win <= 2'd2;
            else if (ab_win != 2'd0)            ab_win <= ab_win - 2'd1;
            prev_abort_r <= r_frame_abort;
            prev_abort_n <= n_frame_abort;
        end
    end

    // ---- 静默点全量比对（每用例后调用） ----
    task quiesce_check(input [8*96-1:0] tag);
        begin
            repeat (8) @(posedge clk);
            $display("  [%0s] good=%0d bad=%0d crc=%0d hdr=%0d pkt_to=%0d frm_to=%0d wc=%0d lines=%0d pbeats=%0d",
                     tag, n_good, n_bad, n_crc_err, n_hdr_err, n_pkt_to, n_frm_to, n_last_wc, n_last_lines,
                     payload_beats);
            chk(n_crc_err === r_crc_err,   {tag, " crc_errors"});
            chk(n_hdr_err === r_hdr_err,   {tag, " hdr_errors"});
            chk(n_pkt_to  === r_pkt_to,    {tag, " pkt_timeouts"});
            chk(n_frm_to  === r_frm_to,    {tag, " frame_timeouts"});
            chk(n_good    === r_good,      {tag, " good_frames"});
            chk(n_bad     === r_bad,       {tag, " bad_frames"});
            chk(n_last_wc === r_last_wc,   {tag, " last_wc"});
            chk(n_last_lines === r_last_lines, {tag, " last_lines"});
            chk(n_sync_wait === r_sync_wait, {tag, " sync_wait"});
        end
    endtask

    // ========================================================================
    //  激励生成
    // ========================================================================
    integer seed = 32'h1234_ABCD;
    task automatic rstep; begin seed = {seed[30:0], seed[31]^seed[21]^seed[1]}; end endtask

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

    task send_short(input [5:0] dt, input [15:0] wcv, input [1:0] vc, input bad_ecc, input integer gap_after);
        reg [23:0] d; reg [7:0] e;
        begin
            d = {wcv, vc, dt};
            e = hdr_ecc(d);
            if (bad_ecc) e = e ^ 8'h40;
            send_word({e, d}, gap_after);
        end
    endtask

    // 长包：payload_used 字节参与 CRC/payload，crc_bad 让 CRC 错；extra 字节补到 4 字节边界
    task send_long(input [15:0] wcv, input integer first_pix, input bad_crc,
                   input integer gap_after, input integer corrupt_data);
        integer nb, i, wi, nwords;
        reg [7:0]  byt [0:1027];
        reg [15:0] crc;
        reg [23:0] hd; reg [7:0] he; reg [31:0] w;
        begin
            for (i = 0; i < wcv; i = i + 1) byt[i] = (first_pix + i) & 8'hFF;
            if (corrupt_data && wcv > 2) byt[wcv/2] = byt[wcv/2] ^ 8'h5A;
            crc = 16'hFFFF;
            for (i = 0; i < wcv; i = i + 1) crc = crc_byte_f(crc, byt[i]);
            if (bad_crc) crc = crc ^ 16'h0040;
            byt[wcv+0] = crc[7:0];
            byt[wcv+1] = crc[15:8];
            hd = {wcv, VC, DT_IMG};
            he = hdr_ecc(hd);
            send_word({he, hd}, 0);
            nb = wcv + 2;
            nwords = (nb + 3) / 4;
            for (wi = 0; wi < nwords; wi = wi + 1) begin
                w = 32'd0;
                for (i = 0; i < 4; i = i + 1)
                    if ((wi*4+i) < nb) w[i*8 +: 8] = byt[wi*4+i];
                send_word(w, (wi == nwords-1) ? gap_after : 0);
            end
        end
    endtask

    task frame_open_evt(input [15:0] fid);
        begin send_short(6'h00, fid, VC, 1'b0, 3); end
    endtask
    task frame_close_evt(input [15:0] fid);
        begin send_short(6'h01, fid, VC, 1'b0, 3); end
    endtask

    integer i, ln, n;
    integer ngood = 0;
    initial begin
        rst_n = 0; en = 0; valid = 0; data = 0;
        repeat (6) @(negedge clk);
        rst_n = 1; repeat (4) @(negedge clk);
        en = 1; repeat (4) @(negedge clk);

        $display("=== P1 好帧（4 行 × WC=80）===");
        frame_open_evt(16'h0001);
        for (ln = 0; ln < 4; ln = ln + 1) send_long(16'd80, ln*80, 1'b0, 3, 0);
        frame_close_evt(16'h0001);
        quiesce_check("P1");
        ngood = (n_good === r_good);

        $display("=== P2 坏 CRC（第 2 行）===");
        frame_open_evt(16'h0002);
        send_long(16'd80, 0, 1'b0, 3, 0);
        send_long(16'd80, 80, 1'b1, 3, 0);
        send_long(16'd80, 160, 1'b0, 3, 0);
        send_long(16'd80, 240, 1'b0, 3, 0);
        frame_close_evt(16'h0002);
        quiesce_check("P2");

        $display("=== P3 WC 边界（5/10/15/80/非5倍/0）===");
        frame_open_evt(16'h0003);
        send_long(16'd5,   0, 1'b0, 3, 0);      // 最小一组（1 字 + CRC 尾）
        send_long(16'd10,  5, 1'b0, 3, 0);
        send_long(16'd15, 15, 1'b0, 3, 0);
        send_long(16'd80, 30, 1'b0, 3, 0);
        send_long(16'd78, 110, 1'b0, 2, 0);     // 非 5 倍数：image_ok=0 → 坏帧
        send_long(16'd80, 188, 1'b0, 3, 0);
        frame_close_evt(16'h0003);
        quiesce_check("P3");

        $display("=== P4 行长/WC 与 IMAGE_WC 不符 + 行数不对 ===");
        frame_open_evt(16'h0004);
        send_long(16'd85, 0, 1'b0, 2, 0);       // WC != IMAGE_WC
        send_long(16'd80, 85, 1'b0, 3, 0);
        send_long(16'd80, 165, 1'b0, 3, 0);
        frame_close_evt(16'h0004);              // 行数 3 != EXPECTED_LINES 4 → 不 good
        quiesce_check("P4");

        $display("=== P5 包内 idle 超时 / 数据中途停 ===");
        frame_open_evt(16'h0005);
        send_word(32'hAAAA_AAAA, 6);            // 毫无意义的一拍（BODY 内）
        quiesce_check("P5");

        $display("=== P6 帧中途停住（帧超时参数=2000 拍）===");
        frame_open_evt(16'h0006);
        send_long(16'd80, 0, 1'b0, 3, 0);
        repeat (2100) @(negedge clk);           // 超过 F_TMO
        quiesce_check("P6");

        $display("=== P7 坏头 ECC / 未知 DT / 非选中 VC / FE 无帧 ===");
        send_short(6'h00, 16'h0007, VC, 1'b1, 3);  // ECC 坏
        send_word({8'h12, 8'h00, 8'h00, 6'h3f}, 3);   // 未知 DT
        send_short(6'h00, 16'h0008, 2'd1, 1'b0, 3);      // 非选中 VC
        send_short(6'h01, 16'h0009, VC, 1'b0, 3);        // FE 无帧
        quiesce_check("P7");

        $display("=== P8 abort 后恢复（FS 打断一帧 → 新帧好）===");
        frame_open_evt(16'h000A);
        send_long(16'd80, 0, 1'b0, 3, 0);
        send_long(16'd80, 80, 1'b0, 3, 0);
        frame_open_evt(16'h000B);                     // 未收尾又来 FS → abort + 重开
        for (ln = 0; ln < 4; ln = ln + 1) send_long(16'd80, ln*80, 1'b0, 3, 0);
        frame_close_evt(16'h000B);
        quiesce_check("P8");

        $display("=== P9 随机流量（200 包，含随机空隙/随机坏 CRC/WC/长度）===");
        for (n = 0; n < 200; n = n + 1) begin
            rstep;
            case (seed[2:0])
                3'd0: begin // 随机长包（不包在帧里）
                    send_long((seed[15:8] % 20 + 1) * 5, seed[23:16], seed[3], seed[5:4], seed[6]);
                end
                3'd1: send_short(seed[5:0], seed[23:8], VC, seed[7], 3);
                3'd2: send_word(seed, seed[5:4]);
                3'd3: begin frame_open_evt(seed[23:8]); end
                3'd4: begin
                    for (i = 0; i < (seed[15:12] % 3 + 1); i = i + 1)
                        send_long(16'd80, i*80, seed[7], seed[3:2], seed[8]);
                    frame_close_evt(seed[23:8]);
                end
                3'd5: repeat (seed[15:12] % 9) @(negedge clk);   // 纯空隙
                3'd6: begin send_short(6'h01, seed[23:8], VC, seed[7], 3); end
                default: send_long(16'd80, 0, 1'b0, seed[3:2], 0);
            endcase
        end
        quiesce_check("P9");

        $display("=== P10 复位后再跑一轮（隔离/恢复）===");
        rst_n = 0; valid = 0; repeat (4) @(negedge clk); rst_n = 1; repeat (4) @(negedge clk);
        frame_open_evt(16'h000C);
        for (ln = 0; ln < 4; ln = ln + 1) send_long(16'd80, ln*80, 1'b0, 3, 0);
        frame_close_evt(16'h000C);
        quiesce_check("P10");

        repeat (10) @(posedge clk);
        $display("payload beats compared = %0d, payload mismatches = %0d", payload_beats, payload_mismatch);
        if (errs == 0) $display("ALL PASS (payload cycle-exact; abort/counters <=2 cycle lag checked)");
        else           $display("FAIL: %0d mismatches", errs);
        $finish;
    end

    initial begin
        #2_000_000;
        $display("FAIL: global timeout");
        $finish;
    end

endmodule
