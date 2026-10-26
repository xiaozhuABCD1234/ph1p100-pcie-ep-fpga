`timescale 1ns/1ps
// =============================================================================
// a1_ddr_model.v -- behavioural DDR model for the P1 native 256-bit port.
// Sim only (never synthesised): flat 256-bit memory, 1-cycle write handshake,
// configurable ready gaps on both directions to exercise back-pressure.
// =============================================================================
module a1_ddr_model #(
    parameter integer WORDS  = 262144,
    parameter integer AW_GAP = 1,
    parameter integer R_GAP  = 1
) (
    input  wire         clk,
    input  wire         rst_n,
    input  wire [31:0]  awaddr,
    input  wire         awvalid,
    output wire         awready,
    input  wire [255:0] wdata,
    input  wire         wvalid,
    output wire         wready,
    input  wire [31:0]  araddr,
    input  wire         arvalid,
    output wire         arready,
    output reg  [255:0] rdata,
    output reg          rvalid,
    input  wire         rready
);
    reg [255:0] mem [0:WORDS-1];
    reg [15:0]  tick;
    reg [7:0]   rwait;
    reg         rpend;
    reg [31:0]  raddr_r;
    localparam [7:0] RG = (R_GAP > 1) ? R_GAP[7:0] : 8'd1;

    wire wr_stall = (AW_GAP > 1) && ((tick % AW_GAP) == 0);
    wire rd_stall = (R_GAP  > 1) && ((tick % R_GAP)  == 0);

    assign awready = rst_n && !wr_stall;
    assign wready  = rst_n && !wr_stall;
    assign arready = rst_n && !rd_stall && !rpend && !rvalid;

    always @(posedge clk) begin
        if (!rst_n) begin
            tick <= 16'd0; rwait <= 8'd0; rpend <= 1'b0; rvalid <= 1'b0;
            rdata <= 256'd0; raddr_r <= 32'd0;
        end else begin
            tick <= tick + 16'd1;
            if (awvalid && awready && wvalid && wready)
                mem[awaddr[23:0]] <= wdata;

            if (rvalid && !rready) begin
                rvalid <= 1'b1;                       // hold under back-pressure
            end else begin
                rvalid <= 1'b0;
            end

            if (rvalid && rready) rvalid <= 1'b0;

            if (arvalid && arready) begin
                raddr_r <= araddr;
                rpend   <= 1'b1;
                rwait   <= RG;
            end else if (rpend) begin
                if (rwait <= 8'd1) begin
                    rpend  <= 1'b0;
                    rdata  <= mem[raddr_r[23:0]];
                    rvalid <= 1'b1;
                end else begin
                    rwait <= rwait - 8'd1;
                end
            end
        end
    end
endmodule
