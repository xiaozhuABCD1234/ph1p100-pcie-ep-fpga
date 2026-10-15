//////////////////////////////////////////////////////////////
//  Copyright(c) 2011-2022 Anlogic, Inc.
//  All Right Reserved.
//////////////////////////////////////////////////////////////
//  Company       : Anlogic
//  Filename      : pcie_uart.v
//  Author        : Dexin - dexin.guo@anlogic.com
//  Last Modified : 2023-10-20 10:45:11
//  Create        : 2023-09-19 16:35:24
//  Description   :
//
///////////////////////////////////////////////////////////////

module pcie_uart
#(
    parameter BAUDRATE = 115200,
    parameter CLK_RATE = 20 // Hz
)
(
    input       wire            aux_clk             ,
    input       wire            core_clk            ,
    input       wire            rst_n               ,

    // uart
    input       wire            rx                  ,
    output      wire            tx                  ,

    // ubus for pcie apb clock region
    output      wire            ubus_pcie_wen       ,
    output      wire    [31:0]  ubus_pcie_waddr     ,
    output      wire    [31:0]  ubus_pcie_wdata     ,
    output      wire            ubus_pcie_ren       ,
    output      wire    [31:0]  ubus_pcie_raddr     ,
    input       wire            ubus_pcie_bken      ,
    input       wire    [31:0]  ubus_pcie_rdata     ,

    // ubus for hxt apb clock region
    output      wire            ubus_hxt_wen        ,
    output      wire    [31:0]  ubus_hxt_waddr      ,
    output      wire    [31:0]  ubus_hxt_wdata      ,
    output      wire            ubus_hxt_ren        ,
    output      wire    [31:0]  ubus_hxt_raddr      ,
    input       wire            ubus_hxt_bken       ,
    input       wire    [31:0]  ubus_hxt_rdata
);


// ====================================================================
// Parameter/wire/reg
// ====================================================================

    reg                 uart_axu_rst_n      ;
    reg                 uart_core_rst_n     ;
    wire                clk_bps_rx          ;
    wire                clk_bps_tx          ;
    wire                bps_start_rx        ;
    wire                bps_start_tx        ;

    wire                aux_rx_en           ;
    wire    [7:0]       aux_rx_data         ;
    reg                 aux_tx_en           ;
    reg     [7:0]       aux_tx_data         ;
    wire                aux_tx_ready        ;

    wire                pcie_rx_en          ;
    wire    [7:0]       pcie_rx_data        ;
    wire                pcie_tx_en          ;
    wire    [7:0]       pcie_tx_data        ;
    wire                pcie_tx_ready       ;

    wire                aux_pcie_rx_en      ;
    wire    [7:0]       aux_pcie_rx_data    ;
    wire                aux_pcie_tx_en      ;
    wire    [7:0]       aux_pcie_tx_data    ;
    wire                aux_pcie_tx_ready   ;

    wire                aux_hxt_rx_en       ;
    wire    [7:0]       aux_hxt_rx_data     ;
    wire                aux_hxt_tx_en       ;
    wire    [7:0]       aux_hxt_tx_data     ;
    wire                aux_hxt_tx_ready    ;

// ====================================================================
// Main Code
// ====================================================================

always@(posedge aux_clk or posedge rst_n )
    if(rst_n)
        uart_axu_rst_n <= 1'b1;
    else
        uart_axu_rst_n <= 1'b0;

always@(posedge core_clk or posedge  rst_n )
    if(rst_n)
        uart_core_rst_n <= 1'b1;
    else
        uart_core_rst_n <= 1'b0;


always@(posedge aux_clk or posedge rst_n )
begin
    if(rst_n) begin
        aux_tx_en   <= 1'b0;  
        aux_tx_data <= 8'd0;
    end else begin
        aux_tx_en   <= aux_hxt_tx_en | aux_pcie_tx_en;  
        aux_tx_data <= aux_hxt_tx_en ? aux_hxt_tx_data :
                       aux_pcie_tx_en? aux_pcie_tx_data: aux_tx_data;
    end
end

assign  aux_hxt_tx_ready  = aux_tx_ready;
assign  aux_pcie_tx_ready = aux_tx_ready;

bps_setting
#(
        .BPS_SET        (   BAUDRATE            ),
        .CLK_PERIO      (   CLK_RATE            )
)
bps_rx(
        .clk            (   aux_clk             ),
        .rst_n          (   uart_axu_rst_n      ),
        .clk_bps        (   clk_bps_rx          ),
        .bps_start      (   bps_start_rx        )
);

