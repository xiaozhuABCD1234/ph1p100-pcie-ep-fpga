"""Planner metadata only: no external process, no build/simulation, no source edits."""
from pathlib import Path
import hashlib,json,datetime
R=Path(r'D:\fpga\ph1p100\workflow\runs\20261025-180900_fpga-dual-offline-closure')
def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def read(p): return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def save(name,obj):
    with (R/name).open('x',encoding='utf-8',newline='\n') as f: json.dump(obj,f,ensure_ascii=False,indent=2);f.write('\n')
def verify(entries):
    out=[]
    for x in entries:
        p=Path(x['path']);actual=sha(p) if p.is_file() else None
        out.append({'path':str(p),'expected':x['sha256'],'actual':actual,'match':actual==x['sha256']})
    return out
M=R/'T08.dual-local-closure/r1/mode-fix02/manifest-mode-fix02.json'
m=read(M); t08=verify(m['files']); assert all(x['match'] for x in t08)
assert sha(M)=='38e0615341330aa5b8f1e0e1f9ecf4e169abbdc6bc4856912b9e4f929bdfcce3'
P08=R/'test-reports/T08.dual-local-closure/r1/integrated-mode-fix02'
p08=[{'path':str(p),'bytes':p.stat().st_size,'sha256':sha(p)} for p in sorted(P08.rglob('*')) if p.is_file()]
P10=R/'T10.dual-aplus-scheduler/cmp-stall-fix01'
cs=read(P10/'evidence/compiled-source.json'); t10=verify(cs); assert all(x['match'] for x in t10)
summary=read(P10/'evidence/summary.json')
receipts=verify([x['checker'] for x in summary['checks'].values()]);assert all(x['match'] for x in receipts)
feedback=R/'user-feedback-continue03.md'
audit={
 'observed_at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
 'trigger':{'path':str(feedback),'sha256':sha(feedback),'exact_user_text':'接着做','root_supplied_now':'2026-10-26T00:50:40+08:00'},
 'scope':'single interruption recovery file audit; no role-status polling/process scanning/experiments',
 'T08':{'manifest_path':str(M),'manifest_sha256':sha(M),'bound_count':len(t08),'drift_count':0,'files_checked':t08,
  'existing_tester_r1_files':p08,'r1_window':read(P08/'window-start.json'),
  'observed_compile_receipts':0,'observed_case_receipts':0,'observed_r1_integrated_report':(R/'test-reports/T08.dual-local-closure-r1-integrated.md').exists(),
  'actual_pre_error_tool_calls':'unknown until original tester reconstructs its own native context; file count is not tool count',
  'actual_pre_error_compile_case_edge_counts':'no receipts observed; original tester must confirm, unknown consumption is not reset',
  'old_deadline_expired':True,'r0_FAIL_preserved':True,'actual_repair_round':1,
  'native_error':'usage limit; try again at Oct 26th, 2026 12:44 AM','user_continue_authorizes_one_same_ID_recovery':True},
 'T10':{'candidate_compiled_inputs':t10,'drift_count':0,'local_receipt_hashes':receipts,
  'summary':{'positive_frames':summary['total_good_frames'],'compiles':summary['this_compile_count'],'cases':summary['this_case_processes'],'faults_increment':summary['faults_suite_increment']},
  'final_manifest_exists':(P10/'manifest-cmp-stall-fix01.json').exists(),'execution_accounting_exists':(P10/'execution-accounting.json').exists(),
  'author_stop_flags':'not received','current_calls':'unknown','historical_calls':'unknown; all known subcounts retained',
  'known_cumulative_compiles':5,'known_cumulative_cases':16,'original_developer_faults':{'used':3,'limit':3},
  'integrated_round0_started':False,'old_deadline':'2026-10-25T22:44:26.9726768+08:00','old_deadline_expired':True,
  'native_error':'Selected model is at capacity. Please try a different model. This agent turn failed.',
  'no_model_change':True},
 'planner_did_not_execute_developer_or_tester_runners':True}
save('continue03-recovery-audit.json',audit)
common={'run_id':R.name,'project_root':r'D:\fpga\ph1p100','output_dir':str(R),'batch_size':1,'status':'ready','needs_user_input':False,
 'question_path':None,'user_summary_path':None,'authorization_path':str(feedback),
 'scope_limits':{'formal_tasks':2,'new_tasks':0,'new_roles':0,'new_implementation_repairs':0,'batch_size':1,'offline_only':True},
 'protected':['All frozen candidate RTL/TB/runner/source inputs and old evidence','Production, other runs, OpenCode candidates, TD and hardware','Global taskboard/config/Git/drive mappings'],
 'on_external_error_or_actual_ID_error':{'operation':'return_to_planner','target':'/root/fpga_plan_dual_offline','automatic_retry':False,'model_change':False,'preemptive_replacement':False},
 'after_each_return':{'operation':'return_to_planner','target':'/root/fpga_plan_dual_offline','requires_actual_counts_stop_flags_manifest_and_problem_if_any':True}}
