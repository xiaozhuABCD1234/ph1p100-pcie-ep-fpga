"""Write development closeout from actual saved local evidence, before unique freeze."""
from pathlib import Path
import ast, datetime, json, sys

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[3]
def save(path,data):path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

def main():
    assert not (HERE/'manifest-r0.json').exists(),'already frozen'
    results=json.loads((HERE/'case-results.json').read_text())
    checks=json.loads((HERE/'local-verification.json').read_text())
    commands=[json.loads(s) for s in (HERE/'commands.jsonl').read_text().splitlines()]
    assert sum(Path(r['command'][0]).name=='vlog.exe' for r in commands)==1
    assert sum(Path(r['command'][0]).name=='vsim.exe' for r in commands)==6
    assert all(r['exit_code']==0 and not r['timeout'] for r in commands)
    assert all(r['local_check_pass'] for r in results) and checks['byte_checked_frames']==105
    syntax=[]
    for path in sorted(HERE.glob('*.py')):
        ast.parse(path.read_text(encoding='utf-8'));syntax.append(str(path))
    save(HERE/'python-syntax-result.json',{'pass':True,'method':'ast.parse','files':syntax})
    warnings=[s for s in (HERE/'local/build-r0/vlog.log').read_text(errors='replace').splitlines() if '** Warning' in s]
    assert len(warnings)==1 and 'pcie_ep_engine.v(127)' in warnings[0] and 'Redundant digits' in warnings[0]
    save(HERE/'warning-audit.json',{'compile_errors':0,'compile_warning_count':1,'warnings':warnings,
         'disposition':'pre-existing redundant literal digits in frozen PCIe engine; no warning suppression or RTL edit'})
    save(HERE/'development-corrections.json',[
      {'stage':'prepare before compile','exit_code':1,'actual_command':['python','-X','utf8',str(HERE/'run_freerun.py'),'compile'],
       'cwd':str(ROOT),'error_excerpt':"KeyError: 'D:/fpga/ph1p100/workflow/runs/20261025-180900_fpga-dual-offline-closure/T08.dual-local-closure/r1/mode-fix02/candidate/rtl/checked/crc32_upd4.v'",
       'new_evidence':'old manifest places crc32_upd4.v in candidate/rtl/ep_side/ddr',
       'correction':'map exact old-manifest include path; native compiler had not started'},
      {'stage':'independent oracle case1','exit_code':1,'actual_entry':'check_freerun.check(package/local/case1) in bounded task orchestration',
       'cwd':str(ROOT),'error_excerpt':'AssertionError: drop gaps do not match busy source frames',
       'new_evidence':'SSOF camera0 fid106=320000ns; RECOVER=320000ns; actual releases occur later; next publication seq8',
       'correction':'derive first eligible recovery source from checked SOF and actual initial-slot release times; require sequence7 or8 then every remaining sequence; do not change RTL, source timing or >=2 final-good threshold'}])
    save(HERE/'execution-accounting.json',{'compile_max':2,'compile_actual':1,'case_process_max':8,'case_process_actual':6,
      'tool_calls_max':45,'native_tool_calls_through_final_freeze_planned':31,'role_minutes_max':75,
      'read_search_deadline_seconds':60,'native_compile_sim_deadline_seconds':300,'vlib_deadline_seconds':60,
      'retry_policy':'no automatic retry; one corrected preparation invocation and one oracle correction after new evidence',
      'timeout_events':0,'foreign_process_termination':0,'RTL_edits':0,'descendant_agents':0,'DeepSeek_delegations':0,
      'TD':0,'hardware':0,'COM':0,'JTAG':0,'download':0,'Flash':0,'RK_write':0,'install':0,'commit':0,'push':0,'external_message':0,
      'deletion_operations':0,
      'bootstrap_deviation':'The first four short shell reads/status commands completed in <=1.6 s each but did not have an explicit subprocess deadline. This is disclosed and cannot be retroactively corrected. Later input retrievals used a 60 s subprocess watchdog; all compile/case child commands had real deadlines.',
      'active_owned_commands_after_freeze_returns':0})
    table=['| Case | Theme | A publish/drop | B publish/drop | Recovery good A/B | Peak slots |',
           '|---|---|---:|---:|---:|---:|']
    for r in results:
        a,b=r['matrix'];table.append(f"| {r['case']} | {r['theme']} | {len(a['accepted_sequences'])}/{a['drops']} | {len(b['accepted_sequences'])}/{b['drops']} | {a['good_after_recovery']}/{b['good_after_recovery']} | {r['peak_occupancy']} |")
    report='''# T08.freerun-isolation development result, round0

Status: local development checks complete; ready for independent integrated testing after manifest freeze. This file does not issue an integrated PASS verdict.

The only modifications are new TB/runner/checker and evidence inside this package. The 74-file source/include/vendor-model closure maps byte-for-byte to the checkout copy of T08 mode-fix02. The old manifest SHA is 38e0615341330aa5b8f1e0e1f9ecf4e169abbdc6bc4856912b9e4f929bdfcce3. Candidate RTL, production rtl/tools/constraints/al_ip, other task implementations, active D:/fpga/ph1p100 runs, RK, handoff files and global libraries were not edited by this role. No old simulation result is used as current evidence.

## Observable local results

One ModelSim compilation completed with Errors: 0 and one frozen redundant-numeric-literal warning. Six separate vsim processes exited zero with FREERUN_PASS and no fatal/error marker. Every case sent exactly twelve absolute-schedule source SOFs/EOFs per camera, and twelve checked CSI SOFs per camera. The Python parser independently checked all 105 published and native-read DMA frames against source bytes, geometry, identity, IEEE header/raw/payload CRC32 and zero padding.

'''+ '\n'.join(table)+'''

Every busy case covers six source frames per camera before recovery; full slots continue receiving further complete source frames, more than two slot-capacity rounds. Source frame conservation is exact: published count + writer whole-frame drop count = 12 for each camera. All dropped source sequences are enumerated in case-results.json and have no publication. The last two source sequences, 11 and 12, publish/read/check/release correctly for both cameras in all cases.

Busy-slot byte snapshots are identical, and the real AW path is asserted never to enter a held slot. Stalled descriptor identity/base/length/geometry stays stable. Every publication has exactly one matching descriptor take, full native read and status0 release; release wire camera and slot mask are checked. Case5 rejects four mismatched identities without releasing any slot, then drains correctly. Camera mutation, held-memory-bit mutation, wrong release routing and a missing/gated source SOF all produce explicit rejection in negative-controls.json.

The recovery control edge is 320 us. Source frame7 starts at that same time in simultaneous cases, before a held slot is actually freed, so it correctly drops; frame8 begins continuous recovery. The skewed B case has frame7 after its actual release and accepts it. The checker uses observed release/SOF timing for this one boundary, then requires all later sequences without gaps. The initial overly strict seq7 assumption and its correction are preserved in development-corrections.json.

## Reproducibility and engineering evidence

Actual native command argv, cwd, return code, deadline, owned PID, elapsed time and output logs are in commands.jsonl. The one compile is local/build-r0/{vlib.log,vlog.log,compile-result.json}; each local/caseN contains vsim.log, sim-result.json, events.log, frame/read byte dumps, native read beats, and oracle-result.json. A 60 s outer watchdog executed verify_local.py; local-verification.log and local-verification.json record its actual zero-exit result and 105-byte-frame total. Python sources also pass ast.parse. input-drift-after-local.json records zero drift across all 74 source entries and five reference files.

The thin interface check verifies the bit widths of all camera/slot/epoch/session/capture_seq fields across frozen T08 A/B descriptors, the P3 selected tuple, and global release. The P3 file is an interface reference only; its implementation and P4 are not instantiated. Source tasks contain no ready/occupancy/consumer dependency. No DUT hierarchical force is used; hierarchical access only observes DUT state and sets documented DDR-model busy controls.

The first four bootstrap shell reads/status calls lacked explicit subprocess deadlines and each completed within 1.6 s. This execution constraint deviation is disclosed in execution-accounting.json. Subsequent retrievals used 60 s watchdogs; all native compile/case children had 60/300 s deadlines and none timed out. No process was killed. One preparation mapping failure occurred before native compile, and one independent oracle assumption failed before correction; both are preserved rather than erased. There was no RTL repair or extra case process.

## Scope, limitations and handoff

The frozen vendor environment supplies DDR byte memory, bus busy/response timing and PLL/PCIe stand-ins; the external consumer is a legal-port test model. Real checked CSI, both frame writers, arbitration, mailboxes, ownership and release logic remain instantiated. SYNC_ENABLE=0 exercises the frozen stream bypass; old sync/I2C behavior is not retested here. Runtime W8/H2 is 20 raw bytes and 4096 DMA bytes; default W1920/H1080 remains 2,592,000 packed bytes/camera and 155.520 MB/s raw for dual30fps. Full geometry, physical Bayer phase, exposure synchronization, timing/resources/CDC, encrypted DDR and PCIe hardware throughput are unmeasured.

Functional local evidence covers all six themes, identity and bytes; engineering local evidence covers source SHA, isolated work/ini, interface widths, static geometry/address budget and reproducible commands; system evidence is limited to honest model boundaries and compatibility. G0/G1/G5 are locally checked. G2 RTL-edit checks are not run because no RTL is changed; G3/G4 are not_run/awaiting_hardware under the plan. These local results do not complete parent T08/T06 or any board task.

handoff.md gives exact independent build/case/check commands and model boundaries; lessons.md records reusable findings. The independent tester should use fresh test-reports/T08.freerun-isolation outputs, add its own independent criterion/control, and check the unique manifest before/after. The package is then stopped and frozen by freeze_r0.py. Rollback is to stop using the package; no candidate replacement or board change exists to undo. No deletion is required.
'''
    (HERE/'result-r0.md').write_text(report,encoding='utf-8')
    print('NOTES_OK cases=6 byte_checked_frames=105 compile=1 case_process=6',flush=True)

if __name__=='__main__':main()
