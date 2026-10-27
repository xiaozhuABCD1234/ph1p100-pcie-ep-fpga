// Test-only RED fixture: no storage implementation.
module ddr_frame_store #(parameter FRAME_WORDS=16200)(
 input clk,rst_n,ddr_ready,
 input frame_begin,input [31:0] frame_id,output frame_begin_ready,
 input [255:0] s_data,input s_valid,s_last,s_abort,output s_ready,
 input frame_switch,output frame_switch_ready,frame_valid,output [31:0] read_frame_id,
 input rd_req,input [15:0] rd_offset,output rd_req_ready,
 output [255:0] rd_data,output rd_valid,input rd_take,
 output [31:0] published_count,error_count,drop_count,
 output [26:0] paxi_awaddr,output paxi_awvalid,input paxi_awready,
 output [255:0] paxi_wdata,output [31:0] paxi_wstrb,output paxi_wvalid,paxi_wlast,input paxi_wready,
 output [26:0] paxi_araddr,output paxi_arvalid,input paxi_arready,
 input [255:0] paxi_rdata,input paxi_rvalid,paxi_rlast,output paxi_rready
);
 assign frame_begin_ready=0,s_ready=0,frame_switch_ready=0,frame_valid=0,read_frame_id=0;
 assign rd_req_ready=0,rd_data=0,rd_valid=0,published_count=0,error_count=0,drop_count=0;
 assign paxi_awaddr=0,paxi_awvalid=0,paxi_wdata=0,paxi_wstrb=0,paxi_wvalid=0,paxi_wlast=1;
 assign paxi_araddr=0,paxi_arvalid=0,paxi_rready=1;
endmodule
