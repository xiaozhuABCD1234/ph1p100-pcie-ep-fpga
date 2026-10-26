# T10.b2-a1-uart-impl r3 lessons

## Reset-mux cleanup needs the register moved out of the synchronous reset block
Deleting the reset assignments alone is not enough: inside `always @(posedge clk) if (!rst_n)
... else ...`, an address register that is only assigned in the `else` gets a reset-derived
**enable**, and TD still times reset -> memory address. The frame `rd_addr` had to move to a
separate reset-free always block (seeded in D_IDLE before rd_en). After that the smem path
disappeared; the new worst path was the core htab ERAM -> bm_b (+0.012).

## Board reset CDC: do not launch a clk_a1 async reset from a 50 MHz flop
Using `por_n` (50 MHz boot counter flop) as the async reset for clk_a1 synchronizers caused
HWNS -5.248/4 EP (removal) on route1. Drive the async reset from the `sys_rst_n` board pin
and let the 2FF/3FF chain + PLL-lock/DDR-ready data hold the reset; route2 hold became +0.020.

## Thin margin
+0.012 ns setup is positive but thin (<+0.2 target); route1/route2 variation and the
188 MHz Fmax leave no robustness claim. Record it explicitly; do not call it robust.

## Practical
- Remove the 224-ERAM camera preview before CWC: design 296 + 30 > 300; after removal
  design 72 + CWC 30 = 102.
- TD 2026.2 `report_cwc_status` has no `-file` option; use `report_cwc_status` with no args.
- `setup_debugger -prj a1_board` produces `cw/compiled.{bit,cwc}`; verify byte equality with
  the parent bit before copying to `a1_board.cwc`.
- Keep the build tcl's synth-negative fail-fast and the BOM-free ASCII write; both saved a
  long phy wait / invalid-command failure.
