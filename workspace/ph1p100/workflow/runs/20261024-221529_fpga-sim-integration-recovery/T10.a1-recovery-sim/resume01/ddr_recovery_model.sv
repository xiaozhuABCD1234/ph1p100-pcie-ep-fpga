`timescale 1ns/1ps
// Native single-beat paired AW/W model. DUT reset gates new acceptance only.
// Memory, pending AR and held R survive DUT reset: no DDR reset is in this port.
module ddr_recovery_model(
 input clk, dut_rst_n, stall_write, input [31:0] read_delay,
 input [31:0] epoch, awaddr, input awvalid, output awready,
 input [255:0] wdata, input wvalid, output wready,
 input [31:0] araddr, input arvalid, output arready,
 output reg [255:0] rdata, output reg rvalid, input rready,
 output reg pending, output reg [31:0] response_epoch,
 output reg [31:0] aw_count, w_count, ar_count, r_count, old_r_count
);
 reg [255:0] mem[0:262143];
 reg [255:0] pending_data;
 reg [31:0] wait_left, tick, request_epoch;
 assign awready=dut_rst_n && !stall_write && (tick%5 != 0);
 assign wready=awready;
 assign arready=dut_rst_n && !pending && !rvalid && (tick%3 != 0);
 initial begin
  tick=0; pending=0; rvalid=0; rdata=0; response_epoch=0;
  request_epoch=0; wait_left=0; pending_data=0;
  aw_count=0; w_count=0; ar_count=0; r_count=0; old_r_count=0;
 end
 always @(posedge clk) begin
  tick<=tick+1;
  if(awvalid&&awready&&wvalid&&wready) begin
   if(awaddr>=262144) $fatal(1,"DDR_ADDRESS_RANGE");
   mem[awaddr]<=wdata; aw_count<=aw_count+1; w_count<=w_count+1;
  end
  if(arvalid&&arready) begin
   if(araddr>=262144) $fatal(1,"DDR_ADDRESS_RANGE");
   pending<=1; pending_data<=mem[araddr]; request_epoch<=epoch;
   wait_left<=read_delay; ar_count<=ar_count+1;
  end else if(pending) begin
   if(wait_left==0) begin
    pending<=0; rvalid<=1; rdata<=pending_data; response_epoch<=request_epoch;
   end else wait_left<=wait_left-1;
  end
  if(rvalid&&rready) begin
   rvalid<=0; r_count<=r_count+1;
   if(response_epoch!=epoch) old_r_count<=old_r_count+1;
  end
 end
endmodule
