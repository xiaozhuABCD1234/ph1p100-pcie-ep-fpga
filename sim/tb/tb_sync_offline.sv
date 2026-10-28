`timescale 1ns/1ps
module tb_sync_offline;
 reg clk_ctrl=0,clk_a=0,clk_b=0;
 always #10 clk_ctrl=~clk_ctrl;
 always #2.6665 clk_a=~clk_a;
 initial begin #1.1; forever #2.6667 clk_b=~clk_b;end
 reg rst_n=0,start=0,abort_req=0,prereq_ok=1,sof_a=0,sof_b=0;
 reg req_ready=0,rsp_valid=0,rsp_ok=1;
 wire req_valid,camera_id,ready,busy,stopped_confirmed,pair_valid,locked;
 wire [15:0] reg_addr;wire [7:0] reg_data;wire [3:0] error_code;
 wire signed [31:0] skew;
 wire [31:0] pair_seq_a,pair_seq_b,pair_count,miss_a,miss_b,overrun_a,overrun_b,
 relock_count,warmup_count,ignored_starts,timestamp;
 sync_offline_top #(.WAIT_CYCLES(12),.I2C_TIMEOUT(40),.FRAME_TIMEOUT(120),
 .PAIR_WINDOW(15),.TIMESTAMP_INIT(32'hffffff00)) dut(.*);
 integer transactions=0,cycles=0,ack_cycle_b,ack_cycle_a,mode=0;
 integer pending=0,delay_rsp=0,fail_index=-1;
 reg [24:0] held;
 reg stalled=0;
 // Independent contract table: derived from the frozen 14 register transactions.
 function automatic [24:0] expected(input integer n);
  case(n)
   0:expected={1'b0,16'h3000,8'h01};1:expected={1'b0,16'h3002,8'h01};
   2:expected={1'b0,16'h30c1,8'h0f};3:expected={1'b1,16'h3000,8'h01};
   4:expected={1'b1,16'h3002,8'h00};5:expected={1'b1,16'h30c1,8'h0f};
   6:expected={1'b1,16'h3003,8'h01};7:expected={1'b1,16'h30c0,8'h2a};
   8:expected={1'b0,16'h3003,8'h00};9:expected={1'b0,16'h30c0,8'h2a};
   10:expected={1'b0,16'h30c1,8'h00};11:expected={1'b1,16'h3000,8'h00};
   12:expected={1'b0,16'h3000,8'h00};13:expected={1'b0,16'h3002,8'h00};
   default:expected=25'h1ffffff;
  endcase
 endfunction
 task automatic check(input bit ok,input string why);
  if(!ok) begin $display("SYNC_FAIL %s cycle=%0d tx=%0d",why,cycles,transactions);$fatal(1);end
 endtask
 always @(posedge clk_ctrl) begin
  cycles=cycles+1;
  if(!rst_n) begin transactions=0;pending=0;rsp_valid<=0;stalled=0;end
  else begin
   rsp_valid<=0;
   if(stalled) check(req_valid && {camera_id,reg_addr,reg_data}===held,"request hold");
   stalled=req_valid&&!req_ready;held={camera_id,reg_addr,reg_data};
   if(req_valid&&req_ready) begin
    check(pending==0,"one outstanding");
    check(reg_addr==16'h3000 || reg_addr==16'h3002 || reg_addr==16'h3003 || reg_addr==16'h30c0 || reg_addr==16'h30c1,"whitelist");
    if(mode==0) begin
     check({camera_id,reg_addr,reg_data}===expected(transactions),"ordered role writes");
     if(transactions==12) check(cycles-ack_cycle_b>=12,"WAIT_B N boundary");
     if(transactions==13) check(cycles-ack_cycle_a>=12,"WAIT_A N boundary");
    end
    pending=1;delay_rsp=2;transactions=transactions+1;
   end
   if(pending && mode!=2) begin
    if(delay_rsp==0) begin
     rsp_valid<=1;rsp_ok<=transactions-1!=fail_index;pending=0;
     if(transactions==12) ack_cycle_b=cycles+1;
     if(transactions==13) ack_cycle_a=cycles+1;
    end else delay_rsp=delay_rsp-1;
   end
  end
 end
 task automatic ticks(input integer n);repeat(n) @(negedge clk_ctrl);endtask
 task automatic reset_all;
  rst_n=0;start=0;abort_req=0;sof_a=0;sof_b=0;prereq_ok=1;req_ready=1;
  fail_index=-1;mode=0;ticks(5);rst_n=1;ticks(5);
 endtask
 task automatic start_it;start=1;ticks(1);start=0;endtask
 task automatic boot;
  start_it();wait(transactions==14);ticks(8);
  check(dut.control.measurement_enable,"boot enters warmup");
 endtask
 task automatic event_a;
  @(negedge clk_a);sof_a=1;@(negedge clk_a);sof_a=0;
 endtask
 task automatic event_b;
  @(negedge clk_b);sof_b=1;@(negedge clk_b);sof_b=0;
 endtask
 task automatic two_events;
  fork event_a();begin #23;event_b();end join
  ticks(12);
 endtask
 integer k,base_pairs;reg [31:0] previous_t;
 initial begin
  reset_all();prereq_ok=0;start_it();ticks(4);
  check(transactions==0 && error_code==1,"prerequisites gate");
  reset_all();req_ready=0;start_it();ticks(8);
  check(req_valid && transactions==0,"backpressure");req_ready=1;
  start_it();wait(transactions==14);ticks(8);
  check(ignored_starts>0,"busy reentry ignored");
  for(k=0;k<8;k=k+1) begin two_events();check(!ready,"first eight not ready");end
  check(warmup_count==8,"warmup exact8");two_events();
  check(ready && locked && pair_count==9,"ninth frame ready");
  check(skew>=0 && skew<=3,"asynchronous skew common ctrl ticks");
  previous_t=timestamp;ticks(70);check(timestamp<previous_t,"timestamp modulo32 wrap");
  // A-only then timeout, followed by later matched events: pairing relocks.
  event_a();ticks(24);check(miss_b>0 && !locked,"single B missing");
  two_events();check(locked && relock_count>=2,"pair recovery after missing");
  // Burst faster than mailbox round trip is explicitly rejected.
  repeat(12) event_a();ticks(12);event_a();ticks(12);
  check(overrun_a>0,"source overrun visible");
  // Stop on abort, cleanup ACKs prove the attempted standby/Hi-Z sequence.
  mode=1;abort_req=1;ticks(1);abort_req=0;ticks(55);
  check(!ready && stopped_confirmed && error_code==4,"abort cleanup");
  reset_all();mode=1;fail_index=5;start_it();ticks(100);
  check(error_code==2 && stopped_confirmed && !ready,"NACK cleanup");
  reset_all();mode=2;start_it();ticks(55);
  check(error_code==3 && !stopped_confirmed && !busy,"accepted request timeout");
  mode=1;pending=0;start_it();ticks(10);
  check(transactions==1,"timeout poisoned until transport reset");
  reset_all();boot();mode=1;ticks(180);
  check(error_code==5 && stopped_confirmed && !ready,"no SOF lock timeout");
  reset_all();boot();two_events();check(pair_count==1,"reset recovery");
  rst_n=0;ticks(5);check(!ready && !req_valid,"reset stops logical traffic");
  $display("SYNC_OFFLINE_PASS mismatch=0 scenarios=prereq,hold,busy,order,wait,warmup,nack,timeout,missing,abort,reset,relock,overrun,wrap");
  $finish;
 end
 initial begin #1000000;$fatal(1,"TB watchdog");end
endmodule
