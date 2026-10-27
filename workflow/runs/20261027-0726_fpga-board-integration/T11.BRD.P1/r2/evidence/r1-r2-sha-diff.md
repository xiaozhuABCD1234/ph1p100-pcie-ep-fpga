# r1 vs r2 SHA comparison (T11.BRD.P1 round 2)

- repo root: `D:/fpga/repos/ph1p100-pcie-ep-fpga`
- r1 work root: `workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r1`
- r2 work root: `workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r2`
- rule: round 2 may only change `sim/**`, `evidence/**`, docs, the manifest
  and the handoff package. RTL / constraints / filelist must stay byte-identical.

## rtl/**

- r1 files: 16   r2 files: 16
- same  `a1_core_fix01/a1_ddr_arb2.v`  B84019BDA057AFE82FF558E0848D6171FA12732BD8CDB7C6239CB71B3F81D6BA  (4164 B)
- same  `a1_core_fix01/a1_ddr_slot_store.v`  6C619CF90E54385D667F1EC0F63CC87EE58AADD3C42143330AC4945EB47DEFE9  (22093 B)
- same  `a1_core_fix01/a1_deflate_core.v`  A91C2ED82FBEF654C4E065B64AE1CC268CA232FEAA26FDD313C58D8740F81B3E  (80501 B)
- same  `a1_core_fix01/a1_frame_top.v`  CDA28C941321F28DF8318DACAF291F6268EA5E4D6EA9FAF9921ED824B3A2160C  (27245 B)
- same  `a1_raw_crop.v`  33A6FEE77FD1AA67A31CACF26DD5530E5E2EA474EE655CBD5F1D98D887C5D72D  (7257 B)
- same  `brd_a1_core_pll.v`  6E484834EE0274B5D985DC87D266027B96A1BB87144FBAF0BA026E2AAD5FB89F  (3654 B)
- same  `brd_board_datapath.v`  3FF99847C5F7393EA39F56FFDBB345D874553FA180CCD544AD1C64763E13CFDF  (32090 B)
- same  `brd_cam_fe.v`  C96A6575250E0D48EBF6EEB489A3295191741743CDAEC55A553506A4E3785EA5  (6462 B)
- same  `brd_cdc_mailboxes.v`  5F5651B7E91A6EAC01066FB34E0899E0315367DEC68F2E0BDD8696FA746CDD00  (18173 B)
- same  `brd_ddr_rd_arb.v`  66AE727C73E5D70B513DAEFE9C3FB61D7C074D4ADB5EE2BDA887C092CCABE396  (6934 B)
- same  `brd_export_seq.v`  BCE77E897A2860DA5E5ED7BC190530E0AC3F6CB748D57B4796407AA341C3FBE2  (4943 B)
- same  `brd_integrated_top.v`  957BC59C3A28D5B8D8EECF329E5669FEE03D71666080332ACE6B616E46A52E0E  (93569 B)
- same  `p2_ddr_bridge.v`  790D8226EC69499C87B92B0E4A05AC0F26915F57B96BD541AFFDCDAC8E740A61  (31332 B)
- same  `ref/common/BDF.v`  C59A0AACF5200B349B9B549E886EA5256FCB525E7E224C5138AC7FF6CD72ADF1  (2998 B)
- same  `ref/common/TLP_FMT_TYPE.v`  167BCD7FB3213A886AFFDED2945F0FA46A0F1D5B92FBFB55761E6ECF4E98B9E4  (3057 B)
- same  `ref/ep_side/ddr/ddr_frame_pusher.v`  E0DD673CD19DD09C0343DD5811A6BC4EFBFAB48ECE2AB5E59396A17EF6F57A5B  (48909 B)

**rtl_delta = 0** (identical files: 16)

## constraints/**

- r1 files: 2   r2 files: 2
- same  `brd_board.sdc`  D69A5092E87A4DA1A648FD407870F12CA021856CF34EF21D53C1BC930B65CAF0  (4485 B)
- same  `ph1p_pcie_case_ep.adc`  67831295AEF0F5AFBEC9F2DFBF062922B793A6586E56C074ACE21787B6365C98  (5668 B)

**constraints_delta = 0** (identical files: 2)

## filelist.tcl

- r1 (package): `handoff/brd-p1-r1-20261027/filelist.tcl` sha256 `41A61493335B84FA8AAFB1FF41FB99C2F8AC71D5E73F018187F567BA277A84A3`
- r2 (work root): `workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r2/filelist.tcl` sha256 `41A61493335B84FA8AAFB1FF41FB99C2F8AC71D5E73F018187F567BA277A84A3`
- identical: True

**filelist_delta = 0**

## r2 files (informational: every r2-only path is sim/evidence/doc/handoff work)

