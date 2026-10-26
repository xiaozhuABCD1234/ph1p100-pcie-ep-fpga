
/*******************************MILIANKE*******************************
*Company : MiLianKe Electronic Technology Co., Ltd.
*WebSite:https://www.milianke.com
*TechWeb:https://www.uisrc.com
*tmall-shop:https://milianke.tmall.com
*jd-shop:https://milianke.jd.com
*taobao-shop1: https://milianke.taobao.com
*Create Date: 2023/08/07
*Module Name:key
*File Name:key.v
*Description: 
*The reference demo provided by Milianke is only used for learning. 
*We cannot ensure that the demo itself is free of bugs, so users 
*should be responsible for the technical problems and consequences
*caused by the use of their own products.
*Copyright: Copyright (c) MiLianKe
*All rights reserved.
*Revision: 1.0
*Signal description
*1) I_ input
*2) O_ output
*3) IO_ input output
*4) S_ system internal signal
*5) _n activ low
*6) _dg debug signal 
*7) _r delay or register
*8) _s state mechine
*********************************************************************/
/*********ui_cfg_imx415 IIC控制模块 ***********
--版本�?1.0
*********************************************************************/

module ui_cfg_imx415 #(
    parameter CLK_DIV=16'd499,
    parameter START_WAIT_CYCLES=1000, // 20 us at 50 MHz, Sony p85 T4
    parameter STANDBY_WAIT_CYCLES=1200000, // 24 ms, Sony p89
    parameter TRANSACTION_TIMEOUT_CYCLES=200000
)(input wire I_clk,input wire I_rst_n,input wire [1:0] I_cam_mode,
  input wire I_ae_req,input wire [7:0] I_ae_data,
  output wire O_cam_scl,inout wire IO_cam_sda,
  output reg O_cfg_done,output reg O_ae_cfg_done,output reg O_bus_error);
    localparam WAIT_START=0,PREPARE=1,WAIT_BUSY=2,WAIT_DONE=3,WAIT_STANDBY=4,READY=5,FAILED=6;
    localparam WRITE_TABLE=0,READ_TABLE=1,CANCEL_STANDBY=2,START_MASTER=3,WRITE_GAIN=4;
    reg [2:0] state=WAIT_START,phase=WRITE_TABLE;
    reg [7:0] index=0;
    reg [31:0] timer=0,wr_data=0;
    reg request=0;
    reg [7:0] wr_count=4,rd_count=0,expected=0,mask=0;
    wire [31:0] table_word;
    wire [7:0] table_size,read_data;
    wire bus_busy,bus_error;
    reg [1:0] busy_sync=0,error_sync=0;
    always @(posedge I_clk or negedge I_rst_n)
        if(!I_rst_n) begin busy_sync<=0;error_sync<=0;end
        else begin busy_sync<={busy_sync[0],bus_busy};error_sync<={error_sync[0],bus_error};end
    ui_imx415reg X_ui_imx415reg(.MODE(I_cam_mode),.REG_INDEX({1'b0,index}),.REG_DATA(table_word),.REG_SIZE(table_size));
    // Only documented mode/control registers are read back. Reserved tuning registers are written, not compared.
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
    ui_i2c #(.WMEN_LEN(4),.RMEN_LEN(1),.CLK_DIV(CLK_DIV)) X_ui_i2c
      (.I_clk(I_clk),.I_rstn(I_rst_n && !O_bus_error),.O_iic_scl(O_cam_scl),.IO_iic_sda(IO_cam_sda),
       .I_wr_data(wr_data),.I_wr_cnt(wr_count),.O_rd_data(read_data),.I_rd_cnt(rd_count),
       .I_iic_mode(rd_count!=0),.I_iic_req(request),.O_iic_busy(bus_busy),
       .O_iic_bus_error(bus_error),.O_iic_sda_dg());
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            state<=WAIT_START;phase<=WRITE_TABLE;index<=0;timer<=0;request<=0;
            wr_data<=0;wr_count<=4;rd_count<=0;expected<=0;mask<=0;
            O_cfg_done<=0;O_ae_cfg_done<=1;O_bus_error<=0;
        end else if(I_cam_mode!=2'd1 || error_sync[1] ||
                    ((state==WAIT_BUSY || state==WAIT_DONE) && timer>=TRANSACTION_TIMEOUT_CYCLES)) begin
            state<=FAILED;request<=0;O_cfg_done<=0;O_ae_cfg_done<=0;O_bus_error<=1;
        end else case(state)
            WAIT_START:begin
                if(timer>=START_WAIT_CYCLES-1) begin timer<=0;state<=PREPARE;end
                else timer<=timer+1'b1;
            end
            PREPARE:begin
                timer<=0;rd_count<=0;wr_count<=4;
                if(phase==WRITE_TABLE && index==table_size) begin phase<=READ_TABLE;index<=0;end
                else if(phase==READ_TABLE && index==table_size) begin phase<=CANCEL_STANDBY;index<=0;end
                else if(phase==READ_TABLE && read_mask(table_word[23:8])==0) index<=index+1'b1;
                else begin
                    if(phase==WRITE_TABLE || phase==READ_TABLE) begin
                        wr_data<={table_word[7:0],table_word[15:8],table_word[23:16],8'h34};
                        expected<=table_word[7:0];mask<=read_mask(table_word[23:8]);
                        if(phase==READ_TABLE) begin wr_count<=3;rd_count<=1;end
                    end else if(phase==CANCEL_STANDBY) wr_data<=32'h00003034; // 3000=00
                    else if(phase==START_MASTER) wr_data<=32'h00023034; // 3002=00
                    else wr_data<={I_ae_data,8'h90,8'h30,8'h34};
                    request<=1;state<=WAIT_BUSY;
                end
            end
            WAIT_BUSY:begin
                timer<=timer+1'b1;
                if(busy_sync[1]) begin request<=0;state<=WAIT_DONE;end
            end
            WAIT_DONE:begin
                timer<=timer+1'b1;
                if(!busy_sync[1]) begin
                    timer<=0;
                    if(phase==READ_TABLE && (read_data & mask)!=(expected & mask)) begin
                        state<=FAILED;O_bus_error<=1;O_cfg_done<=0;O_ae_cfg_done<=0;
                    end else if(phase==CANCEL_STANDBY) state<=WAIT_STANDBY;
                    else if(phase==START_MASTER) begin O_cfg_done<=1;state<=READY;end
                    else if(phase==WRITE_GAIN) begin O_ae_cfg_done<=1;state<=READY;end
                    else begin index<=index+1'b1;state<=PREPARE;end
                end
            end
            WAIT_STANDBY:begin
                if(timer>=STANDBY_WAIT_CYCLES-1) begin phase<=START_MASTER;timer<=0;state<=PREPARE;end
                else timer<=timer+1'b1;
            end
            READY:if(I_ae_req) begin phase<=WRITE_GAIN;O_ae_cfg_done<=0;state<=PREPARE;end
            FAILED:begin request<=0;O_bus_error<=1;O_cfg_done<=0;end
            default:begin state<=FAILED;request<=0;O_bus_error<=1;O_cfg_done<=0;end
        endcase
    end
endmodule