bps_setting
#(
        .BPS_SET        (   BAUDRATE            ),
        .CLK_PERIO      (   CLK_RATE            )
)
bps_tx(
        .clk            (   aux_clk             ),
        .rst_n          (   uart_axu_rst_n      ),
        .clk_bps        (   clk_bps_tx          ),
        .bps_start      (   bps_start_tx        )
);

uart_rx_setting uart_rx_setting_u
(
        .clk            (   aux_clk             ),
        .rst_n          (   uart_axu_rst_n      ),
        .uart_rx        (   rx                  ),

        .rx_data        (   aux_rx_data         ),
        .rx_en          (   aux_rx_en           ),
        .clk_bps        (   clk_bps_rx          ),
        .bps_start      (   bps_start_rx        )
);

uart_tx_setting uart_tx_setting_u
(
        .clk            (   aux_clk             ),
        .rst_n          (   uart_axu_rst_n      ),
        .data           (   aux_tx_data         ),
        .x_int          (   aux_tx_en           ),
        .clk_bps        (   clk_bps_tx          ),
        .uart_tx        (   tx                  ),
        .bps_start      (   bps_start_tx        ),
        .tx_ready       (   aux_tx_ready        )
 );



// ====================================================================
// UBUS to PCIe APB bridge
// PCIe APB is high speed clock, so there is a cdc module
// ====================================================================

assign  aux_pcie_rx_en      = aux_rx_en  ;
assign  aux_pcie_rx_data    = aux_rx_data;

uart_cdc u_uart_cdc(

        .aux_clk        (aux_clk                ),
        .uart_axu_rst_n (uart_axu_rst_n         ),
        .aux_rx_en      (aux_pcie_rx_en         ),
        .aux_rx_data    (aux_pcie_rx_data       ),
        .aux_tx_en      (aux_pcie_tx_en         ),
        .aux_tx_data    (aux_pcie_tx_data       ),
        .aux_tx_ready   (aux_pcie_tx_ready      ),

        .core_clk       (core_clk               ),
        .uart_core_rst_n(uart_core_rst_n        ),
        .core_rx_en     (pcie_rx_en             ),
        .core_rx_data   (pcie_rx_data           ),
        .core_tx_en     (pcie_tx_en             ),
        .core_tx_data   (pcie_tx_data           ),
        .core_tx_ready  (pcie_tx_ready          )
);

pcie_uprotocol u_pcie_uprotocol
(
        .clk            (core_clk               ),
        .rst_n          (uart_core_rst_n        ),
        // uart-rx
        .rx_en          (pcie_rx_en             ),
        .rx_data        (pcie_rx_data           ),

        // uart-tx
        .tx_en          (pcie_tx_en             ),
        .tx_data        (pcie_tx_data           ),
        .tx_ready       (pcie_tx_ready          ),

        // ubus write
        .ubus_wen       (ubus_pcie_wen          ),
        .ubus_waddr     (ubus_pcie_waddr        ),
        .ubus_wdata     (ubus_pcie_wdata        ),

        // ubus read
        .ubus_ren       (ubus_pcie_ren          ),
        .ubus_raddr     (ubus_pcie_raddr        ),
        .ubus_bken      (ubus_pcie_bken         ),
        .ubus_rdata     (ubus_pcie_rdata        )
);

// ====================================================================
// UBUS to HXT APB bridge
// HXT APB is low speed clock, so there not need cdc module
// ====================================================================

assign  aux_hxt_rx_en       = aux_rx_en  ;
assign  aux_hxt_rx_data     = aux_rx_data;

pcie_uprotocol u_hxt_uprotocol
(
        .clk            (aux_clk                ),
        .rst_n          (uart_axu_rst_n         ),
        // uart-rx
        .rx_en          (aux_hxt_rx_en          ),
        .rx_data        (aux_hxt_rx_data        ),

        // uart-tx
        .tx_en          (aux_hxt_tx_en          ),
        .tx_data        (aux_hxt_tx_data        ),
        .tx_ready       (aux_hxt_tx_ready       ),

        // ubus write
        .ubus_wen       (ubus_hxt_wen           ),
        .ubus_waddr     (ubus_hxt_waddr         ),
        .ubus_wdata     (ubus_hxt_wdata         ),

        // ubus read
        .ubus_ren       (ubus_hxt_ren           ),
        .ubus_raddr     (ubus_hxt_raddr         ),
        .ubus_bken      (ubus_hxt_bken          ),
        .ubus_rdata     (ubus_hxt_rdata         )
);

endmodule
