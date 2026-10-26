// RAW12 payload only, low byte / low pixel first. One input beat per clock.
// Upstream must remove CSI headers, CRC and lane padding, and filter DT/VC.
// No backpressure: O_pixel_count (0/2/4) qualifies O_pixels each cycle.
// Errors invalidate the enclosing packet/frame; already emitted pixels remain.
module csi2_raw12_unpack (
    input  wire        I_clock,
    input  wire        I_reset_n,
    input  wire        I_enable,
    input  wire [31:0] I_data,
    input  wire [2:0]  I_nbytes,
    input  wire        I_valid,
    input  wire        I_sop,
    input  wire        I_eop,
    output reg  [47:0] O_pixels,
    output reg  [2:0]  O_pixel_count,
    output reg         O_packet_done,
    output reg         O_packet_error
);
    reg [15:0] residue, residue_next;
    reg [1:0] residue_count, residue_count_next;
    reg active, active_next;
    reg [47:0] pixels_next, assembled;
    reg [31:0] masked_data;
    reg [2:0] pixel_count_next, total;
    reg [1:0] base_count;
    reg done_next, error_next;

    always @* begin
        residue_next = residue;
        residue_count_next = residue_count;
        active_next = active;
        pixels_next = 48'b0;
        pixel_count_next = 3'b0;
        done_next = 1'b0;
        error_next = 1'b0;
        assembled = 48'b0;
        masked_data = 32'b0;
        total = 3'b0;
        base_count = 2'b0;
        if (!I_enable) begin
            residue_next = 16'b0;
            residue_count_next = 2'b0;
            active_next = 1'b0;
        end else if (I_valid) begin
            if (I_nbytes == 0 || I_nbytes > 4 || (!active && !I_sop)) begin
                error_next = 1'b1;
                residue_next = 16'b0;
                residue_count_next = 2'b0;
                active_next = 1'b0;
            end else begin
                error_next = I_sop && active;
                active_next = 1'b1;
                if (!I_sop) begin
                    base_count = residue_count;
                    if (residue_count == 1) assembled[7:0] = residue[7:0];
                    if (residue_count == 2) assembled[15:0] = residue;
                end
                case (I_nbytes)
                    1: masked_data = {24'b0, I_data[7:0]};
                    2: masked_data = {16'b0, I_data[15:0]};
                    3: masked_data = {8'b0, I_data[23:0]};
                    4: masked_data = I_data;
                    default: masked_data = 32'b0;
                endcase
                assembled = assembled | ({16'b0, masked_data} << (base_count * 8));
                total = {1'b0, base_count} + I_nbytes;
                if (total == 6) begin
                    pixels_next[11:0]  = {assembled[7:0], assembled[19:16]};
                    pixels_next[23:12] = {assembled[15:8], assembled[23:20]};
                    pixels_next[35:24] = {assembled[31:24], assembled[43:40]};
                    pixels_next[47:36] = {assembled[39:32], assembled[47:44]};
                    pixel_count_next = 4;
                    residue_next = 0;
                    residue_count_next = 0;
                end else if (total >= 3) begin
                    pixels_next[11:0]  = {assembled[7:0], assembled[19:16]};
                    pixels_next[23:12] = {assembled[15:8], assembled[23:20]};
                    pixel_count_next = 2;
                    residue_next = assembled[39:24];
                    residue_count_next = total - 3;
                end else begin
                    residue_next = assembled[15:0];
                    residue_count_next = total[1:0];
                end
                if (I_eop) begin
                    done_next = 1'b1;
                    error_next = error_next || (residue_count_next != 0);
                    residue_next = 0;
                    residue_count_next = 0;
                    active_next = 1'b0;
                end
            end
        end
    end

    always @(posedge I_clock or negedge I_reset_n) begin
        if (!I_reset_n) begin
            residue <= 0;
            residue_count <= 0;
            active <= 0;
            O_pixels <= 0;
            O_pixel_count <= 0;
            O_packet_done <= 0;
            O_packet_error <= 0;
        end else begin
            residue <= residue_next;
            residue_count <= residue_count_next;
            active <= active_next;
            O_pixels <= pixels_next;
            O_pixel_count <= pixel_count_next;
            O_packet_done <= done_next;
            O_packet_error <= error_next;
        end
    end
endmodule
