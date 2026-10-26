`timescale 1ps/1ps

module usr_mcu_core_alu (
    input          i_clk      ,
    input          i_rst      ,

    input          i_instr_vld,

    input   [31:0] i_pc       ,
    output  [31:0] o_pc       ,
    output         o_pc_vld   ,

    input   [31:0] i_rs1      ,
    input   [31:0] i_rs2      ,

    output         o_rd_vld   ,
    output  [31:0] o_rd_data  ,

    input   [ 4:0] i_shamt    ,
    input   [31:0] i_imm      ,

    input          i_lui      ,
    input          i_auipc    ,
    input          i_jal      ,
    input          i_jalr     ,
    input          i_beq      ,
    input          i_bne      ,
    input          i_blt      ,
    input          i_bge      ,
    input          i_bltu     ,
    input          i_bgeu     ,
    input          i_lb       ,
    input          i_lh       ,
    input          i_lw       ,
    input          i_lbu      ,
    input          i_lhu      ,
    input          i_sb       ,
    input          i_sh       ,
    input          i_sw       ,
    input          i_addi     ,
    input          i_slti     ,
    input          i_sltiu    ,
    input          i_xori     ,
    input          i_ori      ,
    input          i_andi     ,
    input          i_slli     ,
    input          i_srli     ,
    input          i_srai     ,
    input          i_add      ,
    input          i_sub      ,
    input          i_sll      ,
    input          i_slt      ,
    input          i_sltu     ,
    input          i_xor      ,
    input          i_srl      ,
    input          i_sra      ,
    input          i_or       ,
    input          i_and      ,
    input          i_fence    ,
    input          i_ecall    ,
    input          i_ebreak
);

////////////////////////////////////////////////////////////////////////////////////////////////////
// Local Parameter Definition
////////////////////////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////////////////////////
// Function Definition
////////////////////////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////////////////////////
// Internal Signal Definition
////////////////////////////////////////////////////////////////////////////////////////////////////
reg         rd_vld;
reg         pc_vld;
reg  [31:0] rd;
reg  [31:0] pc;

////////////////////////////////////////////////////////////////////////////////////////////////////
// Internal Signal Definition
////////////////////////////////////////////////////////////////////////////////////////////////////
always @ (posedge i_clk or posedge i_rst)
begin
    if (i_rst == 1'b1) begin
        rd_vld <= 1'b0;
        rd     <= 32'h0;
    end else if (i_instr_vld == 1'b0) begin
        rd_vld <= 1'b0;
    end else if (i_lui == 1'b1) begin
        rd_vld <= 1'b1;
        rd     <= {i_imm[31:12], 12'h0};
    end else if (i_auipc == 1'b1) begin
        rd_vld <= 1'b1;
        rd     <= {i_imm[31:12], 12'h0} + i_pc;
    end else if (i_jal == 1'b1) begin
        rd_vld <= 1'b1;
        rd     <= i_pc + 32'h4;
    end else if (i_jalr == 1'b1) begin
        rd_vld <= 1'b1;
        rd     <= i_pc + 32'h4;
//  end else if (i_beq    == 1'b1) begin
//  end else if (i_bne    == 1'b1) begin
//  end else if (i_blt    == 1'b1) begin
//  end else if (i_bge    == 1'b1) begin
//  end else if (i_bltu   == 1'b1) begin
//  end else if (i_bgeu   == 1'b1) begin
//  end else if (i_lb     == 1'b1) begin
//  end else if (i_lh     == 1'b1) begin
//  end else if (i_lw     == 1'b1) begin
//  end else if (i_lbu    == 1'b1) begin
//  end else if (i_lhu    == 1'b1) begin
//  end else if (i_sb     == 1'b1) begin
//  end else if (i_sh     == 1'b1) begin
//  end else if (i_sw     == 1'b1) begin
    end else if (i_addi == 1'b1) begin
        rd_vld <= 1'b1;
        rd     <= i_rs1 + i_imm; 
    end else if (i_slti == 1'b1) begin
        rd_vld <= 1'b1;
        rd     <= ($signed(i_rs1) < $signed(i_imm)) ? 32'h1 : 32'h0;
    end else if (i_sltiu == 1'b1) begin
        rd_vld <= 1'b1;
        rd     <= (i_rs1 < i_imm) ? 32'h1 : 32'h0;
    end else if (i_xori == 1'b1) begin
        rd_vld <= 1'b1;
        rd     <= i_rs1 ^ i_imm; 
    end else if (i_ori == 1'b1) begin
        rd_vld <= 1'b1;
        rd     <= i_rs1 | i_imm; 
    end else if (i_andi == 1'b1) begin
        rd_vld <= 1'b1;
        rd     <= i_rs1 & i_imm; 
    end else if (i_slli == 1'b1) begin
        rd_vld <= 1'b1;
        rd     <= i_rs1 << i_shamt; 
    end else if (i_srli == 1'b1) begin
        rd_vld <= 1'b1;
        rd     <= i_rs1 >> i_shamt; 
    end else if (i_srai == 1'b1) begin
        rd_vld <= 1'b1;
        rd     <= {{32{i_rs1[31]}}, i_rs1} >> i_shamt; 
    end else if (i_add == 1'b1) begin
        rd_vld <= 1'b1;
        rd     <= i_rs1 + i_rs2;
    end else if (i_sub == 1'b1) begin
        rd_vld <= 1'b1;
        rd     <= i_rs1 - i_rs2;
    end else if (i_slt == 1'b1) begin
        rd_vld <= 1'b1;
        rd     <= ($signed(i_rs1) < $signed(i_rs2)) ? 1'b1 : 1'b0;
    end else if (i_sltu == 1'b1) begin
        rd_vld <= 1'b1;
        rd     <= (i_rs1 < i_rs2) ? 1'b1 : 1'b0;
    end else if (i_sll == 1'b1) begin
        rd_vld <= 1'b1;
        rd     <= i_rs1 << i_rs2[4:0]; 
    end else if (i_srl == 1'b1) begin
        rd_vld <= 1'b1;
        rd     <= i_rs1 >> i_rs2[4:0]; 
    end else if (i_sra == 1'b1) begin
        rd_vld <= 1'b1;
        rd     <= {{32{i_rs1[31]}}, i_rs1} >> i_rs2[4:0]; 
    end else if (i_xor == 1'b1) begin
        rd_vld <= 1'b1;
        rd     <= i_rs1 ^ i_rs2;
    end else if (i_or == 1'b1) begin
        rd_vld <= 1'b1;
        rd     <= i_rs1 | i_rs2;
    end else if (i_and == 1'b1) begin
        rd_vld <= 1'b1;
        rd     <= i_rs1 & i_rs2;
//  end else if (i_fence  == 1'b1) begin
//  end else if (i_ecall  == 1'b1) begin
//  end else if (i_ebreak == 1'b1) begin
    end else begin
        rd_vld <= 1'b0;
    end
end

always @ (posedge i_clk or posedge i_rst)
begin
    if (i_rst == 1'b1) begin
        pc_vld <=  1'b0;
        pc     <= 32'h0;
    end else if (i_instr_vld == 1'b0) begin
        pc_vld <= 1'b0;
    end else if (i_jal == 1'b1) begin
        pc_vld <=  1'b1;
        pc     <= i_pc + i_imm;
    end else if (i_jalr == 1'b1) begin
        pc_vld <=  1'b1;
        pc     <= i_rs1 + i_imm;
    end else if (i_beq == 1'b1) begin
        pc_vld <= (i_rs1 == i_rs2) ? 1'b1  : 1'b0;
        pc     <= (i_rs1 == i_rs2) ? i_pc + i_imm : i_pc;
    end else if (i_bne == 1'b1) begin
        pc_vld <= (i_rs1 != i_rs2) ? 1'b1  : 1'b0;
        pc     <= (i_rs1 != i_rs2) ? i_pc + i_imm : i_pc;
    end else if (i_blt == 1'b1) begin
        pc_vld <= ($signed(i_rs1) <  $signed(i_rs2)) ? 1'b1  : 1'b0;
        pc     <= ($signed(i_rs1) <  $signed(i_rs2)) ? i_pc + i_imm : i_pc;
    end else if (i_bge == 1'b1) begin
        pc_vld <= ($signed(i_rs1) >= $signed(i_rs2)) ? 1'b1  : 1'b0;
        pc     <= ($signed(i_rs1) >= $signed(i_rs2)) ? i_pc + i_imm : i_pc;
    end else if (i_bltu == 1'b1) begin
        pc_vld <= (i_rs1 <  i_rs2) ? 1'b1  : 1'b0;
        pc     <= (i_rs1 <  i_rs2) ? i_pc + i_imm : i_pc;
    end else if (i_bgeu == 1'b1) begin
        pc_vld <= (i_rs1 >= i_rs2) ? 1'b1  : 1'b0;
        pc     <= (i_rs1 >= i_rs2) ? i_pc + i_imm : i_pc;
    end else begin
        pc_vld <= 1'b0;
    end
end

assign o_rd_vld  = rd_vld;
assign o_rd_data = rd;

assign o_pc_vld  = pc_vld;
assign o_pc      = pc;

////////////////////////////////////////////////////////////////////////////////////////////////////
// END
////////////////////////////////////////////////////////////////////////////////////////////////////
endmodule

