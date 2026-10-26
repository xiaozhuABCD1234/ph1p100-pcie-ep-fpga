`timescale 1ns/1ps
// Compare the production pipeline against the frozen 233658 sampler, whose
// module name is changed to bayer565_reference only in the run snapshot.
module tb_bayer565_pipeline;
 localparam SW=16,SH=2,N=SW*SH;
 reg clk=0,rst_n=0,frame=0,line=0,pv=0,fe=0,fg=0,abort_frame=0,ready=1;
 reg[39:0] pixels=0;
 wire os,ov,ol,ns,nv,nl,nfe,nfg,na;
 wire[15:0] od,nd;
 wire[31:0] osa,osb,osc,osd,osn,oseq,nsa,nsb,nsc,nsd,nsn,nseq;
 wire osv,nsv;
 wire[257:0] opack,npack;
 wire opv,npv;
 wire[31:0] odrops,ndrops;
 reg ps=0,pv_out=0,pl=0,pfe=0,pfg=0,pa=0;
 reg[15:0] pd=0;
 reg prev_pack_valid=0,prev_strict=0,strict_pack=1;
 reg[257:0] prev_pack_data=0;
 reg[31:0] prev_drops=0;
 reg[257:0] token_queue[0:4095];
 integer put=0,get=0,fixture=0,oracle_fixture=0,oracle_count=0;
 integer cycles=0,pixel_checks=0,latency_checks=0,verdict_checks=0,stat_checks=0,pack_checks=0;
 integer starts=0,words=0,footers=0,aborts=0,cases=0,stalled_cycles=0;
 integer consecutive=0,gaps=0,reset_cases=0,restart_cases=0;
 reg oracle_prev_valid=0;
 always #5 clk=~clk;
 bayer565_reference #(.SW(SW),.SH(SH),.BAYER_PHASE(3),
  .WB_R_GAIN_Q10(2400),.WB_B_GAIN_Q10(2062),.WB_BLACK_LEVEL(50)) reference_dut(
  .clk(clk),.rst_n(rst_n),.in_pixels(pixels),.in_valid(pv),.in_line(line),.in_frame(frame),
  .out_sof(os),.out_valid(ov),.out_last(ol),.out_data(od),
  .frame_end(fe),.frame_good(fg),.frame_abort(abort_frame),
  .stat_a(osa),.stat_b(osb),.stat_c(osc),.stat_d(osd),.stat_count(osn),.stat_sequence(oseq),.stat_valid(osv));
 bayer565_capture #(.SW(SW),.SH(SH),.BAYER_PHASE(3),
  .WB_R_GAIN_Q10(2400),.WB_B_GAIN_Q10(2062),.WB_BLACK_LEVEL(50)) dut(
  .clk(clk),.rst_n(rst_n),.in_pixels(pixels),.in_valid(pv),.in_line(line),.in_frame(frame),
  .out_sof(ns),.out_valid(nv),.out_last(nl),.out_data(nd),
  .frame_end(fe),.frame_good(fg),.frame_abort(abort_frame),
`ifdef PIPELINE_VERDICT_PORTS
  .out_frame_end(nfe),.out_frame_good(nfg),.out_frame_abort(na),
`endif
  .stat_a(nsa),.stat_b(nsb),.stat_c(nsc),.stat_d(nsd),.stat_count(nsn),.stat_sequence(nseq),.stat_valid(nsv));
`ifndef PIPELINE_VERDICT_PORTS
 assign nfe=fe,nfg=fg,na=abort_frame;
