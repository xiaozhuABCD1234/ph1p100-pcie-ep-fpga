module sync_reset(input wire clk, input wire rst_n, output wire reset_n);
  (* ASYNC_REG = "TRUE" *) reg [1:0] release_ff;
  always @(posedge clk or negedge rst_n)
    if (!rst_n) release_ff <= 2'b00;
    else release_ff <= {release_ff[0],1'b1};
  assign reset_n = release_ff[1];
endmodule
