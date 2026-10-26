module sync_start_ctrl #(
 parameter integer CTRL_HZ=50000000,
 parameter integer WAIT_CYCLES=(CTRL_HZ/1000)*24,
 parameter integer WARMUP_FRAMES=8,
 parameter integer I2C_TIMEOUT=5000000,
 parameter integer FRAME_TIMEOUT=5000000
)(input wire clk,reset_n,start,abort_req,prereq_ok,pair_event,
 output wire req_valid,input wire req_ready,
 output reg camera_id,output reg [15:0] reg_addr,output reg [7:0] reg_data,
 input wire rsp_valid,rsp_ok,
 output wire busy,measurement_enable,output reg ready,stopped_confirmed,
 output reg [3:0] error_code,output reg [31:0] warmup_count,
 output reg [31:0] ignored_starts
);
 localparam IDLE=0,SEND=1,ACK=2,WAIT_B=3,WAIT_A=4,WARM=5,RUN=6,ERROR=7;
 reg [3:0] state; reg [4:0] step;
 reg cleanup,transport_poison,cancel_pending;
 reg [31:0] timer;
 assign req_valid=state==SEND;
 assign busy=state!=IDLE && state!=ERROR;
 assign measurement_enable=state==WARM || state==RUN;
 // Cleanup writes standby BEFORE S-class Hi-Z. NACK/timeout during cleanup
 // leaves stopped_confirmed=0: there is no physical stop guarantee over a dead bus.
 always @* begin
  camera_id=0;reg_addr=16'h3000;reg_data=8'h01;
  if(cleanup) case(step)
   0: begin camera_id=0;reg_addr=16'h3000;reg_data=1;end
   1: begin camera_id=1;reg_addr=16'h3000;reg_data=1;end
   2: begin camera_id=0;reg_addr=16'h3002;reg_data=1;end
   3: begin camera_id=1;reg_addr=16'h3002;reg_data=1;end
   4: begin camera_id=0;reg_addr=16'h30c1;reg_data=8'h0f;end
   5: begin camera_id=1;reg_addr=16'h30c1;reg_data=8'h0f;end
  endcase
  else case(step)
   0: begin camera_id=0;reg_addr=16'h3000;reg_data=1;end
   1: begin camera_id=0;reg_addr=16'h3002;reg_data=1;end
   2: begin camera_id=0;reg_addr=16'h30c1;reg_data=8'h0f;end
   3: begin camera_id=1;reg_addr=16'h3000;reg_data=1;end
   4: begin camera_id=1;reg_addr=16'h3002;reg_data=1;end
   5: begin camera_id=1;reg_addr=16'h30c1;reg_data=8'h0f;end
   6: begin camera_id=1;reg_addr=16'h3003;reg_data=1;end
   7: begin camera_id=1;reg_addr=16'h30c0;reg_data=8'h2a;end
   8: begin camera_id=0;reg_addr=16'h3003;reg_data=0;end
   9: begin camera_id=0;reg_addr=16'h30c0;reg_data=8'h2a;end
   10:begin camera_id=0;reg_addr=16'h30c1;reg_data=0;end
   11:begin camera_id=1;reg_addr=16'h3000;reg_data=0;end
   12:begin camera_id=0;reg_addr=16'h3000;reg_data=0;end
   13:begin camera_id=0;reg_addr=16'h3002;reg_data=0;end
  endcase
 end
 always @(posedge clk) begin
  if(!reset_n) begin
   state<=IDLE;step<=0;cleanup<=0;transport_poison<=0;cancel_pending<=0;timer<=0;ready<=0;error_code<=0;
   stopped_confirmed<=0;warmup_count<=0;ignored_starts<=0;
  end else begin
   if(start && busy) ignored_starts<=ignored_starts+1'b1;
   if((abort_req||!prereq_ok) && busy && !cleanup) cancel_pending<=1;
   if((abort_req || !prereq_ok) && busy && !cleanup && state!=ACK && state!=SEND) begin
    cleanup<=1;step<=0;state<=SEND;timer<=0;ready<=0;error_code<=abort_req?4:1;
   end else case(state)
    IDLE,ERROR: if(start && !transport_poison) begin
     ready<=0;stopped_confirmed<=0;warmup_count<=0;timer<=0;
     if(prereq_ok) begin state<=SEND;step<=0;cleanup<=0;cancel_pending<=0;error_code<=0;end
     else begin state<=ERROR;error_code<=1;end
    end
    SEND: begin
     if(req_ready) begin state<=ACK;timer<=0;end
     else if(timer==I2C_TIMEOUT-1) begin
      ready<=0;error_code<=3;timer<=0;
      if(cleanup) state<=ERROR;else begin cleanup<=1;step<=0;state<=SEND;end
     end else timer<=timer+1'b1;
    end
    ACK: begin
     if(rsp_valid) begin
      timer<=0;
      if(!rsp_ok || ((cancel_pending||abort_req||!prereq_ok)&&!cleanup)) begin
       ready<=0;error_code<=!rsp_ok?2:(abort_req?4:1);
       if(cleanup) state<=ERROR;else begin cleanup<=1;step<=0;state<=SEND;end
      end else if(cleanup) begin
       if(step==5) begin stopped_confirmed<=1;state<=ERROR;end
       else begin step<=step+1'b1;state<=SEND;end
      end else if(step==11) state<=WAIT_B;
      else if(step==12) state<=WAIT_A;
      else if(step==13) begin state<=WARM;warmup_count<=0;end
      else begin step<=step+1'b1;state<=SEND;end
     end else if(timer==I2C_TIMEOUT-1) begin
      ready<=0;error_code<=3;timer<=0;
      // A timed out accepted request may reply late. Do not create another
      // request on the same bus; require transport reset with global reset.
      stopped_confirmed<=0;transport_poison<=1;state<=ERROR;
     end else timer<=timer+1'b1;
    end
    WAIT_B,WAIT_A: if(timer==WAIT_CYCLES-1) begin
     timer<=0;step<=step+1'b1;state<=SEND;
    end else timer<=timer+1'b1;
    WARM,RUN: begin
     if(pair_event) begin
      timer<=0;
      if(state==WARM) begin
       if(warmup_count==WARMUP_FRAMES-1) begin warmup_count<=WARMUP_FRAMES;state<=RUN;end
       else warmup_count<=warmup_count+1'b1;
      end else ready<=1;
     end else if(timer==FRAME_TIMEOUT-1) begin
      cleanup<=1;step<=0;state<=SEND;timer<=0;ready<=0;error_code<=5;
     end else timer<=timer+1'b1;
    end
    default:state<=ERROR;
   endcase
  end
 end
endmodule
