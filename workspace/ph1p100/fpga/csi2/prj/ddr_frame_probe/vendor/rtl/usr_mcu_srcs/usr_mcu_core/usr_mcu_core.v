
///////////////////////////////////////////////////////////////////////////////////////////////////
// mcu_core.v
///////////////////////////////////////////////////////////////////////////////////////////////////

`timescale 1ps / 1ps

module usr_mcu_core #(
    parameter  MCU_TCM_INIT = ""
)(
    input         i_clk         ,
    input         i_rst         ,

// local memory bus
    output        o_apb_psel    ,
    output        o_apb_penable ,
    output        o_apb_pwrite  ,
    output [31:0] o_apb_paddr   ,
    output [31:0] o_apb_pwdata  ,
    input  [31:0] i_apb_prdata  ,
    input         i_apb_pready
);

///////////////////////////////////////////////////////////////////////////////////////////////////
// Local Parameters
///////////////////////////////////////////////////////////////////////////////////////////////////
localparam [31:0] RESET_VECTOR = 32'h0000_0000;


///////////////////////////////////////////////////////////////////////////////////////////////////
// Internal Signals
///////////////////////////////////////////////////////////////////////////////////////////////////
wire         rst_done;
reg   [ 1:0] rst_r   ;
wire         rst_int ;

reg          pc_vld;
reg          pc_vld_r;
reg   [31:0] PC;

wire  [31:0] pc_jump;
wire         pc_jump_vld;

reg          instr_vld     ;
reg          instr_vld_r1  ;
reg          instr_vld_r2  ;
reg   [31:0] instr_code    ;

wire  [ 4:0] instr_rs1_idx ;
wire  [ 4:0] instr_rs2_idx ;
wire  [11:0] instr_csr_idx ;
wire  [31:0] instr_rs1     ;
wire  [31:0] instr_rs2     ;
wire  [ 4:0] instr_rd_idx  ;
wire  [31:0] instr_rd_data ;
wire         instr_rd_vld  ;

wire  [ 4:0] instr_shamt   ;
wire  [31:0] instr_imm     ;

wire         instr_op_system;
wire         instr_op_load  ;
wire         instr_op_store ;

wire         instr_lui    ;
wire         instr_auipc  ;
wire         instr_jal    ;
wire         instr_jalr   ;
wire         instr_beq    ;
wire         instr_bne    ;
wire         instr_blt    ;
wire         instr_bge    ;
wire         instr_bltu   ;
wire         instr_bgeu   ;
wire         instr_lb     ;
wire         instr_lh     ;
wire         instr_lw     ;
wire         instr_lbu    ;
wire         instr_lhu    ;
wire         instr_sb     ;
wire         instr_sh     ;
wire         instr_sw     ;
wire         instr_addi   ;
wire         instr_slti   ;
wire         instr_sltiu  ;
wire         instr_xori   ;
wire         instr_ori    ;
wire         instr_andi   ;
wire         instr_slli   ;
wire         instr_srli   ;
wire         instr_srai   ;
wire         instr_add    ;
wire         instr_sub    ;
wire         instr_sll    ;
wire         instr_slt    ;
wire         instr_sltu   ;
wire         instr_xor    ;
wire         instr_srl    ;
wire         instr_sra    ;
wire         instr_or     ;
wire         instr_and    ;
wire         instr_fence  ;
wire         instr_ecall  ;
wire         instr_ebreak ;

wire         instr_csrrw  ;
wire         instr_csrrc  ;
wire         instr_csrrs  ;
wire         instr_csrrwi ;
wire         instr_csrrci ;
wire         instr_csrrsi ;

wire         csr_rd_vld   ;
wire  [31:0] csr_rd_data  ;

wire         mem_wr_done  ;
wire         mem_rd_vld   ;
wire  [31:0] mem_rd_data  ;

wire         mem_wen      ;
wire  [31:0] mem_waddr    ;
wire  [31:0] mem_wdata    ;
wire  [ 3:0] mem_wmask    ;
wire         mem_wresp    ;
wire         mem_ren      ;
wire  [31:0] mem_raddr    ;
wire  [31:0] mem_rdata    ;
wire         mem_rvld     ;

wire         tcm_wen      ;
wire  [31:0] tcm_waddr    ;
wire  [31:0] tcm_wdata    ;
wire  [ 3:0] tcm_wmask    ;
wire         tcm_ren      ;
wire  [31:0] tcm_raddr    ;
wire  [31:0] tcm_rdata    ;
wire         tcm_rvld     ;

wire         mem2tcm_wen  ;
wire  [31:0] mem2tcm_waddr;
wire  [31:0] mem2tcm_wdata;
wire  [ 3:0] mem2tcm_wmask;
wire         mem2tcm_ren  ;
reg          mem2tcm_ren_r;
wire  [31:0] mem2tcm_raddr;
reg   [31:0] mem2tcm_rdata;
reg          mem2tcm_rvld ;

///////////////////////////////////////////////////////////////////////////////////////////////////
// Reset Generate
///////////////////////////////////////////////////////////////////////////////////////////////////
always @ (posedge i_clk or posedge i_rst)
begin
    if (i_rst == 1'b1)
        rst_r <= 2'b11;
    else if (rst_done)
        rst_r <= {rst_r[0], 1'b0};
end

assign rst_int = rst_r[1];

///////////////////////////////////////////////////////////////////////////////////////////////////
// Promgram Counter
///////////////////////////////////////////////////////////////////////////////////////////////////
reg  [1:0] pc_start_r;
wire       pc_start  ;
reg        pc_update ; // synthesis keep

always @ (posedge i_clk or posedge rst_int)
begin
    if (rst_int == 1'b1)
        pc_start_r <= 2'b00;
    else
        pc_start_r <= {pc_start_r[0], 1'b1};
end

assign pc_start = (pc_start_r[0] == 1'b1) & (pc_start_r[1] == 1'b0);

always @ (posedge i_clk or posedge rst_int)
begin
    if (rst_int == 1'b1)
        pc_update <= 1'b0;
    else if (instr_op_load)
        pc_update <= mem_rd_vld;
    else if (instr_op_store)
        pc_update <= mem_wr_done;
    else
        pc_update <= instr_vld_r1;
end

always @ (posedge i_clk or posedge rst_int)
begin
    if (rst_int == 1'b1)
        PC <= RESET_VECTOR;
    else if (pc_update == 1'b1)
        PC <= (pc_jump_vld == 1'b1) ? pc_jump : PC + 4'h4;
end

always @ (posedge i_clk or posedge rst_int)
begin
    if (rst_int == 1'b1)
        pc_vld <= 1'b0;
    else
        pc_vld <= pc_start | pc_update;
end

///////////////////////////////////////////////////////////////////////////////////////////////////
// PC to Memory
///////////////////////////////////////////////////////////////////////////////////////////////////
usr_mcu_core_tcm #(
    .MCU_TCM_INIT ( MCU_TCM_INIT )
) u_mcu_core_tcm (
    .i_clk       ( i_clk      ),
    .i_rst       ( rst_int    ),

    .i_tcm_wen   ( tcm_wen    ),
    .i_tcm_waddr ( tcm_waddr  ), // 4-byte aligned
    .i_tcm_wdata ( tcm_wdata  ),
    .i_tcm_wmask ( tcm_wmask  ),

    .i_tcm_ren   ( tcm_ren    ),
    .i_tcm_raddr ( tcm_raddr  ), // 4-byte aligned
    .o_tcm_rvld  ( tcm_rvld   ),
    .o_tcm_rdata ( tcm_rdata  )
);

assign tcm_wen   = mem2tcm_wen  ;
assign tcm_waddr = mem2tcm_waddr;
assign tcm_wdata = mem2tcm_wdata;
assign tcm_wmask = mem2tcm_wmask;

assign tcm_ren   = pc_vld | mem2tcm_ren;
assign tcm_raddr = pc_vld ? PC : mem2tcm_ren ? mem2tcm_raddr : PC;

always @ (posedge i_clk or posedge rst_int)
begin
    if (rst_int == 1'b1) begin
        pc_vld_r <= 1'b0;
    end else begin
        pc_vld_r <= pc_vld;
    end
end

always @ (posedge i_clk or posedge rst_int)
begin
    if (rst_int == 1'b1) begin
        instr_vld  <=  1'b0;
        instr_code <= 32'h0;
    end else if (pc_vld_r) begin
        instr_vld  <= 1'b1;
        instr_code <= tcm_rdata;
    end else begin
        instr_vld  <= 1'b0;
    end
end

always @ (posedge i_clk or posedge rst_int)
begin
    if (rst_int == 1'b1) begin
        instr_vld_r1 <= 1'b0;
        instr_vld_r2 <= 1'b0;
    end else begin
        instr_vld_r1 <= instr_vld;
        instr_vld_r2 <= instr_vld_r1;
    end
end

always @ (posedge i_clk or posedge rst_int)
begin
    if (rst_int == 1'b1) begin
       mem2tcm_ren_r <= 1'b0;
    end else begin
       mem2tcm_ren_r <= mem2tcm_ren;
    end
end

always @ (posedge i_clk or posedge rst_int)
begin
    if (rst_int == 1'b1) begin
       mem2tcm_rvld  <=  1'b0;
       mem2tcm_rdata <= 32'h0;
    end else if (mem2tcm_ren_r) begin
       mem2tcm_rvld  <= 1'b1;
       mem2tcm_rdata <= tcm_rdata;
    end else begin
       mem2tcm_rvld  <= 1'b0;
    end
end


///////////////////////////////////////////////////////////////////////////////////////////////////
// Instruction Decode
///////////////////////////////////////////////////////////////////////////////////////////////////
usr_mcu_core_decoder u_mcu_core_decoder (
    .i_instr     ( instr_code      ),

    .o_rd        ( instr_rd_idx    ),
    .o_rs1       ( instr_rs1_idx   ),
    .o_rs2       ( instr_rs2_idx   ),
    .o_csr       ( instr_csr_idx   ),
    .o_shamt     ( instr_shamt     ),
    .o_imm       ( instr_imm       ),

    .o_op_system ( instr_op_system ),
    .o_op_load   ( instr_op_load   ),
    .o_op_store  ( instr_op_store  ),

    .o_lui       ( instr_lui       ),
    .o_auipc     ( instr_auipc     ),
    .o_jal       ( instr_jal       ),
    .o_jalr      ( instr_jalr      ),
    .o_beq       ( instr_beq       ),
    .o_bne       ( instr_bne       ),
    .o_blt       ( instr_blt       ),
    .o_bge       ( instr_bge       ),
    .o_bltu      ( instr_bltu      ),
    .o_bgeu      ( instr_bgeu      ),
    .o_lb        ( instr_lb        ),
    .o_lh        ( instr_lh        ),
    .o_lw        ( instr_lw        ),
    .o_lbu       ( instr_lbu       ),
    .o_lhu       ( instr_lhu       ),
    .o_sb        ( instr_sb        ),
    .o_sh        ( instr_sh        ),
    .o_sw        ( instr_sw        ),
    .o_addi      ( instr_addi      ),
    .o_slti      ( instr_slti      ),
    .o_sltiu     ( instr_sltiu     ),
    .o_xori      ( instr_xori      ),
    .o_ori       ( instr_ori       ),
    .o_andi      ( instr_andi      ),
    .o_slli      ( instr_slli      ),
    .o_srli      ( instr_srli      ),
    .o_srai      ( instr_srai      ),
    .o_add       ( instr_add       ),
    .o_sub       ( instr_sub       ),
    .o_sll       ( instr_sll       ),
    .o_slt       ( instr_slt       ),
    .o_sltu      ( instr_sltu      ),
    .o_xor       ( instr_xor       ),
    .o_srl       ( instr_srl       ),
    .o_sra       ( instr_sra       ),
    .o_or        ( instr_or        ),
    .o_and       ( instr_and       ),
    .o_fence     ( instr_fence     ),
    .o_ecall     ( instr_ecall     ),
    .o_ebreak    ( instr_ebreak    ),

    .o_csrrw     ( instr_csrrw     ),
    .o_csrrs     ( instr_csrrs     ),
    .o_csrrc     ( instr_csrrc     ),
    .o_csrrwi    ( instr_csrrwi    ),
    .o_csrrsi    ( instr_csrrsi    ),
    .o_csrrci    ( instr_csrrci    )
);

///////////////////////////////////////////////////////////////////////////////////////////////////
// Control and Status Register
///////////////////////////////////////////////////////////////////////////////////////////////////
usr_mcu_core_csr u_mcu_core_csr (
    .i_clk       ( i_clk         ),
    .i_rst       ( rst_int       ),

    .i_op_system ( instr_vld_r1 & instr_op_system ),
    .i_csrrw     ( instr_csrrw   ),
    .i_csrrs     ( instr_csrrs   ),
    .i_csrrc     ( instr_csrrc   ),
    .i_csrrwi    ( instr_csrrwi  ),
    .i_csrrsi    ( instr_csrrsi  ),
    .i_csrrci    ( instr_csrrci  ),

    .i_csr       ( instr_csr_idx ),
    .i_rs1_data  ( instr_rs1     ),

    .o_rd_vld    ( csr_rd_vld    ),
    .o_rd_data   ( csr_rd_data   )
);

///////////////////////////////////////////////////////////////////////////////////////////////////
// Register File - 32 registers
///////////////////////////////////////////////////////////////////////////////////////////////////
usr_mcu_core_regfile u_mcu_core_regfile (
    .i_clk       ( i_clk         ),
    .i_rst       ( i_rst         ),
    .i_rs1       ( instr_rs1_idx ),
    .i_rs2       ( instr_rs2_idx ),
    .i_rd        ( instr_rd_idx  ),
    .i_rd_data   ( instr_rd_data ),
    .i_rd_vld    ( instr_rd_vld  ),
    .o_rs1_data  ( instr_rs1     ),
    .o_rs2_data  ( instr_rs2     ),
    .i_csr_rvld  ( csr_rd_vld    ),
    .i_csr_rdata ( csr_rd_data   ),
    .i_mem_rvld  ( mem_rd_vld    ),
    .i_mem_rdata ( mem_rd_data   ),
    .o_rst_done  ( rst_done      )
);

///////////////////////////////////////////////////////////////////////////////////////////////////
// Arithmetic Logic Unit - ALU
///////////////////////////////////////////////////////////////////////////////////////////////////
usr_mcu_core_alu u_mcu_core_alu (
    .i_clk        ( i_clk          ),
    .i_rst        ( rst_int        ),

    .i_instr_vld  ( instr_vld_r1   ),

    .i_pc         ( PC             ),
    .o_pc         ( pc_jump        ),
    .o_pc_vld     ( pc_jump_vld    ),

    .i_rs1        ( instr_rs1      ),
    .i_rs2        ( instr_rs2      ),

    .o_rd_vld     ( instr_rd_vld   ),
    .o_rd_data    ( instr_rd_data  ),

    .i_shamt      ( instr_shamt    ),
    .i_imm        ( instr_imm      ),

    .i_lui        ( instr_lui      ),
    .i_auipc      ( instr_auipc    ),
    .i_jal        ( instr_jal      ),
    .i_jalr       ( instr_jalr     ),
    .i_beq        ( instr_beq      ),
    .i_bne        ( instr_bne      ),
    .i_blt        ( instr_blt      ),
    .i_bge        ( instr_bge      ),
    .i_bltu       ( instr_bltu     ),
    .i_bgeu       ( instr_bgeu     ),
    .i_lb         ( instr_lb       ),
    .i_lh         ( instr_lh       ),
    .i_lw         ( instr_lw       ),
    .i_lbu        ( instr_lbu      ),
    .i_lhu        ( instr_lhu      ),
    .i_sb         ( instr_sb       ),
    .i_sh         ( instr_sh       ),
    .i_sw         ( instr_sw       ),
    .i_addi       ( instr_addi     ),
    .i_slti       ( instr_slti     ),
    .i_sltiu      ( instr_sltiu    ),
    .i_xori       ( instr_xori     ),
    .i_ori        ( instr_ori      ),
    .i_andi       ( instr_andi     ),
    .i_slli       ( instr_slli     ),
    .i_srli       ( instr_srli     ),
    .i_srai       ( instr_srai     ),
    .i_add        ( instr_add      ),
    .i_sub        ( instr_sub      ),
    .i_sll        ( instr_sll      ),
    .i_slt        ( instr_slt      ),
    .i_sltu       ( instr_sltu     ),
    .i_xor        ( instr_xor      ),
    .i_srl        ( instr_srl      ),
    .i_sra        ( instr_sra      ),
    .i_or         ( instr_or       ),
    .i_and        ( instr_and      ),
    .i_fence      ( instr_fence    ),
    .i_ecall      ( instr_ecall    ),
    .i_ebreak     ( instr_ebreak   )
);

///////////////////////////////////////////////////////////////////////////////////////////////////
// Register to Memory
///////////////////////////////////////////////////////////////////////////////////////////////////
usr_mcu_core_reg2mem u_mcu_core_reg2mem (
    .i_clk         ( i_clk          ),
    .i_rst         ( rst_int        ),

    .i_instr_vld   ( instr_vld_r1   ),
    .i_op_load     ( instr_op_load  ),
    .i_op_store    ( instr_op_store ),
    .i_lw          ( instr_lw       ),
    .i_lh          ( instr_lh       ),
    .i_lb          ( instr_lb       ),
    .i_lhu         ( instr_lhu      ),
    .i_lbu         ( instr_lbu      ),
    .i_sw          ( instr_sw       ),
    .i_sh          ( instr_sh       ),
    .i_sb          ( instr_sb       ),

    .i_imm         ( instr_imm      ),
    .i_rs1         ( instr_rs1      ),
    .i_rs2         ( instr_rs2      ),

    .o_mem_wen     ( mem_wen        ),
    .o_mem_waddr   ( mem_waddr      ),
    .o_mem_wdata   ( mem_wdata      ),
    .o_mem_wmask   ( mem_wmask      ),
    .i_mem_wresp   ( mem_wresp      ),

    .o_mem_ren     ( mem_ren        ),
    .o_mem_raddr   ( mem_raddr      ),
    .i_mem_rdata   ( mem_rdata      ),
    .i_mem_rvld    ( mem_rvld       ),

    .o_wr_done     ( mem_wr_done    ),
    .o_rd_vld      ( mem_rd_vld     ),
    .o_rd_data     ( mem_rd_data    )
);

///////////////////////////////////////////////////////////////////////////////////////////////////
// Memory to APB
///////////////////////////////////////////////////////////////////////////////////////////////////
usr_mcu_core_mem2apb u_mcu_core_mem2apb (
    .i_clk         ( i_clk         ),
    .i_rst         ( rst_int       ),

// master
    .i_mem_wen     ( mem_wen       ),
    .i_mem_waddr   ( mem_waddr     ),
    .i_mem_wdata   ( mem_wdata     ),
    .i_mem_wmask   ( mem_wmask     ),
    .o_mem_wresp   ( mem_wresp     ),

    .i_mem_ren     ( mem_ren       ),
    .i_mem_raddr   ( mem_raddr     ),
    .o_mem_rdata   ( mem_rdata     ),
    .o_mem_rvld    ( mem_rvld      ),

// slave - tcm
    .o_tcm_wen     ( mem2tcm_wen   ),
    .o_tcm_waddr   ( mem2tcm_waddr ),
    .o_tcm_wdata   ( mem2tcm_wdata ),
    .o_tcm_wmask   ( mem2tcm_wmask ),

    .o_tcm_ren     ( mem2tcm_ren   ),
    .o_tcm_raddr   ( mem2tcm_raddr ),
    .i_tcm_rdata   ( mem2tcm_rdata ),
    .i_tcm_rvld    ( mem2tcm_rvld  ),

// slave - apb
    .o_apb_psel    ( o_apb_psel    ),
    .o_apb_penable ( o_apb_penable ),
    .o_apb_pwrite  ( o_apb_pwrite  ),
    .o_apb_paddr   ( o_apb_paddr   ),
    .o_apb_pwdata  ( o_apb_pwdata  ),
    .i_apb_prdata  ( i_apb_prdata  ),
    .i_apb_pready  ( i_apb_pready  )
);


///////////////////////////////////////////////////////////////////////////////////////////////////
// End
///////////////////////////////////////////////////////////////////////////////////////////////////
endmodule
