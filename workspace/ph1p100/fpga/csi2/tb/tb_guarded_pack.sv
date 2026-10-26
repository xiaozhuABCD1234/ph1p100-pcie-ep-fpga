`timescale 1ns/1ps
module tb_guarded_pack;
 reg clk=0,rst_n=0,sof=0,pixel_valid=0,pixel_last=0,frame_end=0,frame_good=0,frame_abort=0,out_ready=1;
 reg[7:0] pixel=0;wire[257:0] out_data;wire out_valid;wire[31:0] dropped_frames;
 integer footers=0,aborts=0,starts=0,words=0,i,cases=0,f0,a0;reg[31:0] d0;
`ifdef BASELINE
 gray_frame_pack #(.FRAME_BYTES(256)) dut(.clk(clk),.rst_n(rst_n),.sof(sof),.pixel_valid(pixel_valid),.pixel_last(pixel_last),.pixel(pixel),.out_data(out_data),.out_valid(out_valid),.out_ready(out_ready),.dropped_frames(dropped_frames));
`else
 gray_frame_pack_guarded #(.FRAME_BYTES(256)) dut(.*);
`endif
 always #5 clk=~clk;
 task fail(input string why);begin $display("INTEGRITY_FAIL pack %s footers=%0d aborts=%0d",why,footers,aborts);$finish;end endtask
 always @(posedge clk)if(rst_n&&out_valid&&out_ready)case(out_data[257:256])
  1:begin starts=starts+1;words=0;end
  0:begin
   for(integer j=0;j<32;j=j+1)if(out_data[j*8+:8]!==((words*32+j+(words*32+j)/128*17)&255))fail("payload");
   words=words+1;
  end
  2:begin if(words!=8||out_data[31:0]!==32'h43524331||out_data[127:96]!==256)fail("footer");if(out_data[95:64]!==32'h1628db46)fail("CRC32 golden");footers=footers+1;end
  3:aborts=aborts+1;
 endcase
 task tick;begin @(negedge clk);end endtask
 task start;begin tick();sof=1;tick();sof=0;end endtask
 task pixels(input integer n);begin
  for(i=0;i<n;i=i+1)begin tick();pixel_valid=1;pixel=(i+i/128*17)&255;pixel_last=(i==255);end
  tick();pixel_valid=0;pixel_last=0;
 end endtask
 task finish_frame(input bit good);begin tick();frame_end=1;frame_good=good;tick();frame_end=0;frame_good=0;repeat(8)tick();end endtask
 initial begin
  repeat(4)tick();rst_n=1;repeat(3)tick();
  start();pixels(256);repeat(50)tick();if(footers!=0)fail("published before FE");
  frame_abort=1;tick();frame_abort=0;finish_frame(0);if(footers!=0||aborts!=1)fail("late CRC abort escaped");cases++;
  start();pixels(256);finish_frame(1);if(footers!=1)fail("recovery");cases++;
  start();pixels(60);finish_frame(1);if(footers!=1||aborts!=2)fail("early FE committed short preview");cases++;
  start();pixels(256);repeat(30)tick();start();pixels(256);repeat(20)tick();if(footers!=1||aborts!=3)fail("missing FE/new FS");cases++;
  start();pixels(256);finish_frame(1);if(footers!=2)fail("recovery after missing FE");cases++;
  start();pixels(256);out_ready=0;finish_frame(1);repeat(8)tick();frame_abort=1;tick();frame_abort=0;out_ready=1;repeat(8)tick();if(footers!=2||aborts!=4)fail("stalled footer accepted after abort");cases++;
  start();pixels(256);finish_frame(1);if(footers!=3)fail("stalled footer recovery");cases++;
  start();pixels(256);finish_frame(0);if(footers!=3||aborts!=5)fail("bad FE");cases++;
  start();pixels(33);rst_n=0;repeat(4)tick();rst_n=1;repeat(4)tick();start();pixels(256);finish_frame(1);if(footers!=4)fail("reset recovery");cases++;
  // End event coincident with final preview pixel must not drop a valid frame.
  start();for(i=0;i<256;i=i+1)begin tick();pixel_valid=1;pixel=(i+i/128*17)&255;pixel_last=(i==255);frame_end=(i==255);frame_good=frame_end;end
  tick();pixel_valid=0;pixel_last=0;frame_end=0;frame_good=0;repeat(8)tick();if(footers!=5)fail("coincident pixel/FE");cases++;
  // Ready rises on exactly the edge carrying a late abort: no footer leak.
  f0=footers;a0=aborts;start();pixels(256);out_ready=0;finish_frame(1);frame_abort=1;out_ready=1;tick();frame_abort=0;repeat(8)tick();if(footers!=f0||aborts!=a0+1)fail("ready/abort same edge");cases++;
  // One rejected frame, even when FIFO overflow and FE coincide.
  d0=dropped_frames;a0=aborts;f0=footers;start();for(i=0;i<256;i++)begin tick();pixel_valid=1;pixel=(i+i/128*17)&255;pixel_last=(i==255);frame_end=(i==255);frame_good=frame_end;if(i==255)out_ready=0;end
  tick();pixel_valid=0;pixel_last=0;frame_end=0;frame_good=0;out_ready=1;repeat(8)tick();if(dropped_frames!=d0+1||aborts!=a0+1||footers!=f0)fail("overflow/FE exact drop");cases++;
  // A new SOF while the old valid footer is stalled drops only the new input.
  start();pixels(256);out_ready=0;finish_frame(1);d0=dropped_frames;f0=footers;start();pixels(256);if(dropped_frames!=d0+1)fail("stalled footer/new SOF drop");out_ready=1;repeat(8)tick();if(footers!=f0+1)fail("stalled old footer ownership");cases++;
  start();pixels(256);finish_frame(1);if(footers!=f0+2)fail("final recovery");cases++;
  $display("INTEGRITY_PASS pack cases=%0d footers=%0d aborts=%0d",cases,footers,aborts);$finish;
 end
 initial begin #1000000;fail("watchdog");end
endmodule
