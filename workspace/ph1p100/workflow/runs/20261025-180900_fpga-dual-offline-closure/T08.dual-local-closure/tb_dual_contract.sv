`timescale 1ns/1ps
module tb_dual_contract;
 reg clk=0,rst=1;always #4 clk=~clk;
 reg ap=0,bp=0,ar=0,br=0,rv=0,rc=0,rs=0;reg [31:0] re=7,rss=42,rseq=101;
 wire av,bv;wire [31:0] aseq,bseq;wire [3:0] held;wire [1:0] arel,brel;
 wire [31:0] rejects,fault;
 dual_local_closure #(.W(8),.H(2),.DEFAULT_MODE(2),.TIMEOUT_CYCLES(30)) dut(
 .clk(clk),.rst(rst),.epoch(32'd7),.requested_mode(2'd2),.abort(1'b0),
 .a_pub_valid(ap),.a_pub_seq(32'd101),.a_pub_base(32'h00100000),.a_pub_len(32'd4096),.a_pub_session(32'd42),
 .b_pub_valid(bp),.b_pub_seq(32'd202),.b_pub_base(32'h01100000),.b_pub_len(32'd4096),.b_pub_session(32'd42),
 .a_release(arel),.b_release(brel),.a_desc_valid(av),.a_desc_ready(ar),.a_desc_capture_seq(aseq),
 .b_desc_valid(bv),.b_desc_ready(br),.b_desc_capture_seq(bseq),
 .rel_valid(rv),.rel_ready(),.rel_camera_id(rc),.rel_slot_id(rs),.rel_epoch(re),.rel_session(rss),.rel_capture_seq(rseq),.rel_status(3'd2),
 .pass_count(),.fail_count(),.fault(fault),.reject_count(rejects),.held(held),.active_mode(),
 .arid(),.araddr(),.arlen(),.arsize(),.arburst(),.arvalid(),.arready(1'b0),
 .rid(4'd0),.rdata(256'd0),.rresp(2'd0),.rlast(1'b0),.rvalid(1'b0),.rready(),
 .ext_arid(4'd0),.ext_araddr(29'd0),.ext_arlen(8'd0),.ext_arsize(3'd5),.ext_arburst(2'd1),.ext_arvalid(1'b0),.ext_arready(),
 .ext_rid(),.ext_rdata(),.ext_rresp(),.ext_rlast(),.ext_rvalid(),.ext_rready(1'b0));
 task check(input bit ok,input string why);if(!ok)$fatal(1,"CONTRACT_FAIL %s",why);endtask
 task tick;@(negedge clk);endtask
 initial begin
  repeat(3)tick();rst=0;tick();ap=1;bp=1;tick();ap=0;bp=0;tick();
  check(held==5 && av && bv && aseq==101 && bseq==202,"simultaneous pulse captured in two independent slots");
  repeat(5)begin tick();check(av&&bv&&aseq==101&&bseq==202,"all identities stable while stalled");end
  ar=1;br=1;tick();ar=0;br=0;tick();check(!av&&!bv&&held==5,"same-cycle desc transfers retained ownership");
  rv=1;rc=1;rseq=101;tick();rv=0;tick();check(held==5&&rejects==1&&arel==0&&brel==0,"wrong camera cannot release A");
  rv=1;rc=0;re=6;tick();rv=0;tick();check(held==5&&rejects==2,"old epoch cannot release");
  rv=1;rc=1;re=7;rseq=202;tick();rv=0;check(brel==1&&arel==0,"B release routes only to B");tick();check(held==1,"A remains protected");
  rv=1;tick();rv=0;tick();check(held==1&&rejects==3,"duplicate B release rejected");
  rv=1;rc=0;rseq=101;tick();rv=0;check(arel==1&&brel==0,"A release routes only to A");tick();check(held==0&&fault==0,"all slots free");
  $display("CONTRACT_PASS simultaneous_pub=1 simultaneous_desc=1 stall=1 wrong_camera=1 stale_epoch=1 duplicate=1 mismatch=0");$finish;
 end
 initial begin #100000;$fatal(1,"contract watchdog");end
endmodule
