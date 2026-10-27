# T11.BRD.P1 r2 — lessons (root cause / trigger / fix / verification entry)

1. **A testbench constant built from a 32-bit expression cannot be replicated.**
   `{4{(line*32+grp) & 10'h3FF}}` replicates a 32-bit operand into 128 bits and
   then truncates to 40 — the four 10-bit lanes are not equal. Trigger: any
   `{N{expr}}` where `expr` is wider than the lane. Fix: latch the value into a
   lane-wide variable with a **blocking** assignment, then replicate
   (`cam_val = …; cam_pix <= {4{cam_val}};`). Verification entry:
   `sim/tb_brd_g1_r2.v` probe (`stim_lane_bad`, `stim_first_v`, `pk_first`) and
   `evidence/tb-stimulus-fix.md`.
2. **A non-blocking latch in a per-beat loop shifts the data by one beat.**
   The r1 tester's own fixed variant used `cam_val <= …` and the first accepted
   pixel was 519 instead of 520. Blocking assignment keeps the value on the beat
   it belongs to. Verification entry: probe `n=0..7` = 520..527 (increment 1).
3. **`raw == pk_bytes` is a self-comparison, not pixel evidence.** `pk_bytes` is
   the DUT's own packer output, so the equality holds even for malformed input.
   Fix: an independent expected-raw model that reads nothing from the DUT, and
   demote `raw == pk` to an additional check. Verification entry:
   `evidence/gen_expected_raw.py` + `evidence/verify_slot_r2.py`
   (`*_raw_equals_expected_raw`).
4. **The DUT's deflate is not Python zlib.** For the same 3840 B input, CPython
   zlib produced 1391 B while `a1_deflate_core` produced 3137 B with the *same*
   Adler-32. Never freeze `stream_len` from `zlib.compress`; freeze the raw and
   the Adler, and treat the compressed length as candidate-bound. Verification
   entry: `evidence/golden-r2.md` §3.
5. **`cd` in a ModelSim `-do` script fails once a design is loaded**
   (`Cannot change directory while a simulation is in progress`), and after a
   `cd` the relative `work` mapping no longer resolves. Fix: start `vsim`
   without a unit, `cd` first, then `vsim work.<unit>`, and give each dump
   directory a `work` **junction** to the single compiled library. Verification
   entry: `sim/run_sim_r2.ps1`, the two early harness-failure logs.
6. **One dump directory per scenario is cheap insurance.** In r1 a diagnostic
   variant overwrote the frozen `scen0` dump and had to be restored. In r2 every
   scenario (and the arbiter) writes into its own directory, so a candidate dump
   cannot be clobbered. Verification entry: `sim/scen0|scen3|scen4|prep/`.
7. **Do not let a script's own log be bound before it is written.** Freeze order:
   run the checks → generate the manifest (binding the check logs) → run the
   post-freeze verifier whose log is excluded from the manifest. Verification
   entry: `evidence/verify_manifest_r2.py` + `gen_manifest_r2.py` exclusion list.
8. **"Repo-relative" must be true in the JSON too.** r1's
   `filelist-sha256.json` claimed `repo_relative: true` while writing absolute
   `D:/...` paths. Fix: compute each path relative to the repository root and
   add `filelist_tcl_sha256`. Verification entry: `evidence/filelist-check.log`
   (`n2_filelist_json_repo_relative`).
9. **Never ship a generated project file with absolute paths.** r1's
   `brd_board.al` carried 81 absolute paths; the r2 package ships only
   `brd_board.al.tmpl` + `gen_al.py` and the README requires running it first.
   Verification entry: `evidence/static_checks_r2.py` (`n3_*` checks).
