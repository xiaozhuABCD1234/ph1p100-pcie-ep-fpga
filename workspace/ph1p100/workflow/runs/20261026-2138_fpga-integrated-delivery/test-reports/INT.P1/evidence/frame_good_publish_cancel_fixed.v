// corrected copy for verification only; production file unchanged
// fix: parenthesize if condition
module frame_good_publish_cancel (
    input  wire clk,
    input  wire rst_n,
    input  wire sof,
    input  wire last_roi_sample,
    input  wire suffix_done,
    input  wire crc_ok,
    input  wire fe_ok,
    input  wire abort_in,
    input  wire resof,
    output reg  frame_good,
    output reg  frame_abort,
    output reg  commit,
    output reg  cancel,
    output reg  published,
    output reg  busy
);
    localparam ST_IDLE     = 2'd0;
    localparam ST_INFRAME  = 2'd1;
    localparam ST_LASTROI  = 2'd2;
    localparam ST_WAIT     = 2'd3;

    reg [1:0] st;
    reg       roi_done;
    reg       crc_latched;
    reg       fe_latched;

    wire cancel_now = abort_in || resof;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st          <= ST_IDLE;
            roi_done    <= 1'b0;
            crc_latched <= 1'b0;
            fe_latched  <= 1'b0;
            frame_good  <= 1'b0;
            frame_abort <= 1'b0;
            commit      <= 1'b0;
            cancel      <= 1'b0;
            published   <= 1'b0;
            busy        <= 1'b0;
        end else begin
            frame_good  <= 1'b0;
            frame_abort <= 1'b0;
            commit      <= 1'b0;
            cancel      <= 1'b0;
            published   <= 1'b0;

            case (st)
                ST_IDLE: begin
                    busy <= 1'b0;
                    roi_done <= 1'b0;
                    crc_latched <= 1'b0;
                    fe_latched <= 1'b0;
                    if (sof) begin
                        st <= ST_INFRAME;
                        busy <= 1'b1;
                    end
                end
                ST_INFRAME: begin
                    busy <= 1'b1;
                    if (cancel_now) begin
                        st <= ST_IDLE;
                        frame_abort <= 1'b1;
                        cancel <= 1'b1;
                        busy <= 1'b0;
                    end else if (last_roi_sample) begin
                        roi_done <= 1'b1;
                        st <= ST_LASTROI;
                    end else if (sof) begin
                        st <= ST_IDLE;
                        frame_abort <= 1'b1;
                        cancel <= 1'b1;
                        busy <= 1'b0;
                    end
                end
                ST_LASTROI: begin
                    busy <= 1'b1;
                    if (cancel_now) begin
                        st <= ST_IDLE;
                        frame_abort <= 1'b1;
                        cancel <= 1'b1;
                        busy <= 1'b0;
                        roi_done <= 1'b0;
                    end else begin
                        if (crc_ok) crc_latched <= 1'b1;
                        if (fe_ok)  fe_latched  <= 1'b1;
                        st <= ST_WAIT;
                    end
                end
                ST_WAIT: begin
                    busy <= 1'b1;
                    if (cancel_now) begin
                        st <= ST_IDLE;
                        frame_abort <= 1'b1;
                        cancel <= 1'b1;
                        busy <= 1'b0;
                        roi_done <= 1'b0;
                        crc_latched <= 1'b0;
                        fe_latched <= 1'b0;
                    end else begin
                        if (crc_ok) crc_latched <= 1'b1;
                        if (fe_ok)  fe_latched  <= 1'b1;
                        if (suffix_done) begin
                            if ((crc_latched || crc_ok) && (fe_latched || fe_ok)) begin
                                frame_good <= 1'b1;
                                commit     <= 1'b1;
                                published  <= 1'b1;
                            end else begin
                                frame_abort <= 1'b1;
                                cancel      <= 1'b1;
                            end
                            st <= ST_IDLE;
                            busy <= 1'b0;
                            roi_done <= 1'b0;
                            crc_latched <= 1'b0;
                            fe_latched <= 1'b0;
                        end
                    end
                end
                default: st <= ST_IDLE;
            endcase
        end
    end
endmodule