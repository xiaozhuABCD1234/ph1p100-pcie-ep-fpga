module sync_offline_g2(
 input wire clk_ctrl,clk_a,clk_b,rst_n,start,abort_req,prereq_ok,sof_a,sof_b,
 input wire req_ready,rsp_valid,rsp_ok,input wire [3:0] select_diag,
 output wire req_valid,camera_id,output wire [15:0] reg_addr,
 output wire [7:0] reg_data,output wire ready,busy,stopped_confirmed,
 output wire [3:0] error_code,output reg [31:0] diagnostic
);
 wire pair_valid,locked;wire signed [31:0] skew;
 wire [31:0] pair_seq_a,pair_seq_b,pair_count,miss_a,miss_b,overrun_a,overrun_b,
 relock_count,warmup_count,ignored_starts,timestamp;
 sync_offline_top dut(
  .clk_ctrl(clk_ctrl),.clk_a(clk_a),.clk_b(clk_b),.rst_n(rst_n),
  .start(start),.abort_req(abort_req),.prereq_ok(prereq_ok),.sof_a(sof_a),.sof_b(sof_b),
  .req_valid(req_valid),.req_ready(req_ready),.camera_id(camera_id),
  .reg_addr(reg_addr),.reg_data(reg_data),.rsp_valid(rsp_valid),.rsp_ok(rsp_ok),
  .ready(ready),.busy(busy),.stopped_confirmed(stopped_confirmed),.error_code(error_code),
  .pair_valid(pair_valid),.locked(locked),.skew(skew),
  .pair_seq_a(pair_seq_a),.pair_seq_b(pair_seq_b),.pair_count(pair_count),
  .miss_a(miss_a),.miss_b(miss_b),.overrun_a(overrun_a),.overrun_b(overrun_b),
  .relock_count(relock_count),.warmup_count(warmup_count),.ignored_starts(ignored_starts),
  .timestamp(timestamp));
 always @* case(select_diag)
  0:diagnostic=skew;1:diagnostic=pair_seq_a;2:diagnostic=pair_seq_b;
  3:diagnostic=pair_count;4:diagnostic=miss_a;5:diagnostic=miss_b;
  6:diagnostic=overrun_a;7:diagnostic=overrun_b;8:diagnostic=relock_count;
  9:diagnostic=warmup_count;10:diagnostic=ignored_starts;11:diagnostic=timestamp;
  default:diagnostic={30'b0,pair_valid,locked};
 endcase
endmodule
