///////////////////////////////////////////////////////////////////////////////
//  tb_ddr_rd_arb.v — ddr_rd_arb（A/B 两路 AXI 读口仲裁）的定向测试（iverilog）
//
//  ★ 本台严守一条时序纪律：**握手组合信号必须在时钟沿之前查**（输入摆好→#1→查），
//    时钟沿之后查的是"下一拍的新状态"。上一版把 rlast / arready 这类组合握手放在
//    沿后查，得到的是"已经收走之后"的值，于是 8 处报错全是假错（DUT 行为正确）。
//
//  这个模块最容易错的三件事，逐条覆盖：
//    1) 读数据发错人：AR 受理后中途换手 ⇒ 从机的 rdata 泄给另一路（静默错帧，
//       板上表现为"图糊了/串了"，最难查）；
//    2) 锁定期还放 AR：两路 arid 都是 4'd0，一旦有多个未完成突发就无法按 ID 区分；
//    3) 放锁时机错：早放一拍（把 rlast 那拍丢了）或晚放一拍（下一突发被拒）。
//  用例：
//    A) 复位：lock=0，grant=0，只有 0 号能看到 arready，数据通道全 0；
//    B) 0 号 AR 握手 → 锁定；期间 1 号举 AR 也拿不到 arready、看不到 rvalid，
//       且从机口 m_arvalid 必须被关成 0；
//    C) 突发数据只回给 0 号（rdata/rresp/rlast 逐位比），1 号恒 0；
//    D) rlast 那拍必须仍然回给 0 号（不能早放锁），且 m_rready 取自 0 号；
//    E) 放锁后轮转：1 号在请求 ⇒ grant 让给 1 号，1 号的 AR 立刻被受理；
//    F) 1 号突发结束后如果 0 号在请求 ⇒ grant 转回 0 号（不会饿死某一方）；
//    G) 放锁后 m_rready 恒 0（不许在没锁定时接数据）。
//
//  运行：cd sim_do && iverilog -o /tmp/tb_rdarb tb_ddr_rd_arb.v \
//            ../rtl/ep_side/ddr/ddr_rd_arb.v && /tmp/tb_rdarb
///////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps

