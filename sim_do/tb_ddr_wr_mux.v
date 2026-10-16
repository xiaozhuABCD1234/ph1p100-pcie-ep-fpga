///////////////////////////////////////////////////////////////////////////////
//  tb_ddr_wr_mux.v — ddr_wr_mux 的定向测试（iverilog）
//
//  为什么单独测：这个模块是**纯组合路由 + 一个换手寄存器**，没有自己的状态机，
//  所以最容易出的错不是逻辑漏拍、而是**通道方向/接反**（实测就踩过：B 通道把
//  bvalid 写成 input、bready 写成 output —— 顶层照样 elaborate 通过、仿真不覆盖
//  就一路漏到板子上）。所以这里逐条查：
//
//   1) 未被选中的客户机必须看到 awready=0 / wready=0 / bvalid=0（它的状态机才能
//      老实停在原地），且它的请求不能串到从机口上；
//   2) 被选中的客户机的 AW/W/B 都要一路通到从机口（地址/长度/数据/strb/last 逐位比）；
//   3) 从机的 bvalid/bresp 只能给被选中的那个客户机，bready 只能从被选中的那个拿；
//   4) 换手只在 busy0=busy1=0 时发生 —— busy 边沿上改 sel_req，sel_out 必须稳住。
//
//  运行：cd sim_do && iverilog -o /tmp/tb_mux tb_ddr_wr_mux.v \
//            ../rtl/ep_side/ddr/ddr_wr_mux.v && /tmp/tb_mux
///////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps

