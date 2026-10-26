// T10.b18-b17-b structural stub of f9p_camera_display_core (ports copied verbatim)
module f9p_camera_display_core (
    output        cap_frame_end,
    output        cap_frame_good,
    output        cap_frame_abort,
    output        display_pclk,
    output        display_rst_n,
    output        display_vs,
    output        display_hs,
    output        display_de,
    output        cap_clk,
    output        cap_sof,
    output        cap_valid,
    output        cap_last,
    output [7:0]  cap_data,
    output [39:0] o_a_pixel,
    output        o_a_pixel_valid,
    output        o_a_in_line,
    output        o_a_in_frame,
    output        o_a_vsync,
    output        o_a_byte_clk,
    output        o_dbg_a_cfg_done,
    output        o_dbg_a_bus_err_lat,
    output [31:0] o_dbg_a_nack_cnt,
    output [3:0]  o_dbg_a_lane_sticky,
    output [5:0]  o_dbg_a_delay_tap,
    output        o_dbg_a_delay_done,
    output        o_dbg_a_rst_out,
    output        o_dbg_a_sync_wait,
    output        o_dbg_a_pkt_tgl,
    output        o_dbg_a_vs_tgl,
    output        o_dbg_a_clk_tgl,
    output        o_dbg_a_in_frame,
    output        o_dbg_a_vsync,
    output        o_dbg_xclr_n,
    output        o_dbg_pll_locked,
    output        o_dbg_cfg_rst_n,
    output [39:0] o_b_pixel,
    output        o_b_pixel_valid,
    output        o_b_in_line,
    output        o_b_in_frame,
    output        o_b_vsync,
    output        o_b_byte_clk,
    output        o_dbg_b_cfg_done,
    output        o_dbg_b_bus_err_lat,
    output [31:0] o_dbg_b_nack_cnt,
    output [3:0]  o_dbg_b_lane_sticky,
    output [5:0]  o_dbg_b_delay_tap,
    output        o_dbg_b_delay_done,
    output        o_dbg_b_rst_out,
    output        o_dbg_b_sync_wait,
    output        o_dbg_b_pkt_tgl,
    output        o_dbg_b_vs_tgl,
    output        o_dbg_b_clk_tgl,
    output        o_dbg_b_in_frame,
    output        o_dbg_b_vsync,
    output [31:0] o_dbg_b_good_frames,
    output [31:0] o_dbg_b_bad_frames,
    output [31:0] o_dbg_b_crc_errors,
    output [31:0] o_dbg_b_header_errors,
    output [15:0] o_dbg_b_last_wc,
    output [15:0] o_dbg_b_last_lines,
    input         sys_clk50m,
    input         mipi_a_clk_hs_p,
    input         mipi_a_clk_hs_n,
    input  [3:0]  mipi_a_data_hs_p,
    input  [3:0]  mipi_a_data_hs_n,
    input         mipi_b_clk_hs_p,
    input         mipi_b_clk_hs_n,
    input  [3:0]  mipi_b_data_hs_p,
    input  [3:0]  mipi_b_data_hs_n,
    output        cam_a_scl,
    inout         cam_a_sda,
    output        cam_a_mclk,
    output        cam_a_xclr_n,
    output        cam_b_scl,
    inout         cam_b_sda,
    output        cam_b_mclk,
    output        cam_b_xclr_n,
    output [3:0]  O_led,
    output        O_uart_txd,
    output        O_hdmi_clk_p,
    output [2:0]  O_hdmi_tx_p
);
    assign cap_frame_end = 1'b0;
    assign cap_frame_good = 1'b0;
    assign cap_frame_abort = 1'b0;
    assign display_pclk = 1'b0;
    assign display_rst_n = 1'b0;
    assign display_vs = 1'b0;
    assign display_hs = 1'b0;
    assign display_de = 1'b0;
    assign cap_clk = 1'b0;
    assign cap_sof = 1'b0;
    assign cap_valid = 1'b0;
    assign cap_last = 1'b0;
    assign cap_data = 1'b0;
    assign o_a_pixel = 40'hA5_A5A5_A5A5;
    assign o_a_pixel_valid = 1'b0;
    assign o_a_in_line = 1'b0;
    assign o_a_in_frame = 1'b0;
    assign o_a_vsync = 1'b0;
    assign o_a_byte_clk = sys_clk50m;
    assign o_dbg_a_cfg_done = 1'b0;
    assign o_dbg_a_bus_err_lat = 1'b0;
    assign o_dbg_a_nack_cnt = 32'h0000_00A1;
    assign o_dbg_a_lane_sticky = 4'hF;
    assign o_dbg_a_delay_tap = 6'd46;
    assign o_dbg_a_delay_done = 1'b0;
    assign o_dbg_a_rst_out = 1'b0;
    assign o_dbg_a_sync_wait = 1'b0;
    assign o_dbg_a_pkt_tgl = 1'b0;
    assign o_dbg_a_vs_tgl = 1'b0;
    assign o_dbg_a_clk_tgl = 1'b0;
    assign o_dbg_a_in_frame = 1'b0;
    assign o_dbg_a_vsync = 1'b0;
    assign o_dbg_xclr_n = 1'b1;
    assign o_dbg_pll_locked = 1'b1;
    assign o_dbg_cfg_rst_n = 1'b1;
    assign o_b_pixel = 40'hB1_8B18_B18B;
    assign o_b_pixel_valid = 1'b1;
    assign o_b_in_line = 1'b1;
    assign o_b_in_frame = 1'b1;
    assign o_b_vsync = 1'b1;
    assign o_b_byte_clk = sys_clk50m;
    assign o_dbg_b_cfg_done = 1'b1;
    assign o_dbg_b_bus_err_lat = 1'b0;
    assign o_dbg_b_nack_cnt = 32'h0000_00B1;
    assign o_dbg_b_lane_sticky = 4'h1;
    assign o_dbg_b_delay_tap = 6'd46;
    assign o_dbg_b_delay_done = 1'b1;
    assign o_dbg_b_rst_out = 1'b0;
    assign o_dbg_b_sync_wait = 1'b0;
    assign o_dbg_b_pkt_tgl = 1'b0;
    assign o_dbg_b_vs_tgl = 1'b0;
    assign o_dbg_b_clk_tgl = 1'b0;
    assign o_dbg_b_in_frame = 1'b0;
    assign o_dbg_b_vsync = 1'b0;
    assign o_dbg_b_good_frames = 1'b0;
    assign o_dbg_b_bad_frames = 1'b0;
    assign o_dbg_b_crc_errors = 1'b0;
    assign o_dbg_b_header_errors = 1'b0;
    assign o_dbg_b_last_wc = 1'b0;
    assign o_dbg_b_last_lines = 1'b0;
    assign cam_a_scl = 1'b0;
    // inout cam_a_sda left open in the stub
    assign cam_a_mclk = 1'b0;
    assign cam_a_xclr_n = 1'b0;
    assign cam_b_scl = 1'b0;
    // inout cam_b_sda left open in the stub
    assign cam_b_mclk = 1'b0;
    assign cam_b_xclr_n = 1'b0;
    assign O_led = 1'b0;
    assign O_uart_txd = 1'b0;
    assign O_hdmi_clk_p = 1'b0;
    assign O_hdmi_tx_p = 1'b0;
endmodule
