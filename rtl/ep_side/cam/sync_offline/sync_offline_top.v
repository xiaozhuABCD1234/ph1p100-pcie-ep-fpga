module sync_offline_top #(
 parameter integer WAIT_CYCLES=1200000,WARMUP_FRAMES=8,
 parameter integer I2C_TIMEOUT=5000000,FRAME_TIMEOUT=5000000,PAIR_WINDOW=50000,
 parameter [31:0] TIMESTAMP_INIT=0,
 parameter         MASTER_B=0
)(input wire clk_ctrl,clk_a,clk_b,rst_n,start,abort_req,prereq_ok,sof_a,sof_b,
 output wire req_valid,input wire req_ready,output wire camera_id,
 output wire [15:0] reg_addr,output wire [7:0] reg_data,input wire rsp_valid,rsp_ok,
 output wire ready,busy,stopped_confirmed,output wire [3:0] error_code,
 output wire pair_valid,locked,output wire signed [31:0] skew,
 output wire [31:0] pair_seq_a,pair_seq_b,pair_count,miss_a,miss_b,
 output wire [31:0] overrun_a,overrun_b,relock_count,warmup_count,ignored_starts,
 output wire [31:0] timestamp
);
 wire reset_ctrl,reset_a,reset_b,en,a_valid,b_valid;
 wire [31:0] a_seq,b_seq,a_lost,b_lost;
 sync_reset rc(clk_ctrl,rst_n,reset_ctrl);
 sync_reset ra(clk_a,rst_n,reset_a);
 sync_reset rb(clk_b,rst_n,reset_b);
 sync_sof_mailbox ma(
  .src_clk(clk_a),.src_reset_n(reset_a),.src_sof(sof_a),
  .dst_clk(clk_ctrl),.dst_reset_n(reset_ctrl),
  .dst_valid(a_valid),.dst_seq(a_seq),.dst_lost(a_lost),.src_busy());
 sync_sof_mailbox mb(
  .src_clk(clk_b),.src_reset_n(reset_b),.src_sof(sof_b),
  .dst_clk(clk_ctrl),.dst_reset_n(reset_ctrl),
  .dst_valid(b_valid),.dst_seq(b_seq),.dst_lost(b_lost),.src_busy());
 sync_sof_pair #(.PAIR_WINDOW(PAIR_WINDOW),.TIMESTAMP_INIT(TIMESTAMP_INIT)) pairer(
 clk_ctrl,reset_ctrl,en,a_valid,b_valid,a_seq,b_seq,a_lost,b_lost,
 pair_valid,locked,skew,pair_seq_a,pair_seq_b,pair_count,miss_a,miss_b,
 overrun_a,overrun_b,relock_count,timestamp);
 sync_start_ctrl #(.WAIT_CYCLES(WAIT_CYCLES),.WARMUP_FRAMES(WARMUP_FRAMES),
 .I2C_TIMEOUT(I2C_TIMEOUT),.FRAME_TIMEOUT(FRAME_TIMEOUT),.MASTER_B(MASTER_B)) control(
 clk_ctrl,reset_ctrl,start,abort_req,prereq_ok,pair_valid,req_valid,req_ready,
 camera_id,reg_addr,reg_data,rsp_valid,rsp_ok,busy,en,ready,stopped_confirmed,
 error_code,warmup_count,ignored_starts);
endmodule
