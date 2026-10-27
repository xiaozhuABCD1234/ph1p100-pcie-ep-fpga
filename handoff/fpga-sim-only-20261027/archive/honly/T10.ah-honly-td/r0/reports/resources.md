# resources - T10.ah-honly-td

**No resource numbers exist.** TD stopped before mapping/optimisation, so `.area` was
never produced and `flow.status` was not written.

| Metric | Gate | Value |
|---|---|---|
| `#slice*` | <= 71,680 | unavailable |
| `#reg` | - | unavailable |
| `#eram` | ERAM+CWC <= 300 | unavailable |
| `#fifo20k` | ERAM+CWC <= 300 | unavailable |
| `#dsp` | - | unavailable |
| `#IO` | <= 286 | unavailable |

Elaboration did report RAM inference for `smem` (frame_top), and for `wq_mem`,
`opq_mem`, `fifo_mem`, `bm_a`, `bm_b`, `htab_tag`, `htab_p3v`, `htab_pos`, `htab_b`,
`htab_b3`, `cmem` (core). That is **inference evidence only** - it says nothing about
ERAM/fifo20k mapping counts, and no slice/IO/register total can be derived from it.

No estimate was substituted for a missing measurement.