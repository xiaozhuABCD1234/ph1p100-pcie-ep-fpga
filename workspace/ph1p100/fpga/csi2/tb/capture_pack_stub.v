module gray_frame_pack #(parameter FRAME_BYTES=518400)(input clk,rst_n,sof,pixel_valid,pixel_last,input[7:0] pixel,output[257:0] out_data,output out_valid,input out_ready,output[31:0] dropped_frames);
 assign out_data=0;assign out_valid=0;assign dropped_frames=0;
endmodule
module capture_async_fifo #(parameter WIDTH=258,ADDR_BITS=8)(input rst_n,wclk,w_valid,input[WIDTH-1:0] w_data,output w_ready,input rclk,output r_valid,output[WIDTH-1:0] r_data,input r_ready);
 assign w_ready=1;assign r_valid=0;assign r_data=0;
endmodule
