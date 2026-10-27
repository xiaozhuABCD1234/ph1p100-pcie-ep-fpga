`timescale 1ns/1ps
// RGB565 color; DATA rows and each packed pixel retain the existing2x repetition.
// A missing token blacks the rest of that video frame; restart only in blank.
module rgb565_display_pixels #(parameter SW=960,SH=540)(
 input pclk,rst_n,vs,hs,de,input[257:0] token,input token_valid,output token_ready,
 output reg request_toggle,input ack_toggle,
 output reg[23:0] rgb,output reg out_vs,out_hs,out_de,
 output reg[31:0] underflow_frames,shown_frames,output color_mode
);
 (* async_reg="true" *) reg ack1,ack2;
 reg vs_d,await_start,expected_epoch,armed,frame_bad,ever_started,blank_open,first_de,hphase;
 reg[255:0] current_word,next_word;reg current_valid,next_valid;
 reg[3:0] pixel_index;reg[15:0] last_color;
 reg[11:0] x;reg[10:0] y;
 wire vs_rise=vs&&!vs_d;
 // Force real color; no automatic grayscale mode changes.
 assign color_mode=1'b1;
 function[23:0] decode(input[15:0] code);
  begin decode={code[15:11],code[15:13],code[10:5],code[10:9],code[4:0],code[4:2]};end
 endfunction

 wire[1:0] tag=token[257:256];
 assign token_ready=!armed||frame_bad||(tag!=0)||!next_valid;
 always @(posedge pclk or negedge rst_n)begin
  if(!rst_n)begin ack1<=0;ack2<=0;end else begin ack1<=ack_toggle;ack2<=ack1;end
 end
 always @(posedge pclk or negedge rst_n)begin
  if(!rst_n)begin
   request_toggle<=0;vs_d<=0;await_start<=0;expected_epoch<=0;armed<=0;frame_bad<=0;ever_started<=0;
   blank_open<=0;first_de<=0;hphase<=0;current_word<=0;next_word<=0;current_valid<=0;next_valid<=0;
   pixel_index<=0;last_color<=0;rgb<=0;out_vs<=0;out_hs<=0;out_de<=0;underflow_frames<=0;shown_frames<=0;x<=0;y<=0;
  end else begin
   vs_d<=vs;out_vs<=vs;out_hs<=hs;out_de<=de;rgb<=0;
   if(vs_rise)begin
    armed<=0;frame_bad<=0;first_de<=0;blank_open<=1;hphase<=0;
    current_valid<=0;next_valid<=0;pixel_index<=0;x<=0;y<=0;
    await_start<=(request_toggle==ack2);
    if(request_toggle==ack2)begin request_toggle<=~request_toggle;expected_epoch<=~request_toggle;end
   end else begin
    if(token_valid&&token_ready)begin
     if(tag==1&&!de&&blank_open&&await_start&&token[32]==expected_epoch)begin
      armed<=1;await_start<=0;current_valid<=0;next_valid<=0;pixel_index<=0;
     end else if(tag==0&&armed&&!frame_bad)begin next_word<=token[255:0];next_valid<=1;end
    end
    // A second word is prefetched while the current word shifts by one16-bit pixel.
    if(!current_valid&&next_valid&&!frame_bad)begin current_word<=next_word;current_valid<=1;next_valid<=0;pixel_index<=0;end
    if(de)begin
     blank_open<=0;first_de<=1;
     if(!first_de)begin
      if(armed&&(current_valid||next_valid))ever_started<=1;
      else begin frame_bad<=1;if(ever_started)underflow_frames<=underflow_frames+1'b1;end
     end
     if(armed&&!frame_bad)begin
      hphase<=~hphase;
      if(!hphase)begin
       if(current_valid)begin
        rgb<=decode(current_word[15:0]);last_color<=current_word[15:0];current_word<={16'd0,current_word[255:16]};pixel_index<=pixel_index+1'b1;
        if(pixel_index==15)current_valid<=0;
       end else if(next_valid)begin
        rgb<=decode(next_word[15:0]);last_color<=next_word[15:0];current_word<={16'd0,next_word[255:16]};current_valid<=1;next_valid<=0;pixel_index<=1;
       end else begin frame_bad<=1;underflow_frames<=underflow_frames+1'b1;end
      end else rgb<=decode(last_color);
      if(x==SW*2-1)begin x<=0;y<=y+1'b1;if(y==SH*2-1)shown_frames<=shown_frames+1'b1;end
      else x<=x+1'b1;
     end
    end
   end
  end
 end
endmodule
