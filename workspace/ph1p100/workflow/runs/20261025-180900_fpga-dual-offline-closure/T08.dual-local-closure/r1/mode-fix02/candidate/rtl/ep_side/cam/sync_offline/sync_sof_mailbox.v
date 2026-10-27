// One entry stable-bus request/acknowledge mailbox. An occupied slot is never
// overwritten. Sequence counts ALL input events; rejected events are explicit.
module sync_sof_mailbox(
 input wire src_clk, src_reset_n, src_sof,
 input wire dst_clk, dst_reset_n,
 output reg dst_valid, output reg [31:0] dst_seq, dst_lost,
 output wire src_busy
);
 reg req_toggle, ack_toggle;
 (* ASYNC_REG = "TRUE" *) reg ack_meta, ack_sync, req_meta, req_sync;
 reg [31:0] sequence_count, rejected_count;
 reg [63:0] payload_hold;
 assign src_busy = req_toggle != ack_sync;
 always @(posedge src_clk) begin
  if (!src_reset_n) begin
   req_toggle<=0; ack_meta<=0; ack_sync<=0;
   sequence_count<=0; rejected_count<=0; payload_hold<=0;
  end else begin
   ack_meta<=ack_toggle; ack_sync<=ack_meta;
   if(src_sof) begin
    sequence_count<=sequence_count+1'b1;
    if(src_busy) rejected_count<=rejected_count+1'b1;
    else begin payload_hold<={rejected_count,sequence_count+1'b1}; req_toggle<=~req_toggle; end
   end
  end
 end
 always @(posedge dst_clk) begin
  if(!dst_reset_n) begin
   req_meta<=0; req_sync<=0; ack_toggle<=0;
   dst_valid<=0; dst_seq<=0; dst_lost<=0;
  end else begin
   req_meta<=req_toggle; req_sync<=req_meta; dst_valid<=0;
   if(req_sync!=ack_toggle) begin
    {dst_lost,dst_seq}<=payload_hold; dst_valid<=1; ack_toggle<=req_sync;
   end
  end
 end
endmodule
