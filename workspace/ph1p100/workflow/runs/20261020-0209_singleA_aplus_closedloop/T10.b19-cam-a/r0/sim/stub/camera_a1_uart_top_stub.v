// T10.b19-cam-a structural stub of camera_a1_uart_top (ports copied verbatim)
module camera_a1_uart_top #(
    parameter integer CAM_W = 3864,
    parameter integer CAM_H = 2192,
    parameter integer ROI_X = 972,
    parameter integer ROI_Y = 556,
    parameter integer W     = 1920,
    parameter integer H     = 1080,
    parameter integer UART_DIV = 434,
    parameter integer HB_DIV   = 0,
    
    
    
    parameter integer STS_DIV  = 187500000,
    parameter integer PREP_EN = 1,
    parameter integer PRED_EN = 1,
    parameter integer FIFO_AW = 9,
    parameter [31:0]  RAW_BASE = 32'd0,
    
    
    
    parameter [31:0]  CMP_BASE = 32'd262144
) (
    input         clk_cam,
    input         clk_a1,
    input         clk_uart,
    input         rst_n,
    input  [39:0] i_a_pixel,
    input         i_a_pixel_valid,
    input         i_a_in_line,
    input         i_a_in_frame,
    input         i_a_vsync,
    input         i_ddr_rdy,
    input  [5:0]  i_dbg_tap,
    input         i_dbg_delay_done,
    input         i_dbg_rst_out,
    input         i_dbg_sync_wait,
    input         i_dbg_pkt_tgl,
    input         i_dbg_vs_tgl,
    input         i_dbg_clk_tgl,
    input  [63:0] i_dbg_sys,
    input  [511:0] i_dbg_bridge,
    output [31:0] o_ddr_awaddr,
    output        o_ddr_awvalid,
    input         o_ddr_awready,
    output [255:0] o_ddr_wdata,
    output        o_ddr_wvalid,
    input         o_ddr_wready,
    output [31:0] o_ddr_araddr,
    output        o_ddr_arvalid,
    input         o_ddr_arready,
    input  [255:0] i_ddr_rdata,
    input         i_ddr_rvalid,
    output        o_ddr_rready,
    output        o_rd_abort,
    output        o_uart_txd,
    output [7:0]  o_dbg_byte,
    output        o_dbg_byte_valid,
    output [31:0] o_st_cap_frames,
    output [31:0] o_st_enc_frames,
    output [31:0] o_st_exported,
    output [31:0] o_st_export_bytes,
    output [31:0] o_st_raw_pub,
    output [31:0] o_st_raw_drop,
    output [31:0] o_st_cmp_drop,
    output [31:0] o_st_geom_err,
    output [31:0] o_st_errors,
    output [31:0] o_st_read_words,
    output [31:0] o_st_dup_words,
    output [639:0] o_st_raw_sts
);
    assign o_ddr_awaddr = 1'b0;
    assign o_ddr_awvalid = 1'b0;
    assign o_ddr_wdata = 1'b0;
    assign o_ddr_wvalid = 1'b0;
    assign o_ddr_araddr = 1'b0;
    assign o_ddr_arvalid = 1'b0;
    assign o_ddr_rready = 1'b0;
    assign o_rd_abort = 1'b0;
    assign o_uart_txd = 1'b0;
    assign o_dbg_byte = 1'b0;
    assign o_dbg_byte_valid = 1'b0;
    assign o_st_cap_frames = 1'b0;
    assign o_st_enc_frames = 1'b0;
    assign o_st_exported = 1'b0;
    assign o_st_export_bytes = 1'b0;
    assign o_st_raw_pub = 1'b0;
    assign o_st_raw_drop = 1'b0;
    assign o_st_cmp_drop = 1'b0;
    assign o_st_geom_err = 1'b0;
    assign o_st_errors = 1'b0;
    assign o_st_read_words = 1'b0;
    assign o_st_dup_words = 1'b0;
    assign o_st_raw_sts = 1'b0;
endmodule
