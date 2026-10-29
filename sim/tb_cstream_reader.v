`timescale 1ns/1ps
// tb_cstream_reader.v — DDR 回读（突发 AR）+ packed RAW10 5→4 拆包
//
// 判据：输出字节序列等于「每 5 字节取前 4 字节」（分组跨 beat 连续），
// 最后一个 beat 的最后一个字节不能丢；突发长度 ≤ BURST，且不跨 4 KiB。
module tb_cstream_reader;
    localparam integer NB   = 160;             // beat 数（32B/beat）
    localparam integer LEN  = NB * 32;         // 5120 B，能被 5 整除
    localparam integer NOUT = (LEN / 5) * 4;   // 4096
    localparam [28:0] BASE = 29'h0000_1000;
    localparam integer BURST = 64;

    reg clk = 0, rst_n = 0, start = 0;
    wire [7:0] o_data;
    wire o_valid, o_ready, busy, o_done;
    wire [3:0] st_dbg;
    reg  o_ready_r = 1;
    wire [28:0] m_araddr;
    wire [7:0]  m_arlen;
    wire [2:0]  m_arsize;
    wire [1:0]  m_arburst;
    wire m_arvalid, m_arready;
    reg  [255:0] m_rdata = 0;
    reg  m_rvalid = 0, m_rlast = 0;
    wire m_rready;

    cstream_reader #(.BURST(BURST)) dut (
        .clk(clk), .rst_n(rst_n), .start(start), .base(BASE), .bytes(LEN),
        .o_data(o_data), .o_valid(o_valid), .o_ready(o_ready_r), .o_done(o_done),
        .busy(busy), .st_dbg(st_dbg),
        .m_araddr(m_araddr), .m_arlen(m_arlen), .m_arsize(m_arsize),
        .m_arburst(m_arburst), .m_arvalid(m_arvalid), .m_arready(m_arready),
        .m_rdata(m_rdata), .m_rresp(2'b00), .m_rlast(m_rlast),
        .m_rvalid(m_rvalid), .m_rready(m_rready));
    assign o_ready = o_ready_r;

    assign m_arready = 1'b1;

    always #5 clk = ~clk;

    reg [7:0] src [0:LEN-1];
    reg [7:0] got [0:NOUT+8];
    integer nout, i, j, errors, nburst, arn, rem, nidx;
    reg [7:0] expc [0:NOUT-1];

    // AXI 读从机：支持突发；rvalid 保持到 rready
    always @(posedge clk) begin
        if (m_arvalid && m_arready) begin
            if (m_arlen + 1 > BURST) begin
                $display("FAIL: 突发 %0d 拍超过 BURST=%0d", m_arlen + 1, BURST);
                errors = errors + 1;
            end
            if ((m_araddr[11:5] + m_arlen) >= 128) begin
                $display("FAIL: 突发跨 4KiB：addr=0x%08x len=%0d", m_araddr, m_arlen);
                errors = errors + 1;
            end
            nburst = m_arlen + 1;
            arn    = arn + 1;
            rem    = nburst;
            nidx   = (m_araddr - BASE) >> 5;
            for (j = 0; j < 32; j = j + 1) m_rdata[j*8 +: 8] <= src[nidx*32 + j];
            nidx   = nidx + 1;
            m_rvalid <= 1'b1;
            m_rlast  <= (nburst == 1);
        end else if (m_rvalid && m_rready) begin
            if (rem == 1) begin
                m_rvalid <= 1'b0;
                m_rlast  <= 1'b0;
            end else begin
                for (j = 0; j < 32; j = j + 1) m_rdata[j*8 +: 8] <= src[nidx*32 + j];
                nidx  = nidx + 1;
                rem   = rem - 1;
                m_rlast <= (rem == 2);
            end
        end
    end

    always @(posedge clk) begin
        if (o_valid && o_ready_r) begin
            got[nout] = o_data;
            nout = nout + 1;
        end
    end

    initial begin
        errors = 0; nout = 0; arn = 0; rem = 0; nidx = 0;
        for (i = 0; i < LEN; i = i + 1) src[i] = (i * 7 + 3) & 8'hFF;
        for (i = 0; i < NOUT; i = i + 1) expc[i] = src[(i/4)*5 + (i%4)];
        repeat (4) @(negedge clk); rst_n = 1; repeat (2) @(negedge clk);
        @(negedge clk); start = 1; @(negedge clk); start = 0;
        // 制造若干反压，验证 rready 能在 burst 中间停住
        fork
            begin
                repeat (2000) @(negedge clk);
                o_ready_r = 0; repeat (50) @(negedge clk); o_ready_r = 1;
                repeat (1000) @(negedge clk);
                o_ready_r = 0; repeat (20) @(negedge clk); o_ready_r = 1;
            end
        join_none
        repeat (NOUT * 3 + 600) @(negedge clk);
        $display("AR=%0d（BURST=%0d） 输出 %0d 字节（期望 %0d） busy=%0d done=%0d",
                 arn, BURST, nout, NOUT, busy, o_done);
        if (arn !== (NB + BURST - 1) / BURST) errors = errors + 1;
        if (nout !== NOUT) errors = errors + 1;
        for (i = 0; i < NOUT && i < nout; i = i + 1)
            if (got[i] !== expc[i]) begin
                $display("FAIL: 第 %0d 字节 0x%02x != 0x%02x", i, got[i], expc[i]);
                errors = errors + 1;
                if (errors > 5) i = NOUT;
            end
        if (errors == 0) $display("PASS: 突发 5→4 拆包、反压与帧尾字节都正确");
        else             $display("FAIL: %0d 处错误", errors);
        $finish;
    end
    initial #500000 $finish;
endmodule
