//////////////////////////////////////////////////////////////
//  Copyright(c) 2011-2022 Anlogic, Inc.
//  All Right Reserved.
//////////////////////////////////////////////////////////////
//  Company       : Anlogic
//  Filename      : pcie_rc_tx_engine.v
//  Author        : Gehong - hong.ge@anlogic.com
//  Last Modified : 2023-12-27 18:40:27
//  Create        : 2022-05-12 10:37:58
//  Description   : 
//                  Notice:
//                  1.Due to there is no pcie switch, RC send type0
//                    cfg tlp pkg directly.
///////////////////////////////////////////////////////////////

`timescale  1ns/1ps

module  pcie_rc_tx_engine(
    // Clock and Reset
    input       wire                tl_clk_user            ,
    input       wire                tl_rst_user            ,

    // Tx Control signals
    input       wire                tl_op_start            ,
    input       wire    [15:0]      tl_ep_bdf              ,// include pfs and vfs

    input       wire                tl_mw_en               ,
    input       wire    [63:0]      tl_mw_addr             ,
    input       wire    [12:0]      tl_mw_len              ,
    input       wire    [31:0]      tl_mw_data             ,
    input       wire                tl_mw_data_vld         ,
    input       wire                tl_mw_mode             ,
    input       wire                tl_mw_prbs_error       ,

    input       wire                tl_mr_en               ,
    input       wire    [63:0]      tl_mr_addr             ,
    input       wire    [12:0]      tl_mr_len              ,

    input       wire                tl_iow_en              ,
    input       wire    [31:0]      tl_iow_addr            ,
    input       wire    [31:0]      tl_iow_data            ,
    input       wire                tl_ior_en              ,
    input       wire    [31:0]      tl_ior_addr            ,

    input       wire                tl_cfg0w_en            ,
    input       wire    [31:0]      tl_cfg0w_addr          ,
    input       wire    [31:0]      tl_cfg0w_data          ,
    input       wire                tl_cfg0r_en            ,
    input       wire    [31:0]      tl_cfg0r_addr          ,

    output      reg                 tl_mw_op_over          ,

    // error debug
    input       wire                tl_error_ep            ,
    input       wire                tl_error_length        ,
    input       wire                tl_error_address       ,
    
    // TX interface 
    output      reg     [255:0]     tl_tx_data             ,
    output      reg                 tl_tx_eop              ,
    output      wire    [7:0]       tl_tx_err              ,
    output      reg                 tl_tx_sop              ,
    output      wire                tl_tx_stream           ,
    output      reg     [7:0]       tl_tx_valid            ,
    input       wire                tl_tx_wait             ,
    input       wire    [95:0]      tl_tx_credits          

);

`include "../common/TLP_FMT_TYPE.v"
`include "../common/BDF.v"

// ====================================================================
// Parameter|Wire|Reg
// ====================================================================
reg     [10:0]      tl_tx_engine_state=0  ;
// pipeline for input signals
reg                 tl_op_start_ff      ;
reg                 tl_op_start_pose    ;
reg                 tl_mw_en_ff         ;
reg     [63:0]      tl_mw_addr_ff       ;
reg     [12:0]      tl_mw_len_ff        ;
reg     [31:0]      tl_mw_data_ff       ;
reg                 tl_mw_data_vld_ff   ;
reg                 tl_mw_mode_ff       ;
reg                 tl_mw_prbs_error_ff ;
reg                 tl_mr_en_ff         ;
reg     [63:0]      tl_mr_addr_ff       ;
reg     [12:0]      tl_mr_len_ff        ;
reg                 tl_iow_en_ff        ;
reg     [31:0]      tl_iow_addr_ff      ;
reg     [31:0]      tl_iow_data_ff      ;
reg                 tl_ior_en_ff        ;
reg     [31:0]      tl_ior_addr_ff      ;
reg                 tl_cfg0w_en_ff      ;
reg     [31:0]      tl_cfg0w_addr_ff    ;
reg     [31:0]      tl_cfg0w_data_ff    ;
reg                 tl_cfg0r_en_ff      ;
reg     [31:0]      tl_cfg0r_addr_ff    ;

reg                 tl_error_ep_ff      ;
reg                 tl_error_length_ff  ;
reg                 tl_error_address_ff ;

// internal msic signals
reg     [7:0]       np_tag              ;
reg                 mem_addr_is_64bit   ;
reg     [3:0]       mem_last_be         ;
reg                 tl_tx_first_cycle   ;

reg     [12:0]      mwdata_cycle        ;
reg     [7:0]       mwdata_cycle_valid  ;
wire    [7:0]       mwdata_cycle_valid_64bit;
wire    [9:0]       mwdata_cycle_valid_32bit;
wire    [16:0]      mwdata_cycle_valid_tmp;

// prbs
reg                 tl_tx_prbs_first    ;
reg                 tl_tx_prbs_init     ;
reg     [3:0]       tl_tx_prbs_init_cnt ;
reg                 tl_tx_prbs_send     ;
wire    [255:0]     prbs_output_data    ;
reg     [255:0]     prbs_output_data_dly;
reg     [255:0]     prbs_output_data_mux;
reg                 tl_tx_prbs_ok       ;
reg                 prbs_rst            ;

// user data
reg                 user_memwr_flag     ;
wire    [31:0]      user_memwr_wrdata   ;
reg     [9:0]       user_memwr_wraddr   ;
wire    [255:0]     user_memwr_rddata   ;
wire    [255:0]     user_memwr_rddata_inv;
reg     [255:0]     user_memwr_rddata_ff;
reg     [255:0]     user_memwr_rddata_mux;
reg     [6:0]       user_memwr_rdaddr   ;

// mux data 
wire    [255:0]     tl_tx_memwr_data    ;

localparam      TL_TX_IDLE          = 11'b000_0000_0001,
                TL_TX_TYPE_DEF      = 11'b000_0000_0010,
                TL_TX_MEMWR         = 11'b000_0000_0100,
                TL_TX_MEMRD         = 11'b000_0000_1000,
                TL_TX_CFGWR         = 11'b000_0001_0000,
                TL_TX_CFGRD         = 11'b000_0010_0000,
                TL_TX_IOWR          = 11'b000_0100_0000,
                TL_TX_IORD          = 11'b000_1000_0000,
                TL_TX_ERROR_EP      = 11'b001_0000_0000,
                TL_TX_ERROR_ADDRESS = 11'b010_0000_0000,
                TL_TX_ERROR_LENGTH  = 11'b100_0000_0000;

// ====================================================================
// Main Code
// ====================================================================

// pipeline input signals
always@(posedge tl_clk_user or posedge tl_rst_user) begin
    if(tl_rst_user) begin
        tl_op_start_ff          <= 1'b0 ;
        tl_op_start_pose        <= 1'b0 ;
        tl_mw_en_ff             <= 1'b0 ;
        tl_mw_addr_ff           <= 64'b0;
        tl_mw_len_ff            <= 11'b0;
        tl_mw_data_ff           <= 32'b0;
        tl_mw_data_vld_ff       <= 1'b0 ;
        tl_mw_mode_ff           <= 1'b0 ;
        tl_mw_prbs_error_ff     <= 1'b0 ;
        tl_mr_en_ff             <= 1'b0 ;
        tl_mr_addr_ff           <= 64'b0;
        tl_mr_len_ff            <= 11'b0;
        tl_iow_en_ff            <= 1'b0 ;
        tl_iow_addr_ff          <= 32'b0;
        tl_iow_data_ff          <= 32'b0;
        tl_ior_en_ff            <= 1'b0 ;
        tl_ior_addr_ff          <= 32'b0;
        tl_cfg0w_en_ff          <= 1'b0 ;
        tl_cfg0w_addr_ff        <= 32'b0;
        tl_cfg0w_data_ff        <= 32'b0;
        tl_cfg0r_en_ff          <= 1'b0 ;
        tl_cfg0r_addr_ff        <= 32'b0;
        tl_error_ep_ff          <= 1'b0 ;
        tl_error_length_ff      <= 1'b0 ;
        tl_error_address_ff     <= 1'b0 ;
    end else begin
        tl_op_start_ff          <= tl_op_start          ;
        tl_mw_en_ff             <= tl_mw_en             ;
        tl_mw_addr_ff           <= tl_mw_addr           ;
        tl_mw_len_ff            <= tl_mw_len            ;
        tl_mw_data_ff           <= tl_mw_data           ;
        tl_mw_data_vld_ff       <= tl_mw_data_vld       ;
        tl_mw_mode_ff           <= tl_mw_mode           ;
        tl_mw_prbs_error_ff     <= tl_mw_prbs_error     ; 
        tl_mr_en_ff             <= tl_mr_en             ;
        tl_mr_addr_ff           <= tl_mr_addr           ;
        tl_mr_len_ff            <= tl_mr_len            ;
        tl_iow_en_ff            <= tl_iow_en            ;
        tl_iow_addr_ff          <= tl_iow_addr          ;
        tl_iow_data_ff          <= tl_iow_data          ;
        tl_ior_en_ff            <= tl_ior_en            ;
        tl_ior_addr_ff          <= tl_ior_addr          ;
        tl_cfg0w_en_ff          <= tl_cfg0w_en          ;
        tl_cfg0w_addr_ff        <= tl_cfg0w_addr        ;
        tl_cfg0w_data_ff        <= tl_cfg0w_data        ;
        tl_cfg0r_en_ff          <= tl_cfg0r_en          ;
        tl_cfg0r_addr_ff        <= tl_cfg0r_addr        ;
        tl_error_ep_ff          <= tl_error_ep          ;
        tl_error_length_ff      <= tl_error_length      ;
        tl_error_address_ff     <= tl_error_address     ;
        tl_op_start_pose        <= (tl_op_start & !tl_op_start_ff);
    end
end


always@(posedge tl_clk_user) begin
    if(tl_rst_user) begin
        tl_tx_engine_state <= TL_TX_IDLE;
        tl_tx_prbs_send    <= 1'b0;
        tl_tx_prbs_first   <= 1'b0;
    end else begin
        case(tl_tx_engine_state)
            TL_TX_IDLE : begin
                tl_tx_prbs_send    <= 1'b0;
                if(tl_op_start_pose) begin
                    tl_tx_engine_state <= TL_TX_TYPE_DEF;
//                end else if( tl_error_ep_ff  ) begin
//                    tl_tx_engine_state <= TL_TX_ERROR_EP;
//                end else if( tl_error_length_ff  ) begin
//                    tl_tx_engine_state <= TL_TX_ERROR_LENGTH;
//                end else if( tl_error_address_ff  ) begin
//                    tl_tx_engine_state <= TL_TX_ERROR_ADDRESS;
                end else begin
                    tl_tx_engine_state <= TL_TX_IDLE;
                end
            end

            TL_TX_TYPE_DEF : begin
                tl_tx_prbs_first   <= tl_mw_en_ff    ? 1'b1        : 1'b0;
                tl_tx_prbs_send    <= tl_mw_en_ff    ? 1'b1        : 1'b0;
                tl_tx_engine_state <= tl_mw_en_ff    ? TL_TX_MEMWR :
                                      tl_mr_en_ff    ? TL_TX_MEMRD :
                                      tl_cfg0w_en_ff ? TL_TX_CFGWR :
                                      tl_cfg0r_en_ff ? TL_TX_CFGRD :
                                      tl_iow_en_ff   ? TL_TX_IOWR  :
                                      tl_ior_en_ff   ? TL_TX_IORD  : TL_TX_IDLE;
            end

            TL_TX_MEMWR: begin
                tl_tx_prbs_first <= 1'b0;
                if(tl_tx_eop & (!tl_tx_wait) ) begin
                    tl_tx_engine_state <= TL_TX_IDLE;
                end else begin
                    tl_tx_engine_state <= TL_TX_MEMWR;
                end
            end

            TL_TX_MEMRD: begin // to be
                if(tl_tx_eop & (!tl_tx_wait) ) begin
                    tl_tx_engine_state <= TL_TX_IDLE;
                end else begin
                    tl_tx_engine_state <= TL_TX_MEMRD;
                end
            end

            TL_TX_CFGWR: begin
                if(tl_tx_eop & (!tl_tx_wait) ) begin
                    tl_tx_engine_state <= TL_TX_IDLE;
                end else begin
                    tl_tx_engine_state <= TL_TX_CFGWR;
                end
            end

            TL_TX_CFGRD: begin
                if(tl_tx_eop & (!tl_tx_wait) ) begin
                    tl_tx_engine_state <= TL_TX_IDLE;
                end else begin
                    tl_tx_engine_state <= TL_TX_CFGRD;
                end
            end

            TL_TX_IOWR : begin
                if(tl_tx_eop & (!tl_tx_wait) ) begin
                    tl_tx_engine_state <= TL_TX_IDLE;
                end else begin
                    tl_tx_engine_state <= TL_TX_IOWR ;
                end
            end

            TL_TX_IORD : begin
                if(tl_tx_eop & (!tl_tx_wait) ) begin
                    tl_tx_engine_state <= TL_TX_IDLE;
                end else begin
                    tl_tx_engine_state <= TL_TX_IORD;
                end
            end
            default : tl_tx_engine_state <= TL_TX_IDLE;
        endcase
    end
end

// state machine 3 : output signals control
assign  tl_tx_err       = 8'b0;
assign  tl_tx_stream    = 1'b0;

always@(posedge tl_clk_user or posedge tl_rst_user) begin
    if(tl_rst_user) begin
        tl_tx_eop       <= 1'b0;
        tl_tx_sop       <= 1'b0;
        tl_tx_valid     <= 8'h0;
        tl_mw_op_over   <= 1'b0;
    end else begin
        case(tl_tx_engine_state)

            TL_TX_IDLE:begin
                tl_tx_eop   <= 1'b0;
                tl_tx_sop   <= 1'b0;
                tl_tx_valid <= 8'h0;
                tl_mw_op_over<= 1'b0;
            end

            TL_TX_MEMWR: begin // to be
                if( tl_tx_first_cycle ) // first cycle
                    tl_tx_sop <= 1'b1;
                else
                    tl_tx_sop <= 1'b0;
                if(tl_tx_eop & (!tl_tx_wait))
                    tl_tx_eop <= 1'b0;
                else if( tl_tx_first_cycle & mwdata_cycle == 13'd0 )
                    tl_tx_eop <= 1'b1;
                else if( tl_tx_valid[7] & (!tl_tx_wait) & (mwdata_cycle == 13'd0) )
                    tl_tx_eop <= 1'b1;
                if(tl_tx_first_cycle | tl_tx_valid[7] & (!tl_tx_wait) )
                    tl_tx_valid <= mwdata_cycle_valid;
                if( tl_tx_eop & tl_tx_valid[7] & (!tl_tx_wait)  )
                    tl_mw_op_over<= 1'b1;
            end

            TL_TX_MEMRD:begin
                if( tl_tx_eop & tl_tx_sop & !tl_tx_wait) begin
                    tl_tx_eop       <= 1'b0;
                    tl_tx_sop       <= 1'b0;
                    tl_tx_valid     <= 8'h0;
                end else begin
                    tl_tx_eop       <= 1'b1;
                    tl_tx_sop       <= 1'b1;
                    tl_tx_valid     <= mem_addr_is_64bit ? 8'hF0 : 8'hE0;
                end

            end

//            TL_TX_ERROR_EP: begin
//                if( tl_tx_eop & tl_tx_sop & !tl_tx_wait) begin
//                    tl_tx_eop       <= 1'b0;
//                    tl_tx_sop       <= 1'b0;
//                    tl_tx_valid     <= 8'h0;
//                end else begin
//                    tl_tx_eop       <= 1'b1;
//                    tl_tx_sop       <= 1'b1;
//                    tl_tx_valid     <= 8'hf0;
//                end
//            end

//            TL_TX_ERROR_ADDRESS:begin
//                if( tl_tx_eop & tl_tx_sop & !tl_tx_wait) begin
//                    tl_tx_eop       <= 1'b0;
//                    tl_tx_sop       <= 1'b0;
//                    tl_tx_valid     <= 8'h0;
//                end else begin
//                    tl_tx_eop       <= 1'b1;
//                    tl_tx_sop       <= 1'b1;
//                    tl_tx_valid     <= 8'hc0;
//                end
//            end

//            TL_TX_ERROR_LENGTH:begin
//                if( tl_tx_eop & tl_tx_sop & !tl_tx_wait) begin
//                    tl_tx_eop       <= 1'b0;
//                    tl_tx_sop       <= 1'b0;
//                    tl_tx_valid     <= 8'h0;
//                end else begin
//                    tl_tx_eop       <= 1'b1;
//                    tl_tx_sop       <= 1'b1;
//                    tl_tx_valid     <= 8'hf0;
//                end
//            end

            TL_TX_CFGWR,TL_TX_IOWR: begin
                if( tl_tx_eop & tl_tx_sop & !tl_tx_wait) begin
                    tl_tx_eop       <= 1'b0;
                    tl_tx_sop       <= 1'b0;
                    tl_tx_valid     <= 8'h0;
                end else begin
                    tl_tx_eop       <= 1'b1;
                    tl_tx_sop       <= 1'b1;
                    tl_tx_valid     <= 8'hF0;
                end

            end

            TL_TX_CFGRD,TL_TX_IORD: begin
                if( tl_tx_eop & tl_tx_sop & !tl_tx_wait) begin
                    tl_tx_eop       <= 1'b0;
                    tl_tx_sop       <= 1'b0;
                    tl_tx_valid     <= 8'h0;
                end else begin
                    tl_tx_eop       <= 1'b1;
                    tl_tx_sop       <= 1'b1;
                    tl_tx_valid     <= 8'hE0;
                end
            end
        endcase
    end
end

always@(posedge tl_clk_user ) begin
    case(tl_tx_engine_state)
        TL_TX_MEMWR: begin // to be
            if(mem_addr_is_64bit) begin
                if(tl_tx_first_cycle)
                    tl_tx_data <= {`MWR_FMT_4DW                         ,
                                   `MWR_TYPE                            ,
                                   1'b0                                 , // R
                                   3'b0                                 , // tc
                                   1'b0                                 , // R
                                   1'b0                                 , // attr[2]
                                   1'b0                                 , // R
                                   1'b0                                 , // th
                                   1'b0                                 , // td
                                   1'b0                                 , // ep
                                   2'b0                                 , // attr
                                   2'b0                                 , // AT
                                   tl_mw_len_ff[11:2]                   , // length(dw)
                                   {`RC_BUS_NUM,`RC_DEV_NUM,`RC_FUN_NUM}, // requester id
                                   8'd0                                 , // np_tag
                                   mem_last_be[3:0]                     , // last be
                                   4'hf                                 , // first be
                                   tl_mw_addr_ff[63:2]                  , // address
                                   2'b0                                 , // ph
                                   tl_tx_memwr_data[255:128]
                                   };
                else if(tl_tx_valid[7] & (!tl_tx_wait) )
                     tl_tx_data <= tl_tx_memwr_data[255:0];
            end else begin
                if(tl_tx_first_cycle)
                    tl_tx_data <= {`MWR_FMT_3DW                         ,
                                   `MWR_TYPE                            ,
                                   1'b0                                 , // R
                                   3'b0                                 , // tc
                                   1'b0                                 , // R
                                   1'b0                                 , // attr[2]
                                   1'b0                                 , // R
                                   1'b0                                 , // th
                                   1'b0                                 , // td
                                   1'b0                                 , // ep
                                   2'b0                                 , // attr
                                   2'b0                                 , // AT
                                   tl_mw_len_ff[11:2]                   , // length(dw)
                                   {`RC_BUS_NUM,`RC_DEV_NUM,`RC_FUN_NUM}, // requester id
                                   8'd0                                 , // np_tag
                                   mem_last_be[3:0]                     , // last be
                                   4'hf                                 , // first be
                                   tl_mw_addr_ff[31:2]                  , // address
                                   2'b0                                 , // ph
                                   tl_tx_memwr_data[255:96]
                                   };
                else if(tl_tx_valid[7] & (!tl_tx_wait) )
                     tl_tx_data <= tl_tx_memwr_data[255:0];
             end
        end

        TL_TX_MEMRD: begin // to be
            if(mem_addr_is_64bit) begin
                    tl_tx_data <= {`MRD_FMT_4DW                         ,
                                   `MRD_TYPE                            ,
                                   1'b0                                 , // R
                                   3'b0                                 , // tc
                                   1'b0                                 , // R
                                   1'b0                                 , // attr[2]
                                   1'b0                                 , // R
                                   1'b0                                 , // th
                                   1'b0                                 , // td
                                   1'b0                                 , // ep
                                   2'b0                                 , // attr
                                   2'b0                                 , // AT
                                   tl_mr_len_ff[11:2]                   , // length(dw)
                                   {`RC_BUS_NUM,`RC_DEV_NUM,`RC_FUN_NUM}, // requester id
                                   np_tag[7:0]                          , // np_tag
                                   mem_last_be[3:0]                     , // last be
                                   4'hf                                 , // first be
                                   tl_mr_addr_ff[63:2]                  , // address
                                   2'b0                                 , // ph
                                   128'd0
                                   };
            end else begin
                    tl_tx_data <= {`MRD_FMT_3DW                         ,
                                   `MRD_TYPE                            ,
                                   1'b0                                 , // R
                                   3'b0                                 , // tc
                                   1'b0                                 , // R
                                   1'b0                                 , // attr[2]
                                   1'b0                                 , // R
                                   1'b0                                 , // th
                                   1'b0                                 , // td
                                   1'b0                                 , // ep
                                   2'b0                                 , // attr
                                   2'b0                                 , // AT
                                   tl_mr_len_ff[11:2]                   , // length(dw)
                                   {`RC_BUS_NUM,`RC_DEV_NUM,`RC_FUN_NUM}, // requester id
                                   np_tag[7:0]                          , // np_tag
                                   mem_last_be[3:0]                     , // last be
                                   4'hf                                 , // first be
                                   tl_mr_addr_ff[31:2]                  , // address
                                   2'b0                                 , // ph
                                   160'd0
                                   };
            end
        end

        // type0 cfg write
        TL_TX_CFGWR: begin
            tl_tx_data <= {`CFGWR0_FMT                          ,
                           `CFGWR0_TYPE                         ,
                           1'b0                                 , // R
                           3'b0                                 , // tc
                           1'b0                                 , // R
                           1'b0                                 , // attr[2]
                           1'b0                                 , // R
                           1'b0                                 , // th
                           1'b0                                 , // td
                           1'b0                                 , // ep
                           2'b0                                 , // attr
                           2'b0                                 , // AT
                           10'b1                                , // length(dw)
                           {`RC_BUS_NUM,`RC_DEV_NUM,`RC_FUN_NUM}, // requester id
                           8'd0                                 , // np_tag
                           4'b0                                 , // last be
                           4'hf                                 , // first be
                           tl_ep_bdf[15:0]                      ,
                           4'b0                                 , // R
                           tl_cfg0w_addr[11:0]                  , // reg number
                           tl_cfg0w_data[31:0]                  , // cfgw data
                           128'd0                                 // R
                          };
        end

        // type0 cfg write
        TL_TX_CFGRD: begin
            tl_tx_data <= {`CFGRD0_FMT                          ,
                           `CFGRD0_TYPE                         ,
                           1'b0                                 , // R
                           3'b0                                 , // tc
                           1'b0                                 , // R
                           1'b0                                 , // attr[2]
                           1'b0                                 , // R
                           1'b0                                 , // th
                           1'b0                                 , // td
                           1'b0                                 , // ep
                           2'b0                                 , // attr
                           2'b0                                 , // AT
                           10'b1                                , // length(dw)
                           {`RC_BUS_NUM,`RC_DEV_NUM,`RC_FUN_NUM}, // requester id
                           np_tag[7:0]                          , // np_tag
                           4'b0                                 , // last be
                           4'hf                                 , // first be
                           tl_ep_bdf[15:0]                      ,
                           4'b0                                 , // R
                           tl_cfg0r_addr[11:0]                  , // reg number
                           160'd0                                 // R
                          };
        end

        // io wr
        TL_TX_IOWR: begin
            tl_tx_data <= {`IOWR_FMT                            ,
                           `IOWR_TYPE                           ,
                           1'b0                                 , // R
                           3'b0                                 , // tc
                           1'b0                                 , // R
                           1'b0                                 , // attr[2]
                           1'b0                                 , // R
                           1'b0                                 , // th
                           1'b0                                 , // td
                           1'b0                                 , // ep
                           2'b0                                 , // attr
                           2'b0                                 , // AT
                           10'b1                                , // length(dw)
                           {`RC_BUS_NUM,`RC_DEV_NUM,`RC_FUN_NUM}, // requester id
                           8'd0                                 , // np_tag
                           4'b0                                 , // last be
                           4'hf                                 , // first be
                           tl_iow_addr_ff[31:0]                 ,
                           tl_iow_data_ff[31:0]                 ,
                           128'd0                                 // R
                          };
        end

        // io wr
        TL_TX_IORD: begin
            tl_tx_data <= {`IORD_FMT                            ,
                           `IORD_TYPE                           ,
                           1'b0                                 , // R
                           3'b0                                 , // tc
                           1'b0                                 , // R
                           1'b0                                 , // attr[2]
                           1'b0                                 , // R
                           1'b0                                 , // th
                           1'b0                                 , // td
                           1'b0                                 , // ep
                           2'b0                                 , // attr
                           2'b0                                 , // AT
                           10'b1                                , // length(dw)
                           {`RC_BUS_NUM,`RC_DEV_NUM,`RC_FUN_NUM}, // requester id
                           8'd0                                 , // np_tag
                           4'b0                                 , // last be
                           4'hf                                 , // first be
                           tl_ior_addr_ff[31:0]                 ,
                           160'd0                               // R
                          };
        end
//        TL_TX_ERROR_EP: begin
//            tl_tx_data <= {`MWR_FMT_3DW                         ,
//                           `MWR_TYPE                            ,
//                           1'b0                                 , // R
//                           3'b0                                 , // tc
//                           1'b0                                 , // R
//                           1'b0                                 , // attr[2]
//                           1'b0                                 , // R
//                           1'b0                                 , // th
//                           1'b0                                 , // td
//                           1'b1                                 , // ep
//                           2'b0                                 , // attr
//                           2'b0                                 , // AT
//                           9'h1                                 , // length(dw)
//                           {`RC_BUS_NUM,`RC_DEV_NUM,`RC_FUN_NUM}, // requester id
//                           8'd0                                 , // np_tag
//                           4'hf                                 , // last be
//                           4'hf                                 , // first be
//                           `ADDR_BAR0_BA                        , // address
//                           416'd0
//                           };

//        end

//        TL_TX_ERROR_LENGTH: begin
//            tl_tx_data <= {`MWR_FMT_3DW                         ,
//                           `MWR_TYPE                            ,
//                           1'b0                                 , // R
//                           3'b0                                 , // tc
//                           1'b0                                 , // R
//                           1'b0                                 , // attr[2]
//                           1'b0                                 , // R
//                           1'b0                                 , // th
//                           1'b0                                 , // td
//                           1'b0                                 , // ep
//                           2'b0                                 , // attr
//                           2'b0                                 , // AT
//                           9'h2                                 , // length(dw)
//                           {`RC_BUS_NUM,`RC_DEV_NUM,`RC_FUN_NUM}, // requester id
//                           8'd0                                 , // np_tag
//                           4'hf                                 , // last be
//                           4'hf                                 , // first be
//                           `ADDR_BAR0_BA                        , // address
//                           416'd0
//                           };
//        end

//        TL_TX_ERROR_ADDRESS: begin
//            tl_tx_data <= {`MWR_FMT_3DW                         ,
//                           `MWR_TYPE                            ,
//                           1'b0                                 , // R
//                           3'b0                                 , // tc
//                           1'b0                                 , // R
//                           1'b0                                 , // attr[2]
//                           1'b0                                 , // R
//                           1'b0                                 , // th
//                           1'b0                                 , // td
//                           1'b0                                 , // ep
//                           2'b0                                 , // attr
//                           2'b0                                 , // AT
//                           9'h1                                 , // length(dw)
//                           {`RC_BUS_NUM,`RC_DEV_NUM,`RC_FUN_NUM}, // requester id
//                           8'd0                                 , // np_tag
//                           4'hf                                 , // last be
//                           4'hf                                 , // first be
//                           `ADDR_BAR0_BA                        , // address
//                           416'd0
//                           };
//        end

    endcase
end

// rc only send non-post pkg, so np_tag increase every tlp pkg
always@(posedge tl_clk_user or posedge tl_rst_user)
begin
    if(tl_rst_user)
        np_tag <= 8'b0;
    else if(tl_tx_engine_state == TL_TX_MEMRD ||  tl_tx_engine_state == TL_TX_CFGRD  || tl_tx_engine_state == TL_TX_IORD )  begin
        if(tl_tx_eop & !tl_tx_wait )
            np_tag <= np_tag + 1'b1;
    end
end

always@(posedge tl_clk_user or posedge tl_rst_user)
begin
    if(tl_rst_user)
        mem_addr_is_64bit <= 1'b0;
    else if(tl_mw_en_ff & (|tl_mw_addr_ff[63:32])  | tl_mr_en_ff & (|tl_mr_addr_ff[63:32]) )
        mem_addr_is_64bit <= 1'b1;
    else
        mem_addr_is_64bit <= 1'b0;
end

always@(posedge tl_clk_user or posedge tl_rst_user) 
begin 
    if(tl_rst_user)
        tl_tx_first_cycle <= 1'b1;
    else if(tl_tx_engine_state == TL_TX_IDLE || tl_tx_engine_state == TL_TX_TYPE_DEF )
        tl_tx_first_cycle <= 1'b1;
    else 
        tl_tx_first_cycle <= 1'b0;
end

always@(posedge tl_clk_user or posedge tl_rst_user)
begin
    if(tl_rst_user)
        mem_last_be    <= 4'h0;
    else if(tl_mw_en_ff )
        mem_last_be    <= (tl_mw_len_ff > 4 ) ? 4'hf : 4'h0;
    else if(tl_mr_en_ff )
        mem_last_be    <= (tl_mr_len_ff > 4 ) ? 4'hf : 4'h0;
    else
        mem_last_be    <= 4'h0;
end

assign  mwdata_cycle_valid_64bit = 8'hf0        >> (mwdata_cycle[5:2] + (|mwdata_cycle[1:0]) );
assign  mwdata_cycle_valid_32bit = 10'h3_e0     >> (mwdata_cycle[5:2] + (|mwdata_cycle[1:0]) );
assign  mwdata_cycle_valid_tmp   = 16'hff_00     >> (mwdata_cycle[5:2] + (|mwdata_cycle[1:0]) );

always@(posedge tl_clk_user or posedge tl_rst_user) begin
    if(tl_rst_user) begin
        mwdata_cycle        <= 13'h0;
        mwdata_cycle_valid  <= 8'h0;
    end else begin
        case(tl_tx_engine_state)
            TL_TX_IDLE : begin
                mwdata_cycle <= tl_mw_len_ff[12:0];
            end
            TL_TX_TYPE_DEF : begin
                if(mem_addr_is_64bit) begin
                    mwdata_cycle        <= mwdata_cycle > 16 ? mwdata_cycle - 16 : 13'd0;
                    mwdata_cycle_valid  <= mwdata_cycle > 16 ? 8'hff          : {4'hf,mwdata_cycle_valid_64bit[3:0] };
                end else begin
                    mwdata_cycle        <= mwdata_cycle > 20 ? mwdata_cycle - 20 : 13'd0;
                    mwdata_cycle_valid  <= mwdata_cycle > 20 ? 8'hff          : {3'h7,mwdata_cycle_valid_32bit[4:0] };
                end
            end
            TL_TX_MEMWR:begin
                if( (tl_tx_valid[7] & !tl_tx_wait) | tl_tx_first_cycle) begin
                    mwdata_cycle        <= mwdata_cycle > 32 ? mwdata_cycle - 32 : 13'd0;
                    mwdata_cycle_valid  <= mwdata_cycle > 32 ? 8'hff          : mwdata_cycle_valid_tmp[7:0];
                end
            end
        default:;
        endcase
    end
