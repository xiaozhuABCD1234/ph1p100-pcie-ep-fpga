# T08.freerun-isolation development result, round0

Status: local development checks complete; ready for independent integrated testing after manifest freeze. This file does not issue an integrated PASS verdict.

The only modifications are new TB/runner/checker and evidence inside this package. The 74-file source/include/vendor-model closure maps byte-for-byte to the checkout copy of T08 mode-fix02. The old manifest SHA is 38e0615341330aa5b8f1e0e1f9ecf4e169abbdc6bc4856912b9e4f929bdfcce3. Candidate RTL, production rtl/tools/constraints/al_ip, other task implementations, active D:/fpga/ph1p100 runs, RK, handoff files and global libraries were not edited by this role. No old simulation result is used as current evidence.

## Observable local results

One ModelSim compilation completed with Errors: 0 and one frozen redundant-numeric-literal warning. Six separate vsim processes exited zero with FREERUN_PASS and no fatal/error marker. Every case sent exactly twelve absolute-schedule source SOFs/EOFs per camera, and twelve checked CSI SOFs per camera. The Python parser independently checked all 105 published and native-read DMA frames against source bytes, geometry, identity, IEEE header/raw/payload CRC32 and zero padding.

| Case | Theme | A publish/drop | B publish/drop | Recovery good A/B | Peak slots |
|---|---|---:|---:|---:|---:|
| 0 | simultaneous_sof | 12/0 | 12/0 | 6/6 | 1 |
| 1 | A_busy_B_active | 7/5 | 12/0 | 5/6 | 3 |
| 2 | B_busy_A_active_and_skew | 12/0 | 8/4 | 6/6 | 3 |
| 3 | consumer_native_AR_long_busy | 7/5 | 7/5 | 5/5 | 4 |
| 4 | four_slots_full_new_SOF | 7/5 | 7/5 | 5/5 | 4 |
| 5 | stale_identity_reject_and_recovery | 7/5 | 7/5 | 5/5 | 4 |

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
