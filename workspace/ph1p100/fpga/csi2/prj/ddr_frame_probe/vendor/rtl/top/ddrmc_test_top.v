
`timescale 1ps/1ps


module ddrmc_test_top #(
    parameter DX_NUM     = 4 ,
    parameter BA_WIDTH   = 2 ,
    parameter BG_WIDTH   = 0 ,
    parameter ROW_WIDTH  = 13,
    parameter COL_WIDTH  = 10,
    parameter CS_WIDTH   = 1 ,
    parameter CKE_WIDTH  = 1 ,
    parameter ODT_WIDTH  = 1
)(
// clock & reset
    input                       ref_clk       ,
    input                       sys_rst_n     ,
    output                      cfg_clk       ,
    output                      ddrphy_rst_n  ,

    // APB Interface
    input                       usr_apb_pclk    ,
    input                       usr_apb_preset_n,
    input                       usr_apb_psel    ,
    input                       usr_apb_penable ,
    input                       usr_apb_pwrite  ,
    input     [          31:0]  usr_apb_paddr   ,
    input     [          31:0]  usr_apb_pwdata  ,
    output                      usr_apb_pready  ,
    output    [          31:0]  usr_apb_prdata  ,
// ddrio
    output                      ddr_ck_p      ,
    output                      ddr_ck_n      ,
    output  [        1 -1 : 0]  ddr_reset_n   ,
    output  [CKE_WIDTH-1  : 0]  ddr_cke       ,
    output  [ODT_WIDTH-1  : 0]  ddr_odt       ,
    output  [CS_WIDTH-1   : 0]  ddr_cs_n      ,
    output                      ddr_ras_n     ,
    output                      ddr_cas_n     ,
    output                      ddr_we_n      ,
    output  [BA_WIDTH  -1 : 0]  ddr_ba        ,
    output  [ROW_WIDTH -1 : 0]  ddr_addr      ,
    inout   [DX_NUM    -1 : 0]  ddr_dqs_p     ,
    inout   [DX_NUM    -1 : 0]  ddr_dqs_n     ,
    inout   [DX_NUM  *8-1 : 0]  ddr_dq        ,
    inout   [DX_NUM    -1 : 0]  ddr_dm        ,

// MISC
    output  [2:0]               led
);


///////////////////////////////////////////////////////////////////////////////////////////////////
// Local Parameter Definition
///////////////////////////////////////////////////////////////////////////////////////////////////
localparam APP_ADDR_WIDTH = BG_WIDTH + BA_WIDTH + ROW_WIDTH + COL_WIDTH;
localparam APP_DATA_WIDTH = DX_NUM*64;
localparam APP_MASK_WIDTH = DX_NUM*8;

///////////////////////////////////////////////////////////////////////////////////////////////////
// Logic Signals Definition
///////////////////////////////////////////////////////////////////////////////////////////////////
wire                  dhi_clk      ;
wire                  ddrphy_rdy   ;
(*MARK_DEBUG = "true"*) wire mtest_his_err;

// ALC PAXI
wire [APP_ADDR_WIDTH-1:0]  paxi_awaddr        ;
wire                       paxi_awvalid       ;
wire                       paxi_awready       ;
wire [APP_DATA_WIDTH-1:0]  paxi_wdata         ;
wire [APP_MASK_WIDTH-1:0]  paxi_wstrb         ;
wire                       paxi_wvalid        ;
wire                       paxi_wlast         ;
wire                       paxi_wready        ;
wire [APP_ADDR_WIDTH-1:0]  paxi_araddr        ;
wire                       paxi_arvalid       ;
wire                       paxi_arready       ;
wire                       paxi_rlast         ;
wire                       paxi_rvalid        ;
wire                       paxi_rready        ;
(*MARK_DEBUG = "true"*)wire [APP_DATA_WIDTH-1:0]  paxi_rdata ;
// apb
wire                  ddrphy_apb_pclk    ;
wire                  ddrphy_apb_prst_n  ;
wire                  ddrphy_apb_psel    ;
wire                  ddrphy_apb_penable ;
wire                  ddrphy_apb_pwrite  ;
wire [         15:0]  ddrphy_apb_paddr   ;
wire [         31:0]  ddrphy_apb_pwdata  ;
wire                  ddrphy_apb_pready  ;
wire [         31:0]  ddrphy_apb_prdata  ;

wire                  mtest_apb_pclk    ;
wire                  mtest_apb_prst_n  ;
wire                  mtest_apb_psel    ;
wire                  mtest_apb_penable ;
wire                  mtest_apb_pwrite  ;
wire [          7:0]  mtest_apb_paddr   ;
wire [         31:0]  mtest_apb_pwdata  ;
wire                  mtest_apb_pready  ;
wire [         31:0]  mtest_apb_prdata  ;



///////////////////////////////////////////////////////////////////////////////////////////////////
//  DDRPHY WRAPPER
///////////////////////////////////////////////////////////////////////////////////////////////////
ddrmc_x32 u_ddrmc_x32 (
    // clock & reset
    .ref_clk         ( ref_clk        ), // input
    .dhi_clk         ( dhi_clk        ), // output
    .cfg_clk         ( cfg_clk        ), // output

    .sys_rst_n       ( sys_rst_n      ), // input
    .ddrphy_rst_n    ( ddrphy_rst_n   ), // output
    .ddrphy_rdy      ( ddrphy_rdy     ),

    // APB
    .apb_pclk        ( ddrphy_apb_pclk    ),
    .apb_prst_n      ( ddrphy_apb_prst_n  ),
    .apb_psel        ( ddrphy_apb_psel    ),
    .apb_penable     ( ddrphy_apb_penable ),
    .apb_pwrite      ( ddrphy_apb_pwrite  ),
    .apb_paddr       ( ddrphy_apb_paddr   ),
    .apb_pwdata      ( ddrphy_apb_pwdata  ),
    .apb_pready      ( ddrphy_apb_pready  ), // output
    .apb_prdata      ( ddrphy_apb_prdata  ), // output

    .paxi_awaddr     ( paxi_awaddr        ),
    .paxi_awvalid    ( paxi_awvalid       ),
    .paxi_awready    ( paxi_awready       ),
    .paxi_wdata      ( paxi_wdata         ),
    .paxi_wstrb      ( paxi_wstrb         ),
    .paxi_wvalid     ( paxi_wvalid        ),
    .paxi_wlast      ( paxi_wlast         ),
    .paxi_wready     ( paxi_wready        ),
    .paxi_araddr     ( paxi_araddr        ),
    .paxi_arvalid    ( paxi_arvalid       ),
    .paxi_arready    ( paxi_arready       ),
    .paxi_rdata      ( paxi_rdata         ),
    .paxi_rlast      ( paxi_rlast         ),
    .paxi_rvalid     ( paxi_rvalid        ),
    .paxi_rready     ( paxi_rready        ),

    // ddrio
    .ddr_ck_p        ( ddr_ck_p           ),
    .ddr_ck_n        ( ddr_ck_n           ),
    .ddr_reset_n     ( ddr_reset_n        ),
    .ddr_cke         ( ddr_cke            ),
    .ddr_odt         ( ddr_odt            ),
    .ddr_cs_n        ( ddr_cs_n           ),
    .ddr_ras_n       ( ddr_ras_n          ),
    .ddr_cas_n       ( ddr_cas_n          ),
    .ddr_we_n        ( ddr_we_n           ),
    .ddr_ba          ( ddr_ba             ),
    .ddr_addr        ( ddr_addr           ),
    .ddr_dqs_p       ( ddr_dqs_p          ),
    .ddr_dqs_n       ( ddr_dqs_n          ),
    .ddr_dq          ( ddr_dq             ),
    .ddr_dm          ( ddr_dm             )
);


///////////////////////////////////////////////////////////////////////////////////////////////////
//  Traffic Generator
///////////////////////////////////////////////////////////////////////////////////////////////////
ph1p_ddrmc_mtest #(
    .DX_NUM     ( DX_NUM    ),
    .BG_WIDTH   ( BG_WIDTH  ),
    .BA_WIDTH   ( BA_WIDTH  ),
    .ROW_WIDTH  ( ROW_WIDTH ),
    .COL_WIDTH  ( COL_WIDTH )
) u_ddrmc_mtest (

    .clk                 (  dhi_clk             ),
    .rst_n               (  ddrphy_rst_n        ),
    // APB
    .apb_pclk            (  mtest_apb_pclk      ),
    .apb_prst_n          (  mtest_apb_prst_n    ),
    .apb_psel            (  mtest_apb_psel      ),
    .apb_penable         (  mtest_apb_penable   ),
    .apb_pwrite          (  mtest_apb_pwrite    ),
    .apb_paddr           (  mtest_apb_paddr     ),
    .apb_pwdata          (  mtest_apb_pwdata    ),
    .apb_prdata          (  mtest_apb_prdata    ),
    .apb_pready          (  mtest_apb_pready    ),

    // ctrl 
    .ddrphy_rdy          (  ddrphy_rdy          ),

    // status
    .mtest_done          (                      ),
    .mtest_run           (                      ),
    .mtest_his_err       (  mtest_his_err       ),
    .mtest_his_err_byte  (                      ),
    // pseudo-axi
    .paxi_awready        (  paxi_awready        ),
    .paxi_awaddr         (  paxi_awaddr         ),
    .paxi_awvalid        (  paxi_awvalid        ),
    .paxi_wready         (  paxi_wready         ),
    .paxi_wvalid         (  paxi_wvalid         ),
    .paxi_wdata          (  paxi_wdata          ),
    .paxi_wstrb          (  paxi_wstrb          ),
    .paxi_wlast          (  paxi_wlast          ),
    .paxi_arready        (  paxi_arready        ),
    .paxi_arvalid        (  paxi_arvalid        ),
    .paxi_araddr         (  paxi_araddr         ),
    .paxi_rready         (  paxi_rready         ),
    .paxi_rvalid         (  paxi_rvalid         ),
    .paxi_rdata          (  paxi_rdata          ),
    .paxi_rlast          (  paxi_rlast          )
);


///////////////////////////////////////////////////////////////////////////////////////////////////
// APB MUX
///////////////////////////////////////////////////////////////////////////////////////////////////

assign ddrphy_apb_pclk = cfg_clk;
assign mtest_apb_pclk  = cfg_clk;

assign ddrphy_apb_prst_n = usr_apb_preset_n;
assign mtest_apb_prst_n  = usr_apb_preset_n;

assign ddrphy_apb_psel = (usr_apb_paddr[23:20] == 4'h0) ? usr_apb_psel : 1'b0;
assign mtest_apb_psel  = (usr_apb_paddr[23:20] == 4'h1) ? usr_apb_psel : 1'b0;

assign ddrphy_apb_penable = usr_apb_penable;
assign ddrphy_apb_pwrite  = usr_apb_pwrite ;
assign ddrphy_apb_paddr   = usr_apb_paddr  ;
assign ddrphy_apb_pwdata  = usr_apb_pwdata ;

assign mtest_apb_penable  = usr_apb_penable;
assign mtest_apb_pwrite   = usr_apb_pwrite ;
assign mtest_apb_paddr    = usr_apb_paddr  ;
assign mtest_apb_pwdata   = usr_apb_pwdata ;

assign usr_apb_pready = (usr_apb_paddr[23:20] == 4'h0) ? ddrphy_apb_pready :
                        (usr_apb_paddr[23:20] == 4'h1) ? mtest_apb_pready  : 1'b1;
assign usr_apb_prdata = (usr_apb_paddr[23:20] == 4'h0) ? ddrphy_apb_prdata :
                        (usr_apb_paddr[23:20] == 4'h1) ? mtest_apb_prdata  : 32'hdeadbeef;
///////////////////////////////////////////////////////////////////////////////////////////////////
reg [31:0] clk_cnt;

always @ (posedge dhi_clk or negedge ddrphy_rst_n)
begin
    if( ddrphy_rst_n == 1'b0 )
        clk_cnt <= 32'h0;
    else begin
        clk_cnt <= clk_cnt + 1'd1 ;
    end
end

assign led[0] = ~(ddrphy_rdy && clk_cnt[25]) ;
assign led[1] = ~((|paxi_rvalid) && clk_cnt[25]) ;
assign led[2] = ~(mtest_his_err && clk_cnt[20]);

endmodule



