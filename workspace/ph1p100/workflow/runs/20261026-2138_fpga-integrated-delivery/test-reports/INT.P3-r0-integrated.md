### 判定：FAIL

- task_id: INT.P3
- dimension: integrated
- round: 0
- candidate_root: fpga/csi2/src/integrated_delivery
- frozen_manifest: D:\fpga\ph1p100\workflow\runs\20261026-2138_fpga-integrated-delivery\INT.P3-r0-manifest.json
- manifest_sha256: 29f4477120ab154083bb5ca4944df35b104e7bff1878b91f714d6c9d6868df46 (production RTL); tool input dual_channel_schedule.py fe0e879297723289ac600ed79949398018aae0eee775e168de62e10dac105b82
- input_drift_check: no drift; all manifest production/tool hashes re-verified before and after testing, unchanged.
- tools: ModelSim Intel FPGA 10.5b (vlog/vsim), Python 3.11.9; no TD/synthesis/board tools used.

## Scope / G layers (frozen by dev-plan)
- INT.P3: dual A/B capture identity and frame-granular scheduling; B-first via b_priority; A gated by a_enable pending b20 effective result.
- Required G layers: G0, G1, G2. G3/G4 not applicable this round (no board window/download), recorded not_run + awaiting_hardware.
- Thresholds: valid/ready stall hold; identity-preserving release; no cross-frame/mixed-channel; A disabled does not block B.

## Functional (fail)
Passed:
- Dev TB `tb_dual_channel_capture_scheduler.v`: compile 0 errors/0 warnings; vsim run -> `TB_DUAL_CHANNEL_CAPTURE_SCHEDULER PASS`.
- Independent TB `test-reports/INT.P3-r0-evidence/tb_independent.v`: identity mismatch release keeps busy and increments st_rejected; correct release clears busy and increments st_completed; failed release (status!=0) increments st_failed; A disabled selects B; invalid camera_id not accepted; B priority round-robin alternates.
- Python oracle `tools/integrated_delivery/dual_channel_schedule.py`: self-test -> `DUAL_CHANNEL_SCHEDULE PASS`.
Failed / defect found:
- Valid/ready backpressure is not held. In `tb_bp.v`, A accepted (o_capture_seq=3) but before consumer ready, B descriptor arrived and was accepted, overwriting o_capture_seq to 6 while a_busy remained 1. Result: downstream never observes A's descriptor; frame loss/mixed presentation under stall. RTL `a_can`/`b_can` and accept block do not gate on `!(o_valid && !o_ready)`. This violates valid/ready stall preservation.
- A-channel real b20 timing result is not available; A path implemented and gated by a_enable, but not proven on b20. Marked pending, not counted as dual-channel pass.

Independent criterion used: independent testbench (`tb_independent.v`, `tb_bp.v`) with counters connected and distinct scenarios from dev TB; negative mutation copy `dual_channel_MUTATED.v` (drop a_enable gating) was compiled to confirm the testbench targets the intended defect class.

## Engineering (not_run / partial)
- Compile/lint: `vlog -lint` -> 0 errors/0 warnings.
- Simulation: dev TB and independent TB compile/run (see logs).
- G2 synthesis/STA/CDC/resources: not run this round (deferred by development to INT.P4; no synthesis/STA tool run). Recorded not_run + blocked/awaiting_synthesis. Single clock domain, no CDC in this module; constraints/resource data absent.
- Lint: no warnings.

## System (not_run / blocked)
- Top-level integration not yet performed (INT.P4). No address-map/board impact evidence.
- G3 board function and G4 stability/performance: not_run + awaiting_hardware (no board window/download).
- Candidate identity: manifest hashes verified; no bitstream/CWC evidence.

## Evidence paths
- D:\fpga\ph1p100\workflow\runs\20261026-2138_fpga-integrated-delivery\test-reports\INT.P3-r0-evidence\dev_tb_sim.log
- D:\fpga\ph1p100\workflow\runs\20261026-2138_fpga-integrated-delivery\test-reports\INT.P3-r0-evidence\independent_tb_sim.log
- D:\fpga\ph1p100\workflow\runs\20261026-2138_fpga-integrated-delivery\test-reports\INT.P3-r0-evidence\tb_independent.v
- D:\fpga\ph1p100\workflow\runs\20261026-2138_fpga-integrated-delivery\test-reports\INT.P3-r0-evidence\tb_bp.v
- D:\fpga\ph1p100\workflow\runs\20261026-2138_fpga-integrated-delivery\test-reports\INT.P3-r0-evidence\oracle.log

## Unmeasured / next actions
- Fix valid/ready stall gating in scheduler (hold accept while o_valid && !o_ready), then rerun dev + independent TB.
- Obtain A-channel real b20 timing result; only then claim A path pass.
- Run G2 synthesis/STA/CDC/resources in INT.P4.
- Board G3/G4 when hardware window available.