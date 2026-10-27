# lessons — r3 minimal merge (T11.BRD.P1, 2026-10-27)

1. **A new TB is not an oracle until its host model is cross-checked.** r0g's export TB decoded
   payload lanes 0→7 with LSB-first bytes, while its own header decode used lane 7 = DW0 and
   MSB-first. Three pre-existing project TBs (`sim/tb/tb_ddr_frame_pusher_rka1.v`,
   `sim/tb/tb_t11_r10f_e2e.v`, `sim_do/tb_ddr_frame_pusher.v`) use lane 7 + MSB-first and compare
   against LSB-first DDR bytes. The outlier was the new TB, not the DUT. When a fresh TB disagrees
   with every existing one, audit the TB's byte/lane model before touching RTL.

2. **"Try the mapping" beats "apply the expected fix".** The A/B/C experiment (current bswap256,
   no bswap, DW-order-only) on the same captured beats made the decision mechanical: A=0 mismatches,
   B=69/70, C=67/70. No RTL edit was needed. The user's instruction to test first prevented a
   regression that would have broken the known-good r10f path.

3. **A host model must be consistent between header and payload.** The r0g TB parsed the header
   (lane 7 first, MSB first) and the payload (lane 0 first, LSB first) with opposite conventions.
   That inconsistency alone is a red flag; a one-line "legacy mode" kept the old observation
   reproducible instead of erasing it.

4. **Backpressure exposes TB capture bugs.** `core_out_valid` is held while `core_out_ready` is low;
   capturing on valid alone duplicated 236 bytes and shifted `expbuf`, producing 2362 false
   mismatches in SCEN3. Gate the capture with `valid && ready` (or use the store write handshake).

5. **ARM semantics are design-specific.** The r0g flow assumed "the ARM consumes the current
   descriptor". The r2 F1 sequencer (`brd_export_seq`) latches the ARM and emits one source event for
   the published frame, so frame 0 is exported. Reusing a TB written for a different ARM wiring
   produced a false "arming frame exported" failure; the TB branch, not the DUT, had to change.

6. **A header field change moves the header CRC, not the stream.** Starting `a_seq/b_seq` at 1
   changes `frame_id` 0→1 and `hcrc` `5436BF73→A5ECBAD9`; `stream_len=2470` and
   `stream_crc=9909B919` are unchanged. Keep independent values fixed and re-freeze candidate-bound
   values with an explicit reason.

7. **One conversion per boundary.** The working chain is word ×8 (bridge) then ×4 (board remap) =
   ×32. Adding a second ×32 at the bridge gives ×128 and moves word 2048 from `0x1_0000` to
   `0x4_0000`. The pusher base and the descriptor base must use the same ×32; never introduce a third
   multiplier to "make it work".

8. **Comment-stripped diffs prove "comment-only" and "two-line" deltas cheaply.** `static_checks_r3.py`
   removes comments/blank lines, diffs r2 vs r3, and asserts the exact changed lines. This is a
   stronger audit than reading a diff by eye, and it keeps the RTL delta claim falsifiable.

9. **Keep the old verdicts byte-identical.** r0g stays blocked; r0/r1/r2 manifests stay unchanged;
   r3 is a new run with a new manifest. The old manifests are checked for any r3 path or changed-file
   SHA. A new PASS never overwrites an old FAIL/blocked record.

10. **Harness hygiene.** PowerShell `Set-Content -Encoding UTF8` writes a BOM that ModelSim rejects
    (`vlog-13067`); strip it before compiling. Long-running vsim invocations need a per-run work
    junction and a `cd` in the do-file because `vsim` refuses `cd` after loading a design.
