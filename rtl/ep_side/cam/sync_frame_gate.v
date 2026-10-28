// Frame-boundary gate: permit is synchronized into the pixel clock domain;
// a frame that is already open is aborted with a held pulse, never cut silently.
module sync_frame_gate #(parameter ENABLE = 1) (
    input  wire clk,
    input  wire rst_n,
    input  wire permit,
    input  wire sof,
    input  wire in_frame,
    input  wire in_line,
    input  wire pixel_valid,
    input  wire good,
    input  wire abort_in,
    output wire out_sof,
    output wire out_frame,
    output wire out_line,
    output wire out_pixel_valid,
    output wire out_good,
    output wire out_abort
);
    generate if (ENABLE) begin : g_gate
        reg [1:0] permit_s;
        reg       admitted;
        reg       abort_latched;

        // permit is quasi-static from the control clock. Two flops are enough
        // because a wrong sample can only delay or revoke, never create a SOF.
        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) permit_s <= 2'b00;
            else        permit_s <= {permit_s[0], permit};
        end

        wire permit_ok = permit_s[1];

        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                admitted      <= 1'b0;
                abort_latched <= 1'b0;
            end else begin
                if (!permit_ok) admitted <= 1'b0;
                else if (sof)   admitted <= 1'b1;
                else if (!in_frame) admitted <= 1'b0;

                if (admitted && !permit_ok) abort_latched <= 1'b1;
                if (!in_frame)              abort_latched <= 1'b0;
            end
        end

        assign out_sof         = sof         && permit_ok;
        assign out_frame       = in_frame    && admitted && permit_ok;
        assign out_line        = in_line     && admitted && permit_ok;
        assign out_pixel_valid = pixel_valid && admitted && permit_ok;
        assign out_good        = good        && admitted && permit_ok;
        assign out_abort       = abort_in || (admitted && !permit_ok) || abort_latched;
    end else begin : g_bypass
        assign out_sof         = sof;
        assign out_frame       = in_frame;
        assign out_line        = in_line;
        assign out_pixel_valid = pixel_valid;
        assign out_good        = good;
        assign out_abort       = abort_in;
    end endgenerate
endmodule
