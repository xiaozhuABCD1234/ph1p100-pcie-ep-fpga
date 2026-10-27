# result-r0 -- T10.b20-a-timing (A-only abort->smem-address repair on the b19 A candidate)

Run `20261020-0209_singleA_aplus_closedloop`, package `T10.b20-a-timing`, round **r0**.
Developer: general (fpga-dev delegated). Date 2026-10-26.
Parent `T10` stays blocked/active; this package does not close it.

**Status: `caveat_thin_margin` for engineering + sim PASS, `board=blocked` (FTDI/COM8
physically absent at board time, 0 downloads, 0 captures).**

| gate | value | verdict |
|---|---|---|
| delta | 10/11 changed-src byte-identical to b19; only `a1_frame_top.v` differs; SDC `0888b6a7...` / ADC `1cb30346...` identical | PASS |
| C01-C20 | `r0/merge-conformance-r0.txt` `MERGE_SUMMARY checks=20 fail=0 ALL_PASS` | PASS |
| T1 full A chain | `cycles=37,465,298` (exact), `cmp_words=648,677`, `cmp_writes=81,085`, `read_words=129,600`, `dup=0`, `exp_bytes=2,594,706`, `ticks_in_frame=1245`, `status_grants=253`, `source_groups=2,117,472`, `line_rises=2,192`, `frame_rises=1`, four CRCs + strict zlib | PASS |
| T2 native 16-word | 5/5 cases pass (mask/addr/conc/b15-neg) | PASS |
| T3 P1 goldens | micro8x2 `FA513A2B...EDEF`, mid64x8 `EE61E620...9789`, full_grad `B992A8AD...DADA9` byte-identical | PASS |
| T4 drop-R retry | T4a `cycles=89,050`, T4b `cycles=106,094` (delta 0/0, allowed 0..+16), `timeout=retry=1`, `giveup=0`, `exported=1/3`, `cmp_drop=1`, four CRCs + zlib per frame | PASS |
| T5 v6 | 4 packets, `273/6/67`, `bad_xor=0`, `f13=00000f01` bit12=0, bit20=0, lane F | PASS |
| T6 real top CAM_SEL=0 | `sysstat=0x00000F1D`, `u_a1.i_a_pixel=a5a5a5a5a5`, `clk_edges=67`, A selected, B signature absent | PASS |
| synthesis | `SWNS +0.204 / STNS 0.000`, slice 18,766, ERAM 72, reg 20,090 (b19 +0.127) | PASS (route precondition >= +0.127) |
| routed | `SWNS +0.012 / STNS 0.000 / HWNS +0.020 / HTNS 0.000`, **0 violated endpoints**, slices 25,061, RAMs 102, DSP 0 | **thin-margin caveat** (+0.012 in +0.003..<+0.05) |
| cone break | 0 routed paths `a1_abort_reg -> smem*.addrb`; worst clk_a1 now `u_core/sdata_ptr_reg[1] -> u_core/state_reg[4]` +0.012 | PASS (STA evidence) |
| bitgen/CWC | 1 bitgen + 1 CWC, fail-closed `SETUP 0.012/0.000 HOLD 0.020/0.000 PERIOD 2.200`; `compiled.bit|.cwc` == parent; `<phy_eram` present, no incomplete `<logic_eram/>` | PASS |
| board | preflight `FTDI_PRESENT=0`, `PORTS=COM4,COM3` (COM8 gone); 0 downloads, 0 captures | **blocked** |

## 1. The one change

`r0/changed-src/a1_frame_top.v` (`cda28c94...2160c`) vs b19 (`0064607a...27109`):
a single 1-bit register `abort_d` moves the **drain-side** teardown
(`dstate`/`bank_busy`/`dblk`) one cycle after the abort, so the drain/ERAM
read-address cone is never selected by the raw `abort`. The protocol side stays
immediate: `frame_abort`, `killed`, `frame_active`, `istate`, `core_abort`,
`in_ready`, `scnt`, the input counters. `first_byte` is cleared on abort so the
already-aborted core cannot accept a stale SOP in the extra cycle. Diff: 27 added
/ 4 removed lines in 4 hunks (`r0/diag/a1_frame_top-b20.diff`), no port, no
`ifdef`/`force`, no CRC/stat/output/packing/reset change (C20 22 frozen anchors equal).

## 2. Cycle neutrality (hard proof)

T1 reproduces the b19 counters exactly, including `cycles=37,465,298` and
`cmp_words=648,677`; the abort path only moves on aborted frames, where T4 shows a
0-cycle delta (allowed 0..+16). No normal-path bubble, no CRC/length/packing change.

## 3. Timing (thin margin, declared)

* synth worst path moved off the abort cone: `u_cmp_store/wcnt_reg[0] -> u_cam_fifo/rbin_reg[9]` +0.204;
  no `a1_abort_reg` path in the synthesis worst-10;
* routed: 0 violated endpoints, `SWNS +0.012`; the routed violated-path list is
  empty, so it contains 0 `a1_abort_reg -> smem.addrb` paths; the new worst clk_a1
  path is `u_a1/u_a1/u_core/sdata_ptr_reg[1]_syn_2.clk -> u_a1/u_a1/u_core/state_reg[4]_syn_102.imb`;
* per-group worst (all sections of the report, not just the first): clk_a1 +0.012,
  ddr_user +0.012, mipi_a_byte_clk +0.625, sys_clk50m +7.809, pclkx1 +2.086, all
  other groups 0 violations;
* **+0.012 ns is a thin margin** (`timing_caveat=thin_margin_+0.012`): valid for
  bitgen/board under the frozen gate, but no "robust timing" claim. b19 was
  -0.098 with 10 listed violations (11 in the QoR table), so the repair gained
  ~0.110 ns routed (+0.077 ns at synthesis).
* Structural caveat: a LUT-agnostic netlist reachability walk still reports
  abort-reachable `smem*.addrb` nets (`r0/diag/cone-check-routed.txt`,
  `cone_trace_b20.py` finds a 4-LUT route). That walk over-approximates (it follows
  any combinational output of a reached cell regardless of the LUT function) and
  is **not** used as proof; the authoritative cone evidence is the routed STA
  (no such path in the reported worst endpoints, all groups clean).

## 4. Board (blocked, no download, no capture)

`r0/board/log/board_blocked.txt`: at 22:17:04 the FTDI `0403:6042` device was gone
(`FTDI_PRESENT=0`, `PORTS=COM4,COM3`); at 22:00 the same preflight had found the
device and an openable COM8. The single-shot script stopped before any download
(`downloads=0`, `captures=0`), which is the frozen rule for an absent cable. No
claim is made about A pixels. The frozen bit/CWC are ready; resuming needs the
board connected + powered, then
`powershell -File r0\board\run_board_b20.ps1 -Secs 300 -ResetPulse yes`
(1 SRAM download, R14 prompt window, one 300 s COM8 capture).

## 5. Budget used

dev ~57 min / 44 tool calls; TD sessions 3 (build, bitgen+CWC, board preflight);
synth 1, route 1, bitgen 1, CWC 1, downloads 0, Flash 0.
