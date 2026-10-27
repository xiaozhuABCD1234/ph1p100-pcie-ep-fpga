# Prohibitions — brd-p1-r2-20261027

Do not:

1. Use the r3-era derived files
   (`algo_rowwin3_p4.v` `863932B3…`, `gray8_gaussian3x3_stream_p4.v`
   `B8096430…`) — only the r2-hash copies `F3F345ED…`/`158AAE4D…` are accepted.
   `filelist.tcl`, `build/check_filelist.py` and the r2 manifest reject the r3
   paths and SHAs.
2. Mix a b20 bitstream/CWC into this candidate. The package contains no
   bit/CWC; every bit must be generated from this filelist and bound by SHA.
3. Download, Flash, JTAG/COM or run any board action from the local (sim-only)
   machine. Board work belongs to the teammate holding the board.
4. Modify old runs, old reports, old manifests, role IDs or counts to upgrade a
   conclusion. P4 stays ⚠; r2 and r3 evidence must never be spliced.
5. Edit the repo root production RTL (`rtl/`, `al_ip/`, `constraints/`),
   `fpga/csi2/src/integrated_delivery/**`, `img/**`, `mem/**`,
   `pcie_integration/**` or `tools/td/**` for this candidate. Board changes live
   in the r2 work root + this package.
6. Edit `filelist.tcl`, `constraints/brd_board.sdc` or `constraints/ph1p_pcie_case_ep.adc`
   in this package: round 2 froze them byte-identical to r1
   (`filelist.tcl` sha256 `41A61493335B84FA8AAFB1FF41FB99C2F8AC71D5E73F018187F567BA277A84A3`).
   If a constraint change is needed, that is a new task, not a local edit.
7. Add `set_false_path` / `set_multicycle_path` on internal data paths to make
   timing pass. The only allowed false paths are `pcie_power_on_rst` (R14) and
   `user_int_trigger`.
8. Ship or open a pre-generated `build/brd_board.al` instead of running
   `build/gen_al.py`. The r1 package's `.al` contained absolute
   `D:/fpga/repos/...` paths and failed as-is (N3 — fixed here by not shipping
   it).
9. "Fix" D7 by manufacturing a 4-byte delta, renaming a file to `adler-fix01`,
   or patching the host/RK side to force the Adler check to pass. D7 is closed
   without an RTL delta; a real failure reopens it as a separate task that first
   reproduces the r0 condition (see `known-risks.md` §4).
10. Re-use the r1 golden numbers as this package's expectation
    (`stream_len = 3137`, `hcrc = 1263f0ea`, or the r1 tester's lagged variant
    `2510`). They came from the malformed r1 stimulus. The r2 golden is derived
    from `expected_raw.bin` (SHA256 `FBA49D33…`) and the D6 header contract.
11. Compare the decompressed raw only against the DUT's own `pk_bytes.bin`.
    That is a self-comparison (the r1 FAIL). The criterion is the independent
    `expected_raw.bin`.
12. Write a local simulation result as a board pass, a real PCIe transfer, a
    real DDR read, an A-path result, 1080p30 or a long-run result. `G2p` is
    `teammate_required`; `G3/G4` are `awaiting_hardware`.
13. Claim the r0 150 MHz `-2.273 ns / 79 endpoints` or the r3 `+0.072 ns` as
    this candidate's timing. Re-run on this filelist.
14. Commit/push this package from the local machine or contact the teammate
    automatically. The user/teammate takes it with the approved sync method.
