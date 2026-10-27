`timescale 1ns/1ps
// Detect swapped Bayer phase, averaging overflow/round-up, stale row memory,
// dropped last pixels, duplicate output, and reset/frame boundary leakage.
module tb_bayer565_capture;
 localparam SW=8,SH=4;
 reg clk=0,rst_n=0,frame=0,line=0,pv=0,fe=0,fg=0,abort_frame=0;
 wire[31:0] sa[0:3],sb[0:3],sc[0:3],sd[0:3],sn[0:3],seq[0:3];wire[3:0] stats_valid;
 reg[39:0] pixels[0:3];
 wire[3:0] sof,valid,last;wire[15:0] data[0:3];
 integer count[0:3],sofs[0:3],total=0;
 always #5 clk=~clk;
 genvar phase;
 generate for(phase=0;phase<4;phase=phase+1)begin:formats
  bayer565_capture #(.SW(SW),.SH(SH),.BAYER_PHASE(phase)) dut(
   .clk(clk),.rst_n(rst_n),.in_pixels(pixels[phase]),.in_valid(pv),
   .in_line(line),.in_frame(frame),.out_sof(sof[phase]),
   .out_valid(valid[phase]),.out_last(last[phase]),.out_data(data[phase]),
   .frame_end(fe),.frame_good(fg),.frame_abort(abort_frame),
   .stat_a(sa[phase]),.stat_b(sb[phase]),.stat_c(sc[phase]),.stat_d(sd[phase]),
   .stat_count(sn[phase]),.stat_sequence(seq[phase]),.stat_valid(stats_valid[phase]));
 end endgenerate
 function[15:0] want(input integer n);
  case(n%8) 0:want=16'hf800;1:want=16'h07e0;2:want=16'h001f;3:want=16'hffff;
   4:want=0;5:want=16'h0400;6:want=16'h03e0;7:want=16'hc110;endcase
 endfunction
 // Independent literals: R/G1/G2/B in 10-bit sensor units.
 function[9:0] component(input integer n,input integer channel);
  begin component=0;
   case(n%8)
    0:if(channel==0)component=1023;
    1:if(channel==1||channel==2)component=1023;
    2:if(channel==3)component=1023;
    3:component=1023;
    5:if(channel==1)component=1022;else if(channel==2)component=6;
    6:if(channel==1)component=508;else if(channel==2)component=512;
    7:case(channel)0:component=768;1:component=128;2:component=132;3:component=512;endcase
   endcase
  end
 endfunction
 task fail(input string message);begin $display("%s",message);$finish;end endtask
 integer p;
 always @(posedge clk)begin
  #1;
  for(integer k=0;k<4;k=k+1)begin
   if(!rst_n)begin count[k]=0;sofs[k]=0;
    if(valid[k]||last[k]||sof[k])fail($sformatf("RGB565_CAPTURE_FAIL reset outputs"));
   end else begin
    if(sof[k])begin count[k]=0;sofs[k]=sofs[k]+1;end
    if(valid[k])begin
     if(count[k]>=SW*SH)fail($sformatf("RGB565_CAPTURE_FAIL extra pixel"));
     if(data[k]!==want(count[k]%SW+count[k]/SW))
      fail($sformatf("RGB565_CAPTURE_FAIL color phase=%0d index=%0d got=%h want=%h",k,count[k],data[k],want(count[k]%SW+count[k]/SW)));
     if(last[k]!=(count[k]==SW*SH-1))fail($sformatf("RGB565_CAPTURE_FAIL last boundary"));
     count[k]=count[k]+1;total=total+1;
    end else if(last[k])fail($sformatf("RGB565_CAPTURE_FAIL last without valid"));
   end
  end
 end
 task idle(input integer cycles);
  begin @(negedge clk);pv=0;repeat(cycles)@(negedge clk);end
 endtask
 task drive_row(input integer row);
  reg[9:0] r,g1,g2,b,a0,a1;
  integer col,k,n;
  begin
   @(negedge clk);line=(row%2==0);pv=0;
   if(row%2==0)begin repeat(2)@(negedge clk);line=0;end
   for(col=0;col<SW;col=col+1)begin
    n=col+row/4;
    r=component(n,0);g1=component(n,1);g2=component(n,2);b=component(n,3);
    if(col%3==1)idle(1);
    @(negedge clk);pv=1;if(row%2==1)line=(col==0);
    for(k=0;k<4;k=k+1)begin
     case(k)
      0:begin a0=row%4==0?r:g2;a1=row%4==0?g1:b;end // RGGB
      1:begin a0=row%4==0?b:g2;a1=row%4==0?g1:r;end // BGGR
      2:begin a0=row%4==0?g1:b;a1=row%4==0?r:g2;end // GRBG
      3:begin a0=row%4==0?g1:r;a1=row%4==0?b:g2;end // GBRG
     endcase
     if(row%4>=2)begin a0=10'd123;a1=10'd987;end
     pixels[k]={10'd333,10'd777,a1,a0};
    end
   end
   idle(4);
  end
 endtask
 task check_stats;
  integer sums[0:3];integer rr,cc,pp,aa,bb,cv,dv;
  begin
   for(pp=0;pp<4;pp++)begin
    for(cc=0;cc<4;cc++)sums[cc]=0;
    for(rr=0;rr<SH;rr++)for(cc=0;cc<SW;cc++)begin
     case(pp)
      0:begin aa=0;bb=1;cv=2;dv=3;end
      1:begin aa=3;bb=1;cv=2;dv=0;end
      2:begin aa=1;bb=0;cv=3;dv=2;end
      3:begin aa=1;bb=3;cv=0;dv=2;end
     endcase
     sums[0]+=component(cc+rr,aa);sums[1]+=component(cc+rr,bb);
     sums[2]+=component(cc+rr,cv);sums[3]+=component(cc+rr,dv);
    end
    if(!stats_valid[pp]||sn[pp]!=SW*SH||sa[pp]!==sums[0]||sb[pp]!==sums[1]||sc[pp]!==sums[2]||sd[pp]!==sums[3])
     fail($sformatf("RGB565_CAPTURE_FAIL raw statistics phase=%0d got=%0d,%0d,%0d,%0d count=%0d",pp,sa[pp],sb[pp],sc[pp],sd[pp],sn[pp]));
   end
  end
 endtask
 reg[31:0] held_a[0:3],held_b[0:3],held_c[0:3],held_d[0:3],held_n[0:3],held_seq[0:3];
 reg[3:0] held_valid;
 task snapshot_stats;
  begin
   held_valid=stats_valid;
   for(integer z=0;z<4;z++)begin
    held_a[z]=sa[z];held_b[z]=sb[z];held_c[z]=sc[z];held_d[z]=sd[z];held_n[z]=sn[z];held_seq[z]=seq[z];
   end
  end
 endtask
 task unchanged_stats;
  begin
   for(integer z=0;z<4;z++)
    if(sa[z]!==held_a[z]||sb[z]!==held_b[z]||sc[z]!==held_c[z]||sd[z]!==held_d[z]||sn[z]!==held_n[z]||seq[z]!==held_seq[z])
     fail("RGB565_CAPTURE_FAIL premature/invalid statistics publication");
  end
 endtask
 task source(input integer verdict);
  begin
   snapshot_stats();@(negedge clk);frame=1;line=0;pv=0;idle(3);
   for(integer y=0;y<SH*4;y=y+1)drive_row(y);
   idle(6);
   for(integer k=0;k<4;k=k+1)if(count[k]!=SW*SH)fail($sformatf("RGB565_CAPTURE_FAIL missing pixels"));
   // Extra valid rows inside the same frame must not wrap and publish again.
   drive_row(SH*4);drive_row(SH*4+1);idle(4);
   unchanged_stats();if(stats_valid!==held_valid)fail("RGB565_CAPTURE_FAIL valid changed before FE");
   if(verdict>=0)begin @(negedge clk);fe=1;fg=(verdict==1);@(negedge clk);fe=0;fg=0;idle(2);end
   if(verdict==1)begin
    check_stats();for(integer z=0;z<4;z++)if(seq[z]!=held_seq[z]+1)fail("RGB565_CAPTURE_FAIL accepted sequence");
   end else begin unchanged_stats();if(verdict==0&&stats_valid!==0)fail("RGB565_CAPTURE_FAIL bad FE valid");end
   @(negedge clk);frame=0;idle(3);
  end
 endtask
 initial begin
  for(p=0;p<4;p=p+1)begin pixels[p]=0;count[p]=0;sofs[p]=0;end
  idle(3);rst_n=1;source(1);source(1);source(0);source(-1);
  // Assert reset while the first bottom sample is pending in synchronous RAM.
  @(negedge clk);frame=1;idle(3);drive_row(0);
  @(negedge clk);line=1;pv=1;
  pixels[0]=0;pixels[1]={20'd0,10'd1023,10'd0};
  pixels[2]=0;pixels[3]={20'd0,10'd0,10'd1023};
  @(posedge clk);#2;if(valid!==0)fail($sformatf("RGB565_CAPTURE_FAIL pending precondition"));
  @(negedge clk);rst_n=0;frame=0;line=0;pv=0;idle(3);
  rst_n=1;source(1);
  // A nominally good but early FE cannot publish a partial preview.
  snapshot_stats();@(negedge clk);frame=1;idle(3);drive_row(0);drive_row(1);idle(3);
  @(negedge clk);fe=1;fg=1;@(negedge clk);fe=0;fg=0;idle(2);
  unchanged_stats();if(stats_valid!==0)fail("RGB565_CAPTURE_FAIL early FE valid");
  @(negedge clk);abort_frame=1;idle(2);unchanged_stats();if(stats_valid!==0)fail($sformatf("RGB565_CAPTURE_FAIL abort stats"));
  $display("RGB565_CAPTURE_PASS phases=4 complete_previews=5 good_frames=3 bad_missing_early_FE_checked=1 samples=%0d",total);$finish;
 end
 initial begin #100000;fail($sformatf("RGB565_CAPTURE_FAIL timeout"));end
endmodule

