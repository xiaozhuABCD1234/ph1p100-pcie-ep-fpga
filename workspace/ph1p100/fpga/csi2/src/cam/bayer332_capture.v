`timescale 1ns/1ps
// Diagnostic preview: one RGB332 pixel from the first2x2 cell of each4x4 block.
// Phase0=RGGB,1=BGGR,2=GRBG,3=GBRG in received pixel/line order.
module bayer332_capture #(parameter SW=960,SH=540,BAYER_PHASE=0)(
 input clk,rst_n,input[39:0] in_pixels,input in_valid,in_line,in_frame,
 output reg out_sof,out_valid,out_last,output reg[7:0] out_data
);
 localparam CW=$clog2(SW+1),RW=$clog2(SH+1),DEPTH=1<<CW;
 (* ram_style="bram" *) reg[15:0] top_line[0:DEPTH-1];
 reg frame_d,line_d,active,done;
 reg[1:0] line_phase;
 reg[CW-1:0] col;
 reg[RW-1:0] row;
 wire frame_rise=in_frame&&!frame_d,line_rise=in_line&&!line_d;
 wire[1:0] phase_now=line_rise?(line_phase+2'd1):line_phase;
 wire[CW-1:0] col_now=line_rise?{CW{1'b0}}:col;
 wire accept=active&&in_frame&&!done&&!frame_rise&&in_valid&&(col_now<SW);
 wire top_write=accept&&(phase_now==0),bottom_sample=accept&&(phase_now==1);
 wire[15:0] pair={in_pixels[19:12],in_pixels[9:2]};
 reg[15:0] top_q,bottom_q;
 reg pending,pending_last;
 reg[7:0] red,blue;
 reg[8:0] green_sum;
 always @*begin
  red=top_q[7:0];blue=bottom_q[15:8];
  green_sum={1'b0,top_q[15:8]}+{1'b0,bottom_q[7:0]};
  case(BAYER_PHASE)
   1:begin red=bottom_q[15:8];blue=top_q[7:0];end
   2:begin red=top_q[15:8];blue=bottom_q[7:0];green_sum={1'b0,top_q[7:0]}+{1'b0,bottom_q[15:8]};end
   3:begin red=bottom_q[7:0];blue=top_q[15:8];green_sum={1'b0,top_q[7:0]}+{1'b0,bottom_q[15:8]};end
  endcase
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
   if(pending)out_data<={red[7:5],green_sum[8:6],blue[7:6]};
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
