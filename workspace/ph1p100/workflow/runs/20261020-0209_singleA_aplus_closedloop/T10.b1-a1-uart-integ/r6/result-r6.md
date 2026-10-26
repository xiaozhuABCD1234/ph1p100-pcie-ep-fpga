# T10.b1-a1-uart-integ r6 -- reset-mux cleanup + regression PASS (final)

Final RTL hashes:
- core `d4b799612519d4cb6c32a0c0e87807be84dec711fc01e2146b054d464d1b88de`
- frame `c8b24775fa70793f682f1a640be175ec53f304722539cbd89550e0d4aefca65b`
- P1 top `17793341f717ddac3476d9c129a96b87a745f553dbdbee59efb1f29966baac88`

Changes: reset removed from smem/bm/htab/cmem address/data mux registers; frame `rd_addr`
moved to a reset-free always block; control/state/valid/write-enable resets preserved.
Regression: 8x2 / 64x8 / full 1920x1080 all 0 mismatch, four CRC true, zlib true, dup=0,
raw_len 2,592,000, stream_len 40,032, raw_sha256 `2f34e253...d355e830`; no X/half-frame.
Boundary unchanged.
