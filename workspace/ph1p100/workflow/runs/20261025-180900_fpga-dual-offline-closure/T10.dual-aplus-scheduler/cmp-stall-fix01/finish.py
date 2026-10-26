import pathlib,json,hashlib,re,datetime,sys
sys.dont_write_bytecode=True
N=pathlib.Path(__file__).resolve().parent;P=N.parent;R=P.parent;E=N/'evidence'
def sha(f):return hashlib.sha256(f.read_bytes()).hexdigest()
def entry(f):return dict(path=str(f),bytes=f.stat().st_size,sha256=sha(f))
now=datetime.datetime.now().astimezone();assert now.isoformat()<'2026-10-25T22:44:26.9726768+08:00'
snapshot=json.loads((E/'compiled-source.json').read_text());assert all(sha(pathlib.Path(x['path']))==x['sha256']for x in snapshot)
for f,want in [('a1_frame_top.v','c8b24775fa70793f682f1a640be175ec53f304722539cbd89550e0d4aefca65b'),('a1_deflate_core.v','6797db053cfc47497540d6345e3a46b7e79cc1d34fa25da5a4c501505fbf35bb')]:assert sha(N/'candidate'/f)==want
assert json.loads((E/'old-cmp-counterexample/expected-rejection.json').read_text())['expected_rejection']
assert json.loads((E/'crossword-negative/negative-control.json').read_text())['expected_rejection']
checks={};total=0
for name,count in [('cmp-matrix',8),('small-nominal',14),('full-nominal',2)]:
 c=E/name;ck=json.loads((c/'checker.json').read_text());assert ck['frames']==count;txt=(c/'console.log').read_text(errors='replace');assert 'TB_DONE' in txt and 'ASSERT_FAIL' not in txt and 'Errors: 0, Warnings: 0' in txt
 events=(c/'events.log').read_text();services=[]
 for cam,seq,status,cy,words,groups in re.findall(r'FRAME cam=(\d+) seq=(\d+) status=(\d+) cycles=(\d+) words=(\d+) groups=(\d+)',events):
  z=dict(camera=int(cam),seq=int(seq),status=int(status),cycles=int(cy),ar_words=int(words),groups=int(groups));assert z['status']==0
  if name=='full-nominal':assert z['ar_words']==81024 and z['groups']==518400
  services.append(z)
 assert len(services)==count
 checks[name]=dict(frames=count,hits=re.findall(r'HIT (.*)',txt),services=services,checker=entry(c/'checker.json'));total+=count
