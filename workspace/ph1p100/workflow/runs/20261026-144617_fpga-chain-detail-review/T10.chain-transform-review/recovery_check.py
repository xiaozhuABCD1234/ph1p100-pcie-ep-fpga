"""Resume only: qualify existing delivery and bind new authorization; no reruns."""
import csv
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import shutil

OUT=Path(__file__).resolve().parent
RUN=OUT.parent
ROOT=RUN.parents[2]
def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def rj(p): return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def dump(name,obj): (OUT/name).write_text(json.dumps(obj,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

assert not (OUT/'manifest-r0.json').exists(), 'Already frozen: do not regenerate'
recovery_controls={
 'dispatch-recovery-20261026-195235.json': RUN/'dispatch.json',
 'recovery-T10-20261026-195235.md':RUN/'planning/recovery-T10-20261026-195235.md',
 'user-feedback-20261026-195235.md':RUN/'user-feedback-20261026-195235.md',
 'usage-check-T10-20261026-195235.json':RUN/'planning/usage-check-T10-20261026-195235.json'}
bindings=[]
for name,source in recovery_controls.items():
    frozen=OUT/'controls'/name
    before=sha(source)
    if not frozen.exists(): shutil.copyfile(source,frozen)
    assert sha(frozen)==before==sha(source)
    bindings.append(dict(source_path=str(source),snapshot_path=str(frozen),sha256=before))
dump('recovery-control-bindings.json',bindings)
dispatch=rj(OUT/'controls/dispatch-recovery-20261026-195235.json')
assert dispatch['task_ids']==['T10.chain-transform-review']
assert dispatch['next_action']['target']=='/root/fpga_review_dev_t10'

inputs={}
def bind(path,expected,role):
    p=Path(path)
    actual=sha(p)
    assert actual==expected.lower(), str(p)
    key=str(p).lower()
    if key in inputs:
        assert inputs[key]['sha256']==actual
    else:
        inputs[key]=dict(path=str(p),sha256=actual,size=p.stat().st_size,role=role)

bm=RUN/'baseline/source-manifest.json'
bind(bm,sha(bm),'immutable_baseline_manifest')
baseline=rj(bm)
for s in baseline['files']: bind(s['snapshot_path'],s['sha256'],'immutable_unified_baseline')
dep_results=[]
for dep in dispatch['completed_dependencies']:
    bind(dep['manifest_path'],dep['manifest_sha256'],'accepted_dependency_manifest')
    bind(dep['report_path'],dep['report_sha256'],'accepted_integrated_report')
    manifest=rj(dep['manifest_path'])
    for item in manifest['files']: bind(item['path'],item['sha256'],'accepted_dependency_frozen_input')
    dep_results.append(dict(task_id=dep['task_id'],checked_files=len(manifest['files']),
                            manifest_sha256=dep['manifest_sha256'],report_sha256=dep['report_sha256']))

required=['review.md','checkpoints.csv','findings.json','source-map.json','commands.json','lessons.md',
 'witness/check_transform_contract.py','witness/result-r0.json','local-verification-final.json',
 'candidate-binding.json','dependency-qualification.json','supplemental-sources.json']
for name in required:
    assert (OUT/name).stat().st_size>0,name
for name in ['build','witness','prepare']:
    log=rj(OUT/(name+'-native-run.json'))
    assert log['exit_code']==0 and not log['timed_out'],name
for name in ['build-attempt1','witness-attempt1']:
    assert rj(OUT/(name+'-native-run.json'))['exit_code']!=0
with (OUT/'checkpoints.csv').open(encoding='utf-8-sig',newline='') as f: rows=list(csv.DictReader(f))
assert len(rows)==33 and len({r['checkpoint'] for r in rows})==33
assert all(all(str(v).strip() for v in r.values()) for r in rows)
findings=rj(OUT/'findings.json')['findings']
assert len(findings)==11
refs=0
for row in rows:
    assert sha(row['source_path'])==row['source_sha256']
    assert 1<=int(row['line_start'])<=int(row['line_end'])<=len(Path(row['source_path']).read_text(encoding='utf-8-sig').splitlines())
for finding in findings:
    for ref in finding['evidence_refs']:
        assert sha(ref['snapshot_path'])==ref['sha256']
        assert 1<=ref['line_start']<=ref['line_end']<=len(Path(ref['snapshot_path']).read_text(encoding='utf-8-sig').splitlines())
        refs+=1
w=rj(OUT/'witness/result-r0.json')
assert w['marker']=='TRANSFORM_WITNESS_COMPLETE' and len(w['geometry_cases'])==15
assert len(w['strictness_cases'])==2
supp=[]
for src in rj(OUT/'supplemental-sources.json'):
    assert sha(src['snapshot_path'])==src['sha256']
    supp.append(dict(snapshot_path=src['snapshot_path'],frozen_sha256=src['sha256'],
      origin_status_now='same' if sha(src['source_path'])==src['sha256'] else 'changed_after_copy; excluded'))

note='''\n## 20261026-195235 恢复与冻结补充

用户在usage limit后明确“接着做”，续原开发、原任务、round0，实际修复仍0；没有新建替代角色或重跑非幂等prepare。旧controls/dispatch.json保留原开工合同；恢复派发/用户授权/规划说明/账户只读快照另存controls下带日期副本，recovery-control-bindings.json绑定它们。账户快照仅为恢复时条件，非未来可用性保证。

worktree-after.json和prepare-stdout.txt中的TRACKED_STATUS_UNCHANGED=False原样保留。前后均801项tracked状态，但字符串哈希不同；本角色不能据此归因并发修改或编码表现差异，也不把它改为true。实际写命令/脚本仅指向本任务目录；没有reset、覆盖或删除他人成果。统一baseline与已验依赖内容逐文件SHA再次一致，输入快照资格见recovery-verification.json。当前全仓库内容是否由其他角色改变不由本审查宣称。

恢复前开工UTC未单独落盘；首份任务文件09:05:19 UTC、最后只读记录09:49:42 UTC，不能据此证明原45分钟全部合规。原调用与首次失败证据保留，恢复按规划新增30调用/45分钟派发自行停止，不重置同一失败命令/搜索/实际修复计数。原build/witness各首次失败后一次纠正重试，prepare一次成功；本次只校验/绑定/冻结，不追加重试。

冻结前所有本角色自有native工作均已有退出记录、无待执行worker操作、无构建/仿真/硬件进程；随后只机械创建活动结束记录及唯一manifest。ready_for_test只表示审查包可供独立测试，不表示审查PASS或DUT通过。\n'''
review_path=OUT/'review.md'
review=review_path.read_text(encoding='utf-8')
if '## 20261026-195235 恢复与冻结补充' not in review:
    review_path.write_text(review+note,encoding='utf-8')
lessons=OUT/'lessons.md'
text=lessons.read_text(encoding='utf-8')
if '恢复时保留旧控制版本' not in text:
    lessons.write_text(text+'\n- 恢复时保留旧控制版本，以单独副本绑定新授权；非幂等prepare不盲重跑，既有失败与计数不清零。全树状态哈希变化须保留未知归属，冻结输入资格另以逐文件SHA确认。\n',encoding='utf-8')
commands=rj(OUT/'commands.json')
commands['resume']=dict(authorization_path=str(OUT/'controls/user-feedback-20261026-195235.md'),
 original_failure_counts=dict(build=1,witness=1),original_corrective_retries=dict(build=1,witness=1),
 actual_repairs=0,prepare_rerun=False,old_controls_retained=True,
 actual_new_command=f'python -B -X utf8 "{OUT / "recovery_check.py"}"',
 native_record='recovery-check-native-run.json',deadline_seconds=300,
 next_mechanical_command=f'PowerShell Start-Job {{ & "{OUT / "freeze_manifest.ps1"}" }}; Wait-Job -Timeout 60; Stop-Job only on own timeout')
dump('commands.json',commands)
dump('freeze-inputs.json',dict(task_id='T10.chain-transform-review',files=list(inputs.values())))
dump('recovery-verification.json',dict(marker='T10_RECOVERY_QUALIFIED_FOR_FREEZE',
 utc=datetime.now(timezone.utc).isoformat(),baseline_files=len(baseline['files']),
 external_frozen_inputs=len(inputs),dependencies=dep_results,checkpoints=33,findings=11,
 references=refs,witness_cases=15,mutations=2,retained_successful_native_records=['build','witness','prepare'],
 supplementary_snapshot_status=supp,old_controls_untouched=True,recovery_controls=bindings,
 tracked_status_mismatch_preserved=True,production_write_actions=0,hardware_actions=0,
 rerun_build=False,rerun_prepare=False,rerun_witness=False,independent_acceptance=False))
print('T10_RECOVERY_QUALIFIED_FOR_FREEZE external_inputs=%d checkpoints=33 findings=11 refs=%d'%(len(inputs),refs))
