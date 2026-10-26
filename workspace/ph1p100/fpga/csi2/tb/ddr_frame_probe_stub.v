// Test-only RED fixture.
module ddr_frame_probe #(parameter FRAME_WORDS=16200)(
 input clk,rst_n,ddr_ready,
 output [31:0] passed_frames,failed_words,published_frames,protocol_errors,
 output [26:0] paxi_awaddr,output paxi_awvalid,input paxi_awready,
 output [255:0] paxi_wdata,output [31:0] paxi_wstrb,output paxi_wvalid,paxi_wlast,input paxi_wready,
 output [26:0] paxi_araddr,output paxi_arvalid,input paxi_arready,
 input [255:0] paxi_rdata,input paxi_rvalid,paxi_rlast,output paxi_rready
);
 assign passed_frames=0,failed_words=0,published_frames=0,protocol_errors=0;
 assign paxi_awaddr=0,paxi_awvalid=0,paxi_wdata=0,paxi_wstrb=0,paxi_wvalid=0,paxi_wlast=1;
 assign paxi_araddr=0,paxi_arvalid=0,paxi_rready=1;
endmodule
