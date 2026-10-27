"""Final write only after all simulations/production sessions have ended."""
import pathlib,json,hashlib,shutil,sys,time,subprocess,xml.etree.ElementTree as ET,re
TC=pathlib.Path(__file__).resolve().parents[1];OLD=TC.parent;BASE=OLD.parent;RUN=BASE.parents[1]
ROOT=next(p for p in TC.parents if (p/'AGENTS.md').is_file());P=ROOT/'upstream/ph1p100-pcie-ep-fpga'
attempt=int(sys.argv[1]); assert attempt in [5,6]
def readj(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def sha(p):
    h=hashlib.sha256()
    with p.open('rb') as f:
        for b in iter(lambda:f.read(1048576),b''):h.update(b)
    return h.hexdigest()
def writej(p,o):p.write_text(json.dumps(o,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
B=TC/'build'/f'attempt{attempt}';E=TC/'engineering'/f'attempt{attempt}';PHY=B/'prj/ph1p_pcie_integration_Runs/phy_1'
for d in (TC/'build').glob('attempt*'):assert (d/'execution-result.json').is_file(),'production activity still pending'
eng=readj(E/'result.json');exe=readj(B/'execution-result.json');assert exe['exit']==0 and not exe['timed_out']
assert not eng['source_drift']
assert all(sha(pathlib.Path(e['path']))==e['sha256'] for e in readj(B/'inputs.json'))
review=(TC/'manual-engineering-review.md').read_text(encoding='utf-8');assert sha(E/'result.json') in review and 'Final-review-complete: true' in review
ready=bool(eng['pass']) and 'Coverage-boundary-review-complete: true' in review
latest={}
for f in sorted((TC/'g1').glob('*/result.json')):
    r=readj(f);r['result_path']=str(f);latest[r['tb']]=r
for name in ['tb_closedloop_raw_algo','tb_closedloop_injection','tb_cam_algo_oracle','tb_cam_algo_oracle_negative','tb_cam_algo_adapter_big']:
    r=latest[name];assert r['exit']==0 and not r['timeout'] and not r['sim_error'] and r['pass_marker'],name
algo={}
for f in sorted((TC/'algo-g1').glob('*/report.json')):
    r=readj(f);r['report_path']=str(f);algo[(r['case'],r['mutation'])]=r
for key in [('core','none'),('core','he_samebin'),('rate','none')]:assert algo[key]['verdict']=='PASS',key
reuse=readj(TC/'reuse-evidence.json');assert all(r['closure_unchanged'] and not r['changed_algorithm_module_elaborated'] for r in reuse['checks'])
protected=readj(BASE/'protected-T08.json');assert sha(pathlib.Path(protected['manifest']))==protected['manifest_sha256']
assert all(sha(pathlib.Path(e['path']))==e['sha256'] for e in protected['entries'])
candidate=TC/'candidate';candidate.mkdir(exist_ok=False);prefix='current' if ready else 'rejected'
for src,dst in [(PHY/'cw/compiled.bit',prefix+'.bit'),(PHY/'cw/compiled.cwc',prefix+'.cwc'),(PHY/'ph1p_pcie_integration_inst.bid',prefix+'.bid')]:shutil.copyfile(src,candidate/dst)
probes=[]
for n in ET.parse(candidate/(prefix+'.cwc')).getroot().findall('.//watcher_nodes/bus'):
    if n.get('is_enabled')=='yes':probes.append({'name':n.get('name'),'clock':n.get('clock'),'instance':n.get('inst'),'width':len(n.findall('net')),'nets':[p.attrib for p in n.findall('net')]})
writej(candidate/'probe-map.json',{'probes':probes,'snapshot_rule':'Atomic within each native camera/DHI/TL core only; different clock cores not atomic together.','reader_flags':{'31':'sticky completed result present','15:8':'checker error','3':'length_ok','2':'payload_crc_ok','1':'header_crc_ok','0':'magic_ok'},'recovery_rule':'Exact first legal publication after writer rejection must pass full checker; older pending frames do not count.'})
unmeasured=['G3 actual single-A geometry/Bayer phase/full DDR readback/bad-frame recovery (separate T02)','G4 sustained stability/performance/thermal','physical CSI CRC injection and algorithm image quality','PCIe/RK/compression/Flash/dual-camera exposure integration']
writej(TC/'evidence-index.json',{'current_g1':latest,'algo_g1':{'/'.join(k):v['report_path'] for k,v in algo.items()},'reused_dependency_proofs':str(TC/'reuse-evidence.json'),'engineering':str(E/'result.json'),'production_attempt':attempt,'unmeasured':unmeasured,'independent_round0':'not started','actual_repair_rounds':0})
counts=readj(TC/'attempt-counts.json');assert counts['production_cumulative_used']==attempt
metrics=eng['metrics']
report_common=f'''Production variants additionally include a documented bram(fast) row-bank inference request and unreset data-only read registers. Valid/state/config/sideband resets and synchronous read latency stay unchanged. Actual inference/resource/timing findings are in manual-engineering-review.md. One own parallel subst race caused RAW and HE-negative launch failures; both are preserved/count against old cases and corrected by serial execution. No RTL assertion/oracle was weakened. See g1-mapping-failure.md.

Actual candidate: {P}, top ph1p_pcie_ep_top_closedloop, PH1P100SBG484 speed3. Original camera5.332ns/DHI10ns/TL16ns constraints and vendor IP remain unchanged. Production cumulative{attempt}/6; historical two1800s timeouts and checkpoint completion remain archived. This continuation uses actual3600s deadlines; CWC600s. Final routed metrics {metrics}; resource capacity={eng['resources_within_capacity']}, CWC physical checker exit={eng['cwc_check_exit']}, bit-pair equality={eng['bit_pair_equal']}, source drift={eng['source_drift']}. See engineering/attempt{attempt}/result.json and manual-engineering-review.md. Independent integrated round0 has not occurred; actual repair rounds0. No download, Flash, PCIe/RK, commit or push occurred. G3/G4 remain unmeasured. Source prechange SHA/diff, old415/527 manifests and all old failures are preserved. Root one-file deletion rule respected; no files deleted.
'''
for task,title,body in [('T06','DDR writer/readback','Writer/checker/controller implementation unchanged in this continuation. Full1080p648192word CRC/header/length and ownership/drain/error20-case tests reuse actual unchanged elaborated dependencies (11-test reuse-evidence.json); RAW+algo overflow/recovery and one-shot injection were rerun on current top. Independent tester must decide reuse against this new manifest. No partial prefix is claimed full-frame readback.'),('T09','Production parallel algorithms','Production variants are recorded in rtl/ep_side/img/algo/PROVENANCE-production.md: conservative front enable, registered capacity, three-stage exact grayscale partial sums, independent branch token queues and transfer-gated abort notifications. Pixel mathematics/oracle/vector bytes remain unchanged; source byte equivalence is not claimed. Affected core24/HE-negative/varying-adapter/ROI-negative/RAW-isolation/full1080p/continuous-service checks rerun. First core run missed hold coverage; staged TB now adds8cycle periodic independent branch stalls while retaining every original assertion and directed stall. Final numerical, marker, LUT and actual hold checks pass; see frozen detailed logs. Benchmark service remains modeled, not board frame-rate proof.')]:
    (TC/(task+'-development-report.md')).write_text(f'# {task} — {title}\n\nDevelopment status: '+('ready_for_test' if ready else 'blocked')+'\n\n'+body+'\n\n'+report_common,encoding='utf-8')
(TC/'lessons-learned.md').write_text('''# Continuation lessons

A payload register sharing a downstream enable does not cut combinational backpressure. A two-slot valid-token FIFO must derive upstream ready only from registered occupancy; payload and every sideband share entry lifetime. Abort markers are real internal tokens and cannot be auto-popped while the next pipeline is stalled.

Added elasticity can move sparse outputs beyond short directed stalls. Keep exact oracle and assertions, add observable output stalls in a staged TB, record both the missed-coverage failure and passing correction; never remove the coverage assertion.

Native default flow and actual settings must be read together. A named hold-fix option in settings does not prove the explicit fix_hold command ran. Use local native help and actual phase markers; final setup/hold and paired DB/bit/CWC still decide acceptance.

Read the actual netlist path, not only packed cell names: attempt5's bank-named launch was queue count feeding address decode, distributed RAM and the output register. The documented block-RAM request and removal of a read-data asynchronous reset did not guarantee ERAM absorption: native synthesis reported remaining synthesized-output synchronous-reset incompatibility. Inspect actual inference diagnostics and resource mapping; do not infer success from an attribute or generic coding advice. Keep state/valid reset and prove valid pixel/marker/reset behavior with untouched oracle vectors, then confirm actual memory mapping and resource use.

Do not launch mapping-using ModelSim runners concurrently: process-local free-drive checks race on global subst letters. Preserve and count tool launch failures, serialize corrected runs, and terminate only owned native PID trees at the actual deadline.
''',encoding='utf-8')
files=set()
for e in readj(B/'inputs.json'):
    f=pathlib.Path(e['path']).resolve();assert f.is_relative_to(ROOT.resolve())
    if 'sync_offline' in f.parts:continue
    if f.parent==P/'tools/pcie_integration/td' and f.name!='00_all_closedloop.tcl':continue
    if f.parent==P/'constraints' and f.name not in {'ph1p_pcie_case_ep.adc','ph1p_pcie_case_ep_closedloop.sdc','ph1p_pcie_case_ep_dbg.sdc'}:continue
    files.add(f)
for base in [P/'rtl',P/'al_ip',P/'sim']:
    for f in base.rglob('*'):
        if f.is_file() and f.suffix.lower() in {'.v','.sv','.vh','.f','.mem','.hex','.mif','.coe','.xml'} and 'sync_offline' not in f.parts and f.name!='tb_sync_offline.sv':files.add(f.resolve())
for f in TC.rglob('*'):
    if f.is_file() and 'build' not in f.relative_to(TC).parts and f.name not in {'manifest.json','development-result.json','board-entry.md'}:files.add(f.resolve())
for f in PHY.iterdir():
    if f.is_file() and (f.suffix in {'.db','.timing','.area','.ts','.txt','.tcl','.log','.bid'}):files.add(f.resolve())
for f in [B/'inputs.json',B/'execution-result.json',B/'deadline.log',B/'prj/td_00_all_closedloop.log',P/'tools/pcie_integration/run_td.ps1',P/'tools/pcie_integration/run_sim.ps1',ROOT/'tools/td/check_chipwatcher_readback.py',ROOT/'tools/algo/oracle_algo.py',ROOT/'AGENTS.md',OLD/'candidate/manifest.json',BASE/'attempt-counts-verified.json',BASE/'cdc-review.md']:
    assert f.is_file(),str(f);files.add(f.resolve())
for r in reuse['checks']:
    d=pathlib.Path(r['previous_result']).parent
    for name in ['result.json','inputs.json','deadline.log','vlog.log','vsim.log']:
        if (d/name).is_file():files.add((d/name).resolve())
control=candidate/'planning-inputs';control.mkdir()
for name in ['dispatch-production-remaining-attempts01.json','production-remaining-attempts01-plan.md','production-remaining-attempts01-ledger.json','request.md','request-followup-01.md','request-followup-02.md','request-followup-03.md','dispatch-production-timing-continuation01.json','production-timing-continuation01-plan.md','production-timing-continuation01-ledger.json','board-priority-supplement.md','recovery01-plan.md','dev-plan.md','fpga-design-guide.md','input-index.md']:
    dst=control/name;shutil.copyfile(RUN/name,dst);files.add(dst.resolve())
for name in ['C:/Program Files/Python311/python.exe','D:/anlogic/TD_Release_2026.2/bin/td_commands_prompt.exe','D:/anlogic/TD_Release_2026.2/bin/run.exe','D:/anlogic/TD_Release_2026.2/bin/bw.exe','D:/intelFPGA/18.1/modelsim_ase/win32aloem/vsim.exe','D:/intelFPGA/18.1/modelsim_ase/win32aloem/vlog.exe','D:/intelFPGA/18.1/modelsim_ase/win32aloem/vlib.exe']:
    files.add(pathlib.Path(name).resolve())
entries=[{'path':str(f),'size':f.stat().st_size,'sha256':sha(f)} for f in sorted(files,key=str)]
manifest={'schema':'fpga-batch-candidate-v3','run_id':RUN.name,'task_ids':['T06.codex-ddr-readback-int','T09.codex-production-int'],'batch_id':'B01','recovery_phase':'recovery01/timing-continuation01/remaining-attempts01','round':0,'frozen':True,'ready_for_test':ready,'status':'ready_for_test' if ready else 'blocked','independent_acceptance':'pending' if ready else 'not_started_G2_failed','production_attempt':attempt,'production_attempts_used':attempt,'production_attempts_max':6,'G2_pass':ready,'top':'ph1p_pcie_ep_top_closedloop','device':'PH1P100SBG484 speed3','source_head':subprocess.check_output(['git','-C',str(P),'rev-parse','HEAD'],text=True,timeout=10).strip(),'parameters':{'CLOSEDLOOP_EN':1,'DBG_CTRL_DEFAULT_EN':1,'ROI':[960,540,1920,1080],'SKIP_ROWS':37,'PHASE':3,'FIFO_AW':10,'cam_period_ns':5.332,'DHI_MHz':100},'entries':entries,'historical_manifest':{'path':str(OLD/'candidate/manifest.json'),'sha256':sha(OLD/'candidate/manifest.json'),'historical_only':True},'retest':{'required_dimensions':['functional','engineering','system'],'required_checks':['current affected G1/core/negative/marker/stall/RAW-recovery','same-DB final setup+hold/coverage/CDC/resources/CWC+bit pair','unique input selfcheck and T08 protection','unchanged DUT closure evidence reuse decision'],'input_status':'changed','reuse_decision_paths':[str(TC/'reuse-evidence.json')],'report_paths':[str(TC/'T06-development-report.md'),str(TC/'T09-development-report.md')]},'not_run':unmeasured,'derived_after_hash':['board-entry.md','development-result.json'],'tool_versions':{'Python':sys.version,'TD':'Release_2026.2 native6.2.3.210850','ModelSim':'10.5b'}}
blob=(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n').encode('utf-8');mh=hashlib.sha256(blob).hexdigest()
rollback=ROOT/'workflow/runs/20261018-1631_runA_fpga_side_readchannel/debug-fix3/prj/ph1p_pcie_integration_Runs/phy_1/cw'
artifact_lines='\n'.join(f"- `{candidate/n}` SHA256 `{sha(candidate/n)}`" for n in [prefix+'.bit',prefix+'.cwc',prefix+'.bid','probe-map.json'])
board=f'''# B01 unique board entry — developer has not downloaded

Status {'eligible only after both independent integrated reports PASS' if ready else 'BLOCKED — rejected candidate; forbidden to download'}. Manifest SHA256 `{mh}`. Final DB `{PHY/'ph1p_pcie_integration_pr.db'}` SHA256 `{sha(PHY/'ph1p_pcie_integration_pr.db')}`. Final timing `{metrics}`.

{artifact_lines}

SRAM entry, for separately dispatched T02 only, after T06 AND T09 same-manifest integrated PASS:

```powershell
& 'C:/Program Files/Python311/python.exe' '{TC}/scripts/run_sram.py' --execute
```

The wrapper requires the two distinct task reports with this manifest SHA, full frozen hash equality and ready_for_test. Exact reviewed native Tcl `{TC}/board/download_sram.tcl`: PH1P100, cable0, speed7, server127.0.0.1:5555, download -mode jtag (SRAM),120s owned PID-tree deadline. No server autostart, alternate cable scan or retry. SRAM authorization exists; no repeated permission question. Developer never executes this entry. A rejected manifest cannot satisfy its gate.

GUI: open the exact matching current.cwc above after accepted SRAM load. Capture once after live settling and again >=20s later, retaining each camera-domain and DDR-domain core. Expect cl_identity0x434c0101/algo_identity0x414c0101, distinct cl_seq and increasing pass; cl_flags[31]=1, bits3:0=15/error15:8=0, words648192,len2592768,fault0. Use probe-map full32bit writer/source good/bad/abort/injected, cl_recovery_count, geometry and three algo complete/CRC/reject counters. Third eligible source SOF after2 good source frames has one delayed internal abort; the exact following legal published good tuple must pass full checker and advance recovery. This is internal abort, not physical CSI CRC injection. If two captures miss the transient/geometry, collect additional same-candidate samples. Cross-domain captures are not atomic. Real geometry/PHASE3 placeholder require actual single-A samples. Qualified B01 should proceed to T02 without waiting for T08.

Rollback SRAM pair: `{rollback/'compiled.bit'}` SHA256 `{sha(rollback/'compiled.bit')}`; matching `{rollback/'compiled.cwc'}` SHA256 `{sha(rollback/'compiled.cwc')}`. Preserve failed samples/operator/time; no Flash, PCIe/RK, sensor-register changes or automatic retry. G3/G4 and physical margins remain unmeasured.
'''
(TC/'board-entry.md').write_text(board,encoding='utf-8')
result={'task_ids':manifest['task_ids'],'status':manifest['status'],'manifest_path':str(candidate/'manifest.json'),'manifest_sha256':mh,'artifact_paths':[str(TC/'T06-development-report.md'),str(TC/'T09-development-report.md'),str(TC/'evidence-index.json'),str(TC/'board-entry.md'),str(TC/'attempt-counts.json')],'test_input_paths':[str(candidate/'manifest.json'),str(TC/'evidence-index.json'),str(TC/'manual-engineering-review.md'),str(TC/'reuse-evidence.json')],'lessons_path':str(TC/'lessons-learned.md'),'blocked':False if ready else readj(TC/'problems.json')['problems'],'retest':manifest['retest'],'attempts_path':str(TC/'attempt-counts.json'),'unmeasured':unmeasured,'actual_repair_rounds':0}
writej(TC/'development-result.json',result)
# Last write; activity and all source changes must already have ended.
(candidate/'manifest.json').write_bytes(blob)
assert sha(candidate/'manifest.json')==mh and all(sha(pathlib.Path(e['path']))==e['sha256'] for e in entries)
assert all(sha(pathlib.Path(e['path']))==e['sha256'] for e in readj(B/'inputs.json'))
print(json.dumps({'status':manifest['status'],'manifest_path':str(candidate/'manifest.json'),'manifest_sha256':mh,'entries':len(entries),'production_attempts_used':attempt}))
