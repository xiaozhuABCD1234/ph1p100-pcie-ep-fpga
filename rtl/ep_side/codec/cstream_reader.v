// cstream_reader.v — 从 DDR 读回已发布的灰度帧，输出 JPEG 需要的字节流
//
// 为什么回读：4K 实时流 62.7 MB/s 喂不动慢速压缩链（ROI 适配器 FIFO 只有 4 行）。
// 改成读 DDR 里已经落好的整帧，压缩器可以按自己的节奏跑，慢一点只是压缩帧率低。
//
// R10F 载荷是 packed RAW10（4 采样 5 字节），灰度值就在前 4 个字节里（第 5 字节是
// 各采样的低 2 位），所以这里做 5→4 拆包，直接把采样高 8 位吐给 JPEG。
//
// 读 burst + 2 KB FIFO：
//   单拍 AR 的往返延迟约 180 拍，81,600 笔 AR 光握手就 ~147 ms/帧。这里一次
//   AR 读最多 64 拍（2 KB），且不跨 4 KiB；DDR 的 R 通道**不能反压**（rready
//   一低，后续 beat 就不再来了，板上实测会卡死在 S_RD），所以 rready 恒 1，
//   用 64 深 × 256 bit 的 FIFO 吸收突发，解包侧按自己的节奏取。
module cstream_reader #(
    parameter integer BURST = 64        // 每次 AR 的最大拍数（1 拍 = 32 B）
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,          // 单拍：开始读一帧
    input  wire [28:0] base,
    input  wire [31:0] bytes,          // 要读的载荷字节数（2,611,200）
    output reg  [7:0]  o_data,
    output reg         o_valid,
    input  wire        o_ready,
    output wire        busy,
    output reg         o_done,         // 一帧读完（单拍）：通知相机写者释放源块
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
    output wire        m_rready
);
    localparam S_IDLE = 2'd0, S_AR = 2'd1, S_RD = 2'd2, S_OUT = 2'd3;
    localparam FD = 64;                 // FIFO 深度 = 最大突发拍数
    reg [1:0]  st;
    reg [31:0] left;          // 本帧还要接收的 beat 数
    reg [28:0] addr;
    reg [255:0] beat;
    reg [5:0]  bi;
    reg [2:0]  ggrp;
    reg        lastbeat;
    reg        start_pend;
    reg [7:0]  burst_left;    // 本笔突发还剩几拍
    reg [31:0] total;

    reg [255:0] fifo [0:FD-1];
    reg [5:0]   fwr, frd;
    reg [6:0]   fcnt;
    reg         rd_active;    // 本帧读事务进行中：只接收这期间的 R 拍

    assign busy     = (st != S_IDLE);
    assign st_dbg   = {2'b00, st};
    assign m_rready = 1'b1;                 // DDR R 通道不能反压

    wire fifo_push = m_rvalid && rd_active;
    wire fifo_pop  = (st == S_RD) && (fcnt != 7'd0);

    // 本笔突发拍数：min(BURST, 剩余拍数, 到 4 KiB 边界的拍数)
    wire [7:0] page_left = 8'd128 - {1'b0, addr[11:5]};
    wire [7:0] left8     = (left > 32'd128) ? 8'd128 : left[7:0];
    wire [7:0] to_page   = (left8 < page_left) ? left8 : page_left;
    wire [7:0] nburst    = (to_page < BURST) ? to_page : BURST[7:0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= S_IDLE; left <= 0; addr <= 0; beat <= 0; bi <= 0; ggrp <= 0;
            o_data <= 0; o_valid <= 0; lastbeat <= 0; total <= 0; start_pend <= 0; o_done <= 0;
            burst_left <= 0; fwr <= 0; frd <= 0; fcnt <= 0; rd_active <= 0;
            m_araddr <= 0; m_arlen <= 0; m_arsize <= 3'b101; m_arburst <= 2'b01; m_arvalid <= 0;
        end else begin
            o_done <= 1'b0;

            // FIFO 写（DDR 送来即收）
            if (fifo_push) fifo[fwr] <= m_rdata;

            case (st)
            S_IDLE: begin
                if (start) start_pend <= 1'b1;
                if (o_valid) begin
                    if (o_ready) o_valid <= 1'b0;
                end else if (start || start_pend) begin
                    start_pend <= 1'b0;
                    addr  <= base;
                    left  <= (bytes + 31) >> 5;
                    total <= bytes;
                    bi <= 0; ggrp <= 0;
                    fwr <= 0; frd <= 0; fcnt <= 0; rd_active <= 0;
                    st <= S_AR;
                end
            end
            S_AR: begin
                m_araddr  <= addr;
                m_arlen   <= nburst - 8'd1;
                m_arsize  <= 3'b101;
                m_arburst <= 2'b01;
                m_arvalid <= 1'b1;
                if (m_arvalid && m_arready) begin
                    m_arvalid  <= 1'b0;
                    burst_left <= nburst;
                    addr       <= addr + {16'd0, nburst, 5'd0};
                    rd_active  <= 1'b1;
                    st         <= S_RD;
                end
            end
            S_RD: begin
                if (fifo_pop) begin
                    beat  <= fifo[frd];
                    bi    <= 6'd0;
                    left  <= left - 32'd1;
                    lastbeat <= (left == 32'd1);
                    burst_left <= burst_left - 8'd1;
                    st    <= S_OUT;
                end
            end
            S_OUT: begin
                if (o_valid && o_ready) o_valid <= 1'b0;
                if (bi == 6'd32) begin
                    if (!o_valid || o_ready) begin
                        if (lastbeat) begin
                            o_done <= 1'b1;
                            rd_active <= 1'b0;
                            st     <= S_IDLE;
                        end else if (burst_left != 8'd0) st <= S_RD;
                        else                             st <= S_AR;
                    end
                end else if (!o_valid) begin
                    if (ggrp == 3'd4) begin
                        ggrp <= 0;
                        bi   <= bi + 1'b1;
                    end else begin
                        o_data  <= beat[bi*8 +: 8];
                        o_valid <= 1'b1;
                        ggrp <= ggrp + 1'b1;
                        bi   <= bi + 1'b1;
                    end
                end
            end
            default: st <= S_IDLE;
            endcase

            // 指针/计数（push 与 pop 可能同拍）
            if (fifo_push) fwr <= fwr + 6'd1;
            if (fifo_pop)  frd <= frd + 6'd1;
            case ({fifo_push, fifo_pop})
                2'b10: fcnt <= fcnt + 7'd1;
                2'b01: fcnt <= fcnt - 7'd1;
                default: fcnt <= fcnt;
            endcase
        end
    end
endmodule
