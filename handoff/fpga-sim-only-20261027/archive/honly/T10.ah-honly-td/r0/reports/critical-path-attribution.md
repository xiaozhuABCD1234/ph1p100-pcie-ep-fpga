# critical-path-attribution - T10.ah-honly-td

**No STA exists, so there is no "worst path" to attribute.** The required question
("is the worst path in the frame_top dual-CRC32 chain, the core replay/emit cone, or the
scan cone?") is **unanswered by measurement** and must not be answered by guesswork.

What can be attributed instead is the **synthesis blocker**, from elaboration logs:

| Item | Value |
|---|---|
| Object | `a1_deflate_core` / `cmem_lo[15]` |
| Structure | cmem write-combine register pair (`cmem_lo`, `cmem_lo_pend`, `cmem_lo_addr`) feeding the 2048x32 `cmem` |
| Hierarchy | `a1_ah_eng_top.u_dut` -> `a1_deflate_core` (single instance, `OUT_BYTES=2`) |
| Conflicting drivers | L673-687 dedicated write-port `always` (L679, reset-free) vs L964 main sequential `always` (L1042, reset branch) |
| Tool reaction | `HDL-8007` multiple driver -> module kept as black box -> `syn_1` failed |

So the blocker is in the **core replay/write-combine cone** by construction (it is the
cmem write port that the replay reads back), but there is no timing cone to rank: no
comparator, no slack, no path list was produced.

For the record, the two cones the planner asked about are identifiable in RTL but remain
**unmeasured**: `a1_frame_top` dual CRC32 (`raw_crc`/`xform_crc`/`stream_crc` update
chains) and `a1_deflate_core` replay/emit plus the `w0` scan/hash cone (see core L689+
literal/threshold logic). Any future TD package must produce the >=10-path list from its
own routed report; this round cannot inherit one.