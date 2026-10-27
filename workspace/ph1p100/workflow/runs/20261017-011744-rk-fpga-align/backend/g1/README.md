# G1 证据索引（T07.rk-align-backend）

工具：`D:/intelFPGA/18.1/modelsim_ase/win32aloem/{vlib,vlog,vsim}.exe`（ModelSim 10.5b，Intel FPGA Edition）
入口：`tools/pcie_integration/run_sim.ps1`（自动临时 subst 中文路径；用完只撤自己的映射）

## round1（2026-10-17 05:0x；修复 F2 重复声明 + F1 release 之后）

| 子目录 | TB（`-Tb` 模块名） | TbFiles | 结果 |
|---|---|---|---|
| `msim/r1_tb_ddr_frame_pusher_rka1/` | `tb_ddr_frame_pusher_rka1` | `tb/tb_ddr_frame_pusher_rka1.v` | **ALL PASS**（20387 TLP；含 PHASE11 B 路 release、PHASE12 A/B 交叉） |
| `msim/r1_tb_csi_checked/` | `tb_csi_checked` | `tb/tb_csi_checked.v`（需 `-Defines MIPI_PHY_SIM_STUB`） | **ALL PASS** |
| `msim/r1_tb_ep_bar_win_rka1/` | `tb_ep_bar_win_rka1` | `tb/tb_ep_bar_win_rka1.v` | **ALL PASS** |
| `msim/r1_tb_ddr_wr_arb_peer/` | `tb_ddr_wr_arb`（**模块名**，文件叫 `tb_ddr_wr_arb_peer.v`） | `tb/tb_ddr_wr_arb_peer.v` | **ALL PASS** |

判据（每个目录）：`vlog.log` 末行 `Errors: 0` + `vsim.log` 里 `ALL PASS`；
四个 run 的日志时间戳都晚于本轮 RTL 的全部修改（不再出现"旧 PASS 日志早于文件修改"）。
默认入口不含任何 `-suppress`：round0 的 vlog-2388 已由源码修复消除。

## round2（当前冻结输入，2026-10-17 05:54；G2 时序重构之后）

| 子目录 | TB（`-Tb` 模块名） | TbFiles | 结果 |
|---|---|---|---|
| `msim/r2_tb_csi_integrity_diff/` | `tb_csi_integrity_diff` | `tb/tb_csi_integrity_diff.v`（+ 参照副本 `tb/csi_rx_packet_integrity_ref.v`，已进 `compile_checked.f`） | **ALL PASS**（差分 oracle：680 拍载荷逐拍一致、0 失配；abort/计数 ≤2 拍窗口） |
| `msim/r2_tb_csi_checked/` | `tb_csi_checked` | `tb/tb_csi_checked.v`（需 `-Defines MIPI_PHY_SIM_STUB`） | **ALL PASS** |
| `msim/r2_tb_ddr_frame_pusher_rka1/` | `tb_ddr_frame_pusher_rka1` | `tb/tb_ddr_frame_pusher_rka1.v` | **ALL PASS**（20387 TLP） |
| `msim/r2_tb_ep_bar_win_rka1/` | `tb_ep_bar_win_rka1` | `tb/tb_ep_bar_win_rka1.v` | **ALL PASS** |
| `msim/r2_tb_ddr_wr_arb/` | `tb_ddr_wr_arb`（**模块名**，文件叫 `tb_ddr_wr_arb_peer.v`） | `tb/tb_ddr_wr_arb_peer.v` | **ALL PASS** |

判据（每个目录）：`vlog.log` 末行 `Errors: 0` + `vsim.log` 里 `ALL PASS`；五个 run 的日志时间戳
（05:54:05–05:54:39）都晚于本轮 RTL 全部修改（`rtl/checked/csi_rx_packet_integrity.v` 05:50:06、
`rtl/checked/crc16_upd4.v` 05:49:08）。默认入口仍不含任何 `-suppress`。

round2 新增的差分 TB 说明：把 `rtl/checked/csi_rx_packet_integrity.v`（重构版）与
`sim/tb/csi_rx_packet_integrity_ref.v`（**只读原源** `fpga/csi2/src/csi/csi_rx_packet_integrity.v`
的重命名副本，SHA 记在文件头）并联，同一激励喂两个 DUT，覆盖好帧/坏 CRC/WC 边界/行长与行数不符/
包内 idle 超时/帧超时/坏 ECC/未知 DT/非选中 VC/FE 无帧/FS 打断后恢复/复位后恢复/200 随机包。
判定细节见 `../change-report.md` §8.2（差分过程抓到并修掉了两个真实语义缺陷）。

## round3（当前冻结输入，2026-10-17 06:50；入口 BOM 修复之后，**用文档化默认命令原样复跑**）

