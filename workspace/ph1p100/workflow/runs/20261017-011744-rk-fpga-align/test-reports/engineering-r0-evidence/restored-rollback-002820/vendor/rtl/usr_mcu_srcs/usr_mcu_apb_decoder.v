
//***************************************************************************
// mcu_apb_decoder.v
//***************************************************************************

`timescale 1ps / 1ps

module usr_mcu_apb_decoder (
    input               i_slv_apb_psel    , 
    input               i_slv_apb_penable , 
    input               i_slv_apb_pwrite  , 
    input      [31:0]   i_slv_apb_paddr   , 
    input      [31:0]   i_slv_apb_pwdata  , 
    output reg [31:0]   o_slv_apb_prdata  , 
    output reg          o_slv_apb_pready  , 
    output reg          o_slv_apb_pslverr , 

    output reg [ 7:0]   o_mst_apb_psel    , 
    output              o_mst_apb_penable , 
    output              o_mst_apb_pwrite  , 
    output     [31:0]   o_mst_apb_paddr   , 
    output     [31:0]   o_mst_apb_pwdata  , 
    input      [31:0]   i_mst_apb_prdata0 , 
    input      [31:0]   i_mst_apb_prdata1 , 
    input      [31:0]   i_mst_apb_prdata2 , 
    input      [31:0]   i_mst_apb_prdata3 , 
    input      [31:0]   i_mst_apb_prdata4 , 
    input      [31:0]   i_mst_apb_prdata5 , 
    input      [31:0]   i_mst_apb_prdata6 , 
    input      [31:0]   i_mst_apb_prdata7 , 
    input      [ 7:0]   i_mst_apb_pready  , 
    input      [ 7:0]   i_mst_apb_pslverr 
);

assign o_mst_apb_paddr   = i_slv_apb_paddr;
assign o_mst_apb_penable = i_slv_apb_penable;
assign o_mst_apb_pwrite  = i_slv_apb_pwrite;
assign o_mst_apb_pwdata  = i_slv_apb_pwdata;

always @ (*) begin
    o_mst_apb_psel[0] = ((i_slv_apb_paddr & 32'hf000_0000) == 32'h8000_0000) ? i_slv_apb_psel : 1'b0;
    o_mst_apb_psel[1] = ((i_slv_apb_paddr & 32'hf000_0000) == 32'h9000_0000) ? i_slv_apb_psel : 1'b0;    
    o_mst_apb_psel[2] = ((i_slv_apb_paddr & 32'hf000_0000) == 32'ha000_0000) ? i_slv_apb_psel : 1'b0;
    o_mst_apb_psel[3] = ((i_slv_apb_paddr & 32'hf000_0000) == 32'hb000_0000) ? i_slv_apb_psel : 1'b0;
    o_mst_apb_psel[4] = ((i_slv_apb_paddr & 32'hf000_0000) == 32'hc000_0000) ? i_slv_apb_psel : 1'b0;
    o_mst_apb_psel[5] = ((i_slv_apb_paddr & 32'hf000_0000) == 32'hd000_0000) ? i_slv_apb_psel : 1'b0;
    o_mst_apb_psel[6] = ((i_slv_apb_paddr & 32'hf000_0000) == 32'he000_0000) ? i_slv_apb_psel : 1'b0;
    o_mst_apb_psel[7] = ((i_slv_apb_paddr & 32'hf000_0000) == 32'hf000_0000) ? i_slv_apb_psel : 1'b0;
end

always @ (*) begin
    case (o_mst_apb_psel[7:0])
    8'b0000_0001 : o_slv_apb_prdata  = i_mst_apb_prdata0;
    8'b0000_0010 : o_slv_apb_prdata  = i_mst_apb_prdata1;
    8'b0000_0100 : o_slv_apb_prdata  = i_mst_apb_prdata2;
    8'b0000_1000 : o_slv_apb_prdata  = i_mst_apb_prdata3;
    8'b0001_0000 : o_slv_apb_prdata  = i_mst_apb_prdata4;
    8'b0010_0000 : o_slv_apb_prdata  = i_mst_apb_prdata5;
    8'b0100_0000 : o_slv_apb_prdata  = i_mst_apb_prdata6;
    8'b1000_0000 : o_slv_apb_prdata  = i_mst_apb_prdata7;
    default      : o_slv_apb_prdata  = 32'hdeadbeaf;
    endcase
end

always @ (*) begin
    case (o_mst_apb_psel[7:0])
    8'b0000_0001 : o_slv_apb_pready  = i_mst_apb_pready[0];
    8'b0000_0010 : o_slv_apb_pready  = i_mst_apb_pready[1];
    8'b0000_0100 : o_slv_apb_pready  = i_mst_apb_pready[2];
    8'b0000_1000 : o_slv_apb_pready  = i_mst_apb_pready[3];
    8'b0001_0000 : o_slv_apb_pready  = i_mst_apb_pready[4];
    8'b0010_0000 : o_slv_apb_pready  = i_mst_apb_pready[5];
    8'b0100_0000 : o_slv_apb_pready  = i_mst_apb_pready[6];
    8'b1000_0000 : o_slv_apb_pready  = i_mst_apb_pready[7];
    default      : o_slv_apb_pready  = 1'b1;
    endcase
end

always @ (*) begin
    case (o_mst_apb_psel[7:0])
    8'b0000_0001 : o_slv_apb_pslverr  = i_mst_apb_pslverr[0];
    8'b0000_0010 : o_slv_apb_pslverr  = i_mst_apb_pslverr[1];
    8'b0000_0100 : o_slv_apb_pslverr  = i_mst_apb_pslverr[2];
    8'b0000_1000 : o_slv_apb_pslverr  = i_mst_apb_pslverr[3];
    8'b0001_0000 : o_slv_apb_pslverr  = i_mst_apb_pslverr[4];
    8'b0010_0000 : o_slv_apb_pslverr  = i_mst_apb_pslverr[5];
    8'b0100_0000 : o_slv_apb_pslverr  = i_mst_apb_pslverr[6];
    8'b1000_0000 : o_slv_apb_pslverr  = i_mst_apb_pslverr[7];
    default      : o_slv_apb_pslverr  = 1'b0;
    endcase
end

endmodule
