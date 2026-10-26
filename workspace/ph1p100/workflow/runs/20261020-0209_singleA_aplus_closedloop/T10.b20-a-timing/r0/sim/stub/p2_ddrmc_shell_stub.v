// T10.b19-cam-a structural stub of p2_ddrmc_shell (ports copied verbatim)
module p2_ddrmc_shell (
    input         ref_clk,
    input         sys_rst_n,
    output        dhi_clk,
    output        cfg_clk,
    output        ddrphy_rst_n,
    output        ddrphy_rdy,
    input         usr_apb_pclk,
    input         usr_apb_preset_n,
    input         usr_apb_psel,
    input         usr_apb_penable,
    input         usr_apb_pwrite,
    input  [31:0] usr_apb_paddr,
    input  [31:0] usr_apb_pwdata,
    output        usr_apb_pready,
    output [31:0] usr_apb_prdata,
    input  [26:0] paxi_awaddr,
    input         paxi_awvalid,
    output        paxi_awready,
    input  [255:0] paxi_wdata,
    input  [31:0] paxi_wstrb,
    input         paxi_wvalid,
    input         paxi_wlast,
    output        paxi_wready,
    input  [26:0] paxi_araddr,
    input         paxi_arvalid,
    output        paxi_arready,
    output [255:0] paxi_rdata,
    output        paxi_rlast,
    output        paxi_rvalid,
    input         paxi_rready,
    output        ddr_ck_p,
    output        ddr_ck_n,
    output        ddr_reset_n,
    output        ddr_cke,
    output        ddr_odt,
    output        ddr_cs_n,
    output        ddr_ras_n,
    output        ddr_cas_n,
    output        ddr_we_n,
    output [2:0]  ddr_ba,
    output [13:0] ddr_addr,
    inout  [3:0]  ddr_dqs_p,
    inout  [3:0]  ddr_dqs_n,
    inout  [31:0] ddr_dq,
    inout  [3:0]  ddr_dm
);
    assign dhi_clk = ref_clk;
    assign cfg_clk = ref_clk;
    assign ddrphy_rst_n = 1'b1;
    assign ddrphy_rdy = 1'b1;
    assign usr_apb_pready = 1'b0;
    assign usr_apb_prdata = 1'b0;
    assign paxi_awready = 1'b0;
    assign paxi_wready = 1'b0;
    assign paxi_arready = 1'b0;
    assign paxi_rdata = 1'b0;
    assign paxi_rlast = 1'b0;
    assign paxi_rvalid = 1'b0;
    assign ddr_ck_p = 1'b0;
    assign ddr_ck_n = 1'b0;
    assign ddr_reset_n = 1'b0;
    assign ddr_cke = 1'b0;
    assign ddr_odt = 1'b0;
    assign ddr_cs_n = 1'b0;
    assign ddr_ras_n = 1'b0;
    assign ddr_cas_n = 1'b0;
    assign ddr_we_n = 1'b0;
    assign ddr_ba = 1'b0;
    assign ddr_addr = 1'b0;
    // inout ddr_dqs_p left open in the stub
    // inout ddr_dqs_n left open in the stub
    // inout ddr_dq left open in the stub
    // inout ddr_dm left open in the stub
endmodule
