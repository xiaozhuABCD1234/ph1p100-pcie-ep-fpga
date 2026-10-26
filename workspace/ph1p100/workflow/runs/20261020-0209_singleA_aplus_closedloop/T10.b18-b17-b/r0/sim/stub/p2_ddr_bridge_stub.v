// T10.b18-b17-b structural stub of p2_ddr_bridge (ports copied verbatim)
module p2_ddr_bridge #(
    
    
    parameter integer ALLOW_CONCURRENT = 0
) (
    input         clk_a1,
    input         rst_n,
    input  [31:0] s_awaddr,
    input         s_awvalid,
    output        s_awready,
    input  [255:0] s_wdata,
    input         s_wvalid,
    output        s_wready,
    input  [31:0] s_araddr,
    input         s_arvalid,
    output        s_arready,
    output [255:0] s_rdata,
    output        s_rvalid,
    input         s_rready,
    input         rd_abort,
    input         clk_ddr,
    input         ddr_rdy,
    output [26:0] paxi_awaddr,
    output        paxi_awvalid,
    input         paxi_awready,
    output [255:0] paxi_wdata,
    output [31:0] paxi_wstrb,
    output        paxi_wvalid,
    output        paxi_wlast,
    input         paxi_wready,
    output [26:0] paxi_araddr,
    output        paxi_arvalid,
    input         paxi_arready,
    input  [255:0] paxi_rdata,
    input         paxi_rlast,
    input         paxi_rvalid,
    output        paxi_rready,
    output [511:0] dbg_a1
);
    assign s_awready = 1'b0;
    assign s_wready = 1'b0;
    assign s_arready = 1'b0;
    assign s_rdata = 1'b0;
    assign s_rvalid = 1'b0;
    assign paxi_awaddr = 1'b0;
    assign paxi_awvalid = 1'b0;
    assign paxi_wdata = 1'b0;
    assign paxi_wstrb = 1'b0;
    assign paxi_wvalid = 1'b0;
    assign paxi_wlast = 1'b0;
    assign paxi_araddr = 1'b0;
    assign paxi_arvalid = 1'b0;
    assign paxi_rready = 1'b0;
    assign dbg_a1 = 1'b0;
endmodule
