from pathlib import Path
import argparse,datetime,difflib,hashlib,json,re,sys
H=Path(__file__).resolve().parent;R0=H.parent;RUN=R0.parent
DEADLINE=datetime.datetime.fromisoformat('2026-10-25T13:02:49.045073+00:00')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def dump(name,data):
 (H/name).write_text(json.dumps(data,indent=2),encoding='utf-8')
def main():
 p=argparse.ArgumentParser();p.add_argument('--outer-calls',type=int,required=True);p.add_argument('--native-calls',type=int,required=True);p.add_argument('--wait-calls',type=int,default=0);a=p.parse_args()
 assert datetime.datetime.now(datetime.timezone.utc)<DEADLINE,'repair deadline exceeded'
 combined=a.outer_calls+a.native_calls+a.wait_calls;assert combined<=45
 required=['original-edges','matrix','case16','case00','case10','case11','case12','case13','case14','case15','contract','legacy','negative']
 results=[]
 for name in required:
  out=H/'local'/name;r=json.loads((out/'case-result.json').read_text());assert r['pass'],'required case failed '+name
  if name.startswith('case'):
   o=json.loads((out/'oracle-result.json').read_text());assert o['pass']
  results.append({'name':name,'path':str(out/'case-result.json'),'seconds':r['elapsed_seconds'],'pass':r['pass'],'negative_fixture':name=='negative'})
 overlap=json.loads((H/'local/case16/overlap-result.json').read_text());assert overlap['pass']
 commands=[]
 for log in (H/'local').rglob('*.log'):
  for line in log.read_text(encoding='utf-8',errors='replace').splitlines():
   if line.startswith('COMMAND_RESULT '):commands.append(json.loads(line[len('COMMAND_RESULT '):]))
 commands=list({c['log']:c for c in commands}.values())
 assert all(isinstance(c['exit_code'],int) and not c['timeout'] for c in commands),'unfinished or timed-out command'
 compiles=sum(Path(c['command'][0]).name.lower()=='vlog.exe' for c in commands)
 cases=sum(Path(c['command'][0]).name.lower()=='vsim.exe' for c in commands)
 assert compiles<=3 and cases<=14 and cases>=13
 old=json.loads((R0/'manifest-r0.json').read_text());assert sha(R0/'manifest-r0.json')=='264b067bc4f363cb835616ce7f15fa4db996f0a0621ab3c7a6725ab7ff72058e'
 assert all(sha(Path(f['path']))==f['sha256'] for f in old['files']),'protected r0 drift'
 report=RUN/'test-reports/T08.dual-local-closure-r0-integrated.md';assert sha(report)=='2bddce8c19cd71727609eaee04bfedc141d280f0b87b55fccc837d183aa86fa6'
 dump('r0-freeze-audit-after.json',{'manifest_sha256':sha(R0/'manifest-r0.json'),'files_verified':len(old['files']),'mismatch':0,'original_report_sha256':sha(report)})
 dump('commands.json',commands);dump('case-results.json',{'round':1,'required':results,'overlap':overlap})
 counts={'round0':{'functions_exec_calls':40,'functions_wait_calls':1,'native_tool_operations':60,'conservative_combined_calls':101,'historical_limit':60,'historical_limit_overrun':True,'compiles':4,'case_processes':19},
 'round1':{'functions_exec_calls':a.outer_calls,'functions_wait_calls':a.wait_calls,'native_tool_operations':a.native_calls,'conservative_combined_calls':combined,'limit':45,'compiles':compiles,'compile_limit':3,'case_processes':cases,'case_limit':14,'actual_implementation_repair_round':1},
 'cumulative':{'functions_exec_calls':40+a.outer_calls,'functions_wait_calls':1+a.wait_calls,'native_tool_operations':60+a.native_calls,'conservative_combined_calls':101+combined,'compiles':4+compiles,'case_processes':19+cases},
 'original_tester_edges':{'tester_used_before_r1':1,'tester_remaining':1,'developer_original_edges_this_repair':1,'developer_original_edges_failure_count':0,'no_tester_count_reset':True},
 'deadline_shanghai':'2026-10-25T21:02:49.045073+08:00','finished_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
 'historical_count_basis':{'native_counts_by_original_functions_exec':[1,1,1,1,1,1,1,1,1,2,1,1,2,2,1,1,2,2,1,1,1,4,2,1,3,1,3,3,1,2,1,2,1,2,1,2,1,2,1,1],'functions_wait':1,'description':'reconstructed from retained original developer conversation; r0 artifact omitted these counts. The conservative combined r0 overrun is disclosed, not reset or represented as compliant.'},
 'td':0,'hardware':0,'download':0,'flash':0,'mapping_changes':0,'external_messages':0,'automatic_retries':0,'active_commands':0}
 assert sum(counts['historical_count_basis']['native_counts_by_original_functions_exec'])==60
 dump('execution-budget-r1.json',counts)
 baseline=json.loads((H/'local/build-baseline/sources.json').read_text());assert all(sha(Path(x['path']))==x['sha256'] for x in baseline),'baseline compiled-input drift'
 real=[Path(x['path']) for x in baseline if Path(x['path']).suffix=='.v' and Path(x['path']).name not in {'vendor_env.sv','sensor_i2c.sv'}]
 (H/'sources.f').write_text('\n'.join(p.as_posix() for p in real)+'\n',encoding='utf-8')
 (H/'integration-sources.tcl').write_text('set rtl_sources [list \\\n'+''.join(' {'+p.as_posix()+'} \\\n' for p in real)+']\nforeach p $rtl_sources {if {![file isfile $p]} {error "missing source $p"}}\n# Source closure only; no TD invocation.\n',encoding='utf-8')
 mapping=[]
 for item in baseline:
  new=Path(item['path']);old_path=R0/new.relative_to(H)
  if new.name=='tb_tester_edges.sv':old_path=RUN/'test-reports/T08.dual-local-closure/tb_tester_edges.sv'
  mapping.append({'r1_path':str(new),'r1_sha256':item['sha256'],'r0_path':str(old_path) if old_path.is_file() else None,'r0_sha256':sha(old_path) if old_path.is_file() else None,'content_changed':not old_path.is_file() or sha(old_path)!=item['sha256']})
 dump('source-map.json',mapping)
 changed=[x for x in mapping if x['content_changed']]
 dump('change-impact.json',{'changed_sources':changed,'RTL_change':'dual_local_closure only: registered presentation identity and current-cycle ext_take release exclusion','CDC_reset':'new presentation registers use existing common DHI clk/rst; no new crossing or clock/reset source','interfaces':'port names/widths and metadata format unchanged; backpressured fields now stable; same-cycle AR wins over release and retains held slot','DDR_environment':'inter_beat_delay is zero for original regressions and100 DHI cycles for case16 only; actual accepted AR/final R timestamps are recorded','affected_dimensions':['functional','engineering','system'],'unaffected_I2C_sync':'table/ui_i2c/sync_i2c_config/sync modules/frame gate/checker/writer/top are byte-identical copied sources; reuse remains the original tester decision'})
 reuse={'decision':'proposal_only; original integrated tester must approve per-file evidence reuse against manifest-r1','changed_input_retest':['original tester_edges once remaining attempt','new all-camera/slot/status matrix','case16 real overlap and actual-R oracle','case0','case10','case11','case12','case13','case14','case15','contract','legacy','B-release-to-A mutation'],
 'possible_unaffected_evidence':['original tester cases1-9 pin-specific I2C/sync error sequences, subject to exact unchanged RTL SHA, same clocks/parameters/stimulus portions, DDR inter_beat_delay=0 and documented impact review'],
 'never_reuse':['F01/F02 failed result as pass','r0 missing overlap as coverage','changed descriptor/AR/ownership checks without new run','old G2/G3/G4'],
 'old_report':str(report),'old_reuse_decision':str(RUN/'test-reports/T08.dual-local-closure/reuse-decision-r0.json'),'new_source_map':str(H/'source-map.json'),'original_tester_edges_attempts_used':1,'original_tester_edges_attempts_remaining':1}
 dump('reuse-proposal-r1.json',reuse)
 retest={'required_dimensions':['functional','engineering','system'],'required_checks':reuse['changed_input_retest'],'report_paths':[str(report),str(H/'result-r1.md'),str(H/'case-results.json'),str(H/'change-impact.json')],'input_status':'changed','reuse_decision_paths':[str(H/'reuse-proposal-r1.json'),reuse['old_reuse_decision']]}
 dump('retest-r1.json',retest)
 warnings=[]
 for log in (H/'local').rglob('*.log'):
  for line in log.read_text(encoding='utf-8',errors='replace').splitlines():
   if '** Warning' in line:warnings.append({'log':str(log),'line':line})
 dump('warning-audit-r1.json',{'warnings':warnings,'boundary':'RDGN inherited redundant digit warning; TFMPC deliberately unused environment/exported output ports remain visible; read all original warning lines. No target width/multiple-driver warning is waived.'})
 rows=['# T08 development repair round1 result','','Independent round0 FAIL and all r0 evidence are retained. This records developer local verification; integrated round1 acceptance remains pending.','', 'Actual RTL fixes: F01 latches a per-camera presentation selector until transfer, preserves the alternate mailbox and handles same-edge take/refill. F02 includes ext_arvalid&&ext_arready in release eligibility, so an accepted request cannot outlive released ownership. All ports, payload format, top/writer/checker/I2C/sync sources remain unchanged.','', '|Check|Local result|','|---|---|']
 for r in results:rows.append(f"|{r['name']}|required marker/byte or ownership checks satisfied; {r['seconds']:.3f}s|")
 rows+=['', 'F03 uses the actual production checked CSI and writers. DDR read/write operate concurrently; inter-beat R delay100 extends accepted read spans with bounded progress and keeps the same timeout/drain rules. Each camera supplies at least two new SOFs and a complete slot1 publication during an actual AR-to-final-R interval. Four slots held, whole-frame drop counters and sequence gaps are explicitly checked, followed by six good pairs and actual-R CRC/pattern/tail verification. Exact intervals, source identities and addresses are in local/case16/overlap-result.json.','', 'The original tester_edges source is byte-identical and locally passes; the original tester has used one attempt and has only one remaining corrected-input rerun. The new matrix covers both cameras, both initial slot orders, same-edge take/refill, all twelve status/camera/slot AR-release races, delayed R, and LOCK/common reset. The B-release-to-A fixture is correctly compiled in a separate library and rejected by the release-route assertion. The negative Fatal is expected fixture evidence, not a DUT failure or a pass inferred from exit0.','',f'Current repair: {compiles}/3 compiles, {cases}/14 case processes, conservative tool calls {combined}/45. Cumulative compile={4+compiles}, cases={19+cases}. Historical r0 tool recovery is disclosed:40 functions.exec +1 functions.wait +60 nested native operations =101 conservatively counted, exceeding the old60 limit; the old artifact had omitted this value. The new dispatch does not erase that overrun or reset attempt history.','', 'All native commands have final wait/exit records and no timeout. r0 manifest and492 participating files match before/after; source-map.json binds every baseline source SHA. G0/G1 await the original integrated tester. Physical G2 and hardware G3/G4 remain not_run/awaiting_hardware; no TD, board, mapping, download, Flash, RK, Git or external-message action occurred. Default geometry/address bounds and clock/reset architecture are unchanged; small offline cases do not establish real-time dual1080p30 or exposure synchronization.','', 'Rollback is to stop adopting r1. Production and r0 were never overwritten. Read reuse-proposal-r1.json and retest-r1.json for affected checks and conditional reuse; only the original tester can bind reused evidence to the new manifest.']
 (H/'result-r1.md').write_text('\n'.join(rows)+'\n',encoding='utf-8')
 (H/'interface-map-r1.md').write_text('''# Round1 interface/source map

The port and clock contract is unchanged from the protected r0 interface-map.md. All new DUT flops are presentation selector/valid registers in the same DHI domain and common DDR reset. Metadata arrays remain immutable while held. On handshake the current index is excluded from the next selection, the alternate pending slot is preferred, and a valid incoming publication can refill the offer on that same edge. No mailbox or valid input is suppressed to satisfy the stall rule.

External native AXI acceptance is ext_take. Release eligibility checks ext_take as well as the existing registered AR pending and outstanding counts. Thus a read accepted into the skid cannot race with release of its ownership; pending AR remains valid/stable until DDR accepts it, expected R beats must drain, and permanent missing R retains ownership until common DDR reset.

case16 changes only the independent DDR environment timing: inter_beat_delay=100, original cases=0. TB logs DAR and DRLAST from actual native handshakes; OSOF comes from real checked CSI output. The parser reconstructs those time spans and requires both camera SOFs and alternate-slot publications inside them, plus protected drop evidence and later good reads. Production writer, checked CSI, CRC, arbiter and sync are never replaced.

Use Python -B -X utf8 to avoid writing bytecode into frozen source directories. run_t08.py compile/case compiles r1 sources; run_repair.py early/regression are finite developer reproduction entries. The original tester should use its own output/work directories and new manifest, preserve its single remaining original tester_edges attempt, and independently decide reuse from source-map.json/reuse-proposal-r1.json. sources.f/integration-sources.tcl are source integration entries only and invoke no TD.
''',encoding='utf-8')
 (H/'lessons-r1.md').write_text('''# T08 repair1 lessons

- A mailbox retaining an item does not guarantee valid/ready stability. Register the offered index; a newly published higher-priority slot must not replace an already presented stalled identity. Explicitly test both cameras, both slot arrival orders and simultaneous take/refill.
- Sequential release checks must include same-cycle accepted AR events, not just old registered pending/outstanding state. Keep read acceptance and slot release in one arbitration decision, and test every status/camera/slot combination before permitting writer reuse.
- Continued arrival needs time-based evidence from accepted AR through the final valid R beat. Internal busy or sequential write-then-read loops cannot establish overlap. A bounded per-beat DDR delay provides concurrent write/consume pressure while preserving timeout and drain semantics.
- Capture actual protected-drop counters, identity/address intervals and post-drop capture-sequence gaps, then verify later complete good frames from actual R bytes. A test that merely fills four mailboxes is insufficient for overlap.
- Preserve failed r0 evidence and per-role attempt history. Recover missing call counts explicitly: this transcript exposes a conservative r0 overrun, which cannot be repaired by calling it0 or restarting a role. Count wrappers and nested operations conservatively in the repair window.
- The original tester owns independent acceptance and evidence-reuse decisions. A developer rerun does not reset or spend that tester's one remaining original-edge retry.
''',encoding='utf-8')
 tools=[]
 for item in old['tools']:
  q=Path(item['path']);assert sha(q)==item['sha256'];tools.append(item)
 files=[]
 for q in sorted(H.rglob('*')):
  if q.is_file() and q.name!='manifest-r1.json' and '__pycache__' not in q.parts and 'work' not in q.parts and q.suffix.lower() not in {'.wlf','.mti','.dat','.dbs','.qdb','.wdb'}:files.append({'path':str(q),'sha256':sha(q),'bytes':q.stat().st_size})
 refs=[R0/'manifest-r0.json',report,RUN/'dispatch-T08-repair-r1.json',RUN/'T08-repair-r1-plan.md',RUN/'fpga-design-guide.md',RUN/'dev-plan.md',RUN/'planning-input-manifest.json']
 manifest={'schema':'fpga-frozen-development-v1','task_ids':['T08.dual-local-closure'],'round':1,'project_root':r'D:\fpga\ph1p100','candidate_root':str(H/'candidate'),'RTL_overlay':str(H/'dual_local_closure.v'),'created_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'stopped_modifying':True,'active_commands':0,'files':files,'input_references':[{'path':str(q),'sha256':sha(q)} for q in refs],'tools':tools,'parameters':old['parameters']|{'case16_inter_beat_delay_DHI':100,'normal_inter_beat_delay_DHI':0},'environment_substitutes':old['environment_substitutes'],'commands_path':str(H/'commands.json'),'source_map_path':str(H/'source-map.json'),'test_input_paths':[str(H/n) for n in ['run_t08.py','run_repair.py','tb_tester_edges.sv','tb_repair_matrix.sv','tb_production_sync.sv','check_t08.py','case-results.json','reuse-proposal-r1.json','retest-r1.json']],'lessons_path':str(H/'lessons-r1.md'),'retest':retest,'actual_counts':counts,'gates':{'G0':'pending_original_integrated_test','G1':'pending_original_integrated_test','G2':'not_run','G3':'not_run/awaiting_hardware','G4':'not_run/awaiting_hardware'}}
 assert datetime.datetime.now(datetime.timezone.utc)<DEADLINE,'repair deadline exceeded before freeze'
 dump('manifest-r1.json',manifest)
 assert all(sha(Path(f['path']))==f['sha256'] for f in files),'post-freeze drift'
 print(json.dumps({'status':'ready_for_test','manifest_path':str(H/'manifest-r1.json'),'manifest_sha256':sha(H/'manifest-r1.json'),'files':len(files),'stopped_modifying':True,'active_commands':0,'actual_counts':{'round1':counts['round1'],'cumulative':counts['cumulative']}}),flush=True)
if __name__=='__main__':main()
