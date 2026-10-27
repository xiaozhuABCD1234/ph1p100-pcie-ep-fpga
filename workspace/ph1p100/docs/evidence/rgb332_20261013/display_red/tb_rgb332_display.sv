`timescale 1ns/1ps
// Detect channel swaps, wrong bit expansion/luma, byte ordering, 2x scaling,
// visible mode changes, and RGB/control pipeline misalignment.
module tb_rgb332_display;
 reg clk=0,rst_n=0,vs=0,hs=0,de=0,tv=0,ack=0;
 reg[257:0] token=0;
 wire ready,request,ovs,ohs,ode,color_mode;wire[23:0] rgb;
 wire[31:0] underflows,shown;
 always #5 clk=~clk;
 rgb332_display_pixels #(.SW(16),.SH(2),.FRAMES_PER_MODE(2)) dut(
  .pclk(clk),.rst_n(rst_n),.vs(vs),.hs(hs),.de(de),.token(token),.token_valid(tv),.token_ready(ready),
  .request_toggle(request),.ack_toggle(ack),.rgb(rgb),.out_vs(ovs),.out_hs(ohs),.out_de(ode),
  .underflow_frames(underflows),.shown_frames(shown),.color_mode(color_mode));
 function[7:0] palette(input integer n);
  case(n%8)0:palette=8'he0;1:palette=8'h1c;2:palette=3;3:palette=8'hff;
   4:palette=0;5:palette=8'h10;6:palette=8'h0c;7:palette=8'hc6;endcase
 endfunction
 function[23:0] expected(input integer n,input bit color);
  if(color)case(n%8)0:expected=24'hff0000;1:expected=24'h00ff00;2:expected=24'h0000ff;
   3:expected=24'hffffff;4:expected=0;5:expected=24'h009200;6:expected=24'h006d00;7:expected=24'hdb24aa;endcase
  else case(n%8)0:expected=24'h3f3f3f;1:expected=24'h7f7f7f;2:expected=24'h3f3f3f;
   3:expected=24'hffffff;4:expected=0;5:expected=24'h494949;6:expected=24'h363636;7:expected=24'h737373;endcase
 endfunction
 integer samples=0,color_samples=0,gray_samples=0,edges=0;
 reg wanted_mode=1,previous_vs=0;
 task tick(input bit v,input bit d,input bit h);
  begin
   @(negedge clk);vs=v;de=d;hs=h;
   if(rst_n&&v&&!previous_vs)begin edges=edges+1;if(edges%2==0)wanted_mode=~wanted_mode;end
   @(posedge clk);#1;
   if(rst_n)begin
    if({ovs,ode,ohs}!=={v,d,h})$fatal(1,"RGB332_DISPLAY_FAIL sync");
    if(color_mode!==wanted_mode)$fatal(1,"RGB332_DISPLAY_FAIL mode boundary");
   end
   previous_vs=v;
  end
 endtask
 task send(input[257:0] value);
  integer timeout;
  begin
   @(negedge clk);token=value;tv=1;timeout=0;
   while(!ready)begin @(negedge clk);timeout=timeout+1;if(timeout>40)$fatal(1,"RGB332_DISPLAY_FAIL token stall");end
   @(negedge clk);tv=0;
  end
 endtask
 task video_frame;
  reg[255:0] first,second;
  integer x,y;
  begin
   tick(1,0,0);repeat(3)tick(1,0,1);tick(0,0,0);
   for(x=0;x<32;x=x+1)begin first[x*8+:8]=palette(x%16);second[x*8+:8]=palette(x%16+3);end
   send({2'd1,223'd0,request,32'd7});ack=request;
   send({2'd0,first});send({2'd0,second});repeat(5)tick(0,0,0);
   for(y=0;y<4;y=y+1)begin
    for(x=0;x<32;x=x+1)begin
     tick(0,1,1);
     if(rgb!==expected(x/2+(y/2)*3,wanted_mode))
      $fatal(1,"RGB332_DISPLAY_FAIL pixel x=%0d y=%0d color=%b got=%h want=%h",x,y,wanted_mode,rgb,expected(x/2+(y/2)*3,wanted_mode));
     samples=samples+1;if(wanted_mode)color_samples=color_samples+1;else gray_samples=gray_samples+1;
    end
    repeat(3)tick(0,0,0);
   end
   if(underflows!=0)$fatal(1,"RGB332_DISPLAY_FAIL underflow");
  end
 endtask
 initial begin
  repeat(3)tick(0,0,0);@(negedge clk);rst_n=1;
  repeat(4)video_frame();
  if(color_samples!=256||gray_samples!=256||shown!=4)$fatal(1,"RGB332_DISPLAY_FAIL coverage");
  @(negedge clk);rst_n=0;repeat(3)tick(0,0,0);
  if(rgb!==0||ode||ovs||ohs||color_mode!==1)$fatal(1,"RGB332_DISPLAY_FAIL reset");
  $display("RGB332_DISPLAY_PASS samples=%0d color=%0d gray=%0d frames=4",samples,color_samples,gray_samples);$finish;
 end
 initial begin #50000;$fatal(1,"RGB332_DISPLAY_FAIL timeout");end
endmodule

`ifdef BASELINE_GRAY
module rgb332_display_pixels #(parameter SW=16,SH=2,FRAMES_PER_MODE=2)(
 input pclk,rst_n,vs,hs,de,input[257:0] token,input token_valid,output token_ready,
 output request_toggle,input ack_toggle,output[23:0] rgb,output out_vs,out_hs,out_de,
 output[31:0] underflow_frames,shown_frames,output color_mode);
 assign color_mode=1;
 gray_display_pixels #(.SW(SW),.SH(SH)) old(.*);
endmodule
`endif
