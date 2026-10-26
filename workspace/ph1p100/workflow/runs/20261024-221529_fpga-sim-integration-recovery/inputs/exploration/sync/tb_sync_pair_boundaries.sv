`timescale 1ns/1ps
module tb_sync_pair_boundaries;
  reg clk=0;
  always #5 clk=~clk;
  reg reset_n=0,enable=1,a_valid=0,b_valid=0;
  reg [31:0] a_seq=0,b_seq=0,a_lost=0,b_lost=0;
  wire pair_valid,locked;
  wire signed [31:0] skew;
  wire [31:0] pair_seq_a,pair_seq_b,pair_count,miss_a,miss_b;
  wire [31:0] overrun_a,overrun_b,relock_count,timestamp;
  sync_sof_pair #(.PAIR_WINDOW(4),.TIMESTAMP_INIT(32'hfffffffc)) dut(.*);
  integer checks=0;
  task check(input bit ok,input string message);
    checks=checks+1;
    if(!ok) begin $display("PAIR_BOUNDARY_FAIL %s count=%0d skew=%0d t=%h",message,pair_count,skew,timestamp); $fatal(1); end
  endtask
  task step(input bit av,input bit bv,input [31:0] asq,input [31:0] bsq);
    @(negedge clk); a_valid=av;b_valid=bv;a_seq=asq;b_seq=bsq;
    @(posedge clk); #1;
  endtask
  task idle(input integer n);
    repeat(n) step(0,0,0,0);
  endtask
  task restart;
    @(negedge clk); reset_n=0;enable=1;a_valid=0;b_valid=0;a_lost=0;b_lost=0;
    repeat(2) @(posedge clk);
    @(negedge clk);reset_n=1;
  endtask
  initial begin
    restart();step(1,1,10,20);idle(1);
    check(pair_count==1 && pair_valid && skew==0 && pair_seq_a==10 && pair_seq_b==20,"simultaneous identity");
    restart();step(1,0,11,0);idle(3);step(0,1,0,21);idle(1);
    check(pair_count==1 && skew==4 && pair_seq_a==11 && pair_seq_b==21,"positive inclusive window across timestamp wrap");
    restart();step(0,1,0,22);idle(3);step(1,0,12,0);idle(1);
    check(pair_count==1 && skew==-4,"negative inclusive window across timestamp wrap");
    restart();step(1,0,13,0);idle(4);step(0,1,0,23);idle(6);
    check(pair_count==0 && !locked && miss_b>0 && miss_a>0,"outside window rejects and expires");
    restart();step(1,1,100,200);step(1,1,101,201);
    check(pair_count==1 && pair_seq_a==100 && pair_seq_b==200,"consume first while next arrives");
    idle(1);check(pair_count==2 && pair_seq_a==101 && pair_seq_b==201,"retain coincident next pair");
    idle(2);check(pair_count==2 && !pair_valid,"no duplicate publication");
    restart();step(1,0,14,0);
    @(negedge clk); enable=0;a_valid=0;b_valid=0;
    @(posedge clk);#1;check(!locked && !pair_valid,"disable clears pending lock");
    @(negedge clk);enable=1;
    step(0,1,0,24);idle(6);check(pair_count==0,"no cross-disable pair");
    step(1,1,15,25);idle(1);check(pair_count==1 && locked,"recovery after disable");
    @(negedge clk);a_lost=3;b_lost=5;
    @(posedge clk);#1;check(overrun_a==3 && overrun_b==5,"loss counters preserved");
    $display("PAIR_BOUNDARY_PASS checks=%0d",checks);$finish;
  end
  initial begin #20000;$fatal(1,"PAIR_BOUNDARY watchdog");end
endmodule