module tb_ddr_wr_mux;

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

    // ---- 客户机 0（fb[] → DDR3）----
    reg  [28:0]  a0_awaddr = 29'd0;
    reg  [7:0]   a0_awlen  = 8'd0;
    reg  [2:0]   a0_awsize = 3'd5;
    reg  [1:0]   a0_awburst= 2'b01;
    reg          a0_awvalid= 1'b0;
    wire         a0_awready;
    reg  [255:0] a0_wdata  = 256'd0;
    reg  [31:0]  a0_wstrb  = 32'd0;
    reg          a0_wlast  = 1'b0;
    reg          a0_wvalid = 1'b0;
    wire         a0_wready;
    wire [1:0]   a0_bresp;
    wire         a0_bvalid;
    reg          a0_bready = 1'b0;

    // ---- 客户机 1（CSI-2 → DDR3）----
    reg  [28:0]  a1_awaddr = 29'd0;
    reg  [7:0]   a1_awlen  = 8'd0;
    reg  [2:0]   a1_awsize = 3'd5;
    reg  [1:0]   a1_awburst= 2'b01;
    reg          a1_awvalid= 1'b0;
    wire         a1_awready;
    reg  [255:0] a1_wdata  = 256'd0;
    reg  [31:0]  a1_wstrb  = 32'd0;
    reg          a1_wlast  = 1'b0;
    reg          a1_wvalid = 1'b0;
    wire         a1_wready;
    wire [1:0]   a1_bresp;
    wire         a1_bvalid;
    reg          a1_bready = 1'b0;

    // ---- 从机（u_ddr3_mc_0 的写口）----
    wire [28:0]  m_awaddr;
    wire [7:0]   m_awlen;
    wire [2:0]   m_awsize;
    wire [1:0]   m_awburst;
    wire         m_awvalid;
    reg          m_awready = 1'b1;        // 从机永远收 AW（简化）
    wire [255:0] m_wdata;
    wire [31:0]  m_wstrb;
    wire         m_wlast;
    wire         m_wvalid;
    reg          m_wready  = 1'b1;
    reg  [1:0]   m_bresp   = 2'b00;
    reg          m_bvalid  = 1'b0;
    wire         m_bready;

    reg  sel_req = 1'b0;
    reg  busy0 = 1'b0, busy1 = 1'b0;
    wire sel_out;

    ddr_wr_mux u_dut (
        .clk(clk), .rst(rst), .sel_req(sel_req), .busy0(busy0), .busy1(busy1),
        .sel_out(sel_out),
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

    initial begin
        $display("--- tb_ddr_wr_mux: AXI 写通道二选一 ---");

        repeat (4) @(posedge clk);
        rst = 1'b0;
        @(posedge clk);

        // ================= 阶段 A：sel_req=0，0 号客户机在跑 =================
        sel_req = 1'b0; busy0 = 1'b1; busy1 = 1'b0;
        a0_awaddr = 29'h0010_0000; a0_awlen = 8'd3; a0_awvalid = 1'b1;
        a1_awaddr = 29'h0090_0000; a1_awlen = 8'd7; a1_awvalid = 1'b1;  // 1 号也在敲
        @(posedge clk); #1;
        chk("A sel_out=0",              sel_out,    1'b0);
        chkv("A 从机看到 0 号地址",      {3'd0,m_awaddr}, 32'h0010_0000);
        chk("A 从机 awvalid=0 号的",     m_awvalid,  1'b1);
        chkv("A 从机 awlen=0 号的",      {24'd0,m_awlen}, 32'd3);
        chk("A 0 号拿到 awready",        a0_awready, 1'b1);
        chk("A 1 号拿不到 awready",      a1_awready, 1'b0);

        // 数据拍：0 号推两拍（第二拍 wlast），1 号也在推（不能被串出去）
        a0_awvalid = 1'b0; a1_awvalid = 1'b0;
        a0_wdata = 256'hAAAA_0001; a0_wstrb = 32'hFFFF_FFFF; a0_wvalid = 1'b1;
        a1_wdata = 256'hBBBB_0002; a1_wstrb = 32'h0F0F_0F0F; a1_wvalid = 1'b1;
        @(posedge clk); #1;
        chkv("A 从机 wdata 来自 0 号",   m_wdata[31:0], 32'hAAAA_0001);
        chkv("A 从机 wstrb 来自 0 号",   m_wstrb,       32'hFFFF_FFFF);
        chk ("A 0 号拿到 wready",        a0_wready,     1'b1);
        chk ("A 1 号拿不到 wready",      a1_wready,     1'b0);
        // 最后一拍：wlast 也要通
        a0_wdata = 256'hAAAA_0003; a0_wlast = 1'b1; a1_wlast = 1'b0;
        @(posedge clk); #1;
        chkv("A 从机 wdata 末拍",        m_wdata[31:0], 32'hAAAA_0003);
        chk ("A 从机 wlast 来自 0 号",   m_wlast,       1'b1);
        a0_wvalid = 1'b0; a0_wlast = 1'b0; a1_wvalid = 1'b0;

        // 写响应：从机只回 0 号，且 bready 只从 0 号取
        m_bvalid = 1'b1; m_bresp = 2'b00;
        a0_bready = 1'b1; a1_bready = 1'b1;      // 两边都准备好了
        @(posedge clk); #1;
        chk("A 0 号收到 bvalid",         a0_bvalid, 1'b1);
        chk("A 1 号收不到 bvalid",       a1_bvalid, 1'b0);
        chk("A 从机 bready=1",           m_bready,  1'b1);
        chkv("A 0 号 bresp 通",          {30'd0,a0_bresp}, 32'd0);
        m_bvalid = 1'b0;

        // ================= 阶段 B：换手必须给 busy 让路 =================
        // 0 号还有突发在飞（busy0=1），此时改 sel_req，sel_out 不许动
        sel_req = 1'b1;
        repeat (3) @(posedge clk);
        chk("B busy0=1 时 sel_out 稳住 0", sel_out, 1'b0);
        busy0 = 1'b0; busy1 = 1'b0;
        @(posedge clk); #1;
        chk("B 两边空闲后换手到 1",        sel_out, 1'b1);

        // ================= 阶段 C：换手后只有 1 号能通 =================
        a0_awaddr = 29'h0010_1000; a0_awvalid = 1'b1;
        a1_awaddr = 29'h0090_1000; a1_awvalid = 1'b1;
        @(posedge clk); #1;
        chkv("C 从机看到 1 号地址",      {3'd0,m_awaddr}, 32'h0090_1000);
        chk("C 0 号拿不到 awready",      a0_awready, 1'b0);
        chk("C 1 号拿到 awready",        a1_awready, 1'b1);
        a0_awvalid = 1'b0; a1_awvalid = 1'b0;
        a0_wdata = 256'hCCCC_0004; a0_wvalid = 1'b1;
        a1_wdata = 256'hDDDD_0005; a1_wvalid = 1'b1;
        @(posedge clk); #1;
        chkv("C 从机 wdata 来自 1 号",   m_wdata[31:0], 32'hDDDD_0005);
        chk("C 0 号拿不到 wready",       a0_wready,     1'b0);
        chk("C 1 号拿到 wready",         a1_wready,     1'b1);
        a0_wvalid = 1'b0; a1_wvalid = 1'b0;
        // 从机回写响应：只该给 1 号
        m_bvalid = 1'b1; m_bresp = 2'b10;        // SLVERR，验证 bresp 也走对路
        a0_bready = 1'b0; a1_bready = 1'b1;
        @(posedge clk); #1;
        chk("C 0 号收不到 bvalid",       a0_bvalid, 1'b0);
        chk("C 1 号收到 bvalid",         a1_bvalid, 1'b1);
        chkv("C 1 号 bresp 通",          {30'd0,a1_bresp}, 32'd2);
        chk("C 从机 bready=1（取自 1 号）", m_bready, 1'b1);
        // 0 号的 bready=1、1 号的 =0 时，从机口上必须是 0（不能从没被选中的那边取）
        m_bvalid = 1'b0;
        a0_bready = 1'b1; a1_bready = 1'b0;
        @(posedge clk); #1;
        chk("C 从机 bready 不取 0 号",   m_bready, 1'b0);

        // ================= 阶段 D：换回 0 号 =================
        sel_req = 1'b0;
        @(posedge clk); #1;
        chk("D 换回 0 号",               sel_out, 1'b0);
        a1_bready = 1'b1;
        chk("D 从机 bready 又取自 0 号",  m_bready, 1'b1);

        repeat (4) @(posedge clk);
        if (errors == 0) $display("ALL PASS（ddr_wr_mux：通道方向/换手保护/bresp 路由）");
        else             $display("===== 有 %0d 项失败 =====", errors);
        $finish;
    end

endmodule
