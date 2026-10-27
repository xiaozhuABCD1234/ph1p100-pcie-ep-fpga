module sync_sof_pair #(
 parameter integer PAIR_WINDOW=50000,
 parameter [31:0] TIMESTAMP_INIT=0
)(input wire clk, reset_n, enable,
 input wire a_valid,b_valid, input wire [31:0] a_seq,b_seq,a_lost,b_lost,
 output reg pair_valid, locked, output reg signed [31:0] skew,
 output reg [31:0] pair_seq_a,pair_seq_b,pair_count,miss_a,miss_b,
 output reg [31:0] overrun_a,overrun_b,relock_count,
 output reg [31:0] timestamp
);
 reg have_a,have_b;
 reg [31:0] time_a,time_b,seq_a,seq_b;
 wire signed [31:0] difference = time_b-time_a;
 always @(posedge clk) begin
  if(!reset_n) begin
   timestamp<=TIMESTAMP_INIT; have_a<=0;have_b<=0;pair_valid<=0;locked<=0;
   skew<=0;pair_seq_a<=0;pair_seq_b<=0;pair_count<=0;miss_a<=0;miss_b<=0;
   overrun_a<=0;overrun_b<=0;relock_count<=0;time_a<=0;time_b<=0;seq_a<=0;seq_b<=0;
  end else begin
   timestamp<=timestamp+1'b1;pair_valid<=0;
   overrun_a<=a_lost;overrun_b<=b_lost;
   if(!enable) begin have_a<=0;have_b<=0;locked<=0;end
   else if(have_a&&have_b) begin
    if(difference<=PAIR_WINDOW && difference>=-PAIR_WINDOW) begin
     pair_valid<=1;skew<=difference;pair_seq_a<=seq_a;pair_seq_b<=seq_b;
     pair_count<=pair_count+1'b1;locked<=1;if(!locked) relock_count<=relock_count+1'b1;
    end else begin miss_a<=miss_a+1'b1;miss_b<=miss_b+1'b1;locked<=0;end
    // Mailbox pulses coincident with consume are retained as the next slots.
    have_a<=a_valid;have_b<=b_valid;
    if(a_valid) begin time_a<=timestamp;seq_a<=a_seq;end
    if(b_valid) begin time_b<=timestamp;seq_b<=b_seq;end
   end else begin
    if(have_a && (timestamp-time_a)>PAIR_WINDOW) begin have_a<=0;miss_b<=miss_b+1'b1;locked<=0;end
    if(have_b && (timestamp-time_b)>PAIR_WINDOW) begin have_b<=0;miss_a<=miss_a+1'b1;locked<=0;end
    if(a_valid) begin
     if(have_a) begin miss_b<=miss_b+1'b1;locked<=0;end
     have_a<=1;time_a<=timestamp;seq_a<=a_seq;
    end
    if(b_valid) begin
     if(have_b) begin miss_a<=miss_a+1'b1;locked<=0;end
     have_b<=1;time_b<=timestamp;seq_b<=b_seq;
    end
   end
  end
 end
endmodule
