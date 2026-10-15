//////////////////////////////////////////////////////////////
//  Copyright(c) 2011-2022 Anlogic, Inc.
//  All Right Reserved.
//////////////////////////////////////////////////////////////
//  Company       : Anlogic
//  Filename      : ph1p_pcie_rst_sync.v
//  Author        : Gehong - hong.ge@anlogic.com
//  Last Modified : 2024-07-10 18:11:04
//  Create        : 2023-05-05 12:18:26
//  Description   : 
//                  pcie reset sync logic
///////////////////////////////////////////////////////////////

`timescale 1ns/1ps

module ph1p_pcie_rst_sync#(
    parameter   LTSSM_VAULE = 5'h10 
)(
    input   wire                clk         ,
    input   wire                rst         ,
    input   wire    [4:0]       tl_ltssm    ,
    input   wire                pl_link_up  ,
    output  wire                rst_sync    
);

// ====================================================================
// Parameter/wire/reg
// ====================================================================
    reg         pl_link_up_dly;
    reg [4:0]   tl_ltssm_dly;
    reg [10:0]  rst_dly;
    reg         rst_d1;
    reg         rst_d2;
// ====================================================================
// Main Code
// ====================================================================

always@(posedge clk or posedge rst)
begin
    if(rst) begin 
        pl_link_up_dly <= 1'b0;
        tl_ltssm_dly   <= 5'd0;
    end else begin
        pl_link_up_dly <= pl_link_up;
        tl_ltssm_dly   <= tl_ltssm;
    end
end

// delay time for link negotiation is turely finish, in some situation,
// the pl_link and tl_ltssm meet the conditicons at the same time in 
// only few cycle, bucause the link speed change.
always@(posedge clk or posedge rst)
begin
    if(rst)
       rst_dly <= 11'd0;
    else if( pl_link_up_dly == 1'b1 && tl_ltssm_dly == LTSSM_VAULE  )
       rst_dly <= (rst_dly[10] == 1'b0) ? rst_dly + 1'b1 : rst_dly;
    else
       rst_dly <= 11'd0;
end

// async rst , sync release 
always@(posedge clk or posedge rst)
begin 
    if(rst) begin
        rst_d1 <= 1'b1;
        rst_d2 <= 1'b1;
    end else begin 
        rst_d1 <= (~rst_dly[10]);
        rst_d2 <= rst_d1;
    end
end

assign  rst_sync = rst_d2;

/*synthesis translate_off*/
initial begin 
    forever begin
        @(posedge rst_dly[10])
            $display("%0t logic info : ph1p pcie has link up", $realtime);
    end
    forever begin
        @(posedge rst)
            $display("%0t logic info : ph1p pcie has rst", $realtime);
    end
end
/*synthesis translate_on*/

endmodule
