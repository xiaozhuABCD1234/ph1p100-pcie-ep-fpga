`timescale 1ps/1ps

module ph1p_ddrmc_mtest #(
    parameter  DX_NUM     = 2  ,
    parameter  BG_WIDTH   = 0  ,
    parameter  BA_WIDTH   = 3  ,
    parameter  ROW_WIDTH  = 15 ,
    parameter  COL_WIDTH  = 10 ,
    parameter  MC_ADDR_WIDTH = BG_WIDTH + BA_WIDTH + ROW_WIDTH + COL_WIDTH,
    parameter  MC_DATA_WIDTH = DX_NUM*64,
    parameter  MC_MASK_WIDTH = DX_NUM*8
)(
    input                          clk                   ,
    input                          rst_n                 ,

// APB
    input                          apb_pclk              ,
    input                          apb_prst_n            ,
    input                          apb_psel              ,
    input                          apb_penable           ,
    input                          apb_pwrite            ,
    input       [          7 : 0]  apb_paddr             ,
    input       [         31 : 0]  apb_pwdata            ,
    output reg  [         31 : 0]  apb_prdata            ,
    output reg                     apb_pready            ,

// ctrl
    input                          ddrphy_rdy            ,

// status
    output reg                     mtest_done            ,
    output reg                     mtest_run             ,
    output                         mtest_his_err         ,
    output    [  DX_NUM   -1 : 0]  mtest_his_err_byte    ,

// pseudo-axi
    input                          paxi_awready       ,
    output    [MC_ADDR_WIDTH-1:0]  paxi_awaddr        ,
    output                         paxi_awvalid       ,
    input                          paxi_wready        ,
    output                         paxi_wvalid        ,
    output    [MC_DATA_WIDTH-1:0]  paxi_wdata         ,
    output    [MC_MASK_WIDTH-1:0]  paxi_wstrb         ,
    output                         paxi_wlast         ,
    input                          paxi_arready       ,
    output                         paxi_arvalid       ,
    output    [MC_ADDR_WIDTH-1:0]  paxi_araddr        ,
    output                         paxi_rready        ,
    input                          paxi_rvalid        ,
    input     [MC_DATA_WIDTH-1:0]  paxi_rdata         ,
    input                          paxi_rlast
);

//*****************************************************************************
// Local Parameters
//*****************************************************************************
localparam VERSION = 32'h20240408;

//localparam [3 : 0] CMD_MRS = 4'b1000;
//localparam [3 : 0] CMD_REF = 4'b1001;
//localparam [3 : 0] CMD_PRE = 4'b1010;
//localparam [3 : 0] CMD_ACT = 4'b0011;
localparam [3 : 0] CMD_WR  = 4'b1100;
localparam [3 : 0] CMD_RD  = 4'b1101;

localparam DQ_WIDTH = DX_NUM*8;
localparam DM_WIDTH = DX_NUM;

//*****************************************************************************
// Internal Signals
//*****************************************************************************
reg             start   ;
reg   [ 3 : 0]  pat_sel ;
reg             clear   ;
reg   [ 3 : 0]  bsel    ;
reg   [31 : 0]  seed0   ;
reg   [31 : 0]  seed1   ;

wire                          cmd_rdy ;
wire  [               3 : 0]  cmd_type;
wire                          cmd_en  ;
wire  [ MC_ADDR_WIDTH-1 : 0]  cmd_addr;
wire                          cmd_done;

wire                          wr_en;


//*****************************************************************************
//    Function : APB
//*****************************************************************************
// apb register definition
// 0x00 - rw : CR0
// 0x04 - rw : CR1
// 0x08 - ro : SR0
// 0x0C - ro : SR1
// 0x10 - rw : ByteSel
// 0x14 - ro : RDataCnt           : PerByte
// 0x18 - ro : ErrorCnt           : PerByte
// 0x1C - ro : VERSION 
// 0x20 - ro : RDATA      [31: 0] : PerByte
// 0x24 - ro : RDATA      [63:31] : PerByte
// 0x28 - ro : WDATA      [31: 0]
// 0x2C - ro : WDATA      [63:31]
// 0x30 - rw : seed0
// 0x34 - rw : seed1
// 0x40 - ro : DATA_1x_RD  [31: 0] : PerByte
// 0x44 - ro : DATA_1x_RD  [63:32] : PerByte
// 0x48 - ro : DATA_1x_EXP [31: 0] : PerByte
// 0x4C - ro : DATA_1x_EXP [63:32] : PerByte
// 0x50 - ro : DATA_1x_XOR [31: 0] : PerByte
// 0x54 - ro : DATA_1x_XOR [63:32] : PerByte
// 0x60 - ro : DATA_2x_RD  [31: 0] : PerByte
// 0x64 - ro : DATA_2x_RD  [63:32] : PerByte
// 0x68 - ro : DATA_2x_EXP [31: 0] : PerByte
// 0x6C - ro : DATA_2x_EXP [63:32] : PerByte
// 0x70 - ro : DATA_2x_XOR [31: 0] : PerByte
// 0x74 - ro : DATA_2x_XOR [63:32] : PerByte
// 0x80 - ro : DATA_3x_RD  [31: 0] : PerByte
// 0x84 - ro : DATA_3x_RD  [63:32] : PerByte
// 0x88 - ro : DATA_3x_EXP [31: 0] : PerByte
// 0x8C - ro : DATA_3x_EXP [63:32] : PerByte
// 0x90 - ro : DATA_3x_XOR [31: 0] : PerByte
// 0x94 - ro : DATA_3x_XOR [63:32] : PerByte
// 0xA0 - ro : DATA_4x_RD  [31: 0] : PerByte
// 0xA4 - ro : DATA_4x_RD  [63:32] : PerByte
// 0xA8 - ro : DATA_4x_EXP [31: 0] : PerByte
// 0xAC - ro : DATA_4x_EXP [63:32] : PerByte
// 0xB0 - ro : DATA_4x_XOR [31: 0] : PerByte
// 0xB4 - ro : DATA_4x_XOR [63:32] : PerByte
// 0xC0 - ro : ACC_DATA_XOR[31: 0] : PerByte
// 0xC4 - ro : ACC_DATA_XOR[63:32] : PerByte

wire   apb_wr_flag ;
wire   apb_rd_flag ;

reg  [31:0] reg00;
reg  [31:0] reg04;
wire [31:0] reg08;
wire [31:0] reg0c;
reg  [31:0] reg10;
reg  [31:0] reg14;
reg  [31:0] reg18;
wire [31:0] reg1c = VERSION;
reg  [31:0] reg20;
reg  [31:0] reg24;
reg  [31:0] reg28;
reg  [31:0] reg2c;
reg  [31:0] reg30;
reg  [31:0] reg34;
reg  [31:0] reg38;
reg  [31:0] reg3c;
reg  [31:0] reg40;
reg  [31:0] reg44;
reg  [31:0] reg48;
reg  [31:0] reg4c;
reg  [31:0] reg50;
reg  [31:0] reg54;
reg  [31:0] reg58;
reg  [31:0] reg5c;
reg  [31:0] reg60;
reg  [31:0] reg64;
reg  [31:0] reg68;
reg  [31:0] reg6c;
reg  [31:0] reg70;
reg  [31:0] reg74;
reg  [31:0] reg78;
reg  [31:0] reg7c;
reg  [31:0] reg80;
reg  [31:0] reg84;
reg  [31:0] reg88;
reg  [31:0] reg8c;
reg  [31:0] reg90;
reg  [31:0] reg94;
reg  [31:0] reg98;
reg  [31:0] reg9c;
reg  [31:0] rega0;
reg  [31:0] rega4;
reg  [31:0] rega8;
reg  [31:0] regac;
reg  [31:0] regb0;
reg  [31:0] regb4;
reg  [31:0] regb8;
reg  [31:0] regbc;
reg  [31:0] regc0;
reg  [31:0] regc4;
reg  [31:0] regc8;
reg  [31:0] regcc;

assign apb_wr_flag = apb_psel & apb_penable & (apb_pwrite==1'b1) & apb_pready;
assign apb_rd_flag = apb_psel & apb_penable & (apb_pwrite==1'b0);

// apb pready control
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

// apb write
always @ (posedge apb_pclk or negedge apb_prst_n) begin
    if (apb_prst_n == 1'b0) begin
        reg00 <= 32'h0;
        reg04 <= 32'h0;
        reg10 <= 32'h0;
        reg30 <= 32'h0;
        reg34 <= 32'h0;
    end else if (apb_wr_flag) begin
        case (apb_paddr[7:0])
            8'h00 : reg00 <= apb_pwdata;
            8'h04 : reg04 <= apb_pwdata;
            8'h10 : reg10 <= apb_pwdata;
            8'h30 : reg30 <= apb_pwdata;
            8'h34 : reg34 <= apb_pwdata;
            default: begin
            end
        endcase
    end else begin
        reg00 <= reg00;
        reg04 <= reg04;
        reg10 <= reg10;
        reg30 <= reg30;
        reg34 <= reg34;
    end
end

// apb_read
always @ (posedge apb_pclk or negedge apb_prst_n)
begin
    if (apb_prst_n == 1'b0) begin
        apb_prdata <= 32'h0;
    end else if (apb_rd_flag) begin
        case (apb_paddr[7:0])
            8'h00  : apb_prdata <= reg00;
            8'h04  : apb_prdata <= reg04;
            8'h08  : apb_prdata <= reg08;
            8'h0c  : apb_prdata <= reg0c;
            8'h10  : apb_prdata <= reg10;
            8'h14  : apb_prdata <= reg14;
            8'h18  : apb_prdata <= reg18;
            8'h1c  : apb_prdata <= reg1c;
            8'h20  : apb_prdata <= reg20;
            8'h24  : apb_prdata <= reg24;
            8'h28  : apb_prdata <= reg28;
            8'h2c  : apb_prdata <= reg2c;
            8'h30  : apb_prdata <= reg30;
            8'h34  : apb_prdata <= reg34;
            8'h38  : apb_prdata <= reg38;
            8'h3c  : apb_prdata <= reg3c;
            8'h40  : apb_prdata <= reg40;
            8'h44  : apb_prdata <= reg44;
            8'h48  : apb_prdata <= reg48;
            8'h4c  : apb_prdata <= reg4c;
            8'h50  : apb_prdata <= reg50;
            8'h54  : apb_prdata <= reg54;
            8'h58  : apb_prdata <= reg58;
            8'h5c  : apb_prdata <= reg5c;
            8'h60  : apb_prdata <= reg60;
            8'h64  : apb_prdata <= reg64;
            8'h68  : apb_prdata <= reg68;
            8'h6c  : apb_prdata <= reg6c;
            8'h70  : apb_prdata <= reg70;
            8'h74  : apb_prdata <= reg74;
            8'h78  : apb_prdata <= reg78;
            8'h7c  : apb_prdata <= reg7c;
            8'h80  : apb_prdata <= reg80;
            8'h84  : apb_prdata <= reg84;
            8'h88  : apb_prdata <= reg88;
            8'h8c  : apb_prdata <= reg8c;
            8'h90  : apb_prdata <= reg90;
            8'h94  : apb_prdata <= reg94;
            8'h98  : apb_prdata <= reg98;
            8'h9c  : apb_prdata <= reg9c;
            8'ha0  : apb_prdata <= rega0;
            8'ha4  : apb_prdata <= rega4;
            8'ha8  : apb_prdata <= rega8;
            8'hac  : apb_prdata <= regac;
            8'hb0  : apb_prdata <= regb0;
            8'hb4  : apb_prdata <= regb4;
            8'hb8  : apb_prdata <= regb8;
            8'hbc  : apb_prdata <= regbc;
            8'hc0  : apb_prdata <= regc0;
            8'hc4  : apb_prdata <= regc4;
            8'hc8  : apb_prdata <= regc8;
            8'hcc  : apb_prdata <= regcc;
            default: apb_prdata <= 32'hdeadbeef;
        endcase
    end else begin
        apb_prdata <= 32'h0;
    end
end


/*
`ifndef PH1P_DDRPHY_SIM
    wire [31:0] CR0  = reg00;
    wire [31:0] CR1  = reg04;
    wire [31:0] BSEL = reg10;
    `else 
    wire [31:0] CR0  = 32'h0000_0010;
    wire [31:0] CR1  = 32'h0000_0000;
    wire [31:0] BSEL = 32'h0000_0000;
`endif 
*/


