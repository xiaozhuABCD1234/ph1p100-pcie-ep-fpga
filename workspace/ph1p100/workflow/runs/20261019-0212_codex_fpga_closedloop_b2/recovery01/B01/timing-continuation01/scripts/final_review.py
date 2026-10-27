import pathlib,json,hashlib,re,time
TC=pathlib.Path(__file__).resolve().parents[1];OLD=TC.parent;RUN=OLD.parents[1]
ROOT=next(p for p in TC.parents if (p/'AGENTS.md').is_file());P=ROOT/'upstream/ph1p100-pcie-ep-fpga';PHY=TC/'build/attempt4/prj/ph1p_pcie_integration_Runs/phy_1';E=TC/'engineering/attempt4'
def readj(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def writej(p,o):p.write_text(json.dumps(o,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
eng=readj(E/'result.json');assert eng['completion_marker'] and not eng['pass'] and eng['source_drift']==[] and eng['cwc_check_exit']==0
t=(PHY/'ph1p_pcie_integration_pr.timing').read_text(encoding='utf-8');paths=[]
for m in re.finditer(r'(?ms)^Slack\s+:\s*(-?[\d.]+)ns\s*\nBegin Point\s+:\s*([^\n]+)\nEnd Point\s+:\s*([^\n]+)\nCheck Type\s+:\s*([^\n]+)',t):
    if float(m[1])<0:paths.append({'slack_ns':float(m[1]),'begin':m[2].strip(),'end':m[3].strip(),'check':m[4].strip()})
paths.sort(key=lambda x:x['slack_ns']);writej(E/'critical-paths.json',paths);assert paths and all(p['check']=='setup' for p in paths)
chk=(PHY/'ph1p_pcie_integration_chk.timing').read_text(encoding='utf-8')
def nodes(s,k):
    m=re.search(r'(?ms)^'+str(k)+r'\. checking[^\n]*\n-+\n(.*?)(?=^[0-9]+\. checking|\Z)',s);assert m;return sorted(re.findall(r'^\t([^\n]+)',m[1],re.M))
base=ROOT/'workflow/runs/20261018-1631_runA_fpga_side_readchannel/debug-fix3/prj/ph1p_pcie_integration_Runs/phy_1/ph1p_pcie_integration_chk.timing';bs=base.read_text(encoding='utf-8')
compare={str(k):{'node_sets_identical_to_baseline':nodes(chk,k)==nodes(bs,k),'final_nodes':nodes(chk,k)} for k in [1,2,10,11]};assert all(v['node_sets_identical_to_baseline'] for v in compare.values())
writej(E/'constraint-boundary-comparison.json',{'baseline':str(base),'baseline_sha256':sha(base),'final_sha256':sha(PHY/'ph1p_pcie_integration_chk.timing'),'sections':compare,'dummy_final_section':re.search(r'(?ms)^3\. checking.*?(?=^4\. checking)',chk)[0],'review_note':'Inherited same node sets do not by themselves waive warnings. Selected source boundaries in cdc-coverage-review.md; generated unused slice output names recorded verbatim. Final STA is FAIL, no coverage signoff claimed.'})
assert (P/'constraints/ph1p_pcie_case_ep_closedloop.sdc').read_bytes()==(P/'constraints/ph1p_pcie_case_ep_dbg.sdc').read_bytes()
review=f'''# Final engineering review — attempt4 remains rejected

Final-review-complete: true
Coverage-boundary-review-complete: true
G2-pass: false
Engineering-result SHA256: {sha(E/'result.json')}

Full fresh synthesis/place/route executed once on the new elastic boundary; explicit fix_hold began/ended and the native B01_CLOSEDLOOP_ALL_DONE marker is present. The stage log is UTF16; the first helper read it as UTF8 and falsely marked completion=false. That parser-only result is retained in result-parser-first.json; decoding BOM correctly confirms actual completion. No production rerun was hidden in this correction. CWC physical check was rerun after the parser correction, both exit0; this is not another native production session.

Actual attempt4 exit0,1985.058954s under original3600s deadline. Final Routed/both corners, STA coverage97.68%, original187.547MHz camera constraint retained. SWNS=-0.645/STNS=-35.220ns; HWNS=+0.020/HTNS=0ns. Explicit native hold repair removed the old DDR/TL/camera hold failures. CameraA setup=-0.645/TNS-35.129; cameraB=-0.091/TNS-0.091. Hold success cannot override setup failure. Every negative reported endpoint is preserved in critical-paths.json, first={paths[0]}. Original HE->front ready path is cut structurally by registered occupancy; the final report shows remaining paths, rather than assuming full setup closure.

Resources all within actual device capacity: LUT28368/71680, registers40199/143360, ERAM200/300, DSP14/220. All real gray/Gaussian/HE retention tokens true. Native CWC checker0failure, paired bit identical, three source-clock cores {eng['probe_clock_domains']}, source drift0. DB/report/BID/bit/CWC hashes in result.json are the same final candidate.

Selected CDC/reset review is cdc-coverage-review.md; FIFO is entirely cameraA same-clock/reset. Native no-clock PLL.lock/CE2, local-clock4,73 input/87 output port sets exactly equal proven baseline sets; invalid constraints/PLL-frequency/combinational-loop/no-path/shadowed/ignored/partial-delay findings remain0. Final dangling HR_PAD controls are inherited20pins; LSLICE dangling outputs are _al_n1_syn_4273.ofa and u_top/u_csi_a/u_word_align/r_aligned_word[0]_syn_6.ofb, preserved verbatim. Protected PHY/SDC/ADC/clock not modified. This bounded inherited-interface review does not claim serial electrical timing, whole-chip CDC or external pin-delay qualification; G3/T02 remains unmeasured. No blanket waiver/false path/multicycle/frequency relaxation was added.

Quota resume audit confirms original session13307 collected and ended, knownPID67780 absent, no owned process killed/restarted, only preexisting R mapping remains. Production4/6, attempts5/6 unused; G1 latest affected checks pass, historical writer6/8/controller5/6/core4/6 preserved. Original role start15:05:51/240min wall deadline19:05:51 retained conservatively across unknown quota wait, rather than guessing zero elapsed. Remaining role window is insufficient for another ~33minute full implementation. Return original planner with real setup failures and remaining production numbers, no automatic budget expansion. Independent integratedr0 not started, actual repair0. Rejected bit must not be downloaded.
'''
(TC/'manual-engineering-review.md').write_text(review,encoding='utf-8')
problems=[]
for task in ['T06.codex-ddr-readback-int','T09.codex-production-int']:
    problems.append({'task_id':task,'problem_id':task+':LIMIT_REACHED:production-g2-timing','reason_code':'LIMIT_REACHED','new_information':True,'evidence_path':str(E/'result.json'),'requested_action':'Original planner review attempt4 remaining cameraA/B setup paths and quota-resume01 audit. Production4/6, numbers5/6 unused; original conservatively retained role deadline leaves insufficient time for another measured33minute full build. No user GUI action fixes this failure; no rejected-bit download. Continuation requires a concrete original-role time-budget decision and permitted path correction without relaxing gates.','resume_input_path':str(TC/'development-result.json'),'production_attempts_used':4,'production_attempts_max':6,'actual_repair_rounds_used':0,'integrated_round0_occurred':False,'supplement_opportunities_used':0,'metrics':eng['metrics'],'audit_path':str(TC/'quota-resume01/attempt-reconciliation.json'),'critical_paths':str(E/'critical-paths.json')})
writej(TC/'problems.json',{'status':'blocked','batch_id':'B01','problems':problems,'not_production_exhaustion':'4/6 used; remaining role window insufficient; no new attempt started','quota_problem_id':'B01:QUOTA:provider-usage-limit','quota_resume':'native calls succeeded; no second provider error observed; future quota availability not inferred'})
print(json.dumps({'first_negative':paths[0],'negative_reported_paths':len(paths),'cameraB_examples':[p for p in paths if 'cam_b_byte_clk' in p['end']][:2],'review_sha256':sha(TC/'manual-engineering-review.md')}))
