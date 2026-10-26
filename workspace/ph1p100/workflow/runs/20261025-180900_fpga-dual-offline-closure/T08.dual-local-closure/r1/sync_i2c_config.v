// Named sync wrapper: b10 read masks/timeout, safe standby, one real I2C.
module sync_i2c_config #(parameter integer CLK_DIV=624,
 parameter integer TRANSACTION_TIMEOUT_CYCLES=200000)(
 input wire clk,rst_n,input wire [1:0] cam_mode,
 output wire scl,inout wire sda,output reg cfg_done,output reg bus_error,
 output wire [8:0] dbg_idx,output wire dbg_busy,
 input wire req_valid,input wire [15:0] req_addr,input wire [7:0] req_data,
 output wire req_ready,output reg rsp_valid,rsp_ok);
 localparam IDLE=0,LAUNCH=1,WAIT_DONE=2,FAILED=3;
 reg [1:0] state;reg [8:0] index;reg read_phase,initialized,owner_sync;
 reg core_req,error_seen;reg [31:0] write_data,timer;reg [7:0] wr_count,rd_count,expected,mask_q;
 wire [31:0] table_data;wire [7:0] table_size,read_data;wire core_busy,core_error;
 wire [23:0] safe_data=(table_data[23:8]==16'h3000 || table_data[23:8]==16'h3002)
   ? {table_data[23:8],8'h01} : table_data[23:8]==16'h30c1
   ? {16'h30c1,8'h0f} : table_data[23:0];
 ui_imx415reg table_rom(cam_mode,index,table_data,table_size);
    function [7:0] read_mask;
        input [15:0] address;
        begin
            case(address)
                16'h3000,16'h3002,16'h3003,16'h3032,16'h400C:read_mask=8'h01;
                16'h3009,16'h3022,16'h3030,16'h3031:read_mask=8'h03;
                16'h301C,16'h3026,16'h3033:read_mask=8'h0F;
                16'h3119,16'h311B,16'h4001,16'h4074:read_mask=8'h07;
                16'h3008,16'h300A,16'h300B,16'h3024,16'h3025,16'h3028,16'h3029,
                16'h3115,16'h3116,16'h3118,16'h311A,16'h311E,16'h3701,
                16'h4004,16'h4005,16'h4018,16'h4019,16'h401A,16'h401B,
                16'h401C,16'h401D,16'h401E,16'h401F,16'h4020,16'h4021,
                16'h4022,16'h4023,16'h4024,16'h4025,16'h4026,16'h4027,
                16'h4028,16'h4029:read_mask=8'hFF;
                default:read_mask=0;
            endcase
        end
    endfunction

 ui_i2c #(.WMEN_LEN(4),.RMEN_LEN(1),.CLK_DIV(CLK_DIV)) core(
 .I_clk(clk),.I_rstn(rst_n),.O_iic_scl(scl),.IO_iic_sda(sda),
 .I_wr_data(write_data),.I_wr_cnt(wr_count),.O_rd_data(read_data),.I_rd_cnt(rd_count),
 .I_iic_req(core_req),.I_iic_mode(rd_count!=0),.O_iic_busy(core_busy),
 .O_iic_bus_error(core_error),.O_iic_sda_dg());
 assign req_ready=cfg_done && state==IDLE && !core_busy;
 assign dbg_idx=index;assign dbg_busy=core_busy;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   state<=IDLE;index<=0;initialized<=0;read_phase<=0;owner_sync<=0;core_req<=0;
   error_seen<=0;write_data<=0;cfg_done<=0;bus_error<=0;rsp_valid<=0;rsp_ok<=0;
   timer<=0;wr_count<=4;rd_count<=0;expected<=0;mask_q<=0;
  end else begin
   rsp_valid<=0;
   if(core_error) begin error_seen<=1;bus_error<=1;end
   if((state==LAUNCH || state==WAIT_DONE) && timer>=TRANSACTION_TIMEOUT_CYCLES) begin
    core_req<=0;cfg_done<=0;bus_error<=1;state<=FAILED;
    if(owner_sync) begin rsp_valid<=1;rsp_ok<=0;end
   end else begin
    if(state==LAUNCH || state==WAIT_DONE) timer<=timer+1'b1;else timer<=0;
    case(state)
     IDLE: if(!initialized) begin
      if(index=={1'b0,table_size}) begin
       if(!read_phase) begin index<=0;read_phase<=1;end
       else begin initialized<=1;cfg_done<=1;end
      end else if(read_phase && read_mask(safe_data[23:8])==0) index<=index+1'b1;
      else begin
       write_data<={safe_data[7:0],safe_data[15:8],safe_data[23:16],8'h34};
       expected<=safe_data[7:0];mask_q<=read_mask(safe_data[23:8]);
       wr_count<=read_phase?3:4;rd_count<=read_phase?1:0;
       owner_sync<=0;error_seen<=0;core_req<=1;state<=LAUNCH;
      end
     end else if(req_valid && req_ready) begin
      write_data<={req_data,req_addr[7:0],req_addr[15:8],8'h34};wr_count<=4;rd_count<=0;
      owner_sync<=1;error_seen<=0;core_req<=1;state<=LAUNCH;
     end
     LAUNCH: if(core_busy) begin core_req<=0;state<=WAIT_DONE;end
     WAIT_DONE: if(!core_busy) begin
      if(owner_sync) begin rsp_valid<=1;rsp_ok<=!(error_seen||core_error);state<=IDLE;end
      else if(error_seen||core_error || (read_phase && ((read_data&mask_q)!=(expected&mask_q)))) begin
       cfg_done<=0;bus_error<=1;state<=FAILED;
      end else begin index<=index+1'b1;state<=IDLE;end
     end
     FAILED: begin core_req<=0;cfg_done<=0;end
    endcase
   end
  end
 end
endmodule
