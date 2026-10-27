# Expected G1 — brd-p1-r3-20261027 (local simulation only, NOT a hardware guarantee)

Geometry of the local G1 run: camera 128×96, ROI 64×48 (768 packed groups),
slot words 1024, slot byte base `0x1_0000`, one frame per capture.

## 0. Stimulus contract (frozen for TB / model / tester)

ROI rows `r ∈ [16,63]`, groups `g ∈ [8,23]`, `v = (r*32 + g) & 0x3FF`; each
40-bit beat carries **four identical** 10-bit pixels `v`; packed byte offset
`((r-16)*16 + (g-8))*5`; `byte0..3 = v[9:2]`; `byte4 = {v[1:0] x4}`; raw length
`48*16*5 = 3840 B`; first group `v = 520` (bytes `82 82 82 82 00`); last group
`v = 1015` (bytes `FD FD FD FD FF`).

## 1. Independent golden (judged)

Source: `evidence/gen_expected_raw.py` in the r3 work root (contract only; reads
no DUT output, no `pk_bytes`, no slot stream) and `evidence/golden-r3.md` /
`golden-r3.json`.

| item | expected |
|---|---|
| expected raw | 3840 B, SHA256 `FBA49D330DB9196A9BD9B8F29419A5603CEF600FE7D08F73708674F4C3C5111E` |
| expected raw Adler-32 | `392578F9` (last 4 bytes of the zlib stream, big-endian) |
| expected raw CRC-32 | `7269454A` (= `st_xform_crc`/`st_raw_crc` in bypass, and the header `xform_crc`/`raw_crc`) |
| decompressed raw | **byte-identical to `expected_raw.bin`** (primary criterion) |
| decompressed length | `= xform_len = 3840` |
| zlib | `zlib.decompress(slot[0:stream_len])` succeeds with the standard library |
| `frame_bytes` | `align_up(stream_len, 4096)` and `= 4096` |
| MWr | `ceil(frame_bytes/128) = 32` transactions, `mwr_bytes = frame_bytes = 4096` |
| doorbell | exactly 1, payload = `held_seq` |
| slot base | byte `0x1_0000` (word 2048), first two bytes `78 9c`; byte 0 stays 0 |
| A1U1 header (host-built) | magic `A1U1`, version 1, hlen 44, flags 0 (bypass) / 3 (PREP=1,PRED=1), W=64, H=48, raw_len 3840, xform_len 3840, stream_len = len(slot), `frame_id` starts at 1, header CRC over bytes 0..39, payload = slot |
| exported | `st_exported = 1` |
| X / deadlock | 0 X hits, no timeout, arbiter late = 0, switch = 0 |
| ARM | early (before publish) and late (after publish) both export exactly once |

r3 measured values (candidate-bound, repeatability only, **not** a contract):
bypass `stream_len = 2470`, `hcrc = A5ECBAD9`, `stream_crc = 9909B919`
(SCEN0 = SCEN3 = SCEN4, byte-identical slot stream); PREP=1/PRED=1
`stream_len = 538`, `hcrc = 69C48065`, `xform_crc = 7883ABAF`.
`hcrc` changed vs r2 (`5436BF73`/`981E85CF`) only because r3 starts the capture
identity at 1 (`frame_id 0→1`); the compressed stream is unchanged. Do **not**
hardcode these in P2: the compressed length belongs to the DUT's own RFC1950
encoder and changes with the stimulus.

## 2. Negative

| case | expected |
|---|---|
| missing EOF (last ROI row absent) | `committed=0`, `published=0`, `exported=0`, 0 TLP, 0 doorbell, frame aborted and descriptor released |
| wrong ACK (`held_seq^1`) | pusher stays HELD, exported still 1, no release |
| correct ACK after a wrong one | releases, release count +1 |
| duplicate ARM while pending/armed/held | ignored/counted, no second claim/export |
| early ARM + repeated ARM | one export only |
| read arbiter (6 checks) | no owner change inside a burst, bridge single beat, late/orphan beat counted and not rerouted, `o_switch_err=0` |

## 3. PREP=1 / PRED=1 run

Same length/Adler/header/transport criteria, but the transform domain is **not**
byte-compared with `expected_raw` (different domain). Substitute criteria, all
enforced by `evidence/verify_slot_r3.py --only prep`:

- standard zlib decodes the slot, decompressed length = `xform_len` = 3840;
- last 4 bytes = Adler-32 of the decompressed bytes;
- header `raw_crc = 7269454A` (**the raw domain is still the packed RAW10
  input**, so this stays an independent check) and `xform_crc ≠ raw_crc`;
- header CRC/payload/transport/doorbell/0 X as above.

## 4. r3-specific additions (T03 + export)

### 4.1 T03 70 B oracle (`tb_t03_pusher_map`)

The frozen 70-byte stream (`evidence/t03/stream.mem`) is written through
`a1_ddr_slot_store` at word 2048 and read by `ddr_frame_pusher` from byte
`0x1_0000`. In the documented host order (lane 7 first, MSB first inside a DW)
the payload must be byte-identical to `evidence/t03/rtl-slot-read.bin`:

```
PRODUCED_LEN=70 FROZEN_LEN=70 BYTE_DIFF=0
FIRST8=78 9C 62 48 4A 4A 5A 01
```

Mapping candidates: A (current `bswap256`) 0 mismatches; B (no bswap) 69/70;
C (DW-order only) 67/70. A is the only accepted mapping.

### 4.2 Export (`tb_brd_export_r3`)

Two frames, no arming-frame consumption (r2 F1 sequencer), `NF=2`:

- both payloads byte-exact against the store write-side capture (`mismatch=0`);
- one doorbell per frame, `db_val = held_seq = 1,2`;
- wrong ACK (`db_val^1`) holds the slot; correct ACK releases (+1);
- SCEN3 adds host `tl_tx_wait` + slow-DDR windows; same byte/doorbell result;
- `x_cnt=0`, no watchdog;
- the legacy host model (`+HOST_MODEL=1`) reproduces the r0g mismatch (3830/3845)
  and is diagnostic only.

## 5. What this does NOT prove

These are simulation expectations. They do not prove a real PCIe transfer, a real
DDR read, the A path, 1080p30 or a routed bitstream.
