// RGB888 -> GRAY8 stream (Verilog-2001)
// Y = (77*R + 150*G + 29*B + 128) >> 8
//
// Bounded pipelining for Fmax (T09.rk-align-algo round1): the constant
// products are registered first, the sum and shift follow one cycle later.
// Latency is 2 cycles; the sidebands are delayed identically.  The arithmetic
// result is unchanged.
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

    // stage 1: registered products + sidebands
    reg [16:0] p_r, p_g, p_b;
    reg        v1, sof1, last1;

    // Production timing variant: split the exact integer sum after products.
    reg [17:0] rg2, b2;
    reg v2, sof2, last2;
    wire [17:0] sum3 = rg2 + b2;

    assign s_ready = rst_n && (!m_valid || m_ready);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            v1    <= 1'b0;
            sof1  <= 1'b0;
            last1 <= 1'b0;
            p_r   <= 17'd0;
            p_g   <= 17'd0;
            p_b   <= 17'd0;
        end else if (s_ready) begin
            v1    <= s_valid;
            sof1  <= s_sof;
            last1 <= s_last;
            p_r   <= 17'd77  * {9'd0, s_r};
            p_g   <= 17'd150 * {9'd0, s_g};
            p_b   <= 17'd29  * {9'd0, s_b};
        end
    end

    // stage 2: partial sums, under the same complete-pipe stall enable
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rg2<=0; b2<=0; v2<=0; sof2<=0; last2<=0;
        end else if (s_ready) begin
            rg2 <= {1'b0,p_r} + {1'b0,p_g};
            b2 <= {1'b0,p_b} + 18'd128;
            v2<=v1; sof2<=sof1; last2<=last1;
        end
    end
    // stage 3: final sum / shift -> output register (no rounding change)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_valid <= 1'b0;
            m_y     <= 8'd0;
            m_sof   <= 1'b0;
            m_last  <= 1'b0;
        end else if (s_ready) begin
            m_valid <= v2;
            m_sof   <= sof2;
            m_last  <= last2;
            if (v2) m_y <= sum3[15:8];
        end
    end

endmodule
