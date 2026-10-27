# Expected G1 (local simulation only — NOT a hardware guarantee)

Geometry of the local G1 run: camera 128×96, ROI 64×48 (768 packed groups),
slot words 1024, slot byte base `0x1_0000`, one frame per capture.

## 0. Stimulus contract (frozen for TB / model / tester)

ROI rows `r ∈ [16,63]`, groups `g ∈ [8,23]`, `v = (r*32 + g) & 0x3FF`; each
40-bit beat carries **four identical** 10-bit pixels `v`; packed byte offset
`((r-16)*16 + (g-8))*5`; `byte0..3 = v[9:2]`; `byte4 = {v[1:0] x4}`; raw length
`48*16*5 = 3840 B`; first group `v = 520` (bytes `82 82 82 82 00`); last group
`v = 1015` (bytes `FD FD FD FD FF`).

The r1 testbench violated this (`{4{32-bit expression}}` truncation) and was
fixed in round 2 — see `evidence/tb-stimulus-fix.md` in the r2 work root.

## 1. Independent golden (judged)

Source: `workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r2/evidence/gen_expected_raw.py`
(contract only; reads no DUT output, no `pk_bytes`, no slot stream) and
`evidence/golden-r2.md` / `golden-r2.json`.

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
| A1U1 header (host-built) | magic `A1U1`, version 1, hlen 44, flags 0 (bypass) / 3 (PREP=1,PRED=1), W=64, H=48, raw_len 3840, xform_len 3840, stream_len = len(slot), header CRC over bytes 0..39, payload = slot |
| exported | `st_exported = 1` |
| X / deadlock | 0 X hits, no timeout, arbiter late = 0, switch = 0 |
| ARM | early (before publish) and late (after publish) both export exactly once |

Round-2 measured values (candidate-bound, repeatability only, **not** a
contract): bypass `stream_len = 2470`, `hcrc = 5436BF73`, `stream_crc = 9909B919`
(SCEN0 = SCEN3 = SCEN4, byte-identical slot stream); PREP=1/PRED=1
`stream_len = 538`, `hcrc = 981E85CF`, `xform_crc = 7883ABAF`. Do **not**
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
enforced by `evidence/verify_slot_r2.py --only prep`:

- standard zlib decodes the slot, decompressed length = `xform_len` = 3840;
- last 4 bytes = Adler-32 of the decompressed bytes;
- header `raw_crc` = `7269454A` (**the raw domain is still the packed RAW10
  input**, so this stays an independent check) and `xform_crc ≠ raw_crc`;
- header CRC/payload/transport/doorbell/0 X as above.

These are simulation expectations. They do not prove a real PCIe transfer, a real
DDR read, the A path, 1080p30 or a routed bitstream.
