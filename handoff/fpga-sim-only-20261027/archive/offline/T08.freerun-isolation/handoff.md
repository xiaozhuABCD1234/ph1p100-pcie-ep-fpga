# T08 free-running isolation: independent test entry

Task: `T08.freerun-isolation`, round0, offline verification package. Production and snapshot RTL are unchanged. This is a development handoff, not an integrated tester verdict.

The exact source closure is in `inputs/source-binding.json` (74 individually SHA-checked files). `inputs/sources.f` maps the old absolute source paths into the current checkout snapshot. The authoritative old manifest SHA is `38e0615341330aa5b8f1e0e1f9ecf4e169abbdc6bc4856912b9e4f929bdfcce3`. Old simulation results are not reused. Missing historical frame dumps excluded during repository synchronization are not test inputs.

## Reproduce in the tester's evidence directory

The package is already prepared and frozen. Do not invoke `prepare` or `verify_local.py` against the frozen package: those commands regenerate development evidence. `compile` and `case` accept a separate build/output directory under this run's `test-reports/T08.freerun-isolation/` and keep their journals there. Create a fresh directory name; no cleanup/deletion is required.

```powershell
$pkg = 'D:/fpga/repos/ph1p100-pcie-ep-fpga/workflow/runs/20261027-060708_fpga-parallel-offline-delivery/T08.freerun-isolation'
$ev = 'D:/fpga/repos/ph1p100-pcie-ep-fpga/workflow/runs/20261027-060708_fpga-parallel-offline-delivery/test-reports/T08.freerun-isolation/independent-r0'
python -X utf8 "$pkg/run_freerun.py" compile --build "$ev/build"
python -X utf8 "$pkg/run_freerun.py" case --build "$ev/build" --case 0 --out "$ev/case0"
python -X utf8 "$pkg/check_freerun.py" --case-dir "$ev/case0"
```

Repeat the last two commands with case numbers 1 through 5 and distinct `case1` through `case5` directories. The runner applies a real 300 s subprocess deadline to each vlog/vsim, 60 s to vlib, and terminates only the owned PID tree on timeout. It uses a package-local `modelsim.ini` and separate work library. No drive mapping, TD, hardware, install or global configuration operation is used.

Additional read-only checks:

```powershell
python -X utf8 "$pkg/check_freerun.py" --static
python -X utf8 "$pkg/check_freerun.py" --negative --case-dir "$ev/case4"
```

`commands.jsonl` holds actual native compile/simulation commands, cwd, PID, deadline, return code and log paths. `local/case*/sim-result.json`, `events.log`, published `frame_*.hex`, transferred `read_*.hex`, `read_beats.log`, snapshots and `oracle-result.json` are the development evidence. `case-results.json` is the complete camera/sequence matrix.

## Fixed scope and model boundary

Real frozen modules: `ph1p_pcie_ep_top`, checked CSI packet integrity/unpack, both `cam_r10f_writer` instances, write arbitration, four ownership mailboxes and `dual_local_closure`, including its descriptor and release logic. The external consumer drives only legal descriptor-ready, native AR/R and complete-identity release ports. No DUT force is used.

Simulation models: the frozen `vendor_env.sv` provides DDR byte memory, AXI busy/response timing and constant vendor PLL/PCIe stand-ins. This tests the real writer/descriptor/release logic against a memory/consumer model; it does not exercise encrypted DDR, real PCIe or P4. `SYNC_ENABLE=0` deliberately uses the frozen bypass parameter; sync/I2C are not rebuilt, rerun or claimed verified here. P3 is read only as an interface declaration reference; its implementation is not compiled into this package and no P3/P4 functional result is claimed.

Source A has a 14 ns byte clock, source B an 18 ns byte clock with a 3 ns initial clock phase. The model DHI clock is 8 ns, system clock 20 ns. Twelve frames per camera start at absolute predeclared times; generation never consults ready, queue occupancy or consumer progress. Case 2 additionally uses a 52 us B frame period and 3 us B frame-start offset; other periods are 50 us. CSI short packet/ECC/CRC16 framing uses the prior TB packet conventions, with new frame scheduling and consumer logic. The new Python oracle independently generates expected packed payload bytes and uses standard-library CRC32 over documented R10F fields.

Runtime geometry is W8/H2: 20 valid packed bytes and 4096 DMA bytes per frame. Defaults remain W1920/H1080, 2,592,000 packed bytes/camera; dual 30 fps raw budgeting is 155.520 MB/s. This reduced test does not establish full-resolution throughput, physical Bayer phase, exposure synchronization, DDR capacity/resource/timing or CDC signoff. G0/G1/G5 concern this offline package; RTL-edit G2 is not run, and G3/G4 are not run/awaiting hardware under the frozen plan.

## Themes and acceptance evidence

0: simultaneous scheduled SOFs, continuous source, all 12 frames/camera.

1: A descriptor consumer busy for six source frames while B continues; A held memory is unchanged, then A recovers.

2: B busy while A continues, with source phase/period skew; B recovers.

3: a legal external read is accepted while the native DDR AR model remains busy across at least six SOFs/camera. Both other slots publish, all four slots become held, further complete frames drop, then reads/releases drain.

4: both descriptor ready signals stay low through six source frames. Four complete slots remain held while further source SOFs/EOFs continue. Held memory snapshots match before/after, no rejected sequence publishes, then both cameras recover.

5: all four descriptors are taken and held while the consumer pauses. Old epoch, old session, wrong camera with an unowned sequence, and mismatched sequence releases increment rejects and produce no release pulse. Consumer resume reads complete data and releases exact identities. The wrong-camera test intentionally uses a nonmatching sequence: if another camera owns an otherwise identical tuple, changing camera to that tuple denotes a different valid release, not a distinguishable malformed one.

All cases conserve source frames as publications plus whole-frame drops, require one transferred descriptor/read/release per publication, check camera/slot/epoch/session/sequence and every published/read byte, raw/payload/header CRC32 and zero tail. The real writer AW path is checked against every held slot on every DHI cycle. Stalled descriptors must retain all identity, base, length and geometry fields. Recovery ends with sequences 11 and 12 good for each camera.

Recovery enable changes at 320 us. In simultaneous cases, source frame 7 also starts at 320 us and can correctly drop while its target is still protected. The checker derives the first safe recovery frame from observed release and checked-SOF times (7 or 8), then requires all remaining frames without gaps. This accounts for the boundary frame instead of assuming a release has already happened at the control edge.

The four development evidence mutations remove a ready-gated SOF, corrupt a camera byte, change a held snapshot byte, and misroute a release wire pulse. All must be rejected. These are checker sensitivity controls, not RTL mutations. The independent tester should add its own perturbation or independent parsing criterion and verify manifest hashes before and after its work.

Rollback: stop using this package. No candidate replacement, board state, production RTL or global ownership state was changed. Keep evidence; do not batch-delete generated files.
