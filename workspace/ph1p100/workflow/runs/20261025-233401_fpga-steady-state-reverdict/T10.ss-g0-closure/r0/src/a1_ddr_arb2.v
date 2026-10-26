`timescale 1ns/1ps
// =============================================================================
// a1_ddr_arb2.v -- 2:1 arbiter for the P1 native 256-bit DDR port.
// Write transactions are single-cycle (aw and w handshake together); read
// transactions hold the grant until rvalid/rready.  Round-robin fairness.
// P2 replaces this with the PAXI mapping of the real DDR controller.
// =============================================================================
module a1_ddr_arb2 (
    input  wire         clk,
    input  wire         rst_n,

    input  wire [31:0]  m0_awaddr,
    input  wire         m0_awvalid,
    output wire         m0_awready,
    input  wire [255:0] m0_wdata,
    input  wire         m0_wvalid,
    output wire         m0_wready,
    input  wire [31:0]  m0_araddr,
    input  wire         m0_arvalid,
    output wire         m0_arready,
    output wire [255:0] m0_rdata,
    output wire         m0_rvalid,
    input  wire         m0_rready,

    input  wire [31:0]  m1_awaddr,
    input  wire         m1_awvalid,
    output wire         m1_awready,
    input  wire [255:0] m1_wdata,
    input  wire         m1_wvalid,
    output wire         m1_wready,
    input  wire [31:0]  m1_araddr,
    input  wire         m1_arvalid,
    output wire         m1_arready,
    output wire [255:0] m1_rdata,
    output wire         m1_rvalid,
    input  wire         m1_rready,

    output wire [31:0]  s_awaddr,
    output wire         s_awvalid,
    input  wire         s_awready,
    output wire [255:0] s_wdata,
    output wire         s_wvalid,
    input  wire         s_wready,
    output wire [31:0]  s_araddr,
    output wire         s_arvalid,
    input  wire         s_arready,
    input  wire [255:0] s_rdata,
    input  wire         s_rvalid,
    output wire         s_rready
);
    reg wr_last;   // last granted write master
    reg rd_busy;
    reg rd_owner;  // master owning the outstanding read
    reg rd_last;

    wire req0 = m0_awvalid && m0_wvalid;
    wire req1 = m1_awvalid && m1_wvalid;
    wire g0w  = req0 && (!req1 || wr_last);
    wire g1w  = req1 && (!req0 || !wr_last);
    wire wr_ok = s_awready && s_wready;

    assign m0_awready = g0w && wr_ok;
    assign m0_wready  = g0w && wr_ok;
    assign m1_awready = g1w && wr_ok;
    assign m1_wready  = g1w && wr_ok;

    assign s_awvalid  = (g0w && m0_awvalid) || (g1w && m1_awvalid);
    assign s_wvalid   = s_awvalid;
    assign s_awaddr   = g0w ? m0_awaddr : m1_awaddr;
    assign s_wdata    = g0w ? m0_wdata  : m1_wdata;

    wire g0r = !rd_busy && m0_arvalid && (!m1_arvalid || rd_last);
    wire g1r = !rd_busy && m1_arvalid && (!m0_arvalid || !rd_last);

    assign m0_arready = g0r && s_arready;
    assign m1_arready = g1r && s_arready;
    assign s_arvalid  = g0r || g1r;
    assign s_araddr   = rd_busy ? (rd_owner ? m1_araddr : m0_araddr)
                                : (g1r ? m1_araddr : m0_araddr);

    assign s_rready   = rd_busy ? (rd_owner ? m1_rready : m0_rready) : 1'b0;
    assign m0_rvalid  = s_rvalid && rd_busy && !rd_owner;
    assign m1_rvalid  = s_rvalid && rd_busy &&  rd_owner;
    assign m0_rdata   = s_rdata;
    assign m1_rdata   = s_rdata;

    always @(posedge clk) begin
        if (!rst_n) begin
            wr_last <= 1'b1;
            rd_busy <= 1'b0;
            rd_owner <= 1'b0;
            rd_last <= 1'b1;
        end else begin
            if (s_awvalid && wr_ok) wr_last <= g0w ? 1'b0 : 1'b1;
            if (s_arvalid && s_arready && !rd_busy) begin
                rd_busy  <= 1'b1;
                rd_owner <= g1r;
            end
            if (s_rvalid && s_rready) begin
                rd_busy <= 1'b0;
                rd_last <= rd_owner;
            end
        end
    end
endmodule
