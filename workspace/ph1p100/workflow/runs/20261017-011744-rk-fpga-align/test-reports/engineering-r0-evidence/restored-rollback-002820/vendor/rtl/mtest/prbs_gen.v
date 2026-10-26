
///////////////////////////////////////////////////////////////////////////////////////////////////
// module : PRBS Gen : ITU-T O.150
///////////////////////////////////////////////////////////////////////////////////////////////////

`timescale 1ps/1ps

module prbs_gen #(
    parameter MODE = "PRBS31",
    parameter DW   = 64
)(
    input               i_rst  ,
    input               i_clk  ,
    input               i_en   ,
    output reg [DW-1:0] o_data
);

///////////////////////////////////////////////////////////////////////////////////////////////////
// Local Parameter
///////////////////////////////////////////////////////////////////////////////////////////////////
localparam  LEN  = (MODE == "PRBS7" ) ? 7  :
                   (MODE == "PRBS9" ) ? 9  :
                   (MODE == "PRBS11") ? 11 :
                   (MODE == "PRBS15") ? 15 :
                   (MODE == "PRBS20") ? 20 :
                   (MODE == "PRBS23") ? 23 :
                   (MODE == "PRBS29") ? 29 :
                   (MODE == "PRBS31") ? 31 : 31;

localparam  TAP  = (MODE == "PRBS7" ) ? 6  :
                   (MODE == "PRBS9" ) ? 5  :
                   (MODE == "PRBS11") ? 9  :
                   (MODE == "PRBS15") ? 14 :
                   (MODE == "PRBS20") ? 3  :
                   (MODE == "PRBS23") ? 18 :
                   (MODE == "PRBS29") ? 27 :
                   (MODE == "PRBS31") ? 28 : 28;

localparam  INV  = (MODE == "PRBS7" ) ? 1  :
                   (MODE == "PRBS9" ) ? 0  :
                   (MODE == "PRBS11") ? 0  :
                   (MODE == "PRBS15") ? 1  :
                   (MODE == "PRBS20") ? 0  :
                   (MODE == "PRBS23") ? 1  :
                   (MODE == "PRBS29") ? 1  :
                   (MODE == "PRBS31") ? 1  : 1;

///////////////////////////////////////////////////////////////////////////////////////////////////
// Internal Signals
///////////////////////////////////////////////////////////////////////////////////////////////////
wire [LEN-1:0] data[DW:0];
reg  [LEN-1:0] data_r;

wire [DW -1:0] data_xor;

///////////////////////////////////////////////////////////////////////////////////////////////////
//  Main Functions
///////////////////////////////////////////////////////////////////////////////////////////////////
assign data[0] = data_r;

always @ (posedge i_clk or posedge i_rst)
begin
    if (i_rst == 1'b1)
        data_r <= {LEN{1'b1}};
    else if (i_en == 1'b1)
        data_r <= data[DW];
end

genvar n;
generate
for (n = 0; n <= DW-1; n = n+1) begin : nIdx
    assign data_xor[n] =  data[n][LEN-1] ^ data[n][TAP-1];
    assign data  [n+1] = {data[n][LEN-2:0], data_xor[n]};
end
endgenerate

always @ (posedge i_clk or posedge i_rst)
begin
    if (i_rst == 1'b1)
        o_data <= {DW{1'b1}};
    else if (i_en == 1'b1)
        o_data <= (INV == 1) ? ~data_xor[DW-1:0] : data_xor[DW-1:0];
end

endmodule
