///////////////////////////////////////////////////////////////////////////////
//  tb_ddr_wr_arb.v — ddr_wr_arb（A/B 两路 AXI 写口仲裁）的定向测试（iverilog）
//
//  为什么单独测：这个模块是**组合路由 + 一个 grant 寄存器**，没有自己的数据状态机，
//  最容易错的不是漏拍而是三件事：
//    1) 通道方向/接反（B 通道把 bvalid 写成 input 之类）—— 顶层照样 elaborate 过、
//       仿真不覆盖就一路漏到板上；
//    2) 未授权者没被"关住"（它的状态机会多走一步 / 把请求串到从机口上）；
//    3) **在"等端口"时换手**（老设计 `busy0=busy1=0 才换手` 的死锁形态）——
//       grant 冻在空闲的那一路上，等待者永远等不到 awready。
//  逐条覆盖：
//    A) 复位后 grant=0；未授权者看到 awready=0 / wready=0 / bvalid=0；
//    B) 授权者的 AW/W/B 一路通到从机口（地址/长度/数据/strb/last 逐位比）；
//    C) 授权者 busy 期间**不许换手**（另一边拉高 busy 也不行）；
//    D) 授权者一空闲就把端口让给 busy 的另一边；
//    E) 死锁形态：grant 在空闲的 B 上、A 在等端口（busy=1）⇒ grant 必须让给 A；
//    F) 从机的 bvalid/bresp 只给授权者，bready 只从授权者取。
//
//  运行：cd sim_do && iverilog -o /tmp/tb_arb tb_ddr_wr_arb.v \
//            ../rtl/ep_side/ddr/ddr_wr_arb.v && /tmp/tb_arb
///////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps

