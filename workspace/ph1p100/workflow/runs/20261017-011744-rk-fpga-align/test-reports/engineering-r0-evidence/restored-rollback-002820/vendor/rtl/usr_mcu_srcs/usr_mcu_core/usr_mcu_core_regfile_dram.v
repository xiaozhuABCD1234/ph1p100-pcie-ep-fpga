`timescale 1ps/1ps

module usr_mcu_core_regfile (
    input         i_clk      ,
    input         i_rst      ,

    input  [ 4:0] i_rs1      ,
    input  [ 4:0] i_rs2      ,
    input  [ 4:0] i_rd       ,

    input         i_rd_vld   ,
    input  [31:0] i_rd_data  ,
    input         i_csr_rvld ,
    input  [31:0] i_csr_rdata,
    input         i_mem_rvld ,
    input  [31:0] i_mem_rdata,

    output [31:0] o_rs1_data ,
    output [31:0] o_rs2_data ,

    output        o_rst_done

);

///////////////////////////////////////////////////////////////////////////////////////////////////
// Local Parameters
///////////////////////////////////////////////////////////////////////////////////////////////////


///////////////////////////////////////////////////////////////////////////////////////////////////
// Internal Signals
///////////////////////////////////////////////////////////////////////////////////////////////////
reg  [31:0] regfile[31:0]; // synthesis ram_style=dram

reg  [ 4:0] reg_addr;
reg         rst_done; // synthesis keep

//reg  [31:0] x00_zero = 32'h0000_0000;
//reg  [31:0] x01_ra    ;
//reg  [31:0] x02_sp    ;
//reg  [31:0] x03_gp    ;
//reg  [31:0] x04_tp    ;
//reg  [31:0] x05_t0    ;
//reg  [31:0] x06_t1    ;
//reg  [31:0] x07_t2    ;
//reg  [31:0] x08_s0_fp ;
//reg  [31:0] x09_s1    ;
//reg  [31:0] x10_a0    ;
//reg  [31:0] x11_a1    ;
//reg  [31:0] x12_a2    ;
//reg  [31:0] x13_a3    ;
//reg  [31:0] x14_a4    ;
//reg  [31:0] x15_a5    ;
//reg  [31:0] x16_a6    ;
//reg  [31:0] x17_a7    ;
//reg  [31:0] x18_s2    ;
//reg  [31:0] x19_s3    ;
//reg  [31:0] x20_s4    ;
//reg  [31:0] x21_s5    ;
//reg  [31:0] x22_s6    ;
//reg  [31:0] x23_s7    ;
//reg  [31:0] x24_s8    ;
//reg  [31:0] x25_s9    ;
//reg  [31:0] x26_s10   ;
//reg  [31:0] x27_s11   ;
//reg  [31:0] x28_t3    ;
//reg  [31:0] x29_t4    ;
//reg  [31:0] x30_t5    ;
//reg  [31:0] x31_t6    ;

///////////////////////////////////////////////////////////////////////////////////////////////////
// RegFile Operation
///////////////////////////////////////////////////////////////////////////////////////////////////
assign o_rs1_data = regfile[i_rs1[4:0]];
assign o_rs2_data = regfile[i_rs2[4:0]];

always @ (posedge i_clk or posedge i_rst)
begin
    if (i_rst == 1'b1)
        reg_addr <= 5'h0;
    else if (reg_addr == 5'h1f)
        reg_addr <= 5'h1f;
    else
        reg_addr <= reg_addr + 1'b1;
end

always @ (posedge i_clk or posedge i_rst)
begin
    if (i_rst == 1'b1)
        rst_done <= 1'b0;
    else if (reg_addr == 5'h1f)
        rst_done <= 1'b1;
    else
        rst_done <= 1'b0; 
end

always @ (posedge i_clk)
begin
    if (rst_done == 1'b0) begin
        regfile[reg_addr] <= 32'h0;
//  end else if (i_rd[4:0] == 5'h0) begin
//      regfile[0] <= 32'h0;
    end else begin
        regfile[i_rd[4:0]] <= (i_rd[4:0] == 5'h0) ? 32'h0       : 
                               i_rd_vld           ? i_rd_data   : 
                               i_csr_rvld         ? i_csr_rdata :
                               i_mem_rvld         ? i_mem_rdata : regfile[i_rd[4:0]];
    end
end

assign o_rst_done = rst_done;

///////////////////////////////////////////////////////////////////////////////////////////////////
// END
///////////////////////////////////////////////////////////////////////////////////////////////////
endmodule
