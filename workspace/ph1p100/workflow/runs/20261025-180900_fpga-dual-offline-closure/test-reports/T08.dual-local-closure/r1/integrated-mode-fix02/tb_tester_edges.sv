`timescale 1ns/1ps
module tb_tester_edges;
 reg clk=0,rst=1; always #4 clk=~clk;
 reg ap=0,adr=0,rv=0,xvalid=0; reg [31:0] abase=32'h00900000,aseq=101;
 wire dv,ds; wire [31:0] dq,dbase; wire [3:0] held; wire [1:0] arel,brel; wire xr;
 integer failures=0;
 dual_local_closure #(.W(8),.H(2),.DEFAULT_MODE(2),.TIMEOUT_CYCLES(100)) dut(
 .clk(clk),.rst(rst),.epoch(32'd7),.requested_mode(2'd2),.abort(1'b0),
 .a_pub_valid(ap),.a_pub_seq(aseq),.a_pub_base(abase),.a_pub_len(32'd4096),.a_pub_session(32'd42),
 .b_pub_valid(1'b0),.b_pub_seq(32'd0),.b_pub_base(32'h01100000),.b_pub_len(32'd4096),.b_pub_session(32'd42),
 .a_release(arel),.b_release(brel),.a_desc_valid(dv),.a_desc_ready(adr),.a_desc_slot_id(ds),.a_desc_capture_seq(dq),.a_desc_base(dbase),
 .b_desc_ready(1'b0),.rel_valid(rv),.rel_ready(),.rel_camera_id(1'b0),.rel_slot_id(1'b0),.rel_epoch(32'd7),.rel_session(32'd42),.rel_capture_seq(32'd201),.rel_status(3'd2),
 .held(held),.arready(1'b0),.rid(4'd0),.rdata(256'd0),.rresp(2'd0),.rlast(1'b0),.rvalid(1'b0),
 .ext_arid(4'd0),.ext_araddr(29'h00100000),.ext_arlen(8'd0),.ext_arsize(3'd5),.ext_arburst(2'd1),.ext_arvalid(xvalid),.ext_arready(xr),.ext_rready(1'b0));
 task tick; @(negedge clk); endtask
 task ck(input bit ok,input string label);
  if(!ok) begin failures=failures+1; $display("EDGE_FAIL %s held=%x slot=%0d seq=%0d base=%08x releaseA=%x ar_pending=%0d",label,held,ds,dq,dbase,arel,dut.ar_pending); end
  else $display("EDGE_HIT %s",label);
 endtask
 initial begin
  repeat(3)tick();rst=0;tick();ap=1;tick();ap=0;tick();
  ck(dv&&ds==1&&dq==101&&dbase==32'h00900000,"slot1_descriptor_initial");
  repeat(2)tick();abase=32'h00100000;aseq=102;ap=1;tick();ap=0;tick();
  ck(dv&&ds==1&&dq==101&&dbase==32'h00900000,"stalled_descriptor_must_not_change_on_slot0_publication");
  rst=1;repeat(3)tick();rst=0;tick();abase=32'h00100000;aseq=201;ap=1;tick();ap=0;tick();adr=1;tick();adr=0;tick();
  ck(held==1&&!dv,"accepted_descriptor_retains_ownership");
  xvalid=1;rv=1;#1;ck(xr,"external_AR_is_accepted_same_cycle_as_release");tick();xvalid=0;rv=0;
  ck(held==1&&arel==0&&dut.ar_pending,"accepted_AR_must_prevent_status2_release_same_cycle");
  if(failures) $fatal(1,"TESTER_EDGE_FAIL count=%0d",failures);
  $display("TESTER_EDGE_PASS");$finish;
 end
 initial begin #100000;$fatal(1,"tester edge watchdog"); end
endmodule
