
//***************************************************************************
// mcu_apb_gpio.v
//***************************************************************************

`timescale 1ps/1ps

module usr_mcu_apb_gpio (
    input               i_clk         ,
    input               i_rst         ,

    input      [ 7:0]   i_apb_paddr   , 
    input               i_apb_psel    , 
    input               i_apb_penable , 
    input               i_apb_pwrite  , 
    input      [31:0]   i_apb_pwdata  , 
    output     [31:0]   o_apb_prdata  , 
    output              o_apb_pready  , 
    output              o_apb_pslverr , 

    output     [31:0]   o_reg_w_00    ,
    output     [31:0]   o_reg_w_04    ,
    output     [31:0]   o_reg_w_08    ,
    output     [31:0]   o_reg_w_0c    ,
    output     [31:0]   o_reg_w_10    ,
    output     [31:0]   o_reg_w_14    ,
    output     [31:0]   o_reg_w_18    ,
    output     [31:0]   o_reg_w_1c    ,
    input      [31:0]   i_reg_r_20    ,
    input      [31:0]   i_reg_r_24    ,
    input      [31:0]   i_reg_r_28    ,
    input      [31:0]   i_reg_r_2c    ,
    input      [31:0]   i_reg_r_30    ,
    input      [31:0]   i_reg_r_34    ,
    input      [31:0]   i_reg_r_38    ,
    input      [31:0]   i_reg_r_3c
);


// apb misc
wire apb_pclk   =  i_clk;
wire apb_prst_n = ~i_rst;

// apb port
reg           apb_pready  ; // synthesis keep
wire          apb_psel    ; // synthesis keep
wire          apb_penable ; // synthesis keep
wire  [ 7:0]  apb_paddr   ; // synthesis keep
wire          apb_pwrite  ; // synthesis keep
wire  [31:0]  apb_pwdata  ; // synthesis keep
reg   [31:0]  apb_prdata  ; // synthesis keep
wire          apb_wr_flag ; // synthesis keep
wire          apb_rd_flag ; // synthesis keep

reg   [31:0]  wdata_00    ; // synthesis keep
reg   [31:0]  wdata_04    ; // synthesis keep
reg   [31:0]  wdata_08    ; // synthesis keep
reg   [31:0]  wdata_0c    ; // synthesis keep
reg   [31:0]  wdata_10    ; // synthesis keep
reg   [31:0]  wdata_14    ; // synthesis keep
reg   [31:0]  wdata_18    ; // synthesis keep
reg   [31:0]  wdata_1c    ; // synthesis keep
reg   [31:0]  rdata_20    ; // synthesis keep
reg   [31:0]  rdata_24    ; // synthesis keep
reg   [31:0]  rdata_28    ; // synthesis keep
reg   [31:0]  rdata_2c    ; // synthesis keep
reg   [31:0]  rdata_30    ; // synthesis keep
reg   [31:0]  rdata_34    ; // synthesis keep
reg   [31:0]  rdata_38    ; // synthesis keep
reg   [31:0]  rdata_3c    ; // synthesis keep

assign apb_wr_flag = apb_psel & apb_penable & (apb_pwrite == 1'b1) & apb_pready;
assign apb_rd_flag = apb_psel & apb_penable & (apb_pwrite == 1'b0);

// apb timing control
always @ (posedge apb_pclk or negedge apb_prst_n)
begin
    if (apb_prst_n == 1'b0)
        apb_pready <= 1'b1;
    else if (apb_psel & (apb_penable == 1'b0))
        apb_pready <= 1'b0;
    else if (apb_psel & apb_penable & (apb_pwrite == 1'b1))
        apb_pready <= 1'b1;
    else if (apb_psel & apb_penable & (apb_pwrite == 1'b0))
        apb_pready <= apb_rd_flag ;
    else
        apb_pready <= 1'b1;
end


always @ (posedge apb_pclk or negedge apb_prst_n)
begin
    if (apb_prst_n == 1'b0) begin
        wdata_00 <= 32'h0;
        wdata_04 <= 32'h0;
        wdata_08 <= 32'h0;
        wdata_0c <= 32'h0;
        wdata_10 <= 32'h0;
        wdata_14 <= 32'h0;
        wdata_18 <= 32'h0;
        wdata_1c <= 32'h0;
    end else if (apb_wr_flag) begin
        case (apb_paddr[7:0])
            8'h00  : wdata_00 <= apb_pwdata;
            8'h04  : wdata_04 <= apb_pwdata;
            8'h08  : wdata_08 <= apb_pwdata;
            8'h0c  : wdata_0c <= apb_pwdata;
            8'h10  : wdata_10 <= apb_pwdata;
            8'h14  : wdata_14 <= apb_pwdata;
            8'h18  : wdata_18 <= apb_pwdata;
            8'h1c  : wdata_1c <= apb_pwdata;
            default: begin
            end
        endcase
    end
end

assign o_reg_w_00 = wdata_00;
assign o_reg_w_04 = wdata_04;
assign o_reg_w_08 = wdata_08;
assign o_reg_w_0c = wdata_0c;
assign o_reg_w_10 = wdata_10;
assign o_reg_w_14 = wdata_14;
assign o_reg_w_18 = wdata_18;
assign o_reg_w_1c = wdata_1c;

always @ (posedge apb_pclk)
begin
    rdata_20 <= i_reg_r_20;
    rdata_24 <= i_reg_r_24;
    rdata_28 <= i_reg_r_28;
    rdata_2c <= i_reg_r_2c;
    rdata_30 <= i_reg_r_30;
    rdata_34 <= i_reg_r_34;
    rdata_38 <= i_reg_r_38;
    rdata_3c <= i_reg_r_3c;
end

always @ (posedge apb_pclk or negedge apb_prst_n)
begin
    if (apb_prst_n == 1'b0) begin
        apb_prdata <= 32'h0;
    end else if (apb_rd_flag) begin
        case (apb_paddr[7:0])
            8'h00  : apb_prdata <= wdata_00;
            8'h04  : apb_prdata <= wdata_04;
            8'h08  : apb_prdata <= wdata_08;
            8'h0c  : apb_prdata <= wdata_0c;
            8'h10  : apb_prdata <= wdata_10;
            8'h14  : apb_prdata <= wdata_14;
            8'h18  : apb_prdata <= wdata_18;
            8'h1c  : apb_prdata <= wdata_1c;
            8'h20  : apb_prdata <= rdata_20;
            8'h24  : apb_prdata <= rdata_24;
            8'h28  : apb_prdata <= rdata_28;
            8'h2c  : apb_prdata <= rdata_2c;
            8'h30  : apb_prdata <= rdata_30;
            8'h34  : apb_prdata <= rdata_34;
            8'h38  : apb_prdata <= rdata_38;
            8'h3c  : apb_prdata <= rdata_3c;
            default: apb_prdata <= 32'hdeadbeef;
        endcase
    end else begin
        apb_prdata <= 32'h0;
    end
end

// ports connection
assign apb_paddr    = i_apb_paddr  ;
assign apb_psel     = i_apb_psel   ;
assign apb_penable  = i_apb_penable;
assign apb_pwrite   = i_apb_pwrite ;
assign apb_pwdata   = i_apb_pwdata ;

assign o_apb_pready  = apb_pready ;
assign o_apb_prdata  = apb_prdata ;
assign o_apb_pslverr = 1'b0;

endmodule
