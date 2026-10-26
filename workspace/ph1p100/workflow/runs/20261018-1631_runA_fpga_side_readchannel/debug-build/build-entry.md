# Build entry — T11.runB-debug-build

Frozen commit: upstream/ph1p100-pcie-ep-fpga @ 8e1ef05f12831e94311c6cc593090198b0e258fc
(branch codex/raw10-rka1, worktree clean, not pushed).

Final (frozen-entry) command, executed from the upstream checkout:

    powershell -NoProfile -ExecutionPolicy Bypass -File tools\pcie_integration\run_td.ps1 `
      -Stage 00_all_debug -Root <upstream checkout> `
      -OutDir <run>\debug-build\prj_frozen -TimeoutMin 30

TD: D:\anlogic\TD_Release_2026.2\bin\td_commands_prompt.exe (6.2.3.210850).
Hard timeout: wrapper WaitForExit(1800000) + taskkill /PID ... /T /F; not triggered.
Wall: 637.3 s (< 1800 s). Exit 0.

Markers: PRJ-1406 Run phy_1 finished; PRJ-1424 saved as best result;
T07_ALL_DONE + T11_DBG_ALL_DONE; commands.log stage=00_all_debug exit=0;
final_timing.rpt Confidence=Routed.

Preflight experiments (no bitstream, evidence only):
- prj/prj2: tcl copy encoding corruption -> cam_r10f_writer black box.
- prj3: ADC `if/catch` rejected; then SDC multi-line `if` rejected.
They are kept for audit; they are NOT candidate inputs.

Do not download; do not write Flash; do not run P3 (see hardware-ready.md).
