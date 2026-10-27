# T10.b17-paxi-native r1 -- result

Date: 2026-10-26.  Run: `20261020-0209_singleA_aplus_closedloop`.
Candidate: `r1` = **one bitgen + one CWC from the frozen r0 routed database**
(`r0/td/a1_board_Runs/phy_1/a1_board_pr.db`), no re-synthesis, no re-route, no
source/SDC/seed/clock change.  Board branch attempted once, blocked before any
COM8 access; **downloads = 0**.

## 0. Verdict

| dimension | verdict | evidence |
|---|---|---|
| functional | **PASS (inherited, bound by hashes)** | r0 16-word native test, S1/S2/S3, P1 three goldens, v6 structure and negative controls all PASS; r1 changed no source and reused the same routed DB. r1 did not re-run simulation. |
| engineering | **PASS (diagnostic candidate only)** | 1 bitgen + 1 CWC from the same routed DB; 0 violations / 26,705 endpoints; SWNS **+0.002 ns**, HWNS **+0.020 ns**, period **+2.200 ns**; ERAM **102/300**; bit/CWC/BID frozen; `cw/compiled.*` byte-identical to the parent files. |
| system / board | **blocked (FTDI absent)** | `FTDI_PRESENT=0`, no `VID_0403&PID_6042`, no COM8 (only COM3/COM4), 0 downloads, 0 COM8 opens, **v6 not decoded**. |

`timing_caveat=thin_margin_+0.002`.  This is **not production timing sign-off**.

## 1. Planner r1 decision

The r0 package stopped at the dev-plan §6 floor (WNS < +0.003 ns) with 0
violations.  The r1 instruction explicitly accepts **+0.002 ns / 0 violations**
as a **diagnostic candidate** and directs one bitgen + one CWC from the already
routed DB.  Applied as a planner waiver for this diagnostic bitstream only:

- no SDC relaxation, no seed change, no clock change, no ERAM/PAXI change;
- no re-synthesis and no re-route;
- `02_bitgen.tcl` still fails closed on any negative setup/hold/period slack and
  re-checked the final STA before bitgen (`P2_BITGEN_STA_SETUP=0.002/0.000
  HOLD=0.020/0.000 PERIOD=2.200`);
- the critical path remains in the frozen A+ deflate core
  (`u_a1/u_a1/u_core/len_r_reg[5]` -> `add9_syn_221.fci`), not in the v6
  diagnostics.

## 2. Build inputs (frozen r0 route)

| item | value |
|---|---|
| routed DB | `r0/td/a1_board_Runs/phy_1/a1_board_pr.db`, 32,856,638 B |
| routed DB SHA256 | `6033715A030B096B050AECD47AECCDA0DEBC682F5CD96153F5115ED173799632` |
| r0 candidate manifest | SHA256 `02929A24DB49385FDA178E601C31255DE0CBA9E94125EE32DE60E0CBCDBFBF78` |
| r0 routed status | SWNS +0.002 / STNS 0; HWNS +0.020 / HTNS 0; SHA256 `7F684F5C...1AA1` |
| source set | 59 HDL entries in `a1_board.al`, identical to r0 after path normalization; all 11 `changed-src` SHA256 match the r0 manifest |
| SDC / ADC | `p2_board.sdc` `92849824...6D95`, `board_p2.adc` `1CB30346...1580`, byte-identical to r0 |
| build scripts | `02_bitgen.tcl` `EA7E8689...CAF0`, `03_cwc.tcl` `2E1C71D1...57F0`, byte-identical to r0 |
| device / corner | PH1P100SBG484, speed 3, Routed, STA coverage 97.18%, constraint `T:/p2_board.sdc` |

`open_project` rewrote only `r1/td/a1_board.al` metadata (`Path="T:/"` ->
`Path="T:/."`, added `<UCode>00000011</UCode>`, `./src` -> `src`).  The 59-file
source set and all 11 source hashes are unchanged.

## 3. Bitgen + CWC (one each)

