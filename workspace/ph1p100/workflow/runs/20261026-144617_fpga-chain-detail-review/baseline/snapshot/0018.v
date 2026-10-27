// =============================================================================
//  f9p_imx415x2_top.v — MLK-F9P-CA05-PH1P100 + FEP-VID006-MIPI + 2 x IMX415
//  工程: f9p_ph1p100_imx415x2      器件: PH1P100SBG484 / -3      工具: TD 6.2.3
// -----------------------------------------------------------------------------
//  功能
//    · 两路 MIPI CSI-2 接收（自写 PH1P 软 D-PHY + 复用米联客 CSI-2 包层）
//    · 两路独立 I2C 配置 IMX415（4K@30 档），提供传感器 MCLK / XCLR
//    · HDMI 输出：PLL + VTC + 测试图 / 摄像头实时预览（二选一）
//    · 上板遥测：4 个 LED + 115200 UART 状态行（比数灯精确）
//
//  时钟域
//    sys_clk50m  50MHz（H4，1.35V SSTL135）：复位、I2C、遥测
//    byte_clk    111.375MHz：PHY 由 MIPI 时钟 lane 分频得到（两路各自独立）
//    pclkx1      148.5MHz：HDMI 像素时钟（PLL clk0）
//    pclkx5      742.5MHz：HDMI OSERDES 5 倍串行时钟（PLL clk1）
//
//  关键引脚（详见 uisrc/04_pin/fep_vid006_imx415.adc，全部已上板实测）
//    MIPI-A: clk K18/K19  lane0 N20/M20  lane1 K21/K22  lane2 N18/N19  lane3 M21/L21
//    MIPI-B: clk J19/H19  lane0 J22/H22  lane1 G17/G18  lane2 J20/J21  lane3 L19/L20
//    A 口控制: SCL N22  SDA M22  MCLK L18  XCLR M18
//    B 口控制: SCL H13  SDA G13  MCLK G20  XCLR H20
//    注意：MIPI 差分走底板 FEP1B 的 C 排（子卡 A 排那侧串了 100R，会衰减到收不满）
//
//  修订
//    v1.0  2026-10-10  初版：两路 MIPI + I2C + 遥测，上板两路 4K30 满速
//    v1.1  2026-10-10  加 HDMI 输出（测试图）与摄像头预览（320x180 灰度）
// =============================================================================
`timescale 1ns / 1ps

module f9p_camera_display_core (
    output wire display_pclk,display_rst_n,display_vs,display_hs,display_de,
    input wire[23:0] ddr_rgb,input wire ddr_vs,ddr_hs,ddr_de,
    output wire cap_clk,cap_sof,cap_valid,cap_last,output wire[7:0] cap_data,
    input  wire         sys_clk50m,          // 板载 50MHz（H4, 1.35V）

    // ---- MIPI-A（子卡 U5 / FEP1A）----
    input  wire         mipi_a_clk_hs_p,
    input  wire         mipi_a_clk_hs_n,
    input  wire [3:0]   mipi_a_data_hs_p,
    input  wire [3:0]   mipi_a_data_hs_n,
    // ---- MIPI-B（子卡 U6 / FEP1A）----
    input  wire         mipi_b_clk_hs_p,
    input  wire         mipi_b_clk_hs_n,
    input  wire [3:0]   mipi_b_data_hs_p,
    input  wire [3:0]   mipi_b_data_hs_n,

    // ---- 传感器 A 控制（1V8）----
    output wire         cam_a_scl,           // C4  -> N22
    inout  wire         cam_a_sda,           // C5  -> M22
    output wire         cam_a_mclk,          // A5  -> L18
    output wire         cam_a_xclr_n,        // 子卡 A4 (FGPIO 当复位用) -> M18
    // ---- 传感器 B 控制（1V8）----
    output wire         cam_b_scl,           // 子卡 A28 -> H13
    inout  wire         cam_b_sda,           // 子卡 A29 -> G13
    output wire         cam_b_mclk,          // 子卡 C29 -> G20
    output wire         cam_b_xclr_n,        // 子卡 C28 -> H20

    output wire [3:0]   O_led,
    output wire         O_uart_txd,         // FPGA_UART_TX0 = R17，115200 8N1 状态输出

    // ---- HDMI 输出（HDMI-OUT 口：FD0=B15 FD1=B21 FD2=C22 FCLK=C18，3V3 LVDS）----
    output wire         O_hdmi_clk_p,
    output wire [2:0]   O_hdmi_tx_p
);

    // ------------------------------------------------------------------
    // 复位 / 时钟
    // ------------------------------------------------------------------
    reg [15:0] r_pwr_cnt = 16'd0;
    reg        r_rst_n   = 1'b0;
    always @(posedge sys_clk50m) begin
        if (r_pwr_cnt != 16'hFFFF) begin
            r_pwr_cnt <= r_pwr_cnt + 1'b1;
            r_rst_n   <= 1'b0;
        end else begin
            r_rst_n   <= 1'b1;
        end
    end

    wire w_pclkx1,w_pclkx5,w_pll_locked,w_mclk_raw;
    wire w_mclk,w_xclr_n,r_rst_n_slow;
    raw10_display60_clocks X_ui_pll (
        .refclk(sys_clk50m),.reset(~r_rst_n),.lock(w_pll_locked),
        .clk0_out(w_pclkx1),.clk1_out(w_pclkx5),.clk2_out(w_mclk_raw));
    camera_startup u_camera_startup (
        .I_clk(sys_clk50m),.I_pll_locked(w_pll_locked),.I_mclk(w_mclk_raw),
        .O_xclr_n(w_xclr_n),.O_mclk(w_mclk),.O_cfg_rst_n(r_rst_n_slow));
    assign cam_a_mclk=w_mclk;assign cam_b_mclk=w_mclk;
    assign cam_a_xclr_n=w_xclr_n;assign cam_b_xclr_n=w_xclr_n;
    reg [2:0] pixel_reset_sync=0;
    always @(posedge w_pclkx1 or negedge w_pll_locked)
        if(!w_pll_locked) pixel_reset_sync<=0;
        else pixel_reset_sync<={pixel_reset_sync[1:0],1'b1};
    wire w_pixel_rst_n=pixel_reset_sync[2];

    // ------------------------------------------------------------------
    // IDELAY 采样点（tap）：实测眼图中点，见 README「上板踩出来的坑」
    //   tap 45~47 收包率最高；自动扫描（auto_delay_ctl）会回落到复位值 32，只有 1/9 收包率
    //   USE_MANUAL_TAP=0 可切回自动扫描；换板/换线速率需要重新扫（每 2s 换一个 tap 读串口）
    // ------------------------------------------------------------------
    localparam        USE_MANUAL_TAP = 1'b1;
    localparam [5:0]  CAM_IDELAY_TAP = 6'd46;

    // ------------------------------------------------------------------
    // 两路 MIPI CSI-2 接收（PHY 内置字节对齐 + IDELAY 自动扫描）
    // ------------------------------------------------------------------
    wire [5:0]  w_a_delay_tap, w_b_delay_tap;
    wire        w_a_delay_done, w_b_delay_done;
    wire        w_a_byte_clk, w_b_byte_clk;
    wire        w_a_rst_out, w_b_rst_out;
    wire [3:0]  w_a_lane_valid, w_b_lane_valid;
    wire        w_a_sync_wait, w_b_sync_wait;
    wire        w_a_pkt_done, w_b_pkt_done;
    wire        w_a_vsync, w_b_vsync;
    wire        w_a_in_frame, w_b_in_frame;
    wire        w_a_in_line, w_b_in_line;
    wire [39:0] w_a_pixel, w_b_pixel;
    wire        w_a_pixel_valid, w_b_pixel_valid;

    mipi_csi2_rx_ph1p #(.LANE_NUM(4)) u_csi_a (
        .I_ref_clk          (sys_clk50m      ),
        .I_rst_n            (r_rst_n         ),
        .I_rx_en            (r_rst_n         ),
        .I_clk_pad_hs_p     (mipi_a_clk_hs_p ),
        .I_clk_pad_hs_n     (mipi_a_clk_hs_n ),
        .I_data_pad_hs_p    (mipi_a_data_hs_p),
        .I_data_pad_hs_n    (mipi_a_data_hs_n),
        .I_manual_delay     (CAM_IDELAY_TAP),
        .I_manual_en        (USE_MANUAL_TAP),
        .O_byte_clk         (w_a_byte_clk    ),
        .O_rst_out          (w_a_rst_out     ),
        .O_lane_valid       (w_a_lane_valid  ),
        .O_delay_tap        (w_a_delay_tap   ),
        .O_auto_delay_done  (w_a_delay_done  ),
        .O_sync_wait        (w_a_sync_wait   ),
        .O_packet_done      (w_a_pkt_done    ),
        .O_vsync            (w_a_vsync       ),
        .O_in_frame         (w_a_in_frame    ),
        .O_in_line          (w_a_in_line     ),
        .O_pixel_data       (w_a_pixel       ),
        .O_pixel_valid      (w_a_pixel_valid )
    );

    mipi_csi2_rx_ph1p #(.LANE_NUM(4)) u_csi_b (
        .I_ref_clk          (sys_clk50m      ),
        .I_rst_n            (r_rst_n         ),
        .I_rx_en            (r_rst_n         ),
        .I_clk_pad_hs_p     (mipi_b_clk_hs_p ),
        .I_clk_pad_hs_n     (mipi_b_clk_hs_n ),
        .I_data_pad_hs_p    (mipi_b_data_hs_p),
        .I_data_pad_hs_n    (mipi_b_data_hs_n),
        .I_manual_delay     (CAM_IDELAY_TAP),
        .I_manual_en        (USE_MANUAL_TAP),
        .O_byte_clk         (w_b_byte_clk    ),
        .O_rst_out          (w_b_rst_out     ),
        .O_lane_valid       (w_b_lane_valid  ),
        .O_delay_tap        (w_b_delay_tap   ),
        .O_auto_delay_done  (w_b_delay_done  ),
        .O_sync_wait        (w_b_sync_wait   ),
        .O_packet_done      (w_b_pkt_done    ),
        .O_vsync            (w_b_vsync       ),
        .O_in_frame         (w_b_in_frame    ),
        .O_in_line          (w_b_in_line     ),
        .O_pixel_data       (w_b_pixel       ),
        .O_pixel_valid      (w_b_pixel_valid )
    );

    // ------------------------------------------------------------------
    // IMX415 寄存器配置（两路独立 I2C，传感器 I2C 地址相同 0x34(8bit)）
    //   I2C 时钟：50MHz / (CLK_DIV+1) = 100kHz  ->  CLK_DIV = 499
    // ------------------------------------------------------------------
    wire w_a_cfg_done, w_b_cfg_done;
    wire w_a_bus_err,  w_b_bus_err;
    wire w_a_ae_done,  w_b_ae_done;

    ui_cfg_imx415 #(.CLK_DIV(16'd499)) u_cfg_a (
        .I_clk         (sys_clk50m),
        .I_rst_n       (r_rst_n_slow),
        .I_cam_mode    (2'd1),          // 1 = 4K
        .I_ae_req      (1'b0),
        .I_ae_data     (8'd100),
        .O_cam_scl     (cam_a_scl),
        .IO_cam_sda    (cam_a_sda),
        .O_cfg_done    (w_a_cfg_done),
        .O_ae_cfg_done (w_a_ae_done),
        .O_bus_error   (w_a_bus_err)
    );

    ui_cfg_imx415 #(.CLK_DIV(16'd499)) u_cfg_b (
        .I_clk         (sys_clk50m),
        .I_rst_n       (r_rst_n_slow),
        .I_cam_mode    (2'd1),          // 1 = 4K
        .I_ae_req      (1'b0),
        .I_ae_data     (8'd100),
        .O_cam_scl     (cam_b_scl),
        .IO_cam_sda    (cam_b_sda),
        .O_cfg_done    (w_b_cfg_done),
        .O_ae_cfg_done (w_b_ae_done),
        .O_bus_error   (w_b_bus_err)
    );

    // ------------------------------------------------------------------
    // 状态指示（LED1~4）与 UART 状态输出（115200，R17）
    // ------------------------------------------------------------------
    reg r_any_pkt = 1'b0;
    always @(posedge sys_clk50m)
        if (w_a_pkt_done | w_b_pkt_done) r_any_pkt <= 1'b1;

    reg [3:0] r_led = 4'd0;
    always @(posedge sys_clk50m) begin
        r_led[0] <= w_a_cfg_done;                 // A 口 I2C 配置完成
        r_led[1] <= w_b_cfg_done;                 // B 口 I2C 配置完成
        r_led[2] <= w_a_bus_err | w_b_bus_err;    // 任一口 I2C NACK
        r_led[3] <= r_any_pkt;                    // 收到过 CSI-2 包（真出图了）
    end

    assign O_led = r_led;

    // 字节域脉冲 → 翻转电平（跨到 50MHz 域安全计数）
    wire w_a_pkt_tgl, w_a_vs_tgl, w_b_pkt_tgl, w_b_vs_tgl;
    wire w_a_clk_tgl, w_b_clk_tgl;

    // 字节时钟活动（每 2^15 个字节时钟翻转一次）
    clk_activity #(.DIV_BITS(15)) u_a_clk_act (.I_clk(w_a_byte_clk), .I_rst_n(w_a_rst_out), .O_tgl(w_a_clk_tgl));
    clk_activity #(.DIV_BITS(15)) u_b_clk_act (.I_clk(w_b_byte_clk), .I_rst_n(w_b_rst_out), .O_tgl(w_b_clk_tgl));

    // 每 lane 字节对齐粘滞标志（哪几条 lane 曾经对齐过）
    reg [3:0] r_a_lane_sticky = 4'd0, r_b_lane_sticky = 4'd0;
    always @(posedge sys_clk50m) begin
        r_a_lane_sticky <= r_a_lane_sticky | w_a_lane_valid;
        r_b_lane_sticky <= r_b_lane_sticky | w_b_lane_valid;
    end

    // I2C NACK 锁存 + 计数（bus_error 是瞬时信号，0.5s 采一次会漏掉）
    reg r_a_err_lat = 1'b0, r_b_err_lat = 1'b0;
    reg [31:0] r_a_nack_cnt = 32'd0, r_b_nack_cnt = 32'd0;
    always @(posedge sys_clk50m) begin
        if (w_a_bus_err) begin r_a_err_lat <= 1'b1; r_a_nack_cnt <= r_a_nack_cnt + 1'b1; end
        if (w_b_bus_err) begin r_b_err_lat <= 1'b1; r_b_nack_cnt <= r_b_nack_cnt + 1'b1; end
    end

    pulse2toggle u_tgl_apkt (.I_clk(w_a_byte_clk), .I_rst_n(w_a_rst_out), .I_pulse(w_a_pkt_done), .O_tgl(w_a_pkt_tgl));
    pulse2toggle u_tgl_avs  (.I_clk(w_a_byte_clk), .I_rst_n(w_a_rst_out), .I_pulse(w_a_vsync   ), .O_tgl(w_a_vs_tgl ));
    pulse2toggle u_tgl_bpkt (.I_clk(w_b_byte_clk), .I_rst_n(w_b_rst_out), .I_pulse(w_b_pkt_done), .O_tgl(w_b_pkt_tgl));
    pulse2toggle u_tgl_bvs  (.I_clk(w_b_byte_clk), .I_rst_n(w_b_rst_out), .I_pulse(w_b_vsync   ), .O_tgl(w_b_vs_tgl ));

    dbg_uart #(
        .CLK_DIV (16'd434)
    ) u_dbg_uart (
        .I_clk          (sys_clk50m     ),
        .I_rst_n        (r_rst_n        ),
        .I_a_lane_valid (w_a_lane_valid ),
        .I_a_tap        (w_a_delay_tap  ),
        .I_a_cfg_done   (w_a_cfg_done   ),
        .I_a_bus_err    (r_a_err_lat    ),
        .I_a_pkt_tgl    (w_a_pkt_tgl    ),
        .I_a_vs_tgl     (w_a_vs_tgl     ),
        .I_a_clk_tgl    (w_a_clk_tgl    ),
        .I_a_nack_cnt   (r_a_nack_cnt   ),
        .I_a_lane_sticky(r_a_lane_sticky),
        .I_b_lane_sticky(r_b_lane_sticky),
        .I_b_nack_cnt   (r_b_nack_cnt   ),
        .I_b_lane_valid (w_b_lane_valid ),
        .I_b_tap        (w_b_delay_tap  ),
        .I_b_cfg_done   (w_b_cfg_done   ),
        .I_b_bus_err    (r_b_err_lat    ),
        .I_b_pkt_tgl    (w_b_pkt_tgl    ),
        .I_b_vs_tgl     (w_b_vs_tgl     ),
        .I_b_clk_tgl    (w_b_clk_tgl    ),
        .O_txd          (O_uart_txd     )
    );

    // ------------------------------------------------------------------
    // HDMI: 148.5 MHz pixel / 742.5 MHz native serializer; 2200 x 1125, 60 Hz.
    wire w_vtc_vs,w_vtc_hs,w_vtc_de,w_vtc_user,w_vtc_last;
    wire [7:0] w_rgb_r,w_rgb_g,w_rgb_b;

    uivtc #(
        .H_ActiveSize (1920), .H_SyncStart (1920+88), .H_SyncEnd (1920+88+44), .H_FrameSize (1920+88+44+148),
        .V_ActiveSize (1080), .V_SyncStart (1080+4),  .V_SyncEnd (1080+4+5),  .V_FrameSize (1080+4+5+36)
    ) X_uivtc (
        .I_vtc_clk      (w_pclkx1),
        .I_vtc_rstn     (w_pixel_rst_n),
        .O_vtc_vs       (w_vtc_vs),
        .O_vtc_hs       (w_vtc_hs),
        .O_vtc_de_valid (w_vtc_de),
        .O_vtc_user     (w_vtc_user),
        .O_vtc_last     (w_vtc_last)
    );

    wire [23:0] w_tpg_rgb, w_cam_rgb;
    wire        w_cam_de, w_cam_alive;
    // Match camera address-register + synchronous RAM-read latency.
    reg [1:0] r_cam_hs = 0, r_cam_vs = 0;
    always @(posedge w_pclkx1) begin
        if (!w_pixel_rst_n) begin r_cam_hs <= 0; r_cam_vs <= 0; end
        else begin
            r_cam_hs <= {r_cam_hs[0], w_vtc_hs};
            r_cam_vs <= {r_cam_vs[0], w_vtc_vs};
        end
    end

    reg r_tpg_hs=0,r_tpg_vs=0,r_tpg_de=0;
    always @(posedge w_pclkx1) begin
        if(!w_pixel_rst_n) begin r_tpg_hs<=0;r_tpg_vs<=0;r_tpg_de<=0;end
        else begin r_tpg_hs<=w_vtc_hs;r_tpg_vs<=w_vtc_vs;r_tpg_de<=w_vtc_de;end
    end

    uitpg X_uitpg (
        .I_tpg_clk  (w_pclkx1),
        .I_tpg_rstn (w_pixel_rst_n),
        .I_tpg_vs   (w_vtc_vs),
        .I_tpg_hs   (w_vtc_hs),
        .I_tpg_de   (w_vtc_de),
        .O_tpg_vs   (),
        .O_tpg_hs   (),
        .O_tpg_de   (),
        .O_tpg_data (w_tpg_rgb)
    );

    // 摄像头实时预览：A 口 4K 流 → 抽降到 960x540 灰度 → 片内 ERAM(224 块) → 放大 2 倍显示
    cam_preview_capture #(
        .SW (960), .SH (540), .DEC_LINE (4), .DEC_CYC (1)
    ) u_cam_preview (
        .I_bc_clk    (w_a_byte_clk      ),
        .I_bc_rst_n  (w_a_rst_out       ),
        .I_pix_data  (w_a_pixel         ),
        .I_pix_valid (w_a_pixel_valid   ),
        .I_line      (w_a_in_line       ),
        .I_frame     (w_a_in_frame      ),
        .I_pclk      (w_pclkx1          ),
        .I_pclk_rst_n(w_pixel_rst_n     ),
        .I_de        (w_vtc_de          ),
        .I_vs        (w_vtc_vs          ),
        .O_rgb       (w_cam_rgb         ),
        .O_de        (w_cam_de           ),
        .O_cam_alive (w_cam_alive       ),
        .O_gray_sof(cap_sof),.O_gray_valid(cap_valid),.O_gray_last(cap_last),.O_gray_data(cap_data)
    );

    // 有摄像头画面就显示摄像头，否则显示 IP 自带测试图（方便分辨"没数据"和"没显示"）
    assign {w_rgb_r, w_rgb_g, w_rgb_b} = w_cam_alive ? w_cam_rgb : w_tpg_rgb;

    ui_HDMI_TX #(
        .DEVICE ("PH1P")
    ) X_hdmi_tx (
        .I_pixel_clk     (w_pclkx1),
        .I_serial_clk    (w_pclkx5),
        .I_rst           (~w_pll_locked),
        .I_video_in_data (ddr_rgb),
        .I_video_in_de   (ddr_de),
        .I_video_in_vs   (ddr_vs),
        .I_video_in_hs   (ddr_hs),
        .O_hdmi_clk_p    (O_hdmi_clk_p),
        .O_hdmi_tx_p     (O_hdmi_tx_p)
    );

assign cap_clk=w_a_byte_clk;
assign display_pclk=w_pclkx1;assign display_rst_n=w_pixel_rst_n;
assign display_vs=w_vtc_vs;assign display_hs=w_vtc_hs;assign display_de=w_vtc_de;
endmodule
