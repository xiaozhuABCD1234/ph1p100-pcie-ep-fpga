///////////////////////////////////////////////////////////////
//  tb_img.v — img_regs + img_frame_src 冒烟测试（iverilog）
//  iverilog -o tb_img tb_img.v img_regs.v img_frame_src.v && ./tb_img
///////////////////////////////////////////////////////////////
`timescale 1ns/1ps

module tb_img;
    localparam W        = 320;
    localparam H        = 240;
    localparam WORDS    = (W * H) / 4;
    localparam PTR_MASK = (WORDS * 4) - 4;

    reg         clk = 0;
    reg         rst = 1;

    reg         ubus_wen   = 0;
    reg  [31:0] ubus_waddr = 0;
    reg  [31:0] ubus_wdata = 0;
    reg         ubus_ren   = 0;
    reg  [31:0] ubus_raddr = 0;

    wire        hit_dly, bken;
    wire [31:0] rdata;
    wire [31:0] fb_raddr, fb_rdata;
    wire        ctrl_enable, ctrl_trigger;
    wire        st_ready, st_busy;
    wire [31:0] st_frame_cnt, st_data_len;
    wire [15:0] st_width, st_height;

    integer errors = 0;
    integer i;
    reg [31:0] v, fc0, w1, w2;
    reg [7:0]  b0, b1, b2, b3;

    always #4 clk = ~clk;                  // 125 MHz

    img_regs #(.PTR_MASK (PTR_MASK)) u_regs (
        .clk (clk), .rst (rst), .clk_mhz (9'd125),
        .ubus_wen (ubus_wen), .ubus_waddr (ubus_waddr), .ubus_wdata (ubus_wdata),
        .ubus_ren (ubus_ren), .ubus_raddr (ubus_raddr),
        .hit_dly (hit_dly), .bken (bken), .rdata (rdata),
        .fb_raddr (fb_raddr), .fb_rdata (fb_rdata),
        .ctrl_enable (ctrl_enable), .ctrl_trigger (ctrl_trigger),
        .st_ready (st_ready), .st_busy (st_busy),
        .st_frame_cnt (st_frame_cnt), .st_width (st_width),
        .st_height (st_height), .st_data_len (st_data_len)
    );

    img_frame_src #(.W (W), .H (H), .IDLE_CYCLE (200)) u_src (
        .clk (clk), .rst (rst),
        .enable (ctrl_enable), .trigger (ctrl_trigger),
        .rd_addr (fb_raddr), .rd_data (fb_rdata),
        .frame_cnt (st_frame_cnt), .width (st_width), .height (st_height),
        .data_len (st_data_len), .ready (st_ready), .busy (st_busy)
    );

    // ---------------- UBUS 访问 ----------------
    task do_read;
        input  [31:0] addr;
        output [31:0] val;
        begin
            @(posedge clk);
            ubus_ren   <= 1'b1;
            ubus_raddr <= addr;
            @(posedge clk);
            ubus_ren   <= 1'b0;
            wait (bken === 1'b1);
            #1;
            val = rdata;
            @(posedge clk);
        end
    endtask

    task do_write;
        input [31:0] addr;
        input [31:0] val;
        begin
            @(posedge clk);
            ubus_wen   <= 1'b1;
            ubus_waddr <= addr;
            ubus_wdata <= val;
            @(posedge clk);
            ubus_wen   <= 1'b0;
            ubus_waddr <= 32'd0;
            ubus_wdata <= 32'd0;
            @(posedge clk);
        end
    endtask

    task chk;                       // 通用断言
        input [255:0] name;
        input [31:0]  got;
        input [31:0]  exp;
        begin
            if (got !== exp) begin
                $display("  FAIL %0s: got %08x, exp %08x", name, got, exp);
                errors = errors + 1;
            end else
                $display("  PASS %0s = %08x", name, got);
        end
    endtask

    initial begin
        repeat (10) @(posedge clk);
        rst = 0;
        repeat (5) @(posedge clk);

        $display("--- 寄存器通路 ---");
        do_read (32'h40, v);  chk("MAGIC",      v, 32'h50434946);
        do_read (32'h64, v);  chk("VERSION",    v, 32'h00010000);
        do_read (32'h50, v);  chk("WIDTH",      v, W);
        do_read (32'h54, v);  chk("HEIGHT",     v, H);
        do_read (32'h68, v);  chk("CLK_MHZ",    v, 125);
        do_write(32'h6C, 32'hA5A5_5A5A);
        do_read (32'h6C, v);  chk("SCRATCH",    v, 32'hA5A55A5A);
        do_read (32'h7C, v);  chk("未映射寄存器", v, 32'hDEADBEEF);

        $display("--- 出帧 ---");
        do_write(32'h44, 32'h1);                    // CTRL.enable
        v = 32'd0;
        for (i = 0; i < 300000; i = i + 1) begin
            do_read(32'h48, v);
            if (v[0] === 1'b1) i = 300001;
        end
        chk("STATUS.ready", v[0], 1'b1);

        do_read(32'h4C, fc0);
        $display("  INFO FRAME_CNT   = %0d", fc0);
        do_read(32'h58, v);  chk("DATA_LEN",   v, W*H);

        $display("--- 数据窗口 ---");
        // 帧号不再占缓存：它就是 0x4C FRAME_CNT（上面刚读的 fc0），
        // 缓存字 0.. 全是像素，字的顺序按公式 x+y+fc 对。
        do_write(32'h5C, 32'd0);                    // PTR = 0
        do_read (32'h60, w1);                       // 字 0 = 像素 (x=0..3, y=0)
        b0 = w1[7:0]; b1 = w1[15:8]; b2 = w1[23:16]; b3 = w1[31:24];
        if (!(b0 === fc0[7:0] && b1 === (fc0[7:0] + 8'd1) &&
              b2 === (fc0[7:0] + 8'd2) && b3 === (fc0[7:0] + 8'd3))) begin
            $display("  FAIL 字0 = %08x，期望字节 fc,fc+1,fc+2,fc+3（fc=%02x）", w1, fc0[7:0]);
            errors = errors + 1;
        end else
            $display("  PASS 字0 = %08x（字节递增且首字节=帧号 mod 256）", w1);

        // 字 1 = 像素 (x=4..7, y=0)：首字节 = fc+4
        do_read (32'h60, w2);                       // PTR 已自动 +4（=4）
        if (w2[7:0] !== (fc0[7:0] + 8'd4)) begin
            $display("  FAIL 字1 首字节 = %02x，期望 %02x", w2[7:0], fc0[7:0] + 8'd4);
            errors = errors + 1;
        end else
            $display("  PASS 字1 = %08x（指针自动 +4 生效）", w2);

        // 指针确实前进了 8
        do_read (32'h5C, v);  chk("PTR 自动递增", v, 32'd8);

        $display("--- 越界回绕 ---");
        do_write(32'h5C, PTR_MASK);
        do_read (32'h5C, v);  chk("PTR 末字",     v, PTR_MASK);
        do_read (32'h60, v);                        // 读末字
        do_read (32'h5C, v);  chk("PTR 回绕到 0", v, 32'd0);

        if (errors == 0) $display("\n===== 全部通过 =====");
        else             $display("\n===== 有 %0d 项失败 =====", errors);
        $finish;
    end

    initial begin
        #20000000;
        $display("TIMEOUT");
        $finish;
    end
endmodule
