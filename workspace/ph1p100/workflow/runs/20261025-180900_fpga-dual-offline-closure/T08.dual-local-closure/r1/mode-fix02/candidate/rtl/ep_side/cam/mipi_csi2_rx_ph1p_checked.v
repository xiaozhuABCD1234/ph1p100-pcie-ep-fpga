// =============================================================================
//  mipi_csi2_rx_ph1p_checked.v — MIPI CSI-2 接收（peer 软 PHY + 本方 checked 包层）
//
//  T07.rk-align-backend 新增。相对冻结 peer 的 mipi_csi2_rx_ph1p.v：
//    · 保留 PHY / byte align / word align / gear box 的**原样例化与握手**：
//      rx_phy_ph1p 的 I_wait_for_sync / I_packet_done 仍来自包层，
//      word_align 的 I_packet_done / I_wait_for_sync 同样接包层输出；
//    · 把 peer 的 csi_rx_packet_handler 替换成本方的
//      csi_rx_packet_integrity（整帧 CRC16/ECC/ WC/行数/FE 裁决）与
//      csi_rx_10bit_unpack_checked（带 keep 的五字节组解包）；
//    · 输出 40bit 四像素 + FE/good/abort + 错误/几何诊断，全部接顶层。
//
//  数据流（与 peer 原版逐级对应）：
//    rx_phy_ph1p → csi_rx_word_align → csi_rx_word_gear_box
//      → csi_rx_packet_integrity（I_data=32bit 字、O_payload_keep）
//      → csi_rx_10bit_unpack_checked → O_pixel_data[39:0]
//
//  帧裁决语义（详见 csi_rx_packet_integrity.v 头部）：
//    · O_vsync_out  = 收到 FS（dt=0）那一拍；
//    · O_in_frame   = 帧打开（FS 到 FE 之间）；
//    · O_in_line    = 当前字所在行有效（行长包头那一拍起）；
//    · O_frame_end  = 收到 FE 那一拍（无论好坏都发）；
//    · O_frame_good = FE 且 WC/行数/CRC/ECC/超时全过 ⇒ 这一拍为 1；
//    · O_frame_abort= 帧内任何判坏/终止事件（坏 FE 也在这一拍置 abort）。
//    下游 cam_ddr_writer 只把「EOF 且 good」的帧当可发布帧。
//
//  仿真：定义 MIPI_PHY_SIM_STUB 时，用 I_sim_* 端口直接注入包层输入字
//    （32bit/拍，valid 与 packet_done 语义同 gearbox 输出），并旁路 PHY 与
//    位/字对齐（它们是厂商 serdes 原语，ModelSim 无原语库；这条路只在
//    TD 综合/STA 与上板验证）。不定义时 = 真实实现，PHY 原语由 TD 提供。
// =============================================================================
`timescale 1ns / 1ps

module mipi_csi2_rx_ph1p_checked #(
    parameter LANE_NUM = 4,
    // ---- checked 包层参数（与正式几何/DT 一致；合成/诊断可用小几何）----
    parameter [5:0]  IMAGE_DT           = 6'h2b,  // RAW10
    parameter [15:0] IMAGE_WC           = 16'd0,  // 0 = 不约束行长（合成测试）
    parameter [15:0] EXPECTED_LINES     = 16'd0,  // 0 = 不约束行数（合成测试）
    parameter [1:0]  VC_ID              = 2'd0,
    parameter        CHECK_FRAME_ID     = 1'b0,
    parameter [31:0] PACKET_IDLE_CYCLES = 32'd32,
    parameter [31:0] FRAME_TIMEOUT_CYCLES = 32'd16777216,
    parameter        ENABLE_CHECKED     = 1'b1    // 1 = 走 checked 包层（默认）
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
    output wire [LANE_NUM-1:0]   O_lane_valid,
    output wire [5:0]            O_delay_tap,
    output wire                  O_auto_delay_done,

    // 包状态 / 数据（与 peer mipi_csi2_rx_ph1p 同名同义 + T07 新增）
    output wire                  O_sync_wait,
    output wire                  O_packet_done,
    output wire                  O_vsync,
    output wire                  O_in_frame,
    output wire                  O_in_line,
    output wire [39:0]           O_pixel_data,
    output wire                  O_pixel_valid,

    // ---- T07 新增：整帧裁决与诊断（全部在 O_byte_clk 域）----
    output wire                  O_frame_end,
    output wire                  O_frame_good,
    output wire                  O_frame_abort,
    output wire [31:0]           O_crc_errors,
    output wire [31:0]           O_header_errors,
    output wire [31:0]           O_packet_timeouts,
    output wire [31:0]           O_frame_timeouts,
    output wire [31:0]           O_good_frames,
    output wire [31:0]           O_bad_frames,
    output wire [15:0]           O_last_wc,
    output wire [15:0]           O_last_lines,
    // ---- 包层原始载荷（keep 诊断；也是 T11 RAW10 打包的入口）----
    output wire [31:0]           O_payload_out,
    output wire [3:0]            O_payload_keep,
    output wire                  O_payload_valid
`ifdef MIPI_PHY_SIM_STUB
    ,
    // ---- 仅仿真：直接注入包层输入（32bit 字 + valid + packet_done）----
    input  wire                  I_sim_word_valid,
    input  wire [31:0]           I_sim_word_data,
    input  wire                  I_sim_packet_done
