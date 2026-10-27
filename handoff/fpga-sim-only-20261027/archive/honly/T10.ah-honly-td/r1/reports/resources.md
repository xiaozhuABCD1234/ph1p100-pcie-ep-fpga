# resources (r1) - T10.ah-honly-td

Source: **synthesis gate area report only** (`r1/td/run-syn1/syn_gate_area.rpt`).
No placed/routed resource report exists (route blocked, see `routed-sta.md`).

| Metric | Gate | Synthesis value | Verdict (synth only) |
|---|---|---:|---|
| `#slice*` (LUT6-equivalent slices) | <= 71,680 | 3,337 (4.66 %) | inside |
| `#reg` | - | 1,663 (1.16 % of 143,360) | inside |
| `#lut` | - | 4,188 (lut6 1,978; lut5 477; lut4 658; lut3 629; lut2 429; lut1 17) | - |
| `#eram` | ERAM+CWC <= 300 | 27 (all `#eram20k`) | inside |
| `#fifo20k` (CWC) | ERAM+CWC <= 300 | 0 | inside |
| **ERAM+CWC** | **<= 300** | **27 (9.00 %)** | **inside** |
| `#dsp` | - | 0 (0.00 % of 220) | - |
| `#IO` | <= 286 | 121 (42.31 %): 48 in, 73 out, 0 inout | inside |
| `#pcie` | - | 0 | - |
| `#f7mux` / `#f8mux` | - | 0 / 0 | - |
| `#used ram` / `#used logic` | - | 48 / 3,289 | - |

Notes:

1. The 121 IO equal the wrapper port sum exactly (clk, rst_n = 2; in_pix[39:0] = 40;
   in_valid/in_ready/in_sof/prep_en/pred_en/abort = 6; out_data[31:0] = 32; out_valid,
   out_ready, out_keep[3:0], out_last, frame_commit, frame_abort = 41; st_dbg[31:0] = 32),
   i.e. the status-XOR fold worked and no DUT observation bus leaked to the pins.
2. `#eram` 27 matches the RAM inference list from elaboration (frame_top `smem`; core
   `wq_mem`, `opq_mem`, `fifo_mem`, `bm_a`, `bm_b`, `htab_*`, `cmem`).
3. These are **pre-place** estimates. Routing can change slice usage and will add
   buffers; only a routed area report may be used for the device-fit decision, which
   this round does not have.