`timescale 1ns/1ps
// Fixed physical GBRG input. Gain parameters must not change Bayer positions,
// green quantization, framing, or the original unscaled A/B/C/D statistics.
module tb_bayer565_white_balance #(parameter R_GAIN=1615,B_GAIN=1509,BLACK_LEVEL=0);
 localparam SW=16,SH=8,FRAME_PIXELS=SW*SH,FRAMES=9;
 reg clk=0,rst_n=0,pv=0,line=0,frame=0,fe=0,fg=0;
 reg[39:0] pixels=0;
 wire sof,valid,last,stats_valid;
 wire[15:0] data;
 wire[31:0] sa,sb,sc,sd,sn,seq;
 integer stimulus_frame=0,count=0,total=0,sofs=0,lasts=0;
 integer output_checks=0,stats_checks=0,identity_checks=0;
 reg r_covered[0:1023],b_covered[0:1023];
 reg check_publication=0;
 reg[31:0] held_a=0,held_b=0,held_c=0,held_d=0,held_n=0,held_seq=0;
 reg held_valid=0;
 always #5 clk=~clk;
 // Omit new parameter names for the RED run against the original RTL: the
 // missing gain must fail on data, rather than on an unknown parameter error.
 bayer565_capture #(.SW(SW),.SH(SH),.BAYER_PHASE(3)
`ifdef WB_GAIN_PARAMS
  ,.WB_R_GAIN_Q10(R_GAIN),.WB_B_GAIN_Q10(B_GAIN),.WB_BLACK_LEVEL(BLACK_LEVEL)
