# T10.b19-cam-a r0 — lessons

## L1. A compile-time tap select can silently void the frozen clock groups

`CAM_SEL` is a `localparam`; with `1'b0` every B tap/debug output is unused.
TD `optimize_rtl` then removes the whole B byte-clock cone, including
`u_camera/u_csi_b/u_rx_phy/u_hs_clk_div.clkdivout`. The frozen `p2_board.sdc`
still references `mipi_b_byte_clk` in `set_clock_groups -asynchronous`; TD binds
clock groups against the *final* clock set, so the missing generated clock
invalidates the command and all SDC-declared async crossings become timed paths.

Symptom: synthesis WNS collapses by nanoseconds while the netlist is essentially
unchanged (slice 18,754 vs 19,405; eram 72 = 72) and *every self-domain group
still passes*. The report suddenly contains `Same Domain` / `Cross Domain`
groups (clk_a1<->ddr_user, sys_clk50m->mipi_a_byte_clk) that the reference build
does not have at all.

Detection recipe that worked (no extra TD session):
1. Compare `syn_gate_timing.rpt` "Clock Summary" reference vs candidate: the
   trimmed clock is simply absent.
2. Compare "Path Group" lists: reference has only `Self` groups; candidate has
   the async pairs as timed groups.
3. Confirm the negative paths are CDC structures (Gray pointers, PHY reset),
   not logic depth, and that all self groups are positive.

Rule for planning: when a build changes which clock of a duplicated core is
*used*, check every `create_generated_clock`/`set_clock_groups` that names the
now-unused clock. "Both cores stay instantiated" does not keep an unused clock
alive through synthesis.

## L2. Keep the b18 SDC/mipi_b constraint only if the B domain survives

If a future candidate must keep `p2_board.sdc` byte-identical, it must also keep
the B byte clock alive (inert observation / keep attribute), otherwise the same
failure returns. Otherwise the SDC's B group must be dropped with an explicit
approved diff.

## L3. Negative control for the board gate is cheap and decisive

Running the new A gate on the previous B capture (`captures_full`) immediately
showed `camsel_bit12=1 -> FAIL`. This proves the gate can reject the wrong
camera and also exercised the parser. Do this before any download.

Caveat found: a 300 s capture of a continuous stream normally ends mid-frame, so
"no half frame" must allow a *tail-cut* frame (payload runs past capture end)
and only reject a full payload with a bad body CRC. The first version of
`check_b19_board.py` wrongly failed the b18 capture on that tail frame; fixed by
splitting `tail_cut` from `bad`.

## L4. Copied testbench file needs its module renamed

`tb_status_v6.v` copied to `tb_b19_status_v6.v` still declared
`module tb_status_v6`, while the driver asked vsim for `tb_b19_status_v6`
(vsim-3170). Rename the module, not just the filename.

## L5. Parser field map must be read, not guessed

In the A1 status snapshot `cam0..cam14` are: clk_tgl, pkt_tgl, vs_tgl,
pix_beats, line_rises, frame_rises, frame_falls, last_frame_cycles, roi_frames,
crop_groups, crop_short, crop_geom_err, phystat, cam_sysstat, nack. `pix_beats`
is `cam3`, not `cam0`. Verify against the known b18 capture before gating.

## L6. b18 baseline metrics to compare against

b18 synthesis: SWNS +0.426 / STNS 0 / slice 19,405 / eram 72 / reg 20,734;
routed: WNS +0.066, HWNS +0.020, 0 violated endpoints, ERAM 103. Any b19
synthesis report that is nanoseconds worse with a near-identical netlist is a
constraint-application problem first, not an RTL timing regression.

## L7. Dropping the dead B clock group fixed the constraint failure (proven)

With the approved one-group deletion the second synthesis returned to the real
design: `SWNS +0.127 / STNS 0` (24,718 slices? -> 18,718 syn slices, ERAM 72),
and all SDC async groups applied (only `Self` path groups; the earlier
`Same Domain`/`Cross Domain` groups are gone). Final STA still reports
`create_generated_clock ... mipi_b_byte_clk` failure (the divider is trimmed) —
that warning is expected and harmless once the B group no longer references the
clock. So the diagnosis in L1 is confirmed by construction, not only by
inference.

## L8. The b19 A candidate is ~0.1 ns short after route

Routed: `SWNS -0.098 / STNS -0.518 / HWNS +0.020`, 10 violated `clk_a1`
endpoints (all self domain); `ddr_user +0.007`, `mipi_a_byte_clk +0.266`.
Worst path `u_a1/a1_abort_reg -> u_a1/u_a1/smem.addrb[10]` (6 levels, ERAM).
This is below the +0.003 stop line, so per the frozen gate the single route
attempt is spent and no bitgen is allowed. The SDC/clock-group work is done;
the remaining gap is a placement/path issue, not a camera-path issue. A future
authorized candidate needs either a new route attempt with different effort/
seed (outside this task's budget) or a targeted pipeline change around the
`a1_frame_top` abort -> smem address path.

## L9. Do not let a build script's exit code stand in for the route gate

`01_build.tcl` exits 0 even when route STA is negative (it only stops on
synthesis). `P2_BUILD_DONE` + `BUILD_EXIT=0` therefore does not mean the route
gate passed; the routed `SWNS/VIOL_EP` values are the gate. The b19 run
reported `P2_ROUTED_SWNS=-0.098 ... VIOL_EP=10`, so bitgen was skipped
deliberately.
