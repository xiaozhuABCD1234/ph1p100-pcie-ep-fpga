`timescale 1ns/1ps
// A preview is speculative until the input frame's FE/CRC verdict arrives.
// START, DATA, FOOTER and ABORT share the same FIFO; no cross-domain revoke.
module rgb565_frame_pack_guarded #(parameter FRAME_BYTES=1036800)(
 input clk,rst_n,sof,pixel_valid,pixel_last,input[15:0] pixel,
 input frame_end,frame_good,frame_abort,
 output reg[257:0] out_data,output reg out_valid,input out_ready,
 output reg[31:0] dropped_frames
);
 localparam[31:0] FRAME_SIZE=FRAME_BYTES;
 reg active,preview_done,abort_pending,footer_pending;reg[3:0] pixel_index;
 reg[31:0] sequence_id,frame_id,byte_count,crc,final_crc;reg[255:0] pack_data;
 function[31:0] crc_byte(input[31:0] c,input[7:0] b);
  reg[31:0] v;integer k;begin v=c^b;for(k=0;k<8;k=k+1)v=(v>>1)^(v[0]?32'hedb88320:0);crc_byte=v;end
 endfunction
 function[31:0] add_drop(input[31:0] c,input[1:0] n);begin if(c>32'hffffffff-n)add_drop=32'hffffffff;else add_drop=c+n;end endfunction
 wire[31:0] next_crc=crc_byte(crc_byte(crc,pixel[7:0]),pixel[15:8]);
 wire sample=active&&!preview_done&&pixel_valid;
 wire invalid_sample=sample&&((pixel_index==15&&!out_ready)||(pixel_last!=(byte_count==FRAME_BYTES-2)));
 wire complete_now=sample&&pixel_last&&!invalid_sample;
 always @*begin
  out_valid=0;out_data=0;
  if(abort_pending)begin out_valid=1;out_data={2'b11,256'd0};end
  else if(footer_pending&&!frame_abort)begin out_valid=1;out_data={2'b10,128'd0,FRAME_SIZE,final_crc,frame_id,32'h43524331};end
  else if(!frame_abort&&sof&&!active)begin out_valid=1;out_data={2'b01,224'd0,sequence_id+32'd1};end
  else if(!frame_abort&&!sof&&sample&&pixel_index==15)begin out_valid=1;out_data={2'b00,pixel,pack_data[239:0]};end
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   active<=0;preview_done<=0;abort_pending<=0;footer_pending<=0;pixel_index<=0;sequence_id<=0;frame_id<=0;byte_count<=0;crc<=32'hffffffff;final_crc<=0;pack_data<=0;dropped_frames<=0;
  end else begin
   if(sof)sequence_id<=sequence_id+1'b1;
   if(frame_abort&&(active||footer_pending))begin
    active<=0;preview_done<=0;footer_pending<=0;abort_pending<=1;
    dropped_frames<=add_drop(dropped_frames,sof?2:1);
   end else if(abort_pending)begin
    if(out_ready)abort_pending<=0;
    if(sof)dropped_frames<=add_drop(dropped_frames,1);
   end else if(footer_pending)begin
    if(out_ready)footer_pending<=0;
    if(sof)dropped_frames<=add_drop(dropped_frames,1);
   end else if(sof)begin
    pixel_index<=0;byte_count<=0;crc<=32'hffffffff;preview_done<=0;
    if(active)begin active<=0;abort_pending<=1;dropped_frames<=add_drop(dropped_frames,2);end
    else if(out_ready&&!frame_abort)begin active<=1;frame_id<=sequence_id+1'b1;end
    else begin active<=0;dropped_frames<=add_drop(dropped_frames,1);end
   end else if(active)begin
    if(sample)begin
     pack_data[pixel_index*16+:16]<=pixel;pixel_index<=pixel_index+1'b1;byte_count<=byte_count+2'd2;crc<=next_crc;
     if(invalid_sample)begin active<=0;abort_pending<=1;dropped_frames<=add_drop(dropped_frames,1);end
     else if(pixel_last)begin preview_done<=1;final_crc<=~next_crc;end
    end
    if(frame_end)begin
     active<=0;
     if(!frame_good||invalid_sample||!(preview_done||complete_now))begin abort_pending<=1;dropped_frames<=add_drop(dropped_frames,1);end
     else begin footer_pending<=1;if(complete_now)final_crc<=~next_crc;end
    end
   end
  end
 end
endmodule