end

// ====================================================================
// two mode send memory write data 
// 0. prbs mode, the data is generated by prbs mode, and send to tx interface
// 1. user mode, the data is generated by user, the user send the data by uart, and cache into internal eram
// ====================================================================

// prbs data generate, use 1 prbs_gen module, output data width is 32bits

always@(posedge tl_clk_user or posedge tl_rst_user)
begin
    if(tl_rst_user) begin
        tl_tx_prbs_init    <= 1'b0;
        tl_tx_prbs_init_cnt<= 4'd0;
    end else if( tl_mw_en_ff == 1'b0 ) begin
        tl_tx_prbs_init    <= 1'b0;
        tl_tx_prbs_init_cnt<= 4'd0;
    end else begin
        tl_tx_prbs_init_cnt<= tl_tx_prbs_init_cnt[3]     ? tl_tx_prbs_init_cnt : tl_tx_prbs_init_cnt + 1'b1;
        tl_tx_prbs_init    <= tl_tx_prbs_init_cnt==4'd7||
                              tl_tx_prbs_init_cnt==4'd6|| 
                              tl_tx_prbs_init_cnt==4'd5  ? 1'b1 : 1'b0;
    end  
end

always@( * )
begin
    if( tl_tx_prbs_init == 1'b1 )
        tl_tx_prbs_ok = 1'b1;  // first read prbs pipeline data out
    else if( tl_tx_prbs_send == 1'b1)
        tl_tx_prbs_ok =  (  ( tl_tx_engine_state == TL_TX_MEMWR    && tl_tx_first_cycle == 1'b1 ) || 
                             ( tl_tx_valid[7]    == 1'b1           && tl_tx_wait        == 1'b0 )
                          )                                                                           ? 1'b1 : 1'b0;
    else    
        tl_tx_prbs_ok = 1'b0;
end

always@(posedge tl_clk_user or posedge tl_rst_user) begin
    if(tl_rst_user) begin
        prbs_rst             <= 1'b1 ;
    end else begin
        prbs_rst             <= ~tl_mw_en ;
    end
end

// prbs data generate, use 16 prbs_gen module,every module has
// independent enable signal, and output data width is 32bits
genvar i;
generate
    for(i=0;i<8;i=i+1)
    begin : prbs_gen
        prbs_gen_pcie
        #(
            .PRBS_PLOY  ( 15'h6000                        ),
            .DAT_W      ( 32                              ),
            .PRBS_WIDTH ( 35                              )
        )u_prbs_gen_pcie
        (
            .clk        ( tl_clk_user                     ),
            .rst        ( prbs_rst                        ),
            .ena        ( tl_tx_prbs_ok                   ),
            .i_err      ( tl_mw_prbs_error_ff             ),
            .o_dat      ( prbs_output_data[32*i+31:32*i]  )
        );
    end
endgenerate

always@(posedge tl_clk_user or posedge tl_rst_user) begin
    if( tl_rst_user )
        prbs_output_data_dly <= 32'd0;
    else if( tl_tx_prbs_ok )
        prbs_output_data_dly <= prbs_output_data;
end

always@(posedge tl_clk_user or posedge tl_rst_user) begin
    if( tl_rst_user ) begin
        prbs_output_data_mux <= 32'd0;
    end else if( tl_tx_engine_state == TL_TX_IDLE ) begin
        prbs_output_data_mux  <= prbs_output_data_dly ;
    end else if( (tl_tx_valid[7] & !tl_tx_wait) || ( tl_tx_engine_state == TL_TX_MEMWR && tl_tx_first_cycle == 1'b1 ) ) begin
        prbs_output_data_mux  <= mem_addr_is_64bit ? {prbs_output_data_dly[127:  0],prbs_output_data[255:128]} : 
                                                     {prbs_output_data_dly[95 :  0],prbs_output_data[255:96] } ;  
    end    
end

// user data chache, user eram to cache the user data form uart
// write path
always@(posedge tl_clk_user or posedge tl_rst_user) begin
    if(tl_rst_user) begin
        user_memwr_flag   <= 1'b0;
        user_memwr_wraddr <= 10'b0;
    end else begin
        user_memwr_flag   <= tl_mw_en & tl_mw_mode;
        user_memwr_wraddr <= user_memwr_flag   == 1'b0 ? 10'b0             :  
                             tl_mw_data_vld_ff == 1'b0 ? user_memwr_wraddr : user_memwr_wraddr + 1'b1 ;
    end
end

assign  user_memwr_wrdata = tl_mw_data_ff; 

// rd path
assign  user_memwr_rddata_inv = {   user_memwr_rddata[31 : 0],
                                    user_memwr_rddata[63 :32],
                                    user_memwr_rddata[95 :64],
                                    user_memwr_rddata[127:96],
                                    user_memwr_rddata[128+31 :128+ 0],
                                    user_memwr_rddata[128+63 :128+32],
                                    user_memwr_rddata[128+95 :128+64],
                                    user_memwr_rddata[128+127:128+96] 
                                };
always@(posedge tl_clk_user or posedge tl_rst_user) begin
    if(tl_rst_user) begin
        user_memwr_rddata_ff  <= 256'b0;
    end else if( (tl_tx_valid[7] & !tl_tx_wait) | tl_tx_first_cycle ) begin
        user_memwr_rddata_ff  <= user_memwr_rddata_inv;
    end
end

always@(posedge tl_clk_user or posedge tl_rst_user) begin
    if(tl_rst_user) begin
        user_memwr_rdaddr <= 7'b0;
    end else if( tl_mw_mode_ff ) begin
        user_memwr_rdaddr <= ( ( tl_tx_engine_state == TL_TX_IDLE     && tl_op_start_pose  == 1'b1 ) || 
                               ( tl_tx_engine_state == TL_TX_TYPE_DEF                              ) || 
                               ( tl_tx_engine_state == TL_TX_MEMWR    && tl_tx_first_cycle == 1'b1 ) ||
                               ( tl_tx_valid[7]    == 1'b1           && tl_tx_wait        == 1'b0 )
                             )                                                                       ? user_memwr_rdaddr + 1'b1 : user_memwr_rdaddr ;
    end else begin
        user_memwr_rdaddr <= 7'b0;
    end
end

always@(posedge tl_clk_user or posedge tl_rst_user) begin
    if(tl_rst_user) begin
        user_memwr_rddata_mux <= 256'b0;
    end else if( tl_tx_engine_state == TL_TX_IDLE ) begin
        user_memwr_rddata_mux <= user_memwr_rddata_inv;
    end else if( (tl_tx_valid[7] & !tl_tx_wait) || ( tl_tx_engine_state == TL_TX_MEMWR && tl_tx_first_cycle == 1'b1 ) ) begin
        user_memwr_rddata_mux <= mem_addr_is_64bit ? {user_memwr_rddata_ff[127:  0],user_memwr_rddata_inv[255:128]} : 
                                                     {user_memwr_rddata_ff[95 :  0],user_memwr_rddata_inv[255:96]} ;  
    end
end
pcie_tx_ram u_pcie_tx_eram(
    .clka           (tl_clk_user        ),
    .cea            (user_memwr_flag    ),
    .dia            (user_memwr_wrdata  ),
    .addra          (user_memwr_wraddr  ),

    .ceb            (1'b1               ),
    .addrb          (user_memwr_rdaddr  ),
    .dob            (user_memwr_rddata  )
);

assign  tl_tx_memwr_data = tl_mw_mode_ff ? user_memwr_rddata_mux  : prbs_output_data_mux  ;

endmodule

