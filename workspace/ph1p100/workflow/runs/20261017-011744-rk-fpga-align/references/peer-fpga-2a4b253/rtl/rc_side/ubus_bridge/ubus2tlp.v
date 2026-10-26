//////////////////////////////////////////////////////////////
//  Copyright(c) 2011-2022 Anlogic, Inc.
//  All Right Reserved.
//////////////////////////////////////////////////////////////
//  Company       : Anlogic
//  Filename      : ubus2tlp.v
//  Author        : Gehong - hong.ge@anlogic.com
//  Last Modified : 2023-12-27 18:23:50
//  Create        : 2022-06-23 20:15:08
//  Description   : 
//                  conver ubus protocol to internal pcie test loigc
///////////////////////////////////////////////////////////////

`timescale 1ns/1ps

module ubus2tlp(
    input       wire                clk             ,
    input       wire                rst             ,

    // UBUS
    input       wire                ubus_wen        ,
    input       wire    [31:0]      ubus_waddr      ,
    input       wire    [31:0]      ubus_wdata      ,
    input       wire                ubus_ren        ,
    input       wire    [31:0]      ubus_raddr      ,
    output      reg                 ubus_bken       ,
    output      reg     [31:0]      ubus_rdata      ,
    
    // INT
    output      reg                 legacy_int_clear,
    input       wire                inta            ,
    input       wire                intb            ,
    input       wire                intc            ,
    input       wire                intd            ,
    
    // MSI & MSI-X
    input       wire                msi_ctrl_int    ,
    input       wire    [31:0]      msi_ctrl_int_vec,
    output      reg     [31:0]      msi_ctrl_clear  ,

    // to tlp engine
    output      reg                 sys_rst_uart_ep ,
    output      reg                 sys_rst_uart_rc ,
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
    output      wire                error_address   
);

// ====================================================================
// Parameter/wire/reg
// ====================================================================  
    
// pipeline input signals
    reg                 ubus_wen_ff     ;
    reg     [31:0]      ubus_waddr_ff   ;
    reg     [31:0]      ubus_wdata_ff   ;
    reg                 ubus_ren_ff     ;
    reg     [31:0]      ubus_raddr_ff   ;

    reg                 op_start_ff     ;
    reg     [15:0]      ep_bdf_ff       ;
    reg                 mw_en_ff        ;
    reg                 mr_en_ff        ;
    reg                 iow_en_ff       ;
    reg                 ior_en_ff       ;
    reg                 cfg0w_en_ff     ;
    reg                 cfg0r_en_ff     ;

    reg     [63:0]      mw_addr_ff      ;
    reg     [12:0]      mw_len_ff       ;
    reg     [31:0]      mw_data_ff      ;
    reg                 mw_data_vld_ff  ;
    reg                 mw_mode_ff      ;
    reg                 mw_prbs_error_ff;

    reg     [63:0]      mr_addr_ff      ;
    reg     [12:0]      mr_len_ff       ;
    reg                 mr_data_vld_ff  ;
    reg                 mr_mode_ff      ;
    reg                 mr_prbs_clear_ff;

    reg     [31:0]      iow_addr_ff     ;
    reg     [31:0]      iow_data_ff     ;
    reg     [31:0]      ior_addr_ff     ;
    reg     [31:0]      ior_data_ff     ;
    reg     [31:0]      cfg0w_addr_ff   ;
    reg     [31:0]      cfg0w_data_ff   ;
    reg     [31:0]      cfg0r_addr_ff   ;
    reg     [31:0]      cfg0r_data_ff   ;
    reg                 mw_op_over_ff   ;
    reg                 mr_op_over_ff   ;
    reg                 iow_op_over_ff  ;
    reg                 ior_op_over_ff  ;
    reg                 cfg0w_op_over_ff;
    reg                 cfg0r_op_over_ff;
    reg                 mw_op_over_lvl   ;
    reg                 mr_op_over_lvl   ;
    reg                 iow_op_over_lvl  ;
    reg                 ior_op_over_lvl  ;
    reg                 cfg0w_op_over_lvl;
    reg                 cfg0r_op_over_lvl;
    reg                 error_ep_ff     ;
    reg                 error_length_ff ;
    reg                 error_address_ff;
// ====================================================================
// Main Code
// ====================================================================

// pipeline ubus
always@(posedge clk or posedge rst) begin 
    if(rst) begin 
        ubus_wen_ff    <= 'b0;
        ubus_waddr_ff  <= 'b0;
        ubus_wdata_ff  <= 'b0;
        ubus_ren_ff    <= 'b0;
        ubus_raddr_ff  <= 'b0;
    end else begin 
        ubus_wen_ff    <= ubus_wen    ;
        ubus_waddr_ff  <= ubus_waddr  ;
        ubus_wdata_ff  <= ubus_wdata  ;
        ubus_ren_ff    <= ubus_ren    ;
        ubus_raddr_ff  <= ubus_raddr  ;
    end
end

// pipeline input tlp signals
always@(posedge clk or posedge rst) begin 
    if(rst) begin 
        ior_data_ff     <= 'b0;
        cfg0r_data_ff   <= 'b0;
        mw_op_over_ff   <= 'b0;
        mr_op_over_ff   <= 'b0;
        iow_op_over_ff  <= 'b0;
        ior_op_over_ff  <= 'b0;
        cfg0w_op_over_ff<= 'b0;
        cfg0r_op_over_ff<= 'b0;
    end else begin 
        ior_data_ff     <= ior_data     ;
        cfg0r_data_ff   <= cfg0r_data   ;
        mw_op_over_ff   <= mw_op_over   ;
        mr_op_over_ff   <= mr_op_over   ;
        iow_op_over_ff  <= iow_op_over  ;
        ior_op_over_ff  <= ior_op_over  ;
        cfg0w_op_over_ff<= cfg0w_op_over;
        cfg0r_op_over_ff<= cfg0r_op_over;
    end
end

// over signals level detect
always@(posedge clk or posedge rst) begin 
    if(rst) begin 
        mw_op_over_lvl    <= 1'b0;
        mr_op_over_lvl    <= 1'b0;
        iow_op_over_lvl   <= 1'b0;
        ior_op_over_lvl   <= 1'b0;
        cfg0w_op_over_lvl <= 1'b0;
        cfg0r_op_over_lvl <= 1'b0;
    end else if(ubus_wen_ff) begin
        mw_op_over_lvl    <= 1'b0;
        mr_op_over_lvl    <= 1'b0;
        iow_op_over_lvl   <= 1'b0;
        ior_op_over_lvl   <= 1'b0;
        cfg0w_op_over_lvl <= 1'b0;
        cfg0r_op_over_lvl <= 1'b0;
    end else begin 
        mw_op_over_lvl    <= mw_op_over_ff    ? 1'b1 : mw_op_over_lvl    ;
        mr_op_over_lvl    <= mr_op_over_ff    ? 1'b1 : mr_op_over_lvl    ;
        iow_op_over_lvl   <= iow_op_over_ff   ? 1'b1 : iow_op_over_lvl   ;
        ior_op_over_lvl   <= ior_op_over_ff   ? 1'b1 : ior_op_over_lvl   ;
        cfg0w_op_over_lvl <= cfg0w_op_over_ff ? 1'b1 : cfg0w_op_over_lvl ;
        cfg0r_op_over_lvl <= cfg0r_op_over_ff ? 1'b1 : cfg0r_op_over_lvl ;
    end
end

// UBUS WR
//--------------------------------------------
// reg00, op strat signal
//--------------------------------------------
always@(posedge clk or posedge rst) begin 
    if(rst) begin 
        op_start_ff     <= 1'b0;
        ep_bdf_ff       <= 16'd0;
    end else if(ubus_wen_ff & (ubus_waddr_ff[7:0] == 8'h00)) begin 
        op_start_ff     <= ubus_wdata_ff[0];
        ep_bdf_ff       <= ubus_wdata_ff[31:16];
    end else begin 
        op_start_ff     <= 1'b0;
        ep_bdf_ff       <= ep_bdf_ff;       
    end
end

//--------------------------------------------
// reg01, mw en signal
//--------------------------------------------
always@(posedge clk or posedge rst) begin 
    if(rst) begin 
        mw_en_ff        <= 'b0;
    end else if(ubus_wen_ff & (ubus_waddr_ff[7:0] == 8'h01)) begin 
        mw_en_ff        <= ubus_wdata_ff[0];
    end else begin 
        mw_en_ff        <= mw_op_over_ff    ? 1'b0 : mw_en_ff   ;
    end
end

//--------------------------------------------
// reg02 & reg03, memwr addr signal
//--------------------------------------------
always@(posedge clk or posedge rst) begin 
    if(rst) begin 
        mw_addr_ff     <= 64'd0;
    end else begin 
        if(ubus_wen_ff & (ubus_waddr_ff[7:0] == 8'h02)) begin 
            mw_addr_ff[31:0] <= ubus_wdata_ff[31:0];
        end 
        if(ubus_wen_ff & (ubus_waddr_ff[7:0] == 8'h03)) begin 
            mw_addr_ff[63:32]<= ubus_wdata_ff[31:0];
        end 
    end
end

//--------------------------------------------
// reg04, memwr len signal
//--------------------------------------------
always@(posedge clk or posedge rst) begin 
    if(rst) begin 
        mw_len_ff     <= 13'd0;
    end else begin 
        if(ubus_wen_ff & (ubus_waddr_ff[7:0] == 8'h04)) begin 
            mw_len_ff <= ubus_wdata_ff[12:0];
        end 
    end
end

//--------------------------------------------
// reg05, memwr data&vaild signal
//--------------------------------------------
always@(posedge clk or posedge rst) begin 
    if(rst) begin 
        mw_data_ff      <= 32'd0;
        mw_data_vld_ff  <= 1'b0;
    end else begin 
        if(ubus_wen_ff & (ubus_waddr_ff[7:0] == 8'h05)) begin 
            mw_data_ff     <= ubus_wdata_ff[31:0];
            mw_data_vld_ff <= 1'b1;
        end else begin
            mw_data_ff      <= 32'd0;
            mw_data_vld_ff  <= 1'b0;
        end
    end
end

//--------------------------------------------
// reg06, memwr mode signal
// 0 : prbs mode 
// 1 : user data mode
//--------------------------------------------
always@(posedge clk or posedge rst) begin 
    if(rst) begin 
        mw_mode_ff <= 1'd0;
    end else begin 
        if(ubus_wen_ff & (ubus_waddr_ff[7:0] == 8'h06)) begin 
            mw_mode_ff <= ubus_wdata_ff[0];
        end
    end
end

//--------------------------------------------
// reg07, prbs mode error inject
//--------------------------------------------
always@(posedge clk or posedge rst) begin 
    if(rst) begin 
        mw_prbs_error_ff <= 1'b0;
    end else if(ubus_wen_ff & (ubus_waddr_ff[7:0] == 8'h07)) begin 
        mw_prbs_error_ff <= ubus_wdata_ff[0];
    end
end

//--------------------------------------------
// reg11, mr en signal
//--------------------------------------------
always@(posedge clk or posedge rst) begin 
    if(rst) begin 
        mr_en_ff        <= 'b0;
    end else if(ubus_wen_ff & (ubus_waddr_ff[7:0] == 8'h11)) begin 
        mr_en_ff        <= ubus_wdata_ff[0];
    end else begin 
        mr_en_ff        <= mr_op_over_ff    ? 1'b0 : mr_en_ff   ;
    end
end

//--------------------------------------------
// reg12 & reg13, memrd addr signal
//--------------------------------------------
always@(posedge clk or posedge rst) begin 
    if(rst) begin 
        mr_addr_ff     <= 64'd0;
    end else begin 
        if(ubus_wen_ff & (ubus_waddr_ff[7:0] == 8'h12)) begin 
            mr_addr_ff[31:0] <= ubus_wdata_ff[31:0];
        end 
        if(ubus_wen_ff & (ubus_waddr_ff[7:0] == 8'h13)) begin 
            mr_addr_ff[63:32]<= ubus_wdata_ff[31:0];
        end 
    end
end

//--------------------------------------------
// reg14, memrd len signal
//--------------------------------------------
always@(posedge clk or posedge rst) begin 
    if(rst) begin 
        mr_len_ff     <= 13'd0;
    end else begin 
        if(ubus_wen_ff & (ubus_waddr_ff[7:0] == 8'h14)) begin 
            mr_len_ff <= ubus_wdata_ff[12:0];
        end 
    end
end

//--------------------------------------------
// reg15, memrd data signal
//--------------------------------------------
always@(posedge clk or posedge rst) begin 
    if(rst) begin 
        mr_data_vld_ff <= 1'b0;
    end else begin 
        if(ubus_ren_ff & (ubus_raddr_ff[7:0] == 8'h15)) begin 
            mr_data_vld_ff <= 1'b1;
        end else begin 
            mr_data_vld_ff <= 1'b0;
        end
    end
end

//--------------------------------------------
// reg16, memrd mode signal
// 0 : prbs mode
// 1 : user mode
//--------------------------------------------
always@(posedge clk or posedge rst) begin 
    if(rst) begin 
        mr_mode_ff <= 1'b0;
    end else begin 
        if(ubus_wen_ff & (ubus_waddr_ff[7:0] == 8'h16)) begin 
            mr_mode_ff <= ubus_wdata_ff[0];
        end
    end
end

//--------------------------------------------
// reg17, clear prbs error
//--------------------------------------------
always@(posedge clk or posedge rst) begin 
    if(rst) begin 
        mr_prbs_clear_ff <= 1'b0;
    end else begin 
        if(ubus_wen_ff & (ubus_waddr_ff[7:0] == 8'h17)) begin 
            mr_prbs_clear_ff <= ubus_wdata_ff[0];
        end else begin
            mr_prbs_clear_ff <= 1'b0;
        end
    end
end

//--------------------------------------------
// reg21, iow en signal
//--------------------------------------------
always@(posedge clk or posedge rst) begin 
    if(rst) begin 
        iow_en_ff <= 'b0;
    end else if(ubus_wen_ff & (ubus_waddr_ff[7:0] == 8'h21)) begin 
        iow_en_ff <= ubus_wdata_ff[0];
    end else begin 
        iow_en_ff <= iow_op_over_ff   ? 1'b0 : iow_en_ff  ;
    end
end

//--------------------------------------------
// reg22, iow addr
// reg23, iow data
//--------------------------------------------
always@(posedge clk or posedge rst) begin 
    if(rst) begin 
        iow_addr_ff <= 'b0;
        iow_data_ff <= 'b0;
    end else begin 
        if(ubus_wen_ff & (ubus_waddr_ff[7:0] == 8'h22)) begin 
            iow_addr_ff[31:0] <= ubus_wdata_ff[31:0];
        end 
        if(ubus_wen_ff & (ubus_waddr_ff[7:0] == 8'h23)) begin 
            iow_data_ff[31:0] <= ubus_wdata_ff[31:0];
        end 
    end
end

//--------------------------------------------
// reg31, ior en signal
//--------------------------------------------
always@(posedge clk or posedge rst) begin 
    if(rst) begin 
        ior_en_ff <= 'b0;
    end else if(ubus_wen_ff & (ubus_waddr_ff[7:0] == 8'h31)) begin 
        ior_en_ff <= ubus_wdata_ff[0];
    end else begin 
        ior_en_ff <= ior_op_over_ff ? 1'b0 : ior_en_ff  ;
    end
end

//--------------------------------------------
// reg32, ior addr
//--------------------------------------------
always@(posedge clk or posedge rst) begin 
    if(rst) begin 
        ior_addr_ff <= 'b0;
    end else begin 
        if(ubus_wen_ff & (ubus_waddr_ff[7:0] == 8'h32)) begin 
            ior_addr_ff[31:0] <= ubus_wdata_ff[31:0];
        end 
    end
end

//--------------------------------------------
// reg33, ior data signal
//--------------------------------------------

//--------------------------------------------
// reg41, cfg0w en signal
//--------------------------------------------
always@(posedge clk or posedge rst) begin 
    if(rst) begin 
        cfg0w_en_ff     <= 'b0;
    end else if(ubus_wen_ff & (ubus_waddr_ff[7:0] == 8'h41)) begin 
        cfg0w_en_ff     <= ubus_wdata_ff[0];
    end else begin 
        cfg0w_en_ff     <= cfg0w_op_over_ff ? 1'b0 : cfg0w_en_ff;
    end
end

//--------------------------------------------
// reg42 : cfg0w addr
// reg43 : cfg0w data 
//--------------------------------------------
always@(posedge clk or posedge rst) begin 
    if(rst) begin 
        cfg0w_addr_ff     <= 'b0;
        cfg0w_data_ff     <= 'b0;
    end else begin 
        if(ubus_wen_ff & (ubus_waddr_ff[7:0] == 8'h42)) begin 
            cfg0w_addr_ff[31:0] <= ubus_wdata_ff[31:0];
        end 
        if(ubus_wen_ff & (ubus_waddr_ff[7:0] == 8'h43)) begin 
            cfg0w_data_ff[31:0] <= {ubus_wdata_ff[7:0],ubus_wdata_ff[15:8],ubus_wdata_ff[23:16],ubus_wdata_ff[31:24]};
        end 
    end
end

//--------------------------------------------
// reg51, cfg0r en signal
//--------------------------------------------
always@(posedge clk or posedge rst) begin 
    if(rst) begin 
        cfg0r_en_ff     <= 'b0;
    end else if(ubus_wen_ff & (ubus_waddr_ff[7:0] == 8'h51)) begin 
        cfg0r_en_ff     <= ubus_wdata_ff[0];
    end else begin 
        cfg0r_en_ff     <= cfg0r_op_over_ff ? 1'b0 : cfg0r_en_ff;
    end
end

//--------------------------------------------
// reg52, cfg0r addr signal
//--------------------------------------------
always@(posedge clk or posedge rst) begin 
    if(rst) begin 
        cfg0r_addr_ff     <= 'b0;
    end else begin 
        if(ubus_wen_ff & (ubus_waddr_ff[7:0] == 8'h52)) begin 
            cfg0r_addr_ff[31:0] <= ubus_wdata_ff[31:0];
        end 
    end
end

//--------------------------------------------
// reg60, legacy_int_clear
//--------------------------------------------
always@(posedge clk or posedge rst) begin 
    if(rst) begin 
        legacy_int_clear <= 'b0;
    end else if(ubus_wen_ff & (ubus_waddr_ff[7:0] == 8'h60)) begin 
        legacy_int_clear <= ubus_wdata_ff[0];
    end else begin
        legacy_int_clear <= 'b0;
    end
end

//--------------------------------------------
// reg70, msi&msi-x
//--------------------------------------------
always@(posedge clk or posedge rst) begin 
    if(rst) begin 
        msi_ctrl_clear <= 32'b0;
    end else if(ubus_wen_ff & (ubus_waddr_ff[7:0] == 8'h70)) begin 
        msi_ctrl_clear <= ubus_wdata_ff[31:0];
    end else begin
        msi_ctrl_clear <= 32'b0;
    end
end

//--------------------------------------------
// reg80, pcie ep system reset
//--------------------------------------------
always@(posedge clk or posedge rst) begin 
    if(rst) begin 
        sys_rst_uart_ep <= 1'b0;
    end else if(ubus_wen_ff & (ubus_waddr_ff[7:0] == 8'h80)) begin 
        sys_rst_uart_ep <= ubus_wdata_ff[0];
    end
end


//--------------------------------------------
// reg81, pcie rc system reset, except uart&ubus
//--------------------------------------------
always@(posedge clk or posedge rst) begin 
    if(rst) begin 
        sys_rst_uart_rc <= 1'b0;
    end else if(ubus_wen_ff & (ubus_waddr_ff[7:0] == 8'h81)) begin 
        sys_rst_uart_rc <= ubus_wdata_ff[0];
    end
end

//--------------------------------------------
// reg90, rc send tlp with ep
//--------------------------------------------
always@(posedge clk or posedge rst) begin 
    if(rst) begin 
        error_ep_ff <= 1'b0;
    end else if(ubus_wen_ff & (ubus_waddr_ff[7:0] == 8'h90)) begin 
        error_ep_ff <= ubus_wdata_ff[0];
    end else begin
        error_ep_ff <= 1'b0;
    end
end

//--------------------------------------------
// reg91, rc send tlp with error length
//--------------------------------------------
always@(posedge clk or posedge rst) begin 
    if(rst) begin 
        error_length_ff <= 1'b0;
    end else if(ubus_wen_ff & (ubus_waddr_ff[7:0] == 8'h91)) begin 
        error_length_ff <= ubus_wdata_ff[0];
    end else begin
        error_length_ff <= 1'b0;
    end
end

//--------------------------------------------
// reg92, rc send tlp with error address
//--------------------------------------------
always@(posedge clk or posedge rst) begin 
    if(rst) begin 
        error_address_ff <= 1'b0;
    end else if(ubus_wen_ff & (ubus_waddr_ff[7:0] == 8'h92)) begin 
        error_address_ff <= ubus_wdata_ff[0];
    end else begin
        error_address_ff <= 1'b0;
    end
end


// UBUS RD
always@(posedge clk or posedge rst) begin 
    if(rst) begin 
        ubus_bken       <= 'b0;
        ubus_rdata      <= 'b0;
    end else if(ubus_ren_ff) begin
        case(ubus_raddr_ff[7:0])
        8'h00:begin 
            ubus_bken   <= 1'b1;
            ubus_rdata  <= {26'd0,cfg0r_op_over_lvl,cfg0w_op_over_lvl,ior_op_over_lvl,iow_op_over_lvl,mr_op_over_lvl,mw_op_over_lvl };
        end

        8'h15:begin 
            ubus_bken   <= 1'b1;
            ubus_rdata  <= mr_data;         
        end

        8'h33:begin 
            ubus_bken   <= 1'b1;
            ubus_rdata  <= ior_data_ff[31:0];
        end
        8'h53:begin 
            ubus_bken   <= 1'b1;
            ubus_rdata  <= {cfg0r_data_ff[7:0],cfg0r_data_ff[15:8],cfg0r_data_ff[23:16],cfg0r_data_ff[31:24]};
        end

        8'h60: begin
            ubus_bken   <= 1'b1;
            ubus_rdata  <= {28'd0,intd,intc,intb,inta};
        end
        
        8'h70:begin
            ubus_bken   <= 1'b1;
            ubus_rdata  <= {21'd0,msi_ctrl_int};
        end

        8'h71:begin
            ubus_bken   <= 1'b1;
            ubus_rdata  <= msi_ctrl_int_vec;
        end

        default:;
        endcase
    end else begin 
        ubus_bken   <= 'b0;
    end
end

// ====================================================================
// TLP output
// ====================================================================
assign  op_start      = op_start_ff     ;
assign  ep_bdf        = ep_bdf_ff       ;          
assign  mw_en         = mw_en_ff        ;
assign  mr_en         = mr_en_ff        ;
assign  iow_en        = iow_en_ff       ;
assign  ior_en        = ior_en_ff       ;
assign  cfg0w_en      = cfg0w_en_ff     ;
assign  cfg0r_en      = cfg0r_en_ff     ;

assign  mw_addr       = mw_addr_ff      ;
assign  mw_len        = mw_len_ff       ;
assign  mw_data       = mw_data_ff      ;
assign  mw_data_vld   = mw_data_vld_ff  ;
assign  mw_mode       = mw_mode_ff      ;
assign  mw_prbs_error = mw_prbs_error_ff;

assign  mr_addr       = mr_addr_ff      ;
assign  mr_len        = mr_len_ff       ;
assign  mr_data_vld   = mr_data_vld_ff  ;          
assign  mr_mode       = mr_mode_ff      ;
assign  mr_prbs_clear = mr_prbs_clear_ff; 

assign  iow_addr      = iow_addr_ff     ;
assign  iow_data      = iow_data_ff     ;
assign  ior_addr      = ior_addr_ff     ;
assign  cfg0w_addr    = cfg0w_addr_ff   ;
assign  cfg0w_data    = cfg0w_data_ff   ;
assign  cfg0r_addr    = cfg0r_addr_ff   ;

assign  error_ep      = error_ep_ff     ;
assign  error_length  = error_length_ff ;
assign  error_address = error_address_ff;

endmodule
