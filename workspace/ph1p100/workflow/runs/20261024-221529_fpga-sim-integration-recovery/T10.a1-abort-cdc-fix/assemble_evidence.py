import pathlib,json,hashlib,subprocess,sys,datetime,re,os
sys.dont_write_bytecode=True
p=pathlib.Path(r'D:\fpga\ph1p100\workflow\runs\20261024-221529_fpga-sim-integration-recovery\T10.a1-abort-cdc-fix');sys.path.insert(0,str(p));import run_abort
assert p.resolve().parent==p.parent.resolve() and p.resolve().name=='T10.a1-abort-cdc-fix'
# Complete invariant audit, including binding's two passed manifests and prior r0.
audit=run_abort.protect();extra=[]
for pk,sk in [('source_fix_manifest','source_fix_manifest_sha256'),('source_corrected_dut_index','source_corrected_dut_index_sha256'),('original_blocked_manifest_path','original_blocked_manifest_sha256')]:
 assert run_abort.sha(run_abort.BIND[pk])==run_abort.BIND[sk];extra.append(dict(path=run_abort.BIND[pk],sha256=run_abort.BIND[sk]))
old_protection=json.loads((p.parent/'T10.a1-recovery-sim/resume01/protection-before.json').read_text())
for x in old_protection['original_artifacts']:
 assert run_abort.sha(x['path'])==x['sha256'];extra.append(x)
(p/'protection-after.json').write_text(json.dumps(dict(**audit,extra_preserved=extra),indent=2))
records=[]
for n in ['vlog','vsim','vlib']:
 exe=run_abort.MS/(n+'.exe');args=[str(exe),'-version'];rec=dict(tool=n,path=str(exe),sha256=run_abort.sha(exe))
 if n!='vlib':
  cmd=subprocess.run(args,cwd=p,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,encoding='utf-8',errors='replace',timeout=60);rec.update(version=cmd.stdout.strip(),returncode=cmd.returncode,argv=args,timeout_seconds=60)
 records.append(rec)
records.append(dict(tool='Python',version=sys.version,path=sys.executable,sha256=run_abort.sha(sys.executable)))
(p/'tool-identity.json').write_text(json.dumps(records,indent=2))
# Full eight-RTL binding: exactly one new top, one previously passed exporter,
# and six original modules; no copy of the protected seven is compiled.
files=[]
for x in run_abort.BIND['files']:
 y=dict(x);n=y['logical_name'];y['preserved_binding_sha256']=x['sha256']
 if n=='camera_a1_uart_top.v':y['path']=str(p/'candidate'/n);y['sha256']=run_abort.sha(y['path']);y['changed']=True;y['identity']='new abort CDC candidate'
 elif n=='a1_uart_export.v':y['changed_in_this_package']=False;y['identity']='passed descriptor fix; preserved byte-for-byte'
 else:y['changed_in_this_package']=False;y['identity']='original unchanged'
 files.append(y)
index=dict(task_id='T10.a1-abort-cdc-fix',round=0,purpose='Combined immutable simulation DUT: new top + passed exporter + six originals',frozen=True,changed_file_count_this_package=1,unchanged_binding_count=7,unchanged_original_count=6,files=files,rtl_paths={x['logical_name']:x['path'] for x in files},source_manifest_path=str(p/'manifest-r0.json'),previous_binding=str(run_abort.BINDING_PATH) if hasattr(run_abort,'BINDING_PATH') else str(p.parent/'recovery-dut-binding-resume01.json'),not_production_qualified=True)
(p/'corrected-dut-index.json').write_text(json.dumps(index,indent=2))
# Select the final matrix and the one bounded successful fast SOF correction.
selected=[]
for ratio in ['slow','fast']:
 for n in run_abort.CASES:
  q=p/'corrected'/((n+'-fast-retry') if (n,ratio)==('sof-abort','fast') else n+'-'+ratio+'-final')
  d=json.loads((q/'result.json').read_text());assert d['status']=='PASS',str(q)
  tr=(q/'trace.txt').read_text();control={k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',next(l for l in tr.splitlines() if l.startswith('CONTROL ')))}
  assert control['token_w']==control['token_r']
  if n=='bad-frame':assert control['abort_writes']==control['abort_reads']==control['raw_aborts']==1 and d['stats']['raw_drop']>=1
  if n in ['full-abort','sof-abort','last-skid-abort']:assert control['abort_writes']==control['abort_reads']==1
  if n=='last-skid-abort':assert control['last_abort_hits']==1
  if n=='sof-abort':assert control['sof_abort_hits']==1
  selected.append(dict(name=n,ratio=ratio,result_path=str(q/'result.json'),control=control,stats=d['stats'],decoded=d['decoded']))
assert next(x for x in selected if x['name']=='full-abort' and x['ratio']=='fast')['control']['abort_stalls']>0
old=json.loads((p/'old/bad-frame-slow-retry/result.json').read_text());assert old['effective_negative']
negative=json.loads((p/'checker-negatives.json').read_text());assert all(x['rejected'] for x in negative)
local=dict(task_id='T10.a1-abort-cdc-fix',round=0,status='LOCAL_PASS',not_independent_acceptance=True,selected_matrix=selected,old_top_effective_negative=str(p/'old/bad-frame-slow-retry/result.json'),checker_negatives=len(negative),protected_inputs=audit,active_commands=0)
(p/'local-result.json').write_text(json.dumps(local,indent=2))
commands=[]
for q in p.rglob('*.command.json'):
 d=json.loads(q.read_text());d['record_path']=str(q);commands.append(d)
(p/'actual-commands.json').write_text(json.dumps(commands,indent=2))
ledger=dict(task_id='T10.a1-abort-cdc-fix',round=0,actual_repair_rounds=0,native_tool_calls_so_far=42,tool_call_limit=60,minute_limit=75,full_compiles=2,full_compile_limit=2,partial_TB_only_compiles=3,RTL_candidate_revisions_after_first_full_compile=0,corrected_simulations=40,corrected_pass_runs=39,corrected_timing_injection_miss_runs=1,old_top_simulations=2,old_effective_target_rejections=1,old_wrong_monitor_early_rejections=1,final_selected_cases=20,per_case_retries={'fast-sof':1,'old-bad-frame':1},final_matrix_reruns_of_19_previously_run_cases=1,checker_negatives=17,preparation_encoding_failure=1,all_owned_processes_waited=True,active_commands=0,first_reads_no_explicit_hard_timeout=True,read_actual_seconds_under_3=True,all_compile_sim_deadlines_seconds=300,all_TB_watchdogs=True,exact_role_start_not_instrumented=True,earliest_output_creation_utc=datetime.datetime.fromtimestamp(p.stat().st_ctime,datetime.timezone.utc).isoformat(),last_check_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),TD_synthesis_route_bitgen_CWC_download_flash=0)
(p/'execution-ledger-r0.json').write_text(json.dumps(ledger,indent=2))
print('FINAL_AUDIT',audit,'extra',len(extra),'selected',len(selected),'commands',len(commands),'combined_DUT_files',len(files))
