`timescale 1ns/1ps
//////////////////////////////////////////////////////////////////////
//  tb_cam_ae_ctrl.v — cam_ae_ctrl 自检 testbench
//
//  8 帧 64x32 合成画面，行首 8 个像素在测光窗口外（pix=1023），
//  窗口内像素固定为可控均值，因此帧均值应精确等于设定值，
//  同时可检查 win 门控、过亮/过暗计数。
//
//  覆盖：亮帧降增益、暗帧升增益、死区不发请求、
//        等 I_ae_done 才发下一次请求、GAIN_MIN/MAX 夹紧、
//        AE 关闭时保持手动增益。
//////////////////////////////////////////////////////////////////////
module tb_cam_ae_ctrl;

    localparam integer FRAME_W   = 64;
    localparam integer FRAME_H   = 32;
    localparam integer OUT_COLS  = 8;    // 每行窗口外像素数

    reg        clk_cam;
    reg        clk_tl;
    reg        rst_cam;
    reg        rst_tl;

    reg        de;
    reg [9:0]  pix;
    reg        win;
    reg        sof;
    reg        eof;

    reg        I_ae_en;
    reg [7:0]  I_ae_manual_gain;
    reg        I_ae_done;

    wire       O_ae_req;
    wire [7:0] O_ae_data;
    wire [9:0] O_frame_mean;
    wire       O_frame_stats_valid;
    wire [31:0] O_clip_cnt;
    wire [31:0] O_dark_cnt;
    wire [7:0] O_gain_code;

    integer errors;
    integer req_count;
    integer req_seen;
    reg [7:0] req_data_last;
    reg       req_d;
    reg       hold_done;
    integer   wait_cnt;
    reg       done_busy;

    integer i;

    // ---------------- DUT ----------------
    // 为在 8 帧内覆盖夹紧，测试实例把步进调到 ±80；帧分频设为 1。
    cam_ae_ctrl #(
        .P_TARGET     (10'd400),
        .P_DEADBAND   (10'd40),
        .P_GAIN_MIN   (8'd0),
        .P_GAIN_MAX   (8'd160),
        .P_GAIN_INIT  (8'd64),
        .P_FRAME_DIV  (16'd1),
        .P_STEP_SHIFT (4'd0),
        .P_STEP_MAX   (8'd90),
        .P_DONE_TO    (24'h00_FFFF)
    ) u_dut (
        .clk_cam             (clk_cam),
        .rst_cam             (rst_cam),
        .de                  (de),
        .pix                 (pix),
        .win                 (win),
        .sof                 (sof),
        .eof                 (eof),
        .clk_tl              (clk_tl),
        .rst_tl              (rst_tl),
        .I_ae_en             (I_ae_en),
        .I_ae_manual_gain    (I_ae_manual_gain),
        .I_ae_done           (I_ae_done),
        .O_ae_req            (O_ae_req),
        .O_ae_data           (O_ae_data),
        .O_frame_mean        (O_frame_mean),
        .O_frame_stats_valid (O_frame_stats_valid),
        .O_clip_cnt          (O_clip_cnt),
        .O_dark_cnt          (O_dark_cnt),
        .O_gain_code         (O_gain_code)
    );

    // ---------------- 时钟 ----------------
    initial clk_cam = 1'b0;
    always #2.5 clk_cam = ~clk_cam;      // 200MHz
    initial clk_tl = 1'b0;
    always #5.0 clk_tl = ~clk_tl;        // 100MHz

    // ---------------- I_ae_done 行为模型 ----------------
    // 模拟 ui_cfg_imx415：空闲为高，收到请求拉低，写完后拉高。
    always @(posedge clk_tl) begin
        req_d <= O_ae_req;
        if (O_ae_req && !req_d) begin
            req_count     = req_count + 1;
            req_data_last = O_ae_data;
            done_busy     = 1'b1;
            wait_cnt      = 0;
            I_ae_done    <= 1'b0;
        end else if (done_busy) begin
            if (hold_done) begin
                I_ae_done <= 1'b0;
            end else if (wait_cnt < 3) begin
                wait_cnt  = wait_cnt + 1;
                I_ae_done <= 1'b0;
            end else begin
                I_ae_done <= 1'b1;
                done_busy = 1'b0;
            end
        end
    end

    // ---------------- 检查任务 ----------------
    task wait_stats;
        input [9:0] exp_mean;
        input integer id;
        integer k;
        reg hit;
        begin
            hit = 1'b0;
            for (k = 0; k < 20000 && !hit; k = k + 1) begin
                @(posedge clk_tl);
                if (O_frame_stats_valid) begin
                    hit = 1'b1;
                    $display("  [%0d] frame mean=%0d (exp %0d) clip=%0d dark=%0d",
                             id, O_frame_mean, exp_mean, O_clip_cnt, O_dark_cnt);
                    if (O_frame_mean !== exp_mean) begin
                        errors = errors + 1;
                        $display("  ERROR[%0d]: mean mismatch, got %0d", id, O_frame_mean);
                    end
                    if (O_clip_cnt !== 32'd0 || O_dark_cnt !== 32'd0) begin
                        errors = errors + 1;
                        $display("  ERROR[%0d]: window gating broken, clip=%0d dark=%0d",
                                 id, O_clip_cnt, O_dark_cnt);
                    end
                end
            end
            if (!hit) begin
                errors = errors + 1;
                $display("  ERROR[%0d]: timeout waiting frame stats", id);
            end
        end
    endtask

    task expect_req;
        input [7:0] exp_data;
        input integer id;
        integer k;
        reg hit;
        begin
            hit = 1'b0;
            for (k = 0; k < 4000 && !hit; k = k + 1) begin
                @(posedge clk_tl);
                if (req_count > req_seen) begin
                    hit       = 1'b1;
                    req_seen  = req_count;
                    $display("  [%0d] req #%0d data=%0d (exp %0d)",
                             id, req_count, req_data_last, exp_data);
                    if (req_data_last !== exp_data) begin
                        errors = errors + 1;
                        $display("  ERROR[%0d]: req data mismatch, got %0d", id, req_data_last);
                    end
                end
            end
            if (!hit) begin
                errors = errors + 1;
                $display("  ERROR[%0d]: timeout waiting O_ae_req (exp data %0d)", id, exp_data);
            end
        end
    endtask

    task expect_no_req;
        input integer cycles;
        input integer id;
        integer k;
        begin
            for (k = 0; k < cycles; k = k + 1) @(posedge clk_tl);
            if (req_count != req_seen) begin
                errors   = errors + 1;
                req_seen = req_count;
                $display("  ERROR[%0d]: unexpected O_ae_req (data %0d)", id, req_data_last);
            end else begin
                $display("  [%0d] OK: no O_ae_req in %0d cycles", id, cycles);
            end
        end
    endtask

    task check_gain;
        input [7:0] exp_gain;
        input integer id;
        integer k;
        begin
            for (k = 0; k < 20; k = k + 1) @(posedge clk_tl);
            $display("  [%0d] gain_code=%0d (exp %0d)", id, O_gain_code, exp_gain);
            if (O_gain_code !== exp_gain) begin
                errors = errors + 1;
                $display("  ERROR[%0d]: gain_code mismatch, got %0d", id, O_gain_code);
            end
        end
    endtask

    // ---------------- 合成一帧 ----------------
    task send_frame;
        input integer mean_val;
        integer x, y;
        begin
            @(posedge clk_cam);
            sof <= 1'b1; de <= 1'b0; win <= 1'b0; pix <= 10'd0;
            @(posedge clk_cam);
            sof <= 1'b0;
            for (y = 0; y < FRAME_H; y = y + 1) begin
                for (x = 0; x < FRAME_W; x = x + 1) begin
                    @(posedge clk_cam);
                    de  <= 1'b1;
                    win <= (x >= OUT_COLS);
                    pix <= (x >= OUT_COLS) ? mean_val[9:0] : 10'd1023;
                end
            end
            @(posedge clk_cam);
            de <= 1'b0; win <= 1'b0; eof <= 1'b1;
            @(posedge clk_cam);
            eof <= 1'b0;
        end
    endtask

    // ---------------- 主激励 ----------------
    initial begin
        de = 0; pix = 0; win = 0; sof = 0; eof = 0;
        I_ae_en = 1; I_ae_manual_gain = 8'd0; I_ae_done = 1;
        errors = 0; req_count = 0; req_seen = 0; req_data_last = 0;
        req_d = 0; hold_done = 0; wait_cnt = 0; done_busy = 0;
        rst_cam = 1; rst_tl = 1;

        #200;
        rst_cam = 0; rst_tl = 0;
        repeat (10) @(posedge clk_tl);
        $display("---- start: init gain 64, target 400 +/-40 ----");

        // F1: 亮帧 900 -> 64-80 -> 夹到 GAIN_MIN=0
        send_frame(900);
        wait_stats(10'd900, 1);
        expect_req(8'd0, 1);
        check_gain(8'd0, 1);
        expect_no_req(30, 101);

        // F2: 暗帧 100 -> 0+90=90，验证暗帧升增益
        send_frame(100);
        wait_stats(10'd100, 2);
        expect_req(8'd90, 2);
        check_gain(8'd90, 2);
        expect_no_req(30, 102);

        // F3: 继续暗帧 90+90=180 -> 夹到 GAIN_MAX=160
        send_frame(100);
        wait_stats(10'd100, 3);
        expect_req(8'd160, 3);
        check_gain(8'd160, 3);
        expect_no_req(30, 103);

        // F4: 均值 410 在死区内 -> 不得发请求
        send_frame(410);
        wait_stats(10'd410, 4);
        expect_no_req(150, 4);
        check_gain(8'd160, 4);

        // F5: 460 -> 误差 -60，比例步进 -60 -> 100
        send_frame(460);
        wait_stats(10'd460, 5);
        expect_req(8'd100, 5);
        check_gain(8'd100, 5);
        expect_no_req(30, 105);

        // F6: 700 -> 100-90=10；此后扣住 done 不返回
        hold_done = 1'b1;
        send_frame(700);
        wait_stats(10'd700, 6);
        expect_req(8'd10, 6);
        expect_no_req(60, 106);

        // F7: done 一直低，期间再来一帧也不许发新请求
        send_frame(700);
        wait_stats(10'd700, 7);
        expect_no_req(300, 7);

        // 释放 done：先完成 F6，再补发 F7 的更新（10-90 -> 夹到 0）
        hold_done = 1'b0;
        expect_req(8'd0, 8);
        check_gain(8'd0, 8);
        expect_no_req(30, 107);

        // F8: 均值 400 在死区内 -> 不发请求
        send_frame(400);
        wait_stats(10'd400, 9);
        expect_no_req(150, 9);

        // AE 旁路：关闭后必须保持 I_ae_manual_gain
        $display("---- AE bypass ----");
        I_ae_en = 1'b0;
        I_ae_manual_gain = 8'd99;
        expect_req(8'd99, 10);
        check_gain(8'd99, 10);
        expect_no_req(60, 108);

        I_ae_manual_gain = 8'd120;
        expect_req(8'd120, 11);
        check_gain(8'd120, 11);
        expect_no_req(60, 109);

        // 手动值越界也必须夹到 GAIN_MAX
        I_ae_manual_gain = 8'd250;
        expect_req(8'd160, 12);
        check_gain(8'd160, 12);
        expect_no_req(60, 110);

        if (errors == 0) begin
            $display("PASS: cam_ae_ctrl all checks passed");
            $finish;
        end else begin
            $display("FAIL: %0d error(s)", errors);
            $fatal;
        end
    end

endmodule
