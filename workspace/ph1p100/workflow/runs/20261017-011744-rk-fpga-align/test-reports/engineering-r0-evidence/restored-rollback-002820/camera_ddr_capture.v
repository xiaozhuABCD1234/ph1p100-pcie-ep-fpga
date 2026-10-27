`timescale 1ns/1ps
module camera_ddr_capture #(parameter FRAME_BYTES=518400,FIFO_BITS=8)(
 input clk,cap_clk,rst_n,ddr_ready,sof,pixel_valid,pixel_last,input[7:0] pixel,
 output[31:0] passed_frames,failed_frames,published_frames,protocol_errors,capture_drops,
 output[26:0] paxi_awaddr,output paxi_awvalid,input paxi_awready,
 output[255:0] paxi_wdata,output[31:0] paxi_wstrb,output paxi_wvalid,paxi_wlast,input paxi_wready,
 output[26:0] paxi_araddr,output paxi_arvalid,input paxi_arready,
 input[255:0] paxi_rdata,input paxi_rvalid,paxi_rlast,output paxi_rready
);
 (* async_reg="true" *) reg[1:0] cap_reset,usr_reset;
 always @(posedge cap_clk or negedge rst_n)if(!rst_n)cap_reset<=0;else cap_reset<={cap_reset[0],1'b1};
 always @(posedge clk or negedge rst_n)if(!rst_n)usr_reset<=0;else usr_reset<={usr_reset[0],1'b1};
 wire[257:0] token_in,fifo_token;wire token_write,token_space,fifo_valid,token_take;
 reg[257:0] token;reg token_valid;
 wire fifo_take=!token_valid;
 gray_frame_pack #(.FRAME_BYTES(FRAME_BYTES)) u_pack(.clk(cap_clk),.rst_n(cap_reset[1]),.sof(sof),.pixel_valid(pixel_valid),.pixel_last(pixel_last),.pixel(pixel),.out_data(token_in),.out_valid(token_write),.out_ready(token_space),.dropped_frames(capture_drops));
 capture_async_fifo #(.WIDTH(258),.ADDR_BITS(FIFO_BITS)) u_fifo(.rst_n(rst_n),.wclk(cap_clk),.w_valid(token_write),.w_data(token_in),.w_ready(token_space),.rclk(clk),.r_valid(fifo_valid),.r_data(fifo_token),.r_ready(fifo_take));
 // One-word staging cuts consumer decode/ready -> FIFO ERAM read-enable timing.
 // Deliberate bubble: maximum 100M tokens/s at 200MHz, far above this preview.
 always @(posedge clk)if(!token_valid&&fifo_valid)token<=fifo_token;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)token_valid<=0;
  else if(!usr_reset[1]||!ddr_ready)token_valid<=0;
  else if(!token_valid&&fifo_valid)token_valid<=1;
  else if(token_valid&&token_take)token_valid<=0;
 end
 wire[1:0] tag=token[257:256];reg in_frame;
 wire begin_ready,data_ready;
 wire begin_frame=token_valid&&(tag==1)&&!in_frame&&ddr_ready;
 wire abort_frame=token_valid&&((tag==3)||((tag==1)&&in_frame));
 wire data_valid=token_valid&&((tag==0)||(tag==2))&&in_frame&&ddr_ready;
 assign token_take=!ddr_ready?1'b1:
  (tag==1)?(!in_frame&&begin_ready):
  (tag==3)?1'b1:(!in_frame||data_ready);
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)in_frame<=0;
  else if(!usr_reset[1]||!ddr_ready)in_frame<=0;
  else if(abort_frame)in_frame<=0;
  else if(begin_frame&&begin_ready)in_frame<=1;
  else if(data_valid&&data_ready&&tag==2)in_frame<=0;
 end
 wire frame_switch,frame_switch_ready,frame_valid,rd_req,rd_req_ready,rd_valid,rd_take;
 wire[31:0] read_frame_id,backend_drops;wire[15:0] rd_offset;wire[255:0] rd_data;
 ddr_frame_store #(.FRAME_WORDS(FRAME_BYTES/32+1)) u_store(
  .clk(clk),.rst_n(usr_reset[1]),.ddr_ready(ddr_ready),
  .frame_begin(begin_frame),.frame_id(token[31:0]),.frame_begin_ready(begin_ready),
  .s_data(token[255:0]),.s_valid(data_valid),.s_last(tag==2),.s_abort(abort_frame),.s_ready(data_ready),
  .frame_switch(frame_switch),.frame_switch_ready(frame_switch_ready),.frame_valid(frame_valid),.read_frame_id(read_frame_id),
  .rd_req(rd_req),.rd_offset(rd_offset),.rd_req_ready(rd_req_ready),.rd_data(rd_data),.rd_valid(rd_valid),.rd_take(rd_take),
  .published_count(published_frames),.error_count(protocol_errors),.drop_count(backend_drops),
  .paxi_awaddr(paxi_awaddr),.paxi_awvalid(paxi_awvalid),.paxi_awready(paxi_awready),
  .paxi_wdata(paxi_wdata),.paxi_wstrb(paxi_wstrb),.paxi_wvalid(paxi_wvalid),.paxi_wlast(paxi_wlast),.paxi_wready(paxi_wready),
  .paxi_araddr(paxi_araddr),.paxi_arvalid(paxi_arvalid),.paxi_arready(paxi_arready),
  .paxi_rdata(paxi_rdata),.paxi_rvalid(paxi_rvalid),.paxi_rlast(paxi_rlast),.paxi_rready(paxi_rready));
 ddr_capture_check #(.FRAME_BYTES(FRAME_BYTES)) u_check(
  .clk(clk),.rst_n(usr_reset[1]),.ddr_ready(ddr_ready),.frame_switch(frame_switch),.frame_switch_ready(frame_switch_ready),.frame_valid(frame_valid),.read_frame_id(read_frame_id),
  .rd_req(rd_req),.rd_offset(rd_offset),.rd_req_ready(rd_req_ready),.rd_data(rd_data),.rd_valid(rd_valid),.rd_take(rd_take),.passed_frames(passed_frames),.failed_frames(failed_frames));
endmodule
