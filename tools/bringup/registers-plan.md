# R10F bring-up register plan (T11.runA-bringup-kit)

Status: **frozen for offline use; register read channel NOT established.**
The current candidate bit (`e81d353b...2b9a`) has no proven machine-readable
user-register path (B1 result: blocked). This plan is the checklist to run once
a channel is recovered. It is not evidence that any register was read.

Truth sources: `docs/protocol/rka1-r10f-v1/contract/registers.json`,
`rtl/ep_side/img/ep_bar_win.v` (read-only header/decode),
`fpga-design-guide.md` s2/s5.2, `board-selfcheck/channel-notes.md`.
Rule ids refer to `expected_rules.json`.

## 1. Register table

| offset | name | access | expected / decode | rule | source |
|---|---|---|---|---|---|
| 0x040 | MAGIC | RO | must equal `0x50434946` ("FICP"); otherwise stop | R01 | contract offset 64; ep_bar_win.v:350 |
| 0x044 | CTRL | RW | bits 0..3 enable/trigger/reinit_toggle/test_pattern, bit4 reserved reads 0, bit5 ddr_enable, bit6 push_enable, bit7 push_source, bit8 camera_ab; bits 9..31 reserved | R02 | contract ctrl_bits; ep_bar_win.v:354 |
| 0x048 | IMG_STATUS | RO | raw snapshot only; legacy bit map is not frozen for this kit | - | contract offset 72 |
| 0x04C | TEST_FRAME_CNT | RO | raw counter snapshot (no rule) | - | contract offset 76 |
| 0x064 | LEGACY_VERSION | RO | raw snapshot only | - | contract offset 100 |
| 0x080..0x098 | CAM_STAT_080..098 | RO | packed legacy camera status words; keep raw values; bit map not frozen (guide s5.2 lists lane_valid/cfg_done/in_frame/in_line/tap as a hint only) | - | ep_bar_win.v:459 region |
| 0x0A0 | DDR_SEQ_A | RO | frame sequence, monotonically increasing; also the precondition for A-path checks | - | ep_bar_win.v header 0xA0 |
| 0x0A4 | DDR_BASE_A | RO | byte base of the published frame, 128B aligned, nonzero after first frame | R07, R16 | guide s2; ep_bar_win.v header 0xA4 |
| 0x0A8 | DDR_STATUS_A | RO | bit0 valid, bit1 busy, bit2 err, bit3 alive, bit4 cal_done, [31:16] err_cnt; bits [15:5] zero | R09 | ep_bar_win.v header 0xA8 |
| 0x0AC | DDR_LEN_A | RO | must equal 2,592,768 after a frame | R05 | guide s2; ep_bar_win.v header 0xAC |
| 0x0B0 | PUSH_DST_LO | RW | host-owned staging; read back raw, no rule | - | ep_bar_win.v header 0xB0 |
| 0x0B4 | PUSH_DST_HI | RW | host-owned staging; read back raw | - | ep_bar_win.v header 0xB4 |
| 0x0B8 | PUSH_DB_LO | RW | host-owned doorbell staging; read back raw | - | ep_bar_win.v header 0xB8 |
| 0x0BC | PUSH_DB_HI | RW | host-owned doorbell staging; read back raw | - | ep_bar_win.v header 0xBC |
| 0x0C0 | PUSH_DONE | RO | completed push count (1-based); no rule beyond precondition | - | ep_bar_win.v header 0xC0 |
| 0x0C4 | PUSH_STATUS | RO | bit0 busy, bit1 last_ok, bit2 doorbell_sent, bit3 ddr_alive, bit4 ddr_cal_done, [31:16] err_cnt; bits [15:5] zero | R11 | ep_bar_win.v header 0xC4 |
| 0x0C8 | PUSH_ERR | RO | 0 normal, 1 dst unconfigured, 2 tl_tx_wait timeout, 3 AXI non-OKAY, 4 doorbell unconfigured | R12 | ep_bar_win.v header 0xC8 |
| 0x0CC | PUSH_TLP_CNT | RO | MWr count of the last frame; normally 2400 for 1080p | R15 | ep_bar_win.v header 0xCC |
| 0x0D0 | CAM_DIAG_A | RO | raw diagnostic snapshot | - | ep_bar_win.v header 0xD0 |
| 0x0D4 | CAM_TAP_B | RW | raw tap control/readback | - | contract offset 212 |
| 0x0D8 | CAM_DIAG_B | RO | raw diagnostic snapshot | - | ep_bar_win.v header 0xD8 |
| 0x0DC | CAM_DROP_A | RO | `{notack[15:0], stuck[15:0]}` | - | ep_bar_win.v header 0xDC |
| 0x0E0 | DDR_SEQ_B | RO | B-path sequence | - | ep_bar_win.v header 0xE0 |
| 0x0E4 | DDR_BASE_B | RO | B-path base, 128B aligned | R08 | ep_bar_win.v header 0xE4 |
| 0x0E8 | DDR_STATUS_B | RO | same bit map as 0x0A8 | R10 | ep_bar_win.v header 0xE8 |
| 0x0EC | DDR_LEN_B | RO | must equal 2,592,768 after a B frame | R06 | ep_bar_win.v header 0xEC |
| 0x0F0 | CAM_DROP_A2 | RO | `{last_beats[15:0], last_wcnt[15:0]}` | - | ep_bar_win.v header 0xF0 |
| 0x0F4 | CAM_DROP_A3 | RO | 24'd0 + verdict: bit0 p_bad, bit1 no EOF, bit2 word count mismatch, bit3 beat count mismatch, bit4 axi_err, bit5 pub_ok; bits [31:6] zero | R14 | ep_bar_win.v header 0xF4 |
| 0x100 | DMA_CAP_BYTES | RW | transport capacity; 0 before configuration, otherwise >= frame bytes (2,592,768) | - | contract extension offset 256 |
| 0x104 | SESSION_ID | RW | nonzero session identity required before arm | - | contract extension offset 260 |
| 0x108 | TX_CMD | W1 | write-only command; read must return 0 | R17 | contract extension offset 264 |
| 0x10C | ACK_SEQ | RW | staged held completion sequence | - | contract extension offset 268 |
| 0x110 | ACK_SESSION | RW | staged held session | - | contract extension offset 272 |
| 0x114 | TX_STATUS | RO | bit0 armed, bit1 busy, bit2 held, bit3 rejected/error, bit4 draining; bits [31:5] zero | R13 | contract extension offset 276; ep_bar_win.v header 0x114 |
| 0x118 | EXT_MAGIC | RO | must equal `0x31414B52` ("RKA1"); `0xDEADBEEF` means the extension is absent, stop | R03 | contract extension offset 280; ep_bar_win.v:499 |
| 0x11C | EXT_VERSION | RO | must equal `0x00010000` (major 1, minor 0) | R04 | contract extension offset 284; ep_bar_win.v:500 |
| 0x120 | CSI_DIAG_A | RO | packed `{good[31:24], bad[23:16], hdr_err[15:8], crc_err[7:0]}`; human diagnostic only | - | ep_bar_win.v header 0x120 |
| 0x124 | CSI_DIAG_A2 | RO | `{last_lines[31:16], last_wc[15:0]}` | - | ep_bar_win.v header 0x124 |
| 0x128 | CSI_DIAG_B | RO | same as 0x120 | - | ep_bar_win.v header 0x128 |
| 0x12C | CSI_DIAG_B2 | RO | same as 0x124 | - | ep_bar_win.v header 0x12C |

