module camera_ddr_capture #(parameter FRAME_BYTES=518400,FIFO_BITS=8)(
 input clk,cap_clk,rst_n,ddr_ready,sof,pixel_valid,pixel_last,input[7:0] pixel,
 output[31:0] passed_frames,failed_frames,published_frames,protocol_errors,capture_drops,
 output[26:0] paxi_awaddr,output paxi_awvalid,input paxi_awready,
 output[255:0] paxi_wdata,output[31:0] paxi_wstrb,output paxi_wvalid,paxi_wlast,input paxi_wready,
 output[26:0] paxi_araddr,output paxi_arvalid,input paxi_arready,
 input[255:0] paxi_rdata,input paxi_rvalid,paxi_rlast,output paxi_rready);
 wire[2:0] state=0;capture_check_stub u_check();
 assign passed_frames=0;assign failed_frames=0;assign published_frames=0;assign protocol_errors=0;assign capture_drops=0;
 assign paxi_awaddr=0;assign paxi_awvalid=0;assign paxi_wdata=0;assign paxi_wstrb=0;assign paxi_wvalid=0;assign paxi_wlast=1;assign paxi_araddr=0;assign paxi_arvalid=0;assign paxi_rready=1;
endmodule
module capture_check_stub;wire[2:0] state=0;endmodule
