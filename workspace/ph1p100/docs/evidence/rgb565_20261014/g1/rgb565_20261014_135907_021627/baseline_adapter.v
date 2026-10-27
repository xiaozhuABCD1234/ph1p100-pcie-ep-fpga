`timescale 1ns/1ps
module bayer565_capture #(parameter SW=8,SH=4,BAYER_PHASE=0)(
input clk,rst_n,input[39:0] in_pixels,input in_valid,in_line,in_frame,
output out_sof,out_valid,out_last,output[15:0] out_data,
input frame_end,frame_good,frame_abort,
output[31:0] stat_a,stat_b,stat_c,stat_d,stat_count,stat_sequence,output stat_valid);
wire[7:0] old_data;
bayer332_capture #(.SW(SW),.SH(SH),.BAYER_PHASE(BAYER_PHASE)) old(
.clk(clk),.rst_n(rst_n),.in_pixels(in_pixels),.in_valid(in_valid),.in_line(in_line),.in_frame(in_frame),
.out_sof(out_sof),.out_valid(out_valid),.out_last(out_last),.out_data(old_data));
assign out_data={8'd0,old_data};assign {stat_a,stat_b,stat_c,stat_d,stat_count,stat_sequence,stat_valid}=0;
endmodule
