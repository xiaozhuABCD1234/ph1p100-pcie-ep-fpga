`timescale 1ns/1ps
// Board-independent full-frame exerciser, same backend intended for camera data.
module ddr_frame_probe #(parameter FRAME_WORDS=16200)(
 input clk,rst_n,ddr_ready,
 output reg [31:0] passed_frames,failed_words,output [31:0] published_frames,protocol_errors,
 output [26:0] paxi_awaddr,output paxi_awvalid,input paxi_awready,
 output [255:0] paxi_wdata,output [31:0] paxi_wstrb,output paxi_wvalid,paxi_wlast,input paxi_wready,
 output [26:0] paxi_araddr,output paxi_arvalid,input paxi_arready,
 input [255:0] paxi_rdata,input paxi_rvalid,paxi_rlast,output paxi_rready
);
 localparam OFFSET_BITS=(FRAME_WORDS>65536)?$clog2(FRAME_WORDS):16;
 reg sending;reg [31:0] source_id;reg [OFFSET_BITS-1:0] source_offset;
 wire begin_ready,stream_ready,switch_ready,frame_valid,rd_req_ready,rd_valid;
 wire [31:0] read_frame_id,drop_count;
 wire [255:0] rd_data;
 reg [1:0] read_state;reg [OFFSET_BITS-1:0] read_offset;reg bad_frame;
 reg [7:0] word_match;
 localparam WAIT_FRAME=0,REQUEST=1,RESPONSE=2,CHECK=3;
 function [255:0] pattern(input [31:0] fid,input [OFFSET_BITS-1:0] offset);
   integer lane;begin
     for(lane=0;lane<8;lane=lane+1)
       pattern[lane*32+:32]=(fid<<16)^({{(32-OFFSET_BITS){1'b0}},offset}<<8)^(32'h12340000+lane);
   end
 endfunction
 wire [255:0] expected_word=pattern(read_frame_id,read_offset);
 wire mismatch=(word_match!=8'hff);
 ddr_frame_store #(.FRAME_WORDS(FRAME_WORDS),.OFFSET_BITS(OFFSET_BITS)) u_store(
   .clk(clk),.rst_n(rst_n),.ddr_ready(ddr_ready),
   .frame_begin(!sending),.frame_id(source_id),.frame_begin_ready(begin_ready),
   .s_data(pattern(source_id,source_offset)),.s_valid(sending),.s_last(source_offset==FRAME_WORDS-1),.s_abort(1'b0),.s_ready(stream_ready),
   .frame_switch(read_state==WAIT_FRAME),.frame_switch_ready(switch_ready),.frame_valid(frame_valid),.read_frame_id(read_frame_id),
   .rd_req(read_state==REQUEST),.rd_offset(read_offset),.rd_req_ready(rd_req_ready),
   .rd_data(rd_data),.rd_valid(rd_valid),.rd_take(read_state==RESPONSE),
   .published_count(published_frames),.error_count(protocol_errors),.drop_count(drop_count),
   .paxi_awaddr(paxi_awaddr),.paxi_awvalid(paxi_awvalid),.paxi_awready(paxi_awready),
   .paxi_wdata(paxi_wdata),.paxi_wstrb(paxi_wstrb),.paxi_wvalid(paxi_wvalid),.paxi_wlast(paxi_wlast),.paxi_wready(paxi_wready),
   .paxi_araddr(paxi_araddr),.paxi_arvalid(paxi_arvalid),.paxi_arready(paxi_arready),
   .paxi_rdata(paxi_rdata),.paxi_rvalid(paxi_rvalid),.paxi_rlast(paxi_rlast),.paxi_rready(paxi_rready));
 integer group_index;
 always @(posedge clk or negedge rst_n)begin
   if(!rst_n)begin
     sending<=0;source_id<=1;source_offset<=0;
     read_state<=WAIT_FRAME;read_offset<=0;bad_frame<=0;word_match<=0;passed_frames<=0;failed_words<=0;
   end else if(!ddr_ready)begin
     sending<=0;source_offset<=0;read_state<=WAIT_FRAME;read_offset<=0;bad_frame<=0;
   end else begin
     if(!sending&&begin_ready)begin sending<=1;source_offset<=0;end
     if(sending&&stream_ready)begin
       if(source_offset==FRAME_WORDS-1)begin sending<=0;source_id<=source_id+1'b1;end
       else source_offset<=source_offset+1'b1;
     end
     case(read_state)
       WAIT_FRAME:if(switch_ready)begin read_state<=REQUEST;read_offset<=0;bad_frame<=0;end
       REQUEST:if(rd_req_ready)read_state<=RESPONSE;
       RESPONSE:if(rd_valid)begin
         // Register partial comparisons before the error/pass counter enables.
         for(group_index=0;group_index<8;group_index=group_index+1)
           word_match[group_index]<=(rd_data[group_index*32+:32]===expected_word[group_index*32+:32]);
         read_state<=CHECK;
       end
       CHECK:begin
         if(mismatch)begin failed_words<=failed_words+1'b1;bad_frame<=1;end
         if(read_offset==FRAME_WORDS-1)begin
           if(!bad_frame&&!mismatch)passed_frames<=passed_frames+1'b1;
           read_state<=WAIT_FRAME;
         end else begin read_offset<=read_offset+1'b1;read_state<=REQUEST;end
       end
       default:read_state<=WAIT_FRAME;
     endcase
     // A malformed ordinary response invalidates the reader in the backend.
     if(read_state!=WAIT_FRAME&&!frame_valid)begin read_state<=WAIT_FRAME;bad_frame<=1;end
   end
 end
endmodule
