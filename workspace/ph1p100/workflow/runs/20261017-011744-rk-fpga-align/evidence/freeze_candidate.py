from pathlib import Path
import datetime, hashlib, json, subprocess, sys
sys.dont_write_bytecode=True
RUN=Path(__file__).resolve().parents[1]
ROOT=RUN.parents[2]
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def dump(p,x): p.write_text(json.dumps(x,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def command(args):
 d=subprocess.run(args,cwd=ROOT,capture_output=True)
 return {'argv':args,'cwd':ROOT.as_posix(),'exit_code':d.returncode,'stdout':d.stdout.decode('utf-8',errors='replace').strip(),'stderr':d.stderr.decode('utf-8',errors='replace').strip()}

baseline=json.loads((RUN/'backup/baseline-manifest.json').read_text(encoding='utf-8'))
root_drift=[]
for row in baseline['files']:
 p=ROOT/row['path']
 if not p.is_file() or sha(p)!=row['sha256']: root_drift.append(row['path'])
permitted_metadata=['workflow/runs/20261017-011744-rk-fpga-align/main-log.md']
unexplained=[x for x in root_drift if x not in permitted_metadata]
external_drift=[row['source_path'] for row in baseline['rollback'] if sha(Path(row['source_path']))!=row['sha256']]
provenance=json.loads((RUN/'references/provenance.json').read_text(encoding='utf-8'))
peer_errors=[]
for tree in provenance['upstreams']:
 for row in tree['files']:
  if sha(RUN/'references'/tree['name']/row['path'])!=row['sha256']: peer_errors.append(tree['name']+'/'+row['path'])
local=json.loads((RUN/'references/local-provenance.json').read_text(encoding='utf-8'))
local_errors=[row['source_path'] for row in local['files'] if sha(Path(row['source_path']))!=row['sha256'] or sha(Path(row['snapshot_path']))!=row['sha256']]
bundle_check=command(['git','bundle','verify',str(RUN/'backup/all-refs.bundle')])
git_checks=[command(['git','rev-parse','HEAD']),command(['git','rev-parse','origin/main']),command(['git','rev-list','--left-right','--count','origin/main...HEAD'])]
dump(RUN/'evidence/protection-check.json',{'root_baseline_files':len(baseline['files']),'root_drift':root_drift,'permitted_metadata_drift':permitted_metadata,'unexpected_root_drift':unexplained,'external_rollback_files':len(baseline['rollback']),'external_drift':external_drift,'pinned_peer_files':sum(len(x['files']) for x in provenance['upstreams']),'peer_errors':peer_errors,'local_snapshot_errors':local_errors,'bundle_verify':bundle_check,'git_identity_commands':git_checks,'scope':'all production source/current pre-existing dirty bytes checked; mutable current main relay log intentionally documented; backup baseline captures earlier time','marker':'PROTECTED_INPUTS_UNCHANGED' if not(unexplained or external_drift or peer_errors or local_errors or bundle_check['exit_code']) else 'FAILED'})
if unexplained or external_drift or peer_errors or local_errors or bundle_check['exit_code']: raise RuntimeError('protection check failed')

inventory=json.loads((RUN/'evidence/tool-inventory.json').read_text(encoding='utf-8-sig'))
inventory['actual_td_version']='TD Release_2026.2 / 6.2.3.210850'
inventory['actual_tcl_version']='8.6.17'
inventory['ip_tool_scope']=inventory['ip_tool_scope'].replace('PLL generation','APB_GPIO generation')
inventory['compiler_version_queries']=[command(['python','--version']),command(['gcc','--version'])]
inventory['simulator_observations']={'iverilog_vvp':'not found by Get-Command or MSYS2 mingw64 bin filename scan; no installation performed','verilator_script':'D:/MSYS2/mingw64/bin/verilator exists; presence is not proof of usable runtime','actual_attempts':[{'argv':['D:/MSYS2/mingw64/bin/verilator_bin.exe','--version'],'exit_code':-1073741511,'stdout':''},{'argv':['D:/MSYS2/usr/bin/perl.exe','D:/MSYS2/mingw64/bin/verilator','--version'],'exit_code':127,'output':'%Error: Command Failed ulimit -s unlimited 2>/dev/null; exec /mingw64/bin/verilator_bin --version'},{'argv':['D:/MSYS2/usr/bin/bash.exe','-lc','env PATH=/mingw64/bin:/usr/bin /mingw64/bin/verilator --version'],'exit_code':127,'output':'%Error: Command Failed ulimit -s unlimited 2>/dev/null; exec /mingw64/bin/verilator_bin --version'}],'status':'No working RTL simulator verified in this package; next implementation package needs a working entry point. No further retries/repair performed.'}
dump(RUN/'evidence/tool-inventory.json',inventory)

p=RUN/'artifacts/next-backend-input.md'
s=p.read_text(encoding='utf-8').replace('实际运行版本见tool-inventory；','工具实启结果见tool-inventory：原生Verilator返回-1073741511，Perl/MSYS脚本入口127，未确认可用仿真器；')
p.write_text(s,encoding='utf-8')
p=RUN/'evidence/hardware-access.md'
p.write_text(p.read_text(encoding='utf-8')+'\n实际编译器：Python3.11.5、GCC13.2.0版本查询退出0。RTL仿真器：iverilog/vvp未发现；Verilator脚本存在，但原生bin版本查询返回-1073741511，Perl/MSYS入口返回127，未确认工作入口。本包不需要RTL仿真，不以文件存在报可用；下包需先补齐该条件。\n',encoding='utf-8')
(RUN/'evidence/failures.md').write_text('''# 保留的实际失败与修正

1. build_baseline.py首次退出1：FileNotFoundError WinError3，restore-check/tracked下叠加旧trial深路径超过Windows普通路径限制。原zip/bundle已经完成且保留；未删除未覆盖。将恢复目录改为新的restore-check-v2并用扩展路径，第二次退出0，3107项SHA一致。失败目录仍保留，未纳入候选文件逐项清单，因为它仅为未完成校验副本。
2. build_package.py首轮SyntaxError：Python3.11不允许f-string表达式内backslash。package-build.log保留。改为可信静态模板中的loc()替换。第二轮因regex额外双花括号未找到源证据，package-build-02.log保留；修正为匹配实际赋值后第三/四轮package_created=true。未更改生产输入。
3. Verilator原生--version exit -1073741511，输出空；Perl和MSYS脚本--version各exit127，输出Command Failed ulimit...exec /mingw64/bin/verilator_bin --version。只做工具查询，未安装/修复/构建；不作为当前DUT失败。未进一步重试。
''',encoding='utf-8')

inputs=[str(RUN/'candidate-manifest.json'),str(RUN/'contract/acceptance-vectors.json'),str(RUN/'contract/registers.json'),str(RUN/'contract/compatibility.md'),str(RUN/'contract/rk-required-changes.md'),str(RUN/'artifacts/next-backend-input.md'),str(RUN/'backup/baseline-manifest.json'),str(RUN/'references/provenance.json')]
retest={'required_dimensions':['functional','engineering','system'],'report_paths':[],'input_status':'same','reuse_decision_paths':[]}
result={'task_ids':['T03.rk-align-freeze'],'status':'ready_for_test','artifact_paths':[str(RUN/'backup/restore.md'),str(RUN/'contract/compatibility.md'),str(RUN/'contract/registers.json'),str(RUN/'contract/rk-required-changes.md'),str(RUN/'contract/acceptance-vectors.json'),str(RUN/'artifacts/next-backend-input.md'),str(RUN/'evidence/tool-inventory.json'),str(RUN/'evidence/hardware-access.md')],'manifest_path':str(RUN/'candidate-manifest.json'),'test_input_paths':inputs,'lessons_path':str(RUN/'lessons-learned.md'),'blocked':[],'retest':retest,'developer_checks':{'restored_sha_items':3107,'contract_fixture_checks':84,'tool_probe_exit':0,'production_changes':False,'build_or_download':False,'independent_tests':'not started; main dispatches three new testers'},'future_conditions':'RTL simulator working entry point and real RK/JTAG identity remain for later packages; not mandatory for T03 offline contract package'}
dump(RUN/'dev-result.json',result)

selected=[]
for sub in ('references','contract','artifacts','evidence'):
 selected.extend(p for p in (RUN/sub).rglob('*') if p.is_file() and '__pycache__' not in p.parts)
for p in (RUN/'backup').iterdir():
 if p.is_file(): selected.append(p)
 elif p.name=='stable-retake': selected.extend(q for q in p.rglob('*') if q.is_file())
selected.extend([RUN/'dev-result.json',RUN/'lessons-learned.md'])
rows=[{'path':p.as_posix(),'relative_path':p.relative_to(RUN).as_posix(),'bytes':p.stat().st_size,'sha256':sha(p)} for p in sorted(set(selected))]
manifest={'schema_version':1,'run_id':'20261017-011744-rk-fpga-align','task_ids':['T03.rk-align-freeze'],'round':0,'frozen_at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'project_root':ROOT.as_posix(),'candidate_root':RUN.as_posix(),'candidate_kind':'backup, pinned inputs, offline interface contract and synthetic fixtures; no production RTL modifications','files':rows,'upstream_inputs':{'project_head':'ba0fca5f2c397db88059040b2ffe55c76867da31','origin_main':'3862a9beef2081bbd45f8bf54d7f3b4844e3b248','peer_fpga':'2a4b253d9f2e56a943f1667b2a7a366824dcba34','peer_driver':'a0215c5a2fcb95bfc867a4768d4831d68edf64a2','local_provenance':str(RUN/'references/local-provenance.json'),'plan_inputs_snapshot':str(RUN/'references/plan-inputs')},'excluded_from_candidate':[{'path':'candidate-manifest.json','reason':'manifest cannot hash itself; testers hash this file separately'},{'path':'test-reports/','reason':'independent tester outputs/logs must not mutate candidate'},{'path':'backup/restore-check/','reason':'retained failed restoration side-copy, original archives frozen'},{'path':'backup/restore-check-v2/','reason':'verified restoration side-copy, canonical archives and per-entry baseline SHA frozen'},{'path':'run top-level planner/relay control files','reason':'mutable scheduling state; exact task inputs copied into references/plan-inputs and frozen'}],'verification_scope':{'local_G0':'contract proposal only; joint peer signoff pending','G1':'fixture consistency only; no hardware or DUT simulation','G2':'not_applicable; no production RTL/build','G3':'not_applicable for this package; no board download','G4':'not_applicable for this package; no stability run','G5':'not_applicable; parent release and end-to-end remain incomplete'},'stop_modification':'Developer stops all candidate writes after this manifest; tester outputs only in test-reports and own evidence descendants excluded from this list.'}
dump(RUN/'candidate-manifest.json',manifest)
for row in rows:
 if sha(Path(row['path']))!=row['sha256']: raise RuntimeError('freeze verification mismatch')
print(json.dumps({'status':'ready_for_test','files':len(rows),'manifest_sha256':sha(RUN/'candidate-manifest.json'),'marker':'CANDIDATE_FROZEN_INPUTS_VERIFIED','protected_root_files':len(baseline['files']),'unexpected_root_drift':unexplained},ensure_ascii=False))
