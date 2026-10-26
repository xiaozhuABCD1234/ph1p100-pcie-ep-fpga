`timescale 1ns/1ps
// Catches missing DDR display, byte-order/2x2 scaling errors, tearing on frame
// switch, old FIFO residue, active-video underflow drift and missed recovery.
module tb_ddr_display #(parameter SW=64,SH=16,PRODUCTION=0,ADDRESS_FAULT=0);
 localparam FRAME_BYTES=SW*SH,WORDS=FRAME_BYTES/32+1;
 reg clk=0,cap_clk=0,pclk=0;always #2.5 clk=~clk;always #4.5 cap_clk=~cap_clk;always #3.367 pclk=~pclk;
 reg rst_n=0,ddr_ready=0,sof=0,pixel_valid=0,pixel_last=0;reg[7:0] pixel=0;
`ifdef GUARDED
 reg frame_end=0,frame_good=0,frame_abort=0;
`endif
 reg vs=0,hs=0,de=0;wire[23:0] rgb;wire out_vs,out_hs,out_de;
 wire[31:0] passed_frames,failed_frames,published_frames,protocol_errors,capture_drops,underflow_frames,shown_frames;
 wire[26:0] paxi_awaddr,paxi_araddr;wire[255:0] paxi_wdata;wire[31:0] paxi_wstrb;
 wire paxi_awvalid,paxi_wvalid,paxi_wlast,paxi_arvalid,paxi_rready;
 integer cycles=0,delay_left=0,checks=0,reads=0,writes=0;reg pending=0,stall=0,corrupt_footer=0,corrupt_data=0;
 wire paxi_awready=ddr_ready&&cycles%3!=0,paxi_arready=ddr_ready&&!stall&&cycles%5!=0,paxi_wready=ddr_ready&&cycles%7!=0;
 reg[255:0] paxi_rdata=0,pending_data=0;reg paxi_rvalid=0,paxi_rlast=1,pending_last=1;integer bad_rlast=0;
 reg[255:0] memory[0:WORDS*3-1];integer k,x,y,f,model_address;reg[7:0] expected;reg error_at_entry;
`ifdef GUARDED
 camera_ddr_display_guarded
