`timescale 1ns/1ps
// =============================================================================
// p2_paxi_model.v -- behavioural single-beat 256-bit PAXI DDR model (sim only).
//
// Same contract the P2 board DDR exposes to p2_ddr_bridge: one 32-byte beat per
// AW/W pair (wstrb ignored, wlast always 1) and one 32-byte word per AR.  Both
// directions can be stalled independently, and the address FIFO is deep enough
// that a duplicate AR (the T10.b9 F3 defect) is *returned* as duplicate data
// instead of dead-locking the model, so the testbench can see it.
// =============================================================================
module p2_paxi_model #(
    parameter integer WORDS  = 262144,   // 2^18 beats, covers both raw slots
    parameter integer AR_GAP = 3,        // cycles between arready stalls
    parameter integer R_GAP  = 3         // read latency in clk_ddr cycles
) (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         rdy,

    input  wire [26:0]  awaddr,
    input  wire         awvalid,
    output wire         awready,
    input  wire [255:0] wdata,
    input  wire [31:0]  wstrb,
    input  wire         wvalid,
    input  wire         wlast,
    output wire         wready,

    input  wire [26:0]  araddr,
    input  wire         arvalid,
    output wire         arready,
    output reg  [255:0] rdata,
    output wire         rlast,
    output reg          rvalid,
    input  wire         rready,

    output reg  [31:0]  n_ar_hs,
    output reg  [31:0]  n_aw_hs,
    output reg  [31:0]  n_whs,
    output reg  [31:0]  n_r_hs
);
    reg [255:0] mem [0:WORDS-1];

    reg [7:0] tick;
    always @(posedge clk) begin
        if (!rst_n) tick <= 8'd0;
        else        tick <= tick + 8'd1;
    end

    wire aw_stall = (AR_GAP > 1) && ((tick % AR_GAP) == 0);
    wire ar_stall = (AR_GAP > 1) && ((tick % AR_GAP) == 1);

    assign awready = rst_n && !aw_stall;
    assign wready  = rst_n && !aw_stall;
    assign arready = rst_n && !ar_stall;
    assign rlast   = 1'b1;

    // ------------------------------------------------------------- write beat
    // The bridge always presents AW and W together, so one joint handshake is
    // the whole transaction.
    always @(posedge clk) begin
        if (awvalid && awready) n_aw_hs <= n_aw_hs + 32'd1;
        if (wvalid  && wready ) n_whs   <= n_whs   + 32'd1;
        if (awvalid && awready && wvalid && wready)
            mem[awaddr[17:0]] <= wdata;
    end

    // -------------------------------------------------------------- read beat
    reg [26:0] pq [0:7];
    reg [3:0]  pq_w, pq_r, pq_cnt;
    reg [26:0] raddr_r;
    reg [7:0]  rwait;
    reg        rpend;

    wire ar_hs    = arvalid && arready;
    wire start_rd = !rpend && (pq_cnt != 4'd0);
    wire ret      = rpend && (rwait <= 8'd1);

    always @(posedge clk) begin
        if (!rst_n) begin
            pq_w <= 4'd0; pq_r <= 4'd0; pq_cnt <= 4'd0;
            raddr_r <= 27'd0; rwait <= 8'd0; rpend <= 1'b0;
            rvalid <= 1'b0; rdata <= 256'd0;
            n_ar_hs <= 32'd0; n_aw_hs <= 32'd0; n_whs <= 32'd0; n_r_hs <= 32'd0;
        end else begin
            if (rvalid && rready) begin rvalid <= 1'b0; n_r_hs <= n_r_hs + 32'd1; end

            if (ar_hs) begin
                pq[pq_w[2:0]] <= araddr;
                pq_w          <= pq_w + 4'd1;
                n_ar_hs       <= n_ar_hs + 32'd1;
                if (pq_cnt >= 4'd8) $display("MODEL_PQ_OVERFLOW cnt=%0d", pq_cnt);
            end

            // one increment and one decrement can happen on the same edge
            case ({ar_hs, start_rd})
                2'b10: pq_cnt <= pq_cnt + 4'd1;
                2'b01: pq_cnt <= pq_cnt - 4'd1;
                default: pq_cnt <= pq_cnt;      // 2'b00 or 2'b11 (net zero)
            endcase

            if (start_rd) begin
                raddr_r <= pq[pq_r[2:0]];
                pq_r    <= pq_r + 4'd1;
                rwait   <= R_GAP[7:0];
                rpend   <= 1'b1;
            end else if (rpend) begin
                if (rwait <= 8'd1) begin
                    rdata  <= mem[raddr_r[17:0]];
                    rvalid <= 1'b1;
                    rpend  <= 1'b0;
                end else begin
                    rwait <= rwait - 8'd1;
                end
            end
        end
    end
    // rdy is only an input gate for the engines that read it; the memory itself
    // keeps returning accepted reads (a real DDR does the same).
    wire unused_rdy = rdy && (|wstrb) && wlast;
endmodule
