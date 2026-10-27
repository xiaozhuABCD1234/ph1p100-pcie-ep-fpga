`timescale 1ns/1ps
// Full production geometry, two distinct frames without reset. Received GBRG
// positions are fixed; the upper two pixels and rows 2/3 mod4 are distractors.
module tb_bayer565_full_frame #(parameter R_GAIN=2400,B_GAIN=2062,BLACK_LEVEL=50);
 localparam SW=960,SH=540,N=SW*SH,FRAME_BYTES=N*2,WORDS=N/16;
 reg clk=0,rst_n=0,frame=0,line=0,pv=0,fe=0,fg=0;
 reg[39:0] pixels=0;
 wire sof,valid,last,out_fe,out_fg,out_abort;
 wire[15:0] data;
 wire[31:0] sa,sb,sc,sd,sn,seq,drops;
 wire stats_valid,pack_valid;
 wire[257:0] pack_data;
 reg[31:0] golden_crc[0:1];
 reg covered[0:1][0:3][0:1023];
 integer source_frame=0,frame_index=-1,count=0,total=0,sofs=0,lasts=0;
 integer starts=0,footers=0,word_index=0,total_words=0,pack_frame=0;
 integer stats_checks=0,input_gaps=0,high_x=0,high_y=0;
 integer sum_a=0,sum_b=0,sum_c=0,sum_d=0;
 reg watch_stats=0;
 reg[192:0] held_stats=0;
 always #5 clk=~clk;
 bayer565_capture #(.SW(SW),.SH(SH),.BAYER_PHASE(3),
  .WB_R_GAIN_Q10(R_GAIN),.WB_B_GAIN_Q10(B_GAIN),.WB_BLACK_LEVEL(BLACK_LEVEL)) dut(
  .clk(clk),.rst_n(rst_n),.in_pixels(pixels),.in_valid(pv),.in_line(line),.in_frame(frame),
  .out_sof(sof),.out_valid(valid),.out_last(last),.out_data(data),
  .frame_end(fe),.frame_good(fg),.frame_abort(1'b0),
  .out_frame_end(out_fe),.out_frame_good(out_fg),.out_frame_abort(out_abort),
  .stat_a(sa),.stat_b(sb),.stat_c(sc),.stat_d(sd),.stat_count(sn),.stat_sequence(seq),.stat_valid(stats_valid));
 rgb565_frame_pack_guarded #(.FRAME_BYTES(FRAME_BYTES)) packer(
  .clk(clk),.rst_n(rst_n),.sof(sof),.pixel_valid(valid),.pixel_last(last),.pixel(data),
  .frame_end(out_fe),.frame_good(out_fg),.frame_abort(out_abort),
  .out_data(pack_data),.out_valid(pack_valid),.out_ready(1'b1),.dropped_frames(drops));
 task fail(input string why);
  begin $display("WB565_FULL_FRAME_FAIL frame=%0d output=%0d %s",frame_index,count,why);$finish;end
 endtask
 function integer component(input integer f,input integer x,input integer y,input integer channel);
  begin
   case(channel)
    0:component=(x+17*y+173*f)%1024;
    1:component=(5*x+7*y+97*f+19)%1024;
    2:component=(11*x+13*y+211*f+23+((x/7+y/5+f)%2))%1024;
    3:component=(3*x+29*y+509*f+7)%1024;
   endcase
  end
 endfunction
 function integer balanced(input integer value,input integer gain);
  integer delta,magnitude,rounded,result;
  begin
   delta=value-BLACK_LEVEL;magnitude=(delta<0)?-delta:delta;
   rounded=(magnitude*gain+512)/1024;
   result=BLACK_LEVEL+((delta<0)?-rounded:rounded);
   balanced=(result<0)?0:((result>1023)?1023:result);
  end
 endfunction
 function[15:0] expected(input integer f,input integer index);
  integer x,y,r,g,b;
  begin
   x=index%SW;y=index/SW;
   r=balanced(component(f,x,y,0),R_GAIN)/32;
   g=(component(f,x,y,1)+component(f,x,y,2))/32;
   b=balanced(component(f,x,y,3),B_GAIN)/32;
   expected=r*2048+g*32+b;
  end
 endfunction

 // Accepted production packer tokens must be sampled before NBA.
 always @(posedge clk)begin
  if(rst_n&&pack_valid!==1'b0&&pack_valid!==1'b1)fail("unknown packer valid");
  if(rst_n&&pack_valid)begin
   case(pack_data[257:256])
    1:begin
     starts=starts+1;pack_frame=starts;word_index=0;
     if(starts>2||pack_data[255:32]!==224'd0||pack_data[31:0]!==starts)
      fail("START frame id or payload");
    end
    0:begin
     if(pack_frame<1||pack_frame>2||word_index>=WORDS)fail("unframed or extra payload word");
     for(integer j=0;j<16;j=j+1)
      if(pack_data[j*16+:16]!==expected(pack_frame-1,word_index*16+j))
       fail($sformatf("payload word=%0d lane=%0d got=%04h expected=%04h",word_index,j,pack_data[j*16+:16],expected(pack_frame-1,word_index*16+j)));
     word_index=word_index+1;total_words=total_words+1;
    end
    2:begin
     if(word_index!=WORDS||pack_data[255:128]!==128'd0||pack_data[31:0]!==32'h43524331||
        pack_data[63:32]!==pack_frame||pack_data[95:64]!==golden_crc[pack_frame-1]||pack_data[127:96]!==FRAME_BYTES)
      fail($sformatf("FOOTER words=%0d id=%0d crc=%08h expected_crc=%08h bytes=%0d",word_index,pack_data[63:32],pack_data[95:64],golden_crc[pack_frame-1],pack_data[127:96]));
     footers=footers+1;
    end
    3:fail("unexpected ABORT");
    default:fail("unknown packer token type");
   endcase
  end
  #1;
  if(rst_n)begin
   if((^{sof,valid,last,out_fe,out_fg,out_abort,stats_valid})===1'bx)fail("unknown sampler control");
   if(sof)begin
    if(sofs!=source_frame||(sofs!=0&&count!=N))fail("SOF boundary");
    frame_index=source_frame;count=0;sofs=sofs+1;sum_a=0;sum_b=0;sum_c=0;sum_d=0;
   end
   if(valid)begin
    if(frame_index<0||frame_index!=source_frame||count>=N)fail("unframed or extra sampler output");
    if(data!==expected(frame_index,count))fail($sformatf("RGB565 x=%0d y=%0d got=%04h expected=%04h",count%SW,count/SW,data,expected(frame_index,count)));
    if(last!==((count==N-1)?1'b1:1'b0))fail("last boundary");
    if(last)lasts=lasts+1;
    for(integer c=0;c<4;c=c+1)covered[frame_index][c][component(frame_index,count%SW,count/SW,c)]=1;
    sum_a=sum_a+component(frame_index,count%SW,count/SW,1);
    sum_b=sum_b+component(frame_index,count%SW,count/SW,3);
    sum_c=sum_c+component(frame_index,count%SW,count/SW,0);
    sum_d=sum_d+component(frame_index,count%SW,count/SW,2);
    if(count%SW>=256)high_x=high_x+1;
    if(count/SW>=256)high_y=high_y+1;
    count=count+1;total=total+1;
   end else if(last!==0)fail("last without valid");
   if(watch_stats&&{sa,sb,sc,sd,sn,seq,stats_valid}!==held_stats)fail("raw statistics changed outside good FE");
   if(out_abort||drops!==0)fail("abort or dropped frame");
  end
 end
 task tick;begin @(negedge clk);end endtask
 task idle(input integer n);begin tick();pv=0;repeat(n)tick();end endtask
 task send_frame(input integer f);
  integer row,col,a,b,upper_a,upper_b;
  begin
   tick();source_frame=f;frame=1;line=0;pv=0;
   held_stats={sa,sb,sc,sd,sn,seq,stats_valid};watch_stats=1;idle(3);
   for(row=0;row<SH*4;row=row+1)begin
    tick();line=1;pv=0;tick();line=0;idle(1);
    for(col=0;col<SW;col=col+1)begin
     if(row%4==0)begin a=component(f,col,row/4,1);b=component(f,col,row/4,3);end
     else if(row%4==1)begin a=component(f,col,row/4,0);b=component(f,col,row/4,2);end
     else begin a=(row*43+col*3+f*19+103)%1024;b=(row*29+col*17+f*31+701)%1024;end
     upper_a=a^10'h155;upper_b=b^10'h2aa;
     if((col+row+f)%257==31)begin idle(1);input_gaps=input_gaps+1;end
     tick();pv=1;pixels={10'(upper_b),10'(upper_a),10'(b),10'(a)};
    end
    idle(2);
    if(row%540==539)$display("WB565_FULL_FRAME_PROGRESS frame=%0d received_rows=%0d outputs=%0d",f+1,row+1,count);
   end
   idle(8);
   if(count!=N||sofs!=f+1||lasts!=f+1||footers!=f)fail("complete preview boundaries before FE");
   tick();watch_stats=0;fe=1;fg=1;
   tick();fe=0;fg=0;
   if(stats_valid!==1||sn!==N||seq!==f+1||sa!==sum_a||sb!==sum_b||sc!==sum_c||sd!==sum_d)
    fail($sformatf("raw stats got=%0d,%0d,%0d,%0d N=%0d seq=%0d valid=%b expected=%0d,%0d,%0d,%0d",sa,sb,sc,sd,sn,seq,stats_valid,sum_a,sum_b,sum_c,sum_d));
   stats_checks=stats_checks+1;held_stats={sa,sb,sc,sd,sn,seq,stats_valid};watch_stats=1;
   idle(8);if(footers!=f+1||word_index!=WORDS||starts!=f+1)fail("committed packer boundaries");
   tick();frame=0;line=0;idle(8);
  end
 endtask
 integer f,c,level;
 initial begin
  $readmemh("golden_crc.hex",golden_crc);
  for(f=0;f<2;f=f+1)for(c=0;c<4;c=c+1)for(level=0;level<1024;level=level+1)covered[f][c][level]=0;
  idle(4);rst_n=1;idle(3);send_frame(0);send_frame(1);
  if(total!=2*N||sofs!=2||lasts!=2||starts!=2||footers!=2||total_words!=2*WORDS||stats_checks!=2||drops!==0||input_gaps==0||high_x!=760320||high_y!=545280)
   fail("final counts or high-coordinate coverage");
  for(f=0;f<2;f=f+1)for(c=0;c<4;c=c+1)for(level=0;level<1024;level=level+1)
   if(!covered[f][c][level])fail($sformatf("RAW10 coverage frame=%0d channel=%0d level=%0d",f,c,level));
  $display("WB565_FULL_FRAME_PASS frames=2 width=960 height=540 outputs=%0d payload_words=%0d starts=%0d footers=%0d stats_checks=%0d raw_levels_per_channel_per_frame=1024 high_x=%0d high_y=%0d gaps=%0d crc0=%08h crc1=%08h",
   total,total_words,starts,footers,stats_checks,high_x,high_y,input_gaps,golden_crc[0],golden_crc[1]);
  $finish;
 end
 initial begin #100000000;fail("watchdog");end
endmodule
