# Hardware-ready — P1-fix3 candidate (READY-FOR-P3)

- frozen candidate: P1-fix3 (issue-02 reset-domain fix); P2 lightweight re-freeze, no rebuild.
- bit: `debug-fix3/prj/ph1p_pcie_integration_Runs/phy_1/ph1p_pcie_integration.bit`
  SHA256 `bfafdf97ff78d6f6d2646ffc706542a0bbbb7e11869043ba754cf68a270813d0` (5224027 B)
- CWC: `debug-fix3/prj/ph1p_pcie_integration_Runs/phy_1/cw/compiled.cwc`
  SHA256 `8d2998b96ef1763c14a1302118235a687488297ce496692b1f6cd95d76981026` (81063 B)
- BID: `debug-fix3/prj/ph1p_pcie_integration_Runs/phy_1/ph1p_pcie_integration_inst.bid` SHA256 `02c5cfdfb0920871b83f8e1d9b34888c5b09d811ce73c1bbdd26bcc98b77541d`
- CWC map: `debug-fix3/cwc-multipiece-map.json` SHA256 `b6127b21dd72eb9919c6fa57f3ade5cb9be365ccf731dc87036cf78354311b57`

## Gates

| Gate | Result |
|---|---|
| G0 | pass (freeze binding: debug-fix3 manifest/report/diff hashes) |
| G1 | pass (inherited P1-r3; tester reran 9/9 ALL PASS, vlog Errors:0) |
| G2 | pass (inherited P1-r3 build; SWNS 0.134 / STNS 0.000 / HWNS 0.020 / HTNS 0.000 ns; 0 violations; Routed; resources within device) |
| G3 | not_run (P3) |
| G4 | not_run |

## P3 preconditions

- User at the board; camera connected (single A); board powered; no hwserver on 5555; TD closed or ready.
- ASCII staging (user-authorized external write): `D:\anlogic\runa_p3\p1fix3_<YYYYMMDD_HHMMSS>\`
  Copy paired `compiled.cwc` + `compiled.bit` (same basename) into this directory; verify SHA both ways.
- Old bits kept parallel: `e81d353b…` (rollback), `2385cded…` (board-tested NOT_MATCHED; do not reuse).

## Step 1 — SRAM download (developer; no Flash)

1. Start TD hwserver (`D:\anlogic\TD_Release_2026.2\bin\hwserver.exe -r -s 5555 -f 12 -v -w 5556 -i 0`) and open cable (`connect_cable -host_name 127.0.0.1:5555 -open`); `read_device_id` must be `PH1P100`.
2. `download -bit <ASCII>\compiled.bit -mode jtag -cable 0` (PROGRAM_SRAM; one attempt, <=5 min). Success: `PRG-2014` + 100% + rc=0; record wall time.
3. Re-read `read_device_id`; close/leave as needed; stop hwserver and free 5555 before handing to GUI.
4. Zero Flash/efuse/SPI/svf; no wiring/power/camera changes; record all commands/exit codes.

## Step 2 — User GUI (only user action)

1. Open TD 2026.2 → ChipWatcher → open the new `compiled.cwc` from the ASCII staging dir.
2. Confirm Bit File points to the same-SHA `compiled.bit`; click Watch; instance `auto_created_cwc1`; Add Signals the 9 `dbg_bank_word0..8` (or the `dbg_mark$dbg_mark_word0..8[31:0]` names shown).
3. Click **Instant Trigger twice, >=10 s apart**; record each 9-word hex value and timestamp; no other settings changes.
4. If any error/code mismatch/no waveform: stop after at most one extra Instant Trigger; record the UI text verbatim; do not re-synthesize/re-download/change CWC.

### Expected values (record as-is even if different)

| Word | Expected |
|---|---|
| word0 | `50434946` (FICP) |
| word1 | `31414B52` (RKA1) |
| word2 | `00010000` (v1.0) |
| word3-7 | record as-is; may be 0/static if DDR/CSI sources are not running — Tier-2 attribution, not a reason to relax criteria |
| word8 | `00000021` (CTRL bit0=1, bit5=1) |

## Step 3 — Evidence / verdict

- Two samples >=10 s; raw hex + timestamps + instance + bit/CWC SHA + commands/rc.
- Identity gate: word0/1/2 must match; any mismatch = stop, no second sample, keep UI text, rollback/old-bit decision to planner.
- Tier-2 per `readback-criteria.md`; word3-7 static/zero recorded and attributed; never infer values.
- Then same-task P3 dev fills `board-readback/readback-record.md` and manifest; integrated tester verifies evidence (no hardware rerun).

## Stop / rollback

- Identity still all-zero or mismatch -> stop; no blind GUI retries; return to planner for diagnosis.
- D37 off / four LEDs -> user power-off 10 s -> power-on -> re-download same bit (one); still abnormal -> stop.
- Rollback: power cycle (SRAM volatile) or re-download old bit `e81d353b…` (SRAM); never Flash.
