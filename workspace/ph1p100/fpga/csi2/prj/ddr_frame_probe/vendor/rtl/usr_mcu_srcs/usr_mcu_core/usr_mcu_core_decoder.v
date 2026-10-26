`timescale 1ps/1ps

module usr_mcu_core_decoder (
    input   [31:0] i_instr     ,

    output  [ 4:0] o_rd        ,
    output  [ 4:0] o_rs1       ,
    output  [ 4:0] o_rs2       ,
    output  [ 4:0] o_shamt     ,
    output  [31:0] o_imm       ,
    output  [11:0] o_csr       ,
    output  [ 4:0] o_uimm      ,

    output         o_op_system ,
    output         o_op_load   ,
    output         o_op_store  ,

    output         o_lui    ,
    output         o_auipc  ,
    output         o_jal    ,
    output         o_jalr   ,
    output         o_beq    ,
    output         o_bne    ,
    output         o_blt    ,
    output         o_bge    ,
    output         o_bltu   ,
    output         o_bgeu   ,
    output         o_lb     ,
    output         o_lh     ,
    output         o_lw     ,
    output         o_lbu    ,
    output         o_lhu    ,
    output         o_sb     ,
    output         o_sh     ,
    output         o_sw     ,
    output         o_addi   ,
    output         o_slti   ,
    output         o_sltiu  ,
    output         o_xori   ,
    output         o_ori    ,
    output         o_andi   ,
    output         o_slli   ,
    output         o_srli   ,
    output         o_srai   ,
    output         o_add    ,
    output         o_sub    ,
    output         o_sll    ,
    output         o_slt    ,
    output         o_sltu   ,
    output         o_xor    ,
    output         o_srl    ,
    output         o_sra    ,
    output         o_or     ,
    output         o_and    ,
    output         o_fence  ,
    output         o_ecall  ,
    output         o_ebreak ,

    output         o_csrrw  ,
    output         o_csrrs  ,
    output         o_csrrc  ,
    output         o_csrrwi ,
    output         o_csrrsi ,
    output         o_csrrci

);

////////////////////////////////////////////////////////////////////////////////////////////////////
// Local Parameter Definition
////////////////////////////////////////////////////////////////////////////////////////////////////


////////////////////////////////////////////////////////////////////////////////////////////////////
// RV32I Base Instruction Format
////////////////////////////////////////////////////////////////////////////////////////////////////
//---------------------------------------------------------------------------------------------------------
//         | 31 30 29 28 27 26 25 24 23 22 21 20|19 18 17 16 15|14 13 12|11 10 9 8 7        |6 5 4 3 2 1 0|
//---------------------------------------------------------------------------------------------------------
// R-type  | funct7              | rs2          | rs1          | funct3 | rd                | opcode      |
//---------------------------------------------------------------------------------------------------------
// I-type  | imm[11:0]                          | rs1          | funct3 | rd                | opcode      |
//---------------------------------------------------------------------------------------------------------
// S-type  | imm[11:5]           | rs2          | rs1          | funct3 | imm[4:0]          | opcode      |
//---------------------------------------------------------------------------------------------------------
// B-type  | imm[12], imm[10:5]  | rs2          | rs1          | funct3 | imm[4:1], imm[11] | opcode      |
//---------------------------------------------------------------------------------------------------------
// U-type  | imm[31:12]                                                 | rd                | opcode      |
//---------------------------------------------------------------------------------------------------------
// J-type  | imm[20], imm[10:1], imm[11], imm[19:12]                    | rd                | opcode      |
//---------------------------------------------------------------------------------------------------------

localparam  [6:0]  OPCODE_MAP_LOAD     = 7'b00_000_11;
localparam  [6:0]  OPCODE_MAP_LOAD_LP  = 7'b00_001_11;
localparam  [6:0]  OPCODE_MAP_CUST0    = 7'b00_010_11; // custom instruction
localparam  [6:0]  OPCODE_MAP_MISC_MEM = 7'b00_011_11;
localparam  [6:0]  OPCODE_MAP_OP_IMM   = 7'b00_100_11;
localparam  [6:0]  OPCODE_MAP_AUIPC    = 7'b00_101_11;
localparam  [6:0]  OPCODE_MAP_OP_IMM32 = 7'b00_110_11;

localparam  [6:0]  OPCODE_MAP_STORE    = 7'b01_000_11;
localparam  [6:0]  OPCODE_MAP_STORE_FP = 7'b01_001_11;
localparam  [6:0]  OPCODE_MAP_CUST1    = 7'b01_010_11; // custom instruction
localparam  [6:0]  OPCODE_MAP_AMO      = 7'b01_011_11;
localparam  [6:0]  OPCODE_MAP_OP       = 7'b01_100_11;
localparam  [6:0]  OPCODE_MAP_LUI      = 7'b01_101_11;
localparam  [6:0]  OPCODE_MAP_OP32     = 7'b01_110_11;

localparam  [6:0]  OPCODE_MAP_MADD     = 7'b10_000_11;
localparam  [6:0]  OPCODE_MAP_MSUB     = 7'b10_001_11;
localparam  [6:0]  OPCODE_MAP_NMSUB    = 7'b10_010_11;
localparam  [6:0]  OPCODE_MAP_NMADD    = 7'b10_011_11;
localparam  [6:0]  OPCODE_MAP_OP_FP    = 7'b10_100_11;
localparam  [6:0]  OPCODE_MAP_RSVD0    = 7'b10_101_11; // do not use
localparam  [6:0]  OPCODE_MAP_CUST2    = 7'b10_110_11; // custom instruction

localparam  [6:0]  OPCODE_MAP_BRANCH   = 7'b11_000_11;
localparam  [6:0]  OPCODE_MAP_JALR     = 7'b11_001_11;
localparam  [6:0]  OPCODE_MAP_RSVD1    = 7'b11_010_11; // do not use
localparam  [6:0]  OPCODE_MAP_JAL      = 7'b11_011_11;
localparam  [6:0]  OPCODE_MAP_SYSTEM   = 7'b11_100_11;
localparam  [6:0]  OPCODE_MAP_RSVD2    = 7'b11_101_11; // do not use
localparam  [6:0]  OPCODE_MAP_CUST3    = 7'b11_110_11; // custom instruction

////////////////////////////////////////////////////////////////////////////////////////////////////
// RV32I Base Instruction Set
////////////////////////////////////////////////////////////////////////////////////////////////////
// OPCODE : JALR 
localparam  [2:0] FUNCT3_JALR    = 3'b000;

// OPCODE : BRANCH
localparam  [2:0] FUNCT3_BEQ     = 3'b000;
localparam  [2:0] FUNCT3_BNE     = 3'b001;
localparam  [2:0] FUNCT3_BLT     = 3'b100;
localparam  [2:0] FUNCT3_BGE     = 3'b101;
localparam  [2:0] FUNCT3_BLTU    = 3'b110;
localparam  [2:0] FUNCT3_BGEU    = 3'b111;

// OPCODE : LOAD
localparam  [2:0] FUNCT3_LB      = 3'b000;
localparam  [2:0] FUNCT3_LH      = 3'b001;
localparam  [2:0] FUNCT3_LW      = 3'b010;
localparam  [2:0] FUNCT3_LBU     = 3'b100;
localparam  [2:0] FUNCT3_LHU     = 3'b101;

// OPCODE : STORE
localparam  [2:0] FUNCT3_SB      = 3'b000;
localparam  [2:0] FUNCT3_SH      = 3'b001;
localparam  [2:0] FUNCT3_SW      = 3'b010;

// OPCODE : OP_IMM
localparam  [2:0] FUNCT3_ADDI    = 3'b000;
localparam  [2:0] FUNCT3_SLTI    = 3'b010;
localparam  [2:0] FUNCT3_SLTIU   = 3'b011;
localparam  [2:0] FUNCT3_XORI    = 3'b100;
localparam  [2:0] FUNCT3_ORI     = 3'b110;
localparam  [2:0] FUNCT3_ANDI    = 3'b111;
localparam  [2:0] FUNCT3_SLLI    = 3'b001;
localparam  [2:0] FUNCT3_SRLI    = 3'b101;
localparam  [2:0] FUNCT3_SRAI    = 3'b101;

// OPCODE : OP
localparam  [2:0] FUNCT3_ADD     = 3'b000;
localparam  [2:0] FUNCT3_SUB     = 3'b000;
localparam  [2:0] FUNCT3_SLL     = 3'b001;
localparam  [2:0] FUNCT3_SLT     = 3'b010;
localparam  [2:0] FUNCT3_SLTU    = 3'b011;
localparam  [2:0] FUNCT3_LTU     = 3'b011;
localparam  [2:0] FUNCT3_XOR     = 3'b100;
localparam  [2:0] FUNCT3_SRL     = 3'b101;
localparam  [2:0] FUNCT3_SRA     = 3'b101;
localparam  [2:0] FUNCT3_OR      = 3'b110;
localparam  [2:0] FUNCT3_AND     = 3'b111;

// OPCODE : MISC_MEM
localparam  [2:0] FUNCT3_FENCE   = 3'b000;
localparam  [2:0] FUNCT3_FENCE_I = 3'b001;

// OPCODE : SYSTEM
localparam  [2:0] FUNCT3_PRIV    = 3'b000;
localparam  [2:0] FUNCT3_CSRRW   = 3'b001;
localparam  [2:0] FUNCT3_CSRRS   = 3'b010;
localparam  [2:0] FUNCT3_CSRRC   = 3'b011;
localparam  [2:0] FUNCT3_CSRRWI  = 3'b101;
localparam  [2:0] FUNCT3_CSRRSI  = 3'b110;
localparam  [2:0] FUNCT3_CSRRCI  = 3'b111;
localparam  [2:0] FUNCT12_ECALL  = 12'b0000_0000_0000;
localparam  [2:0] FUNCT12_EBREAK = 12'b0000_0000_0001;


localparam  [31:0] ISA_ECALL     = 32'b0000000_00000_00000_000_00000_1110011;
localparam  [31:0] ISA_EBREAK    = 32'b0000000_00001_00000_000_00000_1110011;
localparam  [31:0] ISA_URET      = 32'b0000000_00010_00000_000_00000_1110011;
localparam  [31:0] ISA_SRET      = 32'b0001000_00010_00000_000_00000_1110011;
localparam  [31:0] ISA_MRET      = 32'b0011000_00010_00000_000_00000_1110011;
localparam  [31:0] ISA_WFI       = 32'b0001000_00101_00000_000_00000_1110011;

////////////////////////////////////////////////////////////////////////////////////////////////////
// Internal Signal Definition
////////////////////////////////////////////////////////////////////////////////////////////////////
wire  [ 6:0] opcode = i_instr[ 6: 0];
wire  [ 4:0] rd     = i_instr[11: 7];
wire  [ 2:0] funct3 = i_instr[14:12];
wire  [ 4:0] rs1    = i_instr[19:15];
wire  [ 4:0] rs2    = i_instr[24:20];
wire  [ 4:0] shamt  = i_instr[24:20];
wire  [ 6:0] funct7 = i_instr[31:25];
wire  [11:0] csr    = i_instr[31:20];

wire  [ 4:0] uimm   = i_instr[19:15];

wire  [31:0] imm_i  = {{20{i_instr[31]}}, i_instr[31:20]};
wire  [31:0] imm_s  = {{20{i_instr[31]}}, i_instr[31:25], i_instr[11:7]};
wire  [31:0] imm_u  = {i_instr[31:12], 12'h0};

wire  [31:0] imm_b  = {{19{i_instr[31]}}, i_instr[31], i_instr[7], i_instr[30:25], i_instr[11: 8], 1'b0};
wire  [31:0] imm_j  = {{12{i_instr[31]}}, i_instr[31], i_instr[19:12], i_instr[20], i_instr[30:21], 1'b0};

////////////////////////////////////////////////////////////////////////////////////////////////////
// Instruction Decoder
////////////////////////////////////////////////////////////////////////////////////////////////////
wire instr_ecall   = (i_instr[31:0] == ISA_ECALL ) ? 1'b1 : 1'b0;
wire instr_ebreak  = (i_instr[31:0] == ISA_EBREAK) ? 1'b1 : 1'b0;
wire instr_uret    = (i_instr[31:0] == ISA_URET  ) ? 1'b1 : 1'b0;
wire instr_sret    = (i_instr[31:0] == ISA_SRET  ) ? 1'b1 : 1'b0;
wire instr_mret    = (i_instr[31:0] == ISA_MRET  ) ? 1'b1 : 1'b0;
wire instr_wfi     = (i_instr[31:0] == ISA_WFI   ) ? 1'b1 : 1'b0;

wire instr_op_load     = (opcode == OPCODE_MAP_LOAD    ) ? 1'b1 : 1'b0 ;
wire instr_op_load_lp  = (opcode == OPCODE_MAP_LOAD_LP ) ? 1'b1 : 1'b0 ;
wire instr_op_misc_mem = (opcode == OPCODE_MAP_MISC_MEM) ? 1'b1 : 1'b0 ;
wire instr_op_imm      = (opcode == OPCODE_MAP_OP_IMM  ) ? 1'b1 : 1'b0 ;
wire instr_op_auipc    = (opcode == OPCODE_MAP_AUIPC   ) ? 1'b1 : 1'b0 ;
wire instr_op_imm32    = (opcode == OPCODE_MAP_OP_IMM32) ? 1'b1 : 1'b0 ;
wire instr_op_store    = (opcode == OPCODE_MAP_STORE   ) ? 1'b1 : 1'b0 ;
wire instr_op_store_fp = (opcode == OPCODE_MAP_STORE_FP) ? 1'b1 : 1'b0 ;
wire instr_op_amo      = (opcode == OPCODE_MAP_AMO     ) ? 1'b1 : 1'b0 ;
wire instr_op_op       = (opcode == OPCODE_MAP_OP      ) ? 1'b1 : 1'b0 ;
wire instr_op_lui      = (opcode == OPCODE_MAP_LUI     ) ? 1'b1 : 1'b0 ;
wire instr_op_op32     = (opcode == OPCODE_MAP_OP32    ) ? 1'b1 : 1'b0 ;
wire instr_op_madd     = (opcode == OPCODE_MAP_MADD    ) ? 1'b1 : 1'b0 ;
wire instr_op_msub     = (opcode == OPCODE_MAP_MSUB    ) ? 1'b1 : 1'b0 ;
wire instr_op_nmsub    = (opcode == OPCODE_MAP_NMSUB   ) ? 1'b1 : 1'b0 ;
wire instr_op_nmadd    = (opcode == OPCODE_MAP_NMADD   ) ? 1'b1 : 1'b0 ;
wire instr_op_fp       = (opcode == OPCODE_MAP_OP_FP   ) ? 1'b1 : 1'b0 ;
wire instr_op_branch   = (opcode == OPCODE_MAP_BRANCH  ) ? 1'b1 : 1'b0 ;
wire instr_op_jalr     = (opcode == OPCODE_MAP_JALR    ) ? 1'b1 : 1'b0 ;
wire instr_op_jal      = (opcode == OPCODE_MAP_JAL     ) ? 1'b1 : 1'b0 ;
wire instr_op_system   = (opcode == OPCODE_MAP_SYSTEM  ) ? 1'b1 : 1'b0 ;

// OPCODE : BRANCH
wire instr_beq  = instr_op_branch && (funct3 == FUNCT3_BEQ );
wire instr_bne  = instr_op_branch && (funct3 == FUNCT3_BNE );
wire instr_blt  = instr_op_branch && (funct3 == FUNCT3_BLT );
wire instr_bge  = instr_op_branch && (funct3 == FUNCT3_BGE );
wire instr_bltu = instr_op_branch && (funct3 == FUNCT3_BLTU);
wire instr_bgeu = instr_op_branch && (funct3 == FUNCT3_BGEU);

// OPCODE : LOAD
wire instr_lb  = instr_op_load && (funct3 == FUNCT3_LB );
wire instr_lh  = instr_op_load && (funct3 == FUNCT3_LH );
wire instr_lw  = instr_op_load && (funct3 == FUNCT3_LW );
wire instr_lbu = instr_op_load && (funct3 == FUNCT3_LBU);
wire instr_lhu = instr_op_load && (funct3 == FUNCT3_LHU);

// OPCODE : STORE
wire instr_sb = instr_op_store && (funct3 == FUNCT3_SB);
wire instr_sh = instr_op_store && (funct3 == FUNCT3_SH);
wire instr_sw = instr_op_store && (funct3 == FUNCT3_SW);

// OPCODE : OP_IMM
wire instr_addi  = instr_op_imm && (funct3 == FUNCT3_ADDI );
wire instr_slti  = instr_op_imm && (funct3 == FUNCT3_SLTI );
wire instr_sltiu = instr_op_imm && (funct3 == FUNCT3_SLTIU);
wire instr_xori  = instr_op_imm && (funct3 == FUNCT3_XORI );
wire instr_ori   = instr_op_imm && (funct3 == FUNCT3_ORI  );
wire instr_andi  = instr_op_imm && (funct3 == FUNCT3_ANDI );

wire instr_slli  = instr_op_imm && (funct3 == FUNCT3_SLLI) && (funct7 == 7'b000_0000);
wire instr_srli  = instr_op_imm && (funct3 == FUNCT3_SRLI) && (funct7 == 7'b000_0000);
wire instr_srai  = instr_op_imm && (funct3 == FUNCT3_SRAI) && (funct7 == 7'b010_0000);

// OPCODE : OP
wire instr_add  = instr_op_op && (funct3 == FUNCT3_ADD ) && (funct7 == 7'b000_0000);
wire instr_sub  = instr_op_op && (funct3 == FUNCT3_SUB ) && (funct7 == 7'b010_0000);
wire instr_sll  = instr_op_op && (funct3 == FUNCT3_SLL ) && (funct7 == 7'b000_0000);
wire instr_slt  = instr_op_op && (funct3 == FUNCT3_SLT ) && (funct7 == 7'b000_0000);
wire instr_sltu = instr_op_op && (funct3 == FUNCT3_SLTU) && (funct7 == 7'b000_0000);
wire instr_ltu  = instr_op_op && (funct3 == FUNCT3_LTU ) && (funct7 == 7'b000_0000);
wire instr_xor  = instr_op_op && (funct3 == FUNCT3_XOR ) && (funct7 == 7'b000_0000);
wire instr_srl  = instr_op_op && (funct3 == FUNCT3_SRL ) && (funct7 == 7'b000_0000);
wire instr_sra  = instr_op_op && (funct3 == FUNCT3_SRA ) && (funct7 == 7'b010_0000);
wire instr_or   = instr_op_op && (funct3 == FUNCT3_OR  ) && (funct7 == 7'b000_0000);
wire instr_and  = instr_op_op && (funct3 == FUNCT3_AND ) && (funct7 == 7'b000_0000);

// OPCODE : MISC_MEM
wire instr_fence = instr_op_misc_mem && (funct3 == FUNCT3_FENCE);

wire instr_nop = instr_addi && (rs1 == 5'h0) && (imm_i == 12'h0) && (rd == 5'h0);

// OPCODE : SYSTEM
wire instr_csrrw  = instr_op_system && (funct3 == FUNCT3_CSRRW ); 
wire instr_csrrs  = instr_op_system && (funct3 == FUNCT3_CSRRS ); 
wire instr_csrrc  = instr_op_system && (funct3 == FUNCT3_CSRRC ); 
wire instr_csrrwi = instr_op_system && (funct3 == FUNCT3_CSRRWI); 
wire instr_csrrsi = instr_op_system && (funct3 == FUNCT3_CSRRSI); 
wire instr_csrrci = instr_op_system && (funct3 == FUNCT3_CSRRCI); 

////////////////////////////////////////////////////////////////////////////////////////////////////
// Instruction Output
////////////////////////////////////////////////////////////////////////////////////////////////////
assign o_lui    = instr_op_lui  ;
assign o_auipc  = instr_op_auipc;
assign o_jal    = instr_op_jal  ;
assign o_jalr   = instr_op_jalr ;
assign o_beq    = instr_beq   ;
assign o_bne    = instr_bne   ;
assign o_blt    = instr_blt   ;
assign o_bge    = instr_bge   ;
assign o_bltu   = instr_bltu  ;
assign o_bgeu   = instr_bgeu  ;
assign o_lb     = instr_lb    ;
assign o_lh     = instr_lh    ;
assign o_lw     = instr_lw    ;
assign o_lbu    = instr_lbu   ;
assign o_lhu    = instr_lhu   ;
assign o_sb     = instr_sb    ;
assign o_sh     = instr_sh    ;
assign o_sw     = instr_sw    ;
assign o_addi   = instr_addi  ;
assign o_slti   = instr_slti  ;
assign o_sltiu  = instr_sltiu ;
assign o_xori   = instr_xori  ;
assign o_ori    = instr_ori   ;
assign o_andi   = instr_andi  ;
assign o_slli   = instr_slli  ;
assign o_srli   = instr_srli  ;
assign o_srai   = instr_srai  ;
assign o_add    = instr_add   ;
assign o_sub    = instr_sub   ;
assign o_sll    = instr_sll   ;
assign o_slt    = instr_slt   ;
assign o_sltu   = instr_sltu  ;
assign o_xor    = instr_xor   ;
assign o_srl    = instr_srl   ;
assign o_sra    = instr_sra   ;
assign o_or     = instr_or    ;
assign o_and    = instr_and   ;
assign o_fence  = instr_fence ;
assign o_ecall  = instr_ecall ;
assign o_ebreak = instr_ebreak;

assign o_csrrw  = instr_csrrw ;
assign o_csrrs  = instr_csrrs ;
assign o_csrrc  = instr_csrrc ;
assign o_csrrwi = instr_csrrwi;
assign o_csrrsi = instr_csrrsi;
assign o_csrrci = instr_csrrci;

assign o_op_system = instr_op_system;
assign o_op_load   = instr_op_load;
assign o_op_store  = instr_op_store;

assign o_csr    = csr;
assign o_uimm   = uimm;

assign o_rd     = rd ;
assign o_rs1    = rs1;
assign o_rs2    = rs2;
assign o_shamt  = shamt;
assign o_imm    = instr_op_lui    ? imm_u :
                  instr_op_auipc  ? imm_u :
                  instr_op_imm    ? imm_i :
                  instr_op_jalr   ? imm_i :
                  instr_op_load   ? imm_i :
                  instr_op_store  ? imm_s :
                  instr_op_branch ? imm_b :
                  instr_op_jal    ? imm_j : 32'h0;

endmodule

