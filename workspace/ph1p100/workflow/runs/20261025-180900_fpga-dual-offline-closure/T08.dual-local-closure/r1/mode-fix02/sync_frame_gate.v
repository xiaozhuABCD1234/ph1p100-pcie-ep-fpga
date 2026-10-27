// Asynchronous revoke, two-flop synchronized permit, frame-boundary admission.
// The gate never creates a SOF; revoked open frames reach the writer as aborts.
module sync_frame_gate #(parameter ENABLE=1)(
 input wire clk,rst_n,permit,sof,in_frame,in_line,pixel_valid,good,abort_in,
 output wire out_sof,out_frame,out_line,out_pixel_valid,out_good,out_abort);
 generate if(ENABLE) begin : g
  reg [1:0] permit_s;reg admitted;
  wire permit_reset_n=rst_n && permit;
  always @(posedge clk or negedge permit_reset_n)
   if(!permit_reset_n) permit_s<=0;else permit_s<={permit_s[0],1'b1};
  always @(posedge clk or negedge rst_n)
   if(!rst_n) admitted<=0;
   else if(!permit_s[1]) admitted<=0;
   else if(sof) admitted<=1;
   else if(!in_frame) admitted<=0;
  assign out_sof=sof && permit_s[1];
  assign out_frame=in_frame && admitted && permit_s[1];
  assign out_line=in_line && admitted && permit_s[1];
  assign out_pixel_valid=pixel_valid && admitted && permit_s[1];
  assign out_good=good && admitted && permit_s[1];
  assign out_abort=abort_in || (admitted && !permit_s[1]);
 end else begin : bypass
  assign {out_sof,out_frame,out_line,out_pixel_valid,out_good,out_abort}=
   {sof,in_frame,in_line,pixel_valid,good,abort_in};
 end endgenerate
endmodule
