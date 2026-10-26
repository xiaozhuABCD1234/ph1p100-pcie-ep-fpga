from pathlib import Path
import argparse,datetime,hashlib,json
H=Path(__file__).resolve().parent;R1=H.parent;R0=R1.parent;RUN=R0.parent
DEADLINE=datetime.datetime.fromisoformat('2026-10-25T14:44:20+00:00')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def dump(n,v):(H/n).write_text(json.dumps(v,indent=2),encoding='utf-8')
def main():
 a=argparse.ArgumentParser();a.add_argument('--outer-calls',type=int,required=True);a.add_argument('--native-calls',type=int,required=True);a.add_argument('--wait-calls',type=int,default=0);p=a.parse_args()
 calls=p.outer_calls+p.native_calls+p.wait_calls;assert calls<=30
 assert datetime.datetime.now(datetime.timezone.utc)<DEADLINE
 required=['old-mode-negative','mode-matrix','original-edges','case16','case00','case10','case11','case12','case13','case14','legacy','bad-b-negative']
 receipts=[]
 for name in required:
  out=H/'local'/name;r=json.loads((out/'case-result.json').read_text());assert r['pass'],name+' not passed'
  if name.startswith('case'):assert json.loads((out/'oracle-result.json').read_text())['pass']
  receipts.append({'name':name,'receipt_path':str(out/'case-result.json'),'receipt_sha256':sha(out/'case-result.json'),'seconds':r['elapsed_seconds'],'expected_negative':name.endswith('negative')})
 commands=[]
 for log in (H/'local').rglob('*.log'):
  for line in log.read_text(encoding='utf-8',errors='replace').splitlines():
   if line.startswith('COMMAND_RESULT '):commands.append(json.loads(line[len('COMMAND_RESULT '):]))
 commands=list({r['log']:r for r in commands}.values());assert all(isinstance(r['exit_code'],int) and not r['timeout'] for r in commands)
 compiles=sum(Path(r['command'][0]).name.lower()=='vlog.exe' for r in commands);cases=sum(Path(r['command'][0]).name.lower()=='vsim.exe' for r in commands)
 assert compiles<=2 and cases==12
 protected=R1/'static-closeout01/manifest-r1.json';assert sha(protected)=='1b14a2201403389d4ae085e3c5f3141e382d600c9d3d50988527ad5eb617f544'
 pm=json.loads(protected.read_text());assert all(sha(Path(f['path']))==f['sha256'] for f in pm['files'])
 r0m=json.loads((R0/'manifest-r0.json').read_text());assert all(sha(Path(f['path']))==f['sha256'] for f in r0m['files'])
 compiled=json.loads((H/'local/build/sources.json').read_text());assert all(sha(Path(f['path']))==f['sha256'] for f in compiled)
 dump('protected-input-audit.json',{'static_manifest_sha256':sha(protected),'protected_static_files':len(pm['files']),'protected_r0_files':len(r0m['files']),'compiled_source_count':len(compiled),'drift':0})
 dump('commands.json',commands);dump('case-results.json',receipts)
 mode=(H/'dual_local_closure.v').read_text();prior=(R1/'dual_local_closure.v').read_text()
 oldfixture=(H/'fixtures/old_mode.v').read_text();badfixture=(H/'fixtures/bad_b_release.v').read_text()
 assert oldfixture==prior.replace('module dual_local_closure #(','module dual_local_closure_old_mode #(',1)
 needle='if(rel_camera_id) b_release<=rel_slot_id?2:1;else a_release<=rel_slot_id?2:1;'
 assert badfixture==mode.replace('module dual_local_closure #(','module dual_local_closure_bad_b #(',1).replace(needle,'if(rel_camera_id) a_release<=rel_slot_id?2:1;else a_release<=rel_slot_id?2:1;')
 dump('fixture-provenance.json',{'old_mode':{'source':str(R1/'dual_local_closure.v'),'source_sha256':sha(R1/'dual_local_closure.v'),'fixture_sha256':sha(H/'fixtures/old_mode.v'),'only_transform':'module alias for isolated compilation','same_checker':'tb_mode_matrix DUT_KIND1 vs0','required_observed_rejection':['publication_must_keep_current_mode','no_phantom_after_idle_roundtrip','MODE_MATRIX_FAIL count']},'bad_B':{'source_sha256':sha(H/'dual_local_closure.v'),'fixture_sha256':sha(H/'fixtures/bad_b_release.v'),'only_transforms':['module alias','mode2 B release redirected to A'],'required_observed_rejection':['B_release_routes_only_B','MODE_MATRIX_FAIL count']}})
 mapping=[]
 for f in compiled:
  q=Path(f['path']);old=R1/q.relative_to(H)
  mapping.append(f|{'previous_path':str(old) if old.is_file() else None,'previous_sha256':sha(old) if old.is_file() else None,'content_changed':not old.is_file() or sha(old)!=f['sha256'],'test_fixture':q.parent.name=='fixtures'})
 dump('source-map.json',mapping)
 real=[Path(f['path']) for f in compiled if Path(f['path']).suffix=='.v' and 'fixtures' not in Path(f['path']).parts]
 (H/'sources.f').write_text('\n'.join(q.as_posix() for q in real)+'\n')
 (H/'integration-sources.tcl').write_text('set rtl_sources [list \\\n'+''.join(' {'+q.as_posix()+'} \\\n' for q in real)+']\nforeach p $rtl_sources {if {![file isfile $p]} {error "missing source $p"}}\n# Source closure only; no TD invocation.\n')
 counts={'historical_before_window':{'conservative_calls':125,'compiles':6,'cases':32,'r0_calls101_over_original60':True,'r0_integrated':'FAIL','old_repair_deadline':'2026-10-25T21:02:49.045073+08:00','old_static_window_calls':8},
 'mode_fix02':{'functions_exec_calls':p.outer_calls,'nested_native_operations':p.native_calls,'functions_wait_calls':p.wait_calls,'conservative_calls':calls,'call_limit':30,'compiles':compiles,'compile_limit':2,'cases':cases,'case_limit':12,'actual_start_observed_shanghai':'2026-10-25T21:44:22.2021802+08:00','conservative_deadline_shanghai':'2026-10-25T22:44:20+08:00','finished_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'automatic_retries':0},
 'cumulative':{'conservative_calls':125+calls,'compiles':6+compiles,'cases':32+cases},
 'actual_implementation_repair_round':1,'r1_integrated_started':False,'original_tester_edges':{'used':1,'remaining':1,'developer_prior_r1_positive_runs':1,'developer_this_window_positive_runs':1,'tester_counter_not_reset':True},
 'td':0,'hardware':0,'download':0,'flash':0,'mapping_changes':0,'Git':0,'external_messages':0,'active_commands':0}
 dump('execution-accounting.json',counts)
 raw=1920*1080*5//4;dma=((128+raw+4095)//4096)*4096;bases=[0x100000,0x900000,0x1100000,0x1900000]
 assert raw==2592000 and dma==2592768 and all(b+dma<=b+8388608 and b+8388608<=2**29 for b in bases)
 impact={'RTL_changes':['mode_quiescent rejects current A/B publication, nonzero held/sent/offer, AR pending/outstanding, active reader/request/response state','leaving mode2 clears presentation registers; reentry cannot expose released metadata'],
 'preserved':['F01 stalled descriptor identity and take/refill','F02 current-cycle ext_take prevents release','real checked CSI/writers/CRC/arbiter/sync/I2C/top and clock/reset paths'],
 'ports_changed':False,'CDC_reset':'all added logic uses existing DHI clock/common reset; no new crossing or reset','protocol_geometry_frequency_changed':False,'default_raw_bytes':raw,'default_dma_bytes':dma,'slot_bases':bases,
 'new_mode_matrix':'8 mode/publication camera-slot-direction combinations, dual publication, valid idle transitions, offered/transferred/AR/R/reader busy rejection, no phantom after release,12 AR-release status races, take/refill, stale/duplicate, common reset',
 'matrix_data_boundary':'low-level native read model returns zero data to exercise safe CRC-fail local release; actual correct R10F content is separately verified through full production cases',
 'source_binding':str(H/'source-map.json'),'old_problem_id':'T08.dual-local-closure:PERMISSION_MISSING:mode-publication-stale-offer','implementation_resolution':'targeted actual-source correction and old/new same-checker runs completed; original integrated tester owns acceptance'}
 dump('change-impact.json',impact)
 checks=['mode/publication matrix','original tester_edges: one remaining original-tester attempt','all-camera/slot/status ownership matrix','real production read/arrival overlap','normal six pairs','case10/11/12/13/14/15','contract','legacy','B-release-to-A negative']
 reuse={'decision':'proposal_only; original integrated tester decides against this manifest','must_fresh_retest':checks,'possible_unchanged_reuse':['old I2C-specific cases1-9 after exact RTL/table/clock/parameter/stimulus and impact binding'],
 'do_not_reuse_as_current_pass':['old blocked implementation','old F01/F02 failure','old missing overlap','G2/G3/G4'],'developer_combined_matrix_substitutions':['full12 status/camera/slot races','same-cycle dual publication and release routes','stale/duplicate release','take/refill and common reset'],
 'independent_reference_TBs':[{'path':str(R1/n),'sha256':sha(R1/n)} for n in ['tb_repair_matrix.sv','tb_dual_contract.sv']]}
 dump('reuse-proposal.json',reuse)
 retest={'required_dimensions':['functional','engineering','system'],'required_checks':checks,'report_paths':[str(H/'result-mode-fix02.md'),str(H/'case-results.json'),str(H/'change-impact.json'),str(H/'local/case16/overlap-result.json')],'input_status':'changed','reuse_decision_paths':[str(H/'reuse-proposal.json')],'original_tester_edges_attempts_remaining':1}
 dump('retest.json',retest)
 warnings=[]
 for log in (H/'local').rglob('*.log'):
  for line in log.read_text(errors='replace').splitlines():
   if '** Warning' in line:warnings.append({'log':str(log),'line':line})
 dump('warning-audit.json',{'warnings':warnings,'review':'RDGN numeric warning inherited; TFMPC deliberately unused output/environment ports retained. No target width/multiple-driver warning is waived.'})
 lines=['# T08 mode-fix02 developer result','','This is the existing repair1 pre-submission closure. The original r0 integrated FAIL and blocked static manifest remain unchanged; no r2 or independent r1 verdict is fabricated.','',
 'Mode changes now require current-cycle publication absence and truly empty ownership/offer/AR/R/reader state. A rejected mode request is counted without dropping the publication. Presentation state is cleared outside mode2. Valid idle switching remains enabled. Ports, geometry, clock frequency and the rest of the production RTL are unchanged.','',
 '|Local check|Outcome|','|---|---|']
 for r in receipts:lines.append('|'+r['name']+'|required marker/ownership or captured-byte oracle satisfied; '+f"{r['seconds']:.3f}s"+'|')
 lines+=['', 'The same legal mode matrix rejects isolated old RTL on publication-mode arbitration and the actual post-release phantom-descriptor trace; the corrected RTL passes. No force of held/FSM state is used. The mode matrix also checks all12 AR-release status combinations, dual publication, routes, stale/duplicate release, take/refill and common reset. The separately aliased B-routing mutant is rejected by the same route assertion. Expected mutant Fatal markers are distinguished from DUT passes and exit0 alone is never sufficient.','',
 'Fresh full-top cases cover overlap16, normal0, CRC10, stalled-AR abort11, late-R drain12, permanent-missing-R LOCK/reset13, protected saturation14 and default-disabled legacy. Actual R bytes, frame identity, standard CRC, source pattern and tail zeros are checked; case16 reconstructs accepted AR to final-R intervals and requires both-camera new SOFs and alternate-slot publication, protected whole-frame drop and recovery.','',
 f'Current window: {calls}/30 conservative tool calls, {compiles}/2 compiles, {cases}/12 cases. Historical125 calls/6 compiles/32 cases are retained; cumulative={125+calls}/{6+compiles}/{32+cases}. The r0 overrun and missed old timely handoff are not reclassified by this new actual-modification window. The original tester still has one remaining original-edge attempt.','',
 'G0/G1 require original independent tester acceptance. G2/3/4 remain not_run/awaiting_hardware. There was no TD, board, download, Flash, mapping, Git or external-message action. Small offline vectors do not prove dual1080p30 or exposure timing. All previous frozen files and compiled-source inputs show drift0.','',
 'Canonical source/compile entry is run_mode_fix.py compile_all with its explicit sources.json; the copied run_t08.py is used only for the unchanged native command utility. Independent testing uses its own allowed output directories, deadline and command harness. sources.f/integration-sources.tcl are integration entries only; they invoke no TD.','',
 'Rollback: stop adopting mode-fix02. No production or earlier frozen source was overwritten.']
 (H/'result-mode-fix02.md').write_text('\n'.join(lines)+'\n')
 (H/'lessons.md').write_text('''# Mode ownership closure lessons

- Mode arbitration must include events accepted this cycle. Checking only old held/pending registers permits a publication to acquire an offer in one mode while another mode consumes it.
- Presentation registers require both ownership validity and a consumer-mode lifetime. Clear inactive-mode offer state and require offers/sent/reader state to be empty before changing consumers.
- Preserve valid idle transitions and every incoming pulse when rejecting a conflicting mode request. Do not mask pub or disable switching to satisfy the checker.
- An effective old/new counterexample drives legal ports through consumption and release, then reenters external mode and checks for phantom metadata. A same-checker old fixture and explicit B-route mutation demonstrate rejection without altering frozen evidence.
- Keep conservative wrapper/native accounting, prior overrun and failed/blocked manifests. This is repair1 completion before its first integrated retest, not a new r2 or a replacement verdict.
''')
 (H/'handoff.md').write_text('''# Handoff to original planner

Developer input is ready_for_test after local completion and this freeze; original independent r1 acceptance has not started. Review manifest/source-map/result/retest and preserved counters, then dispatch the original tester under its existing window. Original tester_edges has only one remaining corrected-input execution. No production migration or hardware task completion follows from this handoff.

The frozen source list includes isolated module aliases for old-mode and bad-B negative controls. The canonical production module remains unique. The original ownership/contract reference TBs are SHA-bound in reuse-proposal.json for the original tester's complete14-process plan. Python -B avoids bytecode writes into frozen inputs; the tester owns its output paths and timing budget.
''')
 files=[];excluded=[]
 for q in sorted(H.rglob('*')):
  if not q.is_file() or q.name=='manifest-mode-fix02.json':continue
  if 'work' in q.parts or '__pycache__' in q.parts or q.suffix.lower() in {'.wlf','.mti','.dat','.dbs','.qdb','.wdb'}:excluded.append(str(q));continue
  files.append({'path':str(q),'sha256':sha(q),'bytes':q.stat().st_size})
 refs=[protected,R1/'static-closeout01/mode-publication-risk.md',R0/'manifest-r0.json',RUN/'descriptor-corrections01-plan.md',RUN/'dispatch-descriptor-corrections01.json',RUN/'fpga-design-guide.md',RUN/'dev-plan.md',RUN/'planning-input-manifest.json',R1/'tb_repair_matrix.sv',R1/'tb_dual_contract.sv']
 manifest={'schema':'fpga-frozen-development-v1','task_ids':['T08.dual-local-closure'],'round':1,'stage':'mode-fix02 pre-integrated repair1 closure','status':'ready_for_test','created_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'project_root':r'D:\fpga\ph1p100','candidate_root':str(H/'candidate'),'RTL_overlay':str(H/'dual_local_closure.v'),'stopped_modifying':True,'active_commands':0,'files':files,'excluded_mutable_artifacts':excluded,'input_references':[{'path':str(q),'sha256':sha(q)} for q in refs],'tools':r0m['tools'],'parameters':pm['parameters'],'compiled_sources_path':str(H/'local/build/sources.json'),'source_map_path':str(H/'source-map.json'),'commands_path':str(H/'commands.json'),'test_input_paths':[str(H/n) for n in ['run_mode_fix.py','tb_mode_matrix.sv','tb_tester_edges.sv','tb_production_sync.sv','check_t08.py','source-map.json','retest.json','reuse-proposal.json']],'lessons_path':str(H/'lessons.md'),'retest':retest,'actual_counts':counts,'resolved_problem_id':impact['old_problem_id'],'gates':{'G0':'pending_original_integrated_test','G1':'pending_original_integrated_test','G2':'not_run','G3':'not_run/awaiting_hardware','G4':'not_run/awaiting_hardware'}}
 assert datetime.datetime.now(datetime.timezone.utc)<DEADLINE
 dump('manifest-mode-fix02.json',manifest)
 assert all(sha(Path(f['path']))==f['sha256'] for f in files)
 print(json.dumps({'status':'ready_for_test','manifest_path':str(H/'manifest-mode-fix02.json'),'manifest_sha256':sha(H/'manifest-mode-fix02.json'),'files':len(files),'stopped_modifying':True,'active_commands':0,'actual_counts':counts}),flush=True)
if __name__=='__main__':main()
