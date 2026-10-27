//////////////////////////////////////////////////////////////
//  Copyright(c) 2011-2022 Anlogic, Inc.
//  All Right Reserved.
//////////////////////////////////////////////////////////////
//  Company       : Anlogic
//  Filename      : ubus2apb.v
//  Author        : Dexin - dexin.guo@anlogic.com
//  Last Modified : 2023-03-29 11:09:43
//  Create        : 2022-06-23 16:00:11
//  Description   : 
//                  conver ubus protocol to pcie ip apb4 bus
///////////////////////////////////////////////////////////////


`timescale 1ns/1ps

module ubus2pcie_apb
(
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
    
    // APB
    output      wire                tl_cfg_prst     ,
    output      wire                tl_cfg_penable  ,
    output      wire                tl_cfg_psel     ,
    output      wire                tl_cfg_pwrite   ,
    output      wire    [31:0]      tl_cfg_paddr    ,
    output      wire    [3:0]       tl_cfg_pstrb    ,
    output      wire    [31:0]      tl_cfg_pwdata   ,
    input       wire                tl_cfg_pready   ,
    input       wire    [31:0]      tl_cfg_prdata   ,
    input       wire                tl_cfg_pslverr  
);


// ====================================================================
// Parameter/wire/reg
// ====================================================================
    wire            cfg_prst     ;
    reg             cfg_penable  ;
    reg             cfg_psel     ;
    reg             cfg_pwrite   ;
    reg    [31:0]   cfg_paddr    ;
    wire   [3:0]    cfg_pstrb    ;
    reg    [31:0]   cfg_pwdata   ;

// ====================================================================
// Main Code
// ====================================================================

// user --> apb
assign   cfg_prst = 1'b0;

always@(posedge clk or posedge rst) begin 
    if(rst) begin 
        cfg_pwrite <= 1'b0;
    end else if(tl_cfg_pready & cfg_psel & cfg_penable & cfg_pwrite) begin
        cfg_pwrite <= 1'b0;
    end else if(ubus_wen) begin 
        cfg_pwrite <= 1'b1;
    end
end

always@(posedge clk or posedge rst) begin 
    if(rst) begin 
        cfg_psel <= 1'b0;
    end else if(tl_cfg_pready & cfg_psel & cfg_penable) begin
        cfg_psel <= 1'b0;
    end else if( ubus_wen | ubus_ren ) begin 
        cfg_psel <= 1'b1;
    end
end

always@(posedge clk or posedge rst) begin 
    if(rst) begin 
        cfg_penable <= 1'b0;
    end else if(tl_cfg_pready & cfg_psel & cfg_penable ) begin 
        cfg_penable <= 1'b0;
    end else if( cfg_psel  ) begin 
        cfg_penable <= 1'b1;
    end
end

always@(posedge clk or posedge rst) begin 
    if(rst) begin 
        cfg_paddr  <= 1'b0;
    end else if( ubus_wen ) begin
        cfg_paddr  <= ubus_waddr;
    end else if( ubus_ren ) begin 
        cfg_paddr  <= ubus_raddr;
    end
end

always@(posedge clk or posedge rst) begin 
    if(rst) begin 
        cfg_pwdata <= 1'b0;
    end else if( ubus_wen ) begin
        cfg_pwdata <= ubus_wdata;
    end
end

assign  cfg_pstrb    = 4'hf;

// apb --> user
always@(posedge clk or posedge rst) begin 
    if(rst) begin 
        ubus_bken <= 1'b0;
        ubus_rdata<= 32'b0;
    end else if( tl_cfg_pready & cfg_psel & cfg_penable & (~cfg_pwrite) ) begin 
        ubus_bken <= 1'b1;
        ubus_rdata<= tl_cfg_prdata;
    end else begin 
        ubus_bken <= 1'b0;
        ubus_rdata<= ubus_rdata;
    end
end

// ====================================================================
// APB output
// ====================================================================

assign  tl_cfg_prst     = cfg_prst     ;
assign  tl_cfg_penable  = cfg_penable  ;
assign  tl_cfg_psel     = cfg_psel     ;
assign  tl_cfg_pwrite   = cfg_pwrite   ;
assign  tl_cfg_paddr    = cfg_paddr    ;
assign  tl_cfg_pstrb    = cfg_pstrb    ;
assign  tl_cfg_pwdata   = cfg_pwdata   ;

endmodule
