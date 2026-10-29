`timescale 1ns/1ps
// tb_cstream_writer.v — 压缩字节流写出器：长度、内容、补零边界
//
// 覆盖两件事：
//   1) 帧尾 s_eof 落在不 ready 的拍上时不能丢（锁存）；
//   2) 补零必须停在 FRAME_BYTES，不能按字节数多写一个 beat。
// 从机永远 ready（awready/wready=1），只记录写入的 beat 与地址。
module tb_cstream_writer;
    localparam integer N = 1000;          // 真实码流字节数
    localparam integer FB = 4096;         // 定长帧（32 的整数倍）
    localparam integer BEATS = FB / 32;

    reg clk = 0, rst_n = 0;
    reg [7:0] s_data = 0;
    reg s_valid = 0, s_eof = 0;
    wire s_ready;
    wire [31:0] wr_seq, wr_base, wr_len;
    wire wr_valid;
    wire [31:0] st_bytes, st_stream_len;
    wire [28:0] m_awaddr;
    wire [7:0]  m_awlen;
    wire [2:0]  m_awsize;
    wire [1:0]  m_awburst;
    wire m_awvalid;
    reg  m_awready = 1;
    wire [255:0] m_wdata;
    wire [31:0]  m_wstrb;
    wire m_wlast, m_wvalid;
    reg  m_wready = 1;
    reg  [1:0] m_bresp = 0;
    reg  m_bvalid = 0;
    wire m_bready;
    wire busy;

    cstream_writer #(.BASE(29'h0500_0000), .FRAME_BYTES(FB)) dut (
        .clk(clk), .rst_n(rst_n),
        .s_data(s_data), .s_valid(s_valid), .s_ready(s_ready),
        .s_eof(s_eof),
        .wr_seq(wr_seq), .wr_base(wr_base), .wr_len(wr_len), .wr_valid(wr_valid),
        .st_bytes(st_bytes), .st_stream_len(st_stream_len), .busy(busy),
        .m_awaddr(m_awaddr), .m_awlen(m_awlen), .m_awsize(m_awsize),
        .m_awburst(m_awburst), .m_awvalid(m_awvalid), .m_awready(m_awready),
        .m_wdata(m_wdata), .m_wstrb(m_wstrb), .m_wlast(m_wlast),
        .m_wvalid(m_wvalid), .m_wready(m_wready),
        .m_bresp(m_bresp), .m_bvalid(m_bvalid), .m_bready(m_bready));

    always #5 clk = ~clk;

    reg [7:0] src [0:N-1];
    reg [7:0] mem [0:FB-1];
    integer i, j, nbeat, nstream;
    integer errors;
    reg seen_wr_valid = 0;

    // 从机：接受所有写，按地址落进 mem，同时校验地址连续
    always @(posedge clk) begin
        if (wr_valid) seen_wr_valid <= 1;
        if (m_awvalid && m_awready) begin
            if (m_awaddr !== 29'h0500_0000 + nbeat*32) begin
                $display("FAIL: 第 %0d 拍地址 0x%08x", nbeat, m_awaddr);
                errors = errors + 1;
            end
        end
        if (m_wvalid && m_wready) begin
            for (j = 0; j < 32; j = j + 1)
                if (m_wstrb[j]) mem[nbeat*32 + j] = m_wdata[j*8 +: 8];
            nbeat = nbeat + 1;
        end
    end

    initial begin
        errors = 0; nbeat = 0; nstream = 0;
        for (i = 0; i < N; i = i + 1) src[i] = (i * 37 + 11) & 8'hFF;
        for (i = 0; i < FB; i = i + 1) mem[i] = 8'hEE;

        repeat (4) @(negedge clk); rst_n = 1; repeat (2) @(negedge clk);

        // 一帧：逐字节送（writer 以第一个字节开帧），中途让 valid 多等几拍制造空闲
        for (i = 0; i < N; i = i + 1) begin
            s_data = src[i]; s_valid = 1; s_eof = (i == N-1);
            while (!s_ready) @(negedge clk);
            @(negedge clk);                       // 这一拍 posedge 收下
            if (i % 97 == 0) begin
                s_valid = 0;                      // 制造空洞
                repeat (3) @(negedge clk);
            end
        end
        s_valid = 0; s_eof = 0;
        repeat (10) @(negedge clk);
        repeat (BEATS * 2) @(negedge clk);
        if (!seen_wr_valid) begin $display("FAIL: 没有 wr_valid"); errors = errors + 1; end

        $display("stream_len=%0d（期望 %0d） 写入拍数=%0d（期望 %0d） wr_seq=%0d",
                 st_stream_len, N, nbeat, BEATS, wr_seq);
        if (st_stream_len !== N) errors = errors + 1;
        if (nbeat !== BEATS) errors = errors + 1;
        if (wr_seq !== 1) errors = errors + 1;
        for (i = 0; i < N; i = i + 1)
            if (mem[i] !== src[i]) begin
                $display("FAIL: 码流第 %0d 字节 0x%02x != 0x%02x", i, mem[i], src[i]);
                errors = errors + 1;
                if (errors > 8) i = N;
            end
        for (i = N; i < FB; i = i + 1)
            if (mem[i] !== 8'h00) begin
                $display("FAIL: 补零区第 %0d 字节 0x%02x", i, mem[i]);
                errors = errors + 1;
                i = FB;
            end

        // ---- 第二帧：确认 st_stream_len 是**本帧**长度，不是累计值 ----
        nbeat = 0;
        for (i = 0; i < 777; i = i + 1) begin
            s_data = (i * 13 + 5) & 8'hFF;
            s_valid = 1; s_eof = (i == 776);
            while (!s_ready) @(negedge clk);
            @(negedge clk);
        end
        s_valid = 0; s_eof = 0;
        repeat (BEATS * 2) @(negedge clk);
        $display("第二帧 stream_len=%0d（期望 777） wr_seq=%0d（期望 2）",
                 st_stream_len, wr_seq);
        if (st_stream_len !== 777) errors = errors + 1;
        if (wr_seq !== 2)          errors = errors + 1;

        if (errors == 0) $display("PASS: 长度/内容/补零/地址/第二帧帧长全部正确");
        else             $display("FAIL: %0d 处错误", errors);
        $finish;
    end
    initial #500000 $finish;
endmodule