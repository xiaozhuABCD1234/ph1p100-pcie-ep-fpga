# Golden r3 — independent values and candidate-bound repeatability

This page separates **independent** (contract/model only) values from
**candidate-bound** values (measured on the frozen r3 runs; equality is a
repeatability check, never an independent derivation).

## 1. Independent golden (unchanged from r2)

| quantity | value | source |
|---|---|---|
| expected raw length | 3840 B | `gen_expected_raw.py` (contract only) |
| expected raw SHA256 | `FBA49D330DB9196A9BD9B8F29419A5603CEF600FE7D08F73708674F4C3C5111E` | same |
| Adler-32 | `392578F9` | `zlib.adler32(expected_raw)` |
| CRC-32 | `7269454A` | `zlib.crc32(expected_raw)` |
| first 5 bytes | `82 82 82 82 00` | contract |
| geometry | 64×48 ROI, raw 3840 B, frame_bytes 4096 | contract |

`gen_expected_raw.log` is the r3 regeneration log; it reproduces the same
values. The model never reads a DUT output.

## 2. Candidate-bound (r3 measured)

| quantity | bypass (SCEN0/3/4) | PREP=1/PRED=1 |
|---|---|---|
| stream_len | 2470 | 538 |
| stream_crc | `9909B919` | `10FCD4FE` |
| hcrc (A1U1) | `A5ECBAD9` | `69C48065` |
| xform_crc | `7269454A` (= raw, bypass) | `7883ABAF` |
| raw_crc | `7269454A` | `7269454A` |
| Adler of decoded | `392578F9` | `5F1669E1` |

**Why hcrc changed vs r2 (`5436BF73` / `981E85CF`)**: r3 starts the per-camera
capture identity at 1 (r0d), so the D6 header `frame_id` is 1 instead of 0.
The compressed slot stream is unchanged (`2470 / 9909B919`); only the
host-owned header CRC changes. The verifier checks hcrc by recomputation
(`zlib.crc32(header[0:40])`), not by a hard-coded old value; the
candidate-bound table above is re-frozen for r3.

## 3. What is NOT a criterion

Compressed byte equality with CPython `zlib.compress` is not a criterion:
`a1_deflate_core` is a different RFC1950 encoder (r1 proof: 1391 B from
CPython vs 3137 B from the DUT, both with the same Adler-32). The independent
criteria are the decoded raw bytes, the length, the Adler tail, the D6 header
fields/CRC, and the transport (frame_bytes / MWr / doorbell).

## 4. Files

- `golden-r3.json` — machine-readable (independent + candidate-bound).
- `expected_raw.bin` / `expected_raw.json` — independent model output.
- `gen_expected_raw.py` / `.log` — generator and its r3 log.
- `verify_slot_r3.py` / `verify-slot-r3.log` — 150-check verifier.
- `verify_t03_r3.py` / `verify-t03.log` — T03 70 B oracle + mapping experiment.
- `verify_export_r3.py` / `verify-export-r3.log` — export two-frame/backpressure/ACK/negative.
