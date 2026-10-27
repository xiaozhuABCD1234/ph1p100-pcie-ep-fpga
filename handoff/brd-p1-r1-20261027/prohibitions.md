# Prohibitions — brd-p1-r1-20261027

Do not:

1. Use the r3-era derived files
   (`algo_rowwin3_p4.v` 863932B3..., `gray8_gaussian3x3_stream_p4.v`
   B8096430...) — the r2-hash copies F3F345ED.../158AAE4D... are the only
   accepted pair. The filelist and `check_filelist.py` reject the r3 paths and
   SHAs.
2. Mix a b20 bitstream/CWC (`a1_board.bit` etc.) into this candidate. This
   package contains no bit/CWC; every bit must be generated from this
   filelist and bound by SHA.
3. Download, Flash, JTAG/COM or run any board action from the local (sim-only)
   machine. Board work belongs to the teammate holding the board.
4. Modify old runs, old reports, old manifests, role IDs or counts to upgrade a
   conclusion. P4 stays ⚠; r2 and r3 evidence must never be spliced.
5. Edit the repo root production RTL (`rtl/`, `al_ip/`, `constraints/`),
   `fpga/csi2/src/integrated_delivery/**`, `img/**`, `mem/**`,
   `pcie_integration/**` or `tools/td/**` for this candidate. The board
   changes live in the r1 work root + this package.
6. Add `set_false_path` / `set_multicycle_path` on internal data paths to make
   timing pass. The only allowed false paths are `pcie_power_on_rst` (R14) and
   `user_int_trigger`.
7. Write the local simulation result as a board pass, a real PCIe transfer, a
   real DDR read, an A-path result, 1080p30 or a long-run result. G2p is
   `teammate_required`, G3/G4 are `awaiting_hardware`.
8. Claim the r0 150 MHz `-2.273 ns / 79 endpoints` or the r3 `+0.072 ns` as
   this candidate's timing. Re-run on this filelist.
9. Patch the host/RK side to fix Adler or to fake the A1U1 header as a way to
   declare the DUT pass. The DUT stream is a standard zlib member; the header
   is a host contract, stated as such.
10. Commit/push this package from the local machine or contact the teammate
    automatically. The user/teammate takes it with the approved sync method.
