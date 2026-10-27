// =============================================================================
//  rx_phy_ph1p.v — PH1P(HR bank) 软 MIPI D-PHY 接收前端  v2
//
//  结构（对齐米联客 AFC03 IMX415 参考设计的 csi_rx_phy）：
//    时钟 lane : IBUF_DIFF → PH1P_PHY_LCLK(DIV=4) → 串行时钟 + 字节时钟(BUFG)
//    时钟检测  : csi_rx_clock_det（字节时钟不翻转时保持复位）
//    数据 lane : IBUF_DIFF → PH1P_LOGIC_DYNAMIC_HR_IDELAY(tap) → PH1P_LOGIC_HR_ISERDES(DDRX4)
//                → csi_rx_byte_align（找 0xB8 同步头，输出对齐后的字节 + 有效）
//    延迟扫描  : auto_delay_ctl（eye-scan，用 4 个 lane 的 align 有效做判据，取眼宽中点）
//
//  原语出处：/opt/anlogic/TD_Release_2026.2_NL/arch/ph1p_macro.v
//    PH1P_LOGIC_IBUF_DIFF          (8762 行附近)
//    PH1P_LOGIC_DYNAMIC_HR_IDELAY  (8869 行, dly[7:0], DEVICE="PH1P100")
//    PH1P_LOGIC_HR_ISERDES         (8766 行, IDDRMODE="DDRX4" → odata[9:0])
//    PH1P_PHY_LCLK / PH1P_LOGIC_BUFG
//  IDELAY 接法参照 ip/depot/HSIOF6F1DXP0_1.0/PH1P_HSIO/RTL/High_Speed_IO.v:481
// =============================================================================
`timescale 1ns / 1ps

module rx_phy_ph1p #(
    parameter LANE_NUM = 4,
    parameter DEVICE   = "PH1P100"
)(
    input  wire                  I_ref_clk,        // 参考时钟（时钟检测用），接板载 50M
    input  wire                  I_rst_n,
    input  wire                  I_rx_en,          // PHY 使能（高有效）
    // 板级 MIPI 引脚
    input  wire                  I_clk_pad_hs_p,
    input  wire                  I_clk_pad_hs_n,
    input  wire [LANE_NUM-1:0]   I_data_pad_hs_p,
    input  wire [LANE_NUM-1:0]   I_data_pad_hs_n,
    // 来自 CSI-2 包层的反馈（供 byte_align 判断同步头位置）
    input  wire                  I_wait_for_sync,
    input  wire                  I_packet_done,
    // 手动指定延迟（调试用；I_manual_en=0 时走自动扫描结果）
    input  wire [5:0]            I_manual_delay,
    input  wire                  I_manual_en,

    output wire                  O_serial_clk,     // ≈ lane 速率 / 2（DDR 时钟）
    output wire                  O_byte_clk,       // = 串行时钟 / 4
    output wire                  O_rst_out,        // 解复位（时钟有效后才释放）
    output wire [LANE_NUM*8-1:0] O_rx_data,        // 对齐后的字节数据（8bit/lane）
    output wire [LANE_NUM-1:0]   O_rx_valid,       // 每 lane 数据有效
    output wire [5:0]            O_delay_tap,      // 当前生效 tap
    output wire                  O_auto_delay_done,// 扫描完成
    output wire [5:0]            O_dbg_best_len    // 眼宽（tap 数）
);

    wire                    w_serial_clk_pad;
    wire                    w_serial_clk;
    wire                    w_byte_clk_div;
    wire [LANE_NUM-1:0]     w_data_pad_hs_p;
    wire [LANE_NUM-1:0]     w_data_pad_dly;
    wire [9:0]              w_iserdes [LANE_NUM-1:0];
    wire [7:0]              w_raw_byte [LANE_NUM-1:0];

    wire [5:0]              w_auto_tap, w_best_len;
    wire                    w_auto_tap_vld, w_auto_done;
    wire [5:0]              w_tap;

    // ---------------- 时钟 lane ----------------
    PH1P_LOGIC_IBUF_DIFF #(
        .DIFF_TERM ("TRUE")
    ) u_CK_IBUF_DIFF (
        .i_p            (I_clk_pad_hs_p    ),
        .i_n            (I_clk_pad_hs_n    ),
        .interm_disable (~I_rx_en          ),
        .o              (                  ),
        .o_p            (w_serial_clk_pad  ),
        .o_n            (                  )
    );

    PH1P_PHY_LCLK #(
        .CEMD   ("SYNC"  ),
        .CLKSEL ("ORG"   ),
        .DIV    ("4"     ),
        .LCLK   ("BYPASS")
    ) u_hs_clk_div (
        .clkin     (w_serial_clk_pad ),
        .rst       (~I_rst_n         ),
        .ce        (1'b1             ),
        .clkout    (w_serial_clk     ),
        .clkdivout (w_byte_clk_div   )
    );

    PH1P_LOGIC_BUFG u_hs_byte_clk_bufg (
        .i (w_byte_clk_div ),
        .o (O_byte_clk     )
    );

    assign O_serial_clk = w_serial_clk;

    // ---------------- 时钟检测：时钟 lane 没起来时保持复位 ----------------
    csi_rx_clock_det u_clk_det (
        .I_ref_clock (I_ref_clk   ),
        .I_ext_clock (O_byte_clk  ),
        .I_enable    (I_rx_en     ),
        .I_reset_in  (I_rst_n     ),
        .O_reset_out (O_rst_out   )
    );

    // ---------------- 延迟 tap：手动 > 自动扫描 ----------------
    assign w_tap = I_manual_en ? I_manual_delay : w_auto_tap;
    assign O_delay_tap = w_tap;

    // ---------------- 数据 lane ----------------
    genvar i;
    generate
        for (i = 0; i < LANE_NUM; i = i + 1) begin : gen_lane
            // 差分包输入 → 单端
            PH1P_LOGIC_IBUF_DIFF #(
                .DIFF_TERM ("TRUE")
            ) u_DATA_IBUF_DIFF (
                .i_p            (I_data_pad_hs_p[i]),
                .i_n            (I_data_pad_hs_n[i]),
                .interm_disable (~I_rx_en          ),
                .o              (w_data_pad_hs_p[i]),
                .o_p            (                  ),
                .o_n            (                  )
            );

            // 动态输入延迟（0~63 tap，自动扫描用）
            PH1P_LOGIC_DYNAMIC_HR_IDELAY #(
                .DEVICE ("PH1P100")
            ) u_IDELAY (
                .i         (w_data_pad_hs_p[i]),
                .dly       ({2'b00, w_tap}    ),
                .o         (w_data_pad_dly[i] )
            );

            // 解串：DDRX4 → 每 4 个串行位出 1 个字节
            PH1P_LOGIC_HR_ISERDES #(
                .IDDRMODE ( "DDRX4" )
            ) u_ISERDES (
                .sclk  (w_serial_clk      ),
                .pclk  (O_byte_clk        ),
                .rst   (~I_rx_en          ),
                .idata (w_data_pad_dly[i] ),
                .odata (w_iserdes[i]      )
            );

            assign w_raw_byte[i] = w_iserdes[i][7:0];

            // 字节对齐：找同步头 0xB8，输出偏移修正后的字节
            csi_rx_byte_align u_byte_align (
                .I_clock          (O_byte_clk        ),
                .I_reset_n        (O_rst_out         ),
                .I_enable         (I_rx_en           ),
                .I_lan_data_in    (w_raw_byte[i]     ),
                .I_wait_for_sync  (I_wait_for_sync   ),
                .I_packet_done    (I_packet_done     ),
                .O_data_out_vaild (O_rx_valid[i]     ),
                .O_data_out       (O_rx_data[i*8 +: 8])
            );
        end
    endgenerate

    // ---------------- 自动延迟扫描（eye-scan） ----------------
    auto_delay_ctl #(
        .MIPI_LAN      (LANE_NUM),
        .LAN_DATA_CUNT (10'h3ff)
    ) u_auto_delay_ctl (
        .I_byte_clk        (O_byte_clk       ),
        .I_reset_n         (O_rst_out        ),
        .I_byte_align_done (O_rx_valid       ),
        .O_delay_value     (w_auto_tap       ),
        .O_delay_vaild     (w_auto_tap_vld   ),
        .O_auto_delay_done (w_auto_done      ),
        .O_dbg_best_len    (w_best_len       )
    );

    assign O_auto_delay_done = w_auto_done;
    assign O_dbg_best_len    = w_best_len;

endmodule
