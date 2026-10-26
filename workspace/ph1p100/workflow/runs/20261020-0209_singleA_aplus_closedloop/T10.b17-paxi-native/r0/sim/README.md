# T10.b17-paxi-native r0 simulation index

All commands run with ModelSim ASE 10.5b (`D:\intelFPGA\18.1\modelsim_ase\win32aloem`)
and write temporary libraries only under `%TEMP%\opencode\T10.b17-paxi-native\`.

| case | command | result file |
|---|---|---|
| 16-word native boundary | `python run_b17.py native` | `sim-results-b17-native.json` |
| mask negative control | same (CASE=mask) | same |
| low3/OOB direct model | same (CASE=addr) | same |
| ALLOW_CONCURRENT=1 control | same (CASE=conc) | same |
| frozen b15 bridge control | same (CASE=b15) | same |
| v6 packet structure | `python run_b17.py status` | `sim-results-b17-status.json` |
| S3 drop-1-R recovery | `python run_b17.py chain s3_drop1` | `sim-results-b17-chain-s3_drop1.json` |
| S1 full frame | `vsim tb_b17_chain ... -gNFRAMES=1` | `sim-results-b17-chain-s1_full_clean.json` |
| S2 two full frames | `vsim tb_b17_chain ... -gNFRAMES=2` | `sim-results-b17-chain-s2_full_two.json` |
| P1 three goldens | `python run_b17.py p1` | `sim-results-b17-p1.json` |

Geometry for the full cases: `CAM_W=3864 CAM_H=2192 ROI_X=972 ROI_Y=556 W=1920
H=1080`, `UART_DIV=1`, `STA_DIV=25000`.

Checker: `check_b17.py` (frame/four-CRC/strict-zlib/independent-reference via
`check_b17_core.py`, plus native-contract + v6 gates).  `check_b17_core.py` is
the b13 checker retargeted from 241 B/59 fields to 273 B/67 fields.

Negative controls live in `neg/p2_ddr_bridge_b15.v` (frozen b15 bridge, module
renamed only) and the `ALLOW_BOTH_READY=1` model instance in the 16-word TB.
Neither is part of the board candidate.
