// cstream_reader.v — 从 DDR 读回已发布的灰度帧，输出 RLE 需要的字节流
//
// 为什么回读：4K 实时流 62.7 MB/s 喂不动任何慢速压缩链（ROI 适配器 FIFO 只有 4 行）。
// 改成读 DDR 里已经落好的整帧，压缩器可以按自己的节奏跑，慢一点只是压缩帧率低。
//
// R10F 载荷是 packed RAW10（4 采样 5 字节），灰度值就在前 4 个字节里（第 5 字节是
// 各采样的低 2 位），所以这里做 5→4 拆包，直接把采样高 8 位吐给 RLE。
module cstream_reader (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,          // 单拍：开始读一帧
    input  wire [28:0] base,
    input  wire [31:0] bytes,          // 要读的载荷字节数（2,611,200）
    output reg  [7:0]  o_data,
    output reg         o_valid,
    input  wire        o_ready,
    output reg         o_last,         // 最后一个字节
    output wire        busy,
    output wire [3:0]  st_dbg,
    // AXI 读
    output reg  [28:0] m_araddr,
    output reg  [7:0]  m_arlen,
    output reg  [2:0]  m_arsize,
    output reg  [1:0]  m_arburst,
    output reg         m_arvalid,
    input  wire        m_arready,
    input  wire [255:0] m_rdata,
    input  wire [1:0]  m_rresp,
    input  wire        m_rlast,
    input  wire        m_rvalid,
    input  wire        m_rready
);
    localparam S_IDLE = 2'd0, S_AR = 2'd1, S_RD = 2'd2, S_OUT = 2'd3;
    reg [1:0]  st;
    reg [31:0] left;          // 还要接收的 beat 数（32B/beat）
    reg [28:0] addr;
    reg [255:0] beat;
    reg [5:0]  bi;            // beat 内字节下标
    reg [2:0]  ggrp;          // 0..4：5 字节里第几个
    reg        lastbeat;
    reg [31:0] total;

    assign busy     = (st != S_IDLE);
    assign st_dbg   = {2'b00, st};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= S_IDLE; left <= 0; addr <= 0; beat <= 0; bi <= 0; ggrp <= 0;
            o_data <= 0; o_valid <= 0; o_last <= 0; lastbeat <= 0; total <= 0;
            m_araddr <= 0; m_arlen <= 0; m_arsize <= 3'b101; m_arburst <= 2'b01; m_arvalid <= 0;
        end else begin
            case (st)
            S_IDLE: begin
                o_valid <= 1'b0; o_last <= 1'b0;
                if (start) begin
                    addr  <= base;
                    left  <= (bytes + 31) >> 5;
                    total <= bytes;
                    bi <= 0; ggrp <= 0;
                    st <= S_AR;
                end
            end
            S_AR: begin
                m_araddr  <= addr;
                m_arlen   <= 8'd0;
                m_arsize  <= 3'b101;
                m_arburst <= 2'b01;
                m_arvalid <= 1'b1;
                if (m_arvalid && m_arready) begin
                    m_arvalid <= 1'b0;
                    addr      <= addr + 29'd32;
                    st        <= S_RD;
                end
            end
            S_RD: begin
                if (m_rvalid && m_rready) begin
                    beat <= m_rdata;
                    bi   <= 6'd0;              // ggrp 跨 beat 保留：32 不是 5 的倍数
                    left <= left - 32'd1;
                    lastbeat <= (left == 32'd1);
                    st   <= S_OUT;
                end
            end
            S_OUT: begin
                // 5 字节里取前 4 个（第 5 个是低 2 位）
                if (o_valid && o_ready) o_valid <= 1'b0;
                if (!o_valid) begin
                    if (ggrp == 3'd4) begin
                        ggrp <= 0;
                        bi <= bi + 1'b1;
                    end else begin
                        o_data  <= beat[bi*8 +: 8];
                        o_valid <= 1'b1;
                        ggrp <= ggrp + 1'b1;
                        bi   <= bi + 1'b1;
                    end
                end
                // 这个 beat 的 32 字节处理完 → 下一个
                if (bi == 6'd32) begin
                    if (lastbeat) begin
                        o_last <= 1'b1;
                        st <= S_IDLE;
                    end else st <= S_AR;
                end
            end
            default: st <= S_IDLE;
            endcase
        end
    end
endmodule

