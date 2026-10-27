
///////////////////////////////////////////////////////////////////////////////////////////////////
// module : ph1p_ddrphy_init
///////////////////////////////////////////////////////////////////////////////////////////////////
`timescale 1ps/1ps

module ph1p_ddrphy_init (
    input               clk        ,
    input               rst_n      ,

    output reg          cfg_done   ,

    // DCP
    output              dcp_psel   ,
    output      [ 5:0]  dcp_paddr  ,
    output      [ 8:0]  dcp_pdata  ,
    output              dcp_gate   ,

    // APB
    output              apb_psel   ,
    output              apb_penable,
    output              apb_pwrite ,
    output      [15:0]  apb_paddr  ,
    output      [31:0]  apb_pwdata ,
    input       [31:0]  apb_prdata ,
    input               apb_pready
);

///////////////////////////////////////////////////////////////////////////////////////////////////
//    Parameter Definition
///////////////////////////////////////////////////////////////////////////////////////////////////
localparam ROM_LEN = 255;

///////////////////////////////////////////////////////////////////////////////////////////////////
//    Signals Definition
///////////////////////////////////////////////////////////////////////////////////////////////////
wire [51:0] rom_w52 [0:ROM_LEN-1]; // synthesis ram_style=dram
reg  [ 7:0] rom_addr;
wire [51:0] rom_data;

reg         psel_r         ;
reg         penable_r      ;
wire        prdy_int       ;

wire        transfer_vld   ;
reg  [ 3:0] transfer_cnt   ;
wire        transfer_en    ;
reg         transfer_done  ;

wire [ 3:0] cfg_type;
wire        done;

wire        dcp_pready = (transfer_cnt >= 4'hC);

`ifdef PH1P_DDRPHY_SIM
wire        cfg_sim    = 1'b1;
`else
wire        cfg_sim    = 1'b0;
`endif
///////////////////////////////////////////////////////////////////////////////////////////////////
//    Function Definition : ROM
///////////////////////////////////////////////////////////////////////////////////////////////////
//`include "ph1p_ddrphy_init.vh"
assign rom_w52[8'h00] = 52'h0_0007_11222222;
assign rom_w52[8'h01] = 52'h0_0008_00002111;
assign rom_w52[8'h02] = 52'h0_0009_22222222;
assign rom_w52[8'h03] = 52'h0_000A_00002222;
assign rom_w52[8'h04] = 52'h0_000B_00000000;
assign rom_w52[8'h05] = 52'h0_000C_00000000;
assign rom_w52[8'h06] = 52'h0_000F_088020f0;
assign rom_w52[8'h07] = 52'h0_0012_00001e00;
assign rom_w52[8'h08] = 52'h0_0107_11121122;
assign rom_w52[8'h09] = 52'h0_0108_00002111;
assign rom_w52[8'h0a] = 52'h0_0109_22222222;
assign rom_w52[8'h0b] = 52'h0_010A_00002222;
assign rom_w52[8'h0c] = 52'h0_010B_00000001;
assign rom_w52[8'h0d] = 52'h0_010C_00000000;
assign rom_w52[8'h0e] = 52'h0_010F_088020f0;
assign rom_w52[8'h0f] = 52'h0_0112_00001e00;
assign rom_w52[8'h10] = 52'h0_0207_11111121;
assign rom_w52[8'h11] = 52'h0_0208_00002111;
assign rom_w52[8'h12] = 52'h0_0209_22222222;
assign rom_w52[8'h13] = 52'h0_020A_00002222;
assign rom_w52[8'h14] = 52'h0_020B_00000000;
assign rom_w52[8'h15] = 52'h0_020C_00000000;
assign rom_w52[8'h16] = 52'h0_020F_088020f0;
assign rom_w52[8'h17] = 52'h0_0212_00001e00;
assign rom_w52[8'h18] = 52'h0_1007_00000020;
assign rom_w52[8'h19] = 52'h0_1008_00002000;
assign rom_w52[8'h1a] = 52'h0_1009_11111121;
assign rom_w52[8'h1b] = 52'h0_100A_00002111;
assign rom_w52[8'h1c] = 52'h0_100B_00000020;
assign rom_w52[8'h1d] = 52'h0_100C_00002010;
assign rom_w52[8'h1e] = 52'h0_100F_188020f0;
assign rom_w52[8'h1f] = 52'h0_1012_00001e00;
assign rom_w52[8'h20] = 52'h0_1107_00000000;
assign rom_w52[8'h21] = 52'h0_1108_00002002;
assign rom_w52[8'h22] = 52'h0_1109_11111111;
assign rom_w52[8'h23] = 52'h0_110A_00002112;
assign rom_w52[8'h24] = 52'h0_110B_00000000;
assign rom_w52[8'h25] = 52'h0_110C_00002012;
assign rom_w52[8'h26] = 52'h0_110F_188020f0;
assign rom_w52[8'h27] = 52'h0_1112_00001e00;
assign rom_w52[8'h28] = 52'h0_1207_00000020;
assign rom_w52[8'h29] = 52'h0_1208_00002000;
assign rom_w52[8'h2a] = 52'h0_1209_11111121;
assign rom_w52[8'h2b] = 52'h0_120A_00002111;
assign rom_w52[8'h2c] = 52'h0_120B_00000020;
assign rom_w52[8'h2d] = 52'h0_120C_00002010;
assign rom_w52[8'h2e] = 52'h0_120F_188020f0;
assign rom_w52[8'h2f] = 52'h0_1212_00001e00;
assign rom_w52[8'h30] = 52'h0_1307_00000000;
assign rom_w52[8'h31] = 52'h0_1308_00002200;
assign rom_w52[8'h32] = 52'h0_1309_11111111;
assign rom_w52[8'h33] = 52'h0_130A_00002211;
assign rom_w52[8'h34] = 52'h0_130B_00000000;
assign rom_w52[8'h35] = 52'h0_130C_00002210;
assign rom_w52[8'h36] = 52'h0_130F_188020f0;
assign rom_w52[8'h37] = 52'h0_1312_00001e00;
assign rom_w52[8'h38] = 52'h1_0002_00000055;
assign rom_w52[8'h39] = 52'h1_0003_00000010;
assign rom_w52[8'h3a] = 52'hf_ffff_ffffffff;


///////////////////////////////////////////////////////////////////////////////////////////////////
//    Function Definition : Rom Addr
///////////////////////////////////////////////////////////////////////////////////////////////////
always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0)
        rom_addr <= 8'h0;
    else if (transfer_cnt == 4'hf)
        rom_addr <= done ? rom_addr : rom_addr + 1'd1;
end

///////////////////////////////////////////////////////////////////////////////////////////////////
//    Function Definition : Rom Data
///////////////////////////////////////////////////////////////////////////////////////////////////
assign rom_data = rom_w52[rom_addr];

///////////////////////////////////////////////////////////////////////////////////////////////////
//    Function Definition : Start Gen
///////////////////////////////////////////////////////////////////////////////////////////////////
reg   [3 : 0] por_cnt   ;
wire          start     ;

always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0)
        por_cnt <= 4'h0;
    else
        por_cnt <= (&por_cnt == 1'b1) ? por_cnt : por_cnt + 1'b1;
end

assign start = (por_cnt[3:0] == 4'hE) ? 1'b1 : 1'b0;

///////////////////////////////////////////////////////////////////////////////////////////////////
//    Function Definition : Flow Control 
///////////////////////////////////////////////////////////////////////////////////////////////////
always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0)
        transfer_cnt <= 4'h0;
    else if (start || (transfer_cnt != 0) || ((transfer_cnt == 0) && transfer_done))
        transfer_cnt <= transfer_cnt + 1'b1;
end

assign transfer_en = (transfer_cnt == 4'h8);

always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0)
        transfer_done <= 1'b0;
    else if (transfer_en)
        transfer_done <= 1'b0;
    else if (transfer_vld)
        transfer_done <= 1'b1;
end

///////////////////////////////////////////////////////////////////////////////////////////////////
//    Function Definition : PSEL
///////////////////////////////////////////////////////////////////////////////////////////////////
assign prdy_int     = (cfg_type == 4'h0) ? apb_pready :
                      (cfg_type == 4'h1) ? dcp_pready : 1'b0;

assign transfer_vld = (psel_r && prdy_int && penable_r);

always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0)
        psel_r <= 1'b0;
    else if ((done == 1'b0) && transfer_en)
        psel_r <= 1'b1;
    else if (transfer_vld)
        psel_r <= 1'b0;
end

///////////////////////////////////////////////////////////////////////////////////////////////////
//    Function Definition : Penable
///////////////////////////////////////////////////////////////////////////////////////////////////
always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0)
        penable_r <= 1'b0;
    else if ((psel_r == 1'b1) && (penable_r == 1'b0))
        penable_r <= 1'b1;
    else if (transfer_vld)
        penable_r <= 1'b0; // transfer_vld
end

///////////////////////////////////////////////////////////////////////////////////////////////////
//    Function Definition : Done
///////////////////////////////////////////////////////////////////////////////////////////////////
assign done = (cfg_type == 4'hf); 

always @ ( posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0) begin
        cfg_done <= 1'b0;
    end else if (done && (transfer_cnt == 4'hf)) begin
        cfg_done <= 1'b1;
    end
end

///////////////////////////////////////////////////////////////////////////////////////////////////
//    Function Definition : IN/OUT Ctl
///////////////////////////////////////////////////////////////////////////////////////////////////
assign cfg_type    = rom_data[51:48];

assign apb_psel    = (cfg_type == 4'h0) ? psel_r : 1'b0;
assign apb_pwrite  = 1'b1;
assign apb_penable = penable_r;
assign apb_paddr   = rom_data[47:32];
assign apb_pwdata  = rom_data[31: 0];

assign dcp_psel   = (cfg_type == 4'h1) ? psel_r : 1'b0;
assign dcp_gate   = dcp_psel;
assign dcp_paddr  = rom_data[37:32];
assign dcp_pdata  = rom_data[ 8: 0];

endmodule
