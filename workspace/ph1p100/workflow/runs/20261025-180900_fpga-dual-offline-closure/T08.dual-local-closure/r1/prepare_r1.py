from pathlib import Path
import hashlib,json,shutil,difflib
H=Path(__file__).resolve().parent;R0=H.parent;RUN=R0.parent
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
m=json.loads((R0/'manifest-r0.json').read_text())
assert sha(R0/'manifest-r0.json')=='264b067bc4f363cb835616ce7f15fa4db996f0a0621ab3c7a6725ab7ff72058e'
assert all(sha(Path(f['path']))==f['sha256'] for f in m['files'])
for p in (R0/'candidate').rglob('*'):
 if p.is_file():
  q=H/'candidate'/p.relative_to(R0/'candidate');q.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(p,q)
for name in ['run_t08.py','run_aux.py','check_t08.py','r10f_oracle.py','sync_i2c_config.v','sync_frame_gate.v','vendor_env.sv','sensor_i2c.sv','tb_production_sync.sv','tb_production_sync_legacy.sv','tb_dual_contract.sv']:
 shutil.copyfile(R0/name,H/name)
edge=RUN/'test-reports/T08.dual-local-closure/tb_tester_edges.sv';shutil.copyfile(edge,H/edge.name)
s=(R0/'dual_local_closure.v').read_text()
s=s.replace('reg [1:0] ext_owner;','reg [1:0] ext_owner;\n reg a_offer,b_offer;reg [1:0] a_index,b_index;')
s=s.replace("wire [1:0] ai=held[0]&&!sent[0]?2'd0:2'd1;",'wire [1:0] ai=a_index;')
s=s.replace("wire [1:0] bi=held[2]&&!sent[2]?2'd2:2'd3;",'wire [1:0] bi=b_index;')
s=s.replace('((held[0]&&!sent[0])||(held[1]&&!sent[1]))','a_offer').replace('((held[2]&&!sent[2])||(held[3]&&!sent[3]))','b_offer')
s=s.replace(' assign ext_rid=rid;', ' wire ext_take=ext_arvalid&&ext_arready;\n assign ext_rid=rid;')
s=s.replace('active_mode<=DEFAULT_MODE;mode_seen<=DEFAULT_MODE;', 'a_offer<=0;b_offer<=0;a_index<=0;b_index<=2;\n   active_mode<=DEFAULT_MODE;mode_seen<=DEFAULT_MODE;')
s=s.replace('if(a_desc_valid&&a_desc_ready) sent[ai]<=1;\n    if(b_desc_valid&&b_desc_ready) sent[bi]<=1;', '''// Registered presentation identity is held until ready/valid transfer.
    // Exclude the taken slot, retain the other mailbox, and accept simultaneous refill.
    if(a_desc_valid&&a_desc_ready) sent[ai]<=1;
    if(b_desc_valid&&b_desc_ready) sent[bi]<=1;
    if(!a_offer || a_desc_ready) begin
     if(available[0] && !(a_offer&&a_desc_ready&&ai==0)) begin a_offer<=1;a_index<=0;end
     else if(available[1] && !(a_offer&&a_desc_ready&&ai==1)) begin a_offer<=1;a_index<=1;end
     else if(a_pub_valid && (a_pub_base==slot_base(0)||a_pub_base==slot_base(1)) && !held[a_pub_base==slot_base(1)] && a_pub_len==DMA_BYTES) begin
      a_offer<=1;a_index<=a_pub_base==slot_base(1)?1:0;
     end else a_offer<=0;
    end
    if(!b_offer || b_desc_ready) begin
     if(available[2] && !(b_offer&&b_desc_ready&&bi==2)) begin b_offer<=1;b_index<=2;end
     else if(available[3] && !(b_offer&&b_desc_ready&&bi==3)) begin b_offer<=1;b_index<=3;end
     else if(b_pub_valid && (b_pub_base==slot_base(2)||b_pub_base==slot_base(3)) && !held[b_pub_base==slot_base(3)?3:2] && b_pub_len==DMA_BYTES) begin
      b_offer<=1;b_index<=b_pub_base==slot_base(3)?3:2;
     end else b_offer<=0;
    end''')