Notes
- The 0x120/0x124 field order follows the RTL concatenation (leftmost field is
  the most significant byte/halfword). Confirm against the host decoder before
  treating a mismatch as a hardware fault.
- 0x080..0x098 are grouped because the legacy packed bit map is not frozen in
  this kit; keep the raw dwords in the run record.
- Register offsets are dword offsets in BAR0 (4-byte aligned). Do not pass byte
  addresses.

## 2. Channel and command templates

### 2.1 BW/JTAG (verified by B1, read-only + SRAM download only)

Verified sequence (B1, 2026-10-18):
```
hwserver.exe -r -s 5555 -f 12 -v -w 5556 -i 0
bw_commands_prompt.exe
connect_cable -host_name 127.0.0.1:5555 -open
read_device_id
connect_cable -close
download -bit <ASCII_PATH> -mode jtag -spd 7 -cable 0
```
Observed success markers: `PRG-2014 : Chip validation success: PH1P100`,
`download` rc=0, duration about 28-40 s. `-mode jtag` means PROGRAM SRAM.
Constraints learned in B1: the bit path must be ASCII; invoke scripts by
relative path after `Push-Location`; pass host paths through environment
variables. A stray `Error @ mpsse.cpp:90 : usb_open() failed` can appear next to
a successful download and is not a failure by itself.

