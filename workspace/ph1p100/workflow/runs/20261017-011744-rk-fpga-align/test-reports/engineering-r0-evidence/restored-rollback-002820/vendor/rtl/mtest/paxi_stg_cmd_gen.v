
`timescale 1ps/1ps

module paxi_stg_cmd_gen #(
    parameter BG_WIDTH       = 0 ,
    parameter BA_WIDTH       = 3 ,
    parameter ROW_WIDTH      = 10,
    parameter COL_WIDTH      = 10,
    parameter APP_ADDR_WIDTH = BG_WIDTH + BA_WIDTH + ROW_WIDTH + COL_WIDTH
)(
    input                               clk,
    input                               rst,

    input                               ddrphy_rdy,

    input                               start,

    input                               cmd_rdy ,
    output                              cmd_en  ,
    output       [               3 : 0] cmd_type,
    output       [APP_ADDR_WIDTH-1 : 0] cmd_addr,
    output  reg                         cmd_done,

    input                               rd_vld,
    input                               wr_rdy,
    output                              wr_en
);

///////////////////////////////////////////////////////////////////////////////////////////////////
//  Local Parameter
///////////////////////////////////////////////////////////////////////////////////////////////////

// Instruction Encoding
localparam  [3:0] CMD_IDLE = 4'b0000;
localparam  [3:0] CMD_WR   = 4'b1100;
localparam  [3:0] CMD_RD   = 4'b1101;


localparam NUM_TRANS = 256;

///////////////////////////////////////////////////////////////////////////////////////////////////
//  Internal Signals
///////////////////////////////////////////////////////////////////////////////////////////////////
reg   [               3 : 0]  state;
reg                           ddrphy_rdy_r;

wire                          rd_en   ;
reg   [              31 : 0]  cmd_cnt ; 
reg   [              31 : 0]  wr_cnt  ; 
reg   [              31 : 0]  rd_cnt  ; 
reg   [APP_ADDR_WIDTH-1 : 0]  wr_addr ;
reg   [APP_ADDR_WIDTH-1 : 0]  rd_addr ;


///////////////////////////////////////////////////////////////////////////////////////////////////
//  Main Function
///////////////////////////////////////////////////////////////////////////////////////////////////
always @ (posedge clk) begin
    ddrphy_rdy_r <=  ddrphy_rdy;
end

// FSM
always @ (posedge clk) begin
    if (rst == 1'b1) begin
        state <= CMD_IDLE;
    end else begin
        case (state)
            CMD_IDLE: state <= (start  == 1'b1) ? CMD_WR : CMD_IDLE;
            CMD_WR  : state <= (cmd_rdy && wr_rdy && (wr_cnt == NUM_TRANS-1)) ? CMD_RD   : CMD_WR;
            CMD_RD  : state <= (cmd_rdy && (rd_cnt == NUM_TRANS-1)) ? CMD_IDLE : CMD_RD;
            default : state <= CMD_IDLE;
        endcase
    end
end

// Write or Read Cmd Generation
assign wr_en  = (state == CMD_WR) & cmd_rdy & wr_rdy;
assign rd_en  = (state == CMD_RD) & cmd_rdy;

assign cmd_en   = wr_en | rd_en;
assign cmd_type = (state == CMD_WR) ? CMD_WR : (state == CMD_RD) ? CMD_RD : CMD_IDLE;

// Address Gen
always @ (posedge clk) begin
    if (rst == 1'b1)
        wr_addr <= {APP_ADDR_WIDTH{1'b0}};
    else if (wr_en)
        wr_addr <= wr_addr + 1'b1;
end

always @ (posedge clk) begin
    if (rst == 1'b1)
        rd_addr <= {APP_ADDR_WIDTH{1'b0}};
    else if (rd_en)
        rd_addr <= rd_addr + 1'b1;
end

assign cmd_addr = (state == CMD_WR) ? {wr_addr[APP_ADDR_WIDTH-3-1 : 0], 3'b000} :
                  (state == CMD_RD) ? {rd_addr[APP_ADDR_WIDTH-3-1 : 0], 3'b000} : {APP_ADDR_WIDTH{1'b0}};

// Command Counter
always @ (posedge clk)
begin
    if (rst == 1'b1) begin
        cmd_cnt <= 32'h0;
    end else if (state == CMD_IDLE) begin
        cmd_cnt <= 32'h0;
    end else if (state == CMD_WR) begin
        cmd_cnt <= (wr_en) ? cmd_cnt + 1'b1 : cmd_cnt;
    end else if (state == CMD_RD) begin
        cmd_cnt <= (rd_en) ? cmd_cnt + 1'b1 : cmd_cnt;
    end
end

// Write Counter
always @ (posedge clk)
begin
    if (rst == 1'b1) begin
        wr_cnt <= 32'h0;
    end else if (state == CMD_IDLE) begin
        wr_cnt <= 32'h0;
    end else if (wr_en & wr_rdy) begin
        wr_cnt <=  wr_cnt + 1'b1;
    end
end

// Read Counter
always @ (posedge clk)
begin
    if (rst == 1'b1) begin
        rd_cnt <= 32'h0;
    end else if ((state == CMD_IDLE) || (state == CMD_WR))begin
        rd_cnt <= 32'h0;
    end else if (state == CMD_RD) begin
        rd_cnt <= (cmd_en & cmd_rdy) ? rd_cnt + 1'b1 : rd_cnt;
    end
end

// Done flag after the first write-read finished
always @ (posedge clk)
begin
    if (rst == 1'b1)
         cmd_done <= 1'b0;
    else if (cmd_cnt == NUM_TRANS*2-1)
         cmd_done <= 1'b1;
end

endmodule
