//////////////////////////////////////////////////////////////
//  Copyright(c) 2011-2022 Anlogic, Inc.
//  All Right Reserved.
//////////////////////////////////////////////////////////////
//  Company       : Anlogic
//  Filename      : ubus_bridge.v
//  Author        : Gehong - hong.ge@anlogic.com
//  Last Modified : 2023-12-27 18:09:26
//  Create        : 2022-06-23 15:40:13
//  Description   : 
//                1. receive uart message and convert to:
//                      1a. pcie tlp control signals
//                      1b. read write pcie register via apb4 bus
//                2. interrput handle
//                      1a. legacy int
//                      1b. msi
//                      1c. msix
///////////////////////////////////////////////////////////////

`timescale 1ns/1ps

module rc_ubus_bridge(

    input       wire                tl_clk_user     ,
    input       wire                uart_clk        ,
    input       wire                rst             ,

    // pcie Ubus
    input       wire                ubus_pcie_wen   ,
    input       wire    [31:0]      ubus_pcie_waddr ,
    input       wire    [31:0]      ubus_pcie_wdata ,
    input       wire                ubus_pcie_ren   ,
    input       wire    [31:0]      ubus_pcie_raddr ,
    output      wire                ubus_pcie_bken  ,
    output      wire    [31:0]      ubus_pcie_rdata ,

    // hxt Ubus
    input       wire                ubus_hxt_wen    ,
    input       wire    [31:0]      ubus_hxt_waddr  ,
    input       wire    [31:0]      ubus_hxt_wdata  ,
    input       wire                ubus_hxt_ren    ,
    input       wire    [31:0]      ubus_hxt_raddr  ,
    output      wire                ubus_hxt_bken   ,
    output      wire    [31:0]      ubus_hxt_rdata  ,

    // to tlp engine
    output      wire                sys_rst_uart_ep ,
    output      wire                sys_rst_uart_rc ,
    output      wire                op_start        ,
    output      wire    [15:0]      ep_bdf          ,
    output      wire                mw_en           ,
    output      wire                mr_en           ,
    output      wire                iow_en          ,
    output      wire                ior_en          ,
    output      wire                cfg0w_en        ,
    output      wire                cfg0r_en        ,

    output      wire    [63:0]      mw_addr         ,
    output      wire    [12:0]      mw_len          ,
    output      wire    [31:0]      mw_data         ,
    output      wire                mw_data_vld     ,
    output      wire                mw_mode         ,
    output      wire                mw_prbs_error   ,

    output      wire    [63:0]      mr_addr         ,
    output      wire    [12:0]      mr_len          ,
    input       wire    [31:0]      mr_data         ,
    output      wire                mr_data_vld     ,
    output      wire                mr_mode         ,
    output      wire                mr_prbs_clear   ,

    output      wire    [31:0]      iow_addr        ,
    output      wire    [31:0]      iow_data        ,
    output      wire    [31:0]      ior_addr        ,
    input       wire    [31:0]      ior_data        ,
    output      wire    [31:0]      cfg0w_addr      ,
    output      wire    [31:0]      cfg0w_data      ,
    output      wire    [31:0]      cfg0r_addr      ,
    input       wire    [31:0]      cfg0r_data      ,
    input       wire                mw_op_over      ,
    input       wire                mr_op_over      ,
    input       wire                iow_op_over     ,
    input       wire                ior_op_over     ,
    input       wire                cfg0w_op_over   ,
    input       wire                cfg0r_op_over   ,

    // error debug
    output      wire                error_ep        ,
    output      wire                error_length    ,
    output      wire                error_address   ,

    // INT
    output      wire                legacy_int_clear,
    input       wire                inta            ,
    input       wire                intb            ,
    input       wire                intc            ,
    input       wire                intd            ,
    
    // MSI
    input       wire                msi_ctrl_int    ,
    input       wire    [31:0]      msi_ctrl_int_vec,
    output      wire    [31:0]      msi_ctrl_clear  ,
    
    // APB4 bus
    output      wire                tl_cfg_prst     ,
    output      wire                tl_cfg_penable  ,
    output      wire                tl_cfg_psel     ,
    output      wire                tl_cfg_pwrite   ,
    output      wire    [31:0]      tl_cfg_paddr    ,
    output      wire    [3:0]       tl_cfg_pstrb    ,
    output      wire    [31:0]      tl_cfg_pwdata   ,
    input       wire                tl_cfg_pready   ,
    input       wire    [31:0]      tl_cfg_prdata   ,
    input       wire                tl_cfg_pslverr  ,
    
    //To HXT APB
    output      wire                hxt_apb4_psel_o ,
    output      wire                hxt_apb4_penable_o,
    output      wire                hxt_apb4_pwrite_o ,
    output      wire    [31:0]      hxt_apb4_paddr_o  ,
    output      wire    [31:0]      hxt_apb4_pwdata_o ,
    output      wire    [3:0]       hxt_apb4_pstrb_o  ,
    output      wire    [2:0]       hxt_apb4_pprot_o  ,
    input       wire    [31:0]      hxt_apb4_prdata_i ,
    input       wire                hxt_apb4_pready_i ,
    input       wire                hxt_apb4_pslverr_i 

   );
    
// ====================================================================
// Parameter/wire/reg
// ====================================================================
    localparam          UBUS_BRDGE_TLP  =   8'hFF,
                        UBUS_BRDGE_HXT  =   8'hF0,
                        UBUS_BRDGE_APB  =   8'h00;

    reg                 ubus_pcie_wen_dly     ;
    reg     [31:0]      ubus_pcie_waddr_dly   ;
    reg     [31:0]      ubus_pcie_wdata_dly   ;
    reg                 ubus_pcie_ren_dly     ;
    reg     [31:0]      ubus_pcie_raddr_dly   ;
    reg                 ubus_pcie_bken_dly    ;
    reg     [31:0]      ubus_pcie_rdata_dly   ;

    reg                 ubus_hxt_wen_dly      ;
    reg     [31:0]      ubus_hxt_waddr_dly    ;
    reg     [31:0]      ubus_hxt_wdata_dly    ;
    reg                 ubus_hxt_ren_dly      ;
    reg     [31:0]      ubus_hxt_raddr_dly    ;
    reg                 ubus_hxt_bken_dly     ;
    reg     [31:0]      ubus_hxt_rdata_dly    ;

    reg                 ubus_wen_apb          ;
    reg     [31:0]      ubus_waddr_apb        ;
    reg     [31:0]      ubus_wdata_apb        ;
    reg                 ubus_ren_apb          ;
    reg     [31:0]      ubus_raddr_apb        ;
    wire                ubus_bken_apb         ;
    wire    [31:0]      ubus_rdata_abp        ;

    reg                 ubus_wen_tlp          ;
    reg     [31:0]      ubus_waddr_tlp        ;
    reg     [31:0]      ubus_wdata_tlp        ;
    reg                 ubus_ren_tlp          ;
    reg     [31:0]      ubus_raddr_tlp        ;
    wire                ubus_bken_tlp         ;
    wire    [31:0]      ubus_rdata_tlp        ;

    reg                 ubus_wen_hxt          ;
    reg     [31:0]      ubus_waddr_hxt        ;
    reg     [31:0]      ubus_wdata_hxt        ;
    reg                 ubus_ren_hxt          ;
    reg     [31:0]      ubus_raddr_hxt        ;
    wire                ubus_bken_hxt         ;
    wire    [31:0]      ubus_rdata_hxt        ;

// ====================================================================
// Main Code
// ====================================================================

//pcie ubus from uart module
always@(posedge tl_clk_user or posedge rst)
begin
    if(rst) begin
        ubus_pcie_wen_dly     <= 'b0;
        ubus_pcie_waddr_dly   <= 'b0;
        ubus_pcie_wdata_dly   <= 'b0;
        ubus_pcie_ren_dly     <= 'b0;
        ubus_pcie_raddr_dly   <= 'b0;
    end else begin
        ubus_pcie_wen_dly     <= ubus_pcie_wen     ;
        ubus_pcie_waddr_dly   <= ubus_pcie_waddr   ;
        ubus_pcie_wdata_dly   <= ubus_pcie_wdata   ;
        ubus_pcie_ren_dly     <= ubus_pcie_ren     ;
        ubus_pcie_raddr_dly   <= ubus_pcie_raddr   ;
    end
end

//hxt ubus from uart module
always@(posedge uart_clk or posedge rst)
begin
    if(rst) begin
        ubus_hxt_wen_dly      <= 'b0;
        ubus_hxt_waddr_dly    <= 'b0;
        ubus_hxt_wdata_dly    <= 'b0;
        ubus_hxt_ren_dly      <= 'b0;
        ubus_hxt_raddr_dly    <= 'b0;
    end else begin
        ubus_hxt_wen_dly      <= ubus_hxt_wen     ;
        ubus_hxt_waddr_dly    <= ubus_hxt_waddr   ;
        ubus_hxt_wdata_dly    <= ubus_hxt_wdata   ;
        ubus_hxt_ren_dly      <= ubus_hxt_ren     ;
        ubus_hxt_raddr_dly    <= ubus_hxt_raddr   ;
    end
end

// mux to tlp channel
always@(posedge tl_clk_user or posedge rst) begin 
    if(rst) begin 
        ubus_wen_tlp    <= 'b0;
        ubus_waddr_tlp  <= 'b0;
        ubus_wdata_tlp  <= 'b0;
        ubus_ren_tlp    <= 'b0;
        ubus_raddr_tlp  <= 'b0;
    end else begin 

        if(ubus_pcie_wen_dly & (ubus_pcie_waddr_dly[31:24] == UBUS_BRDGE_TLP)) begin 
            ubus_wen_tlp    <= ubus_pcie_wen_dly  ;
            ubus_waddr_tlp  <= ubus_pcie_waddr_dly;
            ubus_wdata_tlp  <= ubus_pcie_wdata_dly;
        end else begin 
            ubus_wen_tlp    <= 'b0;
            ubus_waddr_tlp  <= 'b0;
            ubus_wdata_tlp  <= 'b0;
        end

        if(ubus_pcie_ren_dly & (ubus_pcie_raddr_dly[31:24] == UBUS_BRDGE_TLP)) begin 
            ubus_ren_tlp    <= ubus_pcie_ren_dly    ;
            ubus_raddr_tlp  <= ubus_pcie_raddr_dly  ;
        end else begin 
            ubus_ren_tlp    <= 'b0;
            ubus_raddr_tlp  <= 'b0;
        end
    end
end

// mux to apb channel
always@(posedge tl_clk_user or posedge rst) begin 
    if(rst) begin 
        ubus_wen_apb    <= 'b0;
        ubus_waddr_apb  <= 'b0;
        ubus_wdata_apb  <= 'b0;
        ubus_ren_apb    <= 'b0;
        ubus_raddr_apb  <= 'b0;
    end else begin 

        if(ubus_pcie_wen_dly & (ubus_pcie_waddr_dly[31:24] == UBUS_BRDGE_APB)) begin 
            ubus_wen_apb    <= ubus_pcie_wen_dly  ;
            ubus_waddr_apb  <= ubus_pcie_waddr_dly;
            ubus_wdata_apb  <= ubus_pcie_wdata_dly;
        end else begin 
            ubus_wen_apb    <= 'b0;
            ubus_waddr_apb  <= 'b0;
            ubus_wdata_apb  <= 'b0;
        end

        if(ubus_pcie_ren_dly & (ubus_pcie_raddr_dly[31:24] == UBUS_BRDGE_APB)) begin 
            ubus_ren_apb    <= ubus_pcie_ren_dly    ;
            ubus_raddr_apb  <= ubus_pcie_raddr_dly  ;
        end else begin 
            ubus_ren_apb    <= 'b0;
            ubus_raddr_apb  <= 'b0;
        end
    end
end
// mux to hxt apb channel
always@(posedge uart_clk or posedge rst) 
begin 
    if(rst) begin 
        ubus_wen_hxt    <= 'b0;
        ubus_waddr_hxt  <= 'b0;
        ubus_wdata_hxt  <= 'b0;
        ubus_ren_hxt    <= 'b0;
        ubus_raddr_hxt  <= 'b0;
    end else begin 

        if(ubus_hxt_wen_dly & (ubus_hxt_waddr_dly[23:16] == UBUS_BRDGE_HXT)) begin 
            ubus_wen_hxt    <= ubus_hxt_wen_dly  ;
            ubus_waddr_hxt  <= ubus_hxt_waddr_dly;
            ubus_wdata_hxt  <= ubus_hxt_wdata_dly;
        end else begin 
            ubus_wen_hxt    <= 'b0;
            ubus_waddr_hxt  <= 'b0;
            ubus_wdata_hxt  <= 'b0;
        end

        if(ubus_hxt_ren_dly & (ubus_hxt_raddr_dly[23:16] == UBUS_BRDGE_HXT)) begin 
            ubus_ren_hxt   <= ubus_hxt_ren_dly    ;
            ubus_raddr_hxt <= ubus_hxt_raddr_dly  ;
        end else begin 
            ubus_ren_hxt   <= 'b0;
            ubus_raddr_hxt <= 'b0;
        end
    end
end
// readback data mux to pcie ubus
always@(posedge tl_clk_user or posedge rst)
begin
    if(rst) begin
        ubus_pcie_bken_dly    <= 'b0;
        ubus_pcie_rdata_dly   <= 'b0;
    end else begin

        ubus_pcie_bken_dly    <= ubus_bken_apb | ubus_bken_tlp ;

        if( ubus_bken_apb )
        ubus_pcie_rdata_dly   <= ubus_rdata_abp ;
        else if( ubus_bken_tlp )
        ubus_pcie_rdata_dly   <= ubus_rdata_tlp ;
    end
end

assign  ubus_pcie_bken = ubus_pcie_bken_dly;
assign  ubus_pcie_rdata= ubus_pcie_rdata_dly;

// readback data mux to hxt ubus
always@(posedge uart_clk or posedge rst)
begin
    if(rst) begin
        ubus_hxt_bken_dly    <= 'b0;
        ubus_hxt_rdata_dly   <= 'b0;
    end else begin
        ubus_hxt_bken_dly    <= ubus_bken_hxt ;
        if( ubus_bken_hxt )
        ubus_hxt_rdata_dly   <= ubus_rdata_hxt;
    end
end

assign  ubus_hxt_bken = ubus_hxt_bken_dly;
assign  ubus_hxt_rdata= ubus_hxt_rdata_dly;

// ====================================================================
// UBUS to TLP bridge
// ====================================================================
ubus2tlp u_ubus2tlp(
    .clk             (tl_clk_user     ),
    .rst             (rst             ),

    // UBUS
    .ubus_wen        (ubus_wen_tlp    ),
    .ubus_waddr      (ubus_waddr_tlp  ),
    .ubus_wdata      (ubus_wdata_tlp  ),
    .ubus_ren        (ubus_ren_tlp    ),
    .ubus_raddr      (ubus_raddr_tlp  ),
    .ubus_bken       (ubus_bken_tlp   ),
    .ubus_rdata      (ubus_rdata_tlp  ),
    
    // INT
    .legacy_int_clear(legacy_int_clear),
    .inta            (inta            ),
    .intb            (intb            ),
    .intc            (intc            ),
    .intd            (intd            ),
    
    // MSI
    .msi_ctrl_int    (msi_ctrl_int    ),
    .msi_ctrl_int_vec(msi_ctrl_int_vec),
    .msi_ctrl_clear  (msi_ctrl_clear  ),

    // to tlp engine
    .sys_rst_uart_ep (sys_rst_uart_ep ),
    .sys_rst_uart_rc (sys_rst_uart_rc ),
    .op_start        (op_start        ),
    .ep_bdf          (ep_bdf          ),
    .mw_en           (mw_en           ),
    .mr_en           (mr_en           ),
    .iow_en          (iow_en          ),
    .ior_en          (ior_en          ),
    .cfg0w_en        (cfg0w_en        ),
    .cfg0r_en        (cfg0r_en        ),
    .mw_addr         (mw_addr         ),
    .mw_len          (mw_len          ),
    .mw_data         (mw_data         ),
    .mw_data_vld     (mw_data_vld     ),
    .mw_mode         (mw_mode         ),
    .mw_prbs_error   (mw_prbs_error   ),

    .mr_addr         (mr_addr         ),
    .mr_len          (mr_len          ),
    .mr_data         (mr_data         ),
    .mr_data_vld     (mr_data_vld     ),
    .mr_mode         (mr_mode         ),
    .mr_prbs_clear   (mr_prbs_clear   ),

    .iow_addr        (iow_addr        ),
    .iow_data        (iow_data        ),
    .ior_addr        (ior_addr        ),
    .ior_data        (ior_data        ),
    .cfg0w_addr      (cfg0w_addr      ),
    .cfg0w_data      (cfg0w_data      ),
    .cfg0r_addr      (cfg0r_addr      ),
    .cfg0r_data      (cfg0r_data      ),
    .mw_op_over      (mw_op_over      ),
    .mr_op_over      (mr_op_over      ),
    .iow_op_over     (iow_op_over     ),
    .ior_op_over     (ior_op_over     ),
    .cfg0w_op_over   (cfg0w_op_over   ),
    .cfg0r_op_over   (cfg0r_op_over   ),
    // error debug
    .error_ep        (error_ep        ),
    .error_length    (error_length    ),
    .error_address   (error_address   )
);
// ====================================================================
// UBUS to APB bridge
// ====================================================================
ubus2pcie_apb u_ubus2apb
(
    .clk             (tl_clk_user     ),
    .rst             (rst             ),

    // UBUS
    .ubus_wen        (ubus_wen_apb    ),
    .ubus_waddr      (ubus_waddr_apb  ),
    .ubus_wdata      (ubus_wdata_apb  ),
    .ubus_ren        (ubus_ren_apb    ),
    .ubus_raddr      (ubus_raddr_apb  ),
    .ubus_bken       (ubus_bken_apb   ),
    .ubus_rdata      (ubus_rdata_abp  ),

    // APB
    .tl_cfg_prst     (tl_cfg_prst     ),
    .tl_cfg_penable  (tl_cfg_penable  ),
    .tl_cfg_psel     (tl_cfg_psel     ),
    .tl_cfg_pwrite   (tl_cfg_pwrite   ),
    .tl_cfg_paddr    (tl_cfg_paddr    ),
    .tl_cfg_pstrb    (tl_cfg_pstrb    ),
    .tl_cfg_pwdata   (tl_cfg_pwdata   ),
    .tl_cfg_pready   (tl_cfg_pready   ),
    .tl_cfg_prdata   (tl_cfg_prdata   ),
    .tl_cfg_pslverr  (tl_cfg_pslverr  )
);

// ====================================================================
// UBUS to HXT APB bridge
// ====================================================================
 ubus2hxt_apb u_hxt_ubus2apb 
(
    .clk             (uart_clk          ),
    .rst             (rst               ),
    // UBUS
    .ubus_wen        (ubus_wen_hxt      ),
    .ubus_waddr      (ubus_waddr_hxt    ),
    .ubus_wdata      (ubus_wdata_hxt    ),
    .ubus_ren        (ubus_ren_hxt      ),
    .ubus_raddr      (ubus_raddr_hxt    ),
    .ubus_bken       (ubus_bken_hxt     ),
    .ubus_rdata      (ubus_rdata_hxt    ),

    // APB
    .tl_cfg_prst     (                  ),
    .tl_cfg_penable  (hxt_apb4_penable_o),
    .tl_cfg_psel     (hxt_apb4_psel_o   ),
    .tl_cfg_pwrite   (hxt_apb4_pwrite_o ),
    .tl_cfg_pprot    (hxt_apb4_pprot_o  ),
    .tl_cfg_paddr    (hxt_apb4_paddr_o  ),
    .tl_cfg_pstrb    (hxt_apb4_pstrb_o  ),
    .tl_cfg_pwdata   (hxt_apb4_pwdata_o ),
    .tl_cfg_pready   (hxt_apb4_pready_i ),
    .tl_cfg_prdata   (hxt_apb4_prdata_i ),
    .tl_cfg_pslverr  (hxt_apb4_pslverr_i)
);
endmodule
