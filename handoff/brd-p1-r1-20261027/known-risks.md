# Known risks — brd-p1-r1-20261027 (T11.BRD.P1 round 1)

Read with `expected-g1.md` and `prohibitions.md`.  None of these is a local
pass; they are the risks the teammate must retire on the real build/board.

1. **r0 timing is history, not this candidate.** `WNS -2.273 ns / TNS
   -31.547 ns / 79 endpoints @150 MHz`, hold unverified, 125 MHz untested,
   route/bitgen/CWC = 0 belong to the r0 source set. The r1 SDC and RTL are
   different; re-run synth/route/STA on this filelist.
2. **G2p / CDC are not run locally.** The C8/C9 2FF and the six clock groups
   are statically checked only; a real CDC report, clock interaction and hold
   analysis are required.
3. **DDR x4 remap is a simulation contract.** P4 emits 256-bit word indices,
   `p2_ddr_bridge` emits word*8, the board multiplies by 4 to byte addresses.
   Only the G1 DDR model validates it. P2 must first confirm the DDR IP
   capacity/addressing and the slot map.
4. **Slot geometry is 2.5 MiB/slot, not 640 KiB.** `SLOT_WORDS=81920` words x
   32 B = 2,621,440 B; slot 0 = `0x1_0000..0x290000`, slot 1 from
   `0x290000`. r0's "640 KiB" is an arithmetic error and is not repeated.
   A full compressed frame must fit; the capacity rejection path is untested.
5. **`SLOT_BASE_WORD=2048`** is a board-side +word offset on both P4 write and
   drain; the P4 r2 sources still instantiate their store at `BASE_WORD=0`.
   No reference `cam_*_writer` is instantiated, so there is no 1 MB/9 MB writer
   conflict inside this netlist - but the DDR map must be checked by the
   teammate.
6. **BAR `0x130..0x13C` / CTRL[9..11] are NOT implemented (D2 rejected in
   round1).** The host cannot read P4 status yet; `a_enable=0`,
   `trigger_mode=0`, `p4_desc_owner=1` are tied. P2 needs this before trusting
   a header built from status.
7. **A1U1 header is host-owned.** The slot starts with `78 9c` (zlib), no 44B
   header. P2/RK must implement `a1u1-header-contract.md`; a host that parses
   the slot as A1U1 will be off by 44 bytes.
8. **A path is netlist-only.** `a_enable=0`; no A-path simulation/board run.
   A evidence belongs to P3.
9. **`cfg_phase=0`** (b18 unproven placeholder); `cfg_aplus_prep/pred=1/1` is
   the board default from b18. The local G1 ran both bypass and 1/1; raw
   pixel correctness at sensor phase is a board item.
10. **No bit/CWC and no real PCIe/RK.** G3/G4 are `awaiting_hardware`; 1080p30,
    long-run and throughput are not demonstrated by any local simulation.
11. **Descriptor depth 1.** A frame is held until a matching ACK; the board
    re-offers the next descriptor immediately after release. Un-ACKed frames
    block the pipeline by design (recorded `held` state).
12. **held_seq alignment.** The P4 egress adapter now compares the ACK against
    the pusher done count (= doorbell value), not `capture_seq`. Hosts must ACK
    with the doorbell/held value; a capture-seq ACK will be rejected.
