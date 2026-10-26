# T10.b9-rawstore r0 result

**Status: PARTIAL / board gate BLOCKED.** G1 (simulation) and G2 (engineering)
are green; the single authorised SRAM download ran, but the A1 UART went
completely silent afterwards, so no v3 status packet was captured and the
raw-store question could not be answered this round. No second download was
attempted, no Flash.

| Gate | Result |
|---|---|
| G1 simulation | **PASS** (all cases) |
| G2 engineering | **PASS** (Routed WNS +0.102 ns, 0/24754 violations) |
| G3.1 board diagnostic | **NOT ACHIEVED** — 0 bytes on COM8 after the download |
| G3.2 board repair (raw_pub/enc/exported > 0) | **NOT EVALUATED** (no packet) |

---

## 1. What was implemented

### W1 status packet v3 (177 B, 43 x u32)

| field | source |
|---|---|
| #1..#23 | unchanged v2 fields (8 legacy + 15 camera) |
| #24..#43 | `raw_begin_ok, raw_begin_deny, raw_wr_beats, raw_wr_words, raw_wr_ptr, raw_wr_state, raw_rd_state, raw_slot_st, raw_slot_len0, raw_slot_len1, raw_rd_idx, raw_rd_words, raw_ar_valid, raw_ar_hs, raw_rv_cnt, raw_rd_open_ok, raw_rd_close, raw_abort_cnt, raw_deny_nofree, raw_deny_ddr` |

- Header `A5 5A B1 03` (LEN 177, VER 3), XOR8 over bytes 0..175.
- **Single-edge snapshot**: `rawsnap/camsnap/ssnap` are latched on the same
  `clk_a1` edge when the packet starts and held for the whole packet. No
  per-field resampling, no multi-bit CDC (all 20 new fields are `clk_a1`).
- Packer is `a1_uart_export.v` (**not** `dbg_uart.v`, which is the 50 MHz text
  logger inside `f9p_camera_display_core` and is unconnected on this board —
  planning file lists should be corrected next round).
- `a1_ddr_slot_store.v` gained 17 **observation-only** outputs (no behavioural
  change); the `cmp` instance leaves them open and synthesis drops them.

### W2 four defects

| ID | Fix |
|---|---|
| F1 | abort is pushed as its own CDC beat (`w_valid = crop_valid \| abort`) with `abort_hold` so a full FIFO cannot swallow it; A1 side issues `wr_abort`, frees the slot, counts `raw_abort_cnt`, and the next frame publishes normally |
| F2 | a rejected SOF latches `skip_frame` and the whole frame is consumed and counted (`raw_begin_deny` + `raw_deny_nofree/ddr`); camera side counts offers the FIFO refused (`fifo_ovf_cnt`). No half frame, no silent drop |
| F3 | `paxi_arvalid = af_rvalid && !ar_pending && ddr_rdy`, `af_pop = paxi_arvalid && paxi_arready`, `ar_pending` set by the AR handshake and cleared only by `paxi_rvalid && paxi_rready` |
| F4 | `camera_a1_uart_top.i_ddr_rdy` → raw store `ddr_ready`; P2 drives it from the existing 2-FF `ddrphy_rdy` synchroniser; `wr_begin` became a level held until the handshake (`begin_pend`) so a dynamic `ddr_ready` can no longer lose it |

One extra change was required and is documented in the RTL header: the 1 Hz
status packet used to be emitted only after the exporter had been idle for a
whole second. That only ever happened because the raw path was dead; with F1–F4
fixed the exporter is busy ~100 % of the time and the packet (the only
diagnostic channel) would starve. The request is now sticky (`sts_want`) and
takes the next **frame boundary**. Frame header/payload/CRC/Length are
untouched; the P1 goldens below prove it.

## 2. G1 evidence (`r0/sim/sim-results-b9.json`, `r0/sim/logs/`)

| case | result |
|---|---|
| `tb_crop_geom_real` (full 1920x1080) | 5,184,000 B byte-identical to the reference, `crop_geom_err=0` |
| p1 `micro8x2` | sha256 `fa513a2b…cef` — identical to the b5/b8 golden |
| p1 `mid64x8` | sha256 `ee61e620…789` — identical |
| p1 `full_grad` | sha256 `b992a8ad…da9` — identical, `err=0`, `raw_pub=1`, `read_words=129600`, `dup=0` |
| `tb_status_v3 +MODE=0` | 4 packets x 177 B, `bad_xor=0`, `field_k == 0xA1B2C300+k` |
| `tb_status_v3 +MODE=1` (tear) | one unique `(field_k - k)` per packet → single-edge snapshot proven |
| `tb_raw_store +CASE=full2` | 2 frames, 259,200 words read **byte-exact**, `ar_hs=259200`, `dup=0`, `drop=0`, `slot_len=2,592,000` |
| `tb_raw_store +CASE=abort` | `abort_cnt=1`, `dropped=1`, slot back to FREE, next frame publishes and reads |
| `tb_raw_store +CASE=nofree` | 3rd `wr_begin` refused for 200 cycles, 0 beats accepted, then 3 frames publish/read after release |
| `tb_raw_store +CASE=rdy` | `ddr_rdy` bursts low during readback: 129,600 AR handshakes for 129,600 words, byte-exact, `dup=0` |
| F3 **negative control** (`old_bridge/p2_ddr_bridge_b8.v`, same TB) | `RESULT case=timeout pass=0 errors=17` — the read returns word 0 forever |

