///////////////////////////////////////////////////////////////////////////////
//  tb_tl_tx_arb.v — tl_tx_arb（两路推帧引擎共用一套用户 TL 发送口）测试
//
//  这个模块最容易错的三件事：
//    1) TLP 期间换手：引擎按「一笔 TLP」借口，utx_sel=1 期间换手会把两个包拼在
//       一起（序列上表现为一个坏包，主机侧看到的是"偶发乱码"）；
//    2) 空档期不换手：被授权者一直不请求时另一路永远拿不到口 ⇒ 饿死；
//    3) 授权/数据不同源：a_sel=1 却把 b 的数据送出去。
//  用例：
//    A) 复位 grant=0；utx_sel=0 时 a_sel/b_sel 都为 0（不许抢口）；
//    B) utx_sel=1、grant=0 ⇒ a_sel=1、b_sel=0，且 m_* 完全等于 a 组；
//    C) utx_sel=1 期间 b_req 拉高**不许换手**（TLP 原子），m_* 仍是 a 组；
//    D) utx_sel=0 且 a_req=0、b_req=1 ⇒ 换手到 b；b_sel 要等引擎再给 utx_sel；
//    E) 轮转回 a（b 不请求、a 请求）；
//    F) 两路都请求时交替进行（不饿死）；
//    G) 授权与数据同源：m_data 必须等于当前被授权者的 data。
//
//  运行：cd sim_do && iverilog -o /tmp/tb_txarb tb_tl_tx_arb.v \
//            ../rtl/ep_side/ddr/tl_tx_arb.v && /tmp/tb_txarb
///////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps

