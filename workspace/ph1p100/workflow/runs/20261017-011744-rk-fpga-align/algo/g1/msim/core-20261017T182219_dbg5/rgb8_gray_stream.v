// RGB888 -> GRAY8 stream (Verilog-2001)
// Y = (77*R + 150*G + 29*B + 128) >> 8
module rgb8_gray_stream (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       s_valid,
    output wire       s_ready,
    input  wire [7:0] s_r,
    input  wire [7:0] s_g,
    input  wire [7:0] s_b,
    input  wire       s_sof,
    input  wire       s_last,
    output reg        m_valid,
    input  wire       m_ready,
    output reg  [7:0] m_y,
    output reg        m_sof,
    output reg        m_last
);

    wire [16:0] sum;
    assign sum = (17'd77 * {9'd0, s_r}) +
                 (17'd150 * {9'd0, s_g}) +
                 (17'd29 * {9'd0, s_b}) +
                 17'd128;

    assign s_ready = rst_n && (!m_valid || m_ready);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_valid <= 1'b0;
            m_y     <= 8'd0;
            m_sof   <= 1'b0;
            m_last  <= 1'b0;
        end else if (s_ready) begin
            m_valid <= s_valid;
            if (s_valid) begin
                m_y    <= sum[15:8];
                m_sof  <= s_sof;
                m_last <= s_last;
            end
        end
    end

endmodule

