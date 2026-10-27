`timescale 1ns/1ps
module tb_repair_matrix;
 reg clk=0,rst=1;always #4 clk=~clk;
 reg ap=0,bp=0,adr=0,bdr=0,rv=0,rc=0,rs=0,xv=0,ddr_ready=0;
 reg [31:0] abase=32'h00100000,bbase=32'h01100000,aseq=100,bseq=200,rseq=100;
 reg [2:0] status=2;reg [28:0] xaddr=0;reg [7:0] xlen=0;
 reg rvalid=0,rlast=0;reg [255:0] rdata=0;
 wire av,bv,aslot,bslot,xready,arvalid,rready;wire [31:0] aq,bq,ab,bb;
 wire [3:0] held;wire [1:0] arel,brel;wire [31:0] fault;
 integer matrix_hits=0,stall_hits=0,refill_hits=0;
 dual_local_closure #(.W(8),.H(2),.DEFAULT_MODE(2),.TIMEOUT_CYCLES(40)) dut(
 .clk(clk),.rst(rst),.epoch(32'd7),.requested_mode(2'd2),.abort(1'b0),
 .a_pub_valid(ap),.a_pub_seq(aseq),.a_pub_base(abase),.a_pub_len(32'd4096),.a_pub_session(32'd42),
 .b_pub_valid(bp),.b_pub_seq(bseq),.b_pub_base(bbase),.b_pub_len(32'd4096),.b_pub_session(32'd42),
 .a_release(arel),.b_release(brel),.a_desc_valid(av),.a_desc_ready(adr),.a_desc_slot_id(aslot),.a_desc_capture_seq(aq),.a_desc_base(ab),
 .b_desc_valid(bv),.b_desc_ready(bdr),.b_desc_slot_id(bslot),.b_desc_capture_seq(bq),.b_desc_base(bb),
 .rel_valid(rv),.rel_ready(),.rel_camera_id(rc),.rel_slot_id(rs),.rel_epoch(32'd7),.rel_session(32'd42),.rel_capture_seq(rseq),.rel_status(status),
 .fault(fault),.held(held),.arvalid(arvalid),.arready(ddr_ready),.rid(4'd0),.rdata(rdata),.rresp(2'd0),.rlast(rlast),.rvalid(rvalid),.rready(rready),
 .ext_arid(4'd0),.ext_araddr(xaddr),.ext_arlen(xlen),.ext_arsize(3'd5),.ext_arburst(2'd1),.ext_arvalid(xv),.ext_arready(xready),.ext_rready(1'b1));
 task tick;@(negedge clk);endtask
 task ck(input bit ok,input string why);if(!ok)$fatal(1,"MATRIX_FAIL %s",why);endtask
 function [31:0] base(input integer c,s);base=(c?32'h01100000:32'h00100000)+(s?32'h00800000:0);endfunction
 task reset_all;
  rst=1;ap=0;bp=0;adr=0;bdr=0;rv=0;xv=0;ddr_ready=0;rvalid=0;rlast=0;repeat(3)tick();rst=0;tick();
 endtask
 task publish(input integer c,s,seq);
  if(c==0)begin abase=base(c,s);aseq=seq;ap=1;end else begin bbase=base(c,s);bseq=seq;bp=1;end
  tick();ap=0;bp=0;tick();
 endtask
 task take(input integer c);
  if(c==0)adr=1;else bdr=1;tick();adr=0;bdr=0;tick();
 endtask
 task return_burst(input integer beats);
  ddr_ready=1;tick();ddr_ready=0;repeat(3)tick();
  for(integer n=0;n<beats;n=n+1)begin
   rvalid=1;rlast=n==beats-1;tick();ck(rready||n==beats-1,"consumer accepts each R");rvalid=0;rlast=0;tick();
  end
 endtask
 initial begin
  // Both cameras and both initial slot orders; incoming alternate pub never changes a stalled offer.
  for(integer c=0;c<2;c=c+1)for(integer s=0;s<2;s=s+1)begin
   reset_all();publish(c,s,101);ck(c==0?(av&&aslot==s&&aq==101&&ab==base(c,s)):(bv&&bslot==s&&bq==101&&bb==base(c,s)),"initial offered identity");
   publish(c,1-s,102);
   repeat(4)begin tick();ck(c==0?(av&&aslot==s&&aq==101&&ab==base(c,s)):(bv&&bslot==s&&bq==101&&bb==base(c,s)),"all stalled identity fields stable after other-slot publication");end
   stall_hits=stall_hits+1;take(c);
   ck(c==0?(av&&aslot==1-s&&aq==102):(bv&&bslot==1-s&&bq==102),"other slot presented after first take");take(c);
   ck(held==(c==0?3:12),"both transferred slots retained until release");
  end
  // A transfer and the other-slot publication occur on the same edge.
  for(integer c=0;c<2;c=c+1)begin
   reset_all();publish(c,1,301);
   if(c==0)begin abase=base(0,0);aseq=302;ap=1;adr=1;end else begin bbase=base(1,0);bseq=302;bp=1;bdr=1;end
   tick();ap=0;bp=0;adr=0;bdr=0;
   ck(c==0?(av&&aslot==0&&aq==302):(bv&&bslot==0&&bq==302),"same-cycle take/refill presents exact new identity");take(c);refill_hits=refill_hits+1;
  end
  // All status/camera/slot race combinations. Status0 starts with a complete prior DMA read.
  for(integer c=0;c<2;c=c+1)for(integer s=0;s<2;s=s+1)for(integer st=0;st<3;st=st+1)begin
   reset_all();publish(c,s,500+c*10+s);take(c);rc=c;rs=s;rseq=500+c*10+s;xaddr=base(c,s);
   if(st==0)begin xlen=127;xv=1;#1;ck(xready,"full prior read accepts");tick();xv=0;return_burst(128);ck(dut.ext_bytes[c*2+s]==4096,"prior DMA length exact");end
   xlen=0;status=st;rv=1;xv=1;#1;ck(xready,"AR accepted in release race");tick();rv=0;xv=0;
   ck(held[c*2+s]&&arel==0&&brel==0&&dut.ar_pending,"accepted AR atomically blocks release for all statuses");
   repeat(3)begin tick();ck(arvalid&&held[c*2+s]&&arel==0&&brel==0,"pending AR and ownership remain stable");end
   return_burst(1);status=1;rv=1;tick();rv=0;
   ck(!held[c*2+s]&&(c==0?arel==(s?2:1):brel==(s?2:1)),"release only after the accepted read drains");
   tick();ck(fault==0,"no spurious lock on delayed legal response");matrix_hits=matrix_hits+1;
  end
  // Permanent absence of R keeps the accepted slot locked until common reset.
  reset_all();publish(1,1,901);take(1);xaddr=base(1,1);xv=1;#1;ck(xready,"lock AR accepted");tick();xv=0;ddr_ready=1;tick();ddr_ready=0;
  repeat(45)tick();ck(fault!=0&&held==8&&arel==0&&brel==0,"missing R locks ownership");reset_all();ck(held==0&&fault==0,"common reset clears ownership and read state");
  $display("MATRIX_PASS stall_orders=%0d take_refill=%0d status_camera_slot_races=%0d late_R=12 lock_reset=1",stall_hits,refill_hits,matrix_hits);$finish;
 end
 initial begin #1000000;$fatal(1,"matrix watchdog");end

 wire [227:0] tester_a_fields={dut.a_desc_camera_id,dut.a_desc_slot_id,dut.a_desc_epoch,dut.a_desc_session,dut.a_desc_capture_seq,dut.a_desc_base,dut.a_desc_dma_bytes,dut.a_desc_raw_bytes,dut.a_desc_width,dut.a_desc_height,dut.a_desc_bayer_phase};
 wire [227:0] tester_b_fields={dut.b_desc_camera_id,dut.b_desc_slot_id,dut.b_desc_epoch,dut.b_desc_session,dut.b_desc_capture_seq,dut.b_desc_base,dut.b_desc_dma_bytes,dut.b_desc_raw_bytes,dut.b_desc_width,dut.b_desc_height,dut.b_desc_bayer_phase};
 reg tester_a_stall=0,tester_b_stall=0;reg [227:0] tester_a_prev,tester_b_prev;
 integer tester_stall_beats=0;
 always @(posedge clk) begin
  if(rst) begin tester_a_stall<=0;tester_b_stall<=0;end
  else begin
   if(tester_a_stall) begin ck(av&&tester_a_fields===tester_a_prev,"TESTER all A descriptor fields stable through stall");tester_stall_beats=tester_stall_beats+1;end
   if(tester_b_stall) begin ck(bv&&tester_b_fields===tester_b_prev,"TESTER all B descriptor fields stable through stall");tester_stall_beats=tester_stall_beats+1;end
   tester_a_stall<=av&&!adr;tester_b_stall<=bv&&!bdr;
   tester_a_prev<=tester_a_fields;tester_b_prev<=tester_b_fields;
  end
 end

endmodule
