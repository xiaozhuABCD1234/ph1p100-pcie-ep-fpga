#!/usr/bin/env python3
"""Freeze once; do not rerun over an existing manifest."""
import hashlib,json,pathlib,sys,threading,os,datetime
sys.stdout.reconfigure(encoding='utf-8')
t=threading.Timer(60,lambda:os._exit(124));t.daemon=True;t.start()
p=pathlib.Path(__file__).resolve().parent
manifest=p/'manifest-r0.json'
if manifest.exists():raise SystemExit('manifest already frozen')
def sha(q):return hashlib.sha256(q.read_bytes()).hexdigest()
binding=json.loads((p/'r0/source-binding.json').read_text(encoding='utf-8'))
inputs=binding['source_entries']
for e in inputs:
 q=pathlib.Path(e['path'])
 if not q.is_file() or sha(q)!=e['sha256']:raise SystemExit('INPUT_DRIFT '+str(q))
positive=json.loads((p/'r0/positive-results.json').read_text(encoding='utf-8'))
negative=json.loads((p/'r0/negative-results.json').read_text(encoding='utf-8'))
rtl=json.loads((p/'r0/rtl-results.json').read_text(encoding='utf-8'))
assert len(positive)==4 and all(x['byte_differences']==0 and x['four_crc_match'] for x in positive)
assert len(negative)==17 and all(x['status']=='reject' for x in negative)
assert rtl['real_slot_byte_differences']==0 and rtl['descriptor_count']==48
assert sum(x['changed'] for x in rtl['boundary'])==44
assert 'BYTE_REPLAY_RTL PASS' in (p/'r0/simulation-retry.log').read_text(encoding='utf-8')
assert 'Errors: 0, Warnings: 0' in (p/'r0/compile.log').read_text(encoding='utf-8')
assert 'SOFTWARE_LOCAL PASS positives=4 negatives=17' in (p/'check-final.log').read_text(encoding='utf-8')
assert [x['exit_code'] for x in json.loads((p/'cli-checks.json').read_text(encoding='utf-8'))]==[0,1]
evidence=dict(input_entries=len(inputs),input_drift_count=0,positive_cases=4,negative_rejects=17,
 real_rtl_slot_byte_differences=0,descriptor_count=48,boundary_length_fixtures=45,boundary_page_increases=44,
 compile_processes=1,simulation_processes=2,simulation_completed_processes=1,
 directed_case_processes_conservative=7,hardware_operations=0,external_messages=0,
 active_owned_children_at_entry=0,known_failed_attempt='vsim modelsimini backslash argument rc12; only simulation retried once',
 deadline_deviation='first two read-only entry calls had no independent hard deadline; remaining reads and all compile/sim/replay checks bounded')
(p/'freeze-evidence.json').write_text(json.dumps(evidence,indent=2)+'\n',encoding='utf-8')
artifacts=[dict(path=str(q),relative_path=q.relative_to(p).as_posix(),size=q.stat().st_size,sha256=sha(q)) for q in sorted(p.rglob('*')) if q.is_file() and q!=manifest]
tools=[]
for q,ver in [(pathlib.Path(sys.executable),sys.version),(pathlib.Path('D:/intelFPGA/18.1/modelsim_ase/win32aloem/vlog.exe'),'ModelSim Intel FPGA Edition 10.5b Compiler 2016.10'),(pathlib.Path('D:/intelFPGA/18.1/modelsim_ase/win32aloem/vsim.exe'),'ModelSim Intel FPGA Edition 10.5b')]:
 tools.append(dict(path=str(q),version=ver,sha256=sha(q)))
m=dict(schema=2,task_id='T03.pcie-byte-replay',round=0,status='ready_for_test',project_root=binding['project_root'],
 package_root=str(p),stopped_modifying=True,active_commands=0,created_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),
 source_binding_path=str(p/'r0/source-binding.json'),input_entries=inputs,artifact_entries=artifacts,tools=tools,
 parameters=dict(W=16,H=4,raw_bytes=80,rtl_zlib_bytes=70,flags=3,slot_mode=1,slot_words=128,AWB=8,BASE_WORD=0,
 P2_SLOT_BYTES=3000000,ALIGN_BYTES=4096,session=7,clock_period_ns=10),
 test_input_paths=[str(p/x) for x in ['runner.py','replay.py','tb_byte_replay.v','r0/sources.f','r0/expected.json','r0/source-binding.json','r0/rtl-results.json','r0/positive-results.json','r0/negative-results.json']],
 local_validation=evidence,limits=dict(tool_calls_max=30,tool_calls_through_final_verification_expected=25,compile_max=2,directed_case_process_max=8,role_minutes_max=45),
 model_boundaries=['DDR memory is a TB native-port model','P2 backend completion/ACK inputs are environment stimulus',
 'No real pusher/PCIe data-plane connection','Only final32B slot word padding observed; DMA page tail is an explicit offline assumption',
 '44B A1U1 header reconstructed offline only','camera/session sidecar context is not a new on-wire field',
 'b18 historical UART control; sensor pixel oracle false and physical phase unknown',
 'length4052..4096 fixtures are not compressor output','G2/G3/G4 not_run; no TD/board/RK operation'],
 responsibility_path=str(p/'byte-responsibility.md'),result_path=str(p/'result-r0.md'),lessons_path=str(p/'lessons.md'),
 manifest_exclusion='This manifest alone is excluded from its artifact hash table to avoid self reference',blocked=[],retest=None)
manifest.write_text(json.dumps(m,indent=2)+'\n',encoding='utf-8')
t.cancel()
print('FROZEN',str(manifest),'artifact_entries',len(artifacts),'input_entries',len(inputs),'sha256',sha(manifest),'stopped_modifying=true active_commands=0')
