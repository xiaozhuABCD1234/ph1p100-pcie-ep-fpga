`timescale 1ns/1ps
// RGB332 diagnostic; DATA rows and each packed pixel retain the existing2x repetition.
// A missing token blacks the rest of that video frame; restart only in blank.
module rgb332_display_pixels #(parameter SW=960,SH=540,FRAMES_PER_MODE=480)(
 input pclk,rst_n,vs,hs,de,input[257:0] token,input token_valid,output token_ready,
 output reg request_toggle,input ack_toggle,
 output reg[23:0] rgb,output reg out_vs,out_hs,out_de,
 output reg[31:0] underflow_frames,shown_frames,output reg color_mode
);
 (* async_reg="true" *) reg ack1,ack2;
 reg vs_d,await_start,expected_epoch,armed,frame_bad,ever_started,blank_open,first_de,hphase;
 reg[255:0] current_word,next_word;reg current_valid,next_valid;
 reg[4:0] byte_index;reg[7:0] last_gray;
 reg[11:0] x;reg[10:0] y;
 wire vs_rise=vs&&!vs_d;
 localparam COUNT_BITS=(FRAMES_PER_MODE>1)?$clog2(FRAMES_PER_MODE):1;
 reg[COUNT_BITS-1:0] mode_frames;
 // Both views use the same quantized color payload. This is not original Gray8.
 function[23:0] decode(input[7:0] code,input color);
  reg[7:0] r,g,b;reg[9:0] sum;
  begin
   r={code[7:5],code[7:5],code[7:6]};
   g={code[4:2],code[4:2],code[4:3]};b={4{code[1:0]}};
   sum={2'b0,r}+{1'b0,g,1'b0}+{2'b0,b};
   decode=color?{r,g,b}:{3{sum[9:2]}};
  end
 endfunction
 always @(posedge pclk or negedge rst_n)begin
  if(!rst_n)begin color_mode<=1;mode_frames<=0;end
  else if(vs_rise&&!de)begin
   if(mode_frames==FRAMES_PER_MODE-1)begin mode_frames<=0;color_mode<=~color_mode;end
   else mode_frames<=mode_frames+1'b1;
  end
 end

 wire[1:0] tag=token[257:256];
 assign token_ready=!armed||frame_bad||(tag!=0)||!next_valid;
 always @(posedge pclk or negedge rst_n)begin
  if(!rst_n)begin ack1<=0;ack2<=0;end else begin ack1<=ack_toggle;ack2<=ack1;end
 end
 always @(posedge pclk or negedge rst_n)begin
  if(!rst_n)begin
   request_toggle<=0;vs_d<=0;await_start<=0;expected_epoch<=0;armed<=0;frame_bad<=0;ever_started<=0;
   blank_open<=0;first_de<=0;hphase<=0;current_word<=0;next_word<=0;current_valid<=0;next_valid<=0;
   byte_index<=0;last_gray<=0;rgb<=0;out_vs<=0;out_hs<=0;out_de<=0;underflow_frames<=0;shown_frames<=0;x<=0;y<=0;
  end else begin
   vs_d<=vs;out_vs<=vs;out_hs<=hs;out_de<=de;rgb<=0;
   if(vs_rise)begin
    armed<=0;frame_bad<=0;first_de<=0;blank_open<=1;hphase<=0;
    current_valid<=0;next_valid<=0;byte_index<=0;x<=0;y<=0;
    await_start<=(request_toggle==ack2);
    if(request_toggle==ack2)begin request_toggle<=~request_toggle;expected_epoch<=~request_toggle;end
   end else begin
    if(token_valid&&token_ready)begin
     if(tag==1&&!de&&blank_open&&await_start&&token[32]==expected_epoch)begin
      armed<=1;await_start<=0;current_valid<=0;next_valid<=0;byte_index<=0;
     end else if(tag==0&&armed&&!frame_bad)begin next_word<=token[255:0];next_valid<=1;end
    end
    // A second word is prefetched while the current word shifts by a fixed byte.
    if(!current_valid&&next_valid&&!frame_bad)begin current_word<=next_word;current_valid<=1;next_valid<=0;byte_index<=0;end
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
        rgb<=decode(current_word[7:0],color_mode);last_gray<=current_word[7:0];current_word<={8'd0,current_word[255:8]};byte_index<=byte_index+1'b1;
        if(byte_index==31)current_valid<=0;
       end else if(next_valid)begin
        rgb<=decode(next_word[7:0],color_mode);last_gray<=next_word[7:0];current_word<={8'd0,next_word[255:8]};current_valid<=1;next_valid<=0;byte_index<=1;
       end else begin frame_bad<=1;underflow_frames<=underflow_frames+1'b1;end
      end else rgb<=decode(last_gray,color_mode);
      if(x==SW*2-1)begin x<=0;y<=y+1'b1;if(y==SH*2-1)shown_frames<=shown_frames+1'b1;end
      else x<=x+1'b1;
     end
    end
   end
  end
 end
endmodule
