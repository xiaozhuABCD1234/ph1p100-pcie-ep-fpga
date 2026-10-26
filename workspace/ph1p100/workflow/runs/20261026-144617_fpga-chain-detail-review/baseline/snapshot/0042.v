// Board wrapper derived from vendor ddrmc_test_top.v.
// Preserves DDR IP and initialization APB; replaces the old traffic generator.

`timescale 1ps/1ps


module ddrmc_display_top #(
    parameter FRAME_BYTES = 518400,
    parameter DX_NUM     = 4 ,
    parameter BA_WIDTH   = 3 ,
    parameter BG_WIDTH   = 0 ,
    parameter ROW_WIDTH  = 14,
    parameter COL_WIDTH  = 10,
    parameter CS_WIDTH   = 1 ,
    parameter CKE_WIDTH  = 1 ,
    parameter ODT_WIDTH  = 1
)(
// clock & reset
    input display_pclk,display_rst_n,display_vs,display_hs,display_de,
    output[23:0] ddr_rgb,output ddr_vs,ddr_hs,ddr_de,
    input cap_clk,cap_sof,cap_valid,cap_last,input[7:0] cap_data,
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
(* MARK_DEBUG="true" *) wire [31:0] passed_frames,failed_frames,published_frames,protocol_errors;


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
wire [APP_DATA_WIDTH-1:0]  paxi_rdata ;
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

    // Retain the vendor refresh policy; do not request a manual refresh.
    .usr_ref_type    ( 2'b00              ),
    .usr_ref_req     ( 1'b0               ),

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


(* MARK_DEBUG="true" *) wire[31:0] capture_drops,underflow_frames,shown_frames;
camera_ddr_display #(.SW(960),.SH(540)) u_capture(
 .clk(dhi_clk),.cap_clk(cap_clk),.rst_n(ddrphy_rst_n&&display_rst_n),.ddr_ready(ddrphy_rdy),
 .pclk(display_pclk),.vs(display_vs),.hs(display_hs),.de(display_de),
 .rgb(ddr_rgb),.out_vs(ddr_vs),.out_hs(ddr_hs),.out_de(ddr_de),.underflow_frames(underflow_frames),.shown_frames(shown_frames),
 .sof(cap_sof),.pixel_valid(cap_valid),.pixel_last(cap_last),.pixel(cap_data),
 .passed_frames(passed_frames),.failed_frames(failed_frames),.published_frames(published_frames),.protocol_errors(protocol_errors),.capture_drops(capture_drops),
 .paxi_awaddr(paxi_awaddr),.paxi_awvalid(paxi_awvalid),.paxi_awready(paxi_awready),
 .paxi_wdata(paxi_wdata),.paxi_wstrb(paxi_wstrb),.paxi_wvalid(paxi_wvalid),.paxi_wlast(paxi_wlast),.paxi_wready(paxi_wready),
 .paxi_araddr(paxi_araddr),.paxi_arvalid(paxi_arvalid),.paxi_arready(paxi_arready),
 .paxi_rdata(paxi_rdata),.paxi_rvalid(paxi_rvalid),.paxi_rlast(paxi_rlast),.paxi_rready(paxi_rready));
// Register the pixel-domain error flag before its two-stage crossing.
reg pixel_error_seen;
always @(posedge display_pclk or negedge ddrphy_rst_n)begin
 if(!ddrphy_rst_n)pixel_error_seen<=0;else if(underflow_frames!=0)pixel_error_seen<=1;
end
(* ASYNC_REG="TRUE" *) reg[1:0] pixel_error_sync;
always @(posedge dhi_clk or negedge ddrphy_rst_n)begin
 if(!ddrphy_rst_n)pixel_error_sync<=0;else pixel_error_sync<={pixel_error_sync[0],pixel_error_seen};
end
reg [25:0] clk_cnt;
reg pass_seen,error_seen;
always @(posedge dhi_clk or negedge ddrphy_rst_n)begin
 if(!ddrphy_rst_n)begin clk_cnt<=0;pass_seen<=0;error_seen<=0;end
 else begin
  clk_cnt<=clk_cnt+1'b1;
  if(passed_frames!=0)pass_seen<=1;
  if(failed_frames!=0||protocol_errors!=0||pixel_error_sync[1])error_seen<=1;
 end
end
// Active-low LEDs: ready heartbeat, a complete good frame seen, sticky failure.
assign led[0]=~(ddrphy_rdy&&clk_cnt[25]);
assign led[1]=~pass_seen;
assign led[2]=~error_seen;

assign ddrphy_apb_prst_n=usr_apb_preset_n;
assign ddrphy_apb_psel=usr_apb_psel&&(usr_apb_paddr[23:20]==0);
assign ddrphy_apb_penable=usr_apb_penable;
assign ddrphy_apb_pwrite=usr_apb_pwrite;
assign ddrphy_apb_paddr=usr_apb_paddr[15:0];
assign ddrphy_apb_pwdata=usr_apb_pwdata;
// cfg_clk is the APB clock supplied to the board MCU, as in the vendor top.
// Only single-bit diagnostic flags cross; no incoherent multi-bit counter reads.
(* ASYNC_REG="TRUE" *) reg [2:0] flags_meta,flags_sync;
always @(posedge usr_apb_pclk or negedge usr_apb_preset_n)begin
 if(!usr_apb_preset_n)begin flags_meta<=0;flags_sync<=0;end
 else begin flags_meta<={error_seen,pass_seen,ddrphy_rdy};flags_sync<=flags_meta;end
end
reg [31:0] status_rdata;
always @* begin
 case(usr_apb_paddr[7:0])
  8'hf0:status_rdata=32'h46525031; // FRP1, distinct from the old mtest register map
  8'hf4:status_rdata={29'd0,flags_sync}; // bit0 ready, bit1 good-frame seen, bit2 failure
  default:status_rdata=32'hdeadbeef;
 endcase
end
// The old mtest window is intentionally not emulated. Writes have no effect.
assign usr_apb_pready=(usr_apb_paddr[23:20]==0)?ddrphy_apb_pready:1'b1;
assign usr_apb_prdata=(usr_apb_paddr[23:20]==0)?ddrphy_apb_prdata:
 (usr_apb_paddr[23:20]==1)?status_rdata:32'hdeadbeef;
endmodule