| 子目录 | TB / 用途 | 结果 |
|---|---|---|
| `msim/r3_tb_csi_integrity_diff/` | `tb_csi_integrity_diff`（差分 oracle） | **ALL PASS**（`payload beats compared = 680, payload mismatches = 0`） |
| `msim/r3_tb_csi_checked/` | `tb_csi_checked`（`-Defines MIPI_PHY_SIM_STUB`） | **ALL PASS** |
| `msim/r3_tb_ddr_frame_pusher_rka1/` | `tb_ddr_frame_pusher_rka1` | **ALL PASS**（20387 TLP） |
| `msim/r3_tb_ep_bar_win_rka1/` | `tb_ep_bar_win_rka1` | **ALL PASS** |
| `msim/r3_tb_ddr_wr_arb/` | `tb_ddr_wr_arb`（文件 `tb_ddr_wr_arb_peer.v`） | **ALL PASS** |
| `msim/r3_entry_before_fix/` | **入口负对照**：修复前的 `run_sim.ps1` 在文档化命令下的失败留痕 | `vlog Errors: 0` 但**无 `run.do`/`vsim.log`**、stderr `WriteAllLines … 空路径名是非法的`、exit 0（`decode_view.txt`：PS 视图 136/76 行 vs 真值 144/81） |
| `msim/r3_neg_m1/` | **oracle 负对照**：项目外隔离树注入 M1（`crc_next` 固定 4 字节推进），修复后入口跑差分 TB | **FAIL: 507 mismatches**（证明 oracle 能拒绝坏实现；该目录 `mutation.json` 因原实例中断未落盘——完整复跑见下表 `r3v_neg_m1/`） |

判据（每个 TB 目录）：`vlog.log` 末行 `Errors: 0` + `run.do`/`vsim.log` 齐备 + `commands.log` 有
`cmd /c vsim …` 与 `vsim exit=0` + `vsim.log` 里 `ALL PASS`；时间 06:50:10–06:50:30，晚于全部输入修改。
**注意**：`-File` 下进程退出码不可作为判据（修复前的中止也是 exit 0）——必须看产物。

### round3 复核（新修复实例 r3v；2026-10-17 07:10–07:13）

原 round3 实例在收尾时上游请求超限失效；主重建的新修复实例（write_scope 不变）完成逐项复核与独立复跑。
**新增证据一律用 `r3v_` 前缀，与 `r3_*` 并存（原证据未覆盖、未删除）**：

| 子目录 | 用途 | 结果 |
|---|---|---|
| `msim/r3v_tb_*/`（5 个） | 文档化默认命令原样复跑五个 TB（07:10:26–07:10:47） | 全部 `vlog Errors: 0` + `run.do`/`vsim.log` 齐备 + `vsim exit=0` + **ALL PASS**（差分 680 拍 0 失配；pusher 20387 TLP）——与 `r3_*` 一致 |
| `msim/r3v_neg_m1/` | M1 oracle 负对照**完整复跑**（新隔离树 `%TEMP%/opencode/r3negv`） | **`FAIL: 507 mismatches`**；**含 `mutation.json`**（shadow `e0e08a86…` 与原 run 完全相同；原 `r3_neg_m1/` 的 mutation.json 因原实例中断未落盘） |
| `msim/r3v_entry_before_fix/` | 修复前入口失败复现：冻结件**去 BOM 的逐字节副本**（= 修复前字节）+ 文档化命令形式 | `vlog Errors: 0` 后中止：无 `run.do`/`vsim.log`、stderr `WriteAllLines…空路径名是非法的`（PS 视图 L116）、exit 0；`decode_view.txt`（136/76 vs 144/81 行、修复前 SHA 全值）、`r3v_entry_ast.txt`（frozen→赋值语句=1，no-BOM→0） |

补记：原实例留在 `r3_entry_before_fix/entry_ast_check.ps1` 的校验脚本自身是"UTF-8 无 BOM + LF + 中文注释"，
被同一缺陷击中（`$PSScriptRoot` 被吞 → 运行即失败、未产出），失败留痕在
`r3v_entry_before_fix/old_ast_script_attempt.txt`；等价语义检查由纯 ASCII 的
`r3v_entry_before_fix/r3v_entry_ast_check.ps1` 完成。详见 `../change-report.md` §10.5。

`g1/crc16_upd4.generated.v`（3,475 B）说明：它是 round2 早期的**单体变体中间产物**，**不是**冻结生产文件
`rtl/checked/crc16_upd4.v`（8,905 B，`20520D04…`）的副本；生产文件可由冻结生成器
`tools/pcie_integration/gen_crc16_flat.py` 逐字节复现。保留仅作过程留痕，勿当候选输入。

失败/中间过程的证据（保留、不删；它们是 round0 三维 FAIL 的直接物证）：

* `msim/tb_csi_checked/vlog.log`：round0 冻结输入在 04:03:28 的 `Errors: 1`（vlog-2388 重复声明）
  与 03:41 的旧 `vsim.log` 并存 —— 正是 functional/engineering/system 三维指出的"证据未绑定"。
* `msim/dbg*/`：开发期定位日志（TB 自身 bug：假 AXI 从机重复上一拍、task 传值、位宽截断等）。
* `msim/compile1|pristine|top|full/`：ModelSim 兼容性排查（peer 源隐式网声明顺序）。

未在本包的仿真范围：serdes PHY 原语、真实相机几何、RKA1 在 RK 上的行为（见 `../hardware-ready.md`）。
