`timescale 1ps/1ps

module usr_mcu_core_mem2apb (
    input          i_clk         ,
    input          i_rst         ,

// master
    input          i_mem_wen     ,
    input  [31:0]  i_mem_waddr   ,
    input  [31:0]  i_mem_wdata   ,
    input  [ 3:0]  i_mem_wmask   ,
    output         o_mem_wresp   ,

    input          i_mem_ren     ,
    input  [31:0]  i_mem_raddr   ,
    output [31:0]  o_mem_rdata   ,
    output         o_mem_rvld    ,

// slave - tcm
    output         o_tcm_wen     ,
    output [31:0]  o_tcm_waddr   ,
    output [31:0]  o_tcm_wdata   ,
    output [ 3:0]  o_tcm_wmask   ,

    output         o_tcm_ren     ,
    output [31:0]  o_tcm_raddr   ,
    input  [31:0]  i_tcm_rdata   ,
    input          i_tcm_rvld    ,

// slave - apb
    output         o_apb_psel    ,
    output         o_apb_penable ,
    output         o_apb_pwrite  ,
    output [31:0]  o_apb_paddr   ,
    output [31:0]  o_apb_pwdata  ,
    input  [31:0]  i_apb_prdata  ,
    input          i_apb_pready
);

///////////////////////////////////////////////////////////////////////////////////////////////////
// Local Parameters
///////////////////////////////////////////////////////////////////////////////////////////////////
localparam [1:0]  S_IDLE   = 2'b00;
localparam [1:0]  S_SETUP  = 2'b01; 
localparam [1:0]  S_ACCESS = 2'b10;

localparam [31:0] TCM_BASEADDR = 32'h0000_0000;
localparam [31:0] APB_BASEADDR = 32'h8000_0000;

///////////////////////////////////////////////////////////////////////////////////////////////////
// Internal Signals
///////////////////////////////////////////////////////////////////////////////////////////////////
reg           mem_wresp;
reg           mem_rvld ;
reg   [31:0]  mem_rdata;

wire          tcm_wen  ;
wire          tcm_ren  ;
reg           tcm_wen_r;
reg   [31:0]  tcm_waddr;
reg   [31:0]  tcm_wdata;
reg   [ 3:0]  tcm_wmask;
reg           tcm_ren_r;
reg   [31:0]  tcm_raddr;
wire  [31:0]  tcm_rdata;
wire          tcm_rvld ;

wire          apb_wen;
wire          apb_ren;
reg   [ 1:0]  apb_state  ; // synthesis keep
reg           apb_psel   ; // synthesis keep
reg           apb_penable; // synthesis keep
reg           apb_pwrite ; // synthesis keep
reg   [31:0]  apb_paddr  ; // synthesis keep
reg   [31:0]  apb_pwdata ; // synthesis keep
reg   [ 3:0]  apb_pwmask ; // synthesis keep
reg   [31:0]  apb_prdata ; // synthesis keep
wire          apb_pready ; // synthesis keep
reg           apb_wdone  ; // synthesis keep
reg           apb_rdone  ; // synthesis keep
wire          apb_done   ; // synthesis keep

///////////////////////////////////////////////////////////////////////////////////////////////////
// ACCESS MUX
///////////////////////////////////////////////////////////////////////////////////////////////////
assign tcm_wen = (i_mem_waddr[31] == 1'b0) ? i_mem_wen : 1'b0; 
assign tcm_ren = (i_mem_raddr[31] == 1'b0) ? i_mem_ren : 1'b0; 

assign apb_wen = (i_mem_waddr[31] == 1'b1) ? i_mem_wen : 1'b0; 
assign apb_ren = (i_mem_raddr[31] == 1'b1) ? i_mem_ren : 1'b0; 

///////////////////////////////////////////////////////////////////////////////////////////////////
// TCM Timing Control
///////////////////////////////////////////////////////////////////////////////////////////////////
always @ (posedge i_clk or posedge i_rst)
begin
    if (i_rst == 1'b1) begin
        tcm_wen_r <=  1'b0;
        tcm_waddr <= 32'h0;
        tcm_wdata <= 32'h0;
        tcm_wmask <=  4'h0;
    end else if (tcm_wen) begin
        tcm_wen_r <= 1'b1;
        tcm_waddr <= i_mem_waddr;
        tcm_wdata <= i_mem_wdata;
        tcm_wmask <= i_mem_wmask;
    end else begin
        tcm_wen_r <= 1'b0;
    end
end

always @ (posedge i_clk or posedge i_rst)
begin
    if (i_rst == 1'b1) begin
        tcm_ren_r <=  1'b0;
        tcm_raddr <= 32'h0;
    end else if (tcm_ren) begin
        tcm_ren_r <= 1'b1;
        tcm_raddr <= i_mem_raddr;
    end else begin
        tcm_ren_r <= 1'b0;
    end
end


///////////////////////////////////////////////////////////////////////////////////////////////////
// APB Timing Control
///////////////////////////////////////////////////////////////////////////////////////////////////
// FSM
always @ (posedge i_clk or posedge i_rst)
begin
    if (i_rst == 1'b1)
        apb_state <= S_IDLE;
    else begin
        case (apb_state)
            S_IDLE   : apb_state <= (apb_wen || apb_ren) ? S_SETUP : S_IDLE;
            S_SETUP  : apb_state <= S_ACCESS; 
            S_ACCESS : apb_state <= apb_done ? ((apb_wen || apb_ren) ? S_SETUP : S_IDLE) : S_ACCESS;
            default  : apb_state <= S_IDLE;
        endcase
    end
end

// apb_psel
always @ (posedge i_clk or posedge i_rst)
begin
    if (i_rst == 1'b1)
        apb_psel <= 1'b0;
    else
        apb_psel <= (apb_state == S_SETUP) ? 1'b1 : apb_done ? 1'b0 : apb_psel;
end

// apb_penable
always @ (posedge i_clk or posedge i_rst)
begin
    if (i_rst == 1'b1)
        apb_penable <= 1'b0;
    else
//      apb_penable <= (apb_state == S_ACCESS) ? 1'b1 : apb_done ? 1'b0 : apb_penable;
        apb_penable <= (apb_state == S_ACCESS) ? 1'b1 : 1'b0;
end

// apb_pwrite
always @ (posedge i_clk or posedge i_rst)
begin
    if (i_rst == 1'b1)
        apb_pwrite <= 1'b0;
    else if (apb_wen == 1'b1)
        apb_pwrite <= 1'b1;
    else if (apb_ren == 1'b1)
        apb_pwrite <= 1'b0;
end

// apb_paddr
always @ (posedge i_clk or posedge i_rst)
begin
    if (i_rst == 1'b1)
        apb_paddr <= 32'h0;
    else if (apb_wen == 1'b1)
        apb_paddr <= i_mem_waddr;
    else if (apb_ren == 1'b1)
        apb_paddr <= i_mem_raddr;
end

// apb_pwdata
always @ (posedge i_clk or posedge i_rst)
begin
    if (i_rst == 1'b1) begin
        apb_pwdata <= 32'h0;
        apb_pwmask <= 4'b1111;
    end else if (apb_wen == 1'b1) begin
        apb_pwdata <= i_mem_wdata;
        apb_pwmask <= i_mem_wmask;
    end
end

// apb_done
assign apb_done = apb_psel & apb_penable & apb_pready;

always @ (posedge i_clk or posedge i_rst)
begin
    if (i_rst == 1'b1) begin
        apb_wdone <= 1'b0;
        apb_rdone <= 1'b0;
    end else begin
        apb_wdone <= apb_done & (apb_pwrite == 1'b1);
        apb_rdone <= apb_done & (apb_pwrite == 1'b0);
    end
end

always @ (posedge i_clk or posedge i_rst)
begin
    if (i_rst == 1'b1) begin
        apb_prdata <= 32'h0;
    end else if (apb_done & (apb_pwrite == 1'b0)) begin
        apb_prdata <= i_apb_prdata;
    end
end

///////////////////////////////////////////////////////////////////////////////////////////////////
// Write & Read Response
///////////////////////////////////////////////////////////////////////////////////////////////////
always @ (posedge i_clk or posedge i_rst)
begin
    if (i_rst == 1'b1)
        mem_wresp <= 1'b0;
    else
        mem_wresp <= apb_wdone | tcm_wen_r;
end

always @ (posedge i_clk or posedge i_rst)
begin
    if (i_rst == 1'b1) begin
        mem_rvld  <=  1'b0;
        mem_rdata <= 32'h0;
    end else begin
        mem_rvld  <= apb_rdone ? 1'b1       : tcm_rvld ? 1'b1      : 1'b0;
        mem_rdata <= apb_rdone ? apb_prdata : tcm_rvld ? tcm_rdata : mem_rdata;
    end
end


///////////////////////////////////////////////////////////////////////////////////////////////////
// IN/OUT control
///////////////////////////////////////////////////////////////////////////////////////////////////
// APB
assign apb_pready    = i_apb_pready;

assign o_apb_psel    = apb_psel   ; 
assign o_apb_penable = apb_penable; 
assign o_apb_pwrite  = apb_pwrite ;
assign o_apb_paddr   ={apb_paddr[31:2], 2'b00};
assign o_apb_pwdata  = apb_pwdata ;

// TCM
assign tcm_rvld      = i_tcm_rvld;
assign tcm_rdata     = i_tcm_rdata;

assign o_tcm_wen     = tcm_wen_r; 
assign o_tcm_waddr   ={tcm_waddr[31:2], 2'b00};
assign o_tcm_wdata   = tcm_wdata;
assign o_tcm_wmask   = tcm_wmask;

assign o_tcm_ren     = tcm_ren_r; 
assign o_tcm_raddr   ={tcm_raddr[31:2], 2'b00};

// MEM
assign o_mem_wresp   = mem_wresp;
assign o_mem_rvld    = mem_rvld ;
assign o_mem_rdata   = mem_rdata;


///////////////////////////////////////////////////////////////////////////////////////////////////
// END
///////////////////////////////////////////////////////////////////////////////////////////////////
endmodule
