"""One-time mechanical freeze, after all developer validation processes have exited."""
from pathlib import Path
import datetime,hashlib,json,os,sys
OUT=Path(__file__).resolve().parent
RUN=OUT.parent
ROOT=RUN.parents[2]
def j(p):return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def now():return datetime.datetime.now(datetime.timezone.utc).isoformat()
manifest=OUT/'manifest-r0.json'
assert not manifest.exists(),'Unique round0 manifest already exists; do not overwrite'
assert j(OUT/'local-check-r0.json')['status']=='local_structure_pass'
assert j(OUT/'witness/result-r0.json')['status']=='local_witness_pass'
tool_identity=dict(python_version=sys.version,python_executable=sys.executable,powershell='7.6.5 actual read',git='2.54.0.windows.1 actual read')
(OUT/'tool-identity-r0.json').write_text(json.dumps(tool_identity,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
for logname in ['native-run-attempt2-r0.json','native-run-final-qa-r0.json']:
    for rec in j(OUT/logname):assert rec['exit_code']==0 and not rec['timed_out']
activity=dict(task_id='T11.chain-egress-review',round=0,development_modification_stopped=True,
    activity_ended_utc=now(),owned_build_sim_hardware_processes_active=0,pending_worker_operations=0,
    worker_task_state='completed; requested noop denied, actual denial resumed once',
    hardware_actions=0,production_modifications=0,deletions=0,
    remaining_activity='this one-time mechanical hashing/freezing process only; no developer edit/test process remains')
(OUT/'activity-ended-r0.json').write_text(json.dumps(activity,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
entries={}
def add(p,role,expected=None):
    p=Path(p).resolve();h=sha(p)
    if expected is not None:assert h==expected,(str(p),h,expected)
    if str(p) not in entries:entries[str(p)]=dict(path=str(p),sha256=h,size=p.stat().st_size,role=role)
    else:assert entries[str(p)]['sha256']==h
add(RUN/'baseline/source-manifest.json','immutable_unified_baseline_index')
for e in j(RUN/'baseline/source-manifest.json')['files']:add(e['snapshot_path'],'immutable_unified_baseline',e['sha256'])
bindings=j(OUT/'dependency-bindings.json')
for d in bindings:
    add(d['manifest_path'],'accepted_dependency_manifest',d['manifest_sha256'])
    add(d['report_path'],'accepted_dependency_integrated_report',d['report_sha256'])
    for e in j(d['manifest_path'])['files']:add(e['path'],'accepted_dependency_transitive_input',e['sha256'])
for p in sorted(OUT.rglob('*')):
    if p.is_file():add(p,'T11_frozen_input_or_review_artifact')
result=dict(schema_version=1,task_id='T11.chain-egress-review',task_ids=['T11.chain-egress-review'],round=0,
    status='ready_for_test',actual_repairs=0,project_root=str(ROOT),task_output_dir=str(OUT),
    purpose='read-only egress and chain audit; no DUT/production/hardware acceptance',
    frozen_utc=now(),development_modification_stopped=True,activity_ended_utc=activity['activity_ended_utc'],
    baseline_manifest_path=str(RUN/'baseline/source-manifest.json'),baseline_manifest_sha256=sha(RUN/'baseline/source-manifest.json'),
    dependencies=bindings,independent_acceptance='pending fresh single integrated tester',
    new_execution_G_layers={'G0':'local audit tools completed; integrated verdict pending','G1':'local arithmetic/event witness completed; integrated verdict pending','G2':'not_applicable per frozen dev-plan read-only scope','G3':'not_applicable per frozen dev-plan read-only scope','G4':'not_applicable per frozen dev-plan read-only scope','G5':'not_applicable per frozen dev-plan read-only scope'},
    files=sorted(entries.values(),key=lambda x:x['path']))
manifest.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'manifest_path':str(manifest),'sha256':sha(manifest),'unique_files':len(entries),'status':'ready_for_test','owned_developer_processes_active':0},ensure_ascii=False))
