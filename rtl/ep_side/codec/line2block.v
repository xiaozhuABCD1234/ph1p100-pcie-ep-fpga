// line2block.v — 行扫描像素 → 8x8 块（JPEG 需要按块处理）
//
// DCT 要吃 8x8 块，但相机按行送。这里用**双缓冲**的 8 行组：
//   写侧把 8 行写进 bank A，写满后切到 bank B 继续收，输出侧同时从 bank A 取块。
// 单缓冲时「读 8 行」和「编码 8 行」串行，是压缩帧率的另一半瓶颈（板上 4.5 fps）；
// 双缓冲后两者重叠，帧时间从 read+encode 降到 max(read, encode)。
//
// 约束：
//   · 写侧绝不写「满」的 bank；目标 bank 未释放时 s_ready=0，反压到 DDR 回读。
//   · 输出侧只读「满」的 bank，读完清标志。
//   · 一帧最后一组的 eof 由写侧锁存，输出侧在最后一块最后一拍给出。
module line2block #(
    parameter integer W = 1920        // 图像宽度（像素）
)(
    input  wire        clk,
    input  wire        rst_n,
    // 像素输入（行优先，4 个/拍）
    input  wire [31:0] s_data,
    input  wire        s_valid,
    output wire        s_ready,
    input  wire        s_eol,         // 行尾（与最后一个像素同拍，当前未用）
    input  wire        s_eof,         // 帧尾（与最后一个像素同拍）
    // 块输出（每块 16 拍，第 1 拍带 m_sof，最后一个块最后一拍带 m_eof）
    output reg  [31:0] m_data,
    output reg         m_valid,
    input  wire        m_ready,
    output reg         m_sof,
    output reg         m_eof
);
    localparam BLK = W / 8;                   // 每行块数
    localparam BW  = W / 4;                   // 每行拍数
    localparam BANK = 8 * W;                  // 一个 bank 的字节数

    reg [7:0] mbuf [0:2*8*W-1];               // 两个 8 行 bank
    reg [2:0] wy;                             // 写侧：行号 0..7
    reg [15:0] wx;                            // 写侧：行内拍号
    reg        wr_bank;                       // 写侧当前 bank
    reg        full0, full1;                  // bank 是否已写满、等待输出
    reg        eof_b0, eof_b1;                // 哪个 bank 含本帧最后一组

    reg        out_run;                       // 输出侧正在吐一个 bank
    reg        out_bank;
    reg [7:0]  obx;                           // 当前块列
    reg [2:0]  orow;                          // 块内行
    reg [1:0]  oc;                            // 行内第几拍（8 像素 = 2 拍）

    wire       bank_full = wr_bank ? full1 : full0;
    wire       any_full  = full0 | full1;
    // 只有「开始写新的 8 行」时才需要目标 bank 空闲；写到一半不会被抢走。
    assign s_ready = (wy != 3'd0) || !bank_full;

    integer k;
    integer base;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wy <= 0; wx <= 0; wr_bank <= 1'b0; full0 <= 1'b0; full1 <= 1'b0;
            eof_b0 <= 0; eof_b1 <= 0;
            out_run <= 1'b0; out_bank <= 1'b0; obx <= 0; orow <= 0; oc <= 0;
            m_data <= 0; m_valid <= 0; m_sof <= 0; m_eof <= 0;
        end else begin
            if (m_valid && m_ready) m_valid <= 1'b0;

            // ---------------- 写侧：8 行一组 ----------------
            if (s_valid && s_ready) begin
                for (k = 0; k < 4; k = k + 1)
                    mbuf[wr_bank*BANK + wy*W + wx*4 + k] <= s_data[k*8 +: 8];
                if (wx == BW - 1) begin
                    wx <= 0;
                    if (wy == 3'd7) begin
                        if (s_eof) begin
                            if (wr_bank) eof_b1 <= 1'b1;
                            else         eof_b0 <= 1'b1;
                        end
                        wy <= 0;
                        if (wr_bank) full1 <= 1'b1;
                        else         full0 <= 1'b1;
                        wr_bank <= ~wr_bank;
                    end else wy <= wy + 3'd1;
                end else wx <= wx + 16'd1;
            end

            // ---------------- 输出侧：满 bank → 块流 ----------------
            if (!out_run) begin
                if (any_full) begin
                    out_bank <= full0 ? 1'b0 : 1'b1;
                    obx <= 0; orow <= 0; oc <= 0;
                    out_run <= 1'b1;
                end
            end else if (!m_valid || m_ready) begin
                base   = out_bank*BANK + orow*W + obx*8 + oc*4;
                m_data <= { mbuf[base+3], mbuf[base+2], mbuf[base+1], mbuf[base+0] };
                m_valid<= 1'b1;
                m_sof  <= (obx == 0) && (orow == 0) && (oc == 0);
                // 帧尾属于「含最后一组的那个 bank」，不能用一个全局锁存 ——
                // 双缓冲下写侧可能领先输出 1~2 组，全局标记会标到上一组上。
                m_eof  <= (out_bank ? eof_b1 : eof_b0) &&
                          (obx == BLK-1) && (orow == 3'd7) && (oc == 2'd1);
                if ((obx == BLK-1) && (orow == 3'd7) && (oc == 2'd1)) begin
                    if (out_bank) eof_b1 <= 1'b0;
                    else          eof_b0 <= 1'b0;
                end

                if (oc == 2'd1) begin
                    oc <= 0;
                    if (orow == 3'd7) begin
                        orow <= 0;
                        if (obx == BLK-1) begin
                            obx <= 0;
                            out_run <= 1'b0;
                            if (out_bank) full1 <= 1'b0;
                            else          full0 <= 1'b0;
                        end else obx <= obx + 8'd1;
                    end else orow <= orow + 3'd1;
                end else oc <= oc + 2'd1;
            end
        end
    end
endmodule