// =============================================================================
//  mipi_csi2_rx_ph1p.v — MIPI CSI-2 接收（PH1P 软 PHY + CSI-2 包层）
//
//  结构（连线对齐米联客 AFC03 IMX415 参考设计的 mipi_csi_rx.v）：
//    rx_phy_ph1p 软 PHY：时钟分频 + 时钟检测 + 每 lane IDELAY/ISERDES + 字节对齐 + tap 扫描
//      → csi_rx_word_align → csi_rx_word_gear_box
//      → csi_rx_packet_handler → csi_rx_10bit_unpack
//
//  注意：word_align 的 I_wait_for_sync / I_packet_done 来自 packet_handler 的输出，
//        与米联客原设计一致（同一字节时钟域内的握手，不要当成组合环去"修"）。
// =============================================================================
`timescale 1ns / 1ps

module mipi_csi2_rx_ph1p #(
    parameter LANE_NUM = 4
)(
    input  wire                  I_ref_clk,        // 参考时钟（接板载 50M）
    input  wire                  I_rst_n,
    input  wire                  I_rx_en,
    // 板级 MIPI 引脚
    input  wire                  I_clk_pad_hs_p,
    input  wire                  I_clk_pad_hs_n,
    input  wire [LANE_NUM-1:0]   I_data_pad_hs_p,
    input  wire [LANE_NUM-1:0]   I_data_pad_hs_n,
    // 手动延迟（调试；I_manual_en=0 走自动扫描）
    input  wire [5:0]            I_manual_delay,
    input  wire                  I_manual_en,

    // 时钟 / 复位 / 状态
    output wire                  O_byte_clk,
    output wire                  O_rst_out,
    output wire [LANE_NUM-1:0]   O_lane_valid,     // 每 lane 字节对齐有效（调试）
    output wire [5:0]            O_delay_tap,
    output wire                  O_auto_delay_done,

    // 包状态 / 数据
    output wire                  O_sync_wait,
    output wire                  O_packet_done,
    output wire                  O_vsync,
    output wire                  O_in_frame,
    output wire                  O_in_line,
    output wire [39:0]           O_pixel_data,
    output wire                  O_pixel_valid
);

    wire [LANE_NUM-1:0]   w_lane_valid;
    wire [LANE_NUM*8-1:0] w_lane_data;
    wire [LANE_NUM*8-1:0] w_word_align_data;
    wire                  w_word_align_valid;
    wire [31:0]           w_gear_data;
    wire                  w_gear_valid;
    wire [31:0]           w_payload;
    wire                  w_payload_valid;
    wire [39:0]           w_pixel_data;
    wire                  w_pixel_valid;

    assign O_lane_valid = w_lane_valid;

    // ---------------- 软 PHY ----------------
    rx_phy_ph1p #(
        .LANE_NUM (LANE_NUM)
    ) u_rx_phy (
        .I_ref_clk          (I_ref_clk        ),
        .I_rst_n            (I_rst_n          ),
        .I_rx_en            (I_rx_en          ),
        .I_clk_pad_hs_p     (I_clk_pad_hs_p   ),
        .I_clk_pad_hs_n     (I_clk_pad_hs_n   ),
        .I_data_pad_hs_p    (I_data_pad_hs_p  ),
        .I_data_pad_hs_n    (I_data_pad_hs_n  ),
        .I_wait_for_sync    (O_sync_wait      ),
        .I_packet_done      (O_packet_done    ),
        .I_manual_delay     (I_manual_delay   ),
        .I_manual_en        (I_manual_en      ),
        .O_serial_clk       (                 ),
        .O_byte_clk         (O_byte_clk       ),
        .O_rst_out          (O_rst_out        ),
        .O_rx_data          (w_lane_data      ),
        .O_rx_valid         (w_lane_valid     ),
        .O_delay_tap        (O_delay_tap      ),
        .O_auto_delay_done  (O_auto_delay_done),
        .O_dbg_best_len     (                 )
    );

    // ---------------- CSI-2 包层（全部跑在 PHY 字节时钟域） ----------------
    csi_rx_word_align #(
        .MIPI_LAN (LANE_NUM)
    ) u_word_align (
        .I_word_clock      (O_byte_clk        ),
        .I_reset_n         (O_rst_out         ),
        .I_enable          (I_rx_en           ),
        .I_packet_done     (O_packet_done     ),
        .I_wait_for_sync   (O_sync_wait       ),
        .O_packet_done_out (                  ),
        .I_word_in         (w_lane_data       ),
        .I_valid_in        (w_lane_valid      ),
        .O_word_out        (w_word_align_data ),
        .O_valid_out       (w_word_align_valid)
    );

    csi_rx_word_gear_box #(
        .MIPI_LAN (LANE_NUM)
    ) u_gear_box (
        .I_word_clock      (O_byte_clk        ),
        .I_reset_n         (O_rst_out         ),
        .I_enable          (I_rx_en           ),
        .I_lane_data       (w_word_align_data ),
        .I_lane_data_valid (w_word_align_valid),
        .O_word_out        (w_gear_data       ),
        .O_valid_out       (w_gear_valid      )
    );

    csi_rx_packet_handler #(
        .MIPI_LAN (LANE_NUM)
    ) u_packet (
        .I_clock         (O_byte_clk        ),
        .I_reset_n       (O_rst_out         ),
        .I_enable        (I_rx_en           ),
        .I_data          (w_gear_data       ),
        .I_data_valid    (w_gear_valid      ),
        .O_sync_wait     (O_sync_wait       ),
        .O_packet_done   (O_packet_done     ),
        .O_payload_out   (w_payload         ),
        .O_payload_valid (w_payload_valid   ),
        .O_vsync_out     (O_vsync           ),
        .O_in_frame      (O_in_frame        ),
        .O_in_line       (O_in_line         )
    );

    csi_rx_10bit_unpack u_unpack (
        .I_clock        (O_byte_clk        ),
        .I_reset_n      (O_rst_out         ),
        .I_enable       (I_rx_en           ),
        .I_line_in      (O_in_line         ),
        .I_data_in      (w_payload         ),
        .I_din_valid    (w_payload_valid   ),
        .O_data_out     (w_pixel_data      ),
        .O_dout_valid   (w_pixel_valid     )
    );

    assign O_pixel_data  = w_pixel_data;
    assign O_pixel_valid = w_pixel_valid;

endmodule
