"""Local document/source verification and final one-way freeze. No later writes."""
import argparse
import csv
import hashlib
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT=Path('D:/fpga/ph1p100')
RUN=ROOT/'workflow/runs/20261026-144617_fpga-chain-detail-review'
OUT=RUN/'T02.chain-input-review'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path):
    # Legacy vendor comments may use a different encoding; hashes use raw bytes.
    return path.read_text(encoding='utf-8-sig',errors='replace')


def save(name,value):
    path=(OUT/name).resolve()
    assert path.is_relative_to(OUT.resolve())
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')


def verify():
    sources=json.loads(read(OUT/'source-map.json'))['sources']
    with (OUT/'checkpoints.csv').open(encoding='utf-8-sig',newline='') as handle:
        rows=list(csv.DictReader(handle))
    assert len(rows)==28 and len({r['checkpoint'] for r in rows})==28
    required=['checkpoint','stage','parent_task','producer','consumer','source_path','source_sha256',
              'line_start','line_end','input_output_units','clock_reset','acceptance_event','ownership',
              'invariant','failure_recovery','result','evidence','optimization','verification_next']
    kinds={'confirmed_issue','redundancy_candidate','evidence_gap','no_issue_found'}
    for row in rows:
        assert all(row.get(key,'').strip() for key in required),row['checkpoint']
        path=Path(row['source_path'])
        assert sha(path)==row['source_sha256']
        assert 1<=int(row['line_start'])<=int(row['line_end'])<=len(read(path).splitlines())
        assert row['result'] in kinds
    findings=json.loads(read(OUT/'findings.json'))['findings']
    assert len(findings)==10
    for item in findings:
        assert item['kind'] in kinds
        for key in ['finding_id','severity','kind','claim','evidence_refs','reproduction','impact',
                    'recommendation','expected_benefit','tradeoff','validation','disposition']:
            assert item[key],(item['finding_id'],key)
        for evidence in item['evidence_refs']:
            path=Path(evidence['snapshot_path'])
            assert sha(path)==evidence['sha256']
            assert 1<=evidence['line_start']<=evidence['line_end']<=len(read(path).splitlines())
            assert evidence['source_id'] in sources
    for entry in sources.values():
        assert sha(Path(entry['snapshot_path']))==entry['sha256']
    baseline=RUN/'baseline/source-manifest.json'
    assert sha(baseline)=='c08adc09b364828fee5d94953a89898a3220af8c8f99cdec52404fec06f74c96'
    for entry in json.loads(read(baseline))['files']:
        assert sha(Path(entry['snapshot_path']))==entry['sha256']
    witness=json.loads(read(OUT/'witness/run-r0/result.json'))
    assert witness['marker']=='T02_INPUT_WITNESS_COMPLETE'
    assert witness['single_lane_sweep']=={'cases':4096,'mismatches':4089}
    for binding in witness['source_bindings']:
        assert sha(Path(binding['path']))==binding['sha256']
    for name in ['review.md','lessons.md','commands.json','coverage-r0.json','baseline-verification-r0.json']:
        assert (OUT/name).stat().st_size>0
    result={'marker':'T02_LOCAL_REVIEW_VERIFIED','status':'local_checks_passed_independent_acceptance_pending',
            'tool_versions':{'python':sys.version,'libraries':'Python standard library only'},
            'checkpoint_rows':28,'blank_rows':0,'finding_count':10,
            'high_risk_findings':[f['finding_id'] for f in findings if f['severity']=='high'],
            'source_map_entries_checked':len(sources),'baseline_snapshot_hashes_checked':287,
            'witness_source_hashes_checked':len(witness['source_bindings']),
            'semantic_source_reading':'developer review documented; reference validity/schema verified here',
            'DUT_or_hardware_pass_claim':False,'production_source_modifications':0}
    save('local-verification-r0.json',result)
    print('T02_LOCAL_REVIEW_VERIFIED checkpoints=28 findings=10 sources='+str(len(sources))+' baseline=287')