`else
 camera_ddr_display
`endif
 #(.SW(SW),.SH(SH),.CAP_FIFO_BITS(4),.DISPLAY_FIFO_BITS(3)) dut(.*);
 task fail(input string msg);begin $display("DDR_DISPLAY_FAIL %s cycles=%0d checks=%0d pub=%0d pass=%0d bad=%0d under=%0d",msg,cycles,checks,published_frames,passed_frames,failed_frames,underflow_frames);$finish;end endtask
 // Include upper address bits: a 256-byte periodic ramp hides word-address
 // aliasing (e.g. word bit4 stuck low changes the offset by 512 bytes).
 function[7:0] value(input integer id,input integer offset);
  value=(id*19+offset*3+(offset>>8)*29+(offset>>16)*101)&255;
 endfunction
 always @(posedge clk)begin
  cycles<=cycles+1;
  if(!rst_n||!ddr_ready)begin paxi_rvalid<=0;pending<=0;end else begin
   if(paxi_awvalid)begin
    if(!paxi_wvalid||!paxi_awready||!paxi_wready||paxi_wstrb!==0||!paxi_wlast)fail("native write");
    if(paxi_awaddr>=WORDS*24||paxi_awaddr[2:0]!=0)fail("write range");
    memory[paxi_awaddr>>3]<=paxi_wdata;writes<=writes+1;
   end
   if(paxi_rvalid&&paxi_rready)paxi_rvalid<=0;
   if(pending&&!stall)begin
    if(delay_left!=0)delay_left<=delay_left-1;else begin paxi_rvalid<=1;paxi_rdata<=pending_data;paxi_rlast<=pending_last;pending<=0;end
   end
   if(paxi_arvalid&&paxi_arready)begin
    if(pending||paxi_rvalid)fail("read overlap");
    if(paxi_araddr>=WORDS*24||paxi_araddr[2:0]!=0)fail("read range");
    pending_last<=!((bad_rlast==1&&(paxi_araddr>>3)%WORDS==WORDS-1)||(bad_rlast==2&&(paxi_araddr>>3)%WORDS==0));
    model_address=paxi_araddr>>3;
    // Deliberate address-alias negative control; preserve footer metadata.
    if(ADDRESS_FAULT&&model_address%WORDS!=WORDS-1)model_address=model_address&~16;
    pending_data<=memory[model_address];pending<=1;delay_left<=cycles%7+4;reads<=reads+1;
    if(corrupt_data&&(paxi_araddr>>3)%WORDS==0)pending_data<=memory[paxi_araddr>>3]^256'd1;
    if(corrupt_footer&&(paxi_araddr>>3)%WORDS==WORDS-1)pending_data<=memory[paxi_araddr>>3]^(256'd1<<96);
   end
  end
 end
 task send_frame(input integer id);begin
  @(negedge cap_clk);sof=1;@(negedge cap_clk);sof=0;
  for(k=0;k<FRAME_BYTES;k=k+1)begin @(negedge cap_clk);pixel_valid=1;pixel=value(id,k);pixel_last=(k==FRAME_BYTES-1);end
  @(negedge cap_clk);pixel_valid=0;pixel_last=0;
`ifdef GUARDED
  repeat(4)@(negedge cap_clk);frame_end=1;frame_good=1;@(negedge cap_clk);frame_end=0;frame_good=0;
`endif
 end endtask
 task tick(input bit v,input bit h,input bit d);begin
  @(negedge pclk);vs=v;hs=h;de=d;@(posedge pclk);#0.1;
  if({out_vs,out_hs,out_de}!=={v,h,d})fail("video control alignment");
 end endtask
 function[23:0] color_expected(input[7:0] code);
 integer r,g,b;begin r=(((code>>5)&7)*255+3)/7;g=(((code>>2)&7)*255+3)/7;b=(code&3)*85;
 color_expected={r[7:0],g[7:0],b[7:0]};end endfunction
 task show_frame(input integer id,input integer fault);integer a,b;begin
  // Long blank is deliberately independent of DUT states: enough for a bounded
  // DDR response and prefill, not a wait on implementation internals.
  tick(0,0,0);repeat(4*(SW*2+16))tick(1,0,0);
  repeat(8*(SW*2+16))tick(0,0,0);
  for(b=0;b<SH*2;b=b+1)begin
   for(a=0;a<SW*2;a=a+1)begin
    if(fault==1&&a==0&&b==0)stall=1;
    if(fault==3&&a==0&&b==SH)stall=0; // START returns during active video.
    tick(0,0,1);expected=value(id,(b/2)*SW+a/2);if(corrupt_data&&a<2&&b<2)expected=expected^1;
    if(fault==0&&rgb!==color_expected(expected))begin $display("pixel x=%0d y=%0d rgb=%h expected=%h",a,b,rgb,expected);fail("2x2 pixel/old-frame residue");end
    if(fault&&underflow_frames!=0&&rgb!==0)fail("underflow remainder must be black");
    checks=checks+1;
   end
   repeat(8)tick(0,1,0);repeat(8)tick(0,0,0);
  end
  repeat(64)tick(0,0,0);
  stall=0;
 end endtask
 initial begin
  repeat(6)@(negedge cap_clk);rst_n=1;repeat(8)@(negedge cap_clk);ddr_ready=1;repeat(12)@(negedge pclk);
  // Startup without a complete frame must remain black, without a false error.
  repeat(64)tick(1,0,0);repeat(128)tick(0,0,0);
  repeat(64)begin tick(0,0,1);if(rgb!==0)fail("startup black");end
  if(underflow_frames!=0)fail("startup false underflow");
  send_frame(1);repeat(300)@(negedge clk);if(published_frames!=1)fail("first complete publication");
  show_frame(1,0);if(passed_frames<1||protocol_errors!=0||underflow_frames!=0)fail("first CRC/display");
  if(!PRODUCTION)begin
   show_frame(1,0); // no fresh camera data: repeat the locked complete frame
   fork
    show_frame(1,0);
    begin repeat(12*(SW*2+16)+SW*2)@(negedge pclk);send_frame(2);end
   join
   if(published_frames!=2)fail("second complete publication during active video");
   show_frame(2,0); // switch only in blank, never mix old/new pixels
   show_frame(2,1);if(underflow_frames!=1)fail("underflow count once per display frame");
   show_frame(2,0);if(underflow_frames!=1)fail("underflow recovery");
   corrupt_footer=1;show_frame(2,0);corrupt_footer=0;if(failed_frames==0)fail("footer corruption detection");
   corrupt_data=1;show_frame(2,0);corrupt_data=0;if(failed_frames<2)fail("all-byte CRC corruption detection");
   repeat(8)tick(1,0,0);wait(pending);
   // Reset with an accepted response pending; model flush follows controller contract.
   @(negedge clk);rst_n=0;ddr_ready=0;repeat(12)@(negedge clk);rst_n=1;repeat(12)@(negedge clk);ddr_ready=1;repeat(12)@(negedge pclk);
   send_frame(3);repeat(300)@(negedge clk);show_frame(3,0);if(passed_frames<1||underflow_frames!=0||protocol_errors!=0)fail("reset recovery");
   repeat(8)tick(1,0,0);wait(pending);@(negedge clk);ddr_ready=0;repeat(12)@(negedge clk);ddr_ready=1;repeat(12)@(negedge pclk);
   send_frame(4);repeat(300)@(negedge clk);show_frame(4,0);if(passed_frames<1||underflow_frames!=0||protocol_errors!=0)fail("ready-loss recovery with controller flush");
   // The backend consumes an invalid RLAST and cancels read ownership without rd_valid.
   bad_rlast=1;show_frame(4,2);bad_rlast=0;send_frame(5);repeat(300)@(negedge clk);show_frame(5,0);
   bad_rlast=2;show_frame(5,2);bad_rlast=0;send_frame(6);repeat(300)@(negedge clk);show_frame(6,0);
   stall=1;show_frame(6,3);repeat(500)@(negedge clk);show_frame(6,0);
   if(protocol_errors!=2)fail("exactly two injected RLAST errors");
  end
  $display("DDR_DISPLAY_PASS size=%0dx%0d pixels=%0d reads=%0d writes=%0d crc=%0d rejected=%0d underflows=%0d shown=%0d",SW,SH,checks,reads,writes,passed_frames,failed_frames,underflow_frames,shown_frames);$finish;
 end
 initial begin #(FRAME_BYTES*1200+1000000);fail("watchdog");end
endmodule
