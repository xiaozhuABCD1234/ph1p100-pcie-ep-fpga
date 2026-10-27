import pathlib,json,hashlib,time,re,datetime,subprocess
TC=pathlib.Path(__file__).resolve().parents[1];OLD=TC.parent;RUN=OLD.parents[1];A=TC/'quota-resume01';A.mkdir(exist_ok=True)
def readj(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def writej(n,o):(A/n).write_text(json.dumps(o,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
start_ms=1792393551812;role_deadline=start_ms/1000+240*60;now=time.time()
B=TC/'build/attempt4';er=readj(B/'execution-result.json');cmd=readj(B/'inputs.json')
assert er['attempt']==4 and er['exit']==0 and not er['timed_out']
drift=[e['path'] for e in cmd if sha(pathlib.Path(e['path']))!=e['sha256']];assert not drift,drift
log=(B/'deadline.log').read_text(encoding='utf-8');header=json.loads(log.splitlines()[0]);assert header['deadline_seconds']==3600
data=(B/'prj/td_00_all_closedloop.log').read_bytes()
stage=data.decode('utf-16' if data.startswith(b'\xff\xfe') else 'utf-8-sig',errors='replace')
assert 'OWN_PID=67780' in log and 'B01_EXPLICIT_HOLD_FIX_BEGIN' in stage and 'B01_EXPLICIT_HOLD_FIX_END' in stage and 'B01_CLOSEDLOOP_ALL_DONE' in stage
assert not (TC/'build/attempt5').exists() and not (TC/'build/attempt6').exists()
phy=B/'prj/ph1p_pcie_integration_Runs/phy_1';names=['ph1p_pcie_integration_pr.db','ph1p_pcie_integration_pr.timing','ph1p_pcie_integration_phy.area','ph1p_pcie_integration_chk.timing','ph1p_pcie_integration_inst.bid','ph1p_pcie_integration.bit','cw/compiled.cwc','cw/compiled.bit']
arts=[]
for n in names:
    p=phy/n;assert p.is_file() and p.stat().st_size>0;arts.append({'path':str(p),'size':p.stat().st_size,'sha256':sha(p)})
old=readj(OLD/'attempt-counts-verified.json');tests=old['tests'];new=[]
for p in sorted((TC/'g1').glob('*/result.json')):
    r=readj(p);new.append({'key':r['tb'],'path':str(p),'pass':r['exit']==0 and not r['timeout'] and not r['sim_error'] and r['pass_marker']})
for p in sorted((TC/'algo-g1').glob('*/report.json')):
    r=readj(p);new.append({'key':'algorithm_'+r['case']+'/'+r['mutation'],'path':str(p),'pass':r['verdict']=='PASS'})
cumulative={k:{'historical_used':v['cumulative_attempts'],'additional_used':sum(e['key']==k for e in new),'cumulative_used':v['cumulative_attempts']+sum(e['key']==k for e in new),'max':8 if k=='tb_closedloop_writer_checker' else 6} for k,v in tests.items()}
assert all(v['cumulative_used']<=v['max'] for v in cumulative.values())
activity={'original_exec_session_id':13307,'session_collection':'write_stdin returned final exit0; session closed','native_owned_root_pid':67780,'ownership_evidence':{'argv_cwd_and_start_header':header,'same_root_pid_returned_by_own_log':True,'get_cim_known_pid_at_resume':'no process returned; no process killed'},'start_epoch':header['start'],'original_deadline_epoch':header['start']+3600,'actual_end_epoch':header['start']+er['elapsed_seconds'],'elapsed_seconds':er['elapsed_seconds'],'timed_out':False,'completion_markers':['B01_EXPLICIT_HOLD_FIX_BEGIN','B01_EXPLICIT_HOLD_FIX_END','B01_CLOSEDLOOP_ALL_DONE'],'own_activity_at_audit':'all previously started production/sim sessions ended; final audit/engineering collection only','mapping_state':'only preexisting unrelated R mapping remained; no mapping removed by audit','source_drift':drift,'artifacts':arts,'quota_state':'native calls in this resumed turn succeeded; account quota availability beyond actual calls not inferred'}
writej('activity-check.json',activity)
reconcile={'production_historical_used':3,'production_attempt4':er,'attempt5':'not started (directory absent; no launch in own conversation)','attempt6':'not started (directory absent; no launch in own conversation)','production_cumulative_used':4,'production_max':6,'new_g1_records':new,'g1_cumulative':cumulative,'actual_repair_rounds':0,'integrated_round0':'not_started','role_budget':{'original_start_epoch':start_ms/1000,'original_240min_deadline_epoch':role_deadline,'audit_epoch':now,'conservative_wall_elapsed_minutes':(now-start_ms/1000)/60,'conservative_wall_remaining_minutes':max(0,(role_deadline-now)/60),'native_build_completed_in_33_09_minutes':True,'pre_interruption_last_own_file_event':{'path':str(TC/'scripts/freeze.py'),'mtime_epoch':(TC/'scripts/freeze.py').stat().st_mtime},'quota_gap':'No new commands or attempts were launched during the provider interruption; exact model-active duration within the gap is unknown. Do not infer zero or reset the role clock. Conservatively retain original wall deadline.','tool_call_accounting':'Visible native/outer call inventory before audit is conservatively below100 combined; reserve100 used including this <=10-call audit. Remaining conservative tool allowance>=50 of original150; final collection only. This upper bound is used for safety, not an invented exact total.'},'previous_manifest_sha256':sha(OLD/'candidate/manifest.json'),'previous_manifest_historical':True,'current_manifest_exists':(TC/'candidate/manifest.json').exists(),'source_snapshot_index':str(TC/'prechange-index.json')}
writej('attempt-reconciliation.json',reconcile)
(A/'resume-decision.md').write_text(f'''# Audited resume decision

Attempt4 already completed natively with exit0 in{er['elapsed_seconds']:.2f}s under its original3600s deadline. Original session13307 was collected, not restarted. Known ownedPID67780 absent; no process killed. Original source snapshot exactly matches all build inputs. Production4/6, attempts5/6 never started; new G1 records9 (8positive/negative-control successes,1 missed-coverage failure). Core cumulative4/6, writer/checker6/8, controller5/6. Independentr0/actual repair0.

Provider interruption spans an unknown model-active interval after own freeze-helper file timestamp, while native attempt4 completed independently at its recorded original end. Retain original role wall deadline19:05:51 local conservatively; at audit {max(0,(role_deadline-now)/60):.2f}minutes remain. Do not restart a ~33minute full build under this insufficient remaining role window or reset/extend budgets. Collect required sameDB CWC/resource/STA and exact failed paths, preserve the new candidate with ready_for_test=false, freeze and return original planner. Actual attempt4 hold is positive, but setup remains negative in cameraA and cameraB; no eligible board bit. The remaining two production numbers are unused, not silently consumed or newly authorized beyond the original role budget.
''',encoding='utf-8')
print(json.dumps({'audit':'complete','production_used':4,'source_drift':drift,'wall_remaining_minutes':max(0,(role_deadline-now)/60),'g1_cumulative':{k:v['cumulative_used'] for k,v in cumulative.items()}}))
