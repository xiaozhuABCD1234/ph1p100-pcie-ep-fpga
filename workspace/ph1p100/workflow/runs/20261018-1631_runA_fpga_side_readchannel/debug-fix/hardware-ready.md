# Hardware-ready — P1-fix2 status (P3 still gated by P2 + user presence)

| Gate | Result |
|---|---|
| Build | PASS (P1-fix): exit 0, PRJ-1406/1424, Routed, 776.8 s; bit sha256=2385cdedae1d9985687360af77341183517e34cb18be9cad0229291593411873 |
| G2 STA | PASS (P1-fix): SWNS 0.139 / STNS 0.000 / HWNS 0.020 / HTNS 0.000 ns; 0 violation lines; SDC failure warnings 0 |
| Resources | PASS within device: LUT6 23.27%, reg 15.19%, ERAM 50.33%, IO 37.41% |
| CWC generation | PASS: auto_created_cwc1, 9 view nodes, 288 trigger + 288 data nets; cw/compiled.cwc sha256=fa24e25830fefe882edb3b4d9ab18de8fd39598a9822231b8622c9a0c73f22bb |
| CWC validator | PASS (P1-fix2 equivalent check): --multipiece accepted; 15 contiguous pieces, 288/288 data coverage + 1 documented TD status tail bit; map=debug-fix/cwc-multipiece-map.json; strict mode unchanged (still rejects multi-piece) |
| Decision | P3 must not start yet: requires P2 lightweight freeze (reuse P1-fix build, no rebuild) + user presence window. Not downloaded, not flashed. |