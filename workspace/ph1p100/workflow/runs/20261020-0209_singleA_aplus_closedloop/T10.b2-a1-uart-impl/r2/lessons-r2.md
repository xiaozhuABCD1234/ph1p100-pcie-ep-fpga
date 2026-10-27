# T10.b2-a1-uart-impl r2 lessons

## What fixed the first critical path
The P1 store's wide read-data/duplicate comparator was fed directly by the bridge R FIFO
ERAM clk2q output. A one-deep skid register at the bridge output (same handshake) removed
that path: clk_a1->clk_a1 went from -0.060/32 EP to +0.116/0 EP. This is a legitimate
board-integration boundary register; no protocol/order change.

## What remains (board-level, not wrapper-fixable)
The synchronized reset `a1_rst_sync[2]` is a real launch flop into the frozen A+ core.
TD times its distribution through the core's FIFO/read-address mux to `smem.addrb`:
-0.193 / 331 endpoints. In the small top `rst_n` was a primary port, so the same path was
not timed (hence +0.275 vs -0.193). The path is inside `a1_deflate_core`/`a1_frame_top`;
fixing it needs a core reset/pipeline change or a real-async reset false path, both outside
r2's authorization. Do not hide it with a BUFG or an SDC false path without explicit
planner/user approval.

## Margin reality
The board PLL required period is 5.266 ns (setup 0.067), not 5.333; the clk_a1 data path is
+0.116 at synth. The small-top route lost ~0.23 ns (synth +0.275 -> routed +0.047). A
route-only P2 candidate would likely be negative even after a reset exception. A robust
+0.2 needs a new bounded A+ core/frame pipeline round (new P1 hash + regression).

## Process
- Remove the 224-ERAM camera preview before CWC: design 296 + CWC 30 > 300; after removal
  design 72 + 30 = 102. The phy aborts in `compile_watcher` if this is missed.
- Add `if {$syn_wns < 0} { exit 1 }` to the build tcl; it saved the 50-minute phy wait.
- The P1 r5 file was not modified; the P2 camera/bridge copies carry the r2 changes.
