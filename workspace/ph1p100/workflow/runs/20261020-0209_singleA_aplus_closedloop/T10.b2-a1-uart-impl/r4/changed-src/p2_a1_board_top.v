`timescale 1ps/1ps
// =============================================================================
// p2_a1_board_top.v -- P2 board candidate top (single-A board chain).
//
//   IMX415 A (MIPI-A, 4K RAW10, byte clock 111.375 MHz)
//     -> f9p_camera_display_core (unchanged camera front end; P2 copy only
//        exposes the existing raw tap and drives HDMI from its own preview/TPG)
//     -> P1 camera_a1_uart_top (crop 1920x1080 -> CDC -> raw DDR slot store ->
//        A+ core bf6af390 -> compressed store -> UART 115200 export)
//     -> p2_ddr_bridge (single-beat 256-bit PAXI, 187.5 MHz -> dhi_clk)
//     -> ddrmc_x32 DDR3-1600 (APB initialised by the board MCU ROM)
//
// Clocks: 50 MHz board osc (H4) -> PLL 187.5 MHz A+ / 148.5+742.5 HDMI /
//         27 MHz sensor MCLK; MIPI byte clock 111.375 MHz; dhi_clk DDR user.
// UART:   clk_uart = clk_a1 (187.5 MHz), UART_DIV=1628 -> 115.172 kbaud.
// Reset:  power-on counter -> PLL lock -> ddrphy_rdy; each domain has its own
//         reset synchronizer.  P1 RTL is byte-identical to the frozen r3 set.
// No bitgen/download is implied by this file.
// =============================================================================
`define USR_MCU_ROM_INIT "T:/src/vendor/rtl/usr_mcu_srcs/mcu_rom/mcu_rom.txt"

