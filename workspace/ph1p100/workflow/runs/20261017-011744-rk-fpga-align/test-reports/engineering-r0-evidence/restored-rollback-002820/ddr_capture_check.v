`timescale 1ns/1ps
// Sequential CRC consumes every image byte; footer is checked separately.
module ddr_capture_check #(parameter FRAME_BYTES=518400)(
 input clk,rst_n,ddr_ready,
 output frame_switch,input frame_switch_ready,frame_valid,input[31:0] read_frame_id,
 output rd_req,output reg[15:0] rd_offset,input rd_req_ready,
 input[255:0] rd_data,input rd_valid,output rd_take,
 output reg[31:0] passed_frames,failed_frames
);
 localparam PAYLOAD_WORDS=FRAME_BYTES/32;
 reg[2:0] state;reg[4:0] byte_index;reg[255:0] word_buf;
 reg[31:0] crc,expected_id;reg[4:0] footer_match;
 function[31:0] crc_byte(input[31:0] c,input[7:0] b);
  reg[31:0] v;integer k;begin v=c^b;for(k=0;k<8;k=k+1)v=(v>>1)^(v[0]?32'hedb88320:0);crc_byte=v;end
 endfunction
 assign frame_switch=(state==0)&&ddr_ready;
 assign rd_req=(state==2)&&ddr_ready&&frame_valid;
 assign rd_take=(state==3)&&rd_valid;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin state<=0;rd_offset<=0;byte_index<=0;word_buf<=0;crc<=32'hffffffff;expected_id<=0;footer_match<=0;passed_frames<=0;failed_frames<=0;end
  else if(!ddr_ready||((state!=0)&&(state!=1)&&!frame_valid))begin state<=0;rd_offset<=0;crc<=32'hffffffff;end
  else case(state)
   0:begin crc<=32'hffffffff;rd_offset<=0;if(frame_switch_ready)state<=1;end
   1:begin expected_id<=read_frame_id;state<=2;end
   2:if(rd_req_ready)state<=3;
   3:if(rd_valid)begin
    if(rd_offset==PAYLOAD_WORDS)begin
     footer_match[0]<=(rd_data[31:0]==32'h43524331);
     footer_match[1]<=(rd_data[63:32]==expected_id);
     footer_match[2]<=(rd_data[95:64]==~crc);
     footer_match[3]<=(rd_data[127:96]==FRAME_BYTES);
     footer_match[4]<=(rd_data[255:128]==0);state<=5;
    end else begin word_buf<=rd_data;byte_index<=0;state<=4;end
   end
   4:begin
    crc<=crc_byte(crc,word_buf[7:0]);word_buf<={8'd0,word_buf[255:8]};byte_index<=byte_index+1'b1;
    if(byte_index==31)begin rd_offset<=rd_offset+1'b1;state<=2;end
   end
   5:begin
    if(footer_match===5'b11111)passed_frames<=passed_frames+1'b1;
    else failed_frames<=failed_frames+1'b1;
    state<=0;
   end
   default:state<=0;
  endcase
 end
endmodule