s=s.replace('!ar_pending&&outstanding==0&&\n        ((rel_status', '!ar_pending&&outstanding==0&&!ext_take&&\n        ((rel_status')
assert s!=(R0/'dual_local_closure.v').read_text() and '!ext_take&&' in s
(H/'dual_local_closure.v').write_text(s,encoding='utf-8')
(H/'rtl-repair.diff').write_text(''.join(difflib.unified_diff((R0/'dual_local_closure.v').read_text().splitlines(True),s.splitlines(True),fromfile=(R0/'dual_local_closure.v').as_posix(),tofile=(H/'dual_local_closure.v').as_posix())),encoding='utf-8')
env=(H/'vendor_env.sv').read_text().replace('integer read_delay=0,delay_q=0;','integer read_delay=0,delay_q=0,inter_beat_delay=0;')
env=env.replace('r_count<=r_count+1;read_valid<=0;', 'delay_q<=inter_beat_delay;\n          r_count<=r_count+1;read_valid<=0;')
(H/'vendor_env.sv').write_text(env,encoding='utf-8')
tb=(H/'tb_production_sync.sv').read_text()
tb=tb.replace('integer releases_a=0,releases_b=0;', 'integer overlap_sof_a=0,overlap_sof_b=0,overlap_pub_a=0,overlap_pub_b=0;reg read_window=0;reg vs_a_old=0,vs_b_old=0;\n integer releases_a=0,releases_b=0;')
body='''  if(case_id==16) begin
   dut.u_ddr3_mc_0.inter_beat_delay=100;
   fork frame(0,60);frame(1,60);join
   wait(pubs_a==1 && pubs_b==1);wait(read_window);ticks(4);
   check(dut.g_dual_local.u_local.outstanding!=0,"overlap starts only after actual accepted AR");
   fork frame(0,61);frame(1,61);join
   wait(pubs_a==2 && pubs_b==2);ticks(4);
   check(dut.local_held==15 && read_window,"other-slot publication completes while first read is active");
   $fdisplay(events,"OVERLAP_FULL_HIT %0t held=%0d",$time,dut.local_held);
   fork frame(0,62);frame(1,62);join
   ticks(100);
   fork frame(0,63);frame(1,63);join
   ticks(1000);
   check(pubs_a==2 && pubs_b==2 && dut.cl_writer_bad>0 && dut.b_cl_bad>0,"overlap protected slots drop whole new frames and count them");
   $fdisplay(events,"OVERLAP_DROP_HIT %0t badA=%0d badB=%0d",$time,dut.cl_writer_bad,dut.b_cl_bad);
   wait(dut.local_held==0);dut.u_ddr3_mc_0.inter_beat_delay=0;ticks(20);
   check(overlap_sof_a>=2 && overlap_sof_b>=2 && overlap_pub_a>=1 && overlap_pub_b>=1,"actual AR-to-last-R overlap for both cameras");
   $fdisplay(events,"OVERLAP_HIT SOFA=%0d SOFB=%0d PUBA=%0d PUBB=%0d",overlap_sof_a,overlap_sof_b,overlap_pub_a,overlap_pub_b);
  end
'''
tb=tb.replace('  three_good();\n  if(case_id==4)', body+'  three_good();\n  if(case_id==4)',1)
tb=tb.replace('else begin\n   if(ar_stall)', '''else begin
   if(dut.w_ddr_arvalid&&dut.w_ddr_arready) begin read_window=1;$fdisplay(events,"DAR %0d %0t %08x %0d",epoch,$time,dut.w_ddr_araddr,dut.w_ddr_arlen+1);end
   if(dut.w_ddr_rvalid&&dut.w_ddr_rready&&dut.w_ddr_rlast) begin read_window=0;$fdisplay(events,"DRLAST %0d %0t",epoch,$time);end
   if(case_id==16 && read_window && dut.cl_pub_valid) overlap_pub_a=overlap_pub_a+1;
   if(case_id==16 && read_window && dut.b_cl_pub_valid) overlap_pub_b=overlap_pub_b+1;
   if(ar_stall)''')
tb=tb.replace('ar_stall=0;end','ar_stall=0;read_window=0;end')
mon='''
 always @(posedge ca) begin
  if(!por) vs_a_old<=0;
  else begin
   if(dut.w_a_vsync&&!vs_a_old) begin
    $fdisplay(events,"OSOF %0d %0t 0 %0d",epoch,$time,fid_a);
    if(case_id==16&&read_window) overlap_sof_a=overlap_sof_a+1;
   end
   vs_a_old<=dut.w_a_vsync;
  end
 end
 always @(posedge cb) begin
  if(!por) vs_b_old<=0;
  else begin
   if(dut.w_b_vsync&&!vs_b_old) begin
    $fdisplay(events,"OSOF %0d %0t 1 %0d",epoch,$time,fid_b);
    if(case_id==16&&read_window) overlap_sof_b=overlap_sof_b+1;
   end
   vs_b_old<=dut.w_b_vsync;
  end
 end
'''
tb=tb.replace('endmodule',mon+'endmodule')
assert 'OVERLAP_HIT' in tb and 'DAR %0d' in tb
(H/'tb_production_sync.sv').write_text(tb,encoding='utf-8')
runner=(H/'run_t08.py').read_text().replace("files += [H/'tb_dual_contract.sv'", "files += [H/'tb_tester_edges.sv',H/'tb_repair_matrix.sv',H/'tb_dual_contract.sv'")
(H/'run_t08.py').write_text(runner,encoding='utf-8')
hist={'round0':{'functions_exec_calls':40,'functions_wait_calls':1,'nested_native_tool_calls':60,'tool_call_accounting':'reconstructed by enumerating this original developer conversation; count both surfaces conservatively','conservative_combined_calls':101,'original_tool_limit':60,'historical_limit_overrun':True,'compiles':4,'case_processes':19,'actual_repair_rounds':0},'round1_limits':{'conservative_combined_calls':45,'compiles':3,'case_processes':14,'deadline_shanghai':'2026-10-25T21:02:49+08:00'},'original_tester_edges':{'tester_attempts_used':1,'tester_remaining':1,'developer_round0_attempts':0},'disclosure':'The r0 artifact omitted tool counts; recovered transcript counts expose an r0 conservative-accounting overrun. This is retained as history and not represented as0 or made compliant by the new repair window.'}
(H/'historical-execution-accounting.json').write_text(json.dumps(hist,indent=2),encoding='utf-8')
(H/'r0-freeze-audit-before.json').write_text(json.dumps({'manifest_sha256':sha(R0/'manifest-r0.json'),'files_verified':len(m['files']),'mismatch':0,'original_edge_sha256':sha(edge)},indent=2),encoding='utf-8')
print('R1_PREPARED actual_DUT_F01_F02_changes=1 protected_r0_files='+str(len(m['files'])))