assert 'SLOT1_STALL_SLOT0_ACK_RECOMMIT' in checks['cmp-matrix']['hits'];assert 'CMP_TAKE_REFILL_ACK_COMMIT_REAL_CORE GOOD8' in checks['cmp-matrix']['hits']
records=[json.loads(x)for x in (E/'commands.jsonl').read_text().splitlines()];comp=[x for x in records if pathlib.Path(x['argv'][0]).name=='vlog.exe'];cases=[x for x in records if pathlib.Path(x['argv'][0]).name=='vsim.exe'];assert len(comp)==1 and len(cases)==5
assert not any('/faults/' in str(a) or '/faults-retry/' in str(a) for x in cases for a in x['argv'])
full=checks['full-nominal']['services'];rates=[2592000/(x['cycles']*1e-8)/1e6 for x in full]
summary=dict(status='developer_local_checks_complete',independent_integrated_verdict=False,checks=checks,total_good_frames=total,old_counterexample='expected descriptor stall assertion',targeted_negative='expected RAW status/content rejection',this_compile_count=1,this_case_processes=5,faults_suite_increment=0,raw_service_MB_s_at100MHz=rates)
(E/'summary.json').write_text(json.dumps(summary,indent=2))
impact=dict(task_id='T10.dual-aplus-scheduler',scope='pre-first-integrated-acceptance CMP offer correction',changed_RTL=['dual_aplus_scheduler.sv'],unchanged_core=True,external_ports_unchanged=True,added_state_bits=2,frame_buffer_added=False,impact=['CMP descriptor timing/ownership/take-refill/reset and ACK interleaving','nominal real-codec output source identity correspondence'],old_problem='T10.dual-aplus-scheduler:INPUT_CONFLICT:cmp-descriptor-stall',local_disposition='targeted old failure reproduced; new matrix and nominal pass locally',integrated_round0_started=False,post_acceptance_repair_round=0)
(N/'change-impact.json').write_text(json.dumps(impact,indent=2))
retest=dict(required_dimensions=['functional','engineering','system'],required_checks=['Independent rebuild of actual new source closure and unchanged real cores','New CMP legal stall/ACK/recommit matrix, all-field stability and old counterexample','Original nominal W8H2/W8H3/W64H8, prep modes, fairness8 and backpressure/held output ownership','Original capacity/phase/source-identity/CRC/RRESP/RID/RLAST/abort/drain/LOCK/reset cases in first independent acceptance','Default1920x1080 A/B complete strict zlib+inverse/pattern/CRC/length and effective mutation negative control'],report_paths=[str(N/'result-cmp-stall-fix01.md')],input_status='changed',reuse_decision_paths=[str(N/'reuse-proposal.json')])
(N/'retest.json').write_text(json.dumps(retest,indent=2))
(N/'reuse-proposal.json').write_text(json.dumps(dict(developer_reuse_is_not_acceptance=True,unchanged=['real core/frame SHA','RAW/header/payload and native reader logic','abort/drain/LOCK and codec-only cleanup implementation'],candidate_changed='CMP presentation/take logic',old_actual_evidence_manifest=str(P/'static-closeout01/manifest-resume01.json'),proposal='Old faults/full are read-only context. Tester must independently exercise complete original checklist against this new manifest and decide exact-input evidence reuse. No old PASS is spliced.'),indent=2))
(N/'source-map.json').write_text(json.dumps(dict(actual_DUT=[entry(f)for f in sorted((N/'candidate').iterdir())],compiled_inputs=snapshot,fixtures='Previous actual scheduler renamed only; same generated legal matrix. No internal slot forces.',test_inputs=[entry(f)for f in sorted((N/'sim').iterdir())if f.is_file()]),indent=2))
(N/'result-cmp-stall-fix01.md').write_text(f'''# T10 CMP correction developer result

New real implementation window21:44:26.9726768 to22:44:26.9726768, actual summary {now.isoformat()}. This is before first integrated round0, not an invented post-acceptance repair. Only this overlay was written; previous sources/manifests/evidence and production remain unchanged.

The CMP offer is registered and held through backpressure; take transitions only the presented slot, with safe other-slot refill and reset cancellation. Existing metadata arrays are protected by slot state. Actual diff is scheduler.diff; no core, RAW, CRC, clock, geometry or physical interface change. The two core hashes are unchanged.

One successful compile and exactly five planned case processes: old actual scheduler counterexample(expected all-field stall rejection); corrected real-core CMP matrix8; small nominal14; cross-word negative(expected content/release rejection); default full A/B2. All24 positive frames passed strict zlib EOF/no-tail, inverse packed RAW10 independent math, and raw/xform/stream length+CRC checks. Matrix includes legal slot1 stall/ACK0/recommit0, reverse order, two held CMP backpressure, wrong ACK identity, premature take/ACK rejection and actual take/refill/commit/ACK coincidences. Actual hit markers/source SHA/commands/exits/outputs are in evidence/summary.json, compiled-source.json and commands.jsonl. No original faults suite or renamed equivalent ran.

Full cycles A/B: {full[0]['cycles']}/{full[1]['cycles']}; each81024 native read words,2592768 DMA bytes,518400 accepted groups and2592000 RAW bytes. At TB100MHz service={rates[0]:.6f}/{rates[1]:.6f}MB/s, not dual155.520MB/s or board throughput. Worst stored2594706 bytes fits8MiB; minimum RAW write+read311.040MB/s excludes overhead. Source identities and metadata match actual stream bytes.

G0/G1 local checks are complete for this correction; no independent integrated verdict. Full original acceptance, odd/prep geometry, comprehensive faults and other required interface boundaries remain for the first independent integrated tester under its existing budget. G2/STA/physical CDC/resources not_run; G3/G4 not_run awaiting_hardware. Single-clock structure and reset ownership were inspected, not physically signed off.

Historical complete call total remains unknown; preserve original reported37, resumed known13native/8wrapper and static9. Original compile4/cases11/faults3; this adds compile1/cases5/faults0, giving known compile5/cases16/faults3. Old deadlines/caps were not rewritten. New conservative wrapper+native count is in execution-accounting.json. Rollback: leave isolated overlay unadopted; no production replacement or delete occurred.
''',encoding='utf-8')
(N/'handoff.md').write_text('''# Original planner review

Candidate is locally ready for first integrated acceptance after source freeze and author stop flags. Read result/change-impact/source-map/retest and exact manifest. Independent tester must run original complete acceptance plus new CMP matrix; local checks/historical fault evidence are not integrated PASS. Copy inputs to a private tester area before running scripts; frozen overlay stays read-only. Developer faults stays3/3; independent first acceptance uses its own existing budget. No TD/hardware or production adoption is authorized.
''',encoding='utf-8')
print(json.dumps(dict(local_status='complete',frames=total,compiles=1,cases=5,full_services=full,rates=rates)))
