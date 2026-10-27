# lessons-r1 - T10.ah-honly-td (Line B, r1)

1. **TD can crash on importing its own synthesis DB.** Trigger: `import_db` of
   `a1_ah_gate.db` printed `Import Inst constraints`, then `Import ChipWatcher`, then
   `Oops! coredump` - twice, in two different working directories, 1.2-1.4 s each. Fix:
   treat a coredump as `TOOL_UNAVAILABLE`, capture the `minidump-*.dmp` name, and do not
   burn the route quota re-trying the same statement. Verification: attempt 2 changed
   only the project directory (copied vs original, because a copied `.al` keeps
   `Path=".../run-syn1"`); the identical crash proves the path was not the cause.

2. **A copied TD project is not a neutral operation.** Trigger: copying `a1_ah.al` +
   `a1_ah_Runs/syn_1` into `run-route1` leaves the project's absolute `Path` pointing at
   the original directory, which mixes cwd and project state. Fix: either run the flow
   in the directory the `.al` names, or regenerate the project there. Verification: route
   attempt 2 in the original directory behaved byte-for-byte the same as attempt 1, so no
   conclusion about the crash may be drawn from the copy alone.

3. **The synthfix multi-driver fix is confirmed by the tool, not just by simulation.**
   Trigger: r0 died with `HDL-8007 cmem_lo[15]`; r1 with the synthfix core elaborated all
   12 RAMs and produced a 2.3 MB gate DB plus timing/area in 43 s. Fix: use the TD
   elaboration as the authoritative check for this defect class. Verification:
   `PRJ-1406 Run syn_1 finished`, `AH_SYN_RUN_COMPLETE`, 0 violated endpoints.

4. **Gate-level +0.029 ns is a warning, not a closure.** Trigger: 52-58 % of each worst
   datapath is already net delay before placement, with 7 logic levels and 8-fanout
   nets. Fix: never promote a synthesis WNS into an eligibility statement; report it as a
   pre-place bound and require routed numbers. Verification: `flow.status` is
   `Timing Mode: basic`, confidence `Synthesized`, and the gate's own IO/ERAM counts are
   explicitly marked as estimates.

5. **Fold every DUT output or the pin count silently changes.** Trigger: the wrapper's
   IO total came out as exactly 121 = 2 + 40 + 6 + 41 + 32, i.e. the status XOR fold kept
   the 8 x 32-bit buses + `st_busy` + `dbg[31:0]` internal. Fix: keep the wrapper
   byte-identical between rounds and verify the IO count against the port sum on the
   first area report. Verification: `#IO 121 out of 286 (42.31 %)`, 0 undriven warnings.

6. **Freeze sentinel semantics explicitly.** Trigger: `flow.status` prints hold
   `WNS 2147483647ps`, which looks like a huge positive slack but means "no failing hold
   endpoint". Fix: record both the sentinel and its meaning (and the timing report's
   `HWNS 0.000 ns`) so a reviewer cannot misread it as a measured margin.