`timescale 1ns/1ps
// Authored diagnostic wrapper over the existing generated PH1P PLL wrapper.
// Same fractional VCO as raw10_clocks; only output divisors differ.
// FULL_RATE=0: 74.25/371.25 MHz; FULL_RATE=1: 148.5/742.5 MHz.
// Not a regenerated IP. Original generated sources remain unchanged.
module hdmi_diagnostic_clocks #(parameter FULL_RATE=0)
    (input refclk,reset,output clk0_out,clk1_out,lock);
    wire pixel_raw;
    PH1P_LOGIC_BUFG bufg_c0(.i(pixel_raw),.o(clk0_out));
    ph1p_phy_pll_wrapper_raw10_clocks #(
        .FBKCLK("VCO_PHASE0"),.FBKCLK_INT("VCO_PHASE0"),.FIN("50.000000000"),
        .REFCLK_DIV(3),.FBCLK_DIV(89),
        .CLKC0_ENABLE("ENABLE"),.CLKC0_DIV(FULL_RATE?10:20),
        .CLKC0_CPHASE(FULL_RATE?9:19),.CLKC0_FPHASE(0),.CLKC0_FPHASE_RSTSEL(0),
        .CLKC0_DUTY50("ENABLE"),.CLKC0_DUTY_INT(FULL_RATE?5:10),
        .CLKC1_ENABLE("ENABLE"),.CLKC1_DIV(FULL_RATE?2:4),
        .CLKC1_CPHASE(FULL_RATE?1:3),.CLKC1_FPHASE(0),.CLKC1_FPHASE_RSTSEL(0),
        .CLKC1_DUTY50("ENABLE"),.CLKC1_DUTY_INT(FULL_RATE?1:2),
        .PLL_USR_RST("ENABLE"),.PLL_FEED_TYPE("EXTERNAL"),.PLL_FASTLOOP("DISABLE"),
        .LPF_RES(3),.LPF_CAP(16),.ICP_CUR(0),.FRAC_ENABLE("ENABLE"),.SDM_FRAC(1677722),
        .PHASE_PATH_SEL(0),.DYN_PHASE_PATH_SEL("DISABLE"),.DYN_FPHASE_EN("DISABLE"),
        .PI_OUT_SEL("NORMAL"),.PI_FRAC_EN("DISABLE"),.CLKC0_PI_SHIFT_EN("DISABLE"),
        .FEEDBK_MODE("NOCOMP"),.DYN_CPHASE_EN("DISABLE")
    ) pll (.refclk(refclk),.fbclk(1'b0),.reset(reset),.lock(lock),
        .clk0_en(1'b1),.clk0_out(pixel_raw),.clkb0_out(),
        .clk1_en(1'b1),.clk1_out(clk1_out),.clkb1_out(),
        .clk2_en(1'b0),.clk2_out(),.clkb2_out(),
        .clk3_en(1'b0),.clk3_out(),.clkb3_out(),
        .clk4_en(1'b0),.clk4_out(),.clkb4_out(),
        .clk5_en(1'b0),.clk5_out(),.clkb5_out(),
        .clk6_en(1'b0),.clk6_out(),.clkb6_out(),
        .drp_clk(1'b0),.drp_rstn(1'b1),.drp_sel(1'b0),.drp_rd(1'b0),.drp_wr(1'b0),
        .drp_addr(8'd0),.drp_wdata(8'd0),.drp_err(),.drp_rdy(),.drp_rdata(),
        .psclk(1'b0),.psclksel(3'd0),.psstep(1'b0),.psdown(1'b0),.cps_step(1'b0),.psdone(),
        .ssc_reset(1'b0),.clkc_rst(2'b00),.pllpd(1'b0),.wakeup(1'b1),.refclk_rst(1'b0));
endmodule
