"""Local reference verification or final freeze; no subprocesses."""
from pathlib import Path
import csv, hashlib, json, sys
from datetime import datetime,timezone
OUT=Path(__file__).resolve().parent; RUN=OUT.parent
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def load(p):return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def put(n,v):(OUT/n).write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
mode=sys.argv[1]
baseline=load(RUN/'baseline/source-manifest.json')
for f in baseline['files']:assert sha(f['snapshot_path'])==f['sha256'],f['snapshot_path']
dep=load(RUN/'T02.chain-input-review/manifest-r0.json')
for f in dep['files']:assert sha(f['path'])==f['sha256'],f['path']
for f in load(OUT/'control-bindings.json'):assert sha(f['original_path'])==sha(f['frozen_path'])==f['sha256'],f
sources=load(OUT/'source-map.json')['sources']; mapped={s['snapshot_path']:s for s in sources}
rows=list(csv.DictReader((OUT/'checkpoints.csv').open(encoding='utf-8-sig',newline='')))
assert len(rows)==35 and len({r['checkpoint'] for r in rows})==35
for row in rows:
    assert all(str(v).strip() for v in row.values()),row
    f=mapped[row['source_path']];assert row['source_sha256']==f['sha256']==sha(f['snapshot_path'])
    assert 1<=int(row['line_start'])<=int(row['line_end'])<=f['line_count'],row
findings=load(OUT/'findings.json')['findings']; refs=0
for f in findings:
    assert set(['finding_id','severity','kind','claim','evidence_refs','reproduction','impact','recommendation','expected_benefit','tradeoff','validation','disposition'])<=set(f)
    assert f['kind'] in ['confirmed_issue','evidence_gap','redundancy_candidate','no_issue_found']
    for r in f['evidence_refs']:
        s=mapped[r['snapshot_path']];assert r['sha256']==s['sha256']==sha(r['snapshot_path'])
        assert 1<=r['line_start']<=r['line_end']<=s['line_count'],r
        refs+=1
w=load(OUT/'witness/result-r0.json')
assert w['marker']=='STORAGE_WITNESS_COMPLETE' and all(w['source_anchors'].values())
assert w['order_counterexample']['descriptor_expected']=='B' and w['order_counterexample']['store_actual']=='D'
assert [c['mismatch_count'] for c in w['conditional_memory_cases'].values()]==[0,1,2,2,0]
assert w['service_budget']['four_move_MBps_single']==404.5152
assert w['service_budget']['four_move_MBps_dual']==809.0304
if mode=='verify':
    put('local-verification-r0.json',{'result':'LOCAL_REFERENCE_CHECK_COMPLETE','checkpoint_count':len(rows),'finding_count':len(findings),'finding_references_checked':refs,'baseline_checked':len(baseline['files']),'T02_dependency_checked':len(dep['files']),'control_bindings_checked':len(load(OUT/'control-bindings.json')),'all_source_anchors':True,'independent_acceptance':'pending; not DUT PASS'})
    print('LOCAL_REFERENCE_CHECK_COMPLETE checkpoints=%d findings=%d refs=%d'%(len(rows),len(findings),refs))
elif mode=='freeze':
    assert not (OUT/'manifest-r0.json').exists(),'unique manifest already exists; do not overwrite'
    commands=load(OUT/'commands.json');assert all(c['exit_code']==0 for c in commands['recorded_script_commands'])
    put('activity-ended-r0.json',{'task_id':'T06.chain-storage-review','round':0,'stopped_modifying':True,'development_activities_ended_utc':datetime.now(timezone.utc).isoformat(),'assembly_witness_and_local_verification_processes':'exited 0 before final freeze command','active_build_simulation_worker_processes':0,'active_deepseek_operations':0,'hardware_actions':0,'production_changes':0,'freeze_control_only':'this final hash writer exits immediately after writing unique manifest; no further files changed'})
    inputs={}
    def add(p,role):
        p=Path(p);inputs[str(p)]={'path':str(p),'sha256':sha(p),'size':p.stat().st_size,'role':role}
    for f in baseline['files']:add(f['snapshot_path'],'immutable_unified_baseline')
    add(RUN/'baseline/source-manifest.json','baseline_manifest')
    for n in ['manifest-r0.json','review.md','findings.json','source-map.json','checkpoints.csv','lessons.md']:
        add(RUN/'T02.chain-input-review'/n,'accepted_T02_dependency')
    add(RUN/'test-reports/T02.chain-input-review-r0-integrated.md','accepted_T02_integrated_report')
    for f in dep['files']:add(f['path'],'accepted_T02_frozen_input')
    for p in sorted(OUT.rglob('*')):
        if p.is_file():
            assert p.resolve().is_relative_to(OUT.resolve()),p
            add(p,'task_artifact_or_control')
    artifact_names=['review.md','checkpoints.csv','findings.json','source-map.json','witness/check_storage_contract.py','witness/result-r0.json','commands.json','coverage-r0.json','local-verification-r0.json']
    put('manifest-r0.json',{'schema_version':1,'task_id':'T06.chain-storage-review','round':0,'status':'ready_for_test','project_root':'D:/fpga/ph1p100','frozen_utc':datetime.now(timezone.utc).isoformat(),'files':list(inputs.values()),'file_count':len(inputs),'controls':load(OUT/'control-bindings.json'),'artifact_paths':[str(OUT/n) for n in artifact_names],'test_input_paths':[str(OUT/n) for n in artifact_names]+[str(OUT/'controls/dev-plan.md'),str(OUT/'controls/fpga-design-guide.md'),str(OUT/'controls/planning/task-T06-chain-storage-review.md')],'lessons_path':str(OUT/'lessons.md'),'dependency_manifest':str(RUN/'T02.chain-input-review/manifest-r0.json'),'dependency_manifest_sha256':sha(RUN/'T02.chain-input-review/manifest-r0.json'),'required_dimensions':['functional','engineering','system'],'required_checks':['all manifest SHA before/after and zero drift','35 checkpoints and all high risk findings','independent different criterion for F05 FIFO order and descriptor mismatch','F01/F02 native address/mask qualification; F03 AW/AR acceptance gap','F04 publication visibility, F06 late verdict, F07 postguard stale R, F08 R_AR watchdog','word/byte/service budget and no slot-depth-to-fps inference','candidate/old STA/CDC/hardware evidence boundary'],'new_G_layers':{'G0':'independent review acceptance pending','G1':'local source/arithmetic/state witnesses complete; independent acceptance pending','G2':'not_applicable per frozen read-only plan','G3':'not_applicable per frozen read-only plan','G4':'not_applicable per frozen read-only plan','G5':'not_applicable per frozen read-only plan'},'production_changes':0,'hardware_actions':0,'active_development_activities':0,'blocked':None})
    print('FREEZE_COMPLETE manifest_sha256='+sha(OUT/'manifest-r0.json')+' files='+str(len(inputs)))
else:raise ValueError(mode)