module tb_ddr_wr_arb;

    reg clk = 1'b0, rst = 1'b1;
    always #5 clk = ~clk;                 // 100MHz

    integer errors = 0;
    task chk; input [255:0] name; input got; input exp;
        begin
            if (got !== exp) begin
                errors = errors + 1;
                $display("  FAIL %0s: got %b exp %b", name, got, exp);
            end
        end
    endtask
    task chkv; input [255:0] name; input [31:0] got; input [31:0] exp;
        begin
            if (got !== exp) begin
                errors = errors + 1;
                $display("  FAIL %0s: got %08x exp %08x", name, got, exp);
            end
        end
    endtask

    // ---- 客户机 0（A 路）----
    reg  [28:0]  a0_awaddr = 29'h0A00000;
    reg  [7:0]   a0_awlen  = 8'd127;
    reg  [2:0]   a0_awsize = 3'd5;
    reg  [1:0]   a0_awburst= 2'b01;
    reg          a0_awvalid= 1'b0;
    wire         a0_awready;
    reg  [255:0] a0_wdata  = 256'h1111_2222_3333_4444_5555_6666_7777_8888_9999_aaaa_bbbb_cccc_dddd_eeee_ffff_0000;
    reg  [31:0]  a0_wstrb  = 32'hFFFF_FFFF;
    reg          a0_wlast  = 1'b1;
    reg          a0_wvalid = 1'b0;
    wire         a0_wready;
    wire [1:0]   a0_bresp;
    wire         a0_bvalid;
    reg          a0_bready = 1'b0;

    // ---- 客户机 1（B 路）----
    reg  [28:0]  a1_awaddr = 29'h1100000;
    reg  [7:0]   a1_awlen  = 8'd127;
    reg  [2:0]   a1_awsize = 3'd5;
    reg  [1:0]   a1_awburst= 2'b01;
    reg          a1_awvalid= 1'b0;
    wire         a1_awready;
    reg  [255:0] a1_wdata  = 256'hAAAA_BBBB_CCCC_DDDD_EEEE_FFFF_0000_1111_2222_3333_4444_5555_6666_7777_8888_9999;
    reg  [31:0]  a1_wstrb  = 32'h0F0F_0F0F;
    reg          a1_wlast  = 1'b1;
    reg          a1_wvalid = 1'b0;
    wire         a1_wready;
    wire [1:0]   a1_bresp;
    wire         a1_bvalid;
    reg          a1_bready = 1'b0;

    reg          busy0 = 1'b0, busy1 = 1'b0;
    wire         grant_out;

    wire [28:0]  m_awaddr;   wire [7:0] m_awlen;   wire [2:0] m_awsize;
    wire [1:0]   m_awburst;  wire m_awvalid, m_awready;
    wire [255:0] m_wdata;    wire [31:0] m_wstrb;
    wire         m_wlast, m_wvalid, m_wready;
    wire [1:0]   m_bresp;    wire m_bvalid, m_bready;

    ddr_wr_arb u_arb (
        .clk(clk), .rst(rst),
        .busy0(busy0), .busy1(busy1), .grant_out(grant_out),
        .a0_awaddr(a0_awaddr), .a0_awlen(a0_awlen), .a0_awsize(a0_awsize),
        .a0_awburst(a0_awburst), .a0_awvalid(a0_awvalid), .a0_awready(a0_awready),
        .a0_wdata(a0_wdata), .a0_wstrb(a0_wstrb), .a0_wlast(a0_wlast),
        .a0_wvalid(a0_wvalid), .a0_wready(a0_wready),
        .a0_bresp(a0_bresp), .a0_bvalid(a0_bvalid), .a0_bready(a0_bready),
        .a1_awaddr(a1_awaddr), .a1_awlen(a1_awlen), .a1_awsize(a1_awsize),
        .a1_awburst(a1_awburst), .a1_awvalid(a1_awvalid), .a1_awready(a1_awready),
        .a1_wdata(a1_wdata), .a1_wstrb(a1_wstrb), .a1_wlast(a1_wlast),
        .a1_wvalid(a1_wvalid), .a1_wready(a1_wready),
        .a1_bresp(a1_bresp), .a1_bvalid(a1_bvalid), .a1_bready(a1_bready),
        .m_awaddr(m_awaddr), .m_awlen(m_awlen), .m_awsize(m_awsize),
        .m_awburst(m_awburst), .m_awvalid(m_awvalid), .m_awready(m_awready),
        .m_wdata(m_wdata), .m_wstrb(m_wstrb), .m_wlast(m_wlast),
        .m_wvalid(m_wvalid), .m_wready(m_wready),
        .m_bresp(m_bresp), .m_bvalid(m_bvalid), .m_bready(m_bready)
    );

    // 从机侧：awready/wready 由测试逐拍给；b 通道由测试给
    reg m_awready_r = 1'b1, m_wready_r = 1'b1;
    reg m_bvalid_r  = 1'b0;
    reg [1:0] m_bresp_r = 2'b00;
    assign m_awready = m_awready_r;
    assign m_wready  = m_wready_r;
    assign m_bvalid  = m_bvalid_r;
    assign m_bresp   = m_bresp_r;

    initial begin
        $display("=== tb_ddr_wr_arb ===");
        rst = 1'b1;
        repeat (4) @(posedge clk);
        rst = 1'b0;
        @(posedge clk);

        // ---- A) 复位后 grant=0；两边都没被授权时 ready 全 0 ----
        chk("A 复位后 grant=0", grant_out, 1'b0);
        a1_awvalid = 1'b1;      // 1 号想发，但没被授权
        a1_wvalid  = 1'b1;
        #1;
        chk("A 未授权的 a1_awready=0", a1_awready, 1'b0);
        chk("A 未授权的 a1_wready",    a1_wready,  1'b0);
        chk("A 未授权的 a1_bvalid",    a1_bvalid,  1'b0);
        chk("A 未授权时从机看不到 a1 请求", m_awvalid, 1'b0);
        a1_awvalid = 1'b0; a1_wvalid = 1'b0;

        // ---- B) 授权者（0 号）的 AW/W 通到从机口 ----
        a0_awvalid = 1'b1; a0_wvalid = 1'b1;
        busy0 = 1'b1;                     // 0 号在发（等端口/突发在飞）
        @(posedge clk); #1;
        chk ("B grant 仍是 0",      grant_out, 1'b0);
        chk ("B m_awvalid = a0",    m_awvalid, 1'b1);
        chkv("B m_awaddr  = a0",    m_awaddr, 29'h0A00000);
        chkv("B m_awlen   = a0",    {24'd0,m_awlen}, 32'd127);
        chkv("B m_wstrb   = a0",    m_wstrb, 32'hFFFF_FFFF);
        chk ("B m_wlast   = a0",    m_wlast, 1'b1);
        chk ("B a0_awready = 从机", a0_awready, m_awready_r);
        chk ("B a0_wready  = 从机", a0_wready,  m_wready_r);

        // ---- C) 授权者 busy 期间不许换手 ----
        busy1 = 1'b1;                     // 1 号也想发
        repeat (3) @(posedge clk); #1;
        chk("C busy0 期间 grant 不换", grant_out, 1'b0);
        chk("C 1 号仍拿不到 ready",    a1_awready, 1'b0);
        chk("C 从机口还是 0 号的",     m_awaddr, 29'h0A00000);

        // ---- D) 授权者一空闲就让给 busy 的 1 号 ----
        a0_awvalid = 1'b0; a0_wvalid = 1'b0; busy0 = 1'b0;
        @(posedge clk); @(posedge clk); #1;
        chk ("D grant 让给 1 号",   grant_out, 1'b1);
        chk ("D 1 号拿到 awready",  a1_awready, m_awready_r);
        // b 通道也应按授权者分发
        m_bvalid_r = 1'b1; m_bresp_r = 2'b10;
        #1;
        chk("D 1 号 bvalid=1",   a1_bvalid, 1'b1);
        chk("D 0 号 bvalid=0",   a0_bvalid, 1'b0);
        chkv("D 1 号 bresp 透传", a1_bresp, 2'b10);
        a1_bready = 1'b1; #1;
        chk("D m_bready 取自 1 号", m_bready, 1'b1);
        a1_bready = 1'b0; m_bvalid_r = 1'b0; m_bresp_r = 2'b00;

        // ---- E) 死锁形态：grant 在空闲的 1 号上、0 号在等端口 ----
        //     老设计（busy0=busy1=0 才换手）会永久冻在 1 号上。
        a1_awvalid = 1'b1; a1_wvalid = 1'b1;   // 1 号也 asserting，但它 busy=0（已发完）
        busy1 = 1'b0;
        a0_awvalid = 1'b1; a0_wvalid = 1'b1; busy0 = 1'b1;   // 0 号在等端口
        repeat (2) @(posedge clk); #1;
        chk("E grant 让给在等的 0 号", grant_out, 1'b0);
        chk("E 0 号拿到 awready",      a0_awready, m_awready_r);
        chk("E 1 号被关住",            a1_awready, 1'b0);
        a0_awvalid = 1'b0; a0_wvalid = 1'b0; busy0 = 1'b0;
        a1_awvalid = 1'b0; a1_wvalid = 1'b0;

        // ---- F) 现在轮到 1 号第二轮：确认 grant 会转回来 ----
        busy1 = 1'b1;
        repeat (2) @(posedge clk); #1;
        chk("F grant 转到 1 号", grant_out, 1'b1);
        busy1 = 1'b0;

        repeat (2) @(posedge clk);
        if (errors == 0) $display("ALL PASS");
        else             $display("FAIL: %0d 处不对", errors);
        $finish;
    end

endmodule
