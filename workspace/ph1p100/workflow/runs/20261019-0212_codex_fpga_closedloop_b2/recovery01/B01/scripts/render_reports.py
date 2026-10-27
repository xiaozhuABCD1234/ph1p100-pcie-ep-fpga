import pathlib,json,hashlib,sys,subprocess
ROOT=pathlib.Path('C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道');P=ROOT/'upstream/ph1p100-pcie-ep-fpga';REC=pathlib.Path(__file__).resolve().parents[1];RUN=REC.parents[1];attempt=int(sys.argv[1])
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def readj(p):return json.loads(p.read_text(encoding='utf-8-sig'))
eng=readj(REC/'engineering'/f'attempt{attempt}'/'result.json');blocked=not eng['pass']
latest={}
for p in sorted((REC/'g1').glob('*/result.json')):
    r=readj(p);r['result_path']=str(p);latest[r['tb']]=r
algo=[]
for p in sorted((REC/'algo-g1').glob('*/report.json')):
    r=readj(p);r['report_path']=str(p);algo.append(r)
provenance=[]
for p in sorted((P/'rtl/ep_side/img/algo').glob('*.v')):
    src=ROOT/'fpga/csi2/src/img'/p.name
    row={'production':str(p),'sha256':sha(p),'original':str(src) if src.is_file() else None,'original_sha256':sha(src) if src.is_file() else None}
    row['relation']='new camera integration/diagnostic module' if not src.is_file() else ('byte-identical approved source' if sha(src)==sha(p) else 'one shared RGB/sideband register before gray DSP; arithmetic unchanged; see before-gray-boundary and critical placed timing')
    if src.is_file() and sha(src)!=sha(p):assert p.name=='img_algo_parallel_top.v'
    provenance.append(row)
(REC/'source-provenance.json').write_text(json.dumps(provenance,indent=2),encoding='utf-8')
pre=readj(REC/'prechange-index.json');changes=[]
for e in pre['entries']:
    p=pathlib.Path(e['path'])
    if sha(p)!=e['sha256']:changes.append({'path':str(p),'old_sha256':e['sha256'],'new_sha256':sha(p),'backup':e['backup']})
