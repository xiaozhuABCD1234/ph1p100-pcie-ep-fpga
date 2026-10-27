"""Run only after manual review, all owned activities ended and final G2 passed."""
import pathlib,json,hashlib,shutil,sys,time,subprocess,xml.etree.ElementTree as ET
ROOT=pathlib.Path('C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道');P=ROOT/'upstream/ph1p100-pcie-ep-fpga';REC=pathlib.Path(__file__).resolve().parents[1];RUN=REC.parents[1]
attempt=int(sys.argv[1]);blocked_mode='--blocked' in sys.argv;B=REC/'build'/f'attempt{attempt}';E=REC/'engineering'/f'attempt{attempt}';PHY=B/'prj/ph1p_pcie_integration_Runs/phy_1'
def sha(p):
    h=hashlib.sha256()
    with p.open('rb') as f:
        for data in iter(lambda:f.read(1024*1024),b''):h.update(data)
    return h.hexdigest()
def readj(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def writej(p,obj):p.write_text(json.dumps(obj,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
assert readj(B/'execution-result.json')['exit']==0
eng=readj(E/'result.json');assert (eng['pass'] or blocked_mode) and not eng['source_drift']
assert all(sha(pathlib.Path(e['path']))==e['sha256'] for e in readj(B/'inputs.json')),'final build-source binding drift'
if blocked_mode:assert not eng['pass'] and attempt==3
assert (REC/'manual-engineering-review.md').is_file(),'record final STA/CDC/resource review first'
review=(REC/'manual-engineering-review.md').read_text(encoding='utf-8')
assert 'Final-review-complete: true' in review and sha(E/'result.json') in review,'review must bind this final engineering result'
required=['tb_closedloop_writer_checker','tb_closedloop_control','tb_closedloop_raw_algo','tb_closedloop_injection','tb_cam_algo_oracle','tb_cam_algo_oracle_negative','tb_cam_algo_adapter_big','tb_ep_bar_win_debug','tb_ddr_frame_readback_checker','tb_ddr_frame_pusher_rka1','tb_ddr_wr_arb_peer','tb_ep_bar_win_rka1','tb_csi_checked','tb_t11_csi_enable_corner','tb_csi_integrity_diff','tb_t11_r10f_e2e']
latest={};history=[]
for f in sorted((REC/'g1').glob('*/result.json')):
    r=readj(f);r['result_path']=str(f);history.append(r);latest[r['tb']]=r
for name in required:
    r=latest[name];assert r['exit']==0 and not r['timeout'] and not r['sim_error'] and r['pass_marker'],name
algo={}
for f in sorted((REC/'algo-g1').glob('*/report.json')):
    r=readj(f);r['report_path']=str(f);algo[(r['case'],r['mutation'])]=r
for key in [('core','none'),('core','he_samebin'),('rate','none')]:assert algo[key]['verdict']=='PASS',key
# Explicitly protect the independent offline T08 input set.
protected=readj(REC/'protected-T08.json');assert all(sha(pathlib.Path(e['path']))==e['sha256'] for e in protected['entries'])
assert sha(pathlib.Path(protected['manifest']))==protected['manifest_sha256']
candidate=REC/'candidate';candidate.mkdir(exist_ok=False)
prefix='rejected' if blocked_mode else 'current'
for src,dst in [(PHY/'cw/compiled.bit',prefix+'.bit'),(PHY/'cw/compiled.cwc',prefix+'.cwc'),(PHY/'ph1p_pcie_integration_inst.bid',prefix+'.bid')]:shutil.copyfile(src,candidate/dst)
probes=[]
for node in ET.parse(candidate/(prefix+'.cwc')).getroot().findall('.//watcher_nodes/bus'):
    if node.get('is_enabled')=='yes':probes.append({'name':node.get('name'),'clock':node.get('clock'),'instance':node.get('inst'),'width':len(node.findall('net')),'nets':[n.attrib for n in node.findall('net')]})
writej(candidate/'probe-map.json',{'probes':probes,'snapshot_rule':'Atomic only within one generated clock-domain core; never combine different domains as one atomic sample.','reader_flags':{'31':'sticky completed result present','15:8':'checker error','3':'length_ok','2':'payload_crc_ok','1':'header_crc_ok','0':'magic_ok'},'recovery':'cl_recovery_count increments only after the exact first legal publication following writer rejection passes full readback. Pending older frames do not count.'})
evidence={'latest_g1':latest,'algo_g1':{'/'.join(k):{'report_path':v['report_path'],'verdict':v['verdict'],'coverage':v['coverage']} for k,v in algo.items()},'history':history,'engineering':str(E/'result.json'),'attempt':attempt,'repair_round':0,'unmeasured':['G3 actual camera geometry/Bayer phase/readback/bad-frame recovery (T02)','G4 long stability and optimization','physical CSI CRC injection','algorithm images on board','PCIe/RK/compression/Flash/dual-camera exposure']}
writej(REC/'evidence-index.json',evidence)
# Freeze actual production dependencies; T08 is observed/protected, never compiled here.
files=set()
for e in readj(B/'inputs.json'):
    p=pathlib.Path(e['path']).resolve()
    assert p.is_relative_to(ROOT.resolve())
    if 'sync_offline' in p.parts:continue
    if p.parent==P/'tools/pcie_integration/td' and p.name!='00_all_closedloop.tcl':continue
    if p.parent==P/'constraints' and p.name not in {'ph1p_pcie_case_ep.adc','ph1p_pcie_case_ep_closedloop.sdc','ph1p_pcie_case_ep_dbg.sdc'}:continue
    files.add(p)
for base in [P/'rtl',P/'al_ip',P/'sim']:
    for p in base.rglob('*'):
        if p.is_file() and p.suffix.lower() in {'.v','.sv','.vh','.f','.mem','.hex','.mif','.coe','.xml'} and 'sync_offline' not in p.parts and p.name!='tb_sync_offline.sv':files.add(p.resolve())
for p in (REC/'scripts').glob('*.py'):files.add(p.resolve())
for p in (REC/'vectors').glob('*'):
    if p.is_file():files.add(p.resolve())
for p in (REC/'board').glob('*.tcl'):files.add(p.resolve())
for p in candidate.glob('*'):files.add(p.resolve())
for p in E.rglob('*'):
    if p.is_file():files.add(p.resolve())
for p in [B/'inputs.json',B/'execution-result.json',B/'deadline.log',PHY/'run.log',B/'prj/td_00_all_closedloop.log',PHY/'ph1p_pcie_integration_pr.db',PHY/'ph1p_pcie_integration_pr.timing',PHY/'ph1p_pcie_integration_phy.area',PHY/'ph1p_pcie_integration_chk.timing',PHY/'ph1p_pcie_integration_exception.timing',PHY/'route_clock_utilization.txt',PHY/'cw/compiled.bit',PHY/'cw/compiled.cwc',PHY/'ph1p_pcie_integration_inst.bid',P/'tools/pcie_integration/run_td.ps1',P/'tools/pcie_integration/run_sim.ps1',ROOT/'tools/td/check_chipwatcher_readback.py',ROOT/'tools/algo/oracle_algo.py',ROOT/'AGENTS.md']:
    assert p.is_file(),p
    files.add(p.resolve())
if attempt==3:
    for p in [PHY/'finish.tcl',REC/'build/attempt2/inputs.json',REC/'build/attempt2/execution-result.json',REC/'build/attempt2/deadline.log',pathlib.Path(readj(B/'execution-result.json')['source_checkpoint'])]:
        assert p.is_file(),p
        files.add(p.resolve())
planning_inputs=[]
control=candidate/'planning-inputs';control.mkdir(exist_ok=False)
for name in ['request.md','request-followup-01.md','request-followup-02.md','request-followup-03.md','dispatch.json','dispatch-supplement-board-priority.json','board-priority-supplement.md','recovery01-plan.md','problem-ledger-recovery01.json','dev-plan.md','fpga-design-guide.md','input-index.md']:
    src=(RUN/name).resolve();dst=control/name;shutil.copyfile(src,dst);files.add(dst.resolve())
    planning_inputs.append({'original_path':str(src),'frozen_copy':str(dst.resolve()),'sha256':sha(dst)})
for p in REC.glob('*'):
    if p.is_file() and p.suffix in {'.md','.json'}:files.add(p.resolve())
for r in latest.values():
    d=pathlib.Path(r['result_path']).parent
    for name in ['result.json','inputs.json','deadline.log','vlog.log','vsim.log']:
        if (d/name).is_file():files.add((d/name).resolve())
for r in algo.values():
    d=pathlib.Path(r['report_path']).parent
    for p in d.iterdir():
        if p.is_file() and p.suffix in {'.v','.sv','.vec','.hex','.json','.log','.do'}:files.add(p.resolve())
toolpaths=['C:/Program Files/Python311/python.exe','D:/anlogic/TD_Release_2026.2/bin/td_commands_prompt.exe','D:/anlogic/TD_Release_2026.2/bin/run.exe','D:/anlogic/TD_Release_2026.2/bin/bw.exe','D:/intelFPGA/18.1/modelsim_ase/win32aloem/vlib.exe','D:/intelFPGA/18.1/modelsim_ase/win32aloem/vlog.exe','D:/intelFPGA/18.1/modelsim_ase/win32aloem/vsim.exe']
for name in toolpaths:
    p=pathlib.Path(name);assert p.is_file(),p;files.add(p.resolve())
entries=[{'path':str(p),'size':p.stat().st_size,'sha256':sha(p)} for p in sorted(files,key=str)]
manifest={'schema':'fpga-batch-candidate-v2','run_id':RUN.name,'task_ids':['T06.codex-ddr-readback-int','T09.codex-production-int'],'batch_id':'B01','recovery_phase':'recovery01','round':0,'frozen':True,'ready_for_test':True,'independent_acceptance':'pending','production_attempt':attempt,'top':'ph1p_pcie_ep_top_closedloop','device':'PH1P100SBG484 speed3','source_head':subprocess.check_output(['git','-C',str(P),'rev-parse','HEAD'],text=True,timeout=10).strip(),'parameters':{'CLOSEDLOOP_EN':1,'DBG_CTRL_DEFAULT_EN':1,'ROI':[960,540,1920,1080],'SKIP_ROWS':37,'PHASE':3,'FIFO_AW':10,'cam_period_ns':5.332,'DHI_MHz':100},'entries':entries,'historical_manifest':{'path':str(RUN/'candidate/manifest.json'),'sha256':sha(RUN/'candidate/manifest.json')},'retest_impact':{'T06':'controller publication recovery tags/result flag and full writer-checker assertion changed; full1080p, ownership/drain/control and RAW-algo recovery rerun','T09':'shared RGB/sideband register cuts actual placed critical path; core24 scenarios, HE negative, varying adapter oracle, stalls/overflow/bad recovery and continuous1080p two-frame service rerun','baseline':'no baseline data-path changes in recovery; baseline suite remains bound to unchanged modules','T08':'uncompiled and protected; all26 hashes unchanged'},'not_run':evidence['unmeasured'],'derived_after_hash':['board-entry.md','development-result.json']}
manifest['planning_inputs']=planning_inputs
manifest['tool_versions']={'Python':sys.version,'TD':'Tang Dynasty Release_2026.2 (same final timing report and native engine hash)','ModelSim':'10.5b (actual frozen vsim logs, IntelFPGA18.1 distribution)'}
if blocked_mode:manifest.update({'ready_for_test':False,'status':'blocked','independent_acceptance':'not_started_G2_failed','G2_pass':False,'problem_paths':[str(REC/'problems.json')],'production_attempts_used':3,'production_attempts_max':3})
blob=(json.dumps(manifest,indent=2,ensure_ascii=False)+'\n').encode('utf-8');mh=hashlib.sha256(blob).hexdigest()
rollback=ROOT/'workflow/runs/20261018-1631_runA_fpga_side_readchannel/debug-fix3/prj/ph1p_pcie_integration_Runs/phy_1/cw'
assert (rollback/'compiled.bit').is_file() and (rollback/'compiled.cwc').is_file()
artifactlines='\n'.join(f"- `{e['path']}` SHA256 `{e['sha256']}`" for e in entries if e['path'] in [str((candidate/n).resolve()) for n in [prefix+'.bit',prefix+'.cwc',prefix+'.bid','probe-map.json']] or e['path'] in [str((PHY/'ph1p_pcie_integration_pr.db').resolve()),str((PHY/'ph1p_pcie_integration_pr.timing').resolve())])
board=f'''# B01 unique board entry — offline developer has not downloaded

Use only after both B01 round0 integrated reports PASS this manifest `{mh}`. The separately dispatched T02 owns board execution. SRAM authorization already exists; this file requests no new authorization.

{artifactlines}

Exact SRAM entry (auto-resolves the one integrated PASS report per task_id/manifest; explicit --report can resolve a documented naming ambiguity):

```powershell
& 'C:/Program Files/Python311/python.exe' '{REC}/scripts/run_sram.py' --execute
```

The reviewed native Tcl `{REC}/board/download_sram.tcl` requires PH1P100, cable0/speed7, `download -mode jtag` SRAM, current.bit above, server127.0.0.1:5555. The wrapper validates all frozen hashes, distinct per-task integrated PASS reports and 120s owned PID-tree timeout. Execution logs go to `{RUN}/board/sram-b01-<timestamp>`, outside frozen candidate inputs. It does not start a server, probe alternative cables or retry download. Missing cable/server/GUI is a concrete T02 dependency, not a B01 PASS claim.

GUI: open current.cwc above with the matching current.bit. Trigger one capture after live settling and a second capture at least20s later; each capture must contain the DDR-domain core and camera-domain core. Expected: cl_identity=0x434c0101, algo_identity=0x414c0101, at least two different cl_seq; cl_flags[31]=1, flags[3:0]=15/error[15:8]=0, cl_words=648192, len=2592768, cl_fault=0, read-pass increasing. Inspect full32bit writer good/bad, cl_recovery_count, source geometry/good/abort/injected counters and three algorithm completed/CRC/rejected counters using probe-map.json. The third eligible source SOF after two good source frames causes one delayed internal abort; the exact following good published frame must pass readback and raise recovery. Label this internal abort, never physical CSI CRC injection. Two clicks are a preferred collection layout, not guaranteed sufficient proof; retain additional same-candidate captures if transitions/geometry are missing. Cross-domain cores are not atomic together. Actual source geometry and Bayer phase remain unmeasured; derive ROI/phase validity from the real samples rather than current placeholder PHASE3.

Rollback same SRAM tool/cable procedure to `{rollback}/compiled.bit` SHA256 `{sha(rollback/'compiled.bit')}` and matching `{rollback}/compiled.cwc` SHA256 `{sha(rollback/'compiled.cwc')}`. Preserve failed candidate/captures and record operator/time. No Flash, host PCIe/RK, sensor-register change or automatic retry.
'''
if blocked_mode:board=f'''# B01 board entry — BLOCKED, no eligible SRAM candidate
Manifest `{mh}` is frozen with ready_for_test=false. Final routed STA={eng['metrics']}, production attempts3/3 used. Native CWC mapping0fail/bit pair equality/resources/source binding do not override setup/hold failure. No download or GUI capture was executed. No independent round0 has started.

The unqualified native artifacts are preserved only for review:
{artifactlines}

`scripts/run_sram.py` and `board/download_sram.tcl` are prepared guarded SRAM-only entry sources; this rejected manifest cannot satisfy their gate. There is no current.bit/current.cwc eligible for board entry. Original planner must receive new allowed execution conditions and qualify a new source/DB/manifest before scheduling T02. Do not wait for T08 to resolve a future qualified B01 board window.

Rollback remains `{rollback}/compiled.bit` SHA256 `{sha(rollback/'compiled.bit')}` with matching `{rollback}/compiled.cwc` SHA256 `{sha(rollback/'compiled.cwc')}`. No Flash/PCIe/RK operation is authorized here.
'''
(REC/'board-entry.md').write_text(board,encoding='utf-8')
result={'task_ids':manifest['task_ids'],'status':'ready_for_test','dimension':'development','manifest_path':str(candidate/'manifest.json'),'manifest_sha256':mh,'artifact_paths':[str(REC/'T06-development-report.md'),str(REC/'T09-development-report.md'),str(REC/'evidence-index.json'),str(REC/'board-entry.md'),str(REC/'attempt-ledger.md')],'test_input_paths':[str(candidate/'manifest.json'),str(REC/'evidence-index.json'),str(REC/'manual-engineering-review.md'),str(REC/'attempt-ledger.md'),str(REC/'board-entry.md')],'lessons_path':str(REC/'lessons-learned.md'),'blocked':False,'retest':manifest['retest_impact'],'unmeasured':manifest['not_run'],'repair_round':0}
if blocked_mode:result.update({'status':'blocked','blocked':True,'ready_for_test':False,'problems':readj(REC/'problems.json')['problems'],'attempts_path':str(REC/'attempt-counts-verified.json')})
writej(REC/'development-result.json',result)
# Manifest is the final write. No input/evidence modifications after this point.
(candidate/'manifest.json').write_bytes(blob)
assert sha(candidate/'manifest.json')==mh and all(sha(pathlib.Path(e['path']))==e['sha256'] for e in entries)
assert all(sha(pathlib.Path(e['path']))==e['sha256'] for e in readj(B/'inputs.json'))
print(json.dumps({'status':'blocked' if blocked_mode else 'ready_for_test','manifest_path':str(candidate/'manifest.json'),'manifest_sha256':mh,'entries':len(entries),'production_attempt':attempt},indent=2))
