`timescale 1ps/1ps

module usr_mcu_core_reg2mem (
    input          i_clk         ,
    input          i_rst         ,

    input          i_instr_vld   ,
    input          i_op_load     ,
    input          i_op_store    ,
    input          i_lw          ,
    input          i_lh          ,
    input          i_lb          ,
    input          i_lhu         ,
    input          i_lbu         ,
    input          i_sw          ,
    input          i_sh          ,
    input          i_sb          ,

    input  [31:0]  i_imm         ,
    input  [31:0]  i_rs1         ,
    input  [31:0]  i_rs2         ,

    output         o_mem_wen     ,
    output [31:0]  o_mem_waddr   ,
    output [31:0]  o_mem_wdata   ,
    output [ 3:0]  o_mem_wmask   ,
    input          i_mem_wresp   ,

    output         o_mem_ren     ,
    output [31:0]  o_mem_raddr   ,
    input  [31:0]  i_mem_rdata   ,
    input          i_mem_rvld    ,

    output         o_wr_done     ,
    output         o_rd_vld      ,
    output [31:0]  o_rd_data
);

///////////////////////////////////////////////////////////////////////////////////////////////////
// Local Parameters
///////////////////////////////////////////////////////////////////////////////////////////////////

///////////////////////////////////////////////////////////////////////////////////////////////////
// Internal Signals
///////////////////////////////////////////////////////////////////////////////////////////////////
reg           ren  ;
reg           rvld ;
reg   [31:0]  rdata;
reg   [31:0]  raddr;
reg           wen  ;
reg   [31:0]  wdata;
reg   [31:0]  waddr;
wire  [ 3:0]  wmask;

wire  [ 1:0]  rbyte;
wire  [ 1:0]  wbyte;

///////////////////////////////////////////////////////////////////////////////////////////////////
// Register to Memory
///////////////////////////////////////////////////////////////////////////////////////////////////
always @ (posedge i_clk or posedge i_rst)
begin
    if (i_rst == 1'b1) begin
        wen   <=  1'b0;
        waddr <= 32'h0;
        wdata <= 32'h0;
    end else if (i_instr_vld && i_sw) begin
        wen   <= 1'b1;
        waddr <= i_rs1 + i_imm;
        wdata <= i_rs2;
    end else if (i_instr_vld && i_sh) begin
        wen   <= 1'b1;
        waddr <= i_rs1 + i_imm;
        wdata <= {16'h0, i_rs2[15:0]};
    end else if (i_instr_vld && i_sb) begin
        wen   <= 1'b1;
        waddr <= i_rs1 + i_imm;
        wdata <= {24'h0, i_rs2[ 7:0]};
    end else begin
        wen   <= 1'b0;
    end
end

assign wbyte = waddr[1:0];
assign wmask = i_sw ?  4'b1111 :
               i_sh ? (4'b0011 << wbyte) :
               i_sb ? (4'b0001 << wbyte) : 4'b1111; 

///////////////////////////////////////////////////////////////////////////////////////////////////
// Memory to Register
///////////////////////////////////////////////////////////////////////////////////////////////////
always @ (posedge i_clk or posedge i_rst)
begin
    if (i_rst == 1'b1) begin
        ren   <=  1'b0;
        raddr <= 32'h0;
    end else if (i_instr_vld && i_op_load) begin
        ren   <= 1'b1;
        raddr <= i_rs1 + i_imm;
    end else begin
        ren   <= 1'b0;
    end
end

assign rbyte = raddr[1:0];

always @ (posedge i_clk or posedge i_rst)
begin
    if (i_rst == 1'b1) begin
        rvld  <= 1'b0;
    end else begin
        rvld  <= i_mem_rvld ? 1'b1 : 1'b0;
    end
end

always @ (posedge i_clk or posedge i_rst)
begin
    if (i_rst == 1'b1) begin
        rdata <= 32'h0;
    end else if (i_lw  == 1'b1) begin
        rdata <= i_mem_rvld ? i_mem_rdata : rdata;
    end else if (i_lh  == 1'b1) begin
        rdata <= i_mem_rvld  ? {{16{i_mem_rdata[rbyte*8+15]}}, i_mem_rdata[rbyte*8 +: 16]} : rdata;
    end else if (i_lb  == 1'b1) begin
        rdata <= i_mem_rvld  ? {{24{i_mem_rdata[rbyte*8+ 7]}}, i_mem_rdata[rbyte*8 +:  8]} : rdata;
    end else if (i_lhu == 1'b1) begin
        rdata <= i_mem_rvld  ? {16'h0, i_mem_rdata[rbyte*8 +: 16]} : rdata;
    end else if (i_lbu == 1'b1) begin
        rdata <= i_mem_rvld  ? {24'h0, i_mem_rdata[rbyte*8 +:  8]} : rdata;
    end
end

///////////////////////////////////////////////////////////////////////////////////////////////////
// OUTPUT
///////////////////////////////////////////////////////////////////////////////////////////////////
assign o_wr_done = i_mem_wresp;
assign o_rd_vld  = rvld ;
assign o_rd_data = rdata;

assign o_mem_wen     = wen; 
assign o_mem_waddr   ={waddr[31:2], 2'b00};
assign o_mem_wdata   =(wdata << (wbyte*8));
assign o_mem_wmask   = wmask;

assign o_mem_ren     = ren; 
assign o_mem_raddr   ={raddr[31:2], 2'b00};

///////////////////////////////////////////////////////////////////////////////////////////////////
// END
///////////////////////////////////////////////////////////////////////////////////////////////////
endmodule