module tb_ddr_rd_arb;

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

    // ---- 客户机 0 / 1 ----
    reg  [28:0]  a0_araddr = 29'h0A00000;
    reg  [7:0]   a0_arlen  = 8'd127;
    reg          a0_arvalid= 1'b0;
    wire         a0_arready;
    wire [255:0] a0_rdata;
    wire [1:0]   a0_rresp;
    wire         a0_rlast, a0_rvalid;
    reg          a0_rready = 1'b0;

    reg  [28:0]  a1_araddr = 29'h1100000;
    reg  [7:0]   a1_arlen  = 8'd127;
    reg          a1_arvalid= 1'b0;
    wire         a1_arready;
    wire [255:0] a1_rdata;
    wire [1:0]   a1_rresp;
    wire         a1_rlast, a1_rvalid;
    reg          a1_rready = 1'b0;

    wire         grant_out;
    wire [28:0]  m_araddr;  wire [7:0] m_arlen;  wire m_arvalid, m_arready;
    wire [255:0] m_rdata;   wire [1:0] m_rresp;  wire m_rlast, m_rvalid, m_rready;

    ddr_rd_arb u_arb (
        .clk(clk), .rst(rst), .grant_out(grant_out),
        .a0_arid(4'd0), .a0_araddr(a0_araddr), .a0_arlen(a0_arlen),
        .a0_arsize(3'd5), .a0_arburst(2'b01), .a0_arvalid(a0_arvalid),
        .a0_arready(a0_arready), .a0_rid(), .a0_rdata(a0_rdata),
        .a0_rresp(a0_rresp), .a0_rlast(a0_rlast), .a0_rvalid(a0_rvalid),
        .a0_rready(a0_rready),
        .a1_arid(4'd0), .a1_araddr(a1_araddr), .a1_arlen(a1_arlen),
        .a1_arsize(3'd5), .a1_arburst(2'b01), .a1_arvalid(a1_arvalid),
        .a1_arready(a1_arready), .a1_rid(), .a1_rdata(a1_rdata),
        .a1_rresp(a1_rresp), .a1_rlast(a1_rlast), .a1_rvalid(a1_rvalid),
        .a1_rready(a1_rready),
        .m_arid(), .m_araddr(m_araddr), .m_arlen(m_arlen), .m_arsize(),
        .m_arburst(), .m_arvalid(m_arvalid), .m_arready(m_arready),
        .m_rid(4'd0), .m_rdata(m_rdata), .m_rresp(m_rresp), .m_rlast(m_rlast),
        .m_rvalid(m_rvalid), .m_rready(m_rready)
    );

    // 从机侧：arready 由测试给；rvalid/rdata/rresp/rlast 由测试给
    reg         m_arready_r = 1'b1;
    reg         m_rvalid_r  = 1'b0;
    reg [255:0] m_rdata_r   = 256'h0;
    reg [1:0]   m_rresp_r   = 2'b00;
    reg         m_rlast_r   = 1'b0;
    assign m_arready = m_arready_r;
    assign m_rvalid  = m_rvalid_r;
    assign m_rdata   = m_rdata_r;
    assign m_rresp   = m_rresp_r;
    assign m_rlast   = m_rlast_r;

    // 数据拍模型：给一拍数据（可选 rlast），返回时应被授权者收走
    task give_r; input last; input [255:0] d; begin
        m_rvalid_r = 1'b1; m_rlast_r = last; m_rdata_r = d; m_rresp_r = 2'b00;
    end endtask
    task no_r; begin
        m_rvalid_r = 1'b0; m_rlast_r = 1'b0;
    end endtask

    initial begin
        $display("=== tb_ddr_rd_arb ===");
        rst = 1'b1;
        repeat (4) @(posedge clk);
        rst = 1'b0;
        @(posedge clk); #1;

        // ---- A) 复位后：grant=0，只有 0 号能拿 arready，数据通道全 0 ----
        chk("A 复位后 grant=0", grant_out, 1'b0);
        chk("A m_rready 未锁定=0", m_rready, 1'b0);
        chk("A 0 号 arready 通",  a0_arready, 1'b1);
        chk("A 1 号 arready 关",  a1_arready, 1'b0);
        chk("A 0 号 rvalid=0",    a0_rvalid, 1'b0);
        chk("A 1 号 rvalid=0",    a1_rvalid, 1'b0);

        // ---- B) 0 号 AR 握手（沿前查通到从机口；沿后进入锁定）----
        a0_arvalid = 1'b1;
        #1;                                      // 握手那一拍，沿前查
        chk ("B m_arvalid 透传 0 号", m_arvalid, 1'b1);
        chkv("B m_araddr  = 0 号", {3'd0,m_araddr}, {3'd0,a0_araddr});
        chkv("B m_arlen   = 0 号", {24'd0,m_arlen}, 32'd127);
        @(posedge clk); #1;                      // 这一沿 AR 被受理 → 锁定
        a0_arvalid = 1'b0;                       // 客户机受理后撤 AR（pusher 进 A_R）
        a1_arvalid = 1'b1;                       // 1 号也想读
        #1;
        chk("B 锁定后 m_arvalid=0",  m_arvalid, 1'b0);   // ★ 不许放第二笔 AR
        chk("B 锁定后 1 号 arready=0", a1_arready, 1'b0);
        chk("B 锁定后 1 号 rvalid=0",  a1_rvalid, 1'b0);
        @(posedge clk); #1;
        chk("B 锁定期 grant 不换", grant_out, 1'b0);

        // ---- C) 突发数据只回给 0 号（沿前查）----
        a0_rready = 1'b1;
        give_r(1'b0, 256'hDEAD_BEEF_0000_1111_2222_3333_4444_5555_6666_7777_8888_9999_AAAA_BBBB_CCCC_1234);
        #1;
        chk ("C 0 号 rvalid=1",   a0_rvalid, 1'b1);
        chk ("C 1 号 rvalid=0",   a1_rvalid, 1'b0);
        chk ("C 0 号 rlast=0",    a0_rlast,  1'b0);
        chkv("C 0 号 rresp 透传", {30'd0,a0_rresp}, 32'd0);
        chk ("C 0 号 rdata 最高位", a0_rdata[255], 1'b1);
        chk ("C 0 号 rdata bit255", a0_rdata[255], 1'b1);
        chk ("C 0 号 rdata bit252", a0_rdata[252], 1'b1);
        chk ("C 1 号 rdata 被关住", a1_rdata, 256'h0);
        chk ("C m_rready 取自 0 号", m_rready, 1'b1);
        @(posedge clk); #1;

        // ---- D) rlast 那拍仍然回给 0 号（沿前查；沿后才放锁）----
        give_r(1'b1, 256'h1111_2222_3333_4444_5555_6666_7777_8888_9999_AAAA_BBBB_CCCC_DDDD_EEEE_5678);
        #1;
        chk("D rlast 仍回给 0 号", a0_rlast, 1'b1);
        chk("D 1 号仍为 0",        a1_rvalid, 1'b0);
        @(posedge clk); #1;                      // 这一沿收走末拍 → 放锁 + 轮转
        no_r;

        // ---- E) 放锁后轮转给在请求的 1 号（沿前查）----
        chk ("E grant 让给 1 号",     grant_out, 1'b1);
        chk ("E 1 号拿到 arready",    a1_arready, 1'b1);
        chk ("E 1 号 AR 通到从机口",  m_arvalid, 1'b1);
        chkv("E 从机口 = 1 号地址",   {3'd0,m_araddr}, {3'd0,a1_araddr});
        chk ("E 0 号 arready 关",     a0_arready, 1'b0);
        chk ("E 放锁后 m_rready=0",   m_rready, 1'b0);   // 用例 G 提前一起查
        @(posedge clk); #1;                      // 1 号 AR 被受理 → 再次锁定
        a1_arvalid = 1'b0;
        a1_rready  = 1'b1;
        chk("E 1 号锁定后 0 号 arready=0", a0_arready, 1'b0);
        give_r(1'b1, 256'hAAAA_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0001);
        #1;
        chk("E 1 号 rvalid=1", a1_rvalid, 1'b1);
        chk("E 0 号 rvalid=0", a0_rvalid, 1'b0);
        chk("E m_rready 取自 1 号", m_rready, 1'b1);
        chk("E 1 号 rdata 是 1 号的数据", a1_rdata[255:240], 16'hAAAA);
        @(posedge clk); #1;
        no_r;

        // ---- F) 0 号再请求 → 轮转回 0 号 ----
        a0_arvalid = 1'b1;
        #1;
        chk("F 换手前 grant 仍在 1 号", grant_out, 1'b1);
        @(posedge clk); #1;      // 授权者空闲 + 另一方请求 → 下一沿换手
        chk("F grant 转回 0 号", grant_out, 1'b0);
        chk("F 0 号 AR 立刻被受理", a0_arready, 1'b1);
        chk("F 1 号被关住",         a1_arready, 1'b0);
        a0_arvalid = 1'b0;

        repeat (2) @(posedge clk);
        if (errors == 0) $display("ALL PASS");
        else             $display("FAIL: %0d 处不对", errors);
        $finish;
    end

endmodule
