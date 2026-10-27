`timescale 1ns/1ps
// Common asynchronous assertion, independent synchronous release. Registered
// read prefetch permits inferred dual-clock RAM and holds data under backpressure.
module capture_async_fifo #(parameter WIDTH=258,ADDR_BITS=8)(
 input rst_n,wclk,w_valid,input[WIDTH-1:0] w_data,output w_ready,
 input rclk,output reg r_valid,output reg[WIDTH-1:0] r_data,input r_ready
);
 (* async_reg="true" *) reg[1:0] wr_reset,rd_reset;
 always @(posedge wclk or negedge rst_n)if(!rst_n)wr_reset<=0;else wr_reset<={wr_reset[0],1'b1};
 always @(posedge rclk or negedge rst_n)if(!rst_n)rd_reset<=0;else rd_reset<={rd_reset[0],1'b1};
 (* ram_style="bram" *) reg[WIDTH-1:0] mem[0:(1<<ADDR_BITS)-1];
 reg[ADDR_BITS:0] wbin,rbin;reg full;
 // SWUG106 section 4.3.6: retain registered Gray outputs across PHY optimization.
 (* dont_touch="true" *) reg[ADDR_BITS:0] wgray,rgray;
 (* async_reg="true" *) reg[ADDR_BITS:0] rq1_wgray,rq2_wgray,wq1_rgray,wq2_rgray;
 wire push=w_valid&&w_ready;
 wire[ADDR_BITS:0] wn=wbin+push,wgn=(wn>>1)^wn;
 wire empty=(rgray==rq2_wgray);
 wire fetch=rd_reset[1]&&!empty&&(!r_valid||r_ready);
 wire[ADDR_BITS:0] rn=rbin+fetch,rgn=(rn>>1)^rn;
 assign w_ready=wr_reset[1]&&!full;
 always @(posedge wclk)if(push)mem[wbin[ADDR_BITS-1:0]]<=w_data;
 always @(posedge rclk)if(fetch)r_data<=mem[rbin[ADDR_BITS-1:0]];
 always @(posedge wclk or negedge rst_n)begin
  if(!rst_n)begin wbin<=0;wgray<=0;full<=0;wq1_rgray<=0;wq2_rgray<=0;end
  else if(!wr_reset[1])begin wbin<=0;wgray<=0;full<=0;wq1_rgray<=0;wq2_rgray<=0;end
  else begin wq1_rgray<=rgray;wq2_rgray<=wq1_rgray;wbin<=wn;wgray<=wgn;
   full<=(wgn=={~wq2_rgray[ADDR_BITS:ADDR_BITS-1],wq2_rgray[ADDR_BITS-2:0]});end
 end
 always @(posedge rclk or negedge rst_n)begin
  if(!rst_n)begin rbin<=0;rgray<=0;rq1_wgray<=0;rq2_wgray<=0;r_valid<=0;end
  else if(!rd_reset[1])begin rbin<=0;rgray<=0;rq1_wgray<=0;rq2_wgray<=0;r_valid<=0;end
  else begin rq1_wgray<=wgray;rq2_wgray<=rq1_wgray;rbin<=rn;rgray<=rgn;
   if(fetch)r_valid<=1;else if(r_ready)r_valid<=0;end
 end
endmodule
