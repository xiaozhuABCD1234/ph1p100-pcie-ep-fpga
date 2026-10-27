// Correctness prototype: bounded frame Gaussian with three Y8 row banks.
// Kernel outer([1,2,1],[1,2,1]), replicated borders, round once (sum+8)>>4.
// Input row loading and output row emission are separate phases: s_ready is
// low throughout output, including sink stalls. There is no continuous CSI
// service or dual-1080p30 throughput guarantee. Nine asynchronous sample
// reads per result are intentional here; production RAM ports/inference,
// pipelining, timing and resources require a separate implementation study.
module gray8_gaussian3x3_frame #(
    parameter MAX_WIDTH = 1920
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        cfg_valid,
    output wire        cfg_ready,
    input  wire [11:0] cfg_width,
    input  wire [11:0] cfg_height,
    input  wire        s_valid,
    output wire        s_ready,
    input  wire [7:0]  s_data,
    output wire        m_valid,
    input  wire        m_ready,
    output reg  [7:0]  m_data,
    output wire        m_sof,
    output wire        m_eol,
    output wire        m_eof,
    output wire        done_valid,
    input  wire        done_ready,
    output wire        done_error
);
    localparam ST_IDLE = 3'd0, ST_VALIDATE = 3'd1;
    localparam ST_FIRST = 3'd2, ST_SECOND = 3'd3, ST_NEXT = 3'd4;
    localparam ST_OUTPUT = 3'd5, ST_DONE = 3'd6;
    reg [2:0] state;
    reg [11:0] width, height, load_x, out_x, out_y;
    reg [1:0] top_bank, mid_bank, bot_bank, load_bank;
    reg error_flag;
    // No row is cleared on reset. State and bank pointers permit reads only
    // after all samples of every referenced row have been accepted.
    reg [7:0] row0 [0:MAX_WIDTH-1];
    reg [7:0] row1 [0:MAX_WIDTH-1];
    reg [7:0] row2 [0:MAX_WIDTH-1];

    assign cfg_ready = rst_n && state == ST_IDLE;
    assign s_ready = rst_n && (state == ST_FIRST || state == ST_SECOND || state == ST_NEXT);
    assign m_valid = rst_n && state == ST_OUTPUT;
    assign m_sof = m_valid && out_x == 0 && out_y == 0;
    assign m_eol = m_valid && out_x == width - 12'd1;
    assign m_eof = m_eol && out_y == height - 12'd1;
    assign done_valid = rst_n && state == ST_DONE;
    assign done_error = done_valid && error_flag;

    function [7:0] sample;
        input [1:0] bank;
        input [11:0] x;
        begin
            case (bank)
                2'd0: sample = row0[x];
                2'd1: sample = row1[x];
                2'd2: sample = row2[x];
                default: sample = 8'd0;
            endcase
        end
    endfunction

    reg [11:0] left_x, right_x;
    reg [9:0] top_sum, mid_sum, bot_sum;
    reg [11:0] weighted_sum, rounded_sum;
    always @* begin
        left_x = 12'd0;
        right_x = 12'd0;
        top_sum = 10'd0;
        mid_sum = 10'd0;
        bot_sum = 10'd0;
        weighted_sum = 12'd0;
        rounded_sum = 12'd0;
        m_data = 8'd0;
        if (m_valid) begin
            left_x = out_x == 0 ? out_x : out_x - 12'd1;
            right_x = out_x == width - 12'd1 ? out_x : out_x + 12'd1;
            // Each sample is widened BEFORE shift/add. Horizontal maximum
            // 255+2*255+255=1020 fits ten bits; no intermediate rounding.
            top_sum = {2'b0,sample(top_bank,left_x)}
                    + ({2'b0,sample(top_bank,out_x)} << 1)
                    + {2'b0,sample(top_bank,right_x)};
            mid_sum = {2'b0,sample(mid_bank,left_x)}
                    + ({2'b0,sample(mid_bank,out_x)} << 1)
                    + {2'b0,sample(mid_bank,right_x)};
            bot_sum = {2'b0,sample(bot_bank,left_x)}
                    + ({2'b0,sample(bot_bank,out_x)} << 1)
                    + {2'b0,sample(bot_bank,right_x)};
            // Maximum 4080, rounded maximum 4088, both fit twelve bits.
            weighted_sum = {2'b0,top_sum} + ({2'b0,mid_sum} << 1) + {2'b0,bot_sum};
            rounded_sum = weighted_sum + 12'd8;
            m_data = rounded_sum[11:4];
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            width <= 12'd0; height <= 12'd0;
            load_x <= 12'd0; out_x <= 12'd0; out_y <= 12'd0;
            top_bank <= 2'd0; mid_bank <= 2'd0; bot_bank <= 2'd0; load_bank <= 2'd0;
            error_flag <= 1'b0;
        end else begin
            case (state)
                ST_IDLE: if (cfg_valid) begin
                    width <= cfg_width;
                    height <= cfg_height;
                    error_flag <= 1'b0;
                    state <= ST_VALIDATE;
                end
                // Exactly one bounded validation cycle; no input accepted.
                ST_VALIDATE: begin
                    if (width == 0 || width > MAX_WIDTH || width > 12'd3840 ||
                        height == 0 || height > 12'd2160) begin
                        error_flag <= 1'b1;
                        state <= ST_DONE;
                    end else begin
                        load_x <= 12'd0;
                        out_x <= 12'd0; out_y <= 12'd0;
                        state <= ST_FIRST;
                    end
                end
                ST_FIRST: if (s_valid) begin
                    row0[load_x] <= s_data;
                    if (load_x == width - 12'd1) begin
                        load_x <= 12'd0;
                        if (height == 12'd1) begin
                            top_bank <= 2'd0; mid_bank <= 2'd0; bot_bank <= 2'd0;
                            state <= ST_OUTPUT;
                        end else state <= ST_SECOND;
                    end else load_x <= load_x + 12'd1;
                end
                ST_SECOND: if (s_valid) begin
                    row1[load_x] <= s_data;
                    if (load_x == width - 12'd1) begin
                        load_x <= 12'd0;
                        top_bank <= 2'd0; mid_bank <= 2'd0; bot_bank <= 2'd1;
                        state <= ST_OUTPUT;
                    end else load_x <= load_x + 12'd1;
                end
                ST_NEXT: if (s_valid) begin
                    case (load_bank)
                        2'd0: row0[load_x] <= s_data;
                        2'd1: row1[load_x] <= s_data;
                        2'd2: row2[load_x] <= s_data;
                    endcase
                    if (load_x == width - 12'd1) begin
                        load_x <= 12'd0;
                        state <= ST_OUTPUT;
                    end else load_x <= load_x + 12'd1;
                end
                ST_OUTPUT: if (m_ready) begin
                    if (out_x == width - 12'd1) begin
                        out_x <= 12'd0;
                        if (out_y == height - 12'd1) state <= ST_DONE;
                        else begin
                            out_y <= out_y + 12'd1;
                            top_bank <= mid_bank;
                            mid_bank <= bot_bank;
                            if (out_y + 12'd1 == height - 12'd1) begin
                                // Last output row repeats its center as bottom.
                                bot_bank <= bot_bank;
                            end else begin
                                // Row zero shares top/center, so bank two is
                                // initially free. Subsequently recycle old top.
                                load_bank <= out_y == 0 ? 2'd2 : top_bank;
                                bot_bank <= out_y == 0 ? 2'd2 : top_bank;
                                load_x <= 12'd0;
                                state <= ST_NEXT;
                            end
                        end
                    end else out_x <= out_x + 12'd1;
                end
                ST_DONE: if (done_ready) begin
                    state <= ST_IDLE;
                    error_flag <= 1'b0;
                end
                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule
