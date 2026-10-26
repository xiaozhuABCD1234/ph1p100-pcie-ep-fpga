"""Static-only closeout. Reads existing captures; never launches an experiment."""
from pathlib import Path
import datetime,hashlib,json,re,struct,sys
H=Path(__file__).resolve().parent;R1=H.parent;R0=R1.parent;RUN=R0.parent
sys.dont_write_bytecode=True;sys.path.insert(0,str(R1))
from check_t08 import check
from r10f_oracle import check_r10f
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def dump(name,value):
 p=H/name;assert p.parent==H;p.write_text(json.dumps(value,indent=2),encoding='utf-8')
def write(name,value):
 p=H/name;assert p.parent==H;p.write_text(value,encoding='utf-8')
def main():
 now=datetime.datetime.now(datetime.timezone.utc)
 stop=datetime.datetime.fromisoformat('2026-10-25T13:43:00+00:00')
 if now>=stop:raise RuntimeError('conservative static cutoff reached; no old experiment deadline is extended')
 audit_path=RUN/'readonly-recovery01/audit.json';audit=json.loads(audit_path.read_text(encoding='utf-8-sig'))['T08']
 old=json.loads((R0/'manifest-r0.json').read_text());r0_drift=[]
 for f in old['files']:
  p=Path(f['path'])
  if not p.is_file() or sha(p)!=f['sha256']:r0_drift.append(str(p))
 baseline=json.loads((R1/'local/build-baseline/sources.json').read_text());mutant=json.loads((R1/'local/build-mutant/sources.json').read_text())
 source_drift=[];mapping=[]
 for variant,entries in [('baseline',baseline),('negative_fixture',mutant)]:
  for f in entries:
   p=Path(f['path']);actual=sha(p) if p.is_file() else None
   if actual!=f['sha256']:source_drift.append({'variant':variant,'path':str(p),'compiled_sha256':f['sha256'],'actual_sha256':actual})
   mapping.append({'variant':variant,'path':str(p),'compiled_sha256':f['sha256'],'current_sha256':actual})
 dump('source-map.json',mapping)
 names=['original-edges','matrix','case16','case00','case10','case11','case12','case13','case14','case15','contract','legacy','negative']
 rows=[];missing=[];data=[]
 markers={'original-edges':'TESTER_EDGE_PASS','matrix':'MATRIX_PASS','contract':'CONTRACT_PASS','legacy':'T08_PASS'}
 for name in names:
  out=R1/'local'/name;p=out/'case-result.json'
  if not p.is_file():missing.append(str(p));continue
  r=json.loads(p.read_text());log=(out/'vsim.log').read_text(encoding='utf-8',errors='replace')
  valid=r.get('pass') is True and r.get('exit_code')==0 and not r.get('timeout')
  if name=='negative':valid=valid and 'CONTRACT_FAIL B release routes only to B' in log and '** Fatal' in log and 'CONTRACT_PASS' not in log
  else:valid=valid and markers.get(name,'T08_PASS') in log and '** Fatal' not in log and '** Error' not in log
  if not valid:missing.append('invalid completed receipt '+name)
  rows.append({'name':name,'receipt_path':str(p),'receipt_sha256':sha(p),'valid_completed_receipt':valid,'owned_pid':r.get('owned_pid'),'elapsed_seconds':r.get('elapsed_seconds'),'negative_fixture':name=='negative'})
  if name.startswith('case'):
   try:
    o=check(out,int(name[4:]));data.append({'name':name,'rechecked_from_existing_R_bytes':True,'result':o})
   except Exception as e:missing.append('captured-byte recheck '+name+': '+repr(e))
 if (R1/'local/legacy/events.log').is_file():
  legacy=[]
  for line in (R1/'local/legacy/events.log').read_text().splitlines():
   x=line.split()
   if x[0]=='PUB':
    cam,seq,fid=int(x[3]),int(x[4]),int(x[7]);p=R1/'local/legacy'/f'frame_{cam}_{seq}.hex'
    legacy.append(check_r10f(bytes(int(v,16) for v in p.read_text().split()),cam,seq,fid))
  if len(legacy)!=6:missing.append('legacy requires six captured frames')
  data.append({'name':'legacy','captured_dump_frames':legacy})
 dump('captured-byte-recheck.json',data)
 # Reconstruct actual accepted-AR/final-R windows; no RTL evaluation is performed.
 events=[x.split() for x in (R1/'local/case16/events.log').read_text().splitlines()]
 spans=[];pending=None
 for x in events:
  if x[0]=='DAR':
   if pending is not None:missing.append('overlap nested AR')
   pending={'epoch':int(x[1]),'start':int(x[2]),'base':int(x[3],16),'beats':int(x[4])}
  elif x[0]=='DRLAST':
   if pending is None:missing.append('overlap unmatched final R')
   else:pending['end']=int(x[2]);spans.append(pending);pending=None
 if pending is not None:missing.append('overlap unclosed AR')
 hits=[]
 for cam in [0,1]:
  sofs=[x for x in events if x[0]=='OSOF' and int(x[3])==cam and any(s['epoch']==int(x[1]) and s['start']<=int(x[2])<s['end'] for s in spans)]
  pubs=[x for x in events if x[0]=='CLPUB' and int(x[3])==cam and int(x[7])==61 and any(s['epoch']==int(x[1]) and s['base']!=int(x[5],16) and s['start']<=int(x[2])<s['end'] for s in spans)]
  if len(sofs)<2 or len(pubs)<1:missing.append('missing real overlap camera '+str(cam))
  hits.append({'camera':cam,'new_sofs':sofs,'other_slot_publications':pubs})
 dump('overlap-recheck.json',{'spans':spans,'camera_hits':hits,'source':str(R1/'local/case16/events.log'),'already_captured_only':True})
 commands=[]
 for p in (R1/'local').rglob('*.log'):
  for line in p.read_text(encoding='utf-8',errors='replace').splitlines():
   if line.startswith('COMMAND_RESULT '):commands.append(json.loads(line[len('COMMAND_RESULT '):]))
 commands=list({c['log']:c for c in commands}.values())
 unfinished=[c for c in commands if not isinstance(c.get('exit_code'),int) or c.get('timeout')]
 if unfinished:missing.append('unfinished or timed-out native receipt')
 compiles=sum(Path(c['command'][0]).name.lower()=='vlog.exe' for c in commands)
 cases=sum(Path(c['command'][0]).name.lower()=='vsim.exe' for c in commands)
 if compiles!=2 or cases!=13:missing.append('historical compile/case inventory differs from2/13')
 dump('command-inventory.json',commands)
 code=(R1/'dual_local_closure.v').read_text();lines=code.splitlines()
 def loc(text):return [i+1 for i,s in enumerate(lines) if text in s]
 risk={'classification':'static RTL counterexample; not simulated in this window','source_path':str(R1/'dual_local_closure.v'),'source_sha256':sha(R1/'dual_local_closure.v'),
 'facts':{'mode_acceptance':loc('if(held==0 && !ar_pending && outstanding==0 && state==WAIT)'), 'incoming_offer':loc('a_offer<=1;a_index<=a_pub_base'), 'valid_from_offer_without_held_check':loc('assign a_desc_valid='), 'only_offer_reset_or_mode2_assignments':loc('a_offer<=')},
 'trace':['Start in mode2, all slots free, offers0, stateWAIT, no pending/outstanding read.',
 'At one DHI edge request mode1 and publish valid A0. Old held=0 lets active_mode become1; capture makes heldA0=1; the old-mode2 branch simultaneously sets a_offer=1 and a_index=0.',
 'Mode1 consumes and safely releases A0. The source has no non-mode2 clearing of a_offer, so it remains1 while heldA0 and sentA0 return0.',
 'When empty and idle, request mode2. a_desc_valid becomes1 from active_mode==2 && !fault && a_offer even though heldA0=0; ready can transfer the already released identity. B is symmetric.'],
 'missing_implementation_closure':'Mode/publication acceptance and presentation state lifetime must be made consistent, then the affected transitions need bounded validation on a new source input. Current static authorization permits neither source edits nor experiments.',
 'evidence_boundary':'This is a source/control-flow deduction. The13 existing local scenarios did not exercise this mode/publication coincidence; no new simulation was run and no independent r1 verdict is asserted.'}
 dump('mode-publication-risk.json',risk)
 write('mode-publication-risk.md','# Static ownership closure issue\n\n'+ '\n\n'.join(risk['trace'])+'\n\nSource: '+risk['source_path']+'; SHA256 '+risk['source_sha256']+'.\n\n'+risk['evidence_boundary']+'\n\n'+risk['missing_implementation_closure']+'\n')
 accounting={'static_closeout01':{'first_evidenced_read_completed_shanghai':'2026-10-25T21:29:11.4447438+08:00','receipt_exact_timestamp':'unknown; it was not timestamped before the initial bounded read','conservative_cutoff_shanghai':'2026-10-25T21:43:00+08:00','metadata_started_utc':now.isoformat(),'metadata_finished_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'functions_exec_calls':3,'nested_native_operations':5,'conservative_calls':8,'limit':10,'new_compiles':0,'new_simulations':0,'new_actual_repairs':0,'source_edits':0,'old_session_read_error':'write_stdin: Unknown process id14266; not retried; not an agent ID recovery','current_exact_own_runner_process_snapshot_count':0},
 'r0_developer':{'functions_exec_calls':40,'functions_wait_calls':1,'nested_native_operations':60,'conservative_calls':101,'original_limit':60,'historical_overrun':True,'compiles':4,'cases':19},
 'r1_developer_before_static':{'functions_exec_calls':7,'functions_wait_calls':0,'nested_native_operations':9,'conservative_calls':16,'compiles':compiles,'cases':cases,'implementation_repair_round':1,'original_deadline_shanghai':'2026-10-25T21:02:49.045073+08:00','no_timely_final_manifest_or_handoff':True,'deadline_is_not_extended_or_backdated':True},
 'cumulative_developer_including_static':{'functions_exec_calls':50,'functions_wait_calls':1,'nested_native_operations':74,'conservative_calls':125,'compiles':4+compiles,'cases':19+cases},
 'original_tester_edges':{'used':1,'total_failed_command_attempt_limit':2,'remaining_corrected_input_attempts':1,'developer_local_r1_edges_runs':1,'tester_counter_not_reset':True},
 'author_stop_statement':'I have stopped changing original r1 source/TB/model/runner. All launched experiment children have terminal Popen.wait receipts; the exact original run_repair.py process snapshot is empty. No new experiment is launched in static closeout. active_commands=0 at return.',
 'history_boundary':'Static metadata are created after the old repair deadline. Existing evidence and the r0 FAIL remain unchanged. Prior missing metadata are not filled with a falsely earlier timestamp.'}
 dump('execution-accounting.json',accounting)
 impact={'r1_compiled_sources_match_current':not source_drift,'compiled_source_drift':source_drift,'r0_protected_files_checked':len(old['files']),'r0_protected_drift':r0_drift,'local_receipts_verified':rows,'captured_byte_recheck_missing':missing,'F01_F02_targeted_repairs_present':('wire [1:0] ai=a_index;' in code and '!ext_take&&' in code),'F03_real_overlap_rechecked':hits,'additional_static_ownership_issue':str(H/'mode-publication-risk.json'),'implementation_ready_for_independent_acceptance':False,'previous_audit_T08_source_drift':audit.get('compiled_source_drift'),'source_changes_in_static_window':0}
 dump('change-impact.json',impact)
 reuse={'status':'proposal_only; no acceptance or evidence reuse approved here','unaffected_sources':'r0/r1 table, I2C, sync, writer, checker and production top remain SHA-bound; original integrated tester owns any eventual reuse decision','changed_ownership_checks':'must be validated against the next implementation that closes the mode/publication trace; do not start testing this blocked input as an implemented-ready candidate','preserved_r0_verdict':'FAIL','original_edges_attempts_remaining':1}
 dump('reuse-proposal-r1.json',reuse)
 retest={'required_dimensions':['functional','engineering','system'],'required_checks':['planner review of static mode/publication ownership trace','implementation closure before independent test dispatch','original tester_edges one remaining corrected-input run','all-camera/slot/status matrix and same-cycle take/refill','mode2-to-local-to-mode2 with coincident publication and no phantom descriptor','actual overlap/CRC/read ownership','case0/10/11/12/13/14/15','contract/legacy/B-to-A mutation'], 'report_paths':[str(H/'result-r1.md'),str(H/'mode-publication-risk.md'),str(RUN/'test-reports/T08.dual-local-closure-r0-integrated.md')],'input_status':'changed','reuse_decision_paths':[str(H/'reuse-proposal-r1.json')],'test_dispatch_allowed_now':False}
 dump('retest-r1.json',retest)
 problem={'problem_id':'T08.dual-local-closure:PERMISSION_MISSING:mode-publication-stale-offer','reason_code':'PERMISSION_MISSING','new_information':True,'evidence_path':str(H/'mode-publication-risk.md'),'requested_action':'Original planner reviews the static trace and, if confirmed, arranges an actual bounded implementation repair; this static-only window cannot modify or test it.','resume_input_path':str(H/'manifest-r1.json')}
 dump('blocked.json',{'status':'blocked','implementation_issue':risk['missing_implementation_closure'],'additional_missing_evidence':missing,'source_drift':source_drift,'r0_drift':r0_drift,'problem':problem})
 write('result-r1.md','# T08 round1 static closeout: blocked\n\nThe13 existing local case receipts, two compilation receipts, compiled-source SHA snapshots and captured RAW bytes were read and checked. Original r0 remains FAIL; this is not integrated r1 PASS.\n\nF01/F02 targeted fixes and real F03 overlap are present, but the mode/publication transition in mode-publication-risk.md leaves a source-level ownership counterexample unclosed. No RTL, TB, model, runner, old evidence or old manifest was modified; no experiment was started.\n\nThe original repair deadline21:02:49 is preserved. This metadata freeze is created at the actual current time after that deadline. Historical r0 conservative calls101/60 and r1 pre-static calls16 with compile2/case13 are retained. Static closeout uses8/10 conservatively counted operations and adds0 experiments.\n\nExact source mapping, native receipts, captured-byte recheck, actual AR/final-R overlap intervals and blockers are linked in this directory. Source checks cannot promote this incomplete ownership implementation to ready_for_test. G2/3/4 remain not_run/awaiting_hardware.\n')
 write('handoff.md','# Handoff to original planner\n\nStatus blocked. Review mode-publication-risk.md and blocked.json before any tester dispatch. The existing13 local successes are preserved and SHA-bound, but they do not cover the statically derived phantom-descriptor transition. The static window cannot repair it. Original tester edges has one remaining attempt; no new role or extra test budget was consumed.\n\nThe original experiment shell session retrieval returned unknown process14266 and was not retried. Every existing child command has a terminal receipt and the exact own runner process snapshot is empty; I have stopped original source modifications and active_commands=0.\n')
 write('lessons.md','# Static closeout lessons\n\n- Registered descriptor presentation needs a lifetime tied to ownership and consumer mode, including simultaneous mode change/publication. A local stall fix can leave a stale valid offer when ownership is later released.\n- Thirteen passing local scenarios and genuine arrival/read overlap do not close a statically identifiable untested ownership path. Freeze blocked when further implementation is necessary and current permission is metadata-only.\n- Count wrappers and nested operations conservatively. Preserve old overruns, the uncompleted timely handoff and unavailable shell-session evidence rather than backdating a new freeze.\n')
 excluded=[];files=[]
 for p in sorted(R1.rglob('*')):
  if not p.is_file() or H in p.parents:continue
  if 'work' in p.parts or '__pycache__' in p.parts or p.suffix.lower() in {'.wlf','.mti','.dat','.dbs','.qdb','.wdb'}:
   excluded.append({'path':str(p),'reason':'derived mutable simulator database/wave/cache; retained, not deleted'});continue
  files.append({'path':str(p),'sha256':sha(p),'bytes':p.stat().st_size,'kind':'existing_r1_evidence_or_source'})
 for p in sorted(H.iterdir()):
  if p.is_file() and p.name!='manifest-r1.json':files.append({'path':str(p),'sha256':sha(p),'bytes':p.stat().st_size,'kind':'new_static_metadata'})
 refs=[R0/'manifest-r0.json',RUN/'fpga-design-guide.md',RUN/'dev-plan.md',RUN/'planning-input-manifest.json',RUN/'T08-repair-r1-plan.md',RUN/'static-closeout01-plan.md',RUN/'dispatch-static-closeout01.json',audit_path,RUN/'test-reports/T08.dual-local-closure-r0-integrated.md']
 manifest={'schema':'fpga-static-closeout-frozen-v1','task_ids':['T08.dual-local-closure'],'round':1,'status':'blocked','created_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'project_root':r'D:\fpga\ph1p100','candidate_root':str(R1/'candidate'),'RTL_overlay':str(R1/'dual_local_closure.v'),'stopped_modifying':True,'active_commands':0,'author_stop_statement':accounting['author_stop_statement'],'files':files,'excluded_mutable_artifacts':excluded,'input_references':[{'path':str(p),'sha256':sha(p)} for p in refs],'compiled_source_snapshots':[str(R1/'local/build-baseline/sources.json'),str(R1/'local/build-mutant/sources.json')],'compiled_source_drift':source_drift,'tools':old['tools'],'parameters':old['parameters']|{'case16_inter_beat_delay_DHI':100,'normal_inter_beat_delay_DHI':0},'local_results_path':str(H/'change-impact.json'),'execution_accounting_path':str(H/'execution-accounting.json'),'test_input_paths':[str(H/'source-map.json'),str(H/'captured-byte-recheck.json'),str(H/'overlap-recheck.json'),str(H/'mode-publication-risk.md'),str(H/'retest-r1.json')],'lessons_path':str(H/'lessons.md'),'blocked':[problem],'retest':retest,'gates':{'G0':'blocked: static ownership counterexample','G1':'local completed evidence retained; independent r1 acceptance not started','G2':'not_run','G3':'not_run/awaiting_hardware','G4':'not_run/awaiting_hardware'}}
 if datetime.datetime.now(datetime.timezone.utc)>=stop:raise RuntimeError('conservative static cutoff reached before freeze')
 dump('manifest-r1.json',manifest)
 drift=[f['path'] for f in files if sha(Path(f['path']))!=f['sha256']]
 if drift:raise RuntimeError('post-freeze drift: '+repr(drift))
 print(json.dumps({'status':'blocked','manifest_path':str(H/'manifest-r1.json'),'manifest_sha256':sha(H/'manifest-r1.json'),'files':len(files),'compiled_source_drift':len(source_drift),'r0_drift':len(r0_drift),'completed_local_receipts':len(rows),'static_calls':8,'stopped_modifying':True,'active_commands':0,'problem':problem}),flush=True)
if __name__=='__main__':main()
