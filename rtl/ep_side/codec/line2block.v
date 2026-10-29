// line2block.v — 行扫描像素 → 8x8 块（JPEG 需要按块处理）
//
// DCT 要吃 8x8 块，但相机按行送。这里用 8 行缓冲把行流转成块流：
// 写满 8 行后停止接收，按块（每块 64 像素、4 个/拍、16 拍）逐个吐出。
//
// 压缩链是 DDR 回读的，不需要实时，所以单缓冲（不做双缓冲）足够：
// 8 行写 3840 拍 + 240 块输出 3840 拍，1088 行共约 6.5 ms/帧 @100 MHz。
module line2block #(
    parameter integer W = 1920        // 图像宽度（像素）
)(
    input  wire        clk,
    input  wire        rst_n,
    // 像素输入（行优先，4 个/拍）
    input  wire [31:0] s_data,
    input  wire        s_valid,
    output wire        s_ready,
    input  wire        s_eol,         // 行尾（与最后一个像素同拍）
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

    reg [7:0] mbuf [0:15359];                  // 8 行 x 1920，固定尺寸
    reg [2:0]  wy;
    reg [15:0] wx;
    reg        eof_lat;

    localparam S_WRITE = 1'b0, S_OUT = 1'b1;
    reg        st;
    reg [7:0]  obx;                           // 当前块列
    reg [2:0]  orow;                          // 块内行
    reg [1:0]  oc;                            // 行内第几拍（8 像素 = 2 拍）

    assign s_ready = (st == S_WRITE);

    integer k;
    integer base;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= S_WRITE; wy <= 0; wx <= 0; eof_lat <= 0;
            obx <= 0; orow <= 0; oc <= 0;
            m_data <= 0; m_valid <= 0; m_sof <= 0; m_eof <= 0;
        end else begin
            if (m_valid && m_ready) m_valid <= 1'b0;

            case (st)
            // ---------------- 写 8 行 ----------------
            S_WRITE: if (s_valid && s_ready) begin
                for (k = 0; k < 4; k = k + 1) begin
                    mbuf[wy*W + wx*4 + k] <= s_data[k*8 +: 8];
                end
                if (wx == BW - 1) begin
                    wx <= 0;
                    if (s_eof) eof_lat <= 1'b1;
                    if (wy == 3'd7) begin
                        wy <= 0;
                        obx <= 0; orow <= 0; oc <= 0;
                        st <= S_OUT;
                    end else wy <= wy + 3'd1;
                end else wx <= wx + 16'd1;
            end

            // ---------------- 按块输出 ----------------
            S_OUT: if (!m_valid || m_ready) begin
                base   = orow * W + obx * 8 + oc * 4;
                m_data <= { mbuf[base+3], mbuf[base+2], mbuf[base+1], mbuf[base+0] };
                m_valid<= 1'b1;
                m_sof  <= (obx == 0) && (orow == 0) && (oc == 0);
                // 最后一块的最后一拍带 eof
                m_eof  <= eof_lat && (obx == BLK-1) && (orow == 3'd7) && (oc == 2'd1);

                if (oc == 2'd1) begin
                    oc <= 0;
                    if (orow == 3'd7) begin
                        orow <= 0;
                        if (obx == BLK-1) begin
                            obx <= 0;
                            eof_lat <= 0;
                            st <= S_WRITE;
                        end else obx <= obx + 8'd1;
                    end else orow <= orow + 3'd1;
                end else oc <= oc + 2'd1;
            end
            endcase
        end
    end
endmodule
