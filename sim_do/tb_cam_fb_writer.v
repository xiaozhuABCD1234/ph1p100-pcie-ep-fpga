///////////////////////////////////////////////////////////////
//  tb_cam_fb_writer.v — cam_fb_writer + img_frame_src 冒烟测试
//
//  ★ 本机没有仿真器：本测试台「只写不跑」，结论里必须标注“未运行”。
//    在有 iverilog 的机器上跑：
//      iverilog -o tb_cam_fb_writer tb_cam_fb_writer.v \
//               ../../rtl/ep_side/img/cam_fb_writer.v \
//               ../../rtl/ep_side/img/img_frame_src.v
//      ./tb_cam_fb_writer            # 期望输出 "ALL PASS"
//
//  测什么：
//   1) 字节时钟域（187.5MHz）按 CSI-2 收包的真实约定造流：
//        cam_vsync 1 拍 = SOF；cam_in_frame 电平（FE 下降沿 = EOF）；
//        cam_in_line 每行 1 拍脉冲；cam_pix_valid 1 拍 = 1 组 = 4 像素，
//        每行 160 组入窗（x=0..636）+ 40 组域外（x=640..796，应被丢掉）；
//   2) 异步 FIFO 跨到 62.5MHz 后，帧缓存的布局：
//        字 0..76799 全是像素，字 y*160+g = {p3[9:2],p2[9:2],p1[9:2],p0[9:2]}，
//        低字节 = 最左像素（帧号不占缓存，它是 cam_frame_cnt / 0x4C 寄存器）；
//   3) 两帧校验（FRAME_CNT 递增、整块缓存逐字对得上）、drop/ovf 计数必须为 0；
//   4) cam_sel=0 时测试图源仍是原来那套（写源 mux 双向都对）。
///////////////////////////////////////////////////////////////
`timescale 1ns/1ps

module tb_cam_fb_writer;

    localparam W        = 640;
    localparam H        = 480;
    localparam GROUPS   = W / 4;              // 每行入窗组数 = 160
    localparam JUNK     = 40;                 // 每行域外组数（应被丢）
    localparam WORDS    = (W * H) / 4;        // 76800

    // ---------------- 时钟 / 复位 ----------------
    reg cam_clk = 0;                 // 187.5MHz（字节时钟）
    reg clk     = 0;                 // 62.5MHz（tl_clk_user）
    reg cam_rst_n = 0;
    reg rst       = 1;
    always #2.667 cam_clk = ~cam_clk;
    always #8.0   clk     = ~clk;

    // ---------------- 字节域激励 ----------------
    reg         cam_vsync   = 0;
    reg         cam_in_frame= 0;
    reg         cam_in_line = 0;
    reg  [39:0] cam_pix     = 0;
    reg         cam_pix_valid = 0;

    // ---------------- DUT 互连 ----------------
    wire        fb_wr_en;
    wire [31:0] fb_wr_addr, fb_wr_data;
    wire [31:0] cam_frame_cnt, cam_data_len;
    wire        cam_ready, cam_busy, cam_frame_done;
    wire [31:0] cam_wr_word_cnt;
    wire [15:0] cam_drop_cnt, cam_ovf_cnt;

    reg         cam_sel = 1'b1;      // 1 = 相机写源
    reg         test_en  = 1'b0;      // 测试图源 enable（第二段检查用）

    wire [31:0] rd_addr;
    wire [31:0] rd_data;
    reg  [31:0] rd_addr_r = 32'd0;

    wire [31:0] img_frame_cnt, img_data_len;
    wire        img_ready, img_busy;
    wire [15:0] img_w, img_h;

    integer errors = 0;
    integer f, y, g, k;
    reg [31:0] got, exp;

    // 每帧/每行像素公式：pix = ((y*GROUPS+g)*4 + j) & 1023（10bit RAW10）
    function [39:0] pack_pix;
        input integer yy;
        input integer gg;
        integer idx;
        begin
            idx = (yy * GROUPS + gg) * 4;
            pack_pix[9:0]   = (idx + 0) & 32'd1023;
            pack_pix[19:10] = (idx + 1) & 32'd1023;
            pack_pix[29:20] = (idx + 2) & 32'd1023;
            pack_pix[39:30] = (idx + 3) & 32'd1023;
        end
    endfunction

    function [31:0] exp_word;
        input integer yy;
        input integer gg;
        integer idx;
        begin
            idx = (yy * GROUPS + gg) * 4;
            exp_word = {((idx + 3) & 32'd1023) >> 2,
                        ((idx + 2) & 32'd1023) >> 2,
                        ((idx + 1) & 32'd1023) >> 2,
                        ((idx + 0) & 32'd1023) >> 2};
        end
    endfunction

    cam_fb_writer #(
        .W (W), .H (H), .AW (17), .FIFO_AW (9)
    ) u_dut (
        .cam_clk       (cam_clk),
        .cam_rst_n     (cam_rst_n),
        .cam_vsync     (cam_vsync),
        .cam_in_frame  (cam_in_frame),
        .cam_in_line   (cam_in_line),
        .cam_pix       (cam_pix),
        .cam_pix_valid (cam_pix_valid),
        .clk           (clk),
        .rst           (rst),
        .fb_wr_en      (fb_wr_en),
        .fb_wr_addr    (fb_wr_addr),
        .fb_wr_data    (fb_wr_data),
        .frame_cnt     (cam_frame_cnt),
        .data_len      (cam_data_len),
        .ready         (cam_ready),
        .busy          (cam_busy),
        .frame_done    (cam_frame_done),
        .wr_word_cnt   (cam_wr_word_cnt),
        .drop_cnt      (cam_drop_cnt),
        .ovf_cnt       (cam_ovf_cnt)
    );

    img_frame_src #(
        .W (W), .H (H), .IDLE_CYCLE (200)
    ) u_src (
        .clk       (clk),
        .rst       (rst),
        .enable    (test_en),         // 测试图源（第二段检查才打开）
        .trigger   (1'b0),
        .rd_addr   (rd_addr),
        .rd_data   (rd_data),
        .dbg_rd_idx(),
        .frame_cnt (img_frame_cnt),
        .width     (img_w),
        .height    (img_h),
        .data_len  (img_data_len),
        .ready     (img_ready),
        .busy      (img_busy),
        .cam_sel       (cam_sel),
        .cam_wr_en     (fb_wr_en),
        .cam_wr_addr   (fb_wr_addr),
        .cam_wr_data   (fb_wr_data),
        .cam_frame_cnt (cam_frame_cnt),
        .cam_data_len  (cam_data_len),
        .cam_ready     (cam_ready),
        .cam_busy      (cam_busy)
    );

    assign rd_addr = rd_addr_r;

    // ---------------- 读帧缓存（与主机 0x5C/0x60 同一读口语义）----------------
    task read_word;
        input  integer widx;
        output [31:0] d;
        begin
            @(negedge clk);
            rd_addr_r = widx * 4;
            @(negedge clk);          // 上一拍 posedge 采样地址 → 本拍拿到数据
            d = rd_data;
        end
    endtask

    task chk;
        input [255:0] name;
        input [31:0]  got_v;
        input [31:0]  exp_v;
        begin
            if (got_v !== exp_v) begin
                if (errors < 20)
                    $display("  FAIL %0s: got %08x exp %08x", name, got_v, exp_v);
                errors = errors + 1;
            end
        end
    endtask

    // 一帧 CSI-2 流：FS → H 行（每行 1 拍行头 + 160 组入窗 + 40 组域外）→ FE
    task gen_frame;
        begin
            @(posedge cam_clk); cam_vsync <= 1'b1; cam_in_frame <= 1'b1;
            @(posedge cam_clk); cam_vsync <= 1'b0;
            for (y = 0; y < H; y = y + 1) begin
                @(posedge cam_clk); cam_in_line <= 1'b1;
                @(posedge cam_clk); cam_in_line <= 1'b0;
                for (g = 0; g < GROUPS + JUNK; g = g + 1) begin
                    @(posedge cam_clk);
                    cam_pix       <= pack_pix(y, g);
                    cam_pix_valid <= 1'b1;         // 1 组/拍 = 最坏突发
                end
                @(posedge cam_clk); cam_pix_valid <= 1'b0;
                repeat (4) @(posedge cam_clk);     // 行间空档（blanking）
            end
            @(posedge cam_clk); cam_in_frame <= 1'b0;   // FE → EOF
            repeat (10) @(posedge cam_clk);
        end
    endtask

    initial begin
        $display("--- tb_cam_fb_writer: cam_fb_writer + img_frame_src ---");

        repeat (8) @(posedge cam_clk);
        cam_rst_n = 1;
        repeat (8) @(posedge clk);
        rst = 0;
        repeat (8) @(posedge clk);

        // ================= 相机写源：第 1、2 帧 =================
        for (f = 0; f < 2; f = f + 1) begin
            gen_frame;
            // 等这一帧写完（EOF 后 frame_cnt 递增、busy 落）
            k = 0;
            while ((cam_frame_cnt !== (f + 1)) && (k < 2000000)) begin
                @(posedge clk); k = k + 1;
            end
            chk("cam frame_cnt", cam_frame_cnt, f + 1);
            chk("cam busy=0",    {31'd0, cam_busy}, 32'd0);
            chk("cam frame_done",{31'd0, cam_frame_done}, 32'd1);
            chk("cam ready",     {31'd0, cam_ready}, 32'd1);
            chk("cam data_len",  cam_data_len, W * H);
            chk("cam wr_word_cnt", cam_wr_word_cnt, WORDS);      // 76800 个像素字
            chk("cam drop_cnt",  {16'd0, cam_drop_cnt}, 32'd0);  // FIFO 不能满
            chk("cam ovf_cnt",   {16'd0, cam_ovf_cnt},  32'd0);

            // 全帧逐字比对（含行号 → 验证行/列计数与组序；字 0 就是第 0 行最左 4 像素）
            for (y = 0; y < H; y = y + 1) begin
                for (g = 0; g < GROUPS; g = g + 1) begin
                    read_word(y * GROUPS + g, got);
                    exp = exp_word(y, g);
                    chk("pixel word", got, exp);
                end
            end
            $display("  frame %0d checked (%0d errors so far)", f + 1, errors);
        end

        // ================= 测试图源仍然可用（写源 mux 反向）=================
        cam_sel = 1'b0;
        test_en = 1'b1;
        repeat (4) @(posedge clk);
        k = 0;
        while ((img_frame_cnt !== 32'd1) && (k < 2000000)) begin
            @(posedge clk); k = k + 1;
        end
        chk("test frame_cnt", img_frame_cnt, 32'd1);      // 测试图源已出完第 0 帧
        // 测试图公式 pix = x + y + FRAME_CNT（帧末才 +1 ⇒ 本帧用 0）
        read_word(0, got); chk("test pixel word0", got, 32'h03020100);
        read_word(1, got); chk("test pixel word1", got, 32'h07060504);
        test_en = 1'b0;

        if (errors == 0) $display("ALL PASS");
        else             $display("FAILED: %0d errors", errors);
        $finish;
    end

    // 超时保护
    initial begin
        #200_000_000;                       // 200ms 仿真时间
        $display("TIMEOUT (errors=%0d)", errors);
        $finish;
    end

endmodule
