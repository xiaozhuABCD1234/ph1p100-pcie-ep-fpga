"""Run only after this role's simulator/compile children have all completed."""
from pathlib import Path
import hashlib,json,re,datetime,subprocess
H=Path(__file__).resolve().parent
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
cases=[]
for case in range(16):
 out=H/'local'/('build3-case'+str(case));s=json.loads((out/'sim-result.json').read_text());o=json.loads((out/'oracle-result.json').read_text())
 assert s['sim_pass'] and o['pass'],'not ready: case '+str(case)
 cases.append({'case':case,'sim_result':str(out/'sim-result.json'),'oracle_result':str(out/'oracle-result.json'),'seconds':s['elapsed_seconds'],'read_frames':o['read_frames'],'good_frames':o['good_frames']})
aux=json.loads((H/'local/aux/aux-results.json').read_text());assert len(aux)==2 and all(r['pass'] for r in aux)
commands=[]
for p in (H/'local').rglob('*.log'):
 for line in p.read_text(encoding='utf-8',errors='replace').splitlines():
  if line.startswith('COMMAND_RESULT '):commands.append(json.loads(line[len('COMMAND_RESULT '):]))
unique={r['log']:r for r in commands};commands=list(unique.values())
compiles=sum(Path(r['command'][0]).name.lower()=='vlog.exe' for r in commands)
sims=sum(Path(r['command'][0]).name.lower()=='vsim.exe' for r in commands)
assert compiles<=4 and sims<=20
# Each result was emitted only after Popen.wait returned a final exit status.
# Do not probe recycled PIDs, which could now belong to unrelated work.
assert all(isinstance(r['exit_code'],int) for r in commands)
protected=json.loads((H/'protected-input-audit.json').read_text())
assert all(sha(Path(p['path']))==p['sha256'] for p in protected)
(H/'commands.json').write_text(json.dumps(commands,indent=2),encoding='utf-8')
(H/'local/build3-case0/oracle-attempt1-tool-return.json').write_text(json.dumps({'source':'verbatim metadata transcribed from the observed native run_local.py tool return before the checker-only correction; original successful sim log was not rerun or overwritten','case':0,'simulation':True,'oracle':False,'seconds':77.92901515960693,'error':"AssertionError('real pin writes and random reads present')",'correction':'B has five sync role writes; retain exact pin/request equality and all independent byte/CRC checks; checker-only rerun produced the current oracle-result.json'},indent=2),encoding='utf-8')
(H/'case-results.json').write_text(json.dumps({'cases':cases,'aux':aux},indent=2),encoding='utf-8')
metrics=[]
for result in cases:
 out=Path(result['sim_result']).parent
 events=[s.split() for s in (out/'events.log').read_text().splitlines()]
 first_epoch=next(int(x[2]) for x in events if x[0]=='EPOCH')
 rel_times=[int(x[2]) for x in events if x[0]=='REL']
 last_rel=max(rel_times)
 read_beats=sum(s.startswith('R ') for s in (out/'read_beats.log').read_text().splitlines())
 metrics.append({'case':result['case'],'control_cycles_first_epoch_to_last_release':(last_rel-first_epoch)//20000,
 'dhi_cycles_first_epoch_to_last_release':(last_rel-first_epoch)//8000,'actual_axi_read_beats':read_beats,
 'actual_axi_read_bytes':32*read_beats,'verified_good_raw_bytes':20*result['good_frames'],
 'cmp_bytes':0,'maximum_declared_outstanding_bursts':1,'slot_queue_peak_proof':'four held slots explicitly hit' if result['case']==14 else 'mailbox capacity four; no claim of observed peak',
 'drop_counter_proof':'both writer bad/drop counters >0 explicitly asserted while four slots held' if result['case']==14 else 'no injected full-slot condition'})
(H/'service-metrics.json').write_text(json.dumps({'cases':metrics,'units':'event timestamps are ps; 50MHz control=20000ps, 125MHz DHI=8000ps','interpretation':'includes initialization and idle/warmup; no production rate or exposure-performance claim; exact internal queue peaks and drop counter values beyond the explicit threshold are not exported by this TB'},indent=2),encoding='utf-8')
warnings=[]
for p in (H/'local').rglob('*.log'):
 if 'build1' in p.parts or 'build2' in p.parts or 'case0-attempt1' in p.parts:continue
 for line in p.read_text(encoding='utf-8',errors='replace').splitlines():
  if '** Warning' in line:warnings.append({'log':str(p),'text':line})
