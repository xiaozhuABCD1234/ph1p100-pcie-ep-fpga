`timescale 1ns/1ps
// =============================================================================
// p2_ddr_bridge.v -- single-beat 256-bit PAXI clock bridge.
//
// The P1 A1 store model exposes one 256-bit word per AW/W pair and one word per
// AR, with no burst length, no B channel and no write strobes.  The board DDR
// PAXI has the same single-beat contract but runs on the DDR user clock
// (dhi_clk, ~200 MHz), so the A1 chain (187.5 MHz) must cross domains.
//
// Three Gray-pointer asynchronous FIFOs (one reset, two clock domains):
//   WF: {awaddr[26:0], wdata[255:0]}  A1 -> DDR
//   AF: araddr[26:0]                  A1 -> DDR
//   RF: rdata[255:0]                  DDR -> A1
// The DDR side holds AW/W until both are accepted, sets wstrb=all-ones and
// wlast=1 for the single beat, and issues one AR at a time.
// No reset-domain-hopping logic beyond the FIFO reset synchronizers that the
// existing capture_async_fifo already contains.
// =============================================================================
module p2_ddr_bridge_b8 (
    // A1 / 187.5 MHz side (same shape as the P1 store's DDR port)
    input  wire         clk_a1,
    input  wire         rst_n,
    input  wire [31:0]  s_awaddr,
    input  wire         s_awvalid,
    output wire         s_awready,
    input  wire [255:0] s_wdata,
    input  wire         s_wvalid,
    output wire         s_wready,
    input  wire [31:0]  s_araddr,
    input  wire         s_arvalid,
    output wire         s_arready,
    output wire [255:0] s_rdata,
    output wire         s_rvalid,
    input  wire         s_rready,

    // DDR user-clock side (PH1P PAXI)
    input  wire         clk_ddr,
    input  wire         ddr_rdy,
    output wire [26:0]  paxi_awaddr,
    output wire         paxi_awvalid,
    input  wire         paxi_awready,
    output wire [255:0] paxi_wdata,
    output wire [31:0]  paxi_wstrb,
    output wire         paxi_wvalid,
    output wire         paxi_wlast,
    input  wire         paxi_wready,
    output wire [26:0]  paxi_araddr,
    output wire         paxi_arvalid,
    input  wire         paxi_arready,
    input  wire [255:0] paxi_rdata,
    input  wire         paxi_rlast,
    input  wire         paxi_rvalid,
    output wire         paxi_rready
);
    // ---------------------------------------------------------- write request
    wire        wf_wready;
    wire        wf_rvalid;
    wire [282:0] wf_rdata;
    reg         wf_pop;

    wire wf_push = s_awvalid && s_wvalid;
    assign s_awready = wf_wready && s_wvalid;
    assign s_wready  = s_awready;

    capture_async_fifo #(.WIDTH(283), .ADDR_BITS(5)) u_wf (
        .rst_n   (rst_n),
        .wclk    (clk_a1),
        .w_valid (wf_push),
        .w_data  ({s_awaddr[26:0], s_wdata}),
        .w_ready (wf_wready),
        .rclk    (clk_ddr),
        .r_valid (wf_rvalid),
        .r_data  (wf_rdata),
        .r_ready (wf_pop)
    );

    // ----------------------------------------------------------- read request
    wire        af_wready;
    wire        af_rvalid;
    wire [26:0] af_rdata;
    wire        af_pop;

    assign s_arready = af_wready;

    capture_async_fifo #(.WIDTH(27), .ADDR_BITS(4)) u_af (
        .rst_n   (rst_n),
        .wclk    (clk_a1),
        .w_valid (s_arvalid),
        .w_data  (s_araddr[26:0]),
        .w_ready (af_wready),
        .rclk    (clk_ddr),
        .r_valid (af_rvalid),
        .r_data  (af_rdata),
        .r_ready (af_pop)
    );

    // -------------------------------------------------------------- read data
    wire         rf_wready;
    wire         rf_rvalid;
    wire [255:0] rf_rdata;

    // Board-integration output register: isolate the ERAM clk2q read data from
    // the frozen slot store's wide read-data/duplicate comparator. One-deep
    // skid register, same handshake, no protocol/order change.
    reg  [255:0] s_rdata_r;
    reg          s_rvalid_r;
    wire         s_load = rf_rvalid && (!s_rvalid_r || s_rready);
    wire         rf_pop = s_load;

    capture_async_fifo #(.WIDTH(256), .ADDR_BITS(4)) u_rf (
        .rst_n   (rst_n),
        .wclk    (clk_ddr),
        .w_valid (paxi_rvalid),
        .w_data  (paxi_rdata),
        .w_ready (rf_wready),
        .rclk    (clk_a1),
        .r_valid (rf_rvalid),
        .r_data  (rf_rdata),
        .r_ready (rf_pop)
    );

    always @(posedge clk_a1 or negedge rst_n) begin
        if (!rst_n) begin
            s_rdata_r <= 256'd0;
            s_rvalid_r <= 1'b0;
        end else if (s_load) begin
            s_rdata_r <= rf_rdata;
            s_rvalid_r <= 1'b1;
        end else if (s_rvalid_r && s_rready) begin
            s_rvalid_r <= 1'b0;
        end
    end

    assign s_rdata  = s_rdata_r;
    assign s_rvalid = s_rvalid_r;
    assign paxi_rready = rf_wready;

    // ------------------------------------------------- DDR-side write engine
    localparam [1:0] W_IDLE = 2'd0, W_RUN = 2'd1;
    reg [1:0] wstate;
    reg       aw_seen, w_seen;

    assign paxi_awaddr  = wf_rdata[282:256];
    assign paxi_wdata   = wf_rdata[255:0];
    assign paxi_wstrb   = 32'hFFFF_FFFF;   // every store word is a full 32-byte beat
    assign paxi_wlast   = 1'b1;            // single-beat transaction
    assign paxi_awvalid = (wstate == W_RUN) && !aw_seen;
    assign paxi_wvalid  = (wstate == W_RUN) && !w_seen;

    always @(posedge clk_ddr or negedge rst_n) begin
        if (!rst_n) begin
            wstate <= W_IDLE; aw_seen <= 1'b0; w_seen <= 1'b0; wf_pop <= 1'b0;
        end else begin
            wf_pop <= 1'b0;
            case (wstate)
                W_IDLE: begin
                    aw_seen <= 1'b0;
                    w_seen  <= 1'b0;
                    if (wf_rvalid && ddr_rdy) wstate <= W_RUN;
                end
                W_RUN: begin
                    if (paxi_awvalid && paxi_awready) aw_seen <= 1'b1;
                    if (paxi_wvalid  && paxi_wready ) w_seen  <= 1'b1;
                    if ((aw_seen || (paxi_awvalid && paxi_awready)) &&
                        (w_seen  || (paxi_wvalid  && paxi_wready ))) begin
                        wf_pop <= 1'b1;
                        wstate <= W_IDLE;
                    end
                end
                default: wstate <= W_IDLE;
            endcase
        end
    end

    // -------------------------------------------------- DDR-side read engine
    reg ar_pending;

    assign paxi_araddr  = af_rdata;
    assign paxi_arvalid = af_rvalid && !ar_pending;
    assign af_pop       = af_rvalid && paxi_arready && ddr_rdy;

    always @(posedge clk_ddr or negedge rst_n) begin
        if (!rst_n) ar_pending <= 1'b0;
        else if (af_pop) ar_pending <= 1'b1;
        else if (paxi_rvalid && paxi_rready) ar_pending <= 1'b0;
    end
endmodule