`endif
);

    wire [LANE_NUM-1:0]   w_lane_valid;
    wire [LANE_NUM*8-1:0] w_lane_data;
    wire [LANE_NUM*8-1:0] w_word_align_data;
    wire                  w_word_align_valid;
    wire [31:0]           w_gear_data;
    wire                  w_gear_valid;
    wire [31:0]           w_payload;
    wire                  w_payload_valid;
    wire [3:0]            w_payload_keep;
    wire [39:0]           w_pixel_data;
    wire                  w_pixel_valid;
    wire                  w_if_pkt_done;    // 包层给出的 packet_done
    wire                  w_pkt_done_used;  // 实际用于 PHY/word_align 握手的那一根

`ifdef MIPI_PHY_SIM_STUB
    // ---------------- 仅仿真：旁路 PHY 与位/字对齐 ----------------
    assign O_byte_clk  = I_ref_clk;      // 包层跑在 TB 直接驱动的时钟上
    assign O_rst_out   = I_rst_n;
    assign O_lane_valid = {LANE_NUM{1'b1}};
    assign O_delay_tap  = 6'd0;
    assign O_auto_delay_done = 1'b1;
    assign w_gear_data  = I_sim_word_data;
    assign w_gear_valid = I_sim_word_valid;
    assign w_pkt_done_used = I_sim_packet_done;
`else
    assign O_lane_valid = w_lane_valid;
    assign w_pkt_done_used = w_if_pkt_done;

    // ---------------- 软 PHY（peer 原样） ----------------
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
        .I_packet_done      (w_pkt_done_used  ),
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

    // ---------------- CSI-2 位/字对齐（peer 原样，握手不变） ----------------
    csi_rx_word_align #(
        .MIPI_LAN (LANE_NUM)
    ) u_word_align (
        .I_word_clock      (O_byte_clk        ),
        .I_reset_n         (O_rst_out         ),
        .I_enable          (I_rx_en           ),
        .I_packet_done     (w_pkt_done_used   ),
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
`endif

    // ---------------- 本方 checked 包层（整帧 CRC/ECC/WC/行数/FE 裁决） ----------------
    csi_rx_packet_integrity #(
        .VC_ID               (VC_ID              ),
        .IMAGE_DT            (IMAGE_DT           ),
        .IMAGE_WC            (IMAGE_WC           ),
        .EXPECTED_LINES      (EXPECTED_LINES     ),
        .CHECK_FRAME_ID      (CHECK_FRAME_ID     ),
        .PACKET_IDLE_CYCLES  (PACKET_IDLE_CYCLES ),
        .FRAME_TIMEOUT_CYCLES(FRAME_TIMEOUT_CYCLES)
    ) u_integrity (
        .I_clock           (O_byte_clk        ),
        .I_reset_n         (O_rst_out         ),
        .I_enable          (I_rx_en           ),
        .I_data            (w_gear_data       ),
        .I_data_valid      (w_gear_valid      ),
        .O_packet_done     (w_if_pkt_done     ),
        .O_sync_wait       (O_sync_wait       ),
        .O_payload_out     (w_payload         ),
        .O_payload_valid   (w_payload_valid   ),
        .O_payload_keep    (w_payload_keep    ),
        .O_vsync_out       (O_vsync           ),
        .O_in_frame        (O_in_frame        ),
        .O_in_line         (O_in_line         ),
        .O_frame_end       (O_frame_end       ),
        .O_frame_good      (O_frame_good      ),
        .O_frame_abort     (O_frame_abort     ),
        .O_crc_errors      (O_crc_errors      ),
        .O_header_errors   (O_header_errors   ),
        .O_packet_timeouts (O_packet_timeouts ),
        .O_frame_timeouts  (O_frame_timeouts  ),
        .O_good_frames     (O_good_frames     ),
        .O_bad_frames      (O_bad_frames      ),
        .O_last_wc         (O_last_wc         ),
        .O_last_lines      (O_last_lines      )
    );

`ifdef MIPI_PHY_SIM_STUB
`else
`endif

    // ---------------- 本方 checked 解包（keep 驱动，五字节组 → 四像素） ----------------
    csi_rx_10bit_unpack_checked u_unpack (
        .I_clock        (O_byte_clk        ),
        .I_reset_n      (O_rst_out         ),
        .I_enable       (I_rx_en           ),
        .I_line_in      (O_in_line         ),
        .I_data_in      (w_payload         ),
        .I_keep         (w_payload_keep    ),
        .I_din_valid    (w_payload_valid   ),
        .O_data_out     (w_pixel_data      ),
        .O_dout_valid   (w_pixel_valid     )
    );

    assign O_pixel_data   = w_pixel_data;
    assign O_pixel_valid  = w_pixel_valid;
    assign O_payload_out  = w_payload;
    assign O_payload_keep = w_payload_keep;
    assign O_payload_valid= w_payload_valid;
    assign O_packet_done  = w_pkt_done_used;

endmodule
