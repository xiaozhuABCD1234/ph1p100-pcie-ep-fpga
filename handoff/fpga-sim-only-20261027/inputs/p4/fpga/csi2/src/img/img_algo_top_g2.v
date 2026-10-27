// img_algo_top_g2.v — pin-level build vehicle for the T09 module-level G2 build.
// Verilog-2001, async reset.
//
// WHY: img_algo_parallel_top has ~285 top-level ports (4px streams + three
// 32-bit outputs + status), which exceeds the device IO count for a standalone
// build.  This thin wrapper keeps the REAL parallel organisation inside and
// brings out only a serial data output, a validity flag and two status bits,
// with a fixed 64x8 phase-0 configuration and a counter-generated input
// pattern.  It is a synthesis/STA/RESOURCE vehicle only: no board download in
// this package (G3/G4 stay with the board-test package), and the pattern is
// synthetic (diagnostic), never claimed as camera data.
//
// Ports: clk, rst_n, dout (serial fold of the three output streams),
//        dout_valid, led_good, led_abort.

module img_algo_top_g2 (
    input  wire clk,
    input  wire rst_n,
    output wire dout,
    output wire dout_valid,
    output wire led_good,
    output wire led_abort
);
    localparam W = 12'd64;    // 16 beats per row, 8 rows
    localparam H = 12'd8;
    localparam NB = 128;      // H * W/4

    reg  [7:0]  beat;         // 0..NB-1
    reg  [11:0] cfgw;
    reg  [11:0] cfgh;
    reg  [1:0]  cfgp;
    reg         cfg_valid;
    wire        cfg_ready;
    wire        cfg_error;

    reg  [39:0] s_data;
    reg         s_valid, s_sof, s_eol, s_eof, s_abort;
    wire        s_ready;

    wire        y8_valid, gau_valid, he_valid;
    wire [31:0] y8_data, gau_data, he_data;
    wire        y8_sof, y8_eol, y8_eof, y8_abort;
    wire        gau_sof, gau_eol, gau_eof, gau_abort;
    wire        he_sof, he_eol, he_eof, he_abort;
    wire [15:0] st_good, st_abort, st_pub, st_rej, st_gauab;
    reg  [7:0]  lut_addr;
    wire [7:0]  lut_data;

    img_algo_parallel_top #(.MAX_WORDS(512)) u_top (
        .clk(clk), .rst_n(rst_n),
        .cfg_valid(cfg_valid), .cfg_ready(cfg_ready),
        .cfg_width(cfgw), .cfg_height(cfgh), .cfg_phase(cfgp),
        .cfg_error(cfg_error),
        .s_valid(s_valid), .s_ready(s_ready), .s_data(s_data),
        .s_sof(s_sof), .s_eol(s_eol), .s_eof(s_eof), .s_abort(s_abort),
        .y8_valid(y8_valid), .y8_ready(1'b1), .y8_data(y8_data),
        .y8_sof(y8_sof), .y8_eol(y8_eol), .y8_eof(y8_eof), .y8_abort(y8_abort),
        .gau_valid(gau_valid), .gau_ready(1'b1), .gau_data(gau_data),
        .gau_sof(gau_sof), .gau_eol(gau_eol), .gau_eof(gau_eof), .gau_abort(gau_abort),
        .he_valid(he_valid), .he_ready(1'b1), .he_data(he_data),
        .he_sof(he_sof), .he_eol(he_eol), .he_eof(he_eof), .he_abort(he_abort),
        .st_frames_good(st_good), .st_frames_abort(st_abort),
        .st_he_published(st_pub), .st_he_rejected(st_rej),
        .st_gau_abort(st_gauab),
        .he_lut_addr(lut_addr), .he_lut_data(lut_data)
    );

    // configuration: fixed 64x8 phase 0, latched once
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cfgw <= W; cfgh <= H; cfgp <= 2'd0; cfg_valid <= 1'b1;
        end else if (cfg_valid && cfg_ready) begin
            cfg_valid <= 1'b0;
        end
    end

    // synthetic input pattern: counter beats with exact sidebands
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            beat <= 8'd0;
            s_data <= 40'd0;
            s_valid <= 1'b0; s_sof <= 1'b0; s_eol <= 1'b0; s_eof <= 1'b0; s_abort <= 1'b0;
        end else begin
            if (!cfg_valid && cfg_ready) begin
                // configuration done, start the frame
                s_data  <= {10'd512, 10'd512, 10'd512, 10'd512};
                s_valid <= 1'b1;
                s_sof   <= 1'b1;
                s_eol   <= 1'b0;
                s_eof   <= 1'b0;
                s_abort <= 1'b0;
                beat    <= 8'd1;
            end else if (s_valid && s_ready) begin
                if (beat == NB[7:0]) begin
                    s_valid <= 1'b0; s_sof <= 1'b0; s_eol <= 1'b0; s_eof <= 1'b0;
                    beat    <= 8'd0;
                end else begin
                    s_data  <= {10'd512, 10'd512, 10'd512, 10'd512} + {30'd0, beat};
                    s_sof   <= 1'b0;
                    s_eol   <= ((beat & 8'd15) == 8'd15);
                    s_eof   <= (beat == (NB[7:0] - 8'd1));
                    s_abort <= 1'b0;
                    beat    <= beat + 8'd1;
                end
            end
        end
    end

    // serial fold of the three output streams (keeps all three datapaths live)
    reg [1:0] rot;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) rot <= 2'd0;
        else if (y8_valid || gau_valid || he_valid) rot <= rot + 2'd1;
    end
    wire [31:0] fold32 = (rot == 2'd0) ? y8_data :
                         (rot == 2'd1) ? gau_data : he_data;
    wire        fold_v = (rot == 2'd0) ? y8_valid :
                         (rot == 2'd1) ? gau_valid : he_valid;
    assign dout       = ^fold32;
    assign dout_valid = fold_v;
    assign led_good   = st_good[0];
    assign led_abort  = st_abort[0];

    // keep the LUT readback and remaining status observable for synthesis
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) lut_addr <= 8'd0;
        else if (y8_eof) lut_addr <= lut_addr + 8'd1;
    end
    wire unused_ok = (^lut_data) ^ (^st_pub) ^ (^st_rej) ^ (^st_gauab) ^
                     (^y8_sof) ^ (^y8_eol) ^ (^y8_eof) ^ (^y8_abort) ^
                     (^gau_sof) ^ (^gau_eol) ^ (^gau_eof) ^ (^gau_abort) ^
                     (^he_sof) ^ (^he_eol) ^ (^he_eof) ^ (^he_abort) ^ cfg_error;
endmodule
