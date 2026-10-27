`timescale 1ps/1ps

module usr_mcu_core_csr (
    input          i_clk       ,
    input          i_rst       ,

    input          i_op_system ,
    input          i_csrrw     ,
    input          i_csrrs     ,
    input          i_csrrc     ,
    input          i_csrrwi    ,
    input          i_csrrsi    ,
    input          i_csrrci    ,

    input  [11:0]  i_csr       ,
    input  [31:0]  i_rs1_data  ,

    output         o_rd_vld    ,
    output [31:0]  o_rd_data
);

///////////////////////////////////////////////////////////////////////////////////////////////////
// Local Parameters
///////////////////////////////////////////////////////////////////////////////////////////////////
localparam  [11:0]  ADDR_CSR_FFLAGS     =  12'h001;
localparam  [11:0]  ADDR_CSR_FRM        =  12'h002;
localparam  [11:0]  ADDR_CSR_FCSR       =  12'h003;
localparam  [11:0]  ADDR_CSR_MSTATUS    =  12'h300;
localparam  [11:0]  ADDR_CSR_MISA       =  12'h301;
localparam  [11:0]  ADDR_CSR_MIE        =  12'h304;
localparam  [11:0]  ADDR_CSR_MTVEC      =  12'h305;
localparam  [11:0]  ADDR_CSR_MSCRATCH   =  12'h340;
localparam  [11:0]  ADDR_CSR_MEPC       =  12'h341;
localparam  [11:0]  ADDR_CSR_MCAUSE     =  12'h342;
localparam  [11:0]  ADDR_CSR_MTVAL      =  12'h343;
localparam  [11:0]  ADDR_CSR_MIP        =  12'h344;
localparam  [11:0]  ADDR_CSR_MCYCLE     =  12'hB00;
localparam  [11:0]  ADDR_CSR_MCYCLEH    =  12'hB80;
localparam  [11:0]  ADDR_CSR_MINSTRET   =  12'hB02;
localparam  [11:0]  ADDR_CSR_MINSTRETH  =  12'hB82;
localparam  [11:0]  ADDR_CSR_MVENDORID  =  12'hF11;
localparam  [11:0]  ADDR_CSR_MARCHID    =  12'hF12;
localparam  [11:0]  ADDR_CSR_MIMPID     =  12'hF13;
localparam  [11:0]  ADDR_CSR_MHARTID    =  12'hF14;


///////////////////////////////////////////////////////////////////////////////////////////////////
// Internal Signals
///////////////////////////////////////////////////////////////////////////////////////////////////
reg  [31:0]  CSR_FFLAGS   ; // 0x001, MRW
reg  [31:0]  CSR_FRM      ; // 0x002, MRW
reg  [31:0]  CSR_FCSR     ; // 0x003, MRW
reg  [31:0]  CSR_MSTATUS  ; // 0x300, MRW
reg  [31:0]  CSR_MISA     ; // 0x301, MRW
reg  [31:0]  CSR_MIE      ; // 0x304, MRW
reg  [31:0]  CSR_MTVEC    ; // 0x305, MRW
reg  [31:0]  CSR_MSCRATCH ; // 0x340, MRW
reg  [31:0]  CSR_MEPC     ; // 0x341, MRW
reg  [31:0]  CSR_MCAUSE   ; // 0x342, MRW
reg  [31:0]  CSR_MTVAL    ; // 0x343, MRW
reg  [31:0]  CSR_MIP      ; // 0x344, MRW
reg  [31:0]  CSR_MCYCLE   ; // 0xB00, MRW
reg  [31:0]  CSR_MCYCLEH  ; // 0xB80, MRW
reg  [31:0]  CSR_MINSTRET ; // 0xB02, MRW
reg  [31:0]  CSR_MINSTRETH; // 0xB82, MRW
reg  [31:0]  CSR_MVENDORID; // 0xF11, MRO
reg  [31:0]  CSR_MARCHID  ; // 0xF12, MRO
reg  [31:0]  CSR_MIMPID   ; // 0xF13, MRO
reg  [31:0]  CSR_MHARTID  ; // 0xF14, MRO

reg  [31:0]  CSR_MTIME    ; // NA, MRW
reg  [31:0]  CSR_MTIMECMP ; // NA, MRW
reg  [31:0]  CSR_MSIP     ; // NA, MRW

reg          csr_rvld ;
reg  [31:0]  csr_rdata;

///////////////////////////////////////////////////////////////////////////////////////////////////
// CSR Write
///////////////////////////////////////////////////////////////////////////////////////////////////

//reg  [31:0]  CSR_MIE      ; // 0x304, MRW
always @ (posedge i_clk or posedge i_rst)
begin
    if (i_rst == 1'b1) begin
        CSR_MIE <= 32'h0;
    end else if (i_op_system == 1'b1) begin
        CSR_MIE <= (i_csrrw == 1'b1) && (i_csr == ADDR_CSR_MIE) ? i_rs1_data : CSR_MIE;
    end
end

//reg  [31:0]  CSR_MSTATUS  ; // 0x300, MRW
always @ (posedge i_clk or posedge i_rst)
begin
    if (i_rst == 1'b1) begin
        CSR_MSTATUS <= 32'h0;
    end else if (i_op_system == 1'b1) begin
        CSR_MSTATUS <= (i_csrrw == 1'b1) && (i_csr == ADDR_CSR_MSTATUS) ? i_rs1_data : CSR_MSTATUS;
    end
end



// reg  [31:0]  CSR_MVENDORID; // 0xF11, MRO
// reg  [31:0]  CSR_MARCHID  ; // 0xF12, MRO
// reg  [31:0]  CSR_MIMPID   ; // 0xF13, MRO
// reg  [31:0]  CSR_MHARTID  ; // 0xF14, MRO
always @ (posedge i_clk or posedge i_rst)
begin
    if (i_rst == 1'b1) begin
        CSR_MVENDORID <= 32'h0688_1070;
        CSR_MARCHID   <= 32'h2004_0722;
        CSR_MIMPID    <= 32'h2004_0722;
        CSR_MHARTID   <= 32'h0000_0000;
    end else begin
    end
end

///////////////////////////////////////////////////////////////////////////////////////////////////
// CSR Read
///////////////////////////////////////////////////////////////////////////////////////////////////
always @ (posedge i_clk or posedge i_rst)
begin
    if (i_rst == 1'b1) begin
        csr_rvld  <=  1'b0;
        csr_rdata <= 32'h0;
    end else if (i_op_system == 1'b0) begin
        csr_rvld  <=  1'b0;
        csr_rdata <= 32'h0;
    end else if (i_op_system == 1'b1) begin
        csr_rvld  <= 1'b1;
        case (i_csr[11:0])
            ADDR_CSR_FFLAGS    : csr_rdata <= CSR_FFLAGS   ;
            ADDR_CSR_FRM       : csr_rdata <= CSR_FRM      ;
            ADDR_CSR_FCSR      : csr_rdata <= CSR_FCSR     ;
            ADDR_CSR_MSTATUS   : csr_rdata <= CSR_MSTATUS  ;
            ADDR_CSR_MISA      : csr_rdata <= CSR_MISA     ;
            ADDR_CSR_MIE       : csr_rdata <= CSR_MIE      ;
            ADDR_CSR_MTVEC     : csr_rdata <= CSR_MTVEC    ;
            ADDR_CSR_MSCRATCH  : csr_rdata <= CSR_MSCRATCH ;
            ADDR_CSR_MEPC      : csr_rdata <= CSR_MEPC     ;
            ADDR_CSR_MCAUSE    : csr_rdata <= CSR_MCAUSE   ;
            ADDR_CSR_MTVAL     : csr_rdata <= CSR_MTVAL    ;
            ADDR_CSR_MIP       : csr_rdata <= CSR_MIP      ;
            ADDR_CSR_MCYCLE    : csr_rdata <= CSR_MCYCLE   ;
            ADDR_CSR_MCYCLEH   : csr_rdata <= CSR_MCYCLEH  ;
            ADDR_CSR_MINSTRET  : csr_rdata <= CSR_MINSTRET ;
            ADDR_CSR_MINSTRETH : csr_rdata <= CSR_MINSTRETH;
            ADDR_CSR_MVENDORID : csr_rdata <= CSR_MVENDORID;
            ADDR_CSR_MARCHID   : csr_rdata <= CSR_MARCHID  ;
            ADDR_CSR_MIMPID    : csr_rdata <= CSR_MIMPID   ;
            ADDR_CSR_MHARTID   : csr_rdata <= CSR_MHARTID  ;
            default            : csr_rdata <= 32'hdeadbeef ;
        endcase
    end
end

assign o_rd_vld  = csr_rvld ;
assign o_rd_data = csr_rdata;

///////////////////////////////////////////////////////////////////////////////////////////////////
// END
///////////////////////////////////////////////////////////////////////////////////////////////////
endmodule
