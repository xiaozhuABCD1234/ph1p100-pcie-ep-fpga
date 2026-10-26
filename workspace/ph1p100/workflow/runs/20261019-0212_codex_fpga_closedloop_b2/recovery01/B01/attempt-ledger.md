# B01 recovery01 actual attempt accounting

Same run/task IDs; still before independent integrated round0. Actual repair rounds=0; supplementary opportunities=0. No counts are reset by output-directory changes.

| Operation | Historical | Recovery attempts so far | Actual result and correction |
|---|---:|---:|---|
| Original tb_closedloop_writer_checker command | 2 compilation failures | 2 | Cumulative attempt3 corrected declaration ordering and PASS; cumulative attempt4 reran after the AR skid implementation and PASS (648192 words). Authorized cumulative max8. |
| New tb_closedloop_control | 0 | 4 | First compile found hex literal adjacent to ternary; second run exposed old sticky completion/progress synchronization in TB; third retained one stale progress trigger; fourth uses new busy and actual in-flight wcnt, PASS20 cases. Max6. |
| New tb_closedloop_raw_algo | 0 | 1 | PASS: real algorithm overflow1, raw_good4/raw_bad2, reader_pass4, algorithm_complete2/2/2. |
| New tb_closedloop_injection | 0 | 2 | First real top elaboration found missing INTX ports in simulation-only stub; corrected direction-only stub, second PASS exactly one pulse routed to writer/algorithm. Max6. |
| New tb_cam_algo_oracle | 0 | 2 | First monitor sampled after FIFO advancement; corrected to posedge pre-NBA with negedge ready drive; second PASS all72 beats per branch/three varying frames. Max6. |
| New tb_cam_algo_oracle_negative | 0 | 1 | Shifted ROI is rejected by named data/sideband mismatches, no simulator error or positive PASS. |
| Recovery preparation bootstrap | 0 | 2 | Windows default GBK could not decode UTF8 T08 manifest; explicit UTF8-sig read fixed it. All236 historical inputs copied with SHA; T08's26 unchanged. No RTL compile attempt was consumed by preparation. |
| Production TD | 0 | 1 started | Attempt1 in its separate directory; 1800s owned process deadline. Cumulative maximum3 across developer and independent tester; no routine repeat after success. |

Every G1 directory has exact command/cwd, own PID/deadline, exit, source hashes and ModelSim raw logs. Build attempt1 has the same metadata and actual RTL/IP/constraint input snapshot. Final execution outcomes are collected in the evidence index; this ledger is updated if another physical attempt becomes necessary.

## Recovery continuation accounting

- Original full writer/checker: cumulative attempt5 completed all data/CRC checks but old flags==15 assertion rejected new sticky completed bit; corrected expected8000000F, cumulative attempt6 PASS. Authorized cumulative max8; no blind retry.
- Controller20cases total5 attempts, latest PASS. RAW+algorithm total2 PASS runs; varying adapter oracle total3 (latestPASS), ROI negative total2 valid rejections, top one-shot total3 (latestPASS). Adapter full1080p two-frame current-pipeline service PASS.
- Current-pipeline core first attempt failed only missing actual output-hold coverage; no numerical/LUT mismatch. Staged test-only stalls+64cycles gave hold64/stalls220 and PASS. Same-bin HE mutation rejected with named branch2 data mismatches. Current-pipeline rate two-frame service PASS. No original protected test/vector was edited.
- TD attempt1 reached routed checkpoint but hit1800s hard deadline before final reports/bit/CWC; taskkill log confirms only owned26456/46816/66988 terminated. No survivor remained. Owned S/T mappings were verified and removed; unrelated R was preserved. Attempt2 changes include the required recovery probe and actual placed critical-path register; source remains fixed during each build. Later build outcomes are in build/attempt*/execution-result.json and final engineering result.
- Actual integrated repair round=0, supplementary opportunity=0. G3/G4 remain unmeasured. All commands retain actual deadlines; output yields are not counted as timeouts.

Final actual TD accounting: attempt1 timeout1800.77s; attempt2 timeout1800.68s; attempt3 completed the exact attempt2 routed checkpoint, native exit0 but final G2 FAIL. Cumulative3/3 production attempts used. No fourth command, no actual integrated repair round and no download.