| item | value |
|---|---|
| bitgen | **1**, exit 0, `P2_CANDIDATE_BIT_GENERATED_NO_DOWNLOAD`, 10.05 s wall |
| CWC | **1**, exit 0, `P2_MATCHING_CWC_EXPORTED_NO_DOWNLOAD` |
| bit | `r1/td/a1_board.bit`, 5,224,022 B, SHA256 **`20AC69F5307B1F0577BAB3144C09BDB56B5283F4449248851F2F9D621BD7DFFA`** |
| CWC | `r1/td/a1_board.cwc`, 110,168 B, SHA256 **`76C0154FF4BFCE0C2A1C61140C54A030EDE7471313E7C1078CA634DEB6B638C6`** |
| BID | `r1/td/a1_board_inst.bid`, 96,813 B, SHA256 **`0BDA22FC34998D98CE11A1AFF76E7C79A1094339682C5F8F2C2E405FEA8000A6`** |
| `cw/compiled.bit` | 5,224,022 B, SHA256 `20AC69F5...7DFFA` -- **byte-identical to `a1_board.bit`** |
| `cw/compiled.cwc` | 110,168 B, SHA256 `76C0154F...B638C6` -- **byte-identical to `a1_board.cwc`** |
| CWC content check | `<phy_eram ...>` present, incomplete `<logic_eram .../>` rejected by `03_cwc.tcl` |

The r1 bit/CWC/BID differ from the b15 r0 files (b15 bit
`C9292CA1...C40F`, CWC `A5036B6D...4626`, BID `3DF29D6C...CDD5`), so the export
is a new candidate, not a stale copy.

Final STA re-check at bitgen (`r1/td/candidate_timing.rpt`):
`SWNS 0.002 / STNS 0.000`, `HWNS 0.020 / HTNS 0.000`, `Period Check WNS 2.200`,
`0 Viol Endpoints / 26,705 Total Endpoints`; abnormal-target report is empty
except its two section headers.

## 4. Board branch

`r1/board/log/board_blocked.txt`:

```text
FTDI_PRESENT=0
board_blocked_reason=FTDI_0403:6042_absent
downloads=0
```

- FTDI preflight was run before any COM8 access: `Get-PnpDevice -PresentOnly`
  found no `VID_0403&PID_6042`; `[System.IO.Ports.SerialPort]::GetPortNames()`
  returned only `COM3,COM4`, so **COM8 does not exist**.
- Per dev-plan §7.1 this is the legal `board=blocked` branch, not a FAIL.
  The download script was never entered (`download_b17.log` absent), hwserver
  count 0, no capture file, **no second download and no Flash**.
- Because the board branch stopped at preflight, **no r1 v6 packet was received
  or decoded**, and no timeout/retry/giveup/enc/exported/capture frame counters
  exist for r1.  No board PASS is claimed.  The offline v6 evidence remains the
  r0 `tb_status_v6` + S1/S2/S3 result, bound by the r0 manifest hash above.

## 5. Limits and rollback

- Claimed: one diagnostic SRAM-downloadable bitstream and its matching CWC,
  generated from the frozen r0 routed DB; offline functional evidence inherited
  from r0.
- Not claimed: production timing sign-off (+0.002 ns caveat), board behavior,
  v6 board decode, DDR sustained bandwidth, dual A/B, PCIe/RK, Flash, G4.
- T10 remains blocked.  r1 does not close the parent task.
- Rollback: delete/ignore `T10.b17-paxi-native/r1/**` and the r1 manifest; r0,
  b15/b13 trees and production files are untouched.  The r1 DB copy is a
  byte-identical copy of the r0 routed DB, not a new place/route.

## 6. Artifact index

`CANDIDATE-MANIFEST-b17-paxi-native-r1.json`, `r1/artifact-hashes.txt`,
`r1/result-r1.md`, `r1/lessons-r1.md`,
`r1/td/{a1_board.bit,a1_board.cwc,a1_board_inst.bid,cw/compiled.bit,cw/compiled.cwc}`,
`r1/td/{bitgen_console_r1.log,cwc_console_r1.log,run_bitgen_cwc_driver_r1.log,candidate_timing.rpt,candidate_abnormal.rpt,candidate_hashes_r1.txt}`,
`r1/board/{run_board_b17_r1.ps1,dl_b17_r1.tcl,log/board_blocked.txt,log/ftdi_preflight.txt}`,
`r1/make_manifest_b17_r1.py`.
