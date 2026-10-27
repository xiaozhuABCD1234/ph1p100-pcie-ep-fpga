`timescale 1ps/1ps
// =============================================================================
// p2_ddrmc_shell.v -- DDR3 controller + APB shell for the P2 board candidate.
//
// Derived from the verified camera_ddr_display project's ddrmc_display_top.v:
// the DDR IP, APB decode and MCU-visible status register are kept identical to
// the board-verified project; the old camera-capture / display-frame-buffer
// user logic is intentionally absent so the A1 store bridge owns the PAXI port.
// The DDR IP instance name (u_ddrmc_x32) and clock structure are preserved so
// the board timing.sdc / DDR IP SDC selectors still resolve.
// =============================================================================
module p2_ddrmc_shell (
    // clock & reset
    input  wire         ref_clk,
    input  wire         sys_rst_n,
    output wire         dhi_clk,
    output wire         cfg_clk,
    output wire         ddrphy_rst_n,
    output wire         ddrphy_rdy,

    // APB (MCU -> DDR controller)
    input  wire         usr_apb_pclk,
    input  wire         usr_apb_preset_n,
    input  wire         usr_apb_psel,
    input  wire         usr_apb_penable,
    input  wire         usr_apb_pwrite,
    input  wire [31:0]  usr_apb_paddr,
    input  wire [31:0]  usr_apb_pwdata,
    output wire         usr_apb_pready,
    output wire [31:0]  usr_apb_prdata,

    // Native 256-bit single-beat PAXI (one word per AW/W pair, one word per AR)
    input  wire [26:0]  paxi_awaddr,
    input  wire         paxi_awvalid,
    output wire         paxi_awready,
    input  wire [255:0] paxi_wdata,
    input  wire [31:0]  paxi_wstrb,
    input  wire         paxi_wvalid,
    input  wire         paxi_wlast,
    output wire         paxi_wready,
    input  wire [26:0]  paxi_araddr,
    input  wire         paxi_arvalid,
    output wire         paxi_arready,
    output wire [255:0] paxi_rdata,
    output wire         paxi_rlast,
    output wire         paxi_rvalid,
    input  wire         paxi_rready,

    // ddrio
    output wire         ddr_ck_p,
    output wire         ddr_ck_n,
    output wire         ddr_reset_n,
    output wire         ddr_cke,
    output wire         ddr_odt,
    output wire         ddr_cs_n,
    output wire         ddr_ras_n,
    output wire         ddr_cas_n,
    output wire         ddr_we_n,
    output wire [2:0]   ddr_ba,
    output wire [13:0]  ddr_addr,
    inout  wire [3:0]   ddr_dqs_p,
    inout  wire [3:0]   ddr_dqs_n,
    inout  wire [31:0]  ddr_dq,
    inout  wire [3:0]   ddr_dm
);

    wire ddrphy_apb_pclk;
    wire ddrphy_apb_prst_n;
    wire ddrphy_apb_psel;
    wire ddrphy_apb_penable;
    wire ddrphy_apb_pwrite;
    wire [15:0] ddrphy_apb_paddr;
    wire [31:0] ddrphy_apb_pwdata;
    wire        ddrphy_apb_pready;
    wire [31:0] ddrphy_apb_prdata;

    ddrmc_x32 u_ddrmc_x32 (
        .ref_clk        (ref_clk),
        .dhi_clk        (dhi_clk),
        .cfg_clk        (cfg_clk),
        .sys_rst_n      (sys_rst_n),
        .ddrphy_rst_n   (ddrphy_rst_n),
        .ddrphy_rdy     (ddrphy_rdy),

        .apb_pclk       (ddrphy_apb_pclk),
        .apb_prst_n     (ddrphy_apb_prst_n),
        .apb_psel       (ddrphy_apb_psel),
        .apb_penable    (ddrphy_apb_penable),
        .apb_pwrite     (ddrphy_apb_pwrite),
        .apb_paddr      (ddrphy_apb_paddr),
        .apb_pwdata     (ddrphy_apb_pwdata),
        .apb_pready     (ddrphy_apb_pready),
        .apb_prdata     (ddrphy_apb_prdata),

        .paxi_awaddr    (paxi_awaddr),
        .paxi_awvalid   (paxi_awvalid),
        .paxi_awready   (paxi_awready),
        .paxi_wdata     (paxi_wdata),
        .paxi_wstrb     (paxi_wstrb),
        .paxi_wvalid    (paxi_wvalid),
        .paxi_wlast     (paxi_wlast),
        .paxi_wready    (paxi_wready),
        .paxi_araddr    (paxi_araddr),
        .paxi_arvalid   (paxi_arvalid),
        .paxi_arready   (paxi_arready),
        .paxi_rdata     (paxi_rdata),
        .paxi_rlast     (paxi_rlast),
        .paxi_rvalid    (paxi_rvalid),
        .paxi_rready    (paxi_rready),

        .usr_ref_type   (2'b00),
        .usr_ref_req    (1'b0),
        .usr_ref_ack    (),

        .ecc_err_sig    (),
        .ecc_err_mul    (),
        .ctl_ram_rst_n  (),
        .ctl_ram_cke    (),

        .ddr_ck_p       (ddr_ck_p),
        .ddr_ck_n       (ddr_ck_n),
        .ddr_reset_n    (ddr_reset_n),
        .ddr_cke        (ddr_cke),
        .ddr_odt        (ddr_odt),
        .ddr_cs_n       (ddr_cs_n),
        .ddr_ras_n      (ddr_ras_n),
        .ddr_cas_n      (ddr_cas_n),
        .ddr_we_n       (ddr_we_n),
        .ddr_ba         (ddr_ba),
        .ddr_addr       (ddr_addr),
        .ddr_dqs_p      (ddr_dqs_p),
        .ddr_dqs_n      (ddr_dqs_n),
        .ddr_dq         (ddr_dq),
        .ddr_dm         (ddr_dm)
    );

    // APB decode: window 0x000000-0x0FFFFF -> DDR controller, 0x100000-0x1FFFFF
    // -> read-only status. Same map the verified board project exposes to the MCU.
    assign ddrphy_apb_prst_n = usr_apb_preset_n;
    assign ddrphy_apb_psel   = usr_apb_psel && (usr_apb_paddr[23:20] == 4'h0);
    assign ddrphy_apb_penable= usr_apb_penable;
    assign ddrphy_apb_pwrite = usr_apb_pwrite;
    assign ddrphy_apb_paddr  = usr_apb_paddr[15:0];
    assign ddrphy_apb_pwdata = usr_apb_pwdata;

    wire [31:0] status_rdata;
    assign status_rdata = (usr_apb_paddr[7:0] == 8'hf0) ? 32'h5032_4131 :  // "P2A1"
                          (usr_apb_paddr[7:0] == 8'hf4) ? {31'd0, ddrphy_rdy} :
                                                          32'hdeadbeef;
    assign usr_apb_pready = (usr_apb_paddr[23:20] == 4'h0) ? ddrphy_apb_pready : 1'b1;
    assign usr_apb_prdata = (usr_apb_paddr[23:20] == 4'h0) ? ddrphy_apb_prdata :
                            (usr_apb_paddr[23:20] == 4'h1) ? status_rdata :
                                                             32'hdeadbeef;
endmodule