`endif
 ) dut(
  .clk(clk),.rst_n(rst_n),.in_pixels(pixels),.in_valid(pv),.in_line(line),.in_frame(frame),
  .out_sof(sof),.out_valid(valid),.out_last(last),.out_data(data),
  .frame_end(fe),.frame_good(fg),.frame_abort(1'b0),
  .stat_a(sa),.stat_b(sb),.stat_c(sc),.stat_d(sd),.stat_count(sn),
  .stat_sequence(seq),.stat_valid(stats_valid));

 task fail(input string why);
  begin $display("WB565_FAIL %s",why);$finish;end
 endtask

 // Channel numbers are physical R/Gtop/Gbottom/B, independent of DUT gains.
 function integer component(input integer frame_number,input integer pixel_number,input integer channel);
  integer n;
  begin
   component=0;
   if(frame_number==0)begin
    case(pixel_number%16)
     // Hand checked: old RGB565=3143, corrected RGB565=4944 at default gains.
     0:case(channel)0:component=200;1,2:component=160;3:component=100;endcase
     1:component=0;
     2:component=1023;
     3:case(channel)0,3:component=20;1:component=1022;2:component=6;endcase
     4:case(channel)0:component=649;1,2:component=0;3:component=695;endcase
     5:case(channel)0:component=648;1:component=508;2:component=512;3:component=694;endcase
     6:case(channel)0,2,3:component=1;1:component=0;endcase
     7:case(channel)0,1,3:component=1023;2:component=1022;endcase
     // Fixed physical fixtures around the nominal sensor pedestal of 50.
     8:case(channel)0,3:component=50;1:component=0;2:component=1;endcase
     9:case(channel)0:component=49;1:component=127;2:component=128;3:component=51;endcase
     10:case(channel)0:component=51;1:component=1023;2:component=0;3:component=49;endcase
     11:case(channel)0:component=48;1:component=32;2:component=33;3:component=52;endcase
     12:case(channel)0:component=52;1:component=33;2:component=32;3:component=48;endcase
     13:case(channel)0:component=31;1,2:component=1023;3:component=69;endcase
     14:case(channel)0:component=69;1:component=1;2:component=2;3:component=31;endcase
     15:case(channel)0,1,2:component=0;3:component=1023;endcase
    endcase
   end else begin
    n=(frame_number-1)*FRAME_PIXELS+pixel_number;
    case(channel)
     0:component=n;
     1:component=(37*n+13)%1024;
     2:component=(73*n+14+(n%2))%1024;
     3:component=1023-n;
    endcase
   end
  end
 endfunction

 // Arithmetic oracle: scale the signed distance from black, round magnitude
 // nearest/ties away from zero, restore the pedestal, clamp, then truncate.
 // Integer arithmetic deliberately avoids the RTL's bit slices or helpers.
 function integer balanced_raw(input integer raw_value,input integer gain_value,input integer black_level);
  integer delta,magnitude,rounded,balanced;
  begin
   delta=raw_value-black_level;
   magnitude=(delta<0)?-delta:delta;
   rounded=(magnitude*gain_value+512)/1024;
   balanced=black_level+((delta<0)?-rounded:rounded);
   if(balanced<0)balanced_raw=0;
   else if(balanced>1023)balanced_raw=1023;
   else balanced_raw=balanced;
  end
 endfunction
 function[15:0] expected(input integer frame_number,input integer pixel_number);
  integer red5,green6,blue5;
  begin
   red5=balanced_raw(component(frame_number,pixel_number,0),R_GAIN,BLACK_LEVEL)/32;
   green6=(component(frame_number,pixel_number,1)+component(frame_number,pixel_number,2))/32;
   blue5=balanced_raw(component(frame_number,pixel_number,3),B_GAIN,BLACK_LEVEL)/32;
   expected=red5*2048+green6*32+blue5;
  end
 endfunction

 task unchanged_stats;
  begin
   if(sa!==held_a||sb!==held_b||sc!==held_c||sd!==held_d||sn!==held_n||seq!==held_seq||stats_valid!==held_valid)
    fail("published raw statistics changed outside good FE");
   stats_checks=stats_checks+1;
  end
 endtask
 always @(posedge clk)begin
  #1;
  if(!rst_n)begin
   if(sof!==0||valid!==0||last!==0)fail("reset framing outputs");
   if(sa!==0||sb!==0||sc!==0||sd!==0||sn!==0||seq!==0||stats_valid!==0)fail("reset statistics");
  end else begin
   if(sof)begin
    if(!frame||sofs!=stimulus_frame)fail("duplicate or misplaced SOF");
    if(sofs!=0&&count!=FRAME_PIXELS)fail("previous frame incomplete at SOF");
    count=0;sofs=sofs+1;
   end
   if(valid)begin
    if(!frame||sofs!=stimulus_frame+1||count>=FRAME_PIXELS)fail("extra or unframed output");
    if(data!==expected(stimulus_frame,count))
     fail($sformatf("color frame=%0d index=%0d got=%04h expected=%04h R=%0d Gtop=%0d Gbottom=%0d B=%0d gains=%0d,%0d black_level=%0d",
      stimulus_frame,count,data,expected(stimulus_frame,count),
      component(stimulus_frame,count,0),component(stimulus_frame,count,1),
      component(stimulus_frame,count,2),component(stimulus_frame,count,3),R_GAIN,B_GAIN,BLACK_LEVEL));
    if(last!==((count==FRAME_PIXELS-1)?1'b1:1'b0))fail("last boundary");
    if(last)lasts=lasts+1;
    if(stimulus_frame>0)begin
     r_covered[component(stimulus_frame,count,0)]=1;
     b_covered[component(stimulus_frame,count,3)]=1;
    end
    count=count+1;total=total+1;output_checks=output_checks+1;
   end else if(last!==0)fail("last without valid");
   if(check_publication)unchanged_stats();
  end
 end

 task idle(input integer cycles);
  begin @(negedge clk);pv=0;repeat(cycles)@(negedge clk);end
 endtask
 task drive_row(input integer raw_row);
  integer col,pixel_number,a,b;
  begin
   @(negedge clk);line=1;pv=0;
   @(negedge clk);line=0;idle(2);
   for(col=0;col<SW;col=col+1)begin
    pixel_number=(raw_row/4)*SW+col;
    // Received GBRG is A=Gtop, B=blue over C=red, D=Gbottom.
    if(raw_row%4==0)begin a=component(stimulus_frame,pixel_number,1);b=component(stimulus_frame,pixel_number,3);end
    else if(raw_row%4==1)begin a=component(stimulus_frame,pixel_number,0);b=component(stimulus_frame,pixel_number,2);end
    else begin a=(729+raw_row*11+col)%1024;b=(303+raw_row*17+col*3)%1024;end
    if(col%3==1)idle(1);
    if((col+raw_row)%7==2)idle(2);
    @(negedge clk);pv=1;pixels={10'd881,10'd337,10'(b),10'(a)};
   end
   idle(4);
  end
 endtask
 task check_stats(input integer frame_number);
  integer a,b,c,d,p;
  begin
   a=0;b=0;c=0;d=0;
   for(p=0;p<FRAME_PIXELS;p=p+1)begin
    a=a+component(frame_number,p,1);b=b+component(frame_number,p,3);
    c=c+component(frame_number,p,0);d=d+component(frame_number,p,2);
   end
   if(stats_valid!==1||sn!==FRAME_PIXELS||seq!==frame_number+1||sa!==a||sb!==b||sc!==c||sd!==d)
    fail($sformatf("raw statistics frame=%0d got=%0d,%0d,%0d,%0d count=%0d seq=%0d valid=%b expected=%0d,%0d,%0d,%0d count=%0d seq=%0d",
     frame_number,sa,sb,sc,sd,sn,seq,stats_valid,a,b,c,d,FRAME_PIXELS,frame_number+1));
   stats_checks=stats_checks+1;
  end
 endtask
 task send_frame(input integer frame_number);
  integer raw_row;
  begin
   stimulus_frame=frame_number;
   held_a=sa;held_b=sb;held_c=sc;held_d=sd;held_n=sn;held_seq=seq;held_valid=stats_valid;
   check_publication=1;
   @(negedge clk);frame=1;line=0;pv=0;idle(3);
   for(raw_row=0;raw_row<SH*4;raw_row=raw_row+1)drive_row(raw_row);
   idle(6);
   if(count!=FRAME_PIXELS||sofs!=frame_number+1||lasts!=frame_number+1)fail("missing output, SOF, or last");
   // Done must prevent wraparound even if extra received rows remain valid.
   drive_row(SH*4);drive_row(SH*4+1);idle(4);
   unchanged_stats();check_publication=0;
   @(negedge clk);fe=1;fg=1;
   @(negedge clk);fe=0;fg=0;idle(2);
   check_stats(frame_number);
   held_a=sa;held_b=sb;held_c=sc;held_d=sd;held_n=sn;held_seq=seq;held_valid=stats_valid;
   check_publication=1;
   @(negedge clk);frame=0;idle(4);
  end
 endtask
 integer f,level;
 initial begin
  for(level=0;level<1024;level=level+1)begin r_covered[level]=0;b_covered[level]=0;end
  // Literal cross-checks guard the reference's sign and half-way convention.
  if(balanced_raw(49,1536,50)!=48||balanced_raw(51,1536,50)!=52||
     balanced_raw(50,2400,50)!=50||balanced_raw(0,2400,50)!=0||
     balanced_raw(1023,2400,50)!=1023)fail("signed-magnitude reference fixtures");
  for(level=0;level<1024;level=level+1)begin
   if(balanced_raw(level,1024,0)!=level||balanced_raw(level,1024,50)!=level)
    fail($sformatf("unity gain identity reference level=%0d",level));
   identity_checks=identity_checks+2;
  end
  if(R_GAIN==1615&&B_GAIN==1509&&BLACK_LEVEL==0&&expected(0,0)!==16'h4944)fail("hand-checked legacy reference fixture");
  if(R_GAIN==2400&&B_GAIN==2062&&BLACK_LEVEL==50&&expected(0,0)!==16'h6144)fail("hand-checked calibrated reference fixture");
  idle(3);rst_n=1;
  for(f=0;f<FRAMES;f=f+1)send_frame(f);
  if(total!=FRAMES*FRAME_PIXELS||sofs!=FRAMES||lasts!=FRAMES||output_checks!=FRAMES*FRAME_PIXELS)
   fail("final output/frame/check count");
  for(level=0;level<1024;level=level+1)
   if(!r_covered[level]||!b_covered[level])fail($sformatf("missing RAW10 coverage level=%0d",level));
  $display("WB565_PASS gains=%0d,%0d black_level=%0d frames=%0d outputs=%0d output_checks=%0d stats_checks=%0d identity_checks=%0d raw_levels_R=1024 raw_levels_B=1024 fixture=GBRG",
   R_GAIN,B_GAIN,BLACK_LEVEL,FRAMES,total,output_checks,stats_checks,identity_checks);
  $finish;
 end
 initial begin #500000;fail("watchdog");end
endmodule
