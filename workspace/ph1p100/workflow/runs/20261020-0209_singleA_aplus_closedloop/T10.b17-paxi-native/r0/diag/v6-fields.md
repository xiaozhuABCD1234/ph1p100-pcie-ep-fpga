# T10.b17 status packet v6 (273 B / 67 fields)

Frozen wire format; frame header/CRC/zlib path untouched.

## Packet

| item | value |
|---|---|
| total | **273 B** = 4 B header + 67×u32 LE + XOR8 |
| header | `A5 5A 11 06` (`LEN=273` low byte 0x11, `VER=6`) |
| XOR | XOR of bytes 0..271, stored at byte 272 |
| snapshot | all 67 fields latched on one `clk_a1` edge at a frame boundary |
| compatibility | parser accepts v5 (241 B / 59 / VER=5) and v6 |

`a1_uart_export.v`: `STS_LEN=9'd273`, `STS_LAST=9'd272`, `STS_VER=6`,
`sidx/sbyte_i` 9 bit, `extsnap` 768 bit, `allsnap` 2144 bit.

## Field order

`#1..#59` are byte-for-byte the v5 fields (legacy 8 + camera 15 + raw store 20 +
read path 16).  Appended:

| # | name | source |
|---:|---|---|
| 60 | `last_issued_ar_addr` | last AR handshake, native PAXI address (27 bit, zero-extended) |
| 61 | `last_issued_ar_low3` | its `[2:0]` (must be 0) |
| 62 | `timeout_ar_addr` | `purge_evt && ar_busy` latched last AR address |
| 63 | `timeout_ar_low3` | its `[2:0]` |
| 64 | `same_aw_ar_cnt` | cycles with AW and AR handshake in the same `clk_ddr` cycle |
| 65 | `same_w_ar_cnt` | cycles with W and AR handshake in the same cycle |
| 66 | `inflight_state` | `[0] ar_busy [1] aw_seen [2] w_seen [3] wstate [4] ddr_rdy [5] rd_hold [6] rf_path_empty [7] paxi_arvalid` |
| 67 | `diag_flags` | `[0] timeout_ar_valid [1] same_aw_ar_seen [2] same_w_ar_seen [3] oob_addr_seen [4] low3_nonzero_seen [5] wstrb_nonzero_seen` |

## Semantics

- `last_issued_ar_addr` updates on every AR handshake.  It is the **native**
  address already multiplied by 8; word index = `addr >> 3` (debug conversion
  only, never written into the packet).
- `timeout_ar_addr` latches `last_issued_ar_addr` in the `clk_ddr` cycle where
  the b13 abort purge fires while `ar_busy=1`.  `timeout_ar_valid` is sticky
  until a successful `rvalid && rready && rlast` or reset; the address keeps
  the last failed value.
- `same_*_seen` / `oob_addr_seen` / `low3_nonzero_seen` / `wstrb_nonzero_seen`
  are sticky, reset by `rst_n`.
- Clean board run: `diag_flags` = 0 and `same_*_cnt` = 0.  A still-failing frame
  leaves `timeout_ar_valid=1` and the exact failed native AR address/low3.

## Diagnostic bus packing (bridge `dbg_a1`, 512 bit)

Old 256-bit layout is unchanged:

```text
[255:224] purge_cnt      [223:192] stale_guard_cnt  [191:160] stale_r_cnt
[159:128] rlast_cnt      [127:96]  r_cnt            [95:64]   ar_block_cnt
[63:32]   ar_cnt         [31:0]    br0
```

New 256-bit block (high to low):

```text
[511:480] diag_flags          [479:448] inflight_state
[447:416] same_w_ar_cnt       [415:384] same_aw_ar_cnt
[383:352] timeout_ar_low3     [351:320] timeout_ar_addr
[319:288] last_issued_ar_low3 [287:256] last_issued_ar_addr
```

`cam_diag_mailbox` instance `W=512` (module body unchanged);
`camera_a1_uart_top.i_dbg_bridge` 512 bit, `sts_ext_bus` 768 bit;
`p2_a1_board_top.dbg_bridge` 512 bit; `a1_uart_export.sts_ext` 768 bit.

## Verification

- `r0/sim/tb_status_v6.v`: 4 back-to-back packets, 0 bad header/XOR/field,
  `B17_V6_RESULT pass=1`.
- All chain cases: every packet 273/6/67, `last_ar_low3=0`, `diag_flags`
  bits1..5 = 0 (S3 allows bit0 while a timeout is being recovered).
- `parse_status_v6.py` also accepts a b15 v5 capture (241/59/VER=5), and rejects
  a corrupted XOR (see `r0/sim/logs/` v5-fixture test and board parser).
