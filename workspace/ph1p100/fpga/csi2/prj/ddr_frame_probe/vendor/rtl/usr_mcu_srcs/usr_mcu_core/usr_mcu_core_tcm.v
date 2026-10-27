`timescale 1ps/1ps

`define MCU_TCM_OREG
`define MCU_TCM_64KB
//`define MCU_TCM_ROM  "../rom/mcu_rom.txt"

module usr_mcu_core_tcm #(
    parameter MCU_TCM_INIT = ""
)(
    input           i_clk       ,
    input           i_rst       ,

    input           i_tcm_wen   ,
    input   [31:0]  i_tcm_waddr , // 4-byte aligned
    input   [31:0]  i_tcm_wdata ,
    input   [ 3:0]  i_tcm_wmask ,

    input           i_tcm_ren   ,
    input   [31:0]  i_tcm_raddr , // 4-byte aligned
    output          o_tcm_rvld  ,
    output  [31:0]  o_tcm_rdata
);

///////////////////////////////////////////////////////////////////////////////////////////////////
// Local Parameters
///////////////////////////////////////////////////////////////////////////////////////////////////
`ifdef MCU_TCM_8KB
localparam AW = 11;
`elsif MCU_TCM_16KB
localparam AW = 12;
`elsif MCU_TCM_32KB
localparam AW = 13;
`elsif MCU_TCM_64KB
localparam AW = 14;
`endif

localparam DEPTH = 2**AW;

///////////////////////////////////////////////////////////////////////////////////////////////////
// Internal Signals
///////////////////////////////////////////////////////////////////////////////////////////////////
reg  [  31:0] tcm_mem[DEPTH-1:0];

wire [AW-1:0] mem_raddr;
reg  [32-1:0] mem_rdata;
reg           mem_rvld ;

wire [AW-1:0] mem_waddr;
wire [32-1:0] mem_wdata;

///////////////////////////////////////////////////////////////////////////////////////////////////
// TCM Init
///////////////////////////////////////////////////////////////////////////////////////////////////
initial begin
    $readmemh(MCU_TCM_INIT, tcm_mem);
end

///////////////////////////////////////////////////////////////////////////////////////////////////
// TCM Read
///////////////////////////////////////////////////////////////////////////////////////////////////
assign mem_raddr = i_tcm_raddr[2 +: AW];

`ifdef MCU_TCM_OREG
always @ (posedge i_clk or posedge i_rst)
begin
    if (i_rst == 1'b1) begin
        mem_rvld  <=  1'b0;
        mem_rdata <= 32'h0;
    end else if (i_tcm_ren) begin
        mem_rvld  <= 1'b1;
        mem_rdata <= tcm_mem[mem_raddr];
    end else begin
        mem_rvld  <= 1'b0;
    end
end
`else
always @ (posedge i_clk or posedge i_rst)
begin
    if (i_rst == 1'b1) begin
        mem_rvld  <=  1'b0;
    end else if (i_tcm_ren) begin
        mem_rvld  <= 1'b1;
    end else begin
        mem_rvld  <= 1'b0;
    end
end

always @ (*) begin
    mem_rdata <= tcm_mem[mem_raddr];
end
`endif

assign o_tcm_rvld  = mem_rvld ;
assign o_tcm_rdata = mem_rdata;

///////////////////////////////////////////////////////////////////////////////////////////////////
// TCM Write
///////////////////////////////////////////////////////////////////////////////////////////////////

assign mem_waddr = i_tcm_waddr[2 +: AW];

genvar n;
generate
    for (n = 0; n <= 3; n = n+1) begin : tcm_wbyte
        always @ (posedge i_clk) begin
            if (i_tcm_wen && i_tcm_wmask[n]) begin 
                tcm_mem[mem_waddr][8*n +: 8] <= i_tcm_wdata[8*n +: 8];
            end
        end
    end
endgenerate

///////////////////////////////////////////////////////////////////////////////////////////////////
// END
///////////////////////////////////////////////////////////////////////////////////////////////////
endmodule
