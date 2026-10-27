# Board verdict — `H4_UNRESOLVED` (T10.b15-ddr-pace r0)

dev-plan §7.4 branch: **the read path still loses exactly one R per attempt** after
the strict-single-AR + `rready`-constant-1 fix. One SRAM download was made
(`B15_DL_OK`, `01:43` bit), COM8 was opened only afterwards for 150 s, and **no
second download / no re-capture** was attempted.

## 1. Capture facts (`board/captures/status_v5.json`, 151 packets, `bad_xor=0`, `noise=0 B`)

| field | first packet (`cap=80`) | last packet (`cap=4580`) | delta |
|---|---|---|---|
| `cap_frames` | 80 | 4,580 | **+4,500** |
| `raw_pub` | — | 4,580 | +4,500 |
| `enc_frames` | 0 | 0 | **0** |
| `exported` | 0 | 0 | **0** |
| `timeout_cnt` | 240 | 13,740 | **+13,500 = 3 / frame** |
| `retry_cnt` | 160 | 9,160 | **+9,000 = 2 / frame** |
| `giveup_cnt` | 80 | 4,580 | **+4,500 = 1 / frame** |
| `ar_cnt` | 290,420 | 17,014,541 | +16,724,121 |
| `r_cnt` | 290,180 | 17,000,801 | +16,710,621 |
| `rlast_cnt` | 290,180 | 17,000,801 | +16,710,621 |
| `stale_r_cnt` | 0 | **0** | 0 |
| `stale_guard_cnt` | 0 | **0** | 0 |
| `ar_cnt − r_cnt` | 240 | **13,740** | = number of attempts |
| `ar_cnt − rlast_cnt` | 240 | **13,740** | = number of attempts |

- `ar − r = ar − rlast =` **exactly the number of read attempts** in every
  packet: each attempt issues N ARs, receives N−1 R, and the last AR of the
  attempt is **never answered**.
- `stale_r = stale_guard = 0`: the missing beat **never appears** on the PAXI R
  channel, not even after the purge/guard window. The bridge cannot have
  swallowed it (rready is constant 1 and every owned beat is pushed: sim
  `b15_rready_low=0`, `b15_rf_ovf=0`).
- Reads per attempt ≈ `16,724,121 / 13,500 = 1,238.8` words of the 81,000-word
  raw slot (≈ 4 % of the frame) before the unanswered AR; the retry re-reads
  from word 0, so the failing point is deterministic per address.
- `crop_short=0`, `crop_geom_err` nonzero in camera fields (not this package),
  `sel=0`, `sysstat bit20=0`, `nack=0`.

## 2. What the fix did prove

- The bridge now holds **exactly one** AR in flight from the AR handshake to
  `rlast` (`b15_max_os=1`, `b15_ar_busy_hs=0`), issues an AR only into an empty
  read-data path, never lowers `paxi_rready` (`b15_rready_low=0`) and never
  drops a pushed beat (`b15_rf_ovf=0`).
- With a compliant single-beat responder the same RTL loses **zero** beats:
  full-frame S1 `ar = r = rlast = 210,685`, `timeout = retry = giveup = 0`,
  frame exported with four CRCs + strict zlib (`r0/sim/cases/b15chain/s1_full_clean`).
- Therefore the remaining loss is **not** an AR-ownership / rready /
  FIFO-overflow artefact of the bridge. It is **one AR that the DDR side accepts
  but never answers** (MC/PAXI-level, or an address the MC cannot serve).

## 3. Evidence for the next investigation

| item | value |
|---|---|
| `L_max` | 1 beat per AR (see `r0/diag/paxi-read-facts.md`) |
| unanswered ARs | 1 per attempt, deterministic |
| position in the slot | `rd_idx ≈ 1,238–1,239` of 81,000 (`ar_per_attempt = 1,210 → 1,238` while `cap_frames` grows) |
| sim `last_ar_addr` (final AR of a full frame) | `r0/sim/cases/b15chain/s1_full_clean/stats.txt` → `b15_last_ar_addr` |
| slot layout | `a1_ddr_slot_store.v`: `BASE_WORD + slot*SLOT_WORDS + rd_idx`; four-slot DDR map printed at sim time: `raw0=0..129599 raw1=129600..259199 cmp0=262144..343228 cmp1=343229..424313` |
| `ddr_rdy` | high during the whole capture (the write side of the same frames keeps working: `raw_pub = cap_frames`) |
| write traffic | 4,500 frames × 81,000 write words published with 0 drops → the DW path is healthy while the read of word ≈1,239 is not answered |

## 4. Decision

- `board = H4_UNRESOLVED` (FAIL for the b15 board gate, **not** a regression:
  b14 r0 measured the identical 3/2/1 pattern).
- No RTL, no SDC, no bitstream, no download retry inside this package; the
  candidate stays frozen and the parent T10 remains blocked.
- Recommended next step (planner): probe the MC read path with the frozen
  `ar/r/rlast/stale` triple plus a per-attempt `rd_idx` (v5 field is frozen, so
  this needs either a debug-only build or the `last_ar_addr` trace), and check
  whether the unanswered AR is reproducible at the same address with the write
  engine idle (write/read interleave on the same PAXI port).
