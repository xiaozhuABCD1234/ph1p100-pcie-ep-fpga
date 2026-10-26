`timescale 1ps/1fs
// 验证 ROM → hdmi_tx_phy_wrapper 的串行位序是否等于模型期望。
//
// 期望来源（**非循环论证**）：TB 读入的是**自然形式** TMDS 码（bit9=符号 MSB），
// 而 ROM 里存的是它们的位反转；"线上先发 natural[9]"必须由 ROM+wrapper+lane **独立产生**。
//
// 采样策略：每 bit **过采样 8 次（125ps）**，再对 8 个相位逐一检查。
// 这样不依赖"猜采样相位"——早期版本用固定 1 点/bit，一旦采到跳变沿就会
// 产生毛刺并把后续位序整体错开（实测只有 ~50% 匹配）。
module tb_tmds_pattern_rom #(parameter DEPTH = 20);
    parameter pclk_half = 5000;
    parameter sclk_half = 1000;
    localparam OS = 8;                       // oversampling per bit
    localparam NBITS = 3 * DEPTH * 10 + 200; // 抓取位数

    reg pclk = 0, sclk = 0, rst = 1;
    reg enable = 0;
    always #(pclk_half) pclk = ~pclk;
    always #(sclk_half) sclk = ~sclk;

    wire [9:0] r0, r1, r2, r3;
    // 在下降沿把 ROM 输出打一拍再送进 OSERDES（避免与并行装载同刻变化）
    reg [9:0] q0, q1, q2, q3;
    always @(negedge pclk) begin
        q0 <= r0; q1 <= r1; q2 <= r2; q3 <= r3;
    end

    tmds_pattern_rom #(.DEPTH(DEPTH)) u_rom (
        .clk(pclk), .rst_n(~rst), .enable(enable),
        .ch0(r0), .ch1(r1), .ch2(r2), .clk_ch(r3), .index());

    wire s0, s1, s2, s3;
    hdmi_tx_phy_wrapper #(.DEVICE("PH1P")) u_phy (
        .I_pixel_clk(pclk), .I_serial_clk(sclk), .I_rst(rst),
        .I_tmds_channel_0(q0), .I_tmds_channel_1(q1),
        .I_tmds_channel_2(q2), .I_tmds_channel_clk(q3),
        .O_tmds_ch0_p(s0), .O_tmds_ch1_p(s1), .O_tmds_ch2_p(s2), .O_tmds_clk_p(s3));

    // 期望（自然形式 10bit 码）
    reg [9:0] e0[0:DEPTH-1], e1[0:DEPTH-1], e2[0:DEPTH-1], e3[0:DEPTH-1];
    reg [1023:0] vecdir, fn;

    reg d0[0:OS*NBITS-1], d1[0:OS*NBITS-1], d2[0:OS*NBITS-1], d3[0:OS*NBITS-1];

    integer i, j, k, p, start, bad, found, chk, dump_fd;
    integer BITS;

    task check_lane(input integer lane);
        begin
            found = -1;
            // 注意：对齐起点必须搜到"抓取长度 - 一个周期"，否则会漏掉带流水延迟的
            // 真实对齐（早期 bug：只搜到 BITS=200，而真值在 ~211，导致假失败）。
            for (p = 0; p < OS && found < 0; p = p + 1) begin
                for (start = 0; start <= NBITS - BITS && found < 0; start = start + 1) begin
                    bad = 0;
                    for (j = 0; j < BITS; j = j + 1) begin
                        case (lane)
                            0: if (d0[p + (start + j) * OS] !== e0[j / 10][9 - (j % 10)]) bad = 1;
                            1: if (d1[p + (start + j) * OS] !== e1[j / 10][9 - (j % 10)]) bad = 1;
                            2: if (d2[p + (start + j) * OS] !== e2[j / 10][9 - (j % 10)]) bad = 1;
                            default: if (d3[p + (start + j) * OS] !== e3[j / 10][9 - (j % 10)]) bad = 1;
                        endcase
                    end
                    if (!bad) begin
                        found = start;
                        $display("ROM_TB_ALIGN lane=%0d phase=%0d start=%0d", lane, p, start);
                    end
                end
            end
            if (found < 0) begin
                $display("ROM_TB_FAIL lane=%0d no phase/alignment matches", lane);
                $finish;
            end
            chk = chk + BITS;
        end
    endtask

    initial begin
        chk = 0;
        BITS = DEPTH * 10;
        if (!$value$plusargs("VECDIR=%s", vecdir)) begin
            $display("ROM_TB_FAIL no +VECDIR");
            $finish;
        end
        fn = {vecdir, "/expect_ch0.hex"}; $readmemh(fn, e0);
        fn = {vecdir, "/expect_ch1.hex"}; $readmemh(fn, e1);
        fn = {vecdir, "/expect_ch2.hex"}; $readmemh(fn, e2);
        fn = {vecdir, "/expect_clk.hex"}; $readmemh(fn, e3);

        rst = 1; enable = 0;
        #40750;
        rst = 0;
        @(posedge sclk);
        enable = 1;
        for (i = 0; i < OS * NBITS; i = i + 1) begin
            d0[i] = s0; d1[i] = s1; d2[i] = s2; d3[i] = s3;
            #125;
        end
        dump_fd = $fopen({vecdir, "/capture.txt"}, "w");
        for (i = 0; i < OS * NBITS; i = i + 1)
            $fwrite(dump_fd, "%b %b %b %b\n", d0[i], d1[i], d2[i], d3[i]);
        $fclose(dump_fd);

        check_lane(0); check_lane(1); check_lane(2); check_lane(3);
        $display("ROM_TB_PASS bits=%0d dep=%0d oversample=%0d", chk, DEPTH, OS);
        $finish;
    end
    initial begin #60000000; $display("ROM_TB_FAIL timeout"); $finish; end
endmodule
