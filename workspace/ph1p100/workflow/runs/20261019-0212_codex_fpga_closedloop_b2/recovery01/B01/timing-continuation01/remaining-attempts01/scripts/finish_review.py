import pathlib,json,hashlib,re,sys,shutil
N=pathlib.Path(__file__).resolve().parents[1];O=N.parent;BASE=O.parent;RUN=BASE.parents[1]
ROOT=next(p for p in N.parents if (p/'AGENTS.md').is_file());P=ROOT/'upstream/ph1p100-pcie-ep-fpga';a=int(sys.argv[1]);B=N/'build'/f'attempt{a}';PHY=B/'prj/ph1p_pcie_integration_Runs/phy_1';E=N/'engineering'/f'attempt{a}'
def readj(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def writej(p,o):p.write_text(json.dumps(o,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
e=readj(E/'result.json');x=readj(B/'execution-result.json');assert x['exit']==0 and not x['timed_out'] and e['completion_marker'] and not e['source_drift']
t=(PHY/'ph1p_pcie_integration_pr.timing').read_text(encoding='utf-8');chk=(PHY/'ph1p_pcie_integration_chk.timing').read_text(encoding='utf-8');paths=[]
for m in re.finditer(r'(?ms)^Slack\s+:\s*(-?[\d.]+)ns\s*\nBegin Point\s+:\s*([^\n]+)\nEnd Point\s+:\s*([^\n]+)\nCheck Type\s+:\s*([^\n]+)',t):
    if float(m[1])<0:paths.append({'slack_ns':float(m[1]),'begin':m[2].strip(),'end':m[3].strip(),'check':m[4].strip()})
paths.sort(key=lambda v:v['slack_ns']);writej(E/'critical-paths.json',paths)
old=readj(O/'engineering/attempt4/result.json')
assert sorted((p['name'],p['clock'],p['width']) for p in e['probes'])==sorted((p['name'],p['clock'],p['width']) for p in old['probes'])
totals={}
for p in e['probes']:totals[p['clock']]=totals.get(p['clock'],0)+p['width']
assert sorted(totals.values())==[288,480,512]
def nodes(s,k):
    m=re.search(r'(?ms)^'+str(k)+r'\. checking[^\n]*\n-+\n(.*?)(?=^[0-9]+\. checking|\Z)',s);assert m;return sorted(re.findall(r'^\t([^\n]+)',m[1],re.M))
baseline=ROOT/'workflow/runs/20261018-1631_runA_fpga_side_readchannel/debug-fix3/prj/ph1p_pcie_integration_Runs/phy_1/ph1p_pcie_integration_chk.timing';bs=baseline.read_text(encoding='utf-8')
compare={str(k):{'identical_inherited_node_sets':nodes(chk,k)==nodes(bs,k),'nodes':nodes(chk,k)} for k in [1,2,10,11]};assert all(v['identical_inherited_node_sets'] for v in compare.values())
for title in ['invalid constraint','pll clock constraints','combinational loops','soft fifo timing exception constraints','no path constraints','shadowed/ignored timing exception constraints','partial input delay','partial output delay','abnormal input delay']:
    assert re.search(r'checking '+re.escape(title)+r'\(0\)',chk),title
writej(E/'constraint-boundary-comparison.json',{'baseline':str(baseline),'baseline_sha256':sha(baseline),'final_sha256':sha(PHY/'ph1p_pcie_integration_chk.timing'),'nodes':compare,'dummy_section':re.search(r'(?ms)^3\. checking.*?(?=^4\. checking)',chk)[0],'scope':'Inherited external PHY/status/board boundaries documented individually in cdc-coverage-review.md. No new clock or external port. No whole-chip CDC or serial-electrical qualification claimed.'})
assert (P/'constraints/ph1p_pcie_case_ep_closedloop.sdc').read_bytes()==(P/'constraints/ph1p_pcie_case_ep_dbg.sdc').read_bytes()
coverage=re.search(r'STA coverage\s*:\s*([^\n]+)',t)[1]
synlog=B/'prj/ph1p_pcie_integration_Runs/syn_1/run.log'
syn=synlog.read_text(encoding='utf-8',errors='replace')
inference=[syn[m.start():m.start()+650] for m in re.finditer(r'SYN-5105 WARNING',syn)]
ram_review={'synthesis_log':str(synlog),'synthesis_log_sha256':sha(synlog),'failed_eram_inference_warning_count':len(inference),'warning_excerpts':inference,'actual_total_eram':next(v['used'] for v in e['resources'] if v['name']=='eram'),'previous_total_eram':200,'critical_warning_check_zero':'critical warning check and 0 issue(s)' in syn,'rule':'ram_style requests inference. Report warnings/fallbacks and actual resource use; never assume mapping success. SameDB setup/hold/resources/CWC still required.'}
writej(E/'row-ram-mapping-review.json',ram_review)
body=f'''# Final engineering review — production attempt{a}

Final-review-complete: true
Coverage-boundary-review-complete: true
G2-pass: {str(e['pass']).lower()}
Engineering-result SHA256: {sha(E/'result.json')}

Actual ERAM{ram_review['actual_total_eram']} versus previous200; failed inference warnings{len(inference)}, native critical-warning check zero={ram_review['critical_warning_check_zero']}. Exact synthesized-output-reset compatibility warnings/fallback are row-ram-mapping-review.json. The bram(fast) attribute requested in attempt6 is not proof that every row bank mapped to ERAM. Attempt6 removes asynchronous reset only from read-data registers; state/valid/config/sideband resets and arithmetic remain unchanged. No mapping success is invented; all final timing gates still apply.

Full fresh production attempt{a}, native exit{x['exit']}, elapsed{x['elapsed_seconds']:.3f}s, actual3600s deadline. Same final RoutedDB, both corners, original camera5.332ns/DHI10ns/TL16ns. Metrics{e['metrics']}; STA coverage{coverage}. Global metrics include every timed group and timing exception, not only the worst camera path. Exact negative endpoints{len(paths)} in critical-paths.json. Each new physical candidate rechecks both setup and hold; previous hold PASS is not imported.

All native resource categories within capacity={e['resources_within_capacity']}; real gray/Gaussian/HE retention={e['retention_tokens']}. CWC physical checker exit{e['cwc_check_exit']}; byte-identical paired bit={e['bit_pair_equal']}; build-source drift={e['source_drift']}; actual completion marker={e['completion_marker']}. All40 enabled probes match attempt4 name/clock/width exactly, camera512/DHI480/TL288bits. CWC source clocks{e['probe_clock_domains']}. Per-core snapshots atomic only within the same clock domain.

Source changes/provenance: conservative demosaic enable from registered downstream room; exact3stage gray products/partial/final sum with identically enabled sidebands; independent Gaussian/HE token queues and transfer-gated abort notification. Row-window arithmetic and reference/oracle/vector untouched. Current real DUT G1 covers24scenarios, exact pixel/sideband/LUT, branch hold/abort/config reset, varying adapter, HE/ROI negative controls, RAW overflow/bad-frame/readback recovery, injection, full1080p and continuous2frames. Unchanged11check elaborated source SHA proof supplied in reuse-evidence.json; independent tester must decide reuse. T06writer6/8/controller5/6 retained.

Selected CDC/reset: all added tokens/occupancy/gray stages and both branch queues use the same cameraA clock/reset. Reset clears valid occupancy, so unreset payload cannot emit a token. No new asynchronous tuple crossing, IO, clock, sensor setting or protected IP changes. Detailed inherited boundary discussion in cdc-coverage-review.md. Final PLL-lock/CE2, local-clock4 and73input/87output port node sets exactly equal baseline; invalid constraints/PLL/loops/no-path/shadowed/ignored/partial-delay findings0. Final dummy primitive output names are recorded verbatim in constraint-boundary-comparison.json rather than assumed synthesis-name equality. Native phys_opt/fix_hold are physical optimization, not timing waivers. Original SDC is byte-identical to protected debug SDC; no false path/multicycle/frequency relaxation introduced. External serial electrical/board delay qualification and whole-chip CDC are outside this selected internal timing review and remain unmeasured.

Production cumulative{a}/6, no attempt7. New role window19:10:01–21:40:01 local,150min/150tools, old240min/tool history preserved separately (total authorized390min/300engineeringtools). Independentr0 not started; actual repair0. No hardware download/Flash/PCIe-RK/commit/push. If G2 passes, stop building and freeze for one integrated tester then priorityT02; if it fails, no rejected-bit download. Actual final bit/DB/report hashes are result.json, not an old candidate or another seed.
'''
dst=N/f'manual-engineering-review-attempt{a}.md';assert not dst.exists();dst.write_text(body,encoding='utf-8')
if e['pass'] or a==6:
    shutil.copyfile(dst,N/'manual-engineering-review.md')
    if not e['pass']:
        problems=[{'task_id':task,'problem_id':task+':LIMIT_REACHED:production-g2-timing','reason_code':'LIMIT_REACHED','new_information':True,'evidence_path':str(E/'result.json'),'requested_action':'Original planner review actual final paths; all6production attempts consumed, no7. Preserve failed candidate and route any protected receiver/IP issue or next independent work within user scope.','resume_input_path':str(N/'development-result.json'),'production_attempts_used':a,'production_attempts_max':6,'actual_repair_rounds_used':0,'integrated_round0_occurred':False} for task in ['T06.codex-ddr-readback-int','T09.codex-production-int']]
        writej(N/'problems.json',{'status':'blocked','problems':problems})
print(json.dumps({'attempt':a,'G2_pass':e['pass'],'metrics':e['metrics'],'coverage':coverage,'negative_paths':paths[:12],'probe_totals':totals}))
