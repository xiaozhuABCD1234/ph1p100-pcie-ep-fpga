`timescale 1ns/1ps
// Single DDR-user-clock domain. Native PH1P PAXI: one 256-bit command,
// address step 8, mask 0 writes every byte. This is not a standard AXI master.
// Contract: ready loss must flush/reset the controller's pending responses.
// Recovery without that flush needs a controller-specific drain/epoch adapter.
module ddr_frame_store #(parameter FRAME_WORDS=16200,
 parameter OFFSET_BITS=(FRAME_WORDS>65536)?$clog2(FRAME_WORDS):16)(
 input clk,rst_n,ddr_ready,
 input frame_begin,input [31:0] frame_id,output frame_begin_ready,
 input [255:0] s_data,input s_valid,s_last,s_abort,output s_ready,
 input frame_switch,output frame_switch_ready,frame_valid,output [31:0] read_frame_id,
 input rd_req,input [OFFSET_BITS-1:0] rd_offset,output rd_req_ready,
 output reg [255:0] rd_data,output reg rd_valid,input rd_take,
 output reg [31:0] published_count,error_count,drop_count,
 output [26:0] paxi_awaddr,output paxi_awvalid,input paxi_awready,
 output [255:0] paxi_wdata,output [31:0] paxi_wstrb,output paxi_wvalid,paxi_wlast,input paxi_wready,
 output [26:0] paxi_araddr,output paxi_arvalid,input paxi_arready,
 input [255:0] paxi_rdata,input paxi_rvalid,paxi_rlast,output paxi_rready
);
 localparam FREE=0,WRITING=1,READY=2,READING=3;
 localparam IDLE=0,WRITE=1,FENCE=2,VERIFY=3;
 reg [1:0] slot_state[0:2];reg [31:0] slot_id[0:2];
 reg [1:0] write_slot,read_slot,write_state;
 reg [OFFSET_BITS-1:0] write_offset;
 reg read_active,read_outstanding,read_is_fence,write_turn,abort_fence;
 reg [255:0] last_word;
 reg [7:0] fence_match;reg fence_rlast;
 wire has_free=(slot_state[0]==FREE)||(slot_state[1]==FREE)||(slot_state[2]==FREE);
 wire [1:0] free_slot=(slot_state[0]==FREE)?0:(slot_state[1]==FREE)?1:2;
 wire has_ready=(slot_state[0]==READY)||(slot_state[1]==READY)||(slot_state[2]==READY);
 wire [1:0] ready_slot=(slot_state[0]==READY)?0:(slot_state[1]==READY)?1:2;
 function [26:0] base(input [1:0] slot);
   begin case(slot) 0:base=0;1:base=FRAME_WORDS*8;default:base=FRAME_WORDS*16;endcase end
 endfunction
 wire want_fence=(write_state==FENCE)&&!read_outstanding&&!s_abort;
 wire want_read=rd_req&&read_active&&!rd_valid&&!read_outstanding&&!frame_switch&&(rd_offset<FRAME_WORDS);
 wire want_write=(write_state==WRITE)&&s_valid&&!s_abort;
 wire read_choice=want_fence||(want_read&&(!want_write||!write_turn));
 wire write_choice=want_write&&!want_fence&&(!want_read||write_turn);
 wire common_ready=rst_n&&ddr_ready&&paxi_awready&&paxi_arready;
 wire do_read=read_choice&&common_ready;
 wire do_write=write_choice&&common_ready&&paxi_wready;
 assign frame_begin_ready=rst_n&&ddr_ready&&(write_state==IDLE)&&has_free&&!s_abort;
 assign frame_switch_ready=rst_n&&ddr_ready&&has_ready&&!read_outstanding&&!rd_valid&&(write_state!=VERIFY);
 assign frame_valid=rst_n&&ddr_ready&&read_active;
 assign read_frame_id=slot_id[read_slot];
 assign rd_req_ready=do_read&&!want_fence;
 assign s_ready=do_write;
 assign paxi_awaddr=base(write_slot)+{{(24-OFFSET_BITS){1'b0}},write_offset,3'b000};
 assign paxi_awvalid=do_write;
 assign paxi_wdata=s_data;
 assign paxi_wstrb=32'd0;
 assign paxi_wvalid=do_write;
 assign paxi_wlast=1'b1;
 assign paxi_araddr=want_fence?(base(write_slot)+(FRAME_WORDS-1)*8):(base(read_slot)+{{(24-OFFSET_BITS){1'b0}},rd_offset,3'b000});
 assign paxi_arvalid=do_read;
 assign paxi_rready=1'b1;
 integer i;
 always @(posedge clk or negedge rst_n)begin
   if(!rst_n)begin
     for(i=0;i<3;i=i+1)begin slot_state[i]<=FREE;slot_id[i]<=0;end
     write_slot<=0;read_slot<=0;write_state<=IDLE;write_offset<=0;
     read_active<=0;read_outstanding<=0;read_is_fence<=0;write_turn<=1;abort_fence<=0;
     last_word<=0;fence_match<=0;fence_rlast<=0;
     rd_data<=0;rd_valid<=0;published_count<=0;error_count<=0;drop_count<=0;
   end else if(!ddr_ready)begin
     for(i=0;i<3;i=i+1)slot_state[i]<=FREE;
     if(write_state!=IDLE)drop_count<=drop_count+1'b1;
     write_state<=IDLE;write_offset<=0;read_active<=0;read_outstanding<=0;
     rd_valid<=0;abort_fence<=0;write_turn<=1;
   end else begin
     if(rd_valid&&rd_take)rd_valid<=0;
     if(frame_begin&&frame_begin_ready)begin
       write_slot<=free_slot;slot_state[free_slot]<=WRITING;slot_id[free_slot]<=frame_id;
       write_offset<=0;write_state<=WRITE;abort_fence<=0;
     end
     if(frame_switch&&frame_switch_ready)begin
       if(read_active)slot_state[read_slot]<=FREE;
       read_slot<=ready_slot;slot_state[ready_slot]<=READING;read_active<=1;
     end
     if(s_abort&&write_state!=IDLE&&write_state!=VERIFY)begin
       if(write_state==FENCE&&read_outstanding)abort_fence<=1;
       else begin slot_state[write_slot]<=FREE;write_state<=IDLE;drop_count<=drop_count+1'b1;end
     end
     if(do_write)begin
       write_turn<=0;
       if(s_last!=(write_offset==FRAME_WORDS-1))begin
         slot_state[write_slot]<=FREE;write_state<=IDLE;
         error_count<=error_count+1'b1;drop_count<=drop_count+1'b1;
       end else if(s_last)begin last_word<=s_data;write_state<=FENCE;end
       else write_offset<=write_offset+1'b1;
     end
     if(do_read)begin read_outstanding<=1;read_is_fence<=want_fence;write_turn<=1;end
     if(paxi_rvalid&&read_outstanding)begin
       read_outstanding<=0;
       if(read_is_fence)begin
         // Break the 256-bit compare -> ownership/counter path at 200MHz.
         for(i=0;i<8;i=i+1)fence_match[i]<=(paxi_rdata[i*32+:32]===last_word[i*32+:32]);
         fence_rlast<=paxi_rlast;write_state<=VERIFY;
         if(s_abort)abort_fence<=1;
       end else if(paxi_rlast!==1'b1)begin
         error_count<=error_count+1'b1;read_active<=0;slot_state[read_slot]<=FREE;
       end else begin rd_data<=paxi_rdata;rd_valid<=1;end
     end
     if(write_state==VERIFY)begin
       write_state<=IDLE;
       if(abort_fence||s_abort)begin slot_state[write_slot]<=FREE;drop_count<=drop_count+1'b1;end
       else if(fence_rlast!==1'b1||fence_match!==8'hff)begin
         slot_state[write_slot]<=FREE;error_count<=error_count+1'b1;drop_count<=drop_count+1'b1;
       end else begin
         // Newest complete frame replaces only READY, never READING.
         for(i=0;i<3;i=i+1)if(slot_state[i]==READY && !(frame_switch&&frame_switch_ready&&ready_slot==i))slot_state[i]<=FREE;
         slot_state[write_slot]<=READY;published_count<=published_count+1'b1;
       end
     end
   end
 end
endmodule
