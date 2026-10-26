import pathlib,json,hashlib,re,subprocess,sys,ctypes,ast
ROOT=pathlib.Path('C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道');REC=pathlib.Path(__file__).resolve().parents[1];RUN=REC.parents[1];PHY=REC/'build/attempt3/prj/ph1p_pcie_integration_Runs/phy_1';E=REC/'engineering/attempt3'
assert not (REC/'candidate/manifest.json').exists()
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
eng=json.loads((E/'result.json').read_text(encoding='utf-8'));assert not eng['pass'] and eng['routed'] and eng['source_drift']==[]
assert len(list((REC/'build').glob('*/execution-result.json')))==3
text=(PHY/'ph1p_pcie_integration_pr.timing').read_text(encoding='utf-8',errors='replace')
paths=[]
for m in re.finditer(r'(?ms)^Slack\s+:\s*(-?[\d.]+)ns\s*\nBegin Point\s+:\s*([^\n]+)\nEnd Point\s+:\s*([^\n]+)\nCheck Type\s+:\s*([^\n]+)',text):
    if float(m[1])<0:paths.append({'slack_ns':float(m[1]),'begin':m[2].strip(),'end':m[3].strip(),'check':m[4].strip()})
paths.sort(key=lambda x:x['slack_ns']);(E/'critical-paths.json').write_text(json.dumps(paths,indent=2),encoding='utf-8')
problem=[]
for task in ['T06.codex-ddr-readback-int','T09.codex-production-int']:
    problem.append({'task_id':task,'problem_id':task+':LIMIT_REACHED:production-g2-timing','reason_code':'LIMIT_REACHED','new_information':True,'evidence_path':str(E/'result.json'),'requested_action':'Return to original planner for conditions/new explicit bounded dispatch after reviewing actual routed setup/hold paths. Current production-attempt budget3/3 is exhausted; no automatic fourth build or download. Technical continuation stays within original B01 scope and must preserve all timing thresholds.','resume_input_path':str(REC/'development-result.json'),'developer_id':'/root/fpga_dev_closedloop_b01','planner_id':'/root/fpga_planner_b2','actual_repair_rounds_used':0,'integrated_round0_occurred':False,'supplement_opportunities_used':0,'production_attempts_used':3,'production_attempts_max':3,'metrics':eng['metrics'],'critical_paths':str(E/'critical-paths.json')})
obj={'status':'blocked','batch_id':'B01','recovery_phase':'recovery01','problems':problem,'resolved_historical_problem':{'problem_id':'T06.codex-ddr-readback-int:LIMIT_REACHED:integrated-tb-compile','status':'resolved_G1','historical_attempts':2,'additional_used':4,'cumulative_used':6,'cumulative_max':8},'distinction':'New physical G2 setup/hold failure after all required G1 recovered; not the old compilation limit.'}
(REC/'problems.json').write_text(json.dumps(obj,indent=2,ensure_ascii=False),encoding='utf-8')
review=f'''# Final engineering review — failed routed candidate

Final-review-complete: true
G2-pass: false
Engineering-result SHA256: {sha(E/'result.json')}

Actual attempt3 imported attempt2's unchanged routed checkpoint SHA f36c1811bf0773223490ea315b829e1b007e177d1b802a436deca4c0031aaf0b, completed the native post-route stage, exported DB/report/bit/BID and ran setup_debugger -prj. Native command exit0 means completion, not timing acceptance.

Final confidence Routed, both corners, original187.547MHz camera clock retained. SWNS=-0.766ns/STNS=-38.113ns/HWNS=-0.075ns/HTNS=-1.242ns; camera setup and DDR/camera/TL hold fail. All resource categories within device capacity (lut28259/71680, reg39950/143360, ERAM200/300, DSP14/220). Real gray/Gaussian/HE retained in final area; CRC diagnostic outputs are not disconnected. CWC coverage check0fail, native bit identical to cw/compiled.bit, no source drift. Native clocks are {eng['probe_clock_domains']}; probes retain512/480/288 bits in three domains. Cross-domain samples remain non-atomic.

STA coverage97.71%. Native check_timing shows no invalid constraints/combinational loops/no-path exceptions, but retains PLL-lock/TL-CE root-clock findings, local-clock/dummy-pad and no-I/O-delay findings. Their raw report is frozen; no new waiver or coverage PASS is claimed. Closedloop SDC remains byte-identical to the protected debug SDC. New controls/probes remain same-domain as cdc-review.md, but that static analysis does not override final timing failure.

Exact negative setup/hold endpoints are critical-paths.json. The placed residual path was gray m_valid -> demosaic row-buffer enable; a future correction should evaluate a genuinely elastic RGB/sideband boundary and native hold-fix, then rerun affected numerical/abort/stall/service tests and final physical checks. No such extra RTL correction or fourth TD run was performed under the exhausted budget.

Independent integrated round0 and G3 have not started. The produced bit/CWC is archived as rejected, not eligible for SRAM entry. User presence creates no missing developer GUI action; the blocker is actual G2 and exhausted production attempts.
'''
(REC/'manual-engineering-review.md').write_text(review,encoding='utf-8')
cdc=(REC/'cdc-review.md').read_text(encoding='utf-8').replace('final database binding pending','bound to failed routed attempt3')
cdc+='\nFinal attempt3 confirms the three clock-domain probe bindings above. Final STA fails; this static CDC table grants no G2 acceptance. See manual-engineering-review.md and engineering/attempt3/critical-paths.json.\n'
(REC/'cdc-review.md').write_text(cdc,encoding='utf-8')
subprocess.run([sys.executable,str(REC/'scripts/render_reports.py'),'3'],check=True,timeout=60)
subprocess.run([sys.executable,str(REC/'scripts/verify_counts.py')],check=True,timeout=60)
subprocess.run([sys.executable,str(REC/'scripts/preflight.py')],check=True,timeout=60,stdout=subprocess.DEVNULL)
lessons=(REC/'lessons-learned.md').read_text(encoding='utf-8')+'\n11. A shared-enable data register can cut forward arithmetic yet retain a long backward ready path. Final routed setup/hold must still pass; a completed native SDK command, valid CWC and spare resources do not substitute for timing. Three actual production attempts were used; stop before a fourth without new conditions.\n12. One bounded DeepSeek text-accounting call was reviewed and rejected for dropped control/TD attempts and inconsistent totals. Native result JSON gave33 G1 runs,26 passes,7 failures. No worker operation/pending call_id existed; no resume or retry was fabricated.\n'
(REC/'lessons-learned.md').write_text(lessons,encoding='utf-8')
print(json.dumps({'setup_worst':next((x for x in paths if x['check']=='setup'),None),'hold_worst':next((x for x in paths if x['check']=='hold'),None),'status':'blocked','reports_written':True},indent=2))
