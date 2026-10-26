`timescale 1ns/1ps
module tb_capture_pack;
 reg wc=0,rc=0,rst=0;always #4.5 wc=~wc;always #2.5 rc=~rc;
 reg sof=0,pv=0,pl=0,pause=0;reg[7:0] pixel=0;
 wire[257:0] wi,ro;wire wv,wr,rv;wire[31:0] drops;
 gray_frame_pack #(.FRAME_BYTES(256)) pack(.clk(wc),.rst_n(rst),.sof(sof),.pixel_valid(pv),.pixel_last(pl),.pixel(pixel),.out_data(wi),.out_valid(wv),.out_ready(wr),.dropped_frames(drops));
 capture_async_fifo #(.WIDTH(258),.ADDR_BITS(2)) fifo(.rst_n(rst),.wclk(wc),.w_valid(wv),.w_data(wi),.w_ready(wr),.rclk(rc),.r_valid(rv),.r_data(ro),.r_ready(!pause));
 integer good=0,aborts=0,words=0,i,k,id=0,checks=0;reg active=0;
 function[31:0] expected_crc(input integer fid);
 begin case(fid)
 1:expected_crc=32'h2a2c8aee;
 4:expected_crc=32'ha8760bfb;
 6:expected_crc=32'h61cfe337;
 8:expected_crc=32'h2f100f01;
 default:expected_crc=0;endcase end endfunction
 task fail(input string msg);begin $display("CAPTURE_PACK_FAIL %s",msg);$finish;end endtask
 always @(posedge rc) if(rst && rv && !pause) begin
  checks=checks+1;
  case(ro[257:256])
   1:begin if(active)fail("START replaced un-aborted frame");active=1;id=ro[31:0];words=0;end
   0:begin
    if(!active)fail("data without start");
    for(k=0;k<32;k=k+1)if(ro[k*8+:8]!==((id*17+words*32+k)&255))fail("payload byte order or FIFO hold");
    words=words+1;
   end
   2:begin
    if(!active||words!=8)fail("partial frame published");
    if(ro[31:0]!==32'h43524331||ro[63:32]!==id||ro[127:96]!==32'd256||ro[255:128]!==128'd0)fail("footer fields");
    if(ro[95:64]!==expected_crc(id))begin $display("CRC got=%h expected=%h id=%0d",ro[95:64],expected_crc(id),id);fail("source CRC differs from Python zlib reference");end
    active=0;good=good+1;
   end
   3:begin active=0;aborts=aborts+1;end
  endcase
 end
 task start;begin @(negedge wc);sof=1;@(negedge wc);sof=0;end endtask
 task pixels(input integer fid,input integer count,input bit last_enable);
 begin for(i=0;i<count;i=i+1)begin @(negedge wc);pv=1;pixel=(fid*17+i)&255;pl=last_enable&&(i==255);end
 @(negedge wc);pv=0;pl=0;repeat(8)@(negedge wc);end endtask
 task wait_good(input integer n);integer t;begin t=0;while(good<n&&t<3000)begin @(negedge rc);t=t+1;end if(good!=n)fail("good-frame timeout");end endtask
 initial begin
  repeat(6)@(negedge wc);rst=1;repeat(6)@(negedge wc);
  start();pixels(1,256,1);wait_good(1);
  start();pixels(2,97,0);start();pixels(3,256,1);repeat(20)@(negedge wc);
  start();pixels(4,256,1);wait_good(2);
  pause=1;start();pixels(5,256,1);repeat(20)@(negedge wc);pause=0;repeat(40)@(negedge wc);
  start();pixels(6,256,1);wait_good(3);
  start();pixels(7,256,0);repeat(30)@(negedge wc);
  start();pixels(8,256,1);wait_good(4);
  if(aborts!=3||drops!=4)begin $display("abort=%0d drops=%0d expected drops=4",aborts,drops);fail("each discarded frame must be counted, including both frames lost at early SOF");end
  start();pixels(9,51,0);rst=0;active=0;repeat(5)@(negedge wc);rst=1;repeat(8)@(negedge wc);
  start();pixels(1,256,1);wait_good(5);
  $display("CAPTURE_PACK_PASS good=%0d aborts=%0d checks=%0d",good,aborts,checks);$finish;
 end
 initial begin #200000;$display("CAPTURE_PACK_FAIL watchdog");$finish;end
endmodule
