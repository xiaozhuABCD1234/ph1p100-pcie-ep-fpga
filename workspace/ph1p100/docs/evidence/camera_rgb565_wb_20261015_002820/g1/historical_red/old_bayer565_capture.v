`timescale 1ns/1ps
// RGB565 preview from each first2x2 cell of a4x4 block; retain raw10 statistics.
// Phase0=RGGB,1=BGGR,2=GRBG,3=GBRG in received pixel/line order.
module bayer565_capture #(parameter SW=960,SH=540,BAYER_PHASE=0)(
 input clk,rst_n,input[39:0] in_pixels,input in_valid,in_line,in_frame,
 output reg out_sof,out_valid,out_last,output reg[15:0] out_data,
 input frame_end,frame_good,frame_abort,
 output reg[31:0] stat_a,stat_b,stat_c,stat_d,stat_count,stat_sequence,output reg stat_valid
);
 localparam CW=$clog2(SW+1),RW=$clog2(SH+1),DEPTH=1<<CW;
 (* ram_style="bram" *) reg[19:0] top_line[0:DEPTH-1];
 reg frame_d,line_d,active,done;
 reg[1:0] line_phase;
 reg[CW-1:0] col;
 reg[RW-1:0] row;
 wire frame_rise=in_frame&&!frame_d,line_rise=in_line&&!line_d;
 wire[1:0] phase_now=line_rise?(line_phase+2'd1):line_phase;
 wire[CW-1:0] col_now=line_rise?{CW{1'b0}}:col;
 wire accept=active&&in_frame&&!done&&!frame_rise&&in_valid&&(col_now<SW);
 wire top_write=accept&&(phase_now==0),bottom_sample=accept&&(phase_now==1);
 wire[19:0] pair={in_pixels[19:10],in_pixels[9:0]};
 reg[19:0] top_q,bottom_q;
 reg pending,pending_last;
 reg[9:0] red,blue;
 reg[10:0] green_sum;
 always @*begin
  red=top_q[9:0];blue=bottom_q[19:10];
  green_sum={1'b0,top_q[19:10]}+{1'b0,bottom_q[9:0]};
  case(BAYER_PHASE)
   1:begin red=bottom_q[19:10];blue=top_q[9:0];end
   2:begin red=top_q[19:10];blue=bottom_q[9:0];green_sum={1'b0,top_q[9:0]}+{1'b0,bottom_q[19:10]};end
   3:begin red=bottom_q[9:0];blue=top_q[19:10];green_sum={1'b0,top_q[9:0]}+{1'b0,bottom_q[19:10]};end
  endcase
 end
 // Physical Bayer positions A/B over C/D, before phase mapping or quantization.
 // Publish only a complete preview belonging to a CSI frame with a good FE verdict.
 reg[31:0] sum_a,sum_b,sum_c,sum_d,sample_count;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   sum_a<=0;sum_b<=0;sum_c<=0;sum_d<=0;sample_count<=0;
   stat_a<=0;stat_b<=0;stat_c<=0;stat_d<=0;stat_count<=0;stat_sequence<=0;stat_valid<=0;
  end else begin
   if(frame_rise)begin sum_a<=0;sum_b<=0;sum_c<=0;sum_d<=0;sample_count<=0;end
   else if(pending)begin
    sum_a<=sum_a+top_q[9:0];sum_b<=sum_b+top_q[19:10];
    sum_c<=sum_c+bottom_q[9:0];sum_d<=sum_d+bottom_q[19:10];sample_count<=sample_count+1'b1;
   end
   if(frame_abort)stat_valid<=0;
   else if(frame_end)begin
    stat_valid<=frame_good&&!frame_rise&&(sample_count+(pending?1:0)==SW*SH);
    if(frame_good&&!frame_rise&&(sample_count+(pending?1:0)==SW*SH))begin
     stat_a<=sum_a+(pending?top_q[9:0]:10'd0);stat_b<=sum_b+(pending?top_q[19:10]:10'd0);
     stat_c<=sum_c+(pending?bottom_q[9:0]:10'd0);stat_d<=sum_d+(pending?bottom_q[19:10]:10'd0);
     stat_count<=sample_count+(pending?1:0);stat_sequence<=stat_sequence+1'b1;
    end
   end
  end
 end
 always @(posedge clk)begin
  if(top_write)top_line[col_now]<=pair;
  if(bottom_sample)begin top_q<=top_line[col_now];bottom_q<=pair;end
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   frame_d<=0;line_d<=0;active<=0;done<=0;line_phase<=3;col<=0;row<=0;
   pending<=0;pending_last<=0;out_sof<=0;out_valid<=0;out_last<=0;out_data<=0;
  end else begin
   frame_d<=in_frame;line_d<=in_line;out_sof<=frame_rise;
   out_valid<=pending;out_last<=pending&&pending_last;
   if(pending)out_data<={red[9:5],green_sum[10:5],blue[9:5]};
   pending<=bottom_sample;pending_last<=bottom_sample&&(col_now==SW-1)&&(row==SH-1);
   if(frame_rise)begin
    active<=1;done<=0;line_phase<=line_rise?0:3;col<=0;row<=0;
    pending<=0;pending_last<=0;out_valid<=0;out_last<=0;
   end else begin
    if(line_rise)begin line_phase<=phase_now;col<=0;end
    if(accept)begin
     col<=col_now+1'b1;
     if(bottom_sample&&col_now==SW-1)begin
      row<=row+1'b1;if(row==SH-1)done<=1;
     end
    end
   end
  end
 end
endmodule
