# 20261027-2359_fpga-r3-merge — T11.BRD.P1 r3 最小合并与回归

本 run 是 **本机仿真/静态** 工作根：以 r2 源为候选，按 `docs/DECISION_r0g_20261027.md` 做最小合并，并同时跑 T03 70 B oracle、r2 六场景 G1、export 两帧/反压/ACK/负例、静态检查。**没有** TD 综合/布线/STA/bitgen/CWC/下载/Flash，也没有板卡/RK/真实 PCIe。

## 1. 一句话结论

r3 **local PASS**（A–E 全过）；RTL 语义 delta 只有 2 处（ACK 切片、seq=1），pusher 映射经 T03 实测**不需要改**（保留 `bswap256`，r0g 的逆序是 TB payload 解码反了）。G2p/G3/G4 仍 `not_run` / `teammate_required` / `awaiting_hardware`。

## 2. 改动（相对 r2）

| 文件 | 变化 |
|---|---|
| `rtl/brd_cdc_mailboxes.v` | `o_ack_seq <= out_bus[63:32]`、`o_ack_session <= out_bus[31:0]`（r0d ACK 切片） |
| `rtl/brd_board_datapath.v` | `a_seq/b_seq` 复位 `32'd1`（r0d capture identity 从 1 起） |
| `rtl/ref/ep_side/ddr/ddr_frame_pusher.v` | 仅注释（T03 A/B/C 映射复核），`bswap256` 行为不变 |

保留：r1 C8/C9 2FF、r2 `+SLOT_BASE_WORD`、r2 bridge ×8、r2 `brd_export_seq` F1、release 极性、slot base ×32。未采用 export 副本的 `BASE_WORD=SLOT_BASE_WORD`、×128 pusher base、×32 bridge、内部 `utx_sel` grant、删除 sequencer。未改：store/deflate/frame_top/a1_ddr_arb2/P4/constraints/其余板级 RTL。

## 3. 回归（A–E）

| 项 | 结果 | 证据 |
|---|---|---|
| A T03 70 B oracle（store + pusher host 顺序） | PASS：`PRODUCED_LEN=70, BYTE_DIFF=0, FIRST8=78 9c 62 48 4a 4a 5a 01`；映射 A=0、B=69/70、C=67/70 | `evidence/verify-t03.log` |
| B 地址：word 2048 → byte 0x10000；pusher 读 0x10000；无 0x40000 | PASS | `sim/t03map/t03_map.txt`、`evidence/verify-t03.log` |
| C r2 G1 六场景（SCEN0/1/2/3/4、PREP、ARB） | PASS：`CHECKS=150 FAILS=0 VERIFY_R3=PASS` | `evidence/verify-slot-r3.log` |
| D export 两帧/反压/ACK/负例 | PASS：2 帧逐字节 mismatch=0、正确 ACK 释放、错误 ACK 不释放、x_cnt=0、无 watchdog；legacy 模式复现 r0g mismatch=3830/3845 | `evidence/verify-export-r3.log` |
| E 静态 | PASS：`CHECK_FILELIST=PASS`（78）、`STATIC_CHECKS_R3=PASS`（64）、无 .bit/.cwc、旧 manifest 无 r3 SHA | `evidence/filelist-check.log`、`evidence/static-checks.log` |

## 4. 目录

```text
rtl/                 r3 候选（= handoff/brd-p1-r3-20261027/rtl）
constraints/         与 r2 字节相同
tb/                  tb_brd_g1_r3.v / tb_brd_export_r3.v / tb_t03_pusher_map.v
sim/                 run_*.ps1、日志、scen0..4/prep/arb/t03map 的 dumps
evidence/            golden、verifier、静态检查、filelist 日志
manifest-r3.json     冻结清单（本文件与 handoff 副本除外）
result-r3.md         本轮结果
lessons.md           经验
gen_manifest_r3.py   冻结脚本
filelist.tcl         handoff filelist 的工作副本
```

## 5. 复跑（本机）

```powershell
cd workflow/runs/20261027-2359_fpga-r3-merge
powershell -File sim/run_t03.ps1
python evidence/verify_t03_r3.py
powershell -File sim/run_sim_r3.ps1 -Test tb_brd_g1_top -Scen 0
powershell -File sim/run_sim_r3.ps1 -Test tb_brd_g1_top -Scen 3 -NoCompile
powershell -File sim/run_sim_r3.ps1 -Test tb_brd_g1_top -Scen 4 -NoCompile
powershell -File sim/run_sim_r3.ps1 -Test tb_brd_g1_top -Scen 1 -NoCompile
powershell -File sim/run_sim_r3.ps1 -Test tb_brd_g1_top -Scen 2 -NoCompile
powershell -File sim/run_sim_r3.ps1 -Test tb_brd_g1_top -Scen 0 -Prep 1 -Pred 1 -NoCompile
powershell -File sim/run_sim_r3.ps1 -Test tb_brd_arb -NoCompile
python evidence/verify_slot_r3.py
powershell -File sim/run_export.ps1 -Scen 0 -Nf 2
powershell -File sim/run_export.ps1 -Scen 3 -Nf 2
powershell -File sim/run_export.ps1 -Scen 2 -Nf 2
python evidence/verify_export_r3.py
python evidence/static_checks_r3.py
```

`run_export.ps1 -HostModel 1` 用于复现 r0g；本机在某些 shell 权限规则下会拒绝该参数名，等价做法是
`sim/run_legacy.do` + `vsim -do`（结果在 `sim/logs_export_legacy.txt`）。

## 6. 边界

- 本 run 不产出 bit/CWC；不把 r0/r1/r2 的时序数字当成本候选。
- 队友构建前：`python handoff/brd-p1-r3-20261027/build/check_filelist.py` → `python .../gen_al.py` → `01_synth → 02_route → 03_bitgen`。
- 旧 run、旧 manifest、旧报告、`handoff/brd-p1-r2-20261027/**` 均未改写。
