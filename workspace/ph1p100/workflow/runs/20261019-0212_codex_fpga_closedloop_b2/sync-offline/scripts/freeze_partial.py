import datetime,hashlib,json,pathlib,subprocess
ROOT=pathlib.Path(__file__).resolve().parents[5]
OUT=pathlib.Path(__file__).resolve().parents[1]
RUN=OUT.parent
TREE=ROOT/'upstream/ph1p100-pcie-ep-fpga'
RTL=TREE/'rtl/ep_side/cam/sync_offline'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def record(p):
    p=p.resolve();assert p.is_relative_to(ROOT)
    return dict(path=str(p),size=p.stat().st_size,sha256=sha(p))
baseline=RUN/'candidate/manifest.json'
b01=json.loads(baseline.read_text(encoding='utf-8-sig'))
drift=[e['path'] for e in b01['entries'] if sha(pathlib.Path(e['path']))!=e['sha256'].lower()]
before=json.loads((OUT/'b01-before.json').read_text(encoding='utf-8-sig'))
assert before['count']==len(b01['entries'])==236
assert not drift and sha(baseline)==before['manifest_sha256'].lower()
def write(p,data):p.write_text(json.dumps(data,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
write(OUT/'b01-after.json',dict(phase='after',count=236,drift=drift,manifest_sha256=sha(baseline),checked_utc=datetime.datetime.now(datetime.timezone.utc).isoformat()))
problem=dict(problem_id='T08.codex-sync-offline:LIMIT_REACHED:offline-tb-compile',reason_code='LIMIT_REACHED',new_information=True,
 evidence_path=str(OUT/'g1/positive-r2/vlog.log'),requested_action='Original planner preserve attempts=2 and partial freeze; await genuine new user input/condition with explicit finite recovery. Do not run third compile now.',resume_input_path=str(OUT/'development-result.json'))
result=dict(task_ids=['T08.codex-sync-offline'],status='blocked',ready_for_test=False,batch_id='B02A',round=0,
 integrated_round0_occurred=False,actual_repair_rounds_used=0,command_attempts=2,command_retry_allowance_used=1,command_retry_allowance_max=1,
 td_attempts=0,gates=dict(G0='partial_fail',G1='blocked',G2='not_run',G3='not_applicable',G4='not_applicable',G5='not_applicable'),
 stopped_modification=True,owned_processes_active=False,temporary_alias_released=True,bit=None,cwc=None,final_database=None,problem=problem)
write(OUT/'development-result.json',result)
dispatch=json.loads((RUN/'dispatch.json').read_text(encoding='utf-8-sig'))
inputs=list(RTL.glob('*.v'))+[TREE/'sim/tb/tb_sync_offline.sv',OUT/'g2/sync_offline_g2.v']+list((OUT/'scripts').glob('*.py'))
inputs += [pathlib.Path(p) for p in dispatch['input_paths']]
inputs += [TREE/'rtl/ep_side/cam/ui_imx415_reg.v',TREE/'rtl/ep_side/cam/ui_cfg_imx415.v',
 OUT/'development-report.md',OUT/'lessons-learned.md',OUT/'development-result.json',OUT/'b01-before.json',OUT/'b01-after.json']
unique={str(p.resolve()):p for p in inputs}
manifest=dict(schema='fpga-partial-input-manifest-v1',task_ids=['T08.codex-sync-offline'],batch_id='B02A',round=0,
 frozen=True,ready_for_test=False,status='blocked',manifest_kind='blocked-development-inputs',
 developer_id='/root/fpga_dev_sync_offline',project_root=str(ROOT),worktree=str(TREE),
 created_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),entries=[record(unique[k]) for k in sorted(unique)],
 actual_simulation_parameters=dict(WAIT_CYCLES=12,WARMUP_FRAMES=8,I2C_TIMEOUT=40,FRAME_TIMEOUT=120,PAIR_WINDOW=15,TIMESTAMP_INIT='0xffffff00'),
 intended_default_parameters=dict(CTRL_HZ=50000000,WAIT_CYCLES=1200000,WARMUP_FRAMES=8,I2C_TIMEOUT=5000000,FRAME_TIMEOUT=5000000,PAIR_WINDOW=50000),
 bit=None,cwc=None,final_database=None,blocking_problem=problem['problem_id'])
write(OUT/'manifest.json',manifest)
evidence=[p for p in (OUT/'g1').rglob('*') if p.is_file() and (p.suffix=='.log' or p.name.endswith('.log.json'))]
write(OUT/'evidence-index.json',dict(manifest_sha256=sha(OUT/'manifest.json'),b01_manifest_sha256=sha(baseline),entries=[record(p) for p in evidence],
 commands_finished=True,owned_processes_active=False,compile_attempts=2,simulation_runs=0,td_attempts=0,negative_control_run=False))
for e in manifest['entries']: assert sha(pathlib.Path(e['path']))==e['sha256']
print(json.dumps(dict(status='blocked',input_entries=len(manifest['entries']),manifest_sha256=sha(OUT/'manifest.json'),b01_count=236,b01_drift=0,evidence_entries=len(evidence))))
