`timescale 1ns/1ps
module camera_rgb565_display_guarded #(parameter SW=960,SH=540,CAP_FIFO_BITS=8,DISPLAY_FIFO_BITS=8)(
 input clk,cap_clk,rst_n,ddr_ready,sof,pixel_valid,pixel_last,input[15:0] pixel,
 input frame_end,frame_good,frame_abort,
 input pclk,vs,hs,de,output[23:0] rgb,output out_vs,out_hs,out_de,
 output[31:0] passed_frames,failed_frames,published_frames,protocol_errors,capture_drops,underflow_frames,shown_frames,
 output[26:0] paxi_awaddr,output paxi_awvalid,input paxi_awready,
 output[255:0] paxi_wdata,output[31:0] paxi_wstrb,output paxi_wvalid,paxi_wlast,input paxi_wready,
 output[26:0] paxi_araddr,output paxi_arvalid,input paxi_arready,
 input[255:0] paxi_rdata,input paxi_rvalid,paxi_rlast,output paxi_rready
);
 // Common reset flushes both FIFO domains and display epochs on ready loss.
 // The DDR controller must also flush its pending responses, as in store contract.
 wire run_rst_n=rst_n&&ddr_ready;
 (* async_reg="true" *) reg[1:0] cap_reset,usr_reset;
 always @(posedge cap_clk or negedge run_rst_n)if(!run_rst_n)cap_reset<=0;else cap_reset<={cap_reset[0],1'b1};
 always @(posedge clk or negedge run_rst_n)if(!run_rst_n)usr_reset<=0;else usr_reset<={usr_reset[0],1'b1};
 // Only the common asynchronous reset uses the controller's decoded ready.
 // All user-domain enables use its existing two-clock release. This keeps the
 // initialization-state decode out of wide data/counter clock-enable cones.
 // Ready loss still asserts every domain's reset without waiting for a clock.
 wire usr_ready=usr_reset[1];
 wire[257:0] token_in,fifo_token;wire token_write,token_space,fifo_valid,token_take;
 reg[257:0] token;reg token_valid;
 wire fifo_take=!token_valid;
 rgb565_frame_pack_guarded #(.FRAME_BYTES(SW*SH*2)) u_pack(.clk(cap_clk),.rst_n(cap_reset[1]),.sof(sof),.pixel_valid(pixel_valid),.pixel_last(pixel_last),.pixel(pixel),.frame_end(frame_end),.frame_good(frame_good),.frame_abort(frame_abort),.out_data(token_in),.out_valid(token_write),.out_ready(token_space),.dropped_frames(capture_drops));
 capture_async_fifo #(.WIDTH(258),.ADDR_BITS(CAP_FIFO_BITS)) u_fifo(.rst_n(run_rst_n),.wclk(cap_clk),.w_valid(token_write),.w_data(token_in),.w_ready(token_space),.rclk(clk),.r_valid(fifo_valid),.r_data(fifo_token),.r_ready(fifo_take));
 // One-word staging cuts consumer decode/ready -> FIFO ERAM read-enable timing.
 // Deliberate bubble: maximum 100M tokens/s at 200MHz, far above this preview.
 always @(posedge clk)if(!token_valid&&fifo_valid)token<=fifo_token;
 always @(posedge clk or negedge run_rst_n)begin
  if(!run_rst_n)token_valid<=0;
  else if(!usr_ready)token_valid<=0;
  else if(!token_valid&&fifo_valid)token_valid<=1;
  else if(token_valid&&token_take)token_valid<=0;
 end
 wire[1:0] tag=token[257:256];reg in_frame;
 wire begin_ready,data_ready;
 wire begin_frame=token_valid&&(tag==1)&&!in_frame&&usr_ready;
 wire abort_frame=token_valid&&((tag==3)||((tag==1)&&in_frame));
 wire data_valid=token_valid&&((tag==0)||(tag==2))&&in_frame&&usr_ready;
 assign token_take=!usr_ready?1'b1:
  (tag==1)?(!in_frame&&begin_ready):
  (tag==3)?1'b1:(!in_frame||data_ready);
 always @(posedge clk or negedge run_rst_n)begin
  if(!run_rst_n)in_frame<=0;
  else if(!usr_ready)in_frame<=0;
  else if(abort_frame)in_frame<=0;
  else if(begin_frame&&begin_ready)in_frame<=1;
  else if(data_valid&&data_ready&&tag==2)in_frame<=0;
 end
 wire frame_switch,frame_switch_ready,frame_valid,rd_req,rd_req_ready,rd_valid,rd_take;
 wire[31:0] read_frame_id,backend_drops;wire[15:0] rd_offset;wire[255:0] rd_data;
 ddr_frame_store #(.FRAME_WORDS((SW*SH)/16+1)) u_store(
  .clk(clk),.rst_n(usr_reset[1]),.ddr_ready(usr_ready),
  .frame_begin(begin_frame),.frame_id(token[31:0]),.frame_begin_ready(begin_ready),
  .s_data(token[255:0]),.s_valid(data_valid),.s_last(tag==2),.s_abort(abort_frame),.s_ready(data_ready),
  .frame_switch(frame_switch),.frame_switch_ready(frame_switch_ready),.frame_valid(frame_valid),.read_frame_id(read_frame_id),
  .rd_req(rd_req),.rd_offset(rd_offset),.rd_req_ready(rd_req_ready),.rd_data(rd_data),.rd_valid(rd_valid),.rd_take(rd_take),
  .published_count(published_frames),.error_count(protocol_errors),.drop_count(backend_drops),
  .paxi_awaddr(paxi_awaddr),.paxi_awvalid(paxi_awvalid),.paxi_awready(paxi_awready),
  .paxi_wdata(paxi_wdata),.paxi_wstrb(paxi_wstrb),.paxi_wvalid(paxi_wvalid),.paxi_wlast(paxi_wlast),.paxi_wready(paxi_wready),
  .paxi_araddr(paxi_araddr),.paxi_arvalid(paxi_arvalid),.paxi_arready(paxi_arready),
  .paxi_rdata(paxi_rdata),.paxi_rvalid(paxi_rvalid),.paxi_rlast(paxi_rlast),.paxi_rready(paxi_rready));
 wire request_toggle,ack_toggle;wire[257:0] display_in,display_out;
 wire display_write,display_space,display_valid,display_take;
 rgb565_display_read #(.SW(SW),.SH(SH)) u_reader(
 .clk(clk),.rst_n(usr_reset[1]),.ddr_ready(usr_ready),.request_toggle(request_toggle),.ack_toggle(ack_toggle),
 .frame_switch(frame_switch),.frame_switch_ready(frame_switch_ready),.frame_valid(frame_valid),.read_frame_id(read_frame_id),
 .rd_req(rd_req),.rd_offset(rd_offset),.rd_req_ready(rd_req_ready),.rd_data(rd_data),.rd_valid(rd_valid),.rd_take(rd_take),
 .token(display_in),.token_valid(display_write),.token_ready(display_space),.passed_frames(passed_frames),.failed_frames(failed_frames));
 capture_async_fifo #(.WIDTH(258),.ADDR_BITS(DISPLAY_FIFO_BITS)) u_display_fifo(
 .rst_n(run_rst_n),.wclk(clk),.w_valid(display_write),.w_data(display_in),.w_ready(display_space),
 .rclk(pclk),.r_valid(display_valid),.r_data(display_out),.r_ready(display_take));
 (* async_reg="true" *) reg[1:0] pixel_reset;
 always @(posedge pclk or negedge run_rst_n)if(!run_rst_n)pixel_reset<=0;else pixel_reset<={pixel_reset[0],1'b1};
 rgb565_display_pixels #(.SW(SW),.SH(SH)) u_pixels(
 .pclk(pclk),.rst_n(pixel_reset[1]),.vs(vs),.hs(hs),.de(de),.token(display_out),.token_valid(display_valid),.token_ready(display_take),
 .request_toggle(request_toggle),.ack_toggle(ack_toggle),.rgb(rgb),.out_vs(out_vs),.out_hs(out_hs),.out_de(out_de),
 .underflow_frames(underflow_frames),.shown_frames(shown_frames),.color_mode());
endmodule