(H/'warning-audit.json').write_text(json.dumps({'warnings':warnings,'interpretation':'RDGN is preserved pcie_ep_engine redundant numeric digits. TFMPC omitted ports are testbench-unused physical outputs, exported descriptor/status ports, and old B debug outputs; all digital target data/ownership/AXI inputs are explicitly tied in the enabled top TB. Default-disabled legacy TB intentionally leaves the new disabled branch ports unused. No target width or multi-driver warning is accepted as a pass by this description; review complete original lines.'},indent=2),encoding='utf-8')
budget={'limits':{'tool_calls':60,'minutes':90,'compiles':4,'case_processes':20,'small_case_seconds':300},'actual_compiles':compiles,'actual_case_processes':sims,'automatic_retries':0,'td':0,'hardware':0,'mappings':0,'download':0,'flash':0,'external_messages':0,'all_owned_commands_finished':True,'failed_evidence_preserved':['local/build1','local/case0-attempt1','local/build2'],'one_normal_case_retry_basis':'actual R bytes proved header identity correct; source inspection located session at word4 rather than mode word6; corrected reader expectations and per-frame flags','checker_correction':'camera B has five role writes; corrected total pin count lower bound from seven to five without changing exact request/pin equality or protocol sequence','worker':{'task_id':'e41b4647d8a442e49e42b98807adc147','completed':True,'pending_call_ids':[],'proposal_independently_verified':'oracle-selftest.json'}}
(H/'execution-budget.json').write_text(json.dumps(budget,indent=2),encoding='utf-8')
names={0:'normal six pairs and repeated slot reuse',1:'last-byte I2C NACK, cleanup, restart',2:'missing B and half-A abort, relock',3:'common reset during real DDR write',4:'explicit sync stop/restart and repeated warmup',5:'reset after accepted/busy I2C before response',6:'checked read-mask bit mismatch then common-reset recovery',7:'non-mask read variation allowed',8:'I2C never-busy launch timeout and recovery',9:'I2C busy-never-completes timeout and recovery',10:'actual AXI payload corruption, CRC fail, drain and good frames',11:'abort while registered AR stalls; AR retained and drained',12:'abort after accepted AR with delayed R, safe drain',13:'permanent missing R locks all held ownership; common reset recovery',14:'four protected slots full, drop whole frames, active mode change rejected',15:'old epoch release rejection'}
lines=['# T08 developer local result, round0','','This is development evidence for the isolated offline candidate; independent integrated acceptance has not yet run.','',f'Actual compiles: {compiles}/4. Actual case processes: {sims}/20. All commands ended; no TD, hardware, mapping, download, Flash or production write was performed.','', '|Case|Observable scenario|Local outcome|','|---|---|---|']
for r in cases:lines.append(f"|{r['case']}|{names[r['case']]}|simulation marker and independent actual-R byte oracle satisfied; {r['read_frames']} reads|")
lines+=['','Auxiliary tb_dual_contract covers simultaneous A/B publication and descriptor transfer, stable stalled identities, wrong-camera/stale-epoch/duplicate release rejection and exact B/A release routing. Default DUAL_LOCAL_EN=0 original normal top runs and six independent R10F frame dumps are checked.','', 'Normal case: A/B each six complete frames, 12 actual DDR reads, two-slot reuse and zero byte differences. Each sensor produced 201 initialization writes plus the exact sync requests, and 49 random-read replies. Each fault recovery completes another six good pairs; error acceptance is restricted to the explicitly injected case10 bytes.','', 'The first normal attempt failed because the added expectation used word6 (mode) for session. Actual returned bytes and source inspection fixed this to word4, plus the per-frame flags reset. The second compile exposed a repeated-generator duplicate port insertion; generation now reads the verified original. All failed logs remain. The independent checker initially overestimated B role write count; exact pin/request equality and byte checking remain enforced.','', 'G0/G1 are the requested offline scope. Full physical STA, resources/CDC, production IP binding, camera exposure timing, board recovery/stability/performance and G2/G3/G4 are not_run/awaiting_hardware. W8H2 runtime does not prove 1080p throughput; default W1920H1080 length/capacity boundaries are statically executed. The preserved reader processes eight 32-bit words per DDR beat and this candidate makes no production throughput claim.','', 'Detailed sources and modifications: source-closure.json, candidate-changes.json, candidate.diff, sources.f, integration-sources.tcl. Environment replacement and clock/ownership contracts are recorded in interface-map.md. Exact commands, return codes, owned PIDs, deadlines and logs are in commands.json and per-command logs.','', 'Rollback: stop adopting this isolated task directory. Production files and all planning-protected inputs remain unchanged.']
(H/'result-r0.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
lessons='''# T08 round0 lessons

- R10F session is header word4; word6 is mode_id. Bind descriptor identity against the frozen writer header definition, and clear every sticky extended checker flag at each new start.
- cl_pub_valid is a pulse in DHI. Separate per-camera/per-slot mailboxes accept simultaneous pulses; ready/valid is applied only after the pulse has been safely stored. A/B release routing must be tested independently with wrong-camera, stale-epoch and duplicate identities.
- A checker abort does not revoke an offered or accepted AXI request. Keep the registered AR skid, count all expected R beats, drain before release, and retain ownership in LOCK when a response never returns. Recovery requires common DDR reset to clear both the model queue and ownership.
- Preserve the frozen b10 read_mask and transaction timeout when giving sync control exclusive use of the same real I2C. Standby and stop expected read values must follow their safe initialization overrides. Pin-only read memory is separate from DUT expectations.
- Regeneration must always start from verified immutable inputs. Reusing a previously patched local closedloop file duplicated expectation port connections; compile logs retained the error and the generator was corrected.
- The A/B sync role transaction counts differ. Check the exact request-to-pin byte sequence for each camera; do not impose the A count on B. Model readback emits 49 actual random reads per camera.
- A low-risk DeepSeek pure byte-checker proposal saved repetitive parsing work. It had no project tools or pending operations, and was independently checked with a W16H3 vector and nine rejected corruptions before use. It does not replace integrated acceptance.
- Small offline cases and static default-size bounds cannot be reused as production G2, exposure synchronization, board recovery or dual-1080p30 throughput evidence.
'''
(H/'lessons.md').write_text(lessons,encoding='utf-8')
files=[]
for p in sorted(H.rglob('*')):
 if p.is_file() and p.name!='manifest-r0.json' and '__pycache__' not in p.parts and not any(x in p.parts for x in ['work']) and p.suffix.lower() not in {'.wlf','.mti','.dat','.dbs','.qdb','.wdb'}:
  files.append({'path':str(p),'sha256':sha(p),'bytes':p.stat().st_size})
inputs=[{'path':str(H.parent/n),'sha256':sha(H.parent/n)} for n in ['request.md','input-index.md','fpga-design-guide.md','dev-plan.md','planning-input-manifest.json']]
manifest={'schema':'fpga-frozen-development-v1','task_ids':['T08.dual-local-closure'],'round':0,'project_root':r'D:\fpga\ph1p100','candidate_root':str(H/'candidate'),'created_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'stopped_modifying':True,'active_commands':0,'files':files,'planning_inputs':inputs,'tools':json.loads((H/'tool-identity.json').read_text()),'parameters':{'DUAL_LOCAL_EN_default':0,'CONSUMER_MODE_default':1,'runtime_W':8,'runtime_H':2,'default_W':1920,'default_H':1080,'default_roi':[960,540,37],'I2C_DIV':14,'CAM_POWER_CYCLES':32,'CAM_CSI_RELEASE_CYCLES':8,'SYNC_WAIT_CYCLES':120,'SYNC_FRAME_TIMEOUT':30000,'SYNC_PAIR_WINDOW':64,'SYNC_I2C_TIMEOUT':5000,'LOCAL_TIMEOUT':2000,'warmup_frames':8,'raw_default_bytes':2592000,'dma_default_bytes':2592768},'environment_substitutes':['PLL and PCIe idle/timing environment','native AXI behavioral DDR memory','pin-only sensor register model','MIPI PHY bypass only; checked digital path retained'],'gates':{'G0':'ready_for_independent_test','G1':'ready_for_independent_test','G2':'not_run','G3':'not_run/awaiting_hardware','G4':'not_run/awaiting_hardware'},'commands_path':str(H/'commands.json'),'test_input_paths':[str(H/n) for n in ['run_t08.py','run_aux.py','check_t08.py','tb_production_sync.sv','tb_dual_contract.sv','tb_production_sync_legacy.sv','case-results.json','interface-map.md']],'lessons_path':str(H/'lessons.md')}
(H/'manifest-r0.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
print(json.dumps({'status':'ready_for_test','manifest_path':str(H/'manifest-r0.json'),'sha256':sha(H/'manifest-r0.json'),'stopped_modifying':True,'active_commands':0,'cases':len(cases),'compiles':compiles,'case_processes':sims}))
if __name__=='__main__':pass
