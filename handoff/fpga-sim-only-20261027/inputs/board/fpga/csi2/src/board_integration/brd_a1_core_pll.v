`timescale 1ns/1ps
// =============================================================================
// brd_a1_core_pll.v -- clk_core = 150.000 MHz from the 50 MHz board oscillator.
//
// Same PH1P PLL parameter wrapper the camera/HDMI PLL uses (an IP source file,
// not a regenerated IP), frozen configuration:
//   VCO = 50 MHz / REFCLK_DIV(3) * FBCLK_DIV(90) = 1500 MHz
//   clk0 = VCO / 10 = 150.000 MHz exactly  (guide 4/5 default gear)
// Only clk0 is enabled, no dynamic reconfiguration.
//
// 125 MHz alternative (guide 5, gear 2) would be VCO 1500 / 12 with
// CLKC0_DIV=12, CLKC0_CPHASE=11, CLKC0_DUTY_INT=6 -- kept as a comment so the
// change stays a one-file edit and never touches the P4 sources.
// 166.667 MHz (gear 3) would be VCO 1500 / 9 (CLKC0_DIV=9, CPHASE=8, DUTY_INT=4).
// =============================================================================
module brd_a1_core_pll (
    input  wire refclk,
    input  wire reset,
    output wire clk_out,
    output wire lock
);
    wire clk0_raw;

    PH1P_LOGIC_BUFG bufg_core (.i(clk0_raw), .o(clk_out));

    ph1p_phy_pll_wrapper_raw10_clocks #(
        .FBKCLK                ("VCO_PHASE0"),
        .FBKCLK_INT            ("VCO_PHASE0"),
        .FIN                   ("50.000000000"),
        .REFCLK_DIV            (3),
        .FBCLK_DIV             (90),
        .CLKC0_ENABLE          ("ENABLE"),
        .CLKC0_DIV             (10),
        .CLKC0_CPHASE          (9),
        .CLKC0_FPHASE          (0),
        .CLKC0_FPHASE_RSTSEL   (0),
        .CLKC0_DUTY50          ("ENABLE"),
        .CLKC0_DUTY_INT        (5),
        .CLKC1_ENABLE          ("DISABLE"),
        .CLKC2_ENABLE          ("DISABLE"),
        .PLL_USR_RST           ("ENABLE"),
        .PLL_FEED_TYPE         ("EXTERNAL"),
        .PLL_FASTLOOP          ("DISABLE"),
        .LPF_RES               (3),
        .LPF_CAP               (16),
        .ICP_CUR               (0),
        .FRAC_ENABLE           ("ENABLE"),
        .SDM_FRAC              (0),
        .PHASE_PATH_SEL        (0),
        .DYN_PHASE_PATH_SEL    ("DISABLE"),
        .DYN_FPHASE_EN         ("DISABLE"),
        .PI_OUT_SEL            ("NORMAL"),
        .PI_FRAC_EN            ("DISABLE"),
        .CLKC0_PI_SHIFT_EN     ("DISABLE"),
        .FEEDBK_MODE           ("NOCOMP"),
        .DYN_CPHASE_EN         ("DISABLE")
    ) u_pll (
        .refclk      (refclk),
        .fbclk       (1'b0),
        .reset       (reset),
        .lock        (lock),
        .clk0_en     (1'b1),
        .clk0_out    (clk0_raw),
        .clkb0_out   (),
        .clk1_en     (1'b0),
        .clk1_out    (),
        .clkb1_out   (),
        .clk2_en     (1'b0),
        .clk2_out    (),
        .clkb2_out   (),
        .clk3_en     (1'b0),
        .clk3_out    (),
        .clkb3_out   (),
        .clk4_en     (1'b0),
        .clk4_out    (),
        .clkb4_out   (),
        .clk5_en     (1'b0),
        .clk5_out    (),
        .clkb5_out   (),
        .clk6_en     (1'b0),
        .clk6_out    (),
        .clkb6_out   (),
        .drp_clk     (1'b0),
        .drp_rstn    (1'b1),
        .drp_sel     (1'b0),
        .drp_rd      (1'b0),
        .drp_wr      (1'b0),
        .drp_addr    (8'd0),
        .drp_wdata   (8'd0),
        .drp_err     (),
        .drp_rdy     (),
        .drp_rdata   (),
        .psclk       (1'b0),
        .psclksel    (3'd0),
        .psstep      (1'b0),
        .psdown      (1'b0),
        .cps_step    (1'b0),
        .psdone      (),
        .ssc_reset   (1'b0),
        .clkc_rst    (2'b00),
        .pllpd       (1'b0),
        .wakeup      (1'b1),
        .refclk_rst  (1'b0)
    );
endmodule