protected_names=['ep_bar_win.v','pcie_ep_engine.v','tb_ep_bar_win_debug.v']
assert not any(pathlib.Path(e['path']).name in protected_names for e in changes)
assert sha(P/'constraints/ph1p_pcie_case_ep_closedloop.sdc')==sha(P/'constraints/ph1p_pcie_case_ep_dbg.sdc')
status=subprocess.check_output(['git','-C',str(P),'status','--short'],text=True,timeout=30)
(REC/'source-review.json').write_text(json.dumps({'head':subprocess.check_output(['git','-C',str(P),'rev-parse','HEAD'],text=True,timeout=10).strip(),'status':status,'historical_manifest_changes':changes,'baseline_three_dirty_preserved':True,'constraint_equal_to_protected_debug':True},indent=2),encoding='utf-8')
def tests(names):return '\n'.join(f"- {name}: `{latest[name]['result_path']}` (exit={latest[name]['exit']}, pass_marker={latest[name]['pass_marker']}, timeout={latest[name]['timeout']}, simulator_error={latest[name]['sim_error']})." for name in names)
outcome='BLOCKED: final G2 setup/hold fail and production attempts3/3 exhausted; not ready_for_test, no independent round0 or board download' if blocked else 'G0/G1/G2 developer checks qualify submission; independent integrated round0 remains pending'
common=f'''Production final attempt{attempt}: `{REC}/engineering/attempt{attempt}/result.json`. Same routed DB, bit/CWC/BID pair, resource report and tool hashes are frozen in the one candidate/manifest.json. STA={eng['metrics']}; every resource within device capacity; three actual watcher clock domains. CWC physical map verification exit={eng['cwc_check_exit']}; paired bit equal={eng['bit_pair_equal']}; input drift={eng['source_drift']}. Static CDC review is bound in manual-engineering-review.md. Outcome: {outcome}.

Historical manifest236 SHA2b328fc0a23ecae57e8d95c6ca66e2c9726cc95b9d536edd673380bcacffeabe remains untouched as history. All old inputs were copied with original SHA before edits. Legal recovery deltas and baseline dirty preservation are in source-review.json; T08's26 frozen inputs remain unmodified/uncompiled. No commit, push, download, Flash, sensor-table modification, PCIe/RK or external output occurred.
'''
text=f'''# T06 development evidence — recovery01/B01, before independent round0

The debug-only production wrapper enables the real RAW writer -> DDR -> checker path with two held A slots. Publication is coherent only after writer good/FE and all B responses. The diagnostic reader owns the complete static AR/R port; the legacy pusher is disabled in this configuration, and CLOSEDLOOP_EN=0 retains its original path. AR is held stable in a skid through timeout/abort, every accepted response is drained before release; a permanently missing response locks with ownership retained until DDR reset.

The full1080p actual writer/model/checker run has words648192, header56BA381A, payloadAC1B6FE1, flags8000000F/error0, pass1/fail0. Twenty directed control cases cover RID/RRESP/RLAST, magic/CRCs/length, abort/timeout/drain, reset, queued metadata, held slot pressure and missing-response lock. Real RAW+algorithm integration covers bad/abort rejection and later good recovery; cl_recovery_count counts only a tagged post-rejection publication that then passes full readback (two verified recoveries). cl_flags[31] is sticky completed-snapshot presence, low4bits four OK flags and bits15:8 error. The same-domain source tuple/current counters are full32bit.

{tests(['tb_closedloop_writer_checker','tb_closedloop_control','tb_closedloop_raw_algo','tb_closedloop_injection','tb_ddr_frame_readback_checker','tb_ddr_frame_pusher_rka1','tb_ddr_wr_arb_peer','tb_ep_bar_win_debug','tb_ep_bar_win_rka1','tb_csi_checked','tb_t11_csi_enable_corner','tb_csi_integrity_diff','tb_t11_r10f_e2e'])}

{common}
{outcome}. This is not independent acceptance. G3 is not run here: after a qualified candidate exists, T02 must obtain actual camera geometry/phase, >=2 distinct full-readback sequences and actual bad-to-good recovery. Internal debug abort is not a physical CSI CRC fault. G4 long stability/optimization remains deferred.
'''
(REC/'T06-development-report.md').write_text(text,encoding='utf-8')
ar='\n'.join(f"- {r['case']}/{r['mutation']}: `{r['report_path']}`, verdict={r['verdict']}, coverage={r['coverage']}." for r in algo)
text=f'''# T09 development evidence — recovery01/B01, before independent round0

The approved demosaic/gray/Gaussian/HE source modules feed the production real camera stream and retained diagnostic sinks. All three algorithms run in parallel on one4px stream; ROI adapter and finite FIFO do not return ready to CSI/RAW. A long stall/overflow/busy/abort rejects this algorithm frame and never marks partial output complete. Full source FE/good gates the final ROI beat. No algorithm DDR output or RK reception is claimed.

Source derivation is explicit in source-provenance.json. Arithmetic modules retain their approved bytes; only img_algo_parallel_top adds one common enabled RGB/data/sideband register before four gray units, because attempt1's actual placed path from demosaic row arithmetic to gray DSP had -0.113ns slack. No arithmetic, output sequence, timing constraint or clock frequency was reduced. All lanes/markers use the same gray enable; hold/abort and sidebands were retested. The original tiny core-test stalls no longer overlapped output after this added latency; its staged TB extends each stall by64cycles, preserving all oracle/stability checks. The first coverage failure and successful corrected stimulus are retained.

{tests(['tb_cam_algo_oracle','tb_cam_algo_oracle_negative','tb_cam_algo_adapter_big','tb_closedloop_raw_algo','tb_closedloop_injection'])}

{ar}

The current pipeline passes independent varying adapter oracle patterns, sidebands/held output, a shifted-ROI negative, original core24scenarios and same-bin HE negative, plus near-continuous two-frame1080p service. The actual camera adapter also completes two1080p frames on all three branches. RAW+algorithm stress has raw_good4/raw_bad2/read_pass4/algorithm_complete2 each, FIFO overflow1 and two verified RAW recoveries; overflow does not corrupt RAW. Source-declared Bayer phase3/ROI remain board assumptions pending physical geometry evidence, not verified image quality. The service evidence is single-A30fps budget at187.547MHz, not measured board throughput or a dual-camera claim.

{common}
{outcome}. G3 algorithm image quality and physical phase are unmeasured. G4 long stability/performance optimization remains deferred. Current board-entry.md records eligibility; T08 is not a prerequisite for a future qualified B01 candidate.
'''
(REC/'T09-development-report.md').write_text(text,encoding='utf-8')
ledger=(REC/'attempt-ledger.md').read_text(encoding='utf-8')
ledger+='''
## Recovery continuation accounting

- Original full writer/checker: cumulative attempt5 completed all data/CRC checks but old flags==15 assertion rejected new sticky completed bit; corrected expected8000000F, cumulative attempt6 PASS. Authorized cumulative max8; no blind retry.
- Controller20cases total5 attempts, latest PASS. RAW+algorithm total2 PASS runs; varying adapter oracle total3 (latestPASS), ROI negative total2 valid rejections, top one-shot total3 (latestPASS). Adapter full1080p two-frame current-pipeline service PASS.
- Current-pipeline core first attempt failed only missing actual output-hold coverage; no numerical/LUT mismatch. Staged test-only stalls+64cycles gave hold64/stalls220 and PASS. Same-bin HE mutation rejected with named branch2 data mismatches. Current-pipeline rate two-frame service PASS. No original protected test/vector was edited.
- TD attempt1 reached routed checkpoint but hit1800s hard deadline before final reports/bit/CWC; taskkill log confirms only owned26456/46816/66988 terminated. No survivor remained. Owned S/T mappings were verified and removed; unrelated R was preserved. Attempt2 changes include the required recovery probe and actual placed critical-path register; source remains fixed during each build. Later build outcomes are in build/attempt*/execution-result.json and final engineering result.
- Actual integrated repair round=0, supplementary opportunity=0. G3/G4 remain unmeasured. All commands retain actual deadlines; output yields are not counted as timeouts.
'''
(REC/'attempt-ledger.md').write_text(ledger,encoding='utf-8')
if blocked:
    with (REC/'attempt-ledger.md').open('a',encoding='utf-8') as f:f.write('\nFinal actual TD accounting: attempt1 timeout1800.77s; attempt2 timeout1800.68s; attempt3 completed the exact attempt2 routed checkpoint, native exit0 but final G2 FAIL. Cumulative3/3 production attempts used. No fourth command, no actual integrated repair round and no download.\n')
lessons=(REC/'lessons-learned.md').read_text(encoding='utf-8')
lessons+='''
8. Freeze required recovery and completed-result probes before the first physical attempt; derive recovery from the exact post-rejection publication and full checker completion, not an old queued good frame.
9. When registering a production algorithm boundary, carry every data lane and SOF/EOL/EOF/abort with one enable. Retest numerics and handshake coverage; a latency change can make a short directed stall miss all outputs, so strengthen the stimulus rather than remove the hold assertion.
10. Whole-flow TD runtime includes synthesis and route/bit postprocessing. Preserve checkpoints and actual timeout evidence; a timed-out build is not G2 PASS. Verify owned children and temporary mappings after termination.
'''
(REC/'lessons-learned.md').write_text(lessons,encoding='utf-8')
print('Reports, source provenance/review and actual attempt ledger written before final manifest.')