module tb_tl_tx_arb;

    reg clk = 1'b0, rst = 1'b1;
    always #5 clk = ~clk;                 // 62.5MHz 量级，频率无关

    integer errors = 0;
    task chk24; input [255:0] name; input [23:0] got; input [23:0] exp;
        begin
            if (got !== exp) begin
                errors = errors + 1;
                $display("  FAIL %0s: got %06x exp %06x", name, got, exp);
            end
        end
    endtask
    task chk; input [255:0] name; input got; input exp;
        begin
            if (got !== exp) begin
                errors = errors + 1;
                $display("  FAIL %0s: got %b exp %b", name, got, exp);
            end
        end
    endtask

    reg          utx_sel = 1'b0;
    wire         grant_out;

    reg          a_req = 1'b0, b_req = 1'b0;
    reg [15:0]   a_tag = 16'hA000, b_tag = 16'hB000;   // 用明显不同的数据认源
    reg          a_sop = 1'b0, a_eop = 1'b0, b_sop = 1'b0, b_eop = 1'b0;
    reg [7:0]    a_valid = 8'h00, b_valid = 8'h00;
    wire         a_sel, b_sel;
    wire         m_req, m_sop, m_eop;
    wire [7:0]   m_valid;
    wire [255:0] m_data;

    // 数据线：整个 256bit 用 tag 填满，便于逐位比对
    wire [255:0] a_data = {a_tag, a_tag, a_tag, a_tag, a_tag, a_tag, a_tag, a_tag,
                           a_tag, a_tag, a_tag, a_tag, a_tag, a_tag, a_tag, a_tag};
    wire [255:0] b_data = {b_tag, b_tag, b_tag, b_tag, b_tag, b_tag, b_tag, b_tag,
                           b_tag, b_tag, b_tag, b_tag, b_tag, b_tag, b_tag, b_tag};

    tl_tx_arb u_arb (
        .clk(clk), .rst(rst), .utx_sel(utx_sel), .grant_out(grant_out),
        .a_req(a_req), .a_data(a_data), .a_sop(a_sop), .a_eop(a_eop),
        .a_valid(a_valid), .a_sel(a_sel),
        .b_req(b_req), .b_data(b_data), .b_sop(b_sop), .b_eop(b_eop),
        .b_valid(b_valid), .b_sel(b_sel),
        .m_req(m_req), .m_data(m_data), .m_sop(m_sop), .m_eop(m_eop),
        .m_valid(m_valid)
    );

    // 辅助：A 组发一笔 TLP（3 拍：头 + 2 个载荷），返回拍数
    integer a_beats, b_beats;
    task do_a_tlp;
        begin
            a_beats = 0;
            a_req = 1'b1; a_sop = 1'b1; a_valid = 8'hF0;
            @(posedge clk);   // 引擎给 utx_sel（本 TB 里由调用者给）
            a_beats = a_beats + 1;
            a_sop = 1'b0; a_valid = 8'hFF; a_eop = 1'b1;   // 单拍载荷收尾
            @(posedge clk);
            a_beats = a_beats + 1;
            a_req = 1'b0; a_eop = 1'b0; a_valid = 8'h00;   // S_TEND：空一拍
            @(posedge clk);
        end
    endtask

    initial begin
        $display("=== tb_tl_tx_arb ===");
        rst = 1'b1;
        repeat (4) @(posedge clk);
        rst = 1'b0;
        @(posedge clk); #1;

        // ---- A) 复位；utx_sel=0 时两组 sel 都为 0 ----
        chk("A 复位后 grant=0", grant_out, 1'b0);
        chk("A utx_sel=0 ⇒ a_sel=0", a_sel, 1'b0);
        chk("A utx_sel=0 ⇒ b_sel=0", b_sel, 1'b0);

        // ---- B) utx_sel=1、grant=0：a 组通到引擎，b 组被关住 ----
        a_req = 1'b1; a_sop = 1'b1; a_valid = 8'hF0;
        utx_sel = 1'b1;
        #1;
        chk("B a_sel=1", a_sel, 1'b1);
        chk("B b_sel=0", b_sel, 1'b0);
        chk("B m_req=a_req", m_req, 1'b1);
        chk("B m_data=a_data[255:240]", m_data[255:240], a_tag);
        chk("B m_data=a_data[15:0]",    m_data[15:0],    a_tag);
        chk24("B m_valid=a_valid",      m_valid, 8'hF0);
        chk("B m_sop=a_sop",            m_sop, 1'b1);

        // ---- C) TLP 期间 b_req 拉高：不许换手 ----
        b_req = 1'b1; b_sop = 1'b1; b_valid = 8'hF0; b_tag = 16'hB111;
        #1;
        chk("C utx_sel=1 期间 grant 不换", grant_out, 1'b0);
        chk("C a_sel 仍=1", a_sel, 1'b1);
        chk("C m_data 仍是 a 组", m_data[255:240], 16'hA000);
        chk24("C m_valid 仍是 a 组", m_valid, 8'hF0);

        // 引擎收走 eop 那拍 → 回 IDLE（本 TB 手工模拟：utx_sel 拉低）
        a_sop = 1'b0; a_eop = 1'b1; a_valid = 8'hFF;
        #1; chk("C 收尾拍 m_eop=a_eop", m_eop, 1'b1);
        utx_sel = 1'b0;
        a_req = 1'b0; a_eop = 1'b0; a_valid = 8'h00;   // a 空档（S_TEND）
        @(posedge clk); #1;

        // ---- D) 空档换手到 b ----
        chk("D grant 让给 b", grant_out, 1'b1);
        chk("D utx_sel=0 时 b_sel 仍为 0（等引擎给口）", b_sel, 1'b0);
        utx_sel = 1'b1; #1;
        chk("D b_sel=1", b_sel, 1'b1);
        chk("D a_sel=0", a_sel, 1'b0);
        chk("D m_data=b 组", m_data[255:240], 16'hB111);
        chk24("D m_valid=b 组", m_valid, 8'hF0);
        chk("D m_req=b_req", m_req, 1'b1);

        // b 发完一笔，空档
        b_sop = 1'b0; b_eop = 1'b1; b_valid = 8'hFF;
        #1; chk("D m_eop=b 收尾", m_eop, 1'b1);
        utx_sel = 1'b0; b_req = 1'b0; b_eop = 1'b0; b_valid = 8'h00;
        @(posedge clk); #1;

        // ---- E) 只有 a 请求 ⇒ 轮转回 a ----
        a_req = 1'b1; a_valid = 8'hF0; a_sop = 1'b1;
        @(posedge clk); #1;
        chk("E grant 转回 a", grant_out, 1'b0);
        utx_sel = 1'b1; #1;
        chk("E a_sel=1", a_sel, 1'b1);
        chk("E b_sel=0", b_sel, 1'b0);
        utx_sel = 1'b0; a_req = 1'b0; a_sop = 1'b0; a_valid = 8'h00;
        @(posedge clk); #1;

        // ---- F) 两路都请求：交替进行（各拿一次，不饿死）----
        a_req = 1'b1; a_valid = 8'hF0;
        b_req = 1'b1; b_valid = 8'hF0;
        @(posedge clk); #1;
        // 上一步放锁时 a 在请求 ⇒ 优先给 a
        chk("F 第一轮给 a", grant_out, 1'b0);
        a_req = 1'b0;                       // a 发完（空档）
        @(posedge clk); #1;
        chk("F 第二轮给 b", grant_out, 1'b1);
        b_req = 1'b0;
        a_req = 1'b1;
        @(posedge clk); #1;
        chk("F 第三轮又给 a", grant_out, 1'b0);
        a_req = 1'b0;

        // ---- G) 授权与数据同源（换手那一拍不许串源）----
        a_tag = 16'hA222; b_tag = 16'hB222;
        b_req = 1'b1;
        @(posedge clk); #1;
        chk("G grant=b", grant_out, 1'b1);
        chk("G m_data = b 组数据", m_data[255:240], 16'hB222);
        a_req = 1'b1;                        // a 同时请求，也不许串
        #1;
        chk("G m_data 仍是 b 组", m_data[255:240], 16'hB222);

        repeat (2) @(posedge clk);
        if (errors == 0) $display("ALL PASS");
        else             $display("FAIL: %0d 处不对", errors);
        $finish;
    end

endmodule