wire [31:0] CR0  = 32'h0000_0010;
wire [31:0] CR1  = 32'h0000_0000;
wire [31:0] BSEL = 32'h0000_0000;
 
    
// CR0
wire cr0_rst   = CR0[0];
wire cr0_start = CR0[4] & ddrphy_rdy;
wire cr0_clear = CR0[12];
//CR1
wire [3:0] cr1_pat_sel = CR1[31:28];
// BSEL
wire [3:0] cr_bsel     = BSEL[3:0];


//*****************************************************************************
//    Function : ctrl signal sync to local clk
//*****************************************************************************
always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0) begin
        start    <= 1'b0;
        pat_sel  <= 4'h0;
        seed0    <= 32'h0;
        seed1    <= 32'h0;
        clear    <= 1'b0;
        bsel     <= 4'h0;
    end else begin
        start    <= cr0_start   ;
        pat_sel  <= cr1_pat_sel ;
        seed0    <= reg30;
        seed1    <= reg34;
        clear    <= cr0_clear;
        bsel     <= cr_bsel;
    end
end

// Reset Generate
wire       rst_int = (cr0_rst == 1'b1) | (rst_n == 1'b0);
reg  [1:0] sw_rst_r; // synthesis keep
wire       sw_rst_n; // synthesis keep