module p2_a1_board_top (
    input  wire         sys_rst_n,
    input  wire         sys_clk50m,
    output wire         O_uart_txd,
    input  wire         usr_uart_rxd,
    output wire [3:0]   O_led,

    // DDR3 (PH1P100SBG484 x32)
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
    inout  wire [3:0]   ddr_dm,

    // MIPI-A / MIPI-B
    input  wire         mipi_a_clk_hs_p,
    input  wire         mipi_a_clk_hs_n,
    input  wire [3:0]   mipi_a_data_hs_p,
    input  wire [3:0]   mipi_a_data_hs_n,
    input  wire         mipi_b_clk_hs_p,
    input  wire         mipi_b_clk_hs_n,
    input  wire [3:0]   mipi_b_data_hs_p,
    input  wire [3:0]   mipi_b_data_hs_n,

    // sensor control (A used, B pinned/disabled)
    output wire         cam_a_scl,
    inout  wire         cam_a_sda,
    output wire         cam_a_mclk,
    output wire         cam_a_xclr_n,
    output wire         cam_b_scl,
    inout  wire         cam_b_sda,
    output wire         cam_b_mclk,
    output wire         cam_b_xclr_n,

    // HDMI (148.5 MHz pixel / 742.5 MHz serial)
    output wire         O_hdmi_clk_p,
    output wire [2:0]   O_hdmi_tx_p
);

    // ---------------------------------------------------------------- power-on
    reg [19:0] pwr_cnt;
    reg        boot_rst_n;
    always @(posedge sys_clk50m) begin
        if (pwr_cnt != 20'hF_FFFF) begin
            pwr_cnt   <= pwr_cnt + 20'd1;
            boot_rst_n <= 1'b0;
        end else begin
            boot_rst_n <= 1'b1;
        end
    end
    wire por_n = sys_rst_n & boot_rst_n;

    // ------------------------------------------------------------- A+ 187.5 PLL
    wire clk_a1, lock_a1;
    p2_a1_pll u_a1_pll (
        .refclk  (sys_clk50m),
        .reset   (~por_n),
        .clk_out (clk_a1),
        .lock    (lock_a1)
    );

    // ---------------------------------------------------- camera front end
    wire [39:0] a_pixel;
    wire        a_pixel_valid, a_in_line, a_in_frame, a_vsync;
    wire        a_byte_clk;

    f9p_camera_display_core u_camera (
        .cap_frame_end   (),
        .cap_frame_good  (),
        .cap_frame_abort (),
        .display_pclk    (),
        .display_rst_n   (),
        .display_vs      (),
        .display_hs      (),
        .display_de      (),
        .cap_clk         (),
        .cap_sof         (),
        .cap_valid       (),
        .cap_last        (),
        .cap_data        (),
        .o_a_pixel       (a_pixel),
        .o_a_pixel_valid (a_pixel_valid),
        .o_a_in_line     (a_in_line),
        .o_a_in_frame    (a_in_frame),
        .o_a_vsync       (a_vsync),
        .o_a_byte_clk    (a_byte_clk),
        .sys_clk50m      (sys_clk50m),
        .mipi_a_clk_hs_p (mipi_a_clk_hs_p),
        .mipi_a_clk_hs_n (mipi_a_clk_hs_n),
        .mipi_a_data_hs_p(mipi_a_data_hs_p),
        .mipi_a_data_hs_n(mipi_a_data_hs_n),
        .mipi_b_clk_hs_p (mipi_b_clk_hs_p),
        .mipi_b_clk_hs_n (mipi_b_clk_hs_n),
        .mipi_b_data_hs_p(mipi_b_data_hs_p),
        .mipi_b_data_hs_n(mipi_b_data_hs_n),
        .cam_a_scl       (cam_a_scl),
        .cam_a_sda       (cam_a_sda),
        .cam_a_mclk      (cam_a_mclk),
        .cam_a_xclr_n    (cam_a_xclr_n),
        .cam_b_scl       (cam_b_scl),
        .cam_b_sda       (cam_b_sda),
        .cam_b_mclk      (cam_b_mclk),
        .cam_b_xclr_n    (cam_b_xclr_n),
        .O_led           (),
        .O_uart_txd      (),
        .O_hdmi_clk_p    (O_hdmi_clk_p),
        .O_hdmi_tx_p     (O_hdmi_tx_p)
    );

    // The camera byte clock is the PHY output; recover it as a clock port.
    // (f9p_camera_display_core's internal w_a_byte_clk is not a module port, so
    //  the P2 copy exports it through a dedicated output added below.)

    // ------------------------------------------------------------- DDR controller
    wire dhi_clk, cfg_clk, ddrphy_rst_n, ddrphy_rdy;
    wire [31:0] usr_apb_paddr, usr_apb_pwdata, usr_apb_prdata;
    wire        usr_apb_psel, usr_apb_penable, usr_apb_pwrite, usr_apb_pready;

    wire [26:0]  paxi_awaddr, paxi_araddr;
    wire         paxi_awvalid, paxi_awready, paxi_wvalid, paxi_wready;
    wire [255:0] paxi_wdata, paxi_rdata;
    wire [31:0]  paxi_wstrb;
    wire         paxi_wlast, paxi_arvalid, paxi_arready, paxi_rlast, paxi_rvalid, paxi_rready;

    p2_ddrmc_shell u_ddrmc_test_top (
        .ref_clk          (sys_clk50m),
        .sys_rst_n        (sys_rst_n),
        .dhi_clk          (dhi_clk),
        .cfg_clk          (cfg_clk),
        .ddrphy_rst_n     (ddrphy_rst_n),
        .ddrphy_rdy       (ddrphy_rdy),
        .usr_apb_pclk     (cfg_clk),
        .usr_apb_preset_n (ddrphy_rst_n),
        .usr_apb_psel     (usr_apb_psel),
        .usr_apb_penable  (usr_apb_penable),
        .usr_apb_pwrite   (usr_apb_pwrite),
        .usr_apb_paddr    (usr_apb_paddr),
        .usr_apb_pwdata   (usr_apb_pwdata),
        .usr_apb_pready   (usr_apb_pready),
        .usr_apb_prdata   (usr_apb_prdata),
        .paxi_awaddr      (paxi_awaddr),
        .paxi_awvalid     (paxi_awvalid),
        .paxi_awready     (paxi_awready),
        .paxi_wdata       (paxi_wdata),
        .paxi_wstrb       (paxi_wstrb),
        .paxi_wvalid      (paxi_wvalid),
        .paxi_wlast       (paxi_wlast),
        .paxi_wready      (paxi_wready),
        .paxi_araddr      (paxi_araddr),
        .paxi_arvalid     (paxi_arvalid),
        .paxi_arready     (paxi_arready),
        .paxi_rdata       (paxi_rdata),
        .paxi_rlast       (paxi_rlast),
        .paxi_rvalid      (paxi_rvalid),
        .paxi_rready      (paxi_rready),
        .ddr_ck_p         (ddr_ck_p),
        .ddr_ck_n         (ddr_ck_n),
        .ddr_reset_n      (ddr_reset_n),
        .ddr_cke          (ddr_cke),
        .ddr_odt          (ddr_odt),
        .ddr_cs_n         (ddr_cs_n),
        .ddr_ras_n        (ddr_ras_n),
        .ddr_cas_n        (ddr_cas_n),
        .ddr_we_n         (ddr_we_n),
        .ddr_ba           (ddr_ba),
        .ddr_addr         (ddr_addr),
        .ddr_dqs_p        (ddr_dqs_p),
        .ddr_dqs_n        (ddr_dqs_n),
        .ddr_dq           (ddr_dq),
        .ddr_dm           (ddr_dm)
    );

    // ------------------------------------------------------------ board MCU (DDR init)
    wire [31:0] o_reg_w_00, o_reg_w_04, o_reg_w_08, o_reg_w_0c;

    usr_mcu_wrapper #(
        .MCU_TCM_INIT ( `USR_MCU_ROM_INIT ),
        .CLK_FREQ     (50_000_000)
    ) u_usr_mcu_wrapper (
        .i_clk         (cfg_clk),
        .i_rst         (!ddrphy_rst_n),
        .o_apb_psel    (usr_apb_psel),
        .o_apb_penable (usr_apb_penable),
        .o_apb_pwrite  (usr_apb_pwrite),
        .o_apb_paddr   (usr_apb_paddr),
        .o_apb_pwdata  (usr_apb_pwdata),
        .i_apb_prdata  (usr_apb_prdata),
        .i_apb_pready  (usr_apb_pready),
        .o_uart_txd    (),
        .i_uart_rxd    (usr_uart_rxd),
        .o_gpio_w00    (o_reg_w_00),
        .o_gpio_w04    (o_reg_w_04),
        .o_gpio_w08    (o_reg_w_08),
        .o_gpio_w0c    (o_reg_w_0c),
        .i_gpio_r20    (32'h20240401),
        .i_gpio_r24    (32'h20240402),
        .i_gpio_r28    (32'h20240403),
        .i_gpio_r2c    (32'h20240404)
    );

    // ------------------------------------------------------- A1 reset / DDR ready
    (* ASYNC_REG = "TRUE" *) reg [1:0] ddr_rdy_sync_a1;
    always @(posedge clk_a1 or negedge sys_rst_n) begin
        if (!sys_rst_n) ddr_rdy_sync_a1 <= 2'b00;
        else        ddr_rdy_sync_a1 <= {ddr_rdy_sync_a1[0], ddrphy_rdy};
    end
    (* ASYNC_REG = "TRUE" *) reg [2:0] a1_rst_sync;
    always @(posedge clk_a1 or negedge sys_rst_n) begin
        if (!sys_rst_n) a1_rst_sync <= 3'b000;
        else        a1_rst_sync <= {a1_rst_sync[1:0], (lock_a1 && ddr_rdy_sync_a1[1])};
    end
    wire a1_rst_n = a1_rst_sync[2];

    // --------------------------------------------------------------- P1 A1 chain
    wire [31:0] a1_awaddr, a1_araddr;
    wire        a1_awvalid, a1_awready, a1_wvalid, a1_wready;
    wire [255:0] a1_wdata, a1_rdata;
    wire        a1_arvalid, a1_arready, a1_rvalid, a1_rready;

    (* MARK_DEBUG = "true" *) wire [31:0] dbg_cap_frames;
    (* MARK_DEBUG = "true" *) wire [31:0] dbg_enc_frames;
    (* MARK_DEBUG = "true" *) wire [31:0] dbg_exported;
    (* MARK_DEBUG = "true" *) wire [31:0] dbg_export_bytes;
    (* MARK_DEBUG = "true" *) wire [31:0] dbg_raw_pub;
    (* MARK_DEBUG = "true" *) wire [31:0] dbg_raw_drop;
    (* MARK_DEBUG = "true" *) wire [31:0] dbg_cmp_drop;
    (* MARK_DEBUG = "true" *) wire [31:0] dbg_geom_err;
    (* MARK_DEBUG = "true" *) wire [31:0] dbg_errors;
    (* MARK_DEBUG = "true" *) wire [31:0] dbg_read_words;
    (* MARK_DEBUG = "true" *) wire [31:0] dbg_dup_words;

    camera_a1_uart_top #(
        .UART_DIV (1628),
        .HB_DIV   (4194304)     // ~44.7 Hz 0x55 idle beacon on clk_a1 (187.5 MHz)
    ) u_a1 (
        .clk_cam             (a_byte_clk),
        .clk_a1              (clk_a1),
        .clk_uart            (clk_a1),
        .rst_n               (a1_rst_n),
        .i_a_pixel           (a_pixel),
        .i_a_pixel_valid     (a_pixel_valid),
        .i_a_in_line         (a_in_line),
        .i_a_in_frame        (a_in_frame),
        .i_a_vsync           (a_vsync),
        .o_ddr_awaddr        (a1_awaddr),
        .o_ddr_awvalid       (a1_awvalid),
        .o_ddr_awready       (a1_awready),
        .o_ddr_wdata         (a1_wdata),
        .o_ddr_wvalid        (a1_wvalid),
        .o_ddr_wready        (a1_wready),
        .o_ddr_araddr        (a1_araddr),
        .o_ddr_arvalid       (a1_arvalid),
        .o_ddr_arready       (a1_arready),
        .i_ddr_rdata         (a1_rdata),
        .i_ddr_rvalid        (a1_rvalid),
        .o_ddr_rready        (a1_rready),
        .o_uart_txd          (O_uart_txd),
        .o_dbg_byte          (),
        .o_dbg_byte_valid    (),
        .o_st_cap_frames     (dbg_cap_frames),
        .o_st_enc_frames     (dbg_enc_frames),
        .o_st_exported       (dbg_exported),
        .o_st_export_bytes   (dbg_export_bytes),
        .o_st_raw_pub        (dbg_raw_pub),
        .o_st_raw_drop       (dbg_raw_drop),
        .o_st_cmp_drop       (dbg_cmp_drop),
        .o_st_geom_err       (dbg_geom_err),
        .o_st_errors         (dbg_errors),
        .o_st_read_words     (dbg_read_words),
        .o_st_dup_words      (dbg_dup_words)
    );

    // ------------------------------------------------------- 187.5 -> dhi_clk bridge
    p2_ddr_bridge u_bridge (
        .clk_a1       (clk_a1),
        .rst_n        (a1_rst_n),
        .s_awaddr     (a1_awaddr),
        .s_awvalid    (a1_awvalid),
        .s_awready    (a1_awready),
        .s_wdata      (a1_wdata),
        .s_wvalid     (a1_wvalid),
        .s_wready     (a1_wready),
        .s_araddr     (a1_araddr),
        .s_arvalid    (a1_arvalid),
        .s_arready    (a1_arready),
        .s_rdata      (a1_rdata),
        .s_rvalid     (a1_rvalid),
        .s_rready     (a1_rready),
        .clk_ddr      (dhi_clk),
        .ddr_rdy      (ddrphy_rdy),
        .paxi_awaddr  (paxi_awaddr),
        .paxi_awvalid (paxi_awvalid),
        .paxi_awready (paxi_awready),
        .paxi_wdata   (paxi_wdata),
        .paxi_wstrb   (paxi_wstrb),
        .paxi_wvalid  (paxi_wvalid),
        .paxi_wlast   (paxi_wlast),
        .paxi_wready  (paxi_wready),
        .paxi_araddr  (paxi_araddr),
        .paxi_arvalid (paxi_arvalid),
        .paxi_arready (paxi_arready),
        .paxi_rdata   (paxi_rdata),
        .paxi_rlast   (paxi_rlast),
        .paxi_rvalid  (paxi_rvalid),
        .paxi_rready  (paxi_rready)
    );

    // ------------------------------------------------------------ LEDs
    reg [23:0] hb_cnt;
    always @(posedge clk_a1) hb_cnt <= hb_cnt + 24'd1;
    assign O_led[0] = hb_cnt[23];
    assign O_led[1] = (dbg_exported   != 32'd0);
    assign O_led[2] = (dbg_errors     != 32'd0) ||
                      (dbg_raw_drop   != 32'd0) ||
                      (dbg_cmp_drop   != 32'd0) ||
                      (dbg_geom_err   != 32'd0);
    assign O_led[3] = (dbg_cap_frames != 32'd0);
endmodule
