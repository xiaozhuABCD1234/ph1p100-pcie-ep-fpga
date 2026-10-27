# Prohibitions — brd-p1-r3-20261027

Do not:

1. Use the rejected derived files
   (`algo_rowwin3_p4.v` `863932B3…`, `gray8_gaussian3x3_stream_p4.v`
   `B8096430…`) — only the r2-hash copies `F3F345ED…`/`158AAE4D…` are accepted.
   `filelist.tcl`, `build/check_filelist.py` and the r3 manifest reject the
   rejected paths and SHAs.
2. Mix a b20 bitstream/CWC into this candidate. The package contains no
   bit/CWC; every bit must be generated from this filelist and bound by SHA.
3. Download, Flash, JTAG/COM or run any board action from the local (sim-only)
   machine. Board work belongs to the teammate holding the board.
4. Modify old runs, old reports, old manifests, role IDs or counts to upgrade a
   conclusion. r0g stays **blocked**; r2 stays local PASS; r3 is a new run with a
   new manifest. Old evidence must never be spliced.
5. Edit the repo root production RTL (`rtl/`, `al_ip/`, `constraints/`),
   `fpga/csi2/src/integrated_delivery/**`, `img/**`, `mem/**`,
   `pcie_integration/**` or `tools/td/**` for this candidate. Board changes live
   in the r3 work root + this package.
6. Edit `filelist.tcl`, `constraints/brd_board.sdc` or
   `constraints/ph1p_pcie_case_ep.adc` in this package. r3 freezes them
   (`filelist.tcl` sha256
   `5FB9AEE7270886305F641CADBE469563399CB1A21539D171DC84B407E299AB6A`).
   If a constraint change is needed, that is a new task, not a local edit.
7. Add `set_false_path` / `set_multicycle_path` on internal data paths to make
   timing pass. The only allowed false paths are `pcie_power_on_rst` (R14) and
   `user_int_trigger`.
8. Ship or open a pre-generated `build/brd_board.al` instead of running
   `build/gen_al.py`. The template carries only `@REPO_ROOT@`; the generated
   `.al` must come from the actual checkout.
9. "Fix" D7 by manufacturing a 4-byte delta, renaming a file to `adler-fix01`,
   or patching the host/RK side to force the Adler check to pass. D7 is closed
   without an RTL delta; a real failure reopens it as a separate task that first
   reproduces the r0 condition (see `known-risks.md` §4).
10. Re-use the r1 golden numbers as this package's expectation
    (`stream_len = 3137`, `hcrc = 1263f0ea`, or the r1 tester's lagged variant
    `2510`). They came from the malformed r1 stimulus. The r3 golden is derived
    from `expected_raw.bin` (SHA256 `FBA49D33…`) and the D6 header contract;
    the candidate-bound table is `stream_len=2470`, `hcrc=A5ECBAD9`,
    `stream_crc=9909B919` (bypass).
11. Compare the decompressed raw only against the DUT's own `pk_bytes.bin`.
    That is a self-comparison (the r1 FAIL). The criterion is the independent
    `expected_raw.bin`.
12. **Change `bswap256` in `ddr_frame_pusher.v` to make a testbench pass.** The
    T03 A/B/C experiment (A=0, B=69/70, C=67/70) and the three project TBs select
    the current mapping. If a new TB disagrees, audit the TB's lane/byte model
    first; the r0g legacy decode (`+HOST_MODEL=1`) is diagnostic only.
13. **Reintroduce the export copy's `×128` address path or
    `BASE_WORD=SLOT_BASE_WORD`.** The only accepted chain is bridge `×8` + board
    `×4` = `×32`; word 2048 must be byte `0x1_0000`, never `0x4_0000`.
14. **Drive `utx_sel` inside `brd_board_datapath`.** On the board the EP engine
    drives the net; an internal `assign` double-drives it. The TB grant model is
    a simulation input, not RTL.
15. Write a local simulation result as a board pass, a real PCIe transfer, a
    real DDR read, an A-path result, 1080p30 or a long-run result. `G2p` is
    `teammate_required`; `G3/G4` are `awaiting_hardware`.
16. Claim the r0 150 MHz `-2.273 ns / 79 endpoints` or the r3 `+0.072 ns` as
    this candidate's timing. Re-run on this filelist.
17. Commit/push this package from the local machine or contact the teammate
    automatically. The user/teammate takes it with the approved sync method.
