`timescale 1ns/1ps
// =============================================================================
// tb_b19_camsel.sv -- T10.b19-cam-a CAM_SEL=0 structural test (C18' / T6).
// Instantiates the REAL merged p2_a1_board_top; only the PLL, DDR shell, MCU
// ROM, MIPI camera core, A1 chain and PAXI bridge are stubbed (their port lists
// are copied verbatim from the frozen sources).  The A tap is alive and the B
// tap is quiet with a different signature, so a wrong mux fails hard.
// =============================================================================
module tb_b19_camsel;
    reg   sys_rst_n;
    reg   sys_clk50m = 1'b0;
    wire  O_uart_txd;
    reg   usr_uart_rxd = 1'b0;
    wire  [3:0] O_led;
    wire  ddr_ck_p;
    wire  ddr_ck_n;
    wire  ddr_reset_n;
    wire  ddr_cke;
    wire  ddr_odt;
    wire  ddr_cs_n;
    wire  ddr_ras_n;
    wire  ddr_cas_n;
    wire  ddr_we_n;
    wire  [2:0] ddr_ba;
    wire  [13:0] ddr_addr;
    wire  [3:0] ddr_dqs_p;
    wire  [3:0] ddr_dqs_n;
    wire  [31:0] ddr_dq;
    wire  [3:0] ddr_dm;
    reg   mipi_a_clk_hs_p = 1'b0;
    reg   mipi_a_clk_hs_n = 1'b0;
    reg   [3:0] mipi_a_data_hs_p = 1'b0;
    reg   [3:0] mipi_a_data_hs_n = 1'b0;
    reg   mipi_b_clk_hs_p = 1'b0;
    reg   mipi_b_clk_hs_n = 1'b0;
    reg   [3:0] mipi_b_data_hs_p = 1'b0;
    reg   [3:0] mipi_b_data_hs_n = 1'b0;
    wire  cam_a_scl;
    wire  cam_a_sda;
    wire  cam_a_mclk;
    wire  cam_a_xclr_n;
    wire  cam_b_scl;
    wire  cam_b_sda;
    wire  cam_b_mclk;
    wire  cam_b_xclr_n;
    wire  O_hdmi_clk_p;
    wire  [2:0] O_hdmi_tx_p;

    always #10 sys_clk50m = ~sys_clk50m;   // 50 MHz board clock

    p2_a1_board_top u_top (.*);

    integer     errs = 0;
    integer     bclk_edges = 0;
    reg [31:0]  sysstat;
    reg [3:0]   lane;
    reg [39:0]  pix;

    always @(posedge sys_clk50m) bclk_edges = bclk_edges + 1;

    task fail(input [1023:0] why);
        begin
            errs = errs + 1;
            $display("B19_CAMSEL_FAIL %0s", why);
        end
    endtask

    initial begin
        #50 sys_rst_n = 1'b0;
        #500 sys_rst_n = 1'b1;
        repeat (40) @(posedge sys_clk50m);
        sysstat = u_top.u_dbg_sys_mail.i_data[63:32];
        lane    = u_top.u_dbg_sys_mail.i_data[43:40];
        $display("B19_CAMSEL_SYSSTAT=%h NACK=%h", sysstat,
                 u_top.u_dbg_sys_mail.i_data[31:0]);
        $display("B19_CAMSEL_U_A1_PIXEL=%h CLK_EDGES=%0d I_VALID=%b",
                 u_top.u_a1.i_a_pixel, bclk_edges, u_top.u_a1.i_a_pixel_valid);
        if (sysstat[12] !== 1'b0)      fail("cam_sysstat[12] (CAM_SEL) != 0");
        if (((sysstat >> 20) & 1) !== 1'b0) fail("cam_sysstat[20] != 0");
        if (lane !== 4'hF)             fail("sel_lane_sticky is not the A value");
        if (sysstat !== 32'h0000_0f1d) fail("cam_sysstat word mismatch");
        pix = u_top.u_a1.i_a_pixel;
        if (pix !== 40'hA5_A5A5_A5A5)  fail("u_a1 does not see the A tap");
        if (pix === 40'hB1_8B18_B18B)  fail("u_a1 sees the B tap, not A");
        if (u_top.sel_pixel !== 40'hA5_A5A5_A5A5) fail("sel_pixel is not A");
        if (bclk_edges < 10)           fail("selected byte clock not toggling");
        if (u_top.u_a1.i_a_pixel_valid !== 1'b1) fail("i_a_pixel_valid not A");
        $display("B19_CAMSEL_RESULT pass=%0d bit12=%0d a_selected=%0d sysstat=%h",
                 (errs == 0), sysstat[12], (pix === 40'hA5_A5A5_A5A5), sysstat);
        $finish;
    end

    initial begin
        #2000000;
        $display("B19_CAMSEL_TIMEOUT");
        $finish;
    end
endmodule
