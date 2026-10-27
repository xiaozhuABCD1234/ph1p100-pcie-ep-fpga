# F3 / Adler-32 root cause (T11.BRD.P1 r1)

Scope: local simulation only. No TD, no hardware. b20 A+ sources unchanged.

## 1. Question

r0 reported that the slot stream (byte 0, `stream_len=3966`) inflates 3840 bytes
but the standard `zlib.decompress` fails with `incorrect data check`, and that
the last 4 bytes are `00 00 00 00`.  The r0 report could not say whether the
core emits the Adler tail as zero, or whether the `wr_keep` / last-word path of
`a1_ddr_slot_store` drops it.  D7 asked for a new `adler-fix01` candidate.

## 2. Probes (r1, all run locally with ModelSim ASE 10.5b)

| # | probe | stimulus | command | result |
|---|---|---|---|---|
| P1 | `a1_deflate_core` alone (`sim/tb_adler_probe.v`) | one 256 B block, `in_sop`/`in_blk_end`/`in_stream_end` | `vlog a1_deflate_core.v tb_adler_probe.v` | `stream_len=267`, tail `41 93 7f 81`, expected Adler `41937f81` -> `PROBE_ADLER=PASS` |
| P2 | `a1_frame_top` + core (`sim/tb_frame_probe.v`), 64x48, bypass | 768 packed groups | `vsim work.tb_frame_probe` | `stream=3928`, tail `93 4e 3a e9 da 15 9d c5`, Python `ZLIB_OK 3840` |
| P3 | full board datapath, bypass (`tb_brd_g1_top +SCEN=0 +PREP=0 +PRED=0`) | camera frame 64x48 -> crop -> 43b CDC -> P4 -> store -> DDR model | `run_sim_r1.ps1` | slot `0x10000` starts `78 9c`, `stream_len=3137`, Python `zlib.decompress` OK 3840 B, Adler `c49f41ae`, raw == A+ input bytes |
| P4 | full board datapath, transform path (`+PREP=1 +PRED=1`) | same | same | `stream_len=3966` (same length as r0), Python `zlib.decompress` OK 3840 B, Adler `d5cadeeb` |

Evidence:
`evidence/probe_run.log`, `evidence/probe_frame_run.log`,
`evidence/sim_scen0.log`, `evidence/sim_prep.log`,
`evidence/verify_scen0.log`, `evidence/slot_prep.bin`, `evidence/meta_prep.txt`.

## 3. Finding

* The b20 core emits the correct big-endian Adler-32 on `out_last` (P1/P2).
* In the full r1 path the slot is a valid RFC1950 member in both the bypass and
  the preprocess/predict path; the last 4 bytes equal the Adler of the
  decompressed bytes (P3/P4).
* The r0 "tail = 00000000" **did not reproduce** with the r1 harness and the
  unmodified b20 core, including the exact r0 `stream_len=3966` geometry.

Most plausible mechanism (not proven against the frozen r0 script, which was
not modified): `a1_ddr_slot_store` publishes `slot_st=READY` on the same cycle
its last 256-bit beat is issued on the AXI write channel.  A testbench that
samples the DDR model array at that instant (or decodes a dump taken before the
write beat commits) sees the previous, unwritten word - zeros - for the tail
group, while `slot_len` already includes it.  r1 therefore dumps the slot only
after the doorbell/export completion (stable), and re-checked with Python.

## 4. Decision (D7)

No RTL delta is made. `rtl/a1_core_fix01/` holds the verified b20 r0 closure
for traceability: `a1_frame_top.v`, `a1_deflate_core.v`, `a1_ddr_slot_store.v`,
`a1_ddr_arb2.v` are byte-identical to the b20 files in the filelist (same
SHA256), and the filelist compiles the b20 originals.  There is no
"adler-fix01" behavioural change to bind, and no host-side Adler patch is used
as a pass.  If the planner still requires a named variant, it must be created
with a real delta and re-proved; inventing a no-op variant would be misleading.

Bound SHAs (b20, unchanged):
- `a1_frame_top.v` CDA28C941321F28DF8318DACAF291F6268EA5E4D6EA9FAF9921ED824B3A2160C
- `a1_deflate_core.v` A91C2ED82FBEF654C4E065B64AE1CC268CA232FEAA26FDD313C58D8740F81B3E
- `a1_ddr_slot_store.v` 6C619CF90E54385D667F1EC0F63CC87EE58AADD3C42143330AC4945EB47DEFE9
- `a1_ddr_arb2.v` B84019BDA057AFE82FF558E0848D6171FA12732BD8CDB7C6239CB71B3F81D6BA

P2/RK must still verify on hardware; local zlib success is not a board result.
