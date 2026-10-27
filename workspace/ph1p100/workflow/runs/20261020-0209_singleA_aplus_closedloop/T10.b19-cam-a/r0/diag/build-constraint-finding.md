# T10.b19-cam-a — synthesis blocker: CAM_SEL=0 trims the B byte clock, which voids the frozen SDC's async clock groups

Date 2026-10-26. Candidate `r0` = b18-proven chain with the single line
`p2_a1_board_top.v:97 CAM_SEL 1'b1 -> 1'b0`. SDC/ADC byte-identical to b18.
TD session 1 (`r0/td/01_build.tcl`) stopped at its inherited synthesis gate:

```
P2_SYN_SWNS=-3.055 P2_SYN_STNS=-3638.322 P2_SYN_SLICE=18754 P2_SYN_ERAM=72 P2_SYN_REG=20053
P2_SYN_NEGATIVE_STOP
BUILD_EXIT=1
```

No route, no bitgen, no download, no board access was performed.

## 1. The netlist is correct and only slightly smaller than b18

| metric (syn_1) | b18 (CAM_SEL=1) | b19 (CAM_SEL=0) |
|---|---|---|
| #slice* | 19,405 | 18,754 |
| #reg | 20,734 | 20,053 |
| #eram | 72 | 72 |
| B byte-clock fanout | 1,645 | **0 (clock object gone)** |
| A byte-clock fanout | 860 | 1,864 |

b18's own `syn_gate_timing.rpt` lists both `mipi_a_byte_clk` and
`mipi_b_byte_clk`; b19's lists only `mipi_a_byte_clk`. The B camera core is
still instantiated but its entire byte-clock cone is dead in this build (all
B tap/debug outputs feed only the unselected `g_cam_sel_b` branch), so
`optimize_rtl` removes it.

## 2. Consequence: the whole `set_clock_groups` command is dropped

`p2_board.sdc` line 39-43 (frozen, hash `3FE16412...CF2ED`):

```tcl
set_clock_groups -asynchronous \
    -group {sys_clk50m pclkx1 pclkx5 mclk27 clk_a1} \
    -group {ddr_user} \
    -group {mipi_a_clk_hs mipi_a_byte_clk} \
    -group {mipi_b_clk_hs mipi_b_byte_clk}
```

With `mipi_b_byte_clk` trimmed away, TD cannot bind that group member; the
command no longer takes effect (the report still exposes the cross-domain
path groups that b18 does not have at all):

| path group | type | b19 SWNS | viol EP |
|---|---|---|---|
| `clk_a1 -> ddr_user` | Same Domain | **-0.898** | 576 |
| `ddr_user -> clk_a1` | Same Domain | **-1.338** | 281 |
| `sys_clk50m -> mipi_a_byte_clk` | Cross Domain | **-3.055** | 1870 |
| all self groups | Self | +0.069 … +36.490 | 0 |

In b18 the same report contains **only** self groups (cross-domain paths were
correctly cut). The three b19 groups are exactly the paths the frozen SDC
declares asynchronous: the bridge Gray-pointer FIFOs (`clk_a1 <-> ddr_user`),
the camera reset/status (`sys_clk50m -> mipi_a_byte_clk`), i.e. structural CDC,
not logic depth. Example worst path:
`u_camera/r_rst_n_reg` (sys50) -> `mipi_a_data_hs_p[3]_syn_2.rst`
(byte clock), data delay 1.478 ns against a 0.128 ns same-edge budget.

## 3. Real (self-domain) timing of the A candidate is clean at synthesis

`clk_a1` +0.069 ns (22,924 EP), `ddr_user` +0.425 ns (14,228 EP),
`mipi_a_byte_clk` +0.810 ns (3,116 EP), `sys_clk50m` +10.131 ns,
`pclkx1` +1.849 ns — 0 violated endpoints in every self group.
So the A-path candidate itself is not the problem; only the broken async-group
application creates negative slack. (b18 reference: SWNS +0.426 / routed +0.066.)

## 4. Why this is a planning/authorization decision, not a dev fix

The package freezes: 10 RTL files byte-identical, the top differing by exactly
one line, and `p2_board.sdc` byte-identical. Any workaround touches one of those
frozen items or the build script beyond "source paths + filelist guard", so the
developer stopped (no self-expanded scope).

Minimal options (planner to choose / authorize):

- **A. SDC token deletion (recommended).** In `set_clock_groups`, drop
  `mipi_b_clk_hs mipi_b_byte_clk` from the last `-group` (or delete that group).
  On this build the B clock does not exist; removing a non-existent group
  cannot relax any A-path. Leaves all real constraints intact. SDC hash changes;
  the "SDC byte-identical" gate needs an explicit, documented exception with the
  one-line diff.
- **B. Keep the B byte clock alive in RTL.** Add one inert observation of
  `b_byte_clk` (e.g. `(* keep *) wire bclk_obs = sel ? b_byte_clk : 1'b0;` or an
  unused register clocked by `b_byte_clk`) so `u_hs_clk_div.clkdivout` survives.
  Keeps the SDC frozen but changes more than the single CAM_SEL line and
  re-introduces B-domain loads (b18 had them at 1,645 fanout and met timing).
- **C. Build-flow re-assert.** In `01_build.tcl`, after `read_sdc`, re-issue the
  same four `set_clock_groups` groups without the two absent B clocks. Keeps
  RTL and SDC frozen, changes the build script beyond paths/guard.

Recommendation: **A** (smallest auditable delta, zero silicon effect) or **C**
if the SDC hash must stay frozen. B is the most invasive for no extra benefit.

## 5. What was completed before the stop

Static conformance C01-C19 all PASS (`merge-conformance-r0.txt`), including the
one-line diff proof and the CAM_SEL=0 A-branch equivalence (17 pairs).
Simulation T1/T2/T3/T4/T5/T6 were run from this candidate (see
`r0/sim/sim-results-b19-*.json`); T6 proves `sysstat=0x00000F1D` (bit12=0) and
the A signature on `u_a1`, T5 proves v6 field #13 bit12=0, T2 the 16-word native
readback, T3 the three P1 goldens byte-identical, T1/T4 the A-geometry chain and
the drop-R retry.

Downstream (b19 bit/CWC, board preflight, download, R14 alignment, COM8 300 s)
was **not** executed: no bit was generated, and reusing b18's B bitstream is
forbidden.
