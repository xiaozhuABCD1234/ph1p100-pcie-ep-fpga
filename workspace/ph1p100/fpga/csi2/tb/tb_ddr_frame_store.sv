`timescale 1ns/1ps
module tb_ddr_frame_store;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,ddr_ready=0;
 reg frame_begin=0,s_valid=0,s_last=0,s_abort=0,frame_switch=0,rd_req=0,rd_take=0;
 reg [31:0] frame_id=0;reg [255:0] s_data=0;reg [15:0] rd_offset=0;
 wire frame_begin_ready,s_ready,frame_switch_ready,frame_valid,rd_req_ready,rd_valid;
 wire [31:0] read_frame_id,published_count,error_count,drop_count;
 wire [255:0] rd_data,paxi_wdata;wire [26:0] paxi_awaddr,paxi_araddr;
 wire [31:0] paxi_wstrb;wire paxi_awvalid,paxi_wvalid,paxi_wlast,paxi_arvalid,paxi_rready;
 integer cycles=0,delay_left=0,checks=0,writes=0,reads=0;
 wire paxi_awready=(cycles%3!=0)&&ddr_ready;
 wire paxi_wready=(cycles%7!=0)&&ddr_ready;
 wire paxi_arready=(cycles%5!=0)&&ddr_ready;
 reg [255:0] paxi_rdata=0;reg paxi_rvalid=0,paxi_rlast=1;
 reg pending=0,corrupt=0,missing_last=0;reg [255:0] pending_data;
 reg [255:0] memory[0:11];
 ddr_frame_store #(.FRAME_WORDS(4)) dut(.*);
 function [255:0] pattern(input integer fid,input integer offset);
   integer lane;begin for(lane=0;lane<8;lane=lane+1) pattern[lane*32+:32]=(fid<<16) ^ (offset<<8) ^ (32'h12340000+lane);end
 endfunction
 task fail(input string msg);begin $display("DDR_FRAME_FAIL %s",msg);$finish;end endtask
 task check(input bit cond,input string msg);begin checks++;if(!cond)fail(msg);end endtask
 always @(posedge clk) begin
   cycles<=cycles+1;
   if(!rst_n||!ddr_ready)begin pending<=0;paxi_rvalid<=0;delay_left<=0;end
   else begin
     if(paxi_awvalid!==paxi_wvalid)fail("AW/W not paired");
     if(paxi_awvalid)begin
       if(!(paxi_awready&&paxi_wready))fail("write without paired ready");
       if(paxi_awaddr[2:0]!=0||paxi_awaddr>=96)fail("write address stride/range");
       if(paxi_wstrb!==0||paxi_wlast!==1)fail("native mask/LAST");
       memory[paxi_awaddr>>3]<=paxi_wdata;writes<=writes+1;
     end
     if(paxi_rvalid&&paxi_rready)paxi_rvalid<=0;
     if(pending)begin
       if(delay_left!=0)delay_left<=delay_left-1;
       else begin paxi_rdata<=pending_data;paxi_rvalid<=1;paxi_rlast<=!missing_last;pending<=0;missing_last<=0;end
     end
     if(paxi_arvalid&&paxi_arready)begin
       if(pending||paxi_rvalid)fail("more than one read outstanding");
       if(paxi_araddr[2:0]!=0||paxi_araddr>=96)fail("read address stride/range");
       pending<=1;delay_left<=2+cycles%4;
       pending_data<=memory[paxi_araddr>>3]^(corrupt?256'd1:256'd0);
       corrupt<=0;reads<=reads+1;
     end
   end
 end
 task start_frame(input integer fid);
   begin @(negedge clk);frame_id=fid;frame_begin=1;
     do @(posedge clk);while(!frame_begin_ready);
     @(negedge clk);frame_begin=0;
   end
 endtask
 task word(input integer fid,input integer idx,input bit last_word);
   begin @(negedge clk);s_data=pattern(fid,idx);s_last=last_word;s_valid=1;
     do @(posedge clk);while(!s_ready);
     @(negedge clk);s_valid=0;s_last=0;
   end
 endtask
 task send_frame(input integer fid);
   begin start_frame(fid);for(integer j=0;j<4;j++)word(fid,j,j==3);end
 endtask
 task await_publish(input integer n);
   begin wait(published_count==n);repeat(2)@(negedge clk);end
 endtask
 task select_frame(input integer fid);
   begin @(negedge clk);frame_switch=1;
     do @(posedge clk);while(!frame_switch_ready);
     @(negedge clk);frame_switch=0;check(frame_valid&&read_frame_id==fid,"wrong complete frame selected");
   end
 endtask
 task read_word(input integer fid,input integer off);
   reg [255:0] held;
   begin @(negedge clk);rd_req=1;rd_offset=off;
     do @(posedge clk);while(!rd_req_ready);
     @(negedge clk);rd_req=0;
     wait(rd_valid);@(negedge clk);held=rd_data;
     repeat(4)begin @(negedge clk);check(rd_valid&&rd_data===held,"returned word lost under backpressure");end
     check(rd_data===pattern(fid,off),"frame data mismatch/reading slot overwritten");
     rd_take=1;@(negedge clk);rd_take=0;
   end
 endtask
 integer before_pub,before_err;
 initial begin
   repeat(4)@(negedge clk);rst_n=1;
   repeat(5)@(negedge clk);check(!paxi_awvalid&&!paxi_arvalid,"command before DDR ready");ddr_ready=1;
   send_frame(10);await_publish(1);select_frame(10);read_word(10,0);read_word(10,3);
   send_frame(11);await_publish(2);send_frame(12);await_publish(3);
   read_word(10,2);select_frame(12);read_word(12,1);read_word(12,3);
   before_pub=published_count;before_err=error_count;
   start_frame(13);word(13,0,0);word(13,1,1);repeat(12)@(negedge clk);
   check(published_count==before_pub&&error_count>before_err,"short frame published");
   start_frame(14);word(14,0,0);s_abort=1;@(negedge clk);s_abort=0;repeat(5)@(negedge clk);
   check(published_count==before_pub,"aborted frame published");
   before_err=error_count;corrupt=1;send_frame(15);repeat(30)@(negedge clk);
   check(published_count==before_pub&&error_count>before_err,"bad fence published");
   before_err=error_count;missing_last=1;send_frame(16);repeat(30)@(negedge clk);
   check(published_count==before_pub&&error_count>before_err,"missing RLAST published");
   start_frame(17);word(17,0,0);ddr_ready=0;repeat(5)@(negedge clk);
   check(!frame_valid&&!rd_valid&&!paxi_awvalid&&!paxi_arvalid,"ready loss retained unsafe frame");
   ddr_ready=1;send_frame(18);await_publish(before_pub+1);select_frame(18);read_word(18,0);read_word(18,3);
   before_pub=published_count;before_err=error_count;
   start_frame(19);for(integer k=0;k<4;k++)word(19,k,0);
   repeat(12)@(negedge clk);
   check(published_count==before_pub&&error_count==before_err+1,"missing final LAST accepted");
   check(frame_begin_ready,"long-frame rejection did not release writer");
   // Abort after a fence has been accepted: drain it without publishing.
   send_frame(20);wait(pending);@(negedge clk);s_abort=1;
   @(negedge clk);s_abort=0;repeat(20)@(negedge clk);
   check(published_count==before_pub&&frame_begin_ready,"aborted in-flight fence published/stuck");
   // A switch requested while a newer fence returns must wait, then select newest.
   send_frame(21);await_publish(before_pub+1);send_frame(22);
   wait(paxi_rvalid);@(negedge clk);frame_switch=1;
   check(!frame_switch_ready,"switch accepted with outstanding fence");
   do @(posedge clk);while(!frame_switch_ready);
   @(negedge clk);frame_switch=0;
   check(read_frame_id==22&&frame_valid,"deferred switch did not select newest frame");
   check(published_count==before_pub+2,"deferred switch lost publication");
   read_word(22,0);read_word(22,3);
   // Malformed ordinary read must retire READING and allow a fresh frame.
   before_err=error_count;missing_last=1;rd_req=1;rd_offset=1;
   do @(posedge clk);while(!rd_req_ready);
   @(negedge clk);rd_req=0;repeat(20)@(negedge clk);
   check(!frame_valid&&!rd_valid&&error_count==before_err+1,"ordinary bad RLAST retained frame");
   send_frame(23);await_publish(before_pub+3);select_frame(23);read_word(23,3);
   before_pub=published_count;
   // Cancel during the extra registered verification cycle, after R was consumed.
   send_frame(24);wait(paxi_rvalid);repeat(2)@(negedge clk);s_abort=1;
   @(negedge clk);s_abort=0;repeat(10)@(negedge clk);
   check(published_count==before_pub&&frame_begin_ready,"verify-stage abort published/stuck");
   // Hold an ordinary response across a complete new publication.
   rd_req=1;rd_offset=2;do @(posedge clk);while(!rd_req_ready);
   @(negedge clk);rd_req=0;wait(rd_valid);@(negedge clk);
   send_frame(25);await_publish(before_pub+1);
   check(rd_valid&&rd_data===pattern(23,2),"publication changed a held response");
   check(!frame_switch_ready,"switch ignored read output backpressure");
   rd_take=1;@(negedge clk);rd_take=0;
   select_frame(25);read_word(25,3);
   check(drop_count>=1,"abort not counted");
   $display("DDR_FRAME_PASS checks=%0d writes=%0d reads=%0d published=%0d errors=%0d",checks,writes,reads,published_count,error_count);$finish;
 end
 initial begin #100000;fail("watchdog: frame handshake or recovery missing");end
endmodule