- `cdc-list.md`
- `evidence/adler-rootcause.md`
- `evidence/cdc-static.log`
- `evidence/expected_raw.json`
- `evidence/gen_expected_raw.log`
- `evidence/gen_expected_raw.py`
- `evidence/golden-r2.json`
- `evidence/golden-r2.md`
- `evidence/historical-evidence-sha256.json`
- `evidence/r1_r2_sha_diff.py`
- `evidence/sdc-groups.md`
- `evidence/tb-fix-notes.md`
- `evidence/verify_slot_r2.log`
- `evidence/verify_slot_r2.py`
- `filelist.tcl`
- `gen_manifest_r2.py`
- `sim/arb/work/_info`
- `sim/arb/work/_lib.qdb`
- `sim/arb/work/_lib1_0.qdb`
- `sim/arb/work/_lib1_0.qpg`
- `sim/arb/work/_lib1_0.qtl`
- `sim/arb/work/_vmake`
- `sim/compile_r2.log`
- `sim/prep/sim_meta.txt`
- `sim/prep/tb_probe_r2.txt`
- `sim/prep/work/_info`
- `sim/prep/work/_lib.qdb`
- `sim/prep/work/_lib1_0.qdb`
- `sim/prep/work/_lib1_0.qpg`
- `sim/prep/work/_lib1_0.qtl`
- `sim/prep/work/_vmake`
- `sim/run_arb_r2.log`
- `sim/run_prep_r2.log`
- `sim/run_scen0_r2.log`
- `sim/run_scen1_r2.log`
- `sim/run_scen2_r2.log`
- `sim/run_scen3_r2.log`
- `sim/run_scen4_r2.log`
- `sim/run_sim_r2.ps1`
- `sim/run_tb_brd_arb_scen0_p0_d0.do`
- `sim/run_tb_brd_g1_top_scen0_p0_d0.do`
- `sim/run_tb_brd_g1_top_scen0_p1_d1.do`
- `sim/run_tb_brd_g1_top_scen1_p0_d0.do`
- `sim/run_tb_brd_g1_top_scen2_p0_d0.do`
- `sim/run_tb_brd_g1_top_scen3_p0_d0.do`
- `sim/run_tb_brd_g1_top_scen4_p0_d0.do`
- `sim/scen0/sim_meta.txt`
- `sim/scen0/tb_probe_r2.txt`
- `sim/scen0/work/_info`
- `sim/scen0/work/_lib.qdb`
- `sim/scen0/work/_lib1_0.qdb`
- `sim/scen0/work/_lib1_0.qpg`
- `sim/scen0/work/_lib1_0.qtl`
- `sim/scen0/work/_vmake`
- `sim/scen1/tb_probe_r2.txt`
- `sim/scen1/work/_info`
- `sim/scen1/work/_lib.qdb`
- `sim/scen1/work/_lib1_0.qdb`
- `sim/scen1/work/_lib1_0.qpg`
- `sim/scen1/work/_lib1_0.qtl`
- `sim/scen1/work/_vmake`
- `sim/scen2/tb_probe_r2.txt`
- `sim/scen2/work/_info`
- `sim/scen2/work/_lib.qdb`
- `sim/scen2/work/_lib1_0.qdb`
- `sim/scen2/work/_lib1_0.qpg`
- `sim/scen2/work/_lib1_0.qtl`
- `sim/scen2/work/_vmake`
- `sim/scen3/sim_meta.txt`
- `sim/scen3/tb_probe_r2.txt`
- `sim/scen3/work/_info`
- `sim/scen3/work/_lib.qdb`
- `sim/scen3/work/_lib1_0.qdb`
- `sim/scen3/work/_lib1_0.qpg`
- `sim/scen3/work/_lib1_0.qtl`
- `sim/scen3/work/_vmake`
- `sim/scen4/sim_meta.txt`
- `sim/scen4/tb_probe_r2.txt`
- `sim/scen4/work/_info`
- `sim/scen4/work/_lib.qdb`
- `sim/scen4/work/_lib1_0.qdb`
- `sim/scen4/work/_lib1_0.qpg`
- `sim/scen4/work/_lib1_0.qtl`
- `sim/scen4/work/_vmake`
- `sim/sim_tb_brd_arb_scen0_p0_d0_20261027_175011.log`
- `sim/sim_tb_brd_arb_scen0_p0_d0_20261027_175011.log.err`
- `sim/sim_tb_brd_g1_top_scen0_p0_d0_20261027_174521.log`
- `sim/sim_tb_brd_g1_top_scen0_p0_d0_20261027_174521.log.err`
- `sim/sim_tb_brd_g1_top_scen0_p0_d0_20261027_174615.log`
- `sim/sim_tb_brd_g1_top_scen0_p0_d0_20261027_174615.log.err`
- `sim/sim_tb_brd_g1_top_scen0_p0_d0_20261027_174701.log`
- `sim/sim_tb_brd_g1_top_scen0_p0_d0_20261027_174701.log.err`
- `sim/sim_tb_brd_g1_top_scen0_p1_d1_20261027_175003.log`
- `sim/sim_tb_brd_g1_top_scen0_p1_d1_20261027_175003.log.err`
- `sim/sim_tb_brd_g1_top_scen1_p0_d0_20261027_174951.log`
- `sim/sim_tb_brd_g1_top_scen1_p0_d0_20261027_174951.log.err`
- `sim/sim_tb_brd_g1_top_scen2_p0_d0_20261027_174956.log`
- `sim/sim_tb_brd_g1_top_scen2_p0_d0_20261027_174956.log.err`
- `sim/sim_tb_brd_g1_top_scen3_p0_d0_20261027_174924.log`
- `sim/sim_tb_brd_g1_top_scen3_p0_d0_20261027_174924.log.err`
- `sim/sim_tb_brd_g1_top_scen4_p0_d0_20261027_174933.log`
- `sim/sim_tb_brd_g1_top_scen4_p0_d0_20261027_174933.log.err`
- `sim/tb_brd_g1_r2.v`
- `sim/transcript`

## verdict

- rtl_delta = 0
- filelist_delta = 0
- overall_delta = 0

**RTL_DELTA_ZERO=TRUE**
