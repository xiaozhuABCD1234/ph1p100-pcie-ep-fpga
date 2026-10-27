// =============================================================================
//  pcie_top.v  —— 选题三 · FPGA 侧顶层（PCIe EP 空壳版，D3 用）
//
//  参考：D:\TD\work\peripheral\12_pcie_gen2x2\rtl\ep_side\ph1p_pcie_ep_top.v
//  端口名与官方一致 → 直接套 constraints\board.adc
//  复位逻辑照官方（已核对）：
//      pcie_power_on_rst = R14 按键，低有效（按下=0）
//      pcie_mperst       = P15，来自主机的 PERST#，低有效
//      power_on_rst_dly  = !pcie_mperst（高有效）→ 给 tl_power_on_rst
//      tl_clk_user_ce_n  = !pll_locked
//
//  TODO(D3)：
//   1) 生成 PLL IP（50MHz → 62.5MHz）后，把 `u_pll` 的模块名/端口对齐
//   2) 确认 PCIe IP 模块名（当前按 test\al_ip\PCI_ExpressF6F1D0D0_0 写）
//   3) constraints\pcie.sdc 里 rename_clock 的层次路径要对上你生成的 PLL
// =============================================================================
`timescale 1ns / 1ps

module pcie_top (
    // ---- HXT 高速专用 IO（无需引脚约束）----
    input  wire        ref_pad_clk_p,
    input  wire        ref_pad_clk_n,
    input  wire [1:0]  pcie_rx_p,
    input  wire [1:0]  pcie_rx_n,
    output wire [1:0]  pcie_tx_p,
    output wire [1:0]  pcie_tx_n,

    // ---- 普通 IO（见 constraints\board.adc）----
    input  wire        sys_clk,             // H4  50MHz
    input  wire        pcie_power_on_rst,   // R14 上电复位按键，低有效
    input  wire        pcie_mperst,         // P15 主机 PERST#，低有效
    input  wire        user_int_trigger,    // P14
    input  wire        rxd,                 // P16
    output wire        txd,                 // R17
    output wire [3:0]  debug_led            // E21/D21/E22/D22
);

    // =============================================================
    // 1) PLL：50MHz -> 62.5MHz（tl_clk_user）
    //    TODO(D3)：模块名以你生成的 PLL IP 为准
    // =============================================================
    wire pll_clk0;      // 62.5 MHz
    wire pll_lock;

    PLLF6F1D0P0_0 u_pll (
        .refclk  (sys_clk),
        .reset   (~pcie_power_on_rst),   // 低有效：按键按下时 =1 复位
        .clk0_out(pll_clk0),
        .lock    (pll_lock)
    );

    // =============================================================
    // 2) 复位链（照官方）
    // =============================================================
    wire  tl_clk_user = pll_clk0;
    reg   pwr_on_reg;
    reg   power_on_rst_dly;

    always @(posedge tl_clk_user or negedge pcie_power_on_rst) begin
        if (!pcie_power_on_rst) pwr_on_reg <= 1'b0;
        else                    pwr_on_reg <= pll_lock;
    end

    always @(posedge tl_clk_user or negedge pwr_on_reg) begin
        if (!pwr_on_reg) power_on_rst_dly <= 1'b1;
        else             power_on_rst_dly <= ~pcie_mperst;   // 主机发 PERST 时也复位
    end

    // =============================================================
    // 3) PCIe EP IP
    // =============================================================
    wire        tl_clk_locked;
    wire        tl_clk_gate;
    wire        pl_link_up;
    wire [4:0]  tl_ltssm;
    wire [4:0]  pl_ltssm;
    wire [1:0]  pl_equ_phase;

    // ---- TL 收（D4 起接 pcie_bar_regs.v）----
    wire        tl_rx_wait      = 1'b0;
    wire        tl_rx_masknp    = 1'b0;
    wire [47:0] tl_rx_bardec;
    wire [255:0]tl_rx_data;
    wire        tl_rx_eop;
    wire [7:0]  tl_rx_err;
    wire [9:0]  tl_rx_mchit;
    wire        tl_rx_sop;
    wire [7:0]  tl_rx_valid;

    // ---- TL 发（D4 起接 pcie_bar_regs.v）----
    wire [255:0]tl_tx_data      = 256'd0;
    wire        tl_tx_eop       = 1'b0;
    wire [7:0]  tl_tx_err       = 8'd0;
    wire        tl_tx_sop       = 1'b0;
    wire        tl_tx_stream    = 1'b0;
    wire [7:0]  tl_tx_valid     = 8'd0;
    wire        tl_tx_wait;
    wire [95:0] tl_tx_credits;

    // ---- APB4（HXT 配置口，先不接）----
    wire [31:0] apb4_prdata_o;
    wire        apb4_pready_o;
    wire        apb4_pslverr_o;

    PCI_ExpressF6F1D0D0_0 #(
        .PH1P_HXT_FAST_SIM (1'b0)
    ) u_pcie (
        .ref_pad_clk_p (ref_pad_clk_p),
        .ref_pad_clk_n (ref_pad_clk_n),
        .pcie_rx_p     (pcie_rx_p),
        .pcie_rx_n     (pcie_rx_n),
        .pcie_tx_p     (pcie_tx_p),
        .pcie_tx_n     (pcie_tx_n),

        // 时钟 / 复位
        .tl_clk_user      (tl_clk_user),
        .tl_clk_user_ce_n (~pll_lock),            // 官方同款：未锁定时 =1
        .tl_clk_locked    (tl_clk_locked),
        .tl_clk_gate      (tl_clk_gate),
        .tl_power_on_rst  (power_on_rst_dly),

        // 配置口（先悬空，D4 再接）
        .tl_cfg_pclk   (sys_clk),
        .tl_cfg_prst   (power_on_rst_dly),
        .tl_cfg_penable(1'b0), .tl_cfg_psel(1'b0), .tl_cfg_pwrite(1'b0),
        .tl_cfg_paddr  (32'd0), .tl_cfg_pstrb(4'd0), .tl_cfg_pwdata(32'd0),
        .tl_cfg_pready(), .tl_cfg_prdata(), .tl_cfg_pslverr(),
        .tl_cfg_tcvc(), .tl_cfg_busdev(),
        .tl_cfg_max_payload_size(), .tl_cfg_max_read_request_size(),
        .tl_cfg_current_link_speed(), .tl_cfg_negotiated_width(),
        .tl_cfg_read_completion_boundary(), .tl_cfg_pfregs_cmd(),
        .tl_cfg_pf0_primary_bus(8'd0), .tl_cfg_pf1_primary_bus(8'd0),

        // 中断（Legacy INTx）
        .tl_int_status   (2'd0),
        .tl_int_pincontrol(4'd0),
        .tl_int_pinstate (),

        // 链路状态
        .pl_equ_phase (pl_equ_phase),
        .tl_ltssm     (tl_ltssm),
        .pl_ltssm     (pl_ltssm),
        .pl_link_up   (pl_link_up),
        .tl_ltssm_enable(1'b1),

        // HXT APB4（先不接）
        .apb4_clk_i(sys_clk), .apb4_preset_i(power_on_rst_dly),
        .apb4_psel_i(1'b0), .apb4_penable_i(1'b0), .apb4_pwrite_i(1'b0),
        .apb4_paddr_i(32'd0), .apb4_pwdata_i(32'd0),
        .apb4_pstrb_i(4'd0), .apb4_pprot_i(3'd0),
        .apb4_prdata_o(apb4_prdata_o),
        .apb4_pready_o(apb4_pready_o),
        .apb4_pslverr_o(apb4_pslverr_o),

        // TL 收
        .tl_rx_wait(tl_rx_wait), .tl_rx_masknp(tl_rx_masknp),
        .tl_rx_bardec(tl_rx_bardec), .tl_rx_data(tl_rx_data),
        .tl_rx_eop(tl_rx_eop), .tl_rx_err(tl_rx_err),
        .tl_rx_mchit(tl_rx_mchit), .tl_rx_sop(tl_rx_sop),
        .tl_rx_valid(tl_rx_valid),

        // TL 发
        .tl_tx_data(tl_tx_data), .tl_tx_eop(tl_tx_eop), .tl_tx_err(tl_tx_err),
        .tl_tx_sop(tl_tx_sop), .tl_tx_stream(tl_tx_stream),
        .tl_tx_valid(tl_tx_valid), .tl_tx_wait(tl_tx_wait),
        .tl_tx_credits(tl_tx_credits)
    );

    // =============================================================
    // 4) LED 指示（照官方：LED0 = 复位中）
    // =============================================================
    assign debug_led[0] = power_on_rst_dly;                             // 复位中亮
    assign debug_led[1] = pll_lock;                                     // PLL 锁定
    assign debug_led[2] = tl_clk_locked;                                // PCIe 时钟锁定
    assign debug_led[3] = pl_link_up & tl_clk_locked & pll_lock;        // 链路 up

    // =============================================================
    // 5) UART（TODO(D7)：接 debug_uart 打印状态）
    // =============================================================
    assign txd = 1'b1;

    // 未使用信号占位，避免综合警告
    wire _unused = &{1'b0, user_int_trigger, rxd, tl_clk_gate,
                     tl_ltssm, pl_ltssm, pl_equ_phase,
                     tl_rx_bardec, tl_rx_data, tl_rx_eop, tl_rx_err,
                     tl_rx_mchit, tl_rx_sop, tl_rx_valid,
                     tl_tx_wait, tl_tx_credits,
                     apb4_prdata_o, apb4_pready_o, apb4_pslverr_o, 1'b0};

endmodule
