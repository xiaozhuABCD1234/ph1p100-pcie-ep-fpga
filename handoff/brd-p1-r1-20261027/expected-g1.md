# Expected G1 (local simulation only — NOT a hardware guarantee)

Geometry of the local G1 run: camera 128x96, ROI 64x48 (768 packed groups),
slot words 1024, slot byte base `0x1_0000`, one frame per capture.

## Positive (bypass `PREP=0 PRED=0`; and a second run with `PREP=1 PRED=1`)

| item | expected |
|---|---|
| ARM timing | early (before publish) and late (after publish) both export exactly once |
| `st_exported` | 1 |
| P4 commit/publish | `st_frames_committed=1`, `st_store_published=1` |
| MWr count | `ceil(frame_bytes/128)` (4096 B -> 32) |
| MWr payload bytes | `frame_bytes` (4096) |
| doorbell | exactly 1, payload = `held_seq` (1) |
| slot byte base | `0x1_0000` (word 2048), first bytes `78 9c`; byte 0 stays 0 |
| standard zlib | `zlib.decompress(slot[0:stream_len])` succeeds |
| decompressed length | `xform_len` (3840) |
| raw bytes | equal to the packed RAW10 A+ input bytes (bypass run) |
| Adler-32 | last 4 bytes = big-endian Adler of the decompressed bytes |
| host A1U1 header | 44 B built by the host, header CRC correct, payload = slot |
| ACK | correct `held_seq`+session -> release count +1 |
| X / deadlock | 0 X hits, no timeout, arbiter late=0 switch=0 |

Local r1 measured: bypass `stream_len=3137`, 32 TLPs/4096 B, Adler `c49f41ae`;
prep/pred `stream_len=3966`, 32 TLPs/4096 B, Adler `d5cadeeb`.  The lengths are
stimulus dependent; do not hardcode them in P2.

## Negative

| case | expected |
|---|---|
| missing EOF (last ROI row absent) | `committed=0`, `published=0`, `exported=0`, 0 TLP, 0 doorbell, frame aborted and descriptor released |
| wrong ACK (`held_seq^1`) | pusher stays HELD, exported still 1, no release |
| correct ACK after a wrong one | releases, release count +1 |
| duplicate ARM while pending/armed/held | ignored/counted, no second claim/export |
| early ARM + repeated ARM | one export only |
| read arbiter (6 checks) | no owner change inside a burst, bridge single beat, late/orphan beat counted and not rerouted, `o_switch_err=0` |

These are simulation expectations.  They do not prove a real PCIe transfer, a
real DDR read, the A path, 1080p30 or a routed bitstream.