d08=dict(common,task_ids=['T08.dual-local-closure'],stage='formal r1 interrupted quota recovery; original remaining acceptance only',
 input_paths=[str(R/'T08-continue03-input.md'),str(M),str(R/'T08-integrated-r1-input.md'),str(R/'continue03-recovery-audit.json')],
 manifest_path=str(M),manifest_sha256=sha(M),
 write_scope=[str(R/'test-reports/T08.dual-local-closure/r1')+'/**',str(R/'test-reports/T08.dual-local-closure-r1-integrated.md')],
 next_action={'operation':'followup_task','target':'/root/fpga_tester_dual_local_180900','role':'fpga-tester','prompt_path':str(R/'T08-continue03-input.md'),'same_model':True,'original_single_tester_only':True},
 execution_limits={'recovery_accounting_static_calls':4,'original_r1_total_calls_including_recovery':30,'prior_calls':'must reconstruct; not zero',
  'remaining_calls':'max(0,30-prior_r1_actual_conservative_calls-current_recovery_calls); no experiments until certified',
  'remaining_compiles':'max(0,2-prior_r1_actual_compiles)','remaining_cases':'max(0,14-prior_r1_actual_case_processes)',
  'original_edges_remaining':'at most 1; deduct any actual interrupted-turn attempt, uncertain means not runnable',
  'recovery_calendar_window_minutes':30,'absolute_deadline':'record real receipt time+30min before any command; old 22:54:16 deadline remains expired in history',
  'rationale':'User continuation after actual quota error opens a finite calendar resumption for remaining acceptance, without restoring calls/compiles/cases or failed-command attempts.',
  'read_search_seconds':60,'compile_case_seconds':300,'search_rounds_per_problem':3,'same_failed_command_attempts_total':2,'no_progress_cycles':2,'TD':0,'hardware':0,'download':0,'Flash':0},
 current_evidence={'observed_receipts_compiles':0,'observed_receipts_cases':0,'no_integrated_r1_verdict':True,'all_actual_counts_require_original_context_confirmation':True},
 history_preserved={'r0_verdict':'FAIL','actual_repair_round':1,'r0_tester_calls':44,'r0_tester_compiles':2,'r0_tester_cases':20,'developer_cumulative_calls':142,'developer_cumulative_compiles':7,'developer_cumulative_cases':44,'developer_r0_overrun':True},
 gate='Account first. Reuse any valid same-manifest own evidence. Execute only certified remaining original checks; unknown/insufficient budget -> truthful blocked handoff, not assumed zero or PASS.')
save('dispatch-T08-continue03.json',d08)
d10=dict(common,task_ids=['T10.dual-aplus-scheduler'],stage='static final freeze after actual capacity failure; no experiments',
 input_paths=[str(R/'T10-continue03-input.md'),str(R/'T10-capacity-error01.md'),str(R/'continue03-recovery-audit.json'),str(P10/'window.json'),str(P10/'result-cmp-stall-fix01.md')],
 write_scope=[str(P10/'static-closeout02')+'/**'],
 next_action={'operation':'followup_task','target':'/root/fpga_dev_dual_scheduler_180900','role':'fpga-dev','prompt_path':str(R/'T10-continue03-input.md'),'same_model':True},
 execution_limits={'static_calls':10,'minutes':15,'absolute_deadline':'record actual receipt+15min before commands','compiles':0,'case_processes':0,'RTL_TB_runner_modifications':0,'new_faults':0,'original_faults_total_limit':3,'read_search_seconds':60,'static_command_seconds':60,'search_rounds_per_problem':3,'no_progress_cycles':2,'TD':0,'hardware':0,'download':0,'Flash':0},
 history_preserved={'cmp_stage_calls':'unknown; recover from original context or retain unknown','cmp_stage_compiles':1,'cmp_stage_cases':5,'cmp_case_limit':5,'known_cumulative_compiles':5,'known_cumulative_cases':16,'developer_faults_used':3,'developer_faults_limit':3,'independent_round0_started':False,'post_acceptance_repair_rounds':0,'old_deadline':read(P10/'window.json')['deadline']},
 gate='A real source-bound manifest, accounting and author stop/active flags return to original planner before any first integrated tester is dispatched.')
save('dispatch-T10-continue03-static.json',d10)
top=dict(common,task_ids=['T08.dual-local-closure','T10.dual-aplus-scheduler'],stage='two independent original-role resumptions; BATCH_SIZE remains one per task',
 input_paths=[str(R/'continue03-recovery-plan.md'),str(R/'continue03-recovery-audit.json')],
 write_scope=d08['write_scope']+d10['write_scope'],
 next_actions=[
 {'operation':'followup_task','target':'/root/fpga_tester_dual_local_180900','task_id':'T08.dual-local-closure','dispatch_path':str(R/'dispatch-T08-continue03.json'),'prompt_path':str(R/'T08-continue03-input.md'),'scope':'recover actual counts then original remaining integrated r1 only'},
 {'operation':'followup_task','target':'/root/fpga_dev_dual_scheduler_180900','task_id':'T10.dual-aplus-scheduler','dispatch_path':str(R/'dispatch-T10-continue03-static.json'),'prompt_path':str(R/'T10-continue03-input.md'),'scope':'10call/15min static-only final manifest/accounting/author stop'}],
 independent_parallel_actions=True,not_a_batch=True,execution_limits={'T08':'prior original calls/compiles/cases deducted; 30min resumed calendar cap','T10':'10 static calls/15min; zero compile/simulation/faults'},
 wait_policy='Only receive events from the two dispatched roles; no polling, scanning logs or progress questions. Each actual return/error goes to original planner; do not wait for failed old turns.',
 on_actual_ID_error='Return actual error to original planner; only then file recovery and real ID mapping. Do not preemptively create a replacement.',
 user_summary_path=str(R/'user-summary-continue03.md'))
save('dispatch-continue03-recovery.json',top)
print(json.dumps({'manifest_T08_checked':len(t08),'T08_drift':0,'T10_compiled_checked':len(t10),'T10_drift':0,'T08_existing_r1_files':len(p08),'dispatch_path':str(R/'dispatch-continue03-recovery.json')},ensure_ascii=False))
