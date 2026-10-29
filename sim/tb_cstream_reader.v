`timescale 1ns/1ps
// tb_cstream_reader.v — DDR 回读 + packed RAW10 5→4 拆包
//
// 判据：输出字节序列等于「每 5 字节取前 4 字节」（分组跨 beat 连续），
// 且最后一个 beat 的最后一个字节不能被丢掉（S_IDLE 清 o_valid 的老 bug）。
module tb_cstream_reader;
    localparam integer NB   = 40;              // beat 数
    localparam integer LEN  = NB * 32;         // 读入字节数
    localparam integer NOUT = (LEN / 5) * 4;   // 每 5 字节出 4 字节

    reg clk = 0, rst_n = 0, start = 0;
    reg [28:0] base = 29'h0000_1000;
    wire [7:0] o_data;
    wire o_valid, o_ready, busy;
    wire [3:0] st_dbg;
    reg  o_ready_r = 1;
    wire [28:0] m_araddr;
    wire [7:0]  m_arlen;
    wire [2:0]  m_arsize;
    wire [1:0]  m_arburst;
    wire m_arvalid;
    wire m_arready;
    reg  [255:0] m_rdata = 0;
    reg  m_rvalid = 0;
    wire m_rready;

    cstream_reader dut (
        .clk(clk), .rst_n(rst_n), .start(start), .base(base), .bytes(LEN),
        .o_data(o_data), .o_valid(o_valid), .o_ready(o_ready_r),
        .busy(busy), .st_dbg(st_dbg),
        .m_araddr(m_araddr), .m_arlen(m_arlen), .m_arsize(m_arsize),
        .m_arburst(m_arburst), .m_arvalid(m_arvalid), .m_arready(m_arready),
        .m_rdata(m_rdata), .m_rresp(2'b00), .m_rlast(1'b0),
        .m_rvalid(m_rvalid), .m_rready(m_rready));

    assign m_arready = 1'b1;
    assign m_rready  = 1'b1;

    always #5 clk = ~clk;

    reg [7:0] src [0:LEN-1];
    reg [7:0] got [0:NOUT+8];
    integer nout, beatn, arn, i, errors;
    reg [7:0] expc [0:NOUT-1];

    // AXI 读从机：每收到一个 AR 就给一拍 32B
    always @(posedge clk) begin
        if (m_arvalid && m_arready) begin
            for (i = 0; i < 32; i = i + 1) m_rdata[i*8 +: 8] <= src[beatn*32 + i];
            beatn  <= beatn + 1;
            m_rvalid <= 1'b1;
            arn    <= arn + 1;
        end else if (m_rvalid && m_rready) begin
            m_rvalid <= 1'b0;
        end
    end

    always @(posedge clk) begin
        if (o_valid && o_ready_r) begin
            got[nout] = o_data;
            nout = nout + 1;
        end
    end

    initial begin
        errors = 0; nout = 0; beatn = 0; arn = 0;
        for (i = 0; i < LEN; i = i + 1) src[i] = (i * 7 + 3) & 8'hFF;
        for (i = 0; i < NOUT; i = i + 1) expc[i] = src[(i/4)*5 + (i%4)];
        repeat (4) @(negedge clk); rst_n = 1; repeat (2) @(negedge clk);
        @(negedge clk); start = 1; @(negedge clk); start = 0;
        repeat (NOUT * 4 + 200) @(negedge clk);
        $display("AR=%0d（期望 %0d） 输出 %0d 字节（期望 %0d） busy=%0d",
                 arn, NB, nout, NOUT, busy);
        if (arn !== NB)   errors = errors + 1;
        if (nout !== NOUT) errors = errors + 1;
        for (i = 0; i < NOUT && i < nout; i = i + 1)
            if (got[i] !== expc[i]) begin
                $display("FAIL: 第 %0d 字节 0x%02x != 0x%02x", i, got[i], expc[i]);
                errors = errors + 1;
                if (errors > 5) i = NOUT;
            end
        if (errors == 0) $display("PASS: 5→4 拆包与帧尾字节都正确");
        else             $display("FAIL: %0d 处错误", errors);
        $finish;
    end
    initial #500000 $finish;
endmodule
