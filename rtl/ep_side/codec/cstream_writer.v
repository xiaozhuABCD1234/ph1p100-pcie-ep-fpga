// cstream_writer.v — 把压缩字节流写成定长 DDR 帧（供 A 路 pusher 送主机）
//
// 为什么定长：主机 slot 长度由驱动按几何推出（1920×1088 R10F = 2,613,248 B），
// pusher 只搬定长。压缩流长度是变的，所以把压缩字节写在最前、其余补零，
// 真实长度放到 0x250 让主机截取。
//
// 写口按 256bit、单拍突发（awlen=0）：一帧 2,613,248 B / 32 B = 81,664 拍，
// 100 MHz 下 0.8 ms，够快，也省掉多拍突发的边界处理。
module cstream_writer #(
    parameter [28:0] BASE        = 29'h0500_0000,
    parameter integer FRAME_BYTES = 2613248
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [7:0]  s_data,
    input  wire        s_valid,
    output wire        s_ready,
    input  wire        s_sof,
    input  wire        s_eof,
    output reg  [31:0] wr_seq,
    output wire [31:0] wr_base,
    output wire [31:0] wr_len,
    output reg         wr_valid,
    output reg  [31:0] st_bytes,
    output reg  [31:0] st_stream_len,   // 帧尾时的真实压缩字节数（不含补零）
    output reg  [28:0] m_awaddr,
    output reg  [7:0]  m_awlen,
    output reg  [2:0]  m_awsize,
    output reg  [1:0]  m_awburst,
    output reg         m_awvalid,
    input  wire        m_awready,
    output reg  [255:0] m_wdata,
    output reg  [31:0] m_wstrb,
    output reg         m_wlast,
    output reg         m_wvalid,
    input  wire        m_wready,
    input  wire [1:0]  m_bresp,
    input  wire        m_bvalid,
    output wire        m_bready
);
    assign m_bready = 1'b1;
    assign wr_base  = BASE;
    assign wr_len   = FRAME_BYTES;

    localparam S_IDLE = 3'd0, S_DATA = 3'd1, S_FLUSH = 3'd2, S_PAD = 3'd3;
    reg [2:0]   st;
    reg [255:0] acc;
    reg [5:0]   fill;
    reg [31:0]  nbytes;
    reg         eof_seen;   // s_eof 是单拍脉冲，可能正好落在不 ready 的拍上
    reg [28:0]  addr;

    // 待发的 beat（1 深）
    reg         bv;
    reg [255:0] bdata;
    reg [28:0]  baddr;

    // acc 还能再收字节，且没有卡住的 beat
    assign s_ready = (st == S_DATA) && (fill != 32) && (!bv || (m_awvalid && m_awready));

    reg [255:0] full_beat;
    always @(*) full_beat = {s_data, acc[247:0]};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= S_IDLE; acc <= 0; fill <= 0; nbytes <= 0; addr <= BASE;
            wr_seq <= 0; wr_valid <= 0; st_bytes <= 0; st_stream_len <= 0;
            m_awaddr <= 0; m_awlen <= 0; m_awsize <= 3'b101; m_awburst <= 2'b01;
            m_awvalid <= 0; m_wdata <= 0; m_wstrb <= 0; m_wlast <= 0; m_wvalid <= 0;
            bv <= 0; bdata <= 0; baddr <= 0; eof_seen <= 1'b0;
        end else begin
            wr_valid <= 1'b0;

            // AXI：aw 与 w 各自握手
            if (m_awvalid && m_awready) m_awvalid <= 1'b0;
            if (m_wvalid && m_wready)   m_wvalid <= 1'b0;

            // 把待发 beat 推上总线
            if (bv && !m_awvalid && !m_wvalid) begin
                m_awaddr  <= baddr;
                m_awlen   <= 8'd0;
                m_awsize  <= 3'b101;
                m_awburst <= 2'b01;
                m_awvalid <= 1'b1;
                m_wdata   <= bdata;
                m_wstrb   <= 32'hFFFF_FFFF;
                m_wlast   <= 1'b1;
                m_wvalid  <= 1'b1;
                bv        <= 1'b0;
                addr      <= baddr + 29'd32;
            end

            case (st)
            S_IDLE: if (s_sof || s_valid) begin
                acc <= 0; fill <= 0; nbytes <= 0; addr <= BASE; st <= S_DATA;
                if (s_valid && s_ready) begin
                    // 第一个字节就在这一拍到了，顺手收下
                    acc[7:0] <= s_data;
                    fill <= 6'd1;
                    nbytes <= 32'd1;
                    st_bytes <= st_bytes + 32'd1;
                end
            end
            S_DATA: begin
                if (s_eof) eof_seen <= 1'b1;      // 先锁住，避免落在不 ready 的拍上丢掉
                if (s_valid && s_ready) begin
                    acc[fill*8 +: 8] <= s_data;
                    nbytes   <= nbytes + 32'd1;
                    st_bytes <= st_bytes + 32'd1;
                    if (fill == 31) begin
                        bdata <= full_beat;
                        baddr <= addr;
                        bv    <= 1'b1;
                        acc   <= 0;
                        fill  <= 0;
                    end else fill <= fill + 1'b1;
                    if (s_eof || eof_seen) begin
                        st_stream_len <= st_bytes + 32'd1;
                        eof_seen <= 1'b0;
                        st <= S_FLUSH;
                    end
                end else if (eof_seen) begin
                    st_stream_len <= st_bytes;
                    eof_seen <= 1'b0;
                    st <= S_FLUSH;
                end
            end
            S_FLUSH: if (!bv) begin
                // 尾部不足 32 字节：补零凑一个 beat（主机只读前 stream_len 字节）
                if (fill != 0) begin
                    bdata <= acc;
                    baddr <= addr;
                    bv    <= 1'b1;
                    fill  <= 0;
                    acc   <= 0;
                end else st <= S_PAD;
            end else if (m_awvalid && m_awready) begin
                bv <= 1'b0;
            end
            S_PAD: begin
                if (nbytes >= FRAME_BYTES) begin
                    if (!bv && !m_awvalid && !m_wvalid) begin
                        wr_seq   <= wr_seq + 1'b1;
                        wr_valid <= 1'b1;
                        st       <= S_IDLE;
                    end
                end else if (!bv) begin
                    bdata   <= 256'd0;
                    baddr   <= addr;
                    bv      <= 1'b1;
                    nbytes  <= nbytes + 32'd32;
                end
            end
            default: st <= S_IDLE;
            endcase
        end
    end
endmodule