`endif
 rgb565_frame_pack_guarded #(.FRAME_BYTES(N*2)) old_packer(
  .clk(clk),.rst_n(rst_n),.sof(os),.pixel_valid(ov),.pixel_last(ol),.pixel(od),
  .frame_end(fe),.frame_good(fg),.frame_abort(abort_frame),
  .out_data(opack),.out_valid(opv),.out_ready(ready),.dropped_frames(odrops));
 rgb565_frame_pack_guarded #(.FRAME_BYTES(N*2)) new_packer(
  .clk(clk),.rst_n(rst_n),.sof(ns),.pixel_valid(nv),.pixel_last(nl),.pixel(nd),
  .frame_end(nfe),.frame_good(nfg),.frame_abort(na),
  .out_data(npack),.out_valid(npv),.out_ready(ready),.dropped_frames(ndrops));
 task fail(input string why);
  begin $display("BAYER565_PIPELINE_FAIL cycle=%0d fixture=%0d %s",cycles,fixture,why);$finish;end
 endtask
 function integer component(input integer f,input integer index,input integer channel);
  begin
   component=0;
   case(index%8)
    0:case(channel)0:component=200;1,2:component=160;3:component=100;endcase
    1:component=0;
    2:component=1023;
    3:case(channel)0:component=42;1:component=1022;2:component=6;3:component=41;endcase
    4:case(channel)0:component=49;1:component=0;2:component=1;3:component=51;endcase
    5:case(channel)0:component=51;1:component=508;2:component=512;3:component=49;endcase
    6:component=(f*97+index*31+channel*73)%1024;
    7:case(channel)0:component=648;1:component=1023;2:component=1022;3:component=694;endcase
   endcase
  end
 endfunction
 function integer balanced(input integer raw_value,input integer gain);
  integer delta,magnitude,rounded,result;
  begin
   delta=raw_value-50;magnitude=(delta<0)?-delta:delta;
   rounded=(magnitude*gain+512)/1024;
   result=50+((delta<0)?-rounded:rounded);
   balanced=(result<0)?0:((result>1023)?1023:result);
  end
 endfunction
 function[15:0] expected(input integer f,input integer index);
  integer r,g,b;
  begin
   r=balanced(component(f,index,0),2400)/32;
   g=(component(f,index,1)+component(f,index,2))/32;
   b=balanced(component(f,index,3),2062)/32;
   expected=r*2048+g*32+b;
  end
 endfunction

 // Packer handshakes and registered verdicts are sampled BEFORE NBA. This is
 // the data the packers consume; a post-edge monitor would miss cleared tokens.
 always @(posedge clk)begin
  cycles=cycles+1;
  if(!rst_n)begin
   put=0;get=0;pfe=0;pfg=0;pa=0;
   prev_pack_valid=0;prev_pack_data=0;prev_drops=0;prev_strict=0;
  end else begin
   if(nfe!==pfe||nfg!==pfg||na!==pa)
    fail($sformatf("verdict delay got=%b%b%b expected=%b%b%b",nfe,nfg,na,pfe,pfg,pa));
   verdict_checks=verdict_checks+1;
   pfe=fe;pfg=fg;pa=abort_frame;
   if(strict_pack&&prev_strict)begin
    if(npv!==prev_pack_valid||(npv&&npack!==prev_pack_data))fail("packer token is not exactly one cycle delayed");
    if(ndrops!==prev_drops)fail("packer drop timing is not exactly one cycle delayed");
    pack_checks=pack_checks+1;
   end
   prev_pack_valid=opv;prev_pack_data=opack;prev_drops=odrops;prev_strict=strict_pack;
   if(!ready)stalled_cycles=stalled_cycles+1;
   if(opv&&ready)begin
    if(put>=4096)fail("token queue overflow");
    token_queue[put]=opack;put=put+1;
    case(opack[257:256])0:words=words+1;1:starts=starts+1;2:footers=footers+1;3:aborts=aborts+1;endcase
   end
   if(npv&&ready)begin
    if(get>=put||npack!==token_queue[get])fail($sformatf("accepted token order/data index=%0d old_count=%0d type=%0d",get,put,npack[257:256]));
    get=get+1;
   end
  end
  #1;
  if(!rst_n)begin
   ps=0;pv_out=0;pl=0;pd=0;oracle_count=0;oracle_prev_valid=0;
   if(ns!==0||nv!==0||nl!==0||nfe!==0||nfg!==0||na!==0)fail("reset outputs");
  end else begin
   if(ns!==ps||nv!==pv_out||nl!==pl||(nv&&nd!==pd))
    fail($sformatf("display delay got=%b%b%b/%04h expected=%b%b%b/%04h",ns,nv,nl,nd,ps,pv_out,pl,pd));
   latency_checks=latency_checks+1;
   ps=os;pv_out=ov;pl=ol;pd=od;
   if({nsa,nsb,nsc,nsd,nsn,nseq,nsv}!=={osa,osb,osc,osd,osn,oseq,osv})fail("raw statistics changed or delayed");
   stat_checks=stat_checks+1;
   if(os)begin oracle_fixture=fixture;oracle_count=0;end
   if(ov)begin
    if(oracle_count>=N||od!==expected(oracle_fixture,oracle_count))fail($sformatf("independent color oracle index=%0d got=%04h expected=%04h",oracle_count,od,expected(oracle_fixture,oracle_count)));
    if(ol!==((oracle_count==N-1)?1'b1:1'b0))fail("reference last boundary");
    oracle_count=oracle_count+1;pixel_checks=pixel_checks+1;
    if(oracle_prev_valid)consecutive=consecutive+1;
   end else begin
    if(ol)fail("reference last without valid");
    if(oracle_prev_valid)gaps=gaps+1;
   end
   oracle_prev_valid=ov;
  end
 end

 task tick;begin @(negedge clk);end endtask
 task idle(input integer n);
  begin tick();pv=0;repeat(n)tick();end
 endtask
 task start_frame;
  begin tick();fixture=fixture+1;frame=1;line=0;pv=0;fe=0;fg=0;abort_frame=0;idle(3);end
 endtask
 task drive_row(input integer raw_row,input integer samples);
  integer c,index,a,b;
  begin
   tick();line=1;pv=0;tick();line=0;idle(1);
   for(c=0;c<samples;c=c+1)begin
    index=(raw_row/4)*SW+c;
    if(raw_row%4==0)begin a=component(fixture,index,1);b=component(fixture,index,3);end
    else if(raw_row%4==1)begin a=component(fixture,index,0);b=component(fixture,index,2);end
    else begin a=(raw_row*31+c)%1024;b=(raw_row*7+c*23)%1024;end
    if(c%5==2)idle(2);
    tick();pv=1;pixels={10'd881,10'd337,10'(b),10'(a)};
   end
  end
 endtask
 task complete_pixels;
  integer row;
  begin for(row=0;row<6;row=row+1)begin drive_row(row,SW);if(row!=5)idle(3);end end
 endtask
 // The final input sample is accepted on the edge immediately after this
 // task starts. offset=1 FE meets pending RAM data; offset=2 is the minimum
 // FE that the original packer can consume together with the final pixel.
 task verdict(input integer offset,input bit good,input bit abort_now);
  begin
   tick();pv=0;
   repeat(offset-1)tick();
   fe=1;fg=good;abort_frame=abort_now;
   tick();fe=0;fg=0;abort_frame=0;
  end
 endtask
 task finish_source;
  begin idle(5);tick();frame=0;line=0;idle(6);end
 endtask
 task drained(input string name);
  begin
   idle(8);
   if(put!=get||odrops!==ndrops)fail($sformatf("drain %s queued=%0d drops=%0d/%0d",name,put-get,odrops,ndrops));
   cases=cases+1;
  end
 endtask
 task good_case(input integer offset,input string name);
  integer f0,a0;
  begin
   f0=footers;a0=aborts;start_frame();complete_pixels();verdict(offset,1,0);finish_source();drained(name);
   if(footers!=f0+1||aborts!=a0||oracle_count!=N)fail($sformatf("good frame did not commit %s",name));
  end
 endtask
 integer f0,a0;
 initial begin
  if(expected(0,0)!==16'h6144)fail("literal oracle fixture");
  idle(3);rst_n=1;idle(3);
  good_case(6,"late_good_FE");
  good_case(2,"minimal_good_FE_with_final_pixel");
  good_case(3,"good_FE_after_final_pixel");
  f0=footers;a0=aborts;start_frame();complete_pixels();verdict(2,0,0);finish_source();drained("bad_FE");
  if(footers!=f0||aborts!=a0+1)fail("bad FE published");
  f0=footers;a0=aborts;start_frame();complete_pixels();verdict(2,1,1);finish_source();drained("abort_with_final_pixel_FE");
  if(footers!=f0||aborts!=a0+1)fail("abort published");
  f0=footers;a0=aborts;start_frame();complete_pixels();verdict(1,1,0);finish_source();drained("early_FE_at_final_pending");
  if(footers!=f0||aborts!=a0+1)fail("pending FE accepted before packer final pixel");
  f0=footers;a0=aborts;start_frame();drive_row(0,SW);idle(3);drive_row(1,8);verdict(3,1,0);finish_source();drained("early_partial_FE");
  if(footers!=f0||aborts!=a0+1)fail("short preview published");
  // A complete preview without FE remains speculative; the next SOF revokes it.
  f0=footers;a0=aborts;start_frame();complete_pixels();finish_source();
  if(footers!=f0)fail("missing FE published");
  start_frame();complete_pixels();verdict(3,1,0);finish_source();drained("missing_FE_new_SOF");
  if(footers!=f0||aborts!=a0+1)fail("missing FE restart ownership");
  good_case(2,"missing_FE_recovery");
  // Restart while the old final partial sample is still in the WB pipeline.
  f0=footers;a0=aborts;start_frame();drive_row(0,SW);idle(3);drive_row(1,4);
  tick();pv=0;frame=0;tick();fixture=fixture+1;frame=1;line=0;idle(3);
  complete_pixels();verdict(3,1,0);finish_source();drained("restart_pending");restart_cases=restart_cases+1;
  if(footers!=f0||aborts!=a0+1)fail("restart pending ownership");
  // Reset after reference output exists but before its delayed output exists.
  start_frame();drive_row(0,SW);idle(3);drive_row(1,1);tick();pv=0;
  tick();if(!ov||nv)fail("reset in-flight precondition");rst_n=0;frame=0;line=0;fe=0;fg=0;abort_frame=0;
  idle(3);rst_n=1;idle(4);reset_cases=reset_cases+1;
  good_case(2,"reset_inflight_recovery");
  // Shared ready is intentionally stationary at SOF and DATA word boundaries.
  // A pending footer/abort may be released on the same edge in both packers,
  // so these cases compare accepted token order instead of exact cycle shift.
  strict_pack=0;f0=footers;a0=aborts;start_frame();complete_pixels();idle(5);ready=0;
  verdict(1,1,0);idle(8);if(footers!=f0)fail("stalled footer consumed");
  tick();ready=1;finish_source();drained("stalled_footer");
  if(footers!=f0+1||aborts!=a0)fail("stalled footer lost");
  f0=footers;a0=aborts;start_frame();drive_row(0,SW);idle(3);drive_row(1,8);idle(5);ready=0;
  verdict(1,0,0);idle(8);tick();ready=1;finish_source();drained("stalled_abort");
  if(footers!=f0||aborts!=a0+1)fail("stalled abort lost");
  strict_pack=1;good_case(2,"final_recovery");
  if(cases!=14||reset_cases!=1||restart_cases!=1||stalled_cycles==0||consecutive==0||gaps==0||put!=get)
   fail($sformatf("coverage cases=%0d reset=%0d restart=%0d stalls=%0d consecutive=%0d gaps=%0d",cases,reset_cases,restart_cases,stalled_cycles,consecutive,gaps));
  $display("BAYER565_PIPELINE_PASS cases=%0d pixel_checks=%0d latency_checks=%0d verdict_checks=%0d stat_checks=%0d pack_checks=%0d starts=%0d words=%0d footers=%0d aborts=%0d stalls=%0d reset_inflight=%0d restart_pending=%0d",
   cases,pixel_checks,latency_checks,verdict_checks,stat_checks,pack_checks,starts,words,footers,aborts,stalled_cycles,reset_cases,restart_cases);
  $finish;
 end
 initial begin #500000;fail("watchdog");end
endmodule
