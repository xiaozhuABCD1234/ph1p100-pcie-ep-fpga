# T10.b1-a1-uart-integ r5 -- post-fix P1 regression (core PASS-with-boundary)

Fix: only the duplicate read-control drivers in `camera_a1_uart_top.v` were cleaned.
The skid always block no longer resets/drives `raw_rd_open`/`raw_rd_close_r`/`raw_rd_take`;
the feeder/sequencer always block is the single owner and now carries the same 0 defaults
in reset and normal cycles. No protocol/frame/CRC/DEFLATE change.

New RTL hash: `17793341f717ddac3476d9c129a96b87a745f553dbdbee59efb1f29966baac88`.

Regression (r1/work, ModelSim ASE 18.1, vlog 0/0):

| case | read_words | dup | mismatch | header/stream/xform/raw CRC | zlib | raw_len | stream_len | cycles |
|---|---|---|---|---|---|---|---|---|
| 8x2 | 1 | 0 | 0 | true/true/true/true | true | 20 | 19 | 3,748 |
| 64x8 | 32 | 0 | 0 | true/true/true/true | true | 640 | 106 | 5,024 |
| 1920x1080 | 129,600 | 0 | 0 | true/true/true/true | true | 2,592,000 | 40,032 | 6,383,945 |

Full-frame raw_sha256 = `2f34e2536590b891539604eea7a40f9f68fe3154e5b0b0ffa77d5656d355e830` (same as r3).
`stream_len 40,032 <= 2,594,706`; `cap_bytes=40,076=44+40,032`.

Boundary unchanged: MODE=2 bad-frame/overflow counters, store-only 2,594,706 B max length,
shortened MODE=1, W=8,H=3 tail, mid-write reset recovery.
