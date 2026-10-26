`timescale 1ns/1ps
// Fixed received GBRG fixture, independent of DUT_PHASE. This tests the
// origin hypothesis, not the physical camera's unmeasured packet geometry.
module tb_bayer_origin #(parameter DUT_PHASE=3);
 localparam SW=8,SH=4;
 reg clk=0,rst_n=0,pv=0,line=0,frame=0,fe=0,fg=0,dummy_first=0;
 reg[39:0] pixels=0;
 wire sof,valid,last;wire[15:0] data;
 integer count=0,total=0,sofs=0;
 always #5 clk=~clk;
 bayer565_capture #(.SW(SW),.SH(SH),.BAYER_PHASE(DUT_PHASE)) dut(
  .clk(clk),.rst_n(rst_n),.in_pixels(pixels),.in_valid(pv),.in_line(line),.in_frame(frame),
  .out_sof(sof),.out_valid(valid),.out_last(last),.out_data(data),
  .frame_end(fe),.frame_good(fg),.frame_abort(1'b0),
`ifdef WB_PIPELINED_PORTS
  .out_frame_end(),.out_frame_good(),.out_frame_abort(),
`endif
  .stat_a(),.stat_b(),.stat_c(),.stat_d(),.stat_count(),.stat_sequence(),.stat_valid());
 task fail(input string why);begin $display("BAYER_ORIGIN_FAIL %s",why);$finish;end endtask
 // R/Gtop/Gbottom/B raw10 values; fixed physical positions do not use DUT_PHASE.
 function[9:0] component(input integer n,input integer c);
  begin component=0;
   case(n%8)
    0:if(c==1||c==2)component=1023;
    1:if(c==0)component=1023;
    2:if(c==3)component=1023;
    3:component=1023;
    5:if(c==1)component=1022;else if(c==2)component=6;
    6:if(c==1)component=508;else if(c==2)component=512;
    7:case(c)0:component=768;1:component=128;2:component=132;3:component=512;endcase
   endcase
  end
 endfunction
 function[15:0] expected(input integer n,input bit partial_dummy);
  begin
   if(partial_dummy)case(n%8)
    0:expected=16'h03e0;1:expected=16'hf800;2:expected=0;3:expected=16'hfbe0;
    4:expected=0;5:expected=0;6:expected=16'h0200;7:expected=16'hc080;
   endcase
   else case(n%8)
    0:expected=16'h07e0;1:expected=16'hf800;2:expected=16'h001f;3:expected=16'hffff;
    4:expected=0;5:expected=16'h0400;6:expected=16'h03e0;7:expected=16'hc110;
   endcase
  end
 endfunction
 always @(posedge clk)begin
  #1;
  if(rst_n)begin
   if(sof)begin count=0;sofs=sofs+1;end
   if(valid)begin
    if(count>=SW*SH||sofs==0)fail("extra/unframed sample");
    if(data!==expected(count%SW+count/SW,dummy_first&&count<SW))
     fail($sformatf("color phase=%0d index=%0d got=%04h expected=%04h",DUT_PHASE,count,data,expected(count%SW+count/SW,dummy_first&&count<SW)));
    if(last!=(count==SW*SH-1))fail("last boundary");
    count=count+1;total=total+1;
   end else if(last)fail("last without valid");
  end
 end
 task idle(input integer n);begin @(negedge clk);pv=0;repeat(n)@(negedge clk);end endtask
 task send_frame(input bit with_dummy);
  integer row,col,n;reg[9:0] a,b;
  begin
   @(negedge clk);dummy_first=with_dummy;frame=1;idle(3);
   for(row=0;row<SH*4;row++)begin
    @(negedge clk);line=1;pv=0;@(negedge clk);line=0;idle(2);
    for(col=0;col<SW;col++)begin
     n=col+row/4;
     if(row%2==0)begin a=component(n,1);b=component(n,3);end
     else begin a=component(n,0);b=component(n,2);end
     if(with_dummy&&row==0)begin a=0;b=0;end
     if(col%3==1)idle(1);
     @(negedge clk);pv=1;pixels={10'd881,10'd337,b,a};
    end
    idle(4);
   end
   idle(6);if(count!=SW*SH)fail("missing samples");
   @(negedge clk);fe=1;fg=1;@(negedge clk);fe=0;fg=0;
   @(negedge clk);frame=0;idle(4);
  end
 endtask
 initial begin
  idle(3);rst_n=1;send_frame(0);send_frame(1);
  if(total!=64||sofs!=2)fail("total/frame count");
  $display("BAYER_ORIGIN_PASS phase=%0d outputs=%0d fixtures=GBRG,GBRG_with_zero_dummy",DUT_PHASE,total);$finish;
 end
 initial begin #100000;fail("watchdog");end
endmodule
