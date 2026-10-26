"""Delivery qualification only. Writes solely within this task directory."""
import csv
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

OUT=Path(__file__).resolve().parent
RUN=OUT.parent
ROOT=RUN.parents[2]
def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def readj(p): return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def dump(n,x): (OUT/n).write_text(json.dumps(x,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

# Explicit current role/constraints copies, separate from prior package controls.
control_sources={
 'root-AGENTS.md':ROOT/'AGENTS.md',
 'fpga-dev-SKILL.md':ROOT/'.agents/skills/fpga-dev/SKILL.md',
 'fpga-design-guide-SKILL.md':ROOT/'.agents/skills/fpga-design-guide/SKILL.md',
 'work-limits.md':ROOT/'.agents/skills/fpga-orchestrator/references/work-limits.md',
 'report-contract.md':ROOT/'.agents/skills/fpga-orchestrator/references/report-contract.md',
 'relay-contract.md':ROOT/'.agents/skills/fpga-orchestrator/references/relay-contract.md'}
control_sources.update({n:RUN/n for n in ['request.md','dev-plan.md','fpga-design-guide.md','input-index.md','dispatch.json']})
control_sources['task-T10-chain-transform-review.md']=RUN/'planning/task-T10-chain-transform-review.md'
controls=[]
for name,source in control_sources.items():
    frozen=OUT/'controls'/name
    before=sha(source)
    if not frozen.exists(): shutil.copyfile(source,frozen)
    assert sha(source)==before==sha(frozen),name
    controls.append(dict(source_path=str(source),snapshot_path=str(frozen),sha256=before))
dump('control-bindings.json',controls)

# Explicitly constrain the standalone HE contract; the row-window producer,
# rather than aggregate HE row counters, supplies strict per-line geometry.
findings=readj(OUT/'findings.json')
f7=next(x for x in findings['findings'] if x['finding_id']=='T10-F07')
f7['impact']+=' HE自身只核对帧总beats/rows，不独立校验逐行位置/active重SOF；其严格几何依赖前级rowwin，不能扩成任意畸形独立HE输入保证。'
dump('findings.json',findings)
review=(OUT/'review.md').read_text(encoding='utf-8')
review+='\n补充合同限定：HE自身的good_evt只核对总beats/rows及EOF/EOL，不独立检查每行长度或active重SOF；严格几何依赖前级rowwin/demosaic。F07 no_issue_found限定为已列标量/静态条件，不能外推任意独立畸形HE输入。\n'
(OUT/'review.md').write_text(review,encoding='utf-8')

w=readj(OUT/'witness/result-r0.json')
assert w['marker']=='TRANSFORM_WITNESS_COMPLETE' and len(w['geometry_cases'])==15
assert len(w['strictness_cases'])==2 and all(x['pc_all_checks'] for x in w['strictness_cases'])
for name in ['build','witness']:
    execution=readj(OUT/f'{name}-native-run.json')
    assert execution['exit_code']==0 and not execution['timed_out']
    assert Path(execution['stdout']).stat().st_size>0
for name in ['build-attempt1','witness-attempt1']:
    assert readj(OUT/f'{name}-native-run.json')['exit_code']!=0

with (OUT/'checkpoints.csv').open(encoding='utf-8-sig',newline='') as f: rows=list(csv.DictReader(f))
assert len(rows)==33 and len({x['checkpoint'] for x in rows})==33
assert all(all(str(v).strip() for v in x.values()) for x in rows)
refs=[]
for row in rows:
    p=Path(row['source_path'])
    assert sha(p)==row['source_sha256']
    assert 1<=int(row['line_start'])<=int(row['line_end'])<=len(p.read_text(encoding='utf-8-sig').splitlines())
for finding in findings['findings']:
    assert all(str(x).strip() for x in finding.values())
    for r in finding['evidence_refs']:
        p=Path(r['snapshot_path'])
        assert sha(p)==r['sha256']
        assert 1<=r['line_start']<=r['line_end']<=len(p.read_text(encoding='utf-8-sig').splitlines())
        refs.append(r)
sm=readj(OUT/'source-map.json')
assert all(sha(s['snapshot_path'])==s['sha256'] for s in sm['sources'].values())
manifest_text=(RUN/'baseline/snapshot/0141.json').read_text(encoding='utf-8').lower()
selected={sid:sm['sources'][sid]['sha256'] for sid in ['B0145','B0146','B0150']}
assert all(value in manifest_text for value in selected.values())
dump('candidate-binding.json',dict(b15_selected_changed_src_sha256=selected,
    manifest_path=str(RUN/'baseline/snapshot/0141.json'),result='selected codec/frame/camera source SHAs present in original candidate manifest',
    qualification='other historical algorithm/throughput candidates remain separately scoped'))

excerpts=[]
for r in refs:
    lines=Path(r['snapshot_path']).read_text(encoding='utf-8-sig').splitlines()
    excerpts.append('\n%s %s:%d-%d SHA256 %s\n%s' % (r['source_id'],r['snapshot_path'],r['line_start'],r['line_end'],r['sha256'],
     '\n'.join('%d: %s'%(i,lines[i-1]) for i in range(r['line_start'],r['line_end']+1))))
(OUT/'source-excerpts.txt').write_text('\n'.join(excerpts)+'\n',encoding='utf-8')
status=subprocess.run(['git','status','--short','--untracked-files=no'],cwd=ROOT,capture_output=True,timeout=60,check=True).stdout.decode('utf-8',errors='replace').splitlines()
before=readj(OUT/'worktree-before.json')
status_sha=hashlib.sha256('\n'.join(status).encode('utf-8')).hexdigest()
dump('worktree-after.json',dict(count=len(status),sha256=status_sha,
 unchanged_from_before=status_sha==before['sha256'],qualification='tracked status identity only; no ownership attribution for concurrent tasks'))
dump('local-verification-final.json',dict(marker='T10_FINAL_DELIVERY_CHECK_COMPLETE',utc=datetime.now(timezone.utc).isoformat(),
 checkpoints=33,findings=11,references=len(refs),control_bindings=len(controls),
 witness_cases=15,mutations=2,candidate_binding=True,source_sha_and_lines_valid=True,
 failed_local_attempts_retained=True,independent_acceptance=False,
 next_action='stop modification and mechanical unique manifest freeze'))
print('T10_FINAL_DELIVERY_CHECK_COMPLETE checkpoints=33 findings=11 refs=%d controls=%d'%(len(refs),len(controls)))
print('WITNESS geometry=' + str([(x['w'],x['h'],x['prep'],x['pred'],x['legacy_inverse']) for x in w['geometry_cases']]))
print('WITNESS strictness='+str(w['strictness_cases']))
print('TRACKED_STATUS_UNCHANGED='+str(status_sha==before['sha256']))