always @ (posedge clk or posedge rst_int)
begin
    if (rst_int == 1'b1)
        sw_rst_r <= 2'b00;
    else
        sw_rst_r <= {sw_rst_r[0], 1'b1};
end

assign sw_rst_n = sw_rst_r[1];


///////////////////////////////////////////////////////////////////////////////////////////////////
//  PAXI CMD Generator
///////////////////////////////////////////////////////////////////////////////////////////////////
paxi_stg_cmd_gen #(
    .BG_WIDTH       ( BG_WIDTH  ),
    .BA_WIDTH       ( BA_WIDTH  ),
    .ROW_WIDTH      ( ROW_WIDTH ),
    .COL_WIDTH      ( COL_WIDTH )
) u_cmd_gen (
    .clk        ( clk         ),
    .rst        (~sw_rst_n    ),
    .ddrphy_rdy ( ddrphy_rdy  ),
    .start      ( start       ),
    .cmd_rdy    ( cmd_rdy     ),
    .cmd_type   ( cmd_type    ),
    .cmd_en     ( cmd_en      ),
    .cmd_addr   ( cmd_addr    ),
    .cmd_done   ( cmd_done    ),
    .rd_vld     ( paxi_rvalid ),
    .wr_rdy     ( paxi_wready ),
    .wr_en      ( wr_en       )
);


//****************************************************************************
//  DHI DATA FORMAT Convert
//****************************************************************************
wire  [MC_DATA_WIDTH-1:0]  rdata_byte;

genvar n, b, p;

for (n = 0; n <= DX_NUM-1; n = n+1) begin : rdata_reorder_nIdx
    for (p = 0; p <= 7; p = p+1) begin : rdata_reorder_pIdx
        assign rdata_byte[n*64+p*8 +: 8] = paxi_rdata[p*DQ_WIDTH+n*8 +: 8];
    end
end


//****************************************************************************
//  Write Data Gen
//****************************************************************************
wire  [MC_DATA_WIDTH-1:0]  wdata_phase;
wire  [MC_MASK_WIDTH-1:0]  wmask_phase;

wire          wdata_en    ;
reg           wdata_en_r  ;
wire  [63:0]  wdata_byte;
reg   [63:0]  wdata_byte_r;
reg   [63:0]  wdata_byte_r1;

assign wdata_en = cmd_en & wr_en & paxi_wready;

data_gen u_data_gen (
    .clk      ( clk          ),
    .rst_n    ( sw_rst_n     ),
    .pat_sel  ( pat_sel      ),

    .seed0    ( seed0        ),
    .seed1    ( seed1        ),

    .data_en  ( wdata_en     ),
    .data     ( wdata_byte   )
);

for (n = 0; n <= DX_NUM-1; n = n+1) begin: wdata_extend_nIdx
    for (p = 0; p <= 7; p = p+1) begin : wdata_extend_pIdx
        assign wdata_phase[p*DQ_WIDTH+n*8 +: 8] = wdata_byte[p*8 +: 8];
        assign wmask_phase[p*DX_NUM+n] = 1'b0;
    end
end

///////////////////////////////////////////////////////////////////////////////////////////////////
//  PAXI OUTPUT
///////////////////////////////////////////////////////////////////////////////////////////////////
assign cmd_rdy = paxi_awready & paxi_arready;

assign paxi_awaddr  = (cmd_type == CMD_WR) ? cmd_addr : {MC_ADDR_WIDTH{1'b0}};
assign paxi_awvalid = (cmd_type == CMD_WR) ? wr_en    : 1'b0;

assign paxi_wvalid  = wr_en & cmd_en;
assign paxi_wdata   = wdata_phase;
assign paxi_wstrb   = wmask_phase;
assign paxi_wlast   = 1'b1;

assign paxi_arvalid = (cmd_type == CMD_RD) ? cmd_en   : 1'b0;
assign paxi_araddr  = (cmd_type == CMD_RD) ? cmd_addr : {MC_ADDR_WIDTH{1'b0}};

assign paxi_rready = 1'b1;


///////////////////////////////////////////////////////////////////////////////////////////////////
//  wdata pipeline for debug
always @ (posedge clk or negedge sw_rst_n)
begin
    if (sw_rst_n == 1'b0) begin
        wdata_en_r   <=  1'b0;
        wdata_byte_r <= 32'h0;
    end else begin
        wdata_en_r   <= wdata_en;
        wdata_byte_r <= wdata_byte;
    end
end

always @ (posedge clk or negedge sw_rst_n)
begin
    if (sw_rst_n == 1'b0)
        wdata_byte_r1 <= 32'h0;
    else if (wdata_en_r == 1'b1)
        wdata_byte_r1 <= wdata_byte_r;
    else
        wdata_byte_r1 <= wdata_byte_r1;
end

//****************************************************************************
//  Data Check
//****************************************************************************

                        

wire  [DX_NUM-1:0]  err_byte;

wire  [9*32-1:0]  cnt_rd      ;
wire  [9*32-1:0]  cnt_err     ;
wire  [9*64-1:0]  data_rel    ;
wire  [9*64-1:0]  data_1x_exp ;
wire  [9*64-1:0]  data_1x_rd  ;
wire  [9*64-1:0]  data_1x_xor ;
wire  [9*64-1:0]  data_2x_exp ;
wire  [9*64-1:0]  data_2x_rd  ;
wire  [9*64-1:0]  data_2x_xor ;
wire  [9*64-1:0]  data_3x_exp ;
wire  [9*64-1:0]  data_3x_rd  ;
wire  [9*64-1:0]  data_3x_xor ;
wire  [9*64-1:0]  data_4x_exp ;
wire  [9*64-1:0]  data_4x_rd  ;
wire  [9*64-1:0]  data_4x_xor ;
wire  [9*64-1:0]  data_acc_xor;

generate
for (n = 0; n <= DX_NUM-1; n= n+1) begin : dataCheck
    if (n <= DX_NUM-1) begin : used
        data_check u_data_check (
            .clk          ( clk                       ),
            .rst_n        ( sw_rst_n                  ),
            .pat_sel      ( pat_sel                   ),
            .seed0        ( seed0                     ),
            .seed1        ( seed1                     ),
            .data_en      ( paxi_rvalid               ),
            .data         ( rdata_byte   [n*64 +: 64] ),
            .err          ( err_byte     [n]          ),
    
            // debug
            .clear        ( clear                     ),
            .cnt_rd       ( cnt_rd       [n*32 +: 32] ),
            .cnt_err      ( cnt_err      [n*32 +: 32] ),
            .data_rel     ( data_rel     [n*64 +: 64] ),
            .data_1x_exp  ( data_1x_exp  [n*64 +: 64] ),
            .data_1x_rd   ( data_1x_rd   [n*64 +: 64] ),
            .data_1x_xor  ( data_1x_xor  [n*64 +: 64] ),
            .data_2x_exp  ( data_2x_exp  [n*64 +: 64] ),
            .data_2x_rd   ( data_2x_rd   [n*64 +: 64] ),
            .data_2x_xor  ( data_2x_xor  [n*64 +: 64] ),
            .data_3x_exp  ( data_3x_exp  [n*64 +: 64] ),
            .data_3x_rd   ( data_3x_rd   [n*64 +: 64] ),
            .data_3x_xor  ( data_3x_xor  [n*64 +: 64] ),
            .data_4x_exp  ( data_4x_exp  [n*64 +: 64] ),
            .data_4x_rd   ( data_4x_rd   [n*64 +: 64] ),
            .data_4x_xor  ( data_4x_xor  [n*64 +: 64] ),
            .data_acc_xor ( data_acc_xor [n*64 +: 64] )
        );
    end else begin : not_used
            assign cnt_rd       [n*32 +: 32] = 32'h0;
            assign cnt_err      [n*32 +: 32] = 32'h0;
            assign data_rel     [n*64 +: 64] = 64'h0;
            assign data_1x_exp  [n*64 +: 64] = 64'h0;
            assign data_1x_rd   [n*64 +: 64] = 64'h0;
            assign data_1x_xor  [n*64 +: 64] = 64'h0;
            assign data_2x_exp  [n*64 +: 64] = 64'h0;
            assign data_2x_rd   [n*64 +: 64] = 64'h0;
            assign data_2x_xor  [n*64 +: 64] = 64'h0;
            assign data_3x_exp  [n*64 +: 64] = 64'h0;
            assign data_3x_rd   [n*64 +: 64] = 64'h0;
            assign data_3x_xor  [n*64 +: 64] = 64'h0;
            assign data_3x_exp  [n*64 +: 64] = 64'h0;
            assign data_3x_rd   [n*64 +: 64] = 64'h0;
            assign data_3x_xor  [n*64 +: 64] = 64'h0;
            assign data_acc_xor [n*64 +: 64] = 64'h0;
    end
end
endgenerate

//****************************************************************************
//  Status
//****************************************************************************
reg  [DX_NUM-1 : 0]  his_err_byte    ; // synthesis keep

for (n = 0; n <= DX_NUM-1; n= n+1) begin : nIdx_Err
    always @ (posedge clk or negedge sw_rst_n)
    begin
        if (sw_rst_n == 1'b0)
            his_err_byte[n] <= 1'b0;
        else if (err_byte[n] == 1'b1)
            his_err_byte[n] <= 1'b1; 
        else
            his_err_byte[n] <= his_err_byte[n]; 
    end
end

assign  mtest_his_err      = |his_err_byte;
assign  mtest_his_err_byte =  his_err_byte;

always @ (posedge clk or negedge sw_rst_n)
begin
    if (sw_rst_n == 1'b0)
        mtest_done <= 1'b0;
    else if (cmd_done)
        mtest_done <= 1'b1; 
    else
        mtest_done <= mtest_done; 
end

always @ (posedge clk or negedge sw_rst_n)
begin
    if (sw_rst_n == 1'b0)
        mtest_run <= 1'b0;
    else 
        mtest_run <= paxi_rvalid || (paxi_wvalid && paxi_wready);
end

reg [3:0]mtest_state;
always @ (posedge clk or negedge sw_rst_n)
begin
    if (sw_rst_n == 1'b0)
        mtest_state <= 4'd0;
    else 
        mtest_state <= cmd_type;
end

//****************************************************************************
//  Status Checking
//****************************************************************************
assign reg08[ 8: 0] = {{(9-DX_NUM){1'b0}}, mtest_his_err_byte};
assign reg08[11: 9] = mtest_his_err;
assign reg08[15:12] = mtest_run;
assign reg08[19:16] = mtest_done;
assign reg08[23:20] = 4'h0;
assign reg08[27:24] = 4'h0;
assign reg08[31:28] = mtest_state;

assign reg0c[ 3: 0] = 4'd0;
assign reg0c[ 7: 4] = 4'h0;
assign reg0c[ 8   ] = 1'b0;
assign reg0c[11: 9] = 3'h0;
assign reg0c[12   ] = rst_int;
assign reg0c[15:13] = 3'h0;
assign reg0c[16   ] = sw_rst_n;
assign reg0c[31:17] = 15'h0;

always @ (posedge clk or negedge sw_rst_n)
begin
    if (sw_rst_n == 1'b0) begin
        reg14 <= 32'h0;
        reg18 <= 32'h0;
        reg20 <= 32'h0;
        reg24 <= 32'h0;
        reg28 <= 32'h0;
        reg2c <= 32'h0;
        reg40 <= 32'h0;
        reg44 <= 32'h0;
        reg48 <= 32'h0;
        reg4c <= 32'h0;
        reg50 <= 32'h0;
        reg54 <= 32'h0;
        reg58 <= 32'h0;
        reg5c <= 32'h0;
        reg60 <= 32'h0;
        reg64 <= 32'h0;
        reg68 <= 32'h0;
        reg6c <= 32'h0;
        reg70 <= 32'h0;
        reg74 <= 32'h0;
        reg78 <= 32'h0;
        reg7c <= 32'h0;
        reg80 <= 32'h0;
        reg84 <= 32'h0;
        reg88 <= 32'h0;
        reg8c <= 32'h0;
        reg90 <= 32'h0;
        reg94 <= 32'h0;
        reg98 <= 32'h0;
        reg9c <= 32'h0;
        rega0 <= 32'h0;
        rega4 <= 32'h0;
        rega8 <= 32'h0;
        regac <= 32'h0;
        regb0 <= 32'h0;
        regb4 <= 32'h0;
        regb8 <= 32'h0;
        regbc <= 32'h0;
        regc0 <= 32'h0;
        regc4 <= 32'h0;
        regc8 <= 32'h0;
        regcc <= 32'h0;
    end else begin
        reg14 <= cnt_rd       >> (32*bsel);
        reg18 <= cnt_err      >> (32*bsel);
        reg20 <= data_rel     >> (64*bsel);
        reg24 <= data_rel     >> (64*bsel + 32);
        reg28 <= wdata_byte_r1[31: 0];
        reg2c <= wdata_byte_r1[63:32];
        reg40 <= data_1x_rd   >> (64*bsel);
        reg44 <= data_1x_rd   >> (64*bsel + 32);
        reg48 <= data_1x_exp  >> (64*bsel);
        reg4c <= data_1x_exp  >> (64*bsel + 32);
        reg50 <= data_1x_xor  >> (64*bsel);
        reg54 <= data_1x_xor  >> (64*bsel + 32);
        reg60 <= data_2x_rd   >> (64*bsel);
        reg64 <= data_2x_rd   >> (64*bsel + 32);
        reg68 <= data_2x_exp  >> (64*bsel);
        reg6c <= data_2x_exp  >> (64*bsel + 32);
        reg70 <= data_2x_xor  >> (64*bsel);
        reg74 <= data_2x_xor  >> (64*bsel + 32);
        reg80 <= data_3x_rd   >> (64*bsel);
        reg84 <= data_3x_rd   >> (64*bsel + 32);
        reg88 <= data_3x_exp  >> (64*bsel);
        reg8c <= data_3x_exp  >> (64*bsel + 32);
        reg90 <= data_3x_xor  >> (64*bsel);
        reg94 <= data_3x_xor  >> (64*bsel + 32);
        rega0 <= data_4x_rd   >> (64*bsel);
        rega4 <= data_4x_rd   >> (64*bsel + 32);
        rega8 <= data_4x_exp  >> (64*bsel);
        regac <= data_4x_exp  >> (64*bsel + 32);
        regb0 <= data_4x_xor  >> (64*bsel);
        regb4 <= data_4x_xor  >> (64*bsel + 32);
        regc0 <= data_acc_xor >> (64*bsel);
        regc4 <= data_acc_xor >> (64*bsel + 32);
    end
end



//*******************************************************************************
// SIMULATION ONLY
//*******************************************************************************
//synthesis translate_off
`ifdef PH1P_DDRPHY_SIM

integer dfi_mtest_result ;

initial begin : Logging
    fork
    begin : write_read_done
        wait (cmd_done);
        $display("Writes and Reads Test Completed");
        #10_000_000;

        wait (cnt_rd[31:0] >= 32);

        if (mtest_his_err == 1'b0) begin
            dfi_mtest_result = $fopen("PASSED", "a");
            $display("\n\n");
            $display("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!");
            $display("!!!!      TEST PASSED       !!!!");
            $display("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!");
            $display("\n\n");
            $display("Test Completed Successfully");
            $fdisplay(dfi_mtest_result, "TEST PASSED");
            $fdisplay(dfi_mtest_result, "Test Completed Successfully");
            $fclose(dfi_mtest_result);
        end else begin
            dfi_mtest_result = $fopen("FAILED", "a");
            $display("\n\n");
            $display("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!");
            $display("!!!!      TEST FAILED       !!!!");
            $display("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!");
            $display("\n\n");
            $display ("TEST FAILED: DATA ERROR");
            $fdisplay(dfi_mtest_result, "TEST FAILED: DATA ERROR");
            $fclose(dfi_mtest_result);
        end

        disable write_read_not_done;
        $finish;
    end

    begin : write_read_not_done
        wait (ddrphy_rdy);
        #100us;
        if (cnt_rd[31:0] === 0) begin
            $display("ERROR: Timeout occured during Write/Read transaction");
        end
        disable write_read_done;
        $finish;
    end
    join
end
`endif
//synthesis translate_on
//*******************************************************************************

endmodule
