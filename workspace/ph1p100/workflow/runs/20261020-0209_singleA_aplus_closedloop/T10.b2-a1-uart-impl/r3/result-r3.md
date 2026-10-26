# T10.b2-a1-uart-impl r3 -- P2 candidate (ready for test; thin +0.012 ns setup caveat)

## 1. P1 r6 cleanup + regression (PASS)
Authorized option A reset-mux cleanup:
- `a1_frame_top.v`: reset removed from `rd_addr`, `dq_r`, `smem_waddr_r`, `smem_wdata_r`;
  `rd_addr` moved to a reset-free always block (seeded in D_IDLE before `rd_en`).
- `a1_deflate_core.v`: reset removed from `raddr`, `praddr`, `w0/w1/w2/x1_r`, `s1_pos_r`,
  `ext_raddr`, `ext_faddr`, `cmem_raddr` in both always blocks; control/state/valid/
  write-enable resets kept.
- Final hashes: core `d4b79961...88de`, frame `c8b24775...65b`, P1 top `17793341...ac88`.
- Regression: 8x2 / 64x8 / full 1920x1080 all 0 mismatch, four CRC true, zlib_ok, dup=0,
  raw_len 2,592,000, stream_len 40,032, full raw_sha256 `2f34e253...d355e830`. No X/half-frame.
  P1 r6 manifest: `T10.b1-a1-uart-integ/CANDIDATE-MANIFEST-b1-a1-uart-integ-r6.json`.

## 2. P2 r3 route/STA (route2)
- Route1: setup passed but hold HWNS -5.248 / 4 EP from the 50 MHz `por_n` async reset into
  clk_a1 (removal). Fixed by driving the A1 reset synchronizers' async reset from the
  `sys_rst_n` board pin (data-gated by PLL lock/DDR ready).
- Route2: **SWNS +0.012 / STNS 0 / 0 of 19,754 endpoints; HWNS +0.020 / HTNS 0**.
- CC-From/To = no/no for the main clocks; 0 combinational loops; 0 unclocked clock pins.
- Resources: LUT6 18,698; reg 25,200; **ERAM 102/300 (design 72 + CWC 30)**; DSP 0; IO 110/286.
- **CAVEAT**: +0.012 ns is a thin setup margin, well below the +0.2 target; not robust.
  Recorded for the planner/tester; no silent claim of a robust margin.

## 3. Bitgen + CWC (exactly one each, no download)
- `a1_board.bit` SHA256 `d1ac8726e84f6584d49979dd223d6e8c484e559bf2a3ad3b2302972c58efc142`
  (5,224,022 B).
- `a1_board.cwc` SHA256 `37b608540f7924f60a09db5ba2b543334db1259ef69f2a1c982cf161cbc8b25c`
  (110,248 B); `cw/compiled.bit` and `cw/compiled.cwc` byte-identical.
- `a1_board_inst.bid` SHA256 `3de68e686e419e20cd85a332e40caa740b9aae55d666c3e8816ef7033d04f213`
  (96,832 B).
- Tool: TD Release_2026.2 / 6.2.3.210850, PH1P100SBG484 -3.
- No download, no Flash, no PCIe/RK/dual/G4.

## 4. Boundaries
- Only the authorized reset-mux cleanup touched the A+ core/frame; protocol/frame/CRC/DDR
  layout/reference/SDC `227dd39e` unchanged. No false path/multicycle.
- P1 r6 boundary unchanged (MODE=2/3/4, store-only max length, MODE=1 shortened, tail,
  mid-write reset).

## 5. Retest
Independent P2 engineering tester: parse routed STA/CDC/resources, re-run P1 r6 regression,
verify bit/CWC/BID and compiled equality, and explicitly record the +0.012 thin-margin
caveat vs +0.2. No download/Flash.
