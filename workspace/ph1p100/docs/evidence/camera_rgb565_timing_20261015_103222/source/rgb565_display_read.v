`timescale 1ns/1ps
// One display request per VS. Stop an old stream and drain any accepted read
// before changing slot ownership. Read each source row twice; CRC only first copy.
module rgb565_display_read #(parameter SW=960,SH=540)(
 input clk,rst_n,ddr_ready,request_toggle,output reg ack_toggle,
 output frame_switch,input frame_switch_ready,frame_valid,input[31:0] read_frame_id,
 output rd_req,output reg[15:0] rd_offset,input rd_req_ready,
 input[255:0] rd_data,input rd_valid,output rd_take,
 output[257:0] token,output token_valid,input token_ready,
 output reg[31:0] passed_frames,failed_frames
);
 localparam ROW_WORDS=SW/16,PAYLOAD_WORDS=SW*SH/16;
 localparam IDLE=0,DRAIN=1,SWITCH=2,LATCH=3,FOOT_REQ=4,FOOT_WAIT=5,START=6,
 DATA_REQ=7,DATA_WAIT=8,SEND=9,CRC=10,NEXT=11,CHECK=12,END=13;
 reg[3:0] state;reg seen,pending_read,row_repeat;
 (* async_reg="true" *) reg rq1,rq2;
 reg[31:0] frame_id,crc,expected_crc;reg[4:0] footer_match,byte_index;
 reg[255:0] word_buf,crc_word;reg[15:0] row_base,col_word,row;
 wire fresh_request=(rq2!=seen);
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin rq1<=0;rq2<=0;end else begin rq1<=request_toggle;rq2<=rq1;end
 end
 function[31:0] crc_byte(input[31:0] c,input[7:0] b);
  reg[31:0] v;integer k;begin v=c^b;for(k=0;k<8;k=k+1)v=(v>>1)^(v[0]?32'hedb88320:0);crc_byte=v;end
 endfunction
 assign frame_switch=(state==SWITCH)&&frame_switch_ready&&!fresh_request&&ddr_ready;
 assign rd_req=((state==FOOT_REQ)||(state==DATA_REQ))&&!fresh_request&&ddr_ready&&frame_valid;
 assign rd_take=rd_valid&&((state==FOOT_WAIT)||(state==DATA_WAIT)||(state==DRAIN)||fresh_request);
 assign token_valid=((state==START)||(state==SEND)||(state==END))&&!fresh_request&&ddr_ready;
 assign token=(state==START)?{2'd1,223'd0,seen,frame_id}:
              (state==END)?{2'd2,224'd0,frame_id}:{2'd0,word_buf};
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin state<=IDLE;seen<=0;ack_toggle<=0;pending_read<=0;rd_offset<=0;row_repeat<=0;
   frame_id<=0;crc<=32'hffffffff;expected_crc<=0;footer_match<=0;byte_index<=0;
   word_buf<=0;crc_word<=0;row_base<=0;col_word<=0;row<=0;passed_frames<=0;failed_frames<=0;end
  else if(!ddr_ready)begin state<=IDLE;seen<=rq2;ack_toggle<=rq2;pending_read<=0;end
  else begin
   if(rd_req&&rd_req_ready)pending_read<=1;
   if(rd_take)pending_read<=0;
   // Store consumes an invalid RLAST itself, cancels ownership and produces no
   // rd_valid. frame_valid low confirms there is no pending consumer response.
   if(!frame_valid)pending_read<=0;
   if(fresh_request)begin seen<=rq2;state<=DRAIN;end
   else if(!frame_valid&&state!=IDLE&&state!=DRAIN&&state!=SWITCH&&state!=LATCH)begin
    state<=IDLE;ack_toggle<=seen;
   end
   else case(state)
    IDLE:begin end
    DRAIN:if(!pending_read&&!rd_valid)state<=SWITCH;
    SWITCH:begin
     if(frame_switch_ready||frame_valid)state<=LATCH;
     else begin ack_toggle<=seen;state<=IDLE;end
    end
    LATCH:begin frame_id<=read_frame_id;rd_offset<=PAYLOAD_WORDS;state<=FOOT_REQ;end
    FOOT_REQ:if(rd_req_ready)state<=FOOT_WAIT;
    FOOT_WAIT:if(rd_valid)begin
     footer_match[0]<=(rd_data[31:0]==32'h43524331);
     footer_match[1]<=(rd_data[63:32]==frame_id);
     footer_match[2]<=(rd_data[127:96]==SW*SH*2);
     footer_match[3]<=(rd_data[255:128]==0);footer_match[4]<=1;
     expected_crc<=rd_data[95:64];state<=START;
    end
    START:if(token_ready)begin
     ack_toggle<=seen;rd_offset<=0;row_base<=0;col_word<=0;row<=0;row_repeat<=0;crc<=32'hffffffff;state<=DATA_REQ;
    end
    DATA_REQ:if(rd_req_ready)state<=DATA_WAIT;
    DATA_WAIT:if(rd_valid)begin word_buf<=rd_data;state<=SEND;end
    SEND:if(token_ready)begin
     if(!row_repeat)begin crc_word<=word_buf;byte_index<=0;state<=CRC;end else state<=NEXT;
    end
    CRC:begin
     crc<=crc_byte(crc_byte(crc,crc_word[7:0]),crc_word[15:8]);crc_word<={16'd0,crc_word[255:16]};byte_index<=byte_index+2'd2;
     if(byte_index==30)state<=NEXT;
    end
    NEXT:begin
     if(col_word==ROW_WORDS-1)begin
      col_word<=0;
      if(!row_repeat)begin row_repeat<=1;rd_offset<=row_base;state<=DATA_REQ;end
      else if(row==SH-1)state<=CHECK;
      else begin row<=row+1'b1;row_repeat<=0;row_base<=row_base+ROW_WORDS;rd_offset<=row_base+ROW_WORDS;state<=DATA_REQ;end
     end else begin col_word<=col_word+1'b1;rd_offset<=rd_offset+1'b1;state<=DATA_REQ;end
    end
    CHECK:begin
     if(footer_match===5'b11111&&expected_crc==~crc)passed_frames<=passed_frames+1'b1;
     else failed_frames<=failed_frames+1'b1;
     state<=END;
    end
    END:if(token_ready)state<=IDLE;
    default:state<=IDLE;
   endcase
  end
 end
endmodule
