# Hardware-ready — P1-fix3 candidate (READY for P2 lightweight re-freeze; P3 still needs user window)

| Gate | Result |
|---|---|
| Build | PASS: exit 0, PRJ-1406 (syn+phy), PRJ-1424, T07_ALL_DONE, T11_DBG_ALL_DONE, Routed, 692.6 s |
| G2 STA | PASS: SWNS 0.134 / STNS 0.000 / HWNS 0.020 / HTNS 0.000 ns; 0 violation lines; SDC failure warnings 0; STA coverage 96.04% |
| Clock table | tl_clk_user 62.5 MHz / cam_a_byte_clk 187.547 / cam_b_byte_clk 187.547 / usr_clk 100 / sys_clk 50 (same as baseline) |
| Resources | PASS within device: LUT6 16627/71680 (23.20%), slice reg 21814/143360 (15.22%), ERAM 151/300 (50.33%), IO 107/286 (37.41%) |
| CWC | PASS: auto_created_cwc1, 9 view nodes, 288 trigger + 288 data nets; cw/compiled.cwc sha256=8d2998b96ef1763c14a1302118235a687488297ce496692b1f6cd95d76981026 |
| CWC validator | PASS: --multipiece accepted (15 pieces, 288/288 data coverage + 1 documented TD status tail bit); map=debug-fix3/cwc-multipiece-map.json |
| Fix (issue-02) | Snapshot regs reset by link-independent dbg_por_rst (board POR or PLL unlocked) instead of tl_rst_user; identity/version/CTRL readable without PCIe link; DDR/CSI sources unchanged |
| Decision | P2 lightweight re-freeze (reuse this build, no rebuild) then P3: SRAM download of bit bfafdf97... + user GUI two samples (>=10 s). Not downloaded, not flashed, not pushed. |