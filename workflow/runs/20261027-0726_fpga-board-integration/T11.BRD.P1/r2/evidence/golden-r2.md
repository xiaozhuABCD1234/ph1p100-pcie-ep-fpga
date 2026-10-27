# golden-r2.md — T11.BRD.P1 round 2 golden (local simulation only)

Rebuilt for the **fixed** camera stimulus (r1 `T11.BRD.P1:TB_CAM_STIMULUS_WIDTH`).
r1 values (`stream_len=3137`, `hcrc=1263f0ea`) and the r1 tester's lagged
fix-variant measurement (`stream_len=2510`) are **cross-references only**; they
are not a source of expectation.

## 1. How this golden was produced

| item | source |
|---|---|
| `expected_raw.bin` (3840 B) | `evidence/gen_expected_raw.py` — the frozen contract only (rows 16..63, groups 8..23, `v=(r*32+g)&0x3FF`, four identical pixels per beat, `byte0..3=v[9:2]`, `byte4={v[1:0] x4}`, offset `((r-16)*16+(g-8))*5`, total `48*16*5`). Reads **no** DUT output, `pk_bytes.bin`, slot stream or developer intermediate. |
| Adler / CRC | computed in the same script with `zlib.adler32` / `zlib.crc32` over `expected_raw.bin` |
| Header expectations | frozen D6 contract (`a1u1-header-contract.md`): 44 B host-owned header, little-endian, CRC-32 over bytes 0..39 |
| Transport expectations | `frame_bytes = align_up(stream_len, 4096)`, `mwr_count = frame_bytes/128`, `mwr_bytes = frame_bytes`, one doorbell |
| `stream_len` / `hcrc` / `stream_crc` | **candidate-bound**: measured on the frozen r2 TB run, used only as a repeatability check (see §3) |

Compressor/parameters recorded: **CPython 3.11.5 `zlib`**, `zlib.adler32`,
`zlib.crc32`, and (reference only) `zlib.compress(raw)` at the default level
(`-1` == 6, header `78 9c`).

## 2. Independent golden (judged)

| item | value | criterion |
|---|---|---|
| expected raw length | 3840 B | `len(zlib.decompress(slot)) == xform_len == 3840` |
| expected raw SHA256 | `FBA49D330DB9196A9BD9B8F29419A5603CEF600FE7D08F73708674F4C3C5111E` | `raw == expected_raw.bin` **byte-for-byte** (primary G1 byte criterion) |
| expected raw Adler-32 | `392578F9` | slot last 4 B, big-endian |
| expected raw CRC-32 | `7269454A` | `st_xform_crc` and `st_raw_crc` in bypass, and header `xform_crc`/`raw_crc` |
| first 5 bytes | `82 82 82 82 00` (first group `v=520`) | fixture self-check + packer output |
| last 5 bytes | `FD FD FD FD FF` (last group `v=1015`) | fixture self-check |
| slot base | word 2048 = byte `0x1_0000`, starts `78 9C`; byte 0 stays all-zero | TB + dump checks |
| `frame_bytes` | 4096 | `align_up(stream_len,4096)` and `== 4096` (any conformant deflate of 3840 B stays far below 4096; worst case with stored blocks ≈ 3845 B) |
| MWr | 32 × 128 B = 4096 B | `tlp_cnt == frame_bytes/128`, `mwr_bytes == frame_bytes` |
| doorbell | 1, payload = `held_seq` | TB scoreboard + meta |
| A1U1 header | magic `A1U1`, version 1, hlen 44, flags 0 (bypass) / 3 (PREP=1,PRED=1), W=64, H=48, raw_len 3840, xform_len 3840, stream_len = len(slot), header CRC over bytes 0..39, payload == slot | independent parser |
| X / deadlock | 0 X hits, no timeout | TB |

## 3. Candidate-bound values (NOT independent — repeatability only)

| item | r2 value | provenance |
|---|---|---|
| `stream_len` | 2470 | frozen r2 TB, `sim/scen0`, PREP=0/PRED=0 |
| `frame_bytes` | 4096 | same run |
| `hcrc` | `5436BF73` | same run (depends on the DUT's own stream length/CRC) |
| `stream_crc` | `9909B919` | same run |
| stimulus probe | `stim_lane_bad=0`, `stim_chain_bad=0`, `stim_first_v=520`, `pk_first=0082828282` | same run (`tb_probe_r2.txt`) |

`stream_len` is **not** derivable from an independent model, and that is not a
weakening: the DUT's `a1_deflate_core` is a different RFC1950 encoder from
CPython zlib. Proof from the r1 frozen frame: CPython `zlib.compress` of the r1
malformed raw is **1391 B**, the DUT emitted **3137 B**, and both carry the same
Adler-32 `c49f41ae`. Requiring byte equality with zlib would judge the encoder's
match/block policy, not the D7/C1–C6 contract. The judged criteria stay:
*standard zlib decodes the slot*, *decoded bytes == expected_raw*, *Adler-32 ==
`392578F9`*, *header/transport consistency*. SCEN0/3/4 must additionally produce
a byte-identical slot stream (same frozen stimulus, same DUT).

## 4. Not covered by this golden

- No statement about real sensor data, the A path, 1080p30, DDR on hardware, or
  a routed bitstream. `G2p = teammate_required`, `G3/G4 = awaiting_hardware`.
- The PREP=1/PRED=1 run uses the same length/Adler/header/transport criteria; the
  transform domain is **not** byte-compared to `expected_raw` (it is a different
  domain). Its substitute criteria are listed in `result-r2.md` §3 and enforced
  by `verify_slot_r2.py --mode prep`.