def freeze():
    # Final write phase: freeze copies of mutable control files, then stop record,
    # then the manifest. Nothing reads live production sources after this point.
    required=OUT/'local-verification-r0.json'
    assert json.loads(read(required))['marker']=='T02_LOCAL_REVIEW_VERIFIED'
    assert not (OUT/'manifest-r0.json').exists(),'r0 manifest already exists; never overwrite frozen input'
    control_files=['request.md','dev-plan.md','fpga-design-guide.md','input-index.md','dispatch.json',
                   'planning/recovery-20261026-151257.md','user-feedback-20261026-151257.md']
    controls=[]
    for name in control_files:
        source=RUN/name
        destination=OUT/'controls'/name
        destination.parent.mkdir(parents=True,exist_ok=True)
        before=sha(source)
        destination.write_bytes(source.read_bytes())
        assert before==sha(source)==sha(destination)
        controls.append({'original_path':str(source),'frozen_path':str(destination),'sha256':before})
    commands=json.loads(read(OUT/'commands.json'))
    commands['executed'].append({'operation':'local artifact verification',
        'command':'"C:/Program Files/Python311/python.exe" -B -X utf8 verify_and_freeze.py verify',
        'cwd':str(OUT),'deadline_seconds':60,'control':'own Start-Process with WaitForExit(60000), Kill(true) only on timeout',
        'exit_code':0,'marker':'T02_LOCAL_REVIEW_VERIFIED','artifact':'local-verification-r0.json'})
    commands['executed'].append({'operation':'activity end and manifest freeze',
        'command':'"C:/Program Files/Python311/python.exe" -B -X utf8 verify_and_freeze.py freeze',
        'cwd':str(OUT),'deadline_seconds':60,'control':'own ProcessStartInfo, CreateNoWindow, redirected pipes only; WaitForExit(60000), Kill(true) on timeout; Python has no child processes',
        'completion_marker':'T02_READY_FOR_TEST_FROZEN','manifest':'manifest-r0.json'})
    save('commands.json',commands)
    stop_time=datetime.now(timezone.utc).isoformat()
    save('activity-ended-r0.json',{'task_id':'T02.chain-input-review','round':0,
        'status':'development_modification_stopped','activity_end_utc':stop_time,
        'active_build_sim_or_hardware_processes_started_by_role':0,
        'witness_and_assembly_and_verify_processes':'all exited before final freeze',
        'production_changes':0,'hardware_actions':0,'bulk_or_single_deletions':0,
        'controls':controls,'next_action':'single independent integrated tester; no developer writes after manifest'})
    base_path=RUN/'baseline/source-manifest.json'
    base=json.loads(read(base_path))
    files=[]
    for entry in base['files']:
        path=Path(entry['snapshot_path'])
        assert sha(path)==entry['sha256']
        files.append({'path':str(path),'sha256':entry['sha256'],'size':path.stat().st_size,'role':'immutable_unified_baseline'})
    files.append({'path':str(base_path),'sha256':sha(base_path),'size':base_path.stat().st_size,'role':'baseline_manifest'})
    for path in sorted(OUT.rglob('*')):
        if path.is_file():
            assert path.resolve().is_relative_to(OUT.resolve())
            if path.name=='manifest-r0.json':
                continue
            files.append({'path':str(path),'sha256':sha(path),'size':path.stat().st_size,
                          'role':'frozen_control_copy' if 'controls' in path.parts else 'task_artifact_or_supplement'})
    assert len(files)==len({entry['path'] for entry in files})
    manifest={'schema_version':1,'task_id':'T02.chain-input-review','task_ids':['T02.chain-input-review'],
        'round':0,'status':'ready_for_test','purpose':'read-only input-chain audit; not a new FPGA build candidate',
        'project_root':str(ROOT),'task_output_dir':str(OUT),'frozen_utc':datetime.now(timezone.utc).isoformat(),
        'activity_ended_utc':stop_time,'development_modification_stopped':True,
        'baseline_manifest_path':str(base_path),'baseline_manifest_sha256':sha(base_path),
        'files':files,'file_count':len(files),'controls':controls,
        'artifact_paths':[str(OUT/name) for name in ['review.md','checkpoints.csv','findings.json','source-map.json','witness','commands.json','coverage-r0.json','local-verification-r0.json']],
        'test_input_paths':[str(OUT/name) for name in ['review.md','checkpoints.csv','findings.json','source-map.json','witness/check_input_contract.py','witness/run-r0/result.json','controls/dev-plan.md','controls/fpga-design-guide.md']],
        'lessons_path':str(OUT/'lessons.md'),'required_dimensions':['functional','engineering','system'],
        'required_checks':['all manifest SHA before/after','100 percent semantic cluster coverage and citation validity',
                           'independent different criterion for F01; inspect all high risk F01/F02/F05',
                           'F02/F03 late verdict/last-line source trace','candidate and source supplement evidence qualification',
                           'no hardware/DUT PASS extrapolation'],
        'new_G_layers':{'G0':'independent acceptance pending','G1':'local witness complete; independent acceptance pending',
                        'G2':'not_applicable per frozen read-only plan','G3':'not_applicable per frozen read-only plan',
                        'G4':'not_applicable per frozen read-only plan','G5':'not_applicable per frozen read-only plan'},
        'production_changes':0,'hardware_actions':0,'blocked':None}
    save('manifest-r0.json',manifest)
    print('T02_READY_FOR_TEST_FROZEN files='+str(len(files))+' manifest_sha256='+sha(OUT/'manifest-r0.json'))


if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('action',choices=['verify','freeze'])
    args=parser.parse_args()
    if args.action=='verify':verify()
    else:freeze()
