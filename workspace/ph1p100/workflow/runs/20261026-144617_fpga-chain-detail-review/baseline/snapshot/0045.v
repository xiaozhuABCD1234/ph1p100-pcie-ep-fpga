`timescale 1ns/1ps
// Source is not backpressurable. Overflow requires an ordered ABORT token before
// any later START. Footer is a separate final word, never an untagged pixel word.
module gray_frame_pack #(parameter FRAME_BYTES=518400)(
 input clk,rst_n,sof,pixel_valid,pixel_last,input[7:0] pixel,
 output reg[257:0] out_data,output reg out_valid,input out_ready,
 output reg[31:0] dropped_frames
);
 localparam [31:0] FRAME_SIZE=FRAME_BYTES;
 reg active,abort_pending,footer_pending;reg[4:0] byte_index;
 reg[31:0] sequence_id,frame_id,byte_count,crc,final_crc;
 reg[255:0] pack_data;
 function[31:0] crc_byte(input[31:0] c,input[7:0] b);
  reg[31:0] v;integer k;begin v=c^b;for(k=0;k<8;k=k+1)v=(v>>1)^(v[0]?32'hedb88320:0);crc_byte=v;end
 endfunction
 wire[31:0] next_crc=crc_byte(crc,pixel);
 always @* begin
  out_valid=0;out_data=0;
  if(abort_pending)begin out_valid=1;out_data={2'b11,256'd0};end
  else if(footer_pending)begin out_valid=1;out_data={2'b10,128'd0,FRAME_SIZE,final_crc,frame_id,32'h43524331};end
  else if(sof&&!active)begin out_valid=1;out_data={2'b01,224'd0,sequence_id+32'd1};end
  else if(!sof&&active&&pixel_valid&&byte_index==31)begin out_valid=1;out_data={2'b00,pixel,pack_data[247:0]};end
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin active<=0;abort_pending<=0;footer_pending<=0;byte_index<=0;
   sequence_id<=0;frame_id<=0;byte_count<=0;crc<=32'hffffffff;final_crc<=0;pack_data<=0;dropped_frames<=0;end
  else begin
   if(sof)sequence_id<=sequence_id+1'b1;
   if(abort_pending)begin
    if(out_ready)abort_pending<=0;
    if(sof)dropped_frames<=dropped_frames+1'b1;
   end else if(footer_pending)begin
    if(out_ready)footer_pending<=0;
    if(sof)dropped_frames<=dropped_frames+1'b1;
   end else if(sof)begin
    byte_index<=0;byte_count<=0;crc<=32'hffffffff;
    // Early SOF discards both the unfinished frame and the arriving frame.
    if(active)begin active<=0;abort_pending<=1;dropped_frames<=dropped_frames+32'd2;end
    else if(out_ready)begin active<=1;frame_id<=sequence_id+1'b1;end
    else begin active<=0;dropped_frames<=dropped_frames+1'b1;end
   end else if(active&&pixel_valid)begin
    pack_data[byte_index*8+:8]<=pixel;byte_index<=byte_index+1'b1;
    byte_count<=byte_count+1'b1;crc<=next_crc;
    if((byte_index==31&&!out_ready)||(pixel_last!=(byte_count==FRAME_BYTES-1)))begin
     active<=0;abort_pending<=1;dropped_frames<=dropped_frames+1'b1;
    end else if(pixel_last)begin active<=0;footer_pending<=1;final_crc<=~next_crc;end
   end
  end
 end
endmodule