**Do not** use any flash/SPI/efuse/SVF command. If such text appears in a
command list, stop and record it.

### 2.2 UART (architecture-unusable on this bit)

Reference template from `doc/uart_cmd_file_pcie.txt` (115200, 8 data bits, odd
parity, 1 stop bit, hex mode), first APB read example:
```
46 45 44 43 42 41 00 00 40 90 00 00 00 00
```
B1 sent this on COM8 before and after download and received 0 bytes. Root
cause: `rtl/ep_side/ph1p_pcie_ep_top.v` ties UART rx to 1 (L155/L757); the
board rxd pin is reassigned to the MIPI sub-card. Status: unavailable.

### 2.3 JTAG register access (doc check: unavailable)

`JTAG_REG_ACCESS`, `JTAG_REG_ACCESS_VEC` and `JTAG_AXIS_APB_ACCESS` appear only
as command names in `board-selfcheck/logs/03-bw-command-list.txt`. No
documentation of their arguments or read/write semantics was found in
`doc/`, `docs/`, `tools/`, the repository README, or the TD install text
documentation (searched 2026-10-18). The candidate bit contains no CWC/debug
core. Possible write side effects are unknown. Status: **unavailable; do not
invoke** until a vendor document defines a read-only user-register path.

### 2.4 PCIe host (not available this round)

No PC/RK host with the driver is attached; RK driver is not built. Reading
BAR0 registers through a host is the preferred recovery path (option a).

## 3. Recovery options (owner decision)

(a) Provide a PCIe host (RK or PC) that can read BAR0 (preferred).
(b) Authorize a new candidate bit with CWC/debug core (requires new freeze and
    G1/G2; the current bit is not rebuilt this round).
(c) Obtain vendor documentation for a read-only JTAG user-register path; then
    a bounded read-only check may be dispatched by the planner.
(d) Authorize a bring-up bit with rdx/lane loopback (requires wiring changes;
    the agent does not perform physical operations).

## 4. Unavailable items (must be stated in every report)

| item | status | evidence |
|---|---|---|
| UART register/memory commands | unavailable (architecture) | B1 channel-notes s2; RTL L155/L757 |
| BW JTAG register access | unavailable (no documented read-only semantics) | B1 log 03; doc search 2026-10-18 |
| PCIe host BAR0 read | unavailable (no host/driver) | B1 dev-result s5 |
| CWC/debug core | absent in candidate | B1 channel-notes s4 |
| Register values 0x040/0x118/0x11C | blocked (not read) | B1 dev-result s1 item 6 |

## 5. Hand-off rule

Do not paste this table into a report as "verified". A report may only claim a
register value when a run record produced by `parse_dump.py` (or an equivalent
decoder) binds that value to a channel, a timestamp and an input hash.
