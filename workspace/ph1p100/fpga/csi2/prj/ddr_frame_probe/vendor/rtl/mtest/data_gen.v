`timescale 1ps/1ps

// pat_sel = 4'b0000 : PRBS
// pat_sel = 4'b0001 : Counter
// pat_sel = 4'b0010 : 64'h0000_0000_0000_0000
// pat_sel = 4'b0011 : 64'hffff_ffff_ffff_ffff
// pat_sel = 4'b0100 : 64'hff00_ff00_ff00_ff00
// pat_sel = 4'b0101 : 64'h00ff_00ff_00ff_00ff
// pat_sel = 4'b0110 : User Seed
// pat_sel = 4'b1000 : Same Pattern

module data_gen (
    input           clk     ,
    input           rst_n   ,
    input   [ 3:0]  pat_sel ,
    input   [31:0]  seed0   ,
    input   [31:0]  seed1   ,
    input           data_en ,
    output  [63:0]  data
);


///////////////////////////////////////////////////////////////////////////////////////////////////
//
///////////////////////////////////////////////////////////////////////////////////////////////////
wire        fifo_full  ;
wire        fifo_empty ;
reg         fifo_wvld  ;
wire        fifo_wen   ;
wire        fifo_ren   ;
wire [63:0] fifo_wdata ;
wire [63:0] fifo_rdata ;

wire [63:0] data_prbs;
wire [63:0] data_cnt ;
wire [63:0] data_0    = 64'h0000_0000_0000_0000;
wire [63:0] data_1    = 64'hffff_ffff_ffff_ffff;
wire [63:0] data_clk0 = 64'hff00_ff00_ff00_ff00;
wire [63:0] data_clk1 = 64'h00ff_00ff_00ff_00ff;
wire [63:0] data_seed = {seed1, seed0};
wire [63:0] data_same = {8{data_prbs[7:0]}};

// prbs
/*
cust_prbs_gen #(
    .U_DLY    ( 0  ),
    .DAT_SIZE ( 64 )
)(
    .clock    ( clk       ),
    .reset    (~rst_n     ),
    .enable   ( fifo_wen  ), 
    .prbs_out ( data_prbs )
);
*/
prbs_gen #(
    .MODE  ( "PRBS15" ),
    .DW    ( 64       )
) u_prbs_gen (
    .i_rst  ( ~rst_n     ) ,
    .i_clk  ( clk        ) ,
    .i_en   ( fifo_wen   ) ,
    .o_data ( data_prbs  )
);
// counter
reg  [7:0] data_p0;
wire [7:0] data_p1;
wire [7:0] data_p2;
wire [7:0] data_p3;
wire [7:0] data_p4;
wire [7:0] data_p5;
wire [7:0] data_p6;
wire [7:0] data_p7;

always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0)
        data_p0 <= 8'h00;
    else 
        data_p0 <= (fifo_wen == 1'b1) ? (data_p0 + 4'h8) : data_p0; 
end

assign data_p1 = data_p0 + 4'h1;
assign data_p2 = data_p0 + 4'h2;
assign data_p3 = data_p0 + 4'h3;
assign data_p4 = data_p0 + 4'h4;
assign data_p5 = data_p0 + 4'h5;
assign data_p6 = data_p0 + 4'h6;
assign data_p7 = data_p0 + 4'h7;

assign data_cnt = {data_p7, data_p6, data_p5, data_p4, data_p3, data_p2, data_p1, data_p0};

// data fifo
fifo_dram_sync #(
    .DW       ( 64 ),
    .AW       ( 4  )
) u_data_fifo (
    .clk      ( clk         ),
    .rst      (~rst_n       ),
    .wren     ( fifo_wen    ),
    .rden     ( fifo_ren    ),
    .din      ( fifo_wdata  ),
    .dout     ( fifo_rdata  ),
    .full     ( fifo_full   ),
    .empty    ( fifo_empty  )
);

always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0)
        fifo_wvld <= 1'b0;
    else
        fifo_wvld <= (fifo_full == 1'b1) ? 1'b0 : 1'b1;
end

assign fifo_wen = (fifo_wvld == 1'b1) && (fifo_full == 1'b0);

assign fifo_wdata = (pat_sel == 4'b0000) ? data_prbs :
                    (pat_sel == 4'b0001) ? data_cnt  :
                    (pat_sel == 4'b0010) ? data_0    :
                    (pat_sel == 4'b0011) ? data_1    :
                    (pat_sel == 4'b0100) ? data_clk0 :
                    (pat_sel == 4'b0101) ? data_clk1 :
                    (pat_sel == 4'b0110) ? data_seed :
                    (pat_sel == 4'b1000) ? data_same : data_cnt;

assign fifo_ren = data_en   ;
assign data     = fifo_rdata;

endmodule

