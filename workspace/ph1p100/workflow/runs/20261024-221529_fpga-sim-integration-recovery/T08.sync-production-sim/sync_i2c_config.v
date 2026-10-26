// Exclusive initialization / synchronous-control owner of one real ui_i2c.
// No second master is connected to the pins. Initialization table is unchanged;
// only standby, stop and output Hi-Z are held safe until the controller takes over.
module sync_i2c_config #(parameter integer CLK_DIV=624)(
 input wire clk,rst_n,input wire [1:0] cam_mode,
 output wire scl,inout wire sda,output reg cfg_done,output reg bus_error,
 output wire [8:0] dbg_idx,output wire dbg_busy,
 input wire req_valid,input wire [15:0] req_addr,input wire [7:0] req_data,
 output wire req_ready,output reg rsp_valid,rsp_ok);
 localparam IDLE=0,LAUNCH=1,WAIT_DONE=2,FAILED=3;
 reg [1:0] state;reg [8:0] index;
 reg initialized,owner_sync,core_req,error_seen;
 reg [31:0] write_data;
 wire [31:0] table_data;wire [7:0] table_size;wire core_busy,core_error;
 wire [23:0] safe_data=(table_data[23:8]==16'h3000 || table_data[23:8]==16'h3002)
   ? {table_data[23:8],8'h01} : table_data[23:8]==16'h30c1
   ? {16'h30c1,8'h0f} : table_data[23:0];
 ui_imx415reg table_rom(cam_mode,index,table_data,table_size);
 ui_i2c #(.WMEN_LEN(4),.RMEN_LEN(1),.CLK_DIV(CLK_DIV)) core(
 .I_clk(clk),.I_rstn(rst_n),.O_iic_scl(scl),.IO_iic_sda(sda),
 .I_wr_data(write_data),.I_wr_cnt(8'd4),.O_rd_data(),.I_rd_cnt(8'd0),
 .I_iic_req(core_req),.I_iic_mode(1'b0),.O_iic_busy(core_busy),
 .O_iic_bus_error(core_error),.O_iic_sda_dg());
 assign req_ready=cfg_done && state==IDLE && !core_busy;
 assign dbg_idx=index;assign dbg_busy=core_busy;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   state<=IDLE;index<=0;initialized<=0;owner_sync<=0;core_req<=0;
   error_seen<=0;write_data<=0;cfg_done<=0;bus_error<=0;rsp_valid<=0;rsp_ok<=0;
  end else begin
   rsp_valid<=0;
   if(core_error) begin error_seen<=1;bus_error<=1;end
   case(state)
    IDLE: if(!initialized) begin
      write_data<={safe_data[7:0],safe_data[15:8],safe_data[23:16],8'h34};
      owner_sync<=0;error_seen<=0;core_req<=1;state<=LAUNCH;
     end else if(req_valid && req_ready) begin
      write_data<={req_data,req_addr[7:0],req_addr[15:8],8'h34};
      owner_sync<=1;error_seen<=0;core_req<=1;state<=LAUNCH;
     end
    LAUNCH: if(core_busy) begin core_req<=0;state<=WAIT_DONE;end
    WAIT_DONE: if(!core_busy) begin
      if(owner_sync) begin rsp_valid<=1;rsp_ok<=!(error_seen||core_error);state<=IDLE;end
      else if(error_seen||core_error) state<=FAILED;
      else if(index==({1'b0,table_size}-1'b1)) begin initialized<=1;cfg_done<=1;state<=IDLE;end
      else begin index<=index+1'b1;state<=IDLE;end
     end
    FAILED: begin core_req<=0;cfg_done<=0;end
   endcase
  end
 end
endmodule
