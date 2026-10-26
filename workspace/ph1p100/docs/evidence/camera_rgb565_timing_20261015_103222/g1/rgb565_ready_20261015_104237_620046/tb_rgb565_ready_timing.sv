`timescale 1ns/1ps
// Exercise raw ready-loss assertion independently of a user-clock sample.
// Removing ddr_ready from the common asynchronous reset must fail this test.
module tb_rgb565_ready_timing;
 localparam SW=64,SH=16,FRAME_BYTES=SW*SH*2,WORDS=FRAME_BYTES/32+1;
 reg clk=0,cap_clk=0,pclk=0;always #2.5 clk=~clk;always #4.5 cap_clk=~cap_clk;always #3.367 pclk=~pclk;
 reg rst_n=0,ddr_ready=0,sof=0,pixel_valid=0,pixel_last=0;reg[15:0] pixel=0;
 reg frame_end=0,frame_good=0,frame_abort=0,vs=0,hs=0,de=0;
 wire[23:0] rgb;wire out_vs,out_hs,out_de;
 wire[31:0] passed_frames,failed_frames,published_frames,protocol_errors,capture_drops,underflow_frames,shown_frames;
 wire[26:0] paxi_awaddr,paxi_araddr;wire[255:0] paxi_wdata;wire[31:0] paxi_wstrb;
 wire paxi_awvalid,paxi_wvalid,paxi_wlast,paxi_arvalid,paxi_rready;
 integer cycles=0,delay_left=0,checks=0,reads=0,writes=0,user_edges=0,release_edges=0;
 integer pulse_cases=0,flush_cases=0,crc_tail_cases=0,check_boundary_cases=0,release_guard_checks=0;
 reg pending=0,stall=0;reg[255:0] paxi_rdata=0,pending_data=0;reg paxi_rvalid=0,paxi_rlast=1;
 wire paxi_awready=ddr_ready&&cycles%3!=0;
 wire paxi_arready=ddr_ready&&!stall&&cycles%5!=0;
 wire paxi_wready=ddr_ready&&cycles%7!=0;
 reg[255:0] memory[0:WORDS*3-1];reg[31:0] golden_crc[1:6],expected_publish_crc;
 integer k,before_pass;reg[15:0] expected;reg crc_tail_armed=0,crc_tail_seen=0,check_armed=0,check_seen=0;
 camera_rgb565_display_guarded #(.SW(SW),.SH(SH),.CAP_FIFO_BITS(4),.DISPLAY_FIFO_BITS(3)) dut(.*);
 initial $readmemh("golden_crc.txt",golden_crc);
 task fail(input string msg);begin
  $display("RGB565_READY_FAIL %s cycles=%0d checks=%0d pub=%0d pass=%0d bad=%0d under=%0d",msg,cycles,checks,published_frames,passed_frames,failed_frames,underflow_frames);$finish;
 end endtask
 function[15:0] value(input integer id,input integer offset);
  value=((id*7919+offset*131+(offset>>8)*997+(offset>>16)*1237)^16'ha639)&65535;
 endfunction
 function[23:0] color_expected(input[15:0] code);integer r,g,b;begin
  r=(code/2048)*8+(code/8192);g=((code/32)%64)*4+((code/512)%4);b=(code%32)*8+((code/4)%8);
  color_expected={r[7:0],g[7:0],b[7:0]};
 end endfunction
 // This is the DDR controller contract: pending accepted responses are flushed
 // on raw ready loss, even when no user-clock rising edge samples the pulse.
 always @(posedge clk)begin cycles<=cycles+1;user_edges<=user_edges+1;end
 always @(posedge clk or negedge rst_n or negedge ddr_ready)begin
  if(!rst_n||!ddr_ready)begin paxi_rvalid<=0;pending<=0;end
  else begin
   if(paxi_awvalid)begin
    if(!paxi_wvalid||!paxi_awready||!paxi_wready||paxi_wstrb!==0||!paxi_wlast)fail("native write contract");
    if(paxi_awaddr>=WORDS*24||paxi_awaddr[2:0]!=0)fail("write range");
    if((paxi_awaddr>>3)%WORDS==WORDS-1)
     if(paxi_wdata[31:0]!==32'h43524331||paxi_wdata[95:64]!==expected_publish_crc||paxi_wdata[127:96]!=FRAME_BYTES)
      fail("independent zlib footer CRC/length");
    memory[paxi_awaddr>>3]<=paxi_wdata;writes<=writes+1;
   end
   if(paxi_rvalid&&paxi_rready)paxi_rvalid<=0;
   if(pending&&!stall)begin
    if(delay_left!=0)delay_left<=delay_left-1;
    else begin paxi_rvalid<=1;paxi_rdata<=pending_data;paxi_rlast<=1;pending<=0;end
   end
   if(paxi_arvalid&&paxi_arready)begin
    if(pending||paxi_rvalid)fail("read overlap");
    if(paxi_araddr>=WORDS*24||paxi_araddr[2:0]!=0)fail("read range");
    pending_data<=memory[paxi_araddr>>3];pending<=1;delay_left<=cycles%7+4;reads<=reads+1;
   end
  end
 end
 // Count the required release edges independently of the DUT synchronizer.
 always @(posedge clk or negedge rst_n or negedge ddr_ready)
  if(!rst_n||!ddr_ready)release_edges<=0;else if(release_edges<2)release_edges<=release_edges+1;
 always @(posedge clk)if(rst_n&&ddr_ready&&release_edges<2)begin
  release_guard_checks=release_guard_checks+1;
  if({paxi_awvalid,paxi_wvalid,paxi_arvalid}!==3'b000)fail("command before two release edges");
 end
 always @(negedge clk)if(!rst_n||!ddr_ready)
  if({paxi_awvalid,paxi_wvalid,paxi_arvalid}!==3'b000)fail("command while raw ready low");
 always @(negedge clk)if(rst_n&&ddr_ready&&release_edges==2)
  if((^{published_frames,passed_frames,failed_frames,protocol_errors,capture_drops,underflow_frames,shown_frames})===1'bx)
   fail("unknown status");
 always @(posedge clk)if(crc_tail_armed&&dut.u_reader.state==10&&dut.u_reader.row==SH-1
                            &&dut.u_reader.col_word==SW/16-1&&dut.u_reader.byte_index==28)crc_tail_seen<=1;
 always @(posedge clk)if(check_armed&&dut.u_reader.state==12)check_seen<=1;
 task send_frame(input integer id);begin
  expected_publish_crc=golden_crc[id];
  @(negedge cap_clk);sof=1;@(negedge cap_clk);sof=0;
  for(k=0;k<SW*SH;k=k+1)begin @(negedge cap_clk);pixel_valid=1;pixel=value(id,k);pixel_last=(k==SW*SH-1);end
  @(negedge cap_clk);pixel_valid=0;pixel_last=0;
  repeat(4)@(negedge cap_clk);frame_end=1;frame_good=1;@(negedge cap_clk);frame_end=0;frame_good=0;
 end endtask
 task tick(input bit v,input bit h,input bit d);begin
  @(negedge pclk);vs=v;hs=h;de=d;@(posedge pclk);#0.1;
  if({out_vs,out_hs,out_de}!=={v,h,d})fail("video controls");
 end endtask
 task show_frame(input integer id);integer a,b;begin
  tick(0,0,0);repeat(4*(SW*2+16))tick(1,0,0);repeat(8*(SW*2+16))tick(0,0,0);
  for(b=0;b<SH*2;b=b+1)begin
   for(a=0;a<SW*2;a=a+1)begin
    tick(0,0,1);expected=value(id,(b/2)*SW+a/2);
    if(rgb!==color_expected(expected))begin $display("pixel x=%0d y=%0d actual=%h expected=%h",a,b,rgb,color_expected(expected));fail("recovery pixel/epoch");end
    checks=checks+1;
   end
   repeat(8)tick(0,1,0);repeat(8)tick(0,0,0);
  end
  repeat(64)tick(0,0,0);
 end endtask
 task verify_healthy;begin
  if(passed_frames===32'd0||failed_frames!==32'd0||protocol_errors!==32'd0||capture_drops!==32'd0||underflow_frames!==32'd0)fail("healthy frame status");
 end endtask
 task short_ready_pulse(input bit require_pending);integer before_edges;begin
  if(require_pending&&!pending)fail("fixture requires accepted read pending");
  @(posedge clk);#0.6;before_edges=user_edges;ddr_ready=0;
  #0.1;
  if({published_frames,passed_frames,failed_frames,protocol_errors,capture_drops,underflow_frames,shown_frames}!==224'd0
     ||rgb!==24'd0||paxi_awvalid!==0||paxi_wvalid!==0||paxi_arvalid!==0)
   fail("ready pulse must flush prior epoch");
  if(pending!==0||paxi_rvalid!==0)fail("controller contract did not flush");
  #0.4;ddr_ready=1;#0.1;if(user_edges!=before_edges)fail("fixture ready pulse crossed user edge");
  pulse_cases=pulse_cases+1;if(require_pending)flush_cases=flush_cases+1;
  stall=0;repeat(12)@(negedge clk);repeat(12)@(negedge pclk);vs=0;de=0;
  // Without a newly completed capture there can be no old epoch publication.
  repeat(100)@(negedge clk);
  if(published_frames!==32'd0||passed_frames!==32'd0||failed_frames!==32'd0||protocol_errors!==32'd0)fail("stale response/ownership survived ready pulse");
 end endtask
 // Drive active video only until the final source-row CRC tail is reached;
 // then the caller inserts a new real VS, with no direct request forcing.
 task show_until_boundary(input integer id,input integer kind);integer a,b;begin : prefix
  crc_tail_seen=0;crc_tail_armed=(kind==0);check_seen=0;check_armed=(kind==1);
  tick(0,0,0);repeat(4*(SW*2+16))tick(1,0,0);repeat(8*(SW*2+16))tick(0,0,0);
  for(b=0;b<SH*2;b=b+1)begin
   for(a=0;a<SW*2;a=a+1)begin
    tick(0,0,1);
    if((kind==0&&crc_tail_seen)||(kind==1&&check_seen))begin
     crc_tail_armed=0;check_armed=0;
     if(kind==0)crc_tail_cases=crc_tail_cases+1;else check_boundary_cases=check_boundary_cases+1;
     disable prefix;
    end
    expected=value(id,(b/2)*SW+a/2);
    if(rgb!==color_expected(expected))fail("CRC-tail prefix pixel");checks=checks+1;
   end
   repeat(8)tick(0,1,0);repeat(8)tick(0,0,0);
  end
  fail("fixture failed to reach selected reader boundary");
 end endtask
 initial begin
  repeat(6)@(negedge cap_clk);rst_n=1;repeat(8)@(negedge cap_clk);ddr_ready=1;repeat(12)@(negedge pclk);
  send_frame(1);repeat(300)@(negedge clk);if(published_frames!==32'd1)fail("initial publication");
  show_frame(1);verify_healthy();
  // Accepted display response stalled before a pulse invisible to user edges.
  tick(1,0,0);wait(pending&&!dut.u_store.read_is_fence);stall=1;
  short_ready_pulse(1);send_frame(2);repeat(300)@(negedge clk);show_frame(2);verify_healthy();
  // Accepted fence response must not publish the interrupted new capture.
  fork
   send_frame(3);
   begin wait(pending&&dut.u_store.read_is_fence);stall=1;short_ready_pulse(1);end
  join
  send_frame(4);repeat(300)@(negedge clk);show_frame(4);verify_healthy();
  // Ready loss while DE is active clears output, then a complete new capture
  // and subsequent VS recover without an old FIFO word or epoch surviving.
  tick(1,0,0);repeat(2200)tick(0,0,0);repeat(16)tick(0,0,1);
  short_ready_pulse(0);send_frame(5);repeat(300)@(negedge clk);show_frame(5);verify_healthy();
  show_until_boundary(5,0);before_pass=passed_frames;show_frame(5);verify_healthy();
  if(passed_frames<before_pass+1||passed_frames>before_pass+2)fail("CRC-tail/VS verdict count");
  // Insert a real VS immediately after observing final CHECK. Depending on
  // clock phase the old verdict may already be counted; the new complete
  // frame must count once and no old FIFO word/epoch may reach active video.
  show_until_boundary(5,1);before_pass=passed_frames;show_frame(5);verify_healthy();
  if(passed_frames<before_pass+1||passed_frames>before_pass+2)fail("CHECK/VS verdict count");
  if(pulse_cases!=3||flush_cases!=2||crc_tail_cases!=1||check_boundary_cases!=1||release_guard_checks!=8)fail("case coverage");
  $display("RGB565_READY_PASS pixels=%0d reads=%0d writes=%0d pulses=%0d accepted_flushes=%0d crc_tail_vs=%0d check_boundaries=%0d release_guard_cycles=%0d pass=%0d shown=%0d",checks,reads,writes,pulse_cases,flush_cases,crc_tail_cases,check_boundary_cases,release_guard_checks,passed_frames,shown_frames);$finish;
 end
 initial begin #10000000;fail("watchdog");end
endmodule
