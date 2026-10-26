module phy2mc_fifo#(
  parameter  DQS_WIDTH = 4,
  parameter  DQ_WIDTH  = DQS_WIDTH *8
)(
  input                      clk   ,
  input                      rst_n ,
  input  [DQ_WIDTH*8-1 : 0]  i_dq  ,
  input  [DQS_WIDTH-1  : 0]  i_vld ,
  output [DQ_WIDTH*8-1 : 0]  o_dq  ,
  output [DQS_WIDTH-1  : 0]  o_vld ,
  output [DQS_WIDTH-1  : 0]  full
);

wire [DQ_WIDTH*8-1 : 0]  dq_tmp; 
wire [DQS_WIDTH-1  : 0]  empty ;
reg                      rd_en ;
wire [DQ_WIDTH*8-1 : 0]  dout  ; 

reg  [DQ_WIDTH*8-1 : 0] i_dq_r;
reg  [DQS_WIDTH-1  : 0] i_vld_r;

always @ (posedge clk or negedge rst_n)begin
    if (!rst_n)
        i_dq_r <=  'b0;
    else
        i_dq_r <= i_dq;
end
always @ (posedge clk or negedge rst_n)begin
    if (!rst_n)
        i_vld_r <=  'b0;
    else
        i_vld_r <= i_vld;
end


genvar n , p;
/*generate
    for (n = 0; n <= DQS_WIDTH-1; n = n+1) begin : byteIdx
        for (p = 0; p <= 7; p = p+1) begin : pIdx
              assign dq_tmp[(64*n + 8*p) +: 8] = i_dq_r[(8*p*DQS_WIDTH + 8*n) +: 8];
        end
    end
endgenerate*/
assign dq_tmp = i_dq_r;
generate
    for (n = 0; n <= DQS_WIDTH-1; n = n+1) begin : byteIdx_1
        fifo_dram_sync #(
            .DW    ( 64 ),
            .AW    ( 4  )
        ) u_wfifo_sync (
            .clk   ( clk         ),
            .rst   (~rst_n       ),
            .wren  ( i_vld_r[n] ),
            .din   ( dq_tmp[n*64 +: 64] ),
            .rden  ( o_vld[n] ),
            .dout  ( dout[n*64 +: 64] ),
            .full  ( full[n] ),
            .empty ( empty[n] )
        );
    end
endgenerate

always @ (posedge clk or negedge rst_n)begin
    if (!rst_n)
        rd_en <= 1'b0;
    else if ( (|empty == 1'b0) )
        rd_en <= 1'b1;
    else 
        rd_en <= 1'b0;
end

/*generate
    for (n = 0; n <= DQS_WIDTH-1; n = n+1) begin : byteIdx_2
        for (p = 0; p <= 7; p = p+1) begin : pIdx_2
              assign o_dq[(8*p*DQS_WIDTH + 8*n) +: 8]  = dout[(64*n + 8*p) +: 8];
        end
    end
endgenerate*/
assign o_dq  = dout;
assign o_vld = {DQS_WIDTH {rd_en && (|empty ==1'b0)}};
endmodule
