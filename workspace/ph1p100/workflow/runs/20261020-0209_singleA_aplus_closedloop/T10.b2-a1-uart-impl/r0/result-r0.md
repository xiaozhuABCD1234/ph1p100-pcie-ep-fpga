# T10.b2-a1-uart-impl r0 -- P2 board implementation result (BLOCKED at synthesis)

Status: **blocked** (no route, no bitgen, no CWC; no download/Flash).
Date: 2026-10-23. Same run 20261020-0209_singleA_aplus_closedloop.

## 1. What was built (P2 scaffolding, complete)

- Derived board project under `r0/td` with the board-verified camera/vendor tree copied
  from `D:/TD/work/csi2/prj/camera_csi_integrity_20261012_222159` (camera 71 files,
  vendor 91 files, 1.58 MB) and `board_p2.adc` (same pins as the verified board project).
- `src/p2_a1_board_top.v`: 50 MHz -> 187.5 MHz PLL; camera A raw tap/byte clock; P1
  `camera_a1_uart_top` (UART_DIV=1628 -> 115.172 kbaud at 187.5 MHz); DDR3 shell;
  187.5 -> dhi_clk bridge; MCU ROM init; A1 reset synchronized to PLL lock + ddrphy_rdy;
  LEDs/status with MARK_DEBUG (for ChipWatcher CWC).
- `src/p2_ddrmc_shell.v`: verified `ddrmc_x32` instance name `u_ddrmc_x32` (keeps the
  board SDC selectors) + APB window; PAXI owned exclusively by the A1 bridge.
- `src/p2_ddr_bridge.v`: 3 Gray-pointer async FIFOs (WF 283b, AF 27b, RF 256b);
  single-beat AW/W pair held until both ready, wstrb=all ones, wlast=1; one AR at a time.
- `src/p2_a1_pll.v`: VCO 50/3*90 = 1500 MHz, CLKC0/8 = **187.5 MHz exactly**.
- `src/f9p_camera_display_core.v` (P2 copy): only adds raw-tap/byte-clock outputs and
  drives HDMI from its own camera preview/test pattern (the DDR frame-buffer display path
  is intentionally not in P2). Camera/MIPI/I2C/HDMI logic otherwise unchanged.
- `p2_board.sdc`: 187.5 rename, async clock groups (camera byte/A1/DDR/HDMI), 8 Gray-bus
  `set_path_skew` constraints (P1 cam FIFO + 3 bridge FIFOs), only real-async false paths
  (`sys_rst_n`, `usr_uart_rxd`, existing startup MCLK handshake), `derive_clocks`.
- `01_build.tcl` (retiming on, ultra post-route, stop marker), `02_bitgen.tcl`
  (fail-closed STA + exactly 1 bitgen), `03_cwc.tcl` (exactly 1 `setup_debugger` CWC,
  compiled bit must equal the parent bit, copy to `a1_board.cwc`).
- Static compile of all new P2 RTL + the modified camera copy: ModelSim 10.5b `vlog -lint`
  **0 errors / 0 warnings**.

## 2. Blocking failure (TD elaboration, session 1)

`td_commands_prompt.exe ./01_build.tcl` (TG 2026.2 / 6.2.3.210850) fails synthesis in
5.05 s with:

```
HDL-8007 ERROR: net 'raw_rd_close_r' is constantly driven from multiple places
              in Y:/fpga/csi2/src/a1/camera_a1_uart_top.v(157)
HDL-5007 WARNING: found another driver here ... (298)
...
module 'camera_a1_uart_top' remains a black box due to errors in its contents
```

The same frozen file also has duplicate procedural drivers on `raw_rd_open` and
`raw_rd_take` (the skid always block at lines 162/166-167 and the sequencer always block
at 305/310/317/331/364/368 both assign them). ModelSim accepted the file (procedural
multi-driver on a reg), which is why the P1 simulations passed; TD rejects it.
The run then launched `phy_1` against the failed synth and waited in vain for
`.opt_route.begin.f` until the session was terminated (30 min wall). No reports, no
bit, no CWC were produced (`a1_board_Runs/syn_1/.read_design.error.f` exists).

Evidence: `td/syn_failure_excerpt.txt`, `td/a1_board_Runs/syn_1/run.log`,
`td/build_console.log`.

## 3. P1 hash verification (important input conflict)

All 8 frozen inputs measured byte-identical to the **r3 full hashes**:

| file | measured SHA256 | r3 |
|---|---|---|
| a1_raw_crop.v | ca2f5d16... | match |
| a1_ddr_slot_store.v | 8bab440d... | match |
| a1_ddr_arb2.v | 6513ad83... | match |
| a1_uart_export.v | 1d7ea9aa... | match |
| camera_a1_uart_top.v | 873cb98c... | match |
| a1_deflate_core.v | bf6af390... | match |
| a1_frame_top.v | 18d51b1b... | match |
| capture_async_fifo.v | 59dd6dcb... | match |

However, `CANDIDATE-MANIFEST-b1-a1-uart-integ-r4.json` lists
`camera_a1_uart_top.v = e88de0910ff0` and `a1_ddr_slot_store.v = 5196c07aed52`
while its narrative says `rtl_tools_drift=0` against r3. No file with either digest
exists anywhere in the workspace. The r4 table is therefore stale/incorrect (documentation
conflict), not a physical RTL drift. This must be resolved by the planner before the P1
evidence is re-bound to P2.

## 4. Why blocked rather than fixed

The P2 dispatch says "any P1 RTL hash drift -> stop immediately" and "do not change P1
frozen evidence". The required cleanup is a 3-line reset-ownership change in
`camera_a1_uart_top.v` (remove the duplicate `raw_rd_open` / `raw_rd_close_r` /
`raw_rd_take` resets/defaults from the skid always block; the sequencer block already
drives them). It is semantically neutral, but it changes the frozen P1 hash and the P1
core evidence would need re-binding. This role cannot self-authorize that; returning
blocked to the planner is the rule-compliant action.

## 5. Minimal next step / resume

1. Planner/user authorizes a bounded P1 repair (file `fpga/csi2/src/a1/camera_a1_uart_top.v`,
   remove the duplicate drivers at lines 162 and 166-167; no protocol/frame/CRC/DEFLATE
   change), or provides the missing `e88de0910ff0` file.
2. Re-freeze P1 hashes (re-run the quick 8x2/64x8 sim if required).
3. Resume P2 at `r0/td/01_build.tcl` (2 synth attempts / 2 route / 1 bitgen / 1 CWC remain).
   The P2 wrapper/constraints/flow are ready and statically compile-clean; only the frozen
   P1 reset cleanup is missing.

## 6. Budget / boundaries

- Dev: ~67 tool calls (dispatch limit 60 -- budget exhausted; stopped rather than retry).
- TD: 1/3 sessions, ~30 min wasted waiting after the failed synth; synth 1/3 (elaboration
  failure), route 0/2, bitgen 0/1, CWC 0/1, download 0.
- No .bit, no .cwc, no download, no Flash; A+ core `bf6af390`, frame `18d51b1b`,
  SDC `227dd39e` untouched; no P1 RTL file modified.
