`timescale 1ns/1ps
// Independent literal palette; input registers model the actual pixel consumer.
module tb_rgb332_reference_overlay;
 localparam SW=8,SH=3,W=SW*2,H=SH*2,REF=2;
 reg pclk=0,rst_n=0,source_vs=0,source_de=0;reg[23:0] source_rgb=0;
 reg vs=0,de=0;reg[23:0] camera_rgb=0;wire[23:0] rgb;
 integer checks=0,reference_checks=0,camera_checks=0;
 always #5 pclk=~pclk;
 always @(posedge pclk)begin vs<=source_vs;de<=source_de;camera_rgb<=source_rgb;end
 rgb332_reference_overlay #(.SW(SW),.SH(SH),.REFERENCE_ROWS(REF)) dut(.*);
 function[23:0] palette(input integer n);
  case(n)0:palette=24'hffffff;1:palette=24'hff0000;2:palette=24'h00ff00;3:palette=24'h0000ff;
   4:palette=24'h00ffff;5:palette=24'hff00ff;6:palette=24'hffff00;7:palette=0;endcase
 endfunction
 task tick(input bit v,input bit d,input[23:0] pixel,input[23:0] expected);
  begin @(negedge pclk);source_vs=v;source_de=d;source_rgb=pixel;
   @(posedge pclk);#1;
   if(rgb!==expected)begin $display("RGB332_REFERENCE_FAIL pixel got=%h expected=%h",rgb,expected);$finish;end
   checks=checks+1;
  end
 endtask
 task frame(input integer mode);
  reg[23:0] pixel,want;integer x,y;
  begin
   tick(1,0,24'habcdef,0);tick(1,0,24'habcdef,0);tick(0,0,24'h123456,0);
   for(y=0;y<H;y=y+1)begin
    for(x=0;x<W;x=x+1)begin
     pixel=mode?{3{8'(x+y*W)}}:(24'h123456+x+y*W);
     want=y<REF?palette(x/2):pixel;tick(0,1,pixel,want);
     if(y<REF)reference_checks=reference_checks+1;else camera_checks=camera_checks+1;
    end
    tick(0,0,24'hfedcba,0);tick(0,0,24'h112233,0);
   end
  end
 endtask
 initial begin
  tick(0,0,0,0);rst_n=1;frame(0);frame(1);
  // Last frame ended at y=H-1. Advance x too, then reset without a new VS:
  // this detects missing asynchronous coordinate reset, not just VS recovery.
  tick(0,1,24'h123456,24'h123456);tick(0,1,24'h234567,24'h234567);
  tick(0,1,24'h345678,24'h345678);
  @(negedge pclk);rst_n=0;#1;if(rgb!==0)$fatal(1,"RGB332_REFERENCE_FAIL asynchronous reset");
  source_de=0;source_vs=0;repeat(2)@(negedge pclk);rst_n=1;
  tick(0,0,0,0);tick(0,1,24'h010203,24'hffffff);
  tick(0,1,24'h040506,24'hffffff);tick(0,1,24'h070809,24'hff0000);
  frame(0);
  if(reference_checks!=96||camera_checks!=192)$fatal(1,"RGB332_REFERENCE_FAIL coverage");
  $display("RGB332_REFERENCE_PASS checks=%0d reference=%0d camera=%0d frames=3",checks,reference_checks,camera_checks);$finish;
 end
 initial begin #100000;$fatal(1,"RGB332_REFERENCE_FAIL timeout");end
endmodule
