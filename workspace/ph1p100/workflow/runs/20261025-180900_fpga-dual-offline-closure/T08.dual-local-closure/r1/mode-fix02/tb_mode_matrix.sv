`timescale 1ns/1ps
module tb_mode_matrix #(parameter integer DUT_KIND=0);
 reg clk=0,rst=1;always #4 clk=~clk;
 reg [1:0] req_mode=2;reg ap=0,bp=0,adr=0,bdr=0,rv=0,rc=0,rs=0,xv=0,stall_ar=0,pause_r=0;
 reg [31:0] abase=32'h00100000,bbase=32'h01100000,aseq=100,bseq=200,rseq=100,repoch=7;
 reg [2:0] status=2;reg [28:0] xaddr=0;reg [7:0] xlen=0;
 wire av,bv,aslot,bslot,xready,arvalid,rready;wire [31:0] aq,bq,ab,bb,passes,fails,fault,rejects;
 wire [3:0] held;wire [1:0] arel,brel,mode;wire [28:0] araddr;wire [7:0] arlen;
 reg rd_active=0;reg [8:0] rd_left=0;integer ar_count=0,r_count=0;
 wire arready=!stall_ar&&!rd_active;
 wire rvalid=rd_active&&!pause_r,rlast=rd_left==1;
 integer failures=0,mode_pub_hits=0,busy_hits=0,race_hits=0,refill_hits=0;
 generate
 if(DUT_KIND==0)begin:g_dut0
dual_local_closure #(.W(8),.H(2),.DEFAULT_MODE(2),.TIMEOUT_CYCLES(2000)) dut(
.clk(clk),.rst(rst),.epoch(32'd7),.requested_mode(req_mode),.abort(1'b0),
.a_pub_valid(ap),.a_pub_seq(aseq),.a_pub_base(abase),.a_pub_len(32'd4096),.a_pub_session(32'd42),
.b_pub_valid(bp),.b_pub_seq(bseq),.b_pub_base(bbase),.b_pub_len(32'd4096),.b_pub_session(32'd42),
.a_release(arel),.b_release(brel),.a_desc_valid(av),.a_desc_ready(adr),.a_desc_slot_id(aslot),.a_desc_capture_seq(aq),.a_desc_base(ab),
.b_desc_valid(bv),.b_desc_ready(bdr),.b_desc_slot_id(bslot),.b_desc_capture_seq(bq),.b_desc_base(bb),
.rel_valid(rv),.rel_ready(),.rel_camera_id(rc),.rel_slot_id(rs),.rel_epoch(repoch),.rel_session(32'd42),.rel_capture_seq(rseq),.rel_status(status),
.pass_count(passes),.fail_count(fails),.fault(fault),.reject_count(rejects),.held(held),.active_mode(mode),
.arid(),.araddr(araddr),.arlen(arlen),.arsize(),.arburst(),.arvalid(arvalid),.arready(arready),
.rid(4'd0),.rdata(256'd0),.rresp(2'd0),.rlast(rlast),.rvalid(rvalid),.rready(rready),
.ext_arid(4'd0),.ext_araddr(xaddr),.ext_arlen(xlen),.ext_arsize(3'd5),.ext_arburst(2'd1),.ext_arvalid(xv),.ext_arready(xready),.ext_rready(1'b1));
end
else if(DUT_KIND==1)begin:g_dut1
dual_local_closure_old_mode #(.W(8),.H(2),.DEFAULT_MODE(2),.TIMEOUT_CYCLES(2000)) dut(
.clk(clk),.rst(rst),.epoch(32'd7),.requested_mode(req_mode),.abort(1'b0),
.a_pub_valid(ap),.a_pub_seq(aseq),.a_pub_base(abase),.a_pub_len(32'd4096),.a_pub_session(32'd42),
.b_pub_valid(bp),.b_pub_seq(bseq),.b_pub_base(bbase),.b_pub_len(32'd4096),.b_pub_session(32'd42),
.a_release(arel),.b_release(brel),.a_desc_valid(av),.a_desc_ready(adr),.a_desc_slot_id(aslot),.a_desc_capture_seq(aq),.a_desc_base(ab),
.b_desc_valid(bv),.b_desc_ready(bdr),.b_desc_slot_id(bslot),.b_desc_capture_seq(bq),.b_desc_base(bb),
.rel_valid(rv),.rel_ready(),.rel_camera_id(rc),.rel_slot_id(rs),.rel_epoch(repoch),.rel_session(32'd42),.rel_capture_seq(rseq),.rel_status(status),
.pass_count(passes),.fail_count(fails),.fault(fault),.reject_count(rejects),.held(held),.active_mode(mode),
.arid(),.araddr(araddr),.arlen(arlen),.arsize(),.arburst(),.arvalid(arvalid),.arready(arready),
.rid(4'd0),.rdata(256'd0),.rresp(2'd0),.rlast(rlast),.rvalid(rvalid),.rready(rready),
.ext_arid(4'd0),.ext_araddr(xaddr),.ext_arlen(xlen),.ext_arsize(3'd5),.ext_arburst(2'd1),.ext_arvalid(xv),.ext_arready(xready),.ext_rready(1'b1));
end
else if(DUT_KIND==2)begin:g_dut2
dual_local_closure_bad_b #(.W(8),.H(2),.DEFAULT_MODE(2),.TIMEOUT_CYCLES(2000)) dut(
.clk(clk),.rst(rst),.epoch(32'd7),.requested_mode(req_mode),.abort(1'b0),
.a_pub_valid(ap),.a_pub_seq(aseq),.a_pub_base(abase),.a_pub_len(32'd4096),.a_pub_session(32'd42),
.b_pub_valid(bp),.b_pub_seq(bseq),.b_pub_base(bbase),.b_pub_len(32'd4096),.b_pub_session(32'd42),
.a_release(arel),.b_release(brel),.a_desc_valid(av),.a_desc_ready(adr),.a_desc_slot_id(aslot),.a_desc_capture_seq(aq),.a_desc_base(ab),
.b_desc_valid(bv),.b_desc_ready(bdr),.b_desc_slot_id(bslot),.b_desc_capture_seq(bq),.b_desc_base(bb),
.rel_valid(rv),.rel_ready(),.rel_camera_id(rc),.rel_slot_id(rs),.rel_epoch(repoch),.rel_session(32'd42),.rel_capture_seq(rseq),.rel_status(status),
.pass_count(passes),.fail_count(fails),.fault(fault),.reject_count(rejects),.held(held),.active_mode(mode),
.arid(),.araddr(araddr),.arlen(arlen),.arsize(),.arburst(),.arvalid(arvalid),.arready(arready),
.rid(4'd0),.rdata(256'd0),.rresp(2'd0),.rlast(rlast),.rvalid(rvalid),.rready(rready),
.ext_arid(4'd0),.ext_araddr(xaddr),.ext_arlen(xlen),.ext_arsize(3'd5),.ext_arburst(2'd1),.ext_arvalid(xv),.ext_arready(xready),.ext_rready(1'b1));
end
 endgenerate
 // Native AXI response model only. Zero data intentionally exercises safe CRC-fail release
 // when mode1 owns a low-level descriptor; full production cases validate actual R10F bytes.
 always @(posedge clk) begin
  if(rst)begin rd_active<=0;rd_left<=0;ar_count<=0;r_count<=0;end
  else begin
   if(arvalid&&arready)begin rd_active<=1;rd_left<={1'b0,arlen}+1;ar_count<=ar_count+1;end
   else if(rvalid&&rready)begin r_count<=r_count+1;rd_left<=rd_left-1;if(rd_left==1)rd_active<=0;end
  end
 end
 task tick;@(negedge clk);endtask
 task ck(input bit ok,input string label);
  if(!ok)begin failures=failures+1;$display("MODE_FAIL %s kind=%0d mode=%0d held=%h Avalid=%0d Bvalid=%0d seqA=%0d seqB=%0d",label,DUT_KIND,mode,held,av,bv,aq,bq);end
 endtask
 function [31:0] base(input integer c,s);base=(c?32'h01100000:32'h00100000)+(s?32'h00800000:0);endfunction
 task reset_to(input integer initial_mode);
  rst=1;req_mode=2;ap=0;bp=0;adr=0;bdr=0;rv=0;xv=0;stall_ar=0;pause_r=0;repoch=7;status=2;xlen=0;
  repeat(3)tick();rst=0;repeat(2)tick();
  if(initial_mode!=2)begin req_mode=initial_mode;repeat(3)tick();end
  ck(mode==initial_mode,"idle_mode_change_is_supported");
 endtask
 task publish(input integer c,s,seq);
  if(c==0)begin abase=base(c,s);aseq=seq;ap=1;end else begin bbase=base(c,s);bseq=seq;bp=1;end
  tick();ap=0;bp=0;tick();
 endtask
 task take_desc(input integer c);
  integer n;
  begin n=0;while(!(c==0?av:bv)&&n<20)begin tick();n=n+1;end
   ck(c==0?av:bv,"actual_presented_descriptor_before_take");
   if(c==0)adr=1;else bdr=1;tick();adr=0;bdr=0;tick();
  end
 endtask
 task release_desc(input integer c,s,seq,st);
  rc=c;rs=s;rseq=seq;status=st;repoch=7;rv=1;tick();rv=0;
  ck(!held[c*2+s],"matching_release_clears_only_owned_slot");
  if(c==0)ck(arel==(s?2:1)&&brel==0,"A_release_routes_only_A");
  else ck(brel==(s?2:1)&&arel==0,"B_release_routes_only_B");
  tick();
 endtask
 task wait_free;
  integer n;
  begin n=0;while(held!=0&&n<10000)begin tick();n=n+1;end
   ck(held==0&&!rd_active&&!arvalid,"local_read_drains_before_free");repeat(3)tick();
  end
 endtask
 task wait_read_done;
  integer n;
  begin n=0;while((rd_active||arvalid)&&n<10000)begin tick();n=n+1;end
   ck(!rd_active&&!arvalid,"accepted_native_read_completed");repeat(2)tick();
  end
 endtask
 task idle_roundtrip;
  req_mode=2;repeat(3)tick();req_mode=1;repeat(3)tick();ck(mode==1,"empty_transition_to_mode1");
  req_mode=2;repeat(3)tick();ck(mode==2,"empty_transition_to_mode2");
  ck(held==0&&!av&&!bv,"no_phantom_after_idle_roundtrip");
 endtask
 initial begin
  // Both directions, cameras and slots use legal pulse descriptors, no forced state.
  for(integer initial_mode=1;initial_mode<=2;initial_mode=initial_mode+1)
   for(integer c=0;c<2;c=c+1)for(integer s=0;s<2;s=s+1)begin
    reset_to(initial_mode);req_mode=initial_mode==2?1:2;
    if(c==0)begin abase=base(c,s);aseq=100+c*10+s;ap=1;end
    else begin bbase=base(c,s);bseq=100+c*10+s;bp=1;end
    tick();ap=0;bp=0;
    ck(mode==initial_mode&&held[c*2+s],"publication_must_keep_current_mode");
    ck(rejects>0,"publication_mode_request_is_counted_rejected");
    if(mode==2)begin take_desc(c);release_desc(c,s,100+c*10+s,2);end
    else wait_free();
    idle_roundtrip();mode_pub_hits=mode_pub_hits+1;
   end
  // Simultaneous A/B pulses and complete identity ownership, followed by valid idle changes.
  reset_to(2);req_mode=1;abase=base(0,0);aseq=201;bbase=base(1,1);bseq=202;ap=1;bp=1;tick();ap=0;bp=0;
  ck(mode==2&&held==9,"two_publications_reject_mode_change_without_loss");
  if(mode==2)begin
   ck(av&&bv&&aq==201&&bq==202,"both_real_offers_retained");adr=1;bdr=1;tick();adr=0;bdr=0;tick();
   release_desc(0,0,201,2);release_desc(1,1,202,2);
  end else wait_free();
  idle_roundtrip();
  // Stalled offer, transferred held descriptor, offered AR and accepted R all reject changes.
  reset_to(2);publish(0,0,300);req_mode=1;repeat(3)tick();
  ck(mode==2&&av&&aq==300&&held==1,"held_stalled_offer_rejects_mode_change");
  req_mode=2;tick();take_desc(0);req_mode=1;repeat(2)tick();ck(mode==2&&held==1,"sent_held_descriptor_rejects_mode_change");
  req_mode=2;tick();stall_ar=1;pause_r=1;xaddr=base(0,0);xlen=0;xv=1;#1;ck(xready,"external_read_accepts");tick();xv=0;
  req_mode=1;repeat(3)tick();ck(mode==2&&arvalid&&held==1,"pending_AR_rejects_mode_change_and_stays_valid");
  stall_ar=0;repeat(2)tick();req_mode=0;repeat(3)tick();ck(mode==2&&rd_active&&held==1,"accepted_AR_missing_R_rejects_mode_change");
  pause_r=0;wait_read_done();release_desc(0,0,300,1);idle_roundtrip();busy_hits=busy_hits+4;
  // Real checker busy/drain is reached through a legal mode1 publication.
  reset_to(1);pause_r=1;publish(1,1,401);wait(rd_active);req_mode=2;repeat(3)tick();
  ck(mode==1&&held==8&&!bv,"local_reader_busy_rejects_mode_change");pause_r=0;wait_free();idle_roundtrip();busy_hits=busy_hits+1;
  // F02: all twelve statuses/cameras/slots, including a full prior read for status0.
  for(integer c=0;c<2;c=c+1)for(integer s=0;s<2;s=s+1)for(integer st=0;st<3;st=st+1)begin
   reset_to(2);publish(c,s,500+c*10+s);take_desc(c);xaddr=base(c,s);
   if(st==0)begin xlen=127;xv=1;#1;ck(xready,"prior_full_read_accepts");tick();xv=0;wait_read_done();ck(r_count==128,"prior_full_DMA_return_count");end
   xlen=0;stall_ar=1;pause_r=1;status=st;rc=c;rs=s;rseq=500+c*10+s;rv=1;xv=1;#1;ck(xready,"same_cycle_AR_accepts");
   tick();rv=0;xv=0;ck(held[c*2+s]&&arel==0&&brel==0&&arvalid,"accepted_AR_blocks_same_cycle_release");
   repeat(3)tick();ck(held[c*2+s]&&arvalid,"AR_stall_preserves_ownership");
   stall_ar=0;repeat(3)tick();pause_r=0;wait_read_done();release_desc(c,s,500+c*10+s,1);race_hits=race_hits+1;
  end
  // F01 same-edge take/refill, both cameras; fields and alternate mailbox are retained.
  for(integer c=0;c<2;c=c+1)begin
   reset_to(2);publish(c,1,601);
   if(c==0)begin abase=base(c,0);aseq=602;ap=1;adr=1;end else begin bbase=base(c,0);bseq=602;bp=1;bdr=1;end
   tick();ap=0;bp=0;adr=0;bdr=0;
   ck(c==0?(av&&aslot==0&&aq==602&&ab==base(c,0)):(bv&&bslot==0&&bq==602&&bb==base(c,0)),"same_edge_take_refill_identity");
   take_desc(c);release_desc(c,1,601,2);release_desc(c,0,602,2);refill_hits=refill_hits+1;
  end
  // Old epoch and duplicate releases cannot clear/recreate an offer.
  reset_to(2);publish(1,0,701);take_desc(1);rc=1;rs=0;rseq=701;repoch=6;status=2;rv=1;tick();rv=0;
  ck(held==4&&arel==0&&brel==0&&rejects>0,"stale_epoch_rejected");tick();release_desc(1,0,701,2);
  rv=1;tick();rv=0;tick();ck(held==0&&arel==0&&brel==0,"duplicate_release_rejected");idle_roundtrip();
  // Common reset cancels the model queue and ownership, never a consumer-only reset.
  reset_to(2);publish(0,1,801);take_desc(0);pause_r=1;xaddr=base(0,1);xv=1;tick();xv=0;repeat(3)tick();
  ck(rd_active&&held==2,"reset_case_has_actual_outstanding_read");reset_to(2);ck(held==0&&!av&&!bv&&!rd_active,"common_reset_cancels_all_ownership");
  if(failures)$fatal(1,"MODE_MATRIX_FAIL count=%0d",failures);
  $display("MODE_MATRIX_PASS mode_pub=%0d both_pub=1 busy=%0d AR_release=%0d take_refill=%0d stale_duplicate=1 reset=1",mode_pub_hits,busy_hits,race_hits,refill_hits);$finish;
 end
 initial begin #1000000;$fatal(1,"mode matrix watchdog");end
endmodule