## 3. G2 evidence (`r0/td/*.log`, `r0/td/*.rpt`)

- Synthesis: `SWNS=0.271 STNS=0.000 SLICE=18281 ERAM=72 REG=18859`.
- Routed: `SWNS=+0.102 ns  STNS=0.000  HWNS=+0.020  HTNS=0.000  VIOL_EP=0/24754`,
  `routed_timing_status.rpt` = `SWNS 0.102 / HWNS 0.020`, period WNS 2.200.
- Resources vs b8: slice +3.0 %, ERAM 0 %, reg +4.9 % — inside ±5 %.
- `02_bitgen.tcl` exit 0 (`P2_CANDIDATE_BIT_GENERATED_NO_DOWNLOAD`, STA setup
  0.102/0.000 hold 0.020/0.000 period 2.200); `03_cwc.tcl` exit 0, debug bit
  byte-identical to the parent.
- bit `sha256 950b6e4a867cf1aa87d11c4f084607f4254a82d335f5ed10891dcf74b66a5a06`
  (5,224,022 B); CWC `b9515f79…1cdd7`; BID `67c289a8…70a8b`.

## 4. G3 board — what happened (blocked)

1. `run_board_b9.ps1 -Secs 150` opened the COM8 listener **first**, then ran
   `download_sram_b9.tcl`. First attempt: the script was looked up in `r0/td/`
   while it lived in `r0/board/` → TD printed only its banner and **no download
   happened** (verified by the empty log). The pre-download capture of that
   attempt (kept as `com8_150s_oldbit_v2_probe.bin`) shows the then-running b8
   bit: **679 B = 7 x 97-byte v2 packets**, `A5 5A 61 02`, UART/baud fine.
2. Retry with the script in place: `B9D_DL_DEVICE=PH1P100`,
   `B9D_DL_OK mode=jtag(sram) bit=…/T10.b9-rawstore/r0/td/a1_board.bit`
   (`r0/board/download_sram_b9.log`). hwserver also logged
   `Error @ mpsse.cpp:90 : usb_open() failed` while COM8 was held open.
3. Same capture window: **679 B** (only the pre-download v2 packets, the port
   died at the moment of the download). A second, download-free 150 s window:
   **0 bytes** (`r0/board/captures_pwr/com8_150s.bin`, 0 B). Total silence.
4. Consequence: no `A5 5A B1 03` packet, `bad_len_ver=6` on the pre-download
   probe (all v2), `parse_status_v3.txt` = `NO_PACKETS`.

Interpretation (evidence-limited): the UART path and the board are fine before
the download, and the silence starts exactly at the download. Either the device
is no longer configured or the A1 domain is held in reset (a1_rst_n needs
`lock_a1 && ddrphy_rdy`); a v3 packet is emitted from `clk_a1` alone, so an
idle-high line after the download means the A1 domain is not running. The
FTDI-contention message suggests the JTAG download and the COM8 listener cannot
both own this single-FTDI device.

**No second download, no Flash, no re-capture beyond the two authorised 150 s
windows.** The board question is unanswered:
`raw 写入卡在哪/为什么没发布` — **undetermined this round**.

### Recommended next round (needs new authorisation)

1. Invert the order: `download` first, *then* open COM8 (or capture from a
   second host/second FTDI channel) so hwserver and the listener never contend.
2. If silence reproduces after a clean download, check `O_led[0]`
   (`hb_cnt[23]`, toggles iff `clk_a1` runs) and read `ddrphy_rdy` state to
   separate "unconfigured" from "A1 in reset".
3. Keep G1/G2 as the acceptance base: the RTL, the 177-byte packet and the
   candidate bit are frozen and re-usable without a rebuild.

## 5. Files

- `r0/changed-src/{a1_ddr_slot_store,camera_a1_uart_top,a1_uart_export}.v`
  (also unchanged copies of `a1_raw_crop`, `cam_diag_mailbox`, `a1_deflate_core`)
- `r0/td/src/{p2_a1_board_top,p2_ddr_bridge}.v`, `r0/td/{01_build,02_bitgen,03_cwc}.tcl`,
  `r0/td/a1_board.{bit,cwc}`, `r0/td/a1_board_inst.bid`, reports
- `r0/sim/*.v`, `r0/sim/run_sims_b9.py`, `r0/sim/sim-results-b9.json`, `r0/sim/logs/`,
  `r0/sim/caps/`, `r0/sim/old_bridge/p2_ddr_bridge_b8.v`
- `r0/board/{capture_com8.py,parse_status_v3.py,decode_frame.py,download_sram_b9.tcl,run_board_b9.ps1}`,
  `r0/board/captures_pwr/`, `r0/board/log/`, `r0/board/download_sram_b9.log`
- `r0/rtl-diff-r0.patch`, `r0/artifact-hashes.txt` (298 entries),
  `CANDIDATE-MANIFEST-b9-rawstore-r0.json`, `lessons-r0.md`
