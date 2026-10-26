
///////////////////////////////////////////////////////////////////////////////////////////////////
// mcu_apb_uart.v
///////////////////////////////////////////////////////////////////////////////////////////////////
`timescale 1ps / 1ps

module usr_mcu_apb_uart #(
    parameter CLK_FREQ = 100_000_000
)(
    input         i_clk        ,
    input         i_rst        ,

    input         i_apb_psel   ,
    input         i_apb_penable,
    input         i_apb_pwrite ,
    input  [ 7:0] i_apb_paddr  ,
    input  [31:0] i_apb_pwdata ,
    output [31:0] o_apb_prdata ,
    output        o_apb_pready ,

    input         i_uart_rxd   ,
    output        o_uart_txd
);

///////////////////////////////////////////////////////////////////////////////////////////////////
// Local Parameters
///////////////////////////////////////////////////////////////////////////////////////////////////
localparam BAUD_RATE = 115_200;

///////////////////////////////////////////////////////////////////////////////////////////////////
// Internal Signals
///////////////////////////////////////////////////////////////////////////////////////////////////
// 0x00 : CR - RW
//        [0] : tx fifo reset
//        [1] : rx fifo reset
// 0x04 : SR - RO
//        [0] : tx_fifo_empty
//        [1] : tx_fifo_full
//        [2] : rx_fifo_empty
//        [3] : rx_fifo_full
// 0x08 : TX_FIFO - WO
// 0x0C : RX_FIFO - RO

reg  [31:0] reg_00;
reg  [31:0] reg_04;
reg  [31:0] reg_08;
wire [31:0] reg_0c;

reg         apb_pready;
reg  [31:0] apb_prdata;
wire        apb_wen;
wire        apb_ren;
wire        apb_rld;

reg         tx_en;
reg         rx_en;

wire        tx_fifo_rst  ;
wire        tx_fifo_empty;
wire        tx_fifo_full ;
reg         tx_fifo_wen  ;
reg  [ 7:0] tx_fifo_wdata;
wire        tx_fifo_ren  ;
wire [ 7:0] tx_fifo_rdata;

wire        rx_fifo_rst  ;
wire        rx_fifo_empty;
wire        rx_fifo_full ;
wire        rx_fifo_wen  ;
wire [ 7:0] rx_fifo_wdata;
wire        rx_fifo_ren  ;
wire [ 7:0] rx_fifo_rdata;

///////////////////////////////////////////////////////////////////////////////////////////////////
// APB Timing
///////////////////////////////////////////////////////////////////////////////////////////////////
always @ (posedge i_clk or posedge i_rst)
begin
    if (i_rst == 1'b1)
        apb_pready <= 1'b0;
    else if (i_apb_psel && (i_apb_penable == 1'b0))
        apb_pready <= 1'b0;
//  else if (i_apb_psel && (i_apb_penable == 1'b1) && (i_apb_pwrite == 1'b1))
    else if (i_apb_psel && i_apb_penable)
        apb_pready <= 1'b1;
//  else if (i_apb_psel && (i_apb_penable == 1'b1) && (i_apb_pwrite == 1'b0))
//      apb_pready <= apb_ren;
    else
        apb_pready <= 1'b1;
end

assign apb_wen = i_apb_psel & i_apb_penable & (i_apb_pwrite == 1'b1) & apb_pready;
assign apb_ren = i_apb_psel & i_apb_penable & (i_apb_pwrite == 1'b0) & apb_pready;

assign apb_rld = i_apb_psel & i_apb_penable & (i_apb_pwrite == 1'b0) & (apb_pready == 1'b0);

// APB_Write
always @ (posedge i_clk or posedge i_rst)
begin
    if (i_rst == 1'b1) begin
        reg_00 <= 32'h0;
        reg_08 <= 32'h0;
    end else if (apb_wen) begin
        case (i_apb_paddr[7:0])
            8'h00   : reg_00 <= i_apb_pwdata;
            8'h08   : reg_08 <= i_apb_pwdata;
            default : begin
                reg_00 <= reg_00;
                reg_08 <= reg_08;
            end
        endcase
    end
end

always @ (posedge i_clk or posedge i_rst)
begin
    if (i_rst == 1'b1) begin
        apb_prdata <= 32'h0;
    end else if (apb_rld) begin
        case (i_apb_paddr[7:0])
            8'h00   : apb_prdata <= reg_00;
            8'h04   : apb_prdata <= reg_04;
            8'h08   : apb_prdata <= reg_08;
            8'h0c   : apb_prdata <= reg_0c;
            default : apb_prdata <= 32'hdeadbeef;
        endcase
    end
end

assign o_apb_pready = apb_pready;
assign o_apb_prdata = apb_prdata;

///////////////////////////////////////////////////////////////////////////////////////////////////
// Interaction between Register and UART Ctrl
///////////////////////////////////////////////////////////////////////////////////////////////////
assign tx_fifo_rst = reg_00[0];
assign rx_fifo_rst = reg_00[1];

always @ (posedge i_clk or posedge i_rst)
begin
    if (i_rst == 1'b1) begin
        tx_en <= 1'b0;
        rx_en <= 1'b0;
    end else begin
        tx_en <= apb_wen && (i_apb_paddr[7:0] == 8'h08);
        rx_en <= apb_ren && (i_apb_paddr[7:0] == 8'h0c);
    end
end

always @ (posedge i_clk or posedge i_rst)
begin
    if (i_rst == 1'b1) begin
        tx_fifo_wen   <= 1'b0;
        tx_fifo_wdata <= 8'h0;
    end else if (tx_en) begin
        tx_fifo_wen   <= 1'b1;
        tx_fifo_wdata <= reg_08[7:0];
    end else begin
        tx_fifo_wen   <= 1'b0;
    end
end

assign rx_fifo_ren = rx_en;

always @ (posedge i_clk or posedge i_rst)
begin
    if (i_rst == 1'b1) begin
        reg_04 <= 32'h0;
//      reg_0c <= 32'h0;
    end else begin
        reg_04 <= {28'h0, rx_fifo_full, rx_fifo_empty, tx_fifo_full, tx_fifo_empty};
//      reg_0c <= rx_fifo_ren ? {24'h0, rx_fifo_rdata} : reg_0c;
    end
end

assign reg_0c = {24'h0, rx_fifo_rdata};

///////////////////////////////////////////////////////////////////////////////////////////////////
// UART Components
///////////////////////////////////////////////////////////////////////////////////////////////////
usr_mcu_uart_fifo u_tx_fifo (
    .clk          ( i_clk               ),
    .rst          ( i_rst | tx_fifo_rst ),
    .fifo_empty   ( tx_fifo_empty       ),
    .fifo_full    ( tx_fifo_full        ),
    .fifo_wr_en   ( tx_fifo_wen         ),
    .fifo_wr_data ( tx_fifo_wdata       ),
    .fifo_rd_en   ( tx_fifo_ren         ),
    .fifo_rd_data ( tx_fifo_rdata       )
);

usr_mcu_uart_fifo u_rx_fifo (
    .clk          ( i_clk               ),
    .rst          ( i_rst | rx_fifo_rst ),
    .fifo_empty   ( rx_fifo_empty       ),
    .fifo_full    ( rx_fifo_full        ),
    .fifo_wr_en   ( rx_fifo_wen         ),
    .fifo_wr_data ( rx_fifo_wdata       ),
    .fifo_rd_en   ( rx_fifo_ren         ),
    .fifo_rd_data ( rx_fifo_rdata       )
);

// UART TX
usr_mcu_uart_tx #(
    .BAUD_RATE ( BAUD_RATE ),
    .CLK_FREQ  ( CLK_FREQ  )
) u_uart_tx (
    .i_clk     ( i_clk         ),
    .i_rst     ( i_rst         ),
    .i_tx_req  (~tx_fifo_empty ),
    .i_tx_data ( tx_fifo_rdata ),
    .o_tx_ack  ( tx_fifo_ren   ),
    .o_txd     ( o_uart_txd    )
);

// UART RX 
usr_mcu_uart_rx #(
    .BAUD_RATE ( BAUD_RATE ),
    .CLK_FREQ  ( CLK_FREQ  )
) u_uart_rx (
    .i_clk     ( i_clk         ),
    .i_rst     ( i_rst         ),
    .i_rxd     ( i_uart_rxd    ),
    .o_rx_vld  ( rx_fifo_wen   ),
    .o_rx_data ( rx_fifo_wdata ),
    .o_err     (               )
);

endmodule


///////////////////////////////////////////////////////////////////////////////////////////////////
// mcu_uart_fifo.v
///////////////////////////////////////////////////////////////////////////////////////////////////
//`timescale 1ps / 1ps
module usr_mcu_uart_fifo (
    input        clk         ,
    input        rst         ,

    output       fifo_empty  ,
    output       fifo_full   ,

    input        fifo_wr_en  ,
    input  [7:0] fifo_wr_data,

    input        fifo_rd_en  ,
    output [7:0] fifo_rd_data
);
///////////////////////////////////////////////////////////////////////////////////////////////////
// Internal Signals
///////////////////////////////////////////////////////////////////////////////////////////////////
reg  [7:0] fifo_data[0:15]; // synthesis ram_style = dram

