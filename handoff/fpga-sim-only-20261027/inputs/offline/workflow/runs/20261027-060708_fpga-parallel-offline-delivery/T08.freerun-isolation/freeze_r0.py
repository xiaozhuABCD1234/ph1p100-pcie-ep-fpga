"""One final packaging action. Run only after all other commands have ended."""
from pathlib import Path
import datetime, hashlib, json, sys

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[3]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def save(p,d):p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

def main():
    target=HERE/'manifest-r0.json'
    assert not target.exists(),'unique freeze already exists; do not overwrite'
    local=json.loads((HERE/'local-verification.json').read_text())
    assert local['local_checks_pass'] and local['compile_count']==1 and local['case_process_count']==6
    binding=json.loads((HERE/'inputs/source-binding.json').read_text())
    refs=binding['sources']+binding['references']
    refs+=[{'path':binding['old_manifest_path'],'sha256':binding['old_manifest_sha256'],'role':'old_frozen_manifest'}]
    tool_paths=[Path(sys.executable)]+[Path('D:/intelFPGA/18.1/modelsim_ase/win32aloem')/n for n in ['vlib.exe','vlog.exe','vsim.exe']]
    for p in tool_paths:refs.append({'path':str(p),'sha256':sha(p),'bytes':p.stat().st_size,'role':'tool_binary'})
    for r in refs:assert sha(Path(r['path']))==r['sha256'],('input drift',r['path'])
    save(HERE/'retest.json',{'required_dimensions':['functional','engineering','system'],
      'required_checks':['six real frozen DUT cases with continuous source SOFs/EOFs','independent byte/CRC and source conservation',
        'held-slot memory and AW exclusion','A/B/selected/release identity interface','four sensitivity controls plus tester-independent criterion',
        'manifest before/after drift check','model boundary and default geometry/address budget review'],
      'report_paths':[str(HERE/'result-r0.md'),str(HERE/'case-results.json'),str(HERE/'negative-controls.json'),str(HERE/'static-interface-result.json')],
      'input_status':'same','reuse_decision_paths':[]})
    metadata={'task_ids':['T08.freerun-isolation'],'status':'ready_for_test','stopped_modifying':True,'active_commands':0,
      'artifact_paths':[str(HERE/'result-r0.md'),str(HERE/'handoff.md'),str(HERE/'case-results.json'),str(HERE/'static-interface-result.json'),str(HERE/'negative-controls.json')],
      'manifest_path':str(target),'test_input_paths':[str(HERE/'run_freerun.py'),str(HERE/'tb_freerun.sv'),str(HERE/'check_freerun.py'),str(HERE/'inputs/source-binding.json'),str(HERE/'inputs/task-dispatch.json')],
      'lessons_path':str(HERE/'lessons.md'),'blocked':[],
      'retest':json.loads((HERE/'retest.json').read_text())}
    save(HERE/'ready-for-test.json',metadata)
    files=[];excluded=[]
    for p in sorted(HERE.rglob('*')):
      if not p.is_file() or p==target:continue
      rel=p.relative_to(HERE)
      if '__pycache__' in rel.parts or 'work' in rel.parts or p.suffix in ['.wlf']:
        excluded.append({'path':str(p),'reason':'rebuildable simulator library/waveform or Python bytecode; not a verification input'});continue
      assert p.resolve().is_relative_to(HERE),'linked output outside package'
      files.append({'path':str(p),'sha256':sha(p),'bytes':p.stat().st_size,'role':'package_artifact'})
    for row in refs:
      p=Path(row['path']);files.append({'path':str(p),'sha256':row['sha256'],'bytes':p.stat().st_size,'role':row.get('role','frozen_readonly_input')})
    manifest={'schema':'fpga-frozen-development-v1','task_ids':['T08.freerun-isolation'],'round':0,'status':'ready_for_test',
      'created_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'project_root':str(ROOT),'package_root':str(HERE),
      'stopped_modifying':True,'active_commands':0,'files':files,'excluded_mutable_artifacts':excluded,
      'parameters':{'source_frames_per_camera':12,'runtime_W':8,'runtime_H':2,'runtime_raw_bytes':20,'runtime_dma_bytes':4096,
        'default_W':1920,'default_H':1080,'default_packed_bytes_per_camera':2592000,'dual_raw_30fps_MB_s':155.520,
        'SYNC_ENABLE':0,'DUAL_LOCAL_EN':1,'CONSUMER_MODE':2,'LOCAL_TIMEOUT':1000000,
        'byte_clock_period_ns':[14,18],'DHI_clock_period_ns':8,'system_clock_period_ns':20,
        'T0_ns':20000,'consumer_recovery_ns':320000,'normal_frame_period_ns':50000,'case2_B_frame_period_ns':52000,'case2_B_frame_phase_ns':3000},
      'actual_counts':{'compile':1,'case_process':6,'TD':0,'hardware':0,'download':0,'Flash':0,'COM':0,'JTAG':0,'RK_write':0,'install':0,'commit':0,'push':0,'external_message':0},
      'compiled_sources_path':str(HERE/'inputs/sources.f'),'source_binding_path':str(HERE/'inputs/source-binding.json'),
      'commands_path':str(HERE/'commands.jsonl'),'test_input_paths':metadata['test_input_paths'],'lessons_path':metadata['lessons_path'],
      'retest':metadata['retest'],'gates':{'G0':'development_local_checked','G1':'real frozen RTL simulation local checked','G2':'not_run: no RTL edits in this package','G3':'not_run/awaiting_hardware','G4':'not_run/awaiting_hardware','G5':'development artifact closure checked'},
      'scope_limit':'offline package only; no independent integrated verdict, full-resolution throughput or board claim'}
    save(target,manifest)
    print(json.dumps({'status':'ready_for_test','manifest_path':str(target),'manifest_sha256':sha(target),'files':len(files),'excluded_rebuildable':len(excluded),'stopped_modifying':True,'active_commands_after_exit':0}),flush=True)

if __name__=='__main__':main()