reg  [3:0] fifo_wr_addr;
reg  [3:0] fifo_rd_addr;

wire [4:0] fifo_gap;

assign fifo_empty = (fifo_gap == 5'h0) ? 1'b1 : 1'b0 ;
assign fifo_full  = (fifo_gap == 5'hF) ? 1'b1 : 1'b0 ;

///////////////////////////////////////////////////////////////////////////////////////////////////
// Main Function
///////////////////////////////////////////////////////////////////////////////////////////////////
// FIFO Write Data
always @ (posedge clk)
begin
    if (fifo_wr_en) begin
        fifo_data[fifo_wr_addr] <= fifo_wr_data;
    end
end

// FIFO Write Addr
always @ (posedge clk or posedge rst)
begin
    if (rst == 1'b1) begin
        fifo_wr_addr <= 4'h0 ;
    end else if (fifo_wr_en) begin
        if (fifo_gap == 5'h0F)
            fifo_wr_addr <= fifo_wr_addr ;
        else if (fifo_wr_addr == 4'hF) begin
            fifo_wr_addr <= 4'h0 ;
        end else begin
            fifo_wr_addr <= fifo_wr_addr + 1'b1 ;
        end
    end else begin
        fifo_wr_addr <= fifo_wr_addr ;
    end
end

// FIFO Read Addr
always @ (posedge clk or posedge rst)
begin
    if (rst == 1'b1) begin
        fifo_rd_addr <= 4'h0 ;
    end else if (fifo_rd_en) begin
        if (fifo_gap == 5'h00) begin
            fifo_rd_addr <= fifo_rd_addr ;
        end else if (fifo_rd_addr == 4'hF) begin
            fifo_rd_addr <= 4'h0 ;
        end else begin
            fifo_rd_addr <= fifo_rd_addr + 1'b1 ;
        end
    end
end

assign fifo_rd_data = fifo_data[fifo_rd_addr[3:0]] ;

assign fifo_gap = (fifo_wr_addr >= fifo_rd_addr) ? (fifo_wr_addr - fifo_rd_addr) : ({1'b1, fifo_wr_addr} - fifo_rd_addr);


endmodule


///////////////////////////////////////////////////////////////////////////////////////////////////
// mcu_uart_tx.v
///////////////////////////////////////////////////////////////////////////////////////////////////
//`timescale 1ps/1ps
module usr_mcu_uart_tx #(
    parameter BAUD_RATE = 115_200,
    parameter CLK_FREQ  = 100_000_000
)(
    input        i_clk    ,
    input        i_rst    ,
    input        i_tx_req ,
    input  [7:0] i_tx_data,
    output       o_tx_ack ,
    output       o_txd
);
///////////////////////////////////////////////////////////////////////////////////////////////////
// Internal Signals
///////////////////////////////////////////////////////////////////////////////////////////////////
wire  baud_x16_en;

///////////////////////////////////////////////////////////////////////////////////////////////////
// Internal Signals
///////////////////////////////////////////////////////////////////////////////////////////////////
usr_mcu_uart_baud_gen #(
    .CLK_FREQ   ( CLK_FREQ   ),
    .BAUD_RATE  ( BAUD_RATE  )
) u_baud_gen    (
    .i_clk      ( i_clk       ),
    .i_rst      ( i_rst       ),
    .o_x16_en   ( baud_x16_en )
);

usr_mcu_uart_tx_ctl u_tx_ctl (
    .i_clk      ( i_clk       ),
    .i_rst      ( i_rst       ),
    .i_x16_en   ( baud_x16_en ),
    .i_tx_req   ( i_tx_req    ),
    .i_tx_data  ( i_tx_data   ),
    .o_tx_ack   ( o_tx_ack    ),
    .o_txd      ( o_txd       )
);

endmodule


///////////////////////////////////////////////////////////////////////////////////////////////////
// mcu_uart_rx.v
///////////////////////////////////////////////////////////////////////////////////////////////////
//`timescale 1ps/1ps
module usr_mcu_uart_rx #(
    parameter CLK_FREQ  = 100_000_000,
    parameter BAUD_RATE = 115_200
)(
    input          i_clk    ,
    input          i_rst    ,

    input          i_rxd    ,

    output  [7:0]  o_rx_data,
    output         o_rx_vld ,
    output         o_err
);

///////////////////////////////////////////////////////////////////////////////////////////////////
// Local Parameter
///////////////////////////////////////////////////////////////////////////////////////////////////


///////////////////////////////////////////////////////////////////////////////////////////////////
// Internal Signals
///////////////////////////////////////////////////////////////////////////////////////////////////
reg        rxd_sync;
wire       baud_x16_en;
wire       rx_vld   ;

///////////////////////////////////////////////////////////////////////////////////////////////////
// Main Function
///////////////////////////////////////////////////////////////////////////////////////////////////
always @ (posedge i_clk or posedge i_rst)
begin
    if (i_rst == 1'b1)
        rxd_sync <= 1'b1;
    else
        rxd_sync <= i_rxd;
end

usr_mcu_uart_baud_gen #(
    .BAUD_RATE  ( BAUD_RATE   ),
    .CLK_FREQ   ( CLK_FREQ    )
) u_baud_gen    (
    .i_clk      ( i_clk       ),
    .i_rst      ( i_rst       ),
    .o_x16_en   ( baud_x16_en )
);

usr_mcu_uart_rx_ctl u_rx_ctl (
    .i_clk      ( i_clk       ),
    .i_rst      ( i_rst       ),

    .i_x16_en   ( baud_x16_en ),
    .i_rxd      ( rxd_sync    ),

    .o_rx_vld   ( o_rx_vld    ),
    .o_rx_data  ( o_rx_data   ),
    .o_err      ( o_err       )
);

endmodule


///////////////////////////////////////////////////////////////////////////////////////////////////
// mcu_uart_tx_ctl.v
///////////////////////////////////////////////////////////////////////////////////////////////////
//`timescale 1ps/1ps
module usr_mcu_uart_tx_ctl (
    input          i_clk     ,
    input          i_rst     ,

    input          i_x16_en  ,

    input          i_tx_req  ,
    input   [7:0]  i_tx_data ,
    output         o_tx_ack  ,

    output         o_txd
);

///////////////////////////////////////////////////////////////////////////////////////////////////
// Local Parameter
///////////////////////////////////////////////////////////////////////////////////////////////////
// FSM
localparam IDLE  = 2'b00;
localparam START = 2'b01;
localparam DATA  = 2'b10;
localparam STOP  = 2'b11;

///////////////////////////////////////////////////////////////////////////////////////////////////
// Internal Signals
///////////////////////////////////////////////////////////////////////////////////////////////////
reg  [1:0]  state;

reg  [3:0]  sample_cnt;
wire        sample_done;

reg  [2:0]  bit_cnt;
wire        bit_done;

reg  [7:0]  tx_data;
reg         txd_r;

///////////////////////////////////////////////////////////////////////////////////////////////////
// Main Function
///////////////////////////////////////////////////////////////////////////////////////////////////
// state machine
always @ (posedge i_clk or posedge i_rst)
begin
    if (i_rst == 1'b1) begin
        state         <= IDLE;
    end else if (i_x16_en) begin
        case (state)
            IDLE : state <= (i_tx_req == 1'b1)                  ? START : IDLE ;
            START: state <= (sample_done == 1'b1)               ? DATA  : START; 
            DATA : state <= (sample_done && bit_done)           ? STOP  : DATA ;
            STOP : state <= (sample_done && (i_tx_req == 1'b0)) ? IDLE  :
                            (sample_done && (i_tx_req == 1'b1)) ? START : STOP ;
        endcase
    end
end

assign o_tx_ack = i_x16_en & sample_done & (state == START);

// Sample Counter
always @ (posedge i_clk or posedge i_rst)
begin
    if (i_rst == 1'b1) begin
        sample_cnt <= 4'h0;
    end else if (i_x16_en) begin
        if ((state == IDLE) && (i_tx_req == 1'b1))
            sample_cnt <= 4'h0;
        else
            sample_cnt <= sample_cnt + 1'b1;
    end
end

assign sample_done = (sample_cnt == 4'hf);

// Bit Counter 
always @ (posedge i_clk or posedge i_rst)
begin
    if (i_rst == 1'b1) begin
        bit_cnt <= 3'b0;
    end else if (i_x16_en && sample_done) begin
        bit_cnt <= (state == START) ? 3'h0 :
                   (state == DATA ) ? bit_cnt + 1'b1 : bit_cnt;
    end
end

assign bit_done = (bit_cnt == 3'd7);

// Generate the output
always @ (posedge i_clk or posedge i_rst)
begin
    if (i_rst == 1'b1) begin
        tx_data <= 8'h0;
    end else if (o_tx_ack) begin
        tx_data <= i_tx_data;
    end
end

always @ (posedge i_clk or posedge i_rst)
begin
    if (i_rst == 1'b1) begin
        txd_r <= 1'b1;
    end else if (i_x16_en) begin
        case (state)
            IDLE : txd_r <= 1'b1;
            START: txd_r <= 1'b0;
            DATA : txd_r <= tx_data[bit_cnt];
            STOP : txd_r <= 1'b1;
        endcase
    end
end

assign o_txd = txd_r;

endmodule


///////////////////////////////////////////////////////////////////////////////////////////////////
// mcu_uart_rx_ctl.v
///////////////////////////////////////////////////////////////////////////////////////////////////
//`timescale 1ps/1ps
module usr_mcu_uart_rx_ctl (
    input             i_clk   ,
    input             i_rst   ,

    input             i_x16_en,  
    input             i_rxd   ,
  
    output  reg [7:0] o_rx_data,
    output  reg       o_rx_vld ,
    output            o_err
);

///////////////////////////////////////////////////////////////////////////////////////////////////
// Local Parameter
///////////////////////////////////////////////////////////////////////////////////////////////////
// FSM
localparam  IDLE  = 2'b00;
localparam  START = 2'b01;
localparam  DATA  = 2'b10;
localparam  STOP  = 2'b11;

///////////////////////////////////////////////////////////////////////////////////////////////////
// Internal Signals
///////////////////////////////////////////////////////////////////////////////////////////////////
reg          rx_vld ;
reg [7:0]    rx_data;
reg          frm_err;

reg [1:0]    state;

reg [3:0]    sample_cnt;
wire         sample_done;

reg [2:0]    bit_cnt;
wire         bit_done;

///////////////////////////////////////////////////////////////////////////////////////////////////
// Main Function
///////////////////////////////////////////////////////////////////////////////////////////////////
// FSM
always @ (posedge i_clk or posedge i_rst)
begin
    if (i_rst == 1'b1) begin
        state <= IDLE;
    end else if (i_x16_en) begin
        case (state)
            IDLE : state <= (i_rxd == 1'b0) ? START : IDLE;
            START: state <= (sample_done && (i_rxd == 1'b0)) ? DATA :
                            (sample_done && (i_rxd == 1'b1)) ? IDLE : START;
            DATA : state <= (sample_done && bit_done) ? STOP : DATA;
            STOP : state <= sample_done ? IDLE : STOP;
        endcase
    end
end

// Sample Cnt Gen
always @ (posedge i_clk or posedge i_rst)
begin
    if (i_rst == 1'b1) begin
        sample_cnt <= 4'd0;
    end else if (i_x16_en) begin
        sample_cnt <= ((state == IDLE ) && (i_rxd == 1'b0)) ? 4'h8 :
                      (sample_done && (state == START) && (i_rxd == 1'b0)) ? 4'h0 :
                      (sample_done && (state == DATA ))                    ? 4'h0 : sample_cnt + 1'b1;
    end
end

assign sample_done = (sample_cnt == 4'hf);

// BIT Counter 
always @ (posedge i_clk or posedge i_rst)
begin
    if (i_rst == 1'b1) begin
        bit_cnt    <= 3'b0;
    end else begin
        bit_cnt <= (i_x16_en && sample_done && (state == START)) ? 3'h0 :
                   (i_x16_en && sample_done && (state == DATA )) ? bit_cnt + 1'b1 : bit_cnt;
    end
end

assign bit_done = (bit_cnt == 3'h7);

// RX Data Capture 
always @ (posedge i_clk or posedge i_rst)
begin
    if (i_rst == 1'b1) begin
        rx_vld  <= 1'b0;
        rx_data <= 8'b0000_0000;
    end else begin
        if (i_x16_en && sample_done) begin
            if (state == DATA) begin
                rx_vld           <= bit_done;
                rx_data[bit_cnt] <= i_rxd;
            end else begin
                rx_vld <= 1'b0;
            end
        end
    end
end

// Frame Error Detect
always @ (posedge i_clk or posedge i_rst)
begin
    if (i_rst == 1'b1) begin
        frm_err <= 1'b0;
    end else if (i_x16_en) begin
        if ((state == STOP) && sample_done && (i_rxd == 1'b0)) begin
            frm_err <= 1'b1;
        end else begin
            frm_err <= 1'b0;
        end
    end
end

always @ (posedge i_clk or posedge i_rst)
begin
    if (i_rst == 1'b1) begin
        o_rx_vld  <= 1'b0;
        o_rx_data <= 8'h0;
    end else if (i_x16_en && sample_done && rx_vld) begin
        o_rx_vld  <= rx_vld ;
        o_rx_data <= rx_data;
    end else begin
        o_rx_vld  <= 1'b0;
    end
end

assign o_err = frm_err;

endmodule

///////////////////////////////////////////////////////////////////////////////////////////////////
// mcu_uart_baud_gen.v
///////////////////////////////////////////////////////////////////////////////////////////////////
//`timescale 1ps/1ps
module usr_mcu_uart_baud_gen #(
    CLK_FREQ  = 100_000_000,
    BAUD_RATE = 115_200
)(
    input   i_clk,
    input   i_rst,
    output  o_x16_en
);

///////////////////////////////////////////////////////////////////////////////////////////////////
// Local Parameter
///////////////////////////////////////////////////////////////////////////////////////////////////
localparam integer MAX_CNT = CLK_FREQ/(BAUD_RATE*16);

///////////////////////////////////////////////////////////////////////////////////////////////////
// Internal Signals
///////////////////////////////////////////////////////////////////////////////////////////////////
reg  [31:0] cnt_r;
reg         baud_x16_en;

///////////////////////////////////////////////////////////////////////////////////////////////////
// Main Function
///////////////////////////////////////////////////////////////////////////////////////////////////
always @ (posedge i_clk or posedge i_rst)
begin
    if (i_rst == 1'b1) begin
        cnt_r <= 32'h0;
    end else if (cnt_r == MAX_CNT) begin
        cnt_r <= 32'h0;
    end else begin
        cnt_r <= cnt_r + 1'b1;
    end
end

always @ (posedge i_clk or posedge i_rst)
begin
    if (i_rst == 1'b1) begin
        baud_x16_en <= 1'b0;
    end else begin
        baud_x16_en <= (cnt_r == MAX_CNT-1) ? 1'b1 : 1'b0;
    end
end

assign o_x16_en = baud_x16_en;

endmodule

