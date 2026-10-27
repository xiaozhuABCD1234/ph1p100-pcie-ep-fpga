# dev-notes — T01.tool-E2（6.2.3 全链构建 + 同口径对比 + 0.300ns 如实评定 + 条件性 bitgen）

- 角色：fpga-dev（E2）；日期：2026-10-17；run：`workflow/runs/20261017_153201_T01_ddr1333_integration/`
- 依据：`dev-plan.md` §4.2；派发注记（超时：综合≤1800s、route≤3600s、bitgen≤900s；绝对路径；D 盘 ASCII 目录；不下硬件/无 GUI）
- 状态：**ready-for-test**（6 个阶段全部执行完毕并留档；bitgen 为条件性延伸且已满足条件；未下载/未上板）
- 基线零漂移：002820 manifest `8f8e4efe…` / bit `4d591c31…`（运行前后复算一致）；run1 `d71057f3…` / run2 `9b3e5d00…` 只读复核一致

## 1. 产物

| 产物 | 路径 | SHA256（摘要/完整） |
|---|---|---|
| 新 runner（仓库，新建，唯一新增工具脚本） | `tools/td/run_rgb565_ddr1333.py`（13,443 B） | `4c42e3685b990509f625f960afaea78c5e4e9b665483143daa27336ca859755e` |
| E2 证据（全阶段+对比表+评定；正名） | `docs/evidence/ddr1333_build_sta_20261017.json`（81,640 B） | `7c633508480a886ed63aa89f14f0195f068cc4f9a3d01e0abed0c2115fee9010` |
| E2 证据（派发注记名，同内容别名） | `docs/evidence/ddr1333_integration_timing_20261017.json`（81,640 B） | 同 `7c633508480a886ed63aa89f14f0195f068cc4f9a3d01e0abed0c2115fee9010` |
| 执行记录（1333 候选内） | `native_build.json/.txt`、`native_route.json/.txt`、`native_bitgen.json/.txt` | 见证据 `artifacts_inventory.native_stage_records` |
| 执行记录（1600ctl 候选内） | 同上 6 件 | 同上 |
| 控制台全文日志（本目录） | `dev-notes-E2-run-{ddr1333,ctl}-{build,route,bitgen}.log` | 见证据 `artifacts_inventory.tee_logs` |
| gate 输出（本目录） | `dev-notes-E2-gate-ddr1333.json`、`dev-notes-E2-gate-ctl.json` | 见证据 `gate_0_300` |
| 独立再抽（本目录） | `dev-notes-E2-sta-recheck-{ddr1333,ctl}.log` | 见证据 `sta_rechecks` |
| 形状/时钟/分组复核（本目录） | `dev-notes-E2-clock-summary-ddr1333.txt`、`dev-notes-E2-per-group-margins-ddr1333.txt`、`dev-notes-E2-ctl-postroute.log` | 随本目录留档 |
| 证据生成器（本目录） | `dev-notes-E2-assemble-evidence.py` | 可复算两份证据 JSON（断言不覆盖既有） |

- **证据文件名双名说明**：dev-plan §4.2 名义名=`ddr1333_build_sta_<date>.json`；派发注记名=`ddr1333_integration_timing_<date>.json`。二者**同内容**（同一生成器一次写出），任一可引用；已在 JSON 内 `evidence_files` 互相登记。

## 2. 执行记录（实际命令/退出码/标记/时长）

命令统一：`& 'C:\Program Files\Python311\python.exe' -X utf8 -B <repo>/tools/td/run_rgb565_ddr1333.py <候选> <stage> --timeout <T>`（cwd=`C:/Users/czz`；TD 子进程 cwd=工程目录，正斜杠）。

| 候选 | 阶段 | 命令(脚本) | exit | 完成标记 | 时长 | 关键产物 |
|---|---|---|---|---|---|---|
| ddr1333_20261017_160741 | build | `./build_rgb565.tcl`（`5aa25fd2…`） | 0 | `RGB565_SYNTHESIS_RETURNED` ✅ | 192.3s | gate.db `e727732f…`（10,481,662 B） |
| ddr1333 | route | `./route_rgb565.tcl`（`019db289…`） | 0 | `RGB565_ROUTE_RETURNED_CHECK_REPORTS_NO_BIT` ✅ | 764.6s | pr db `8fecd7c1…`；capture_timing `b7947e91…` |
| ddr1333 | bitgen | `./bitgen_rgb565.tcl`（`fcce5e20…`）+body（`7999f5f7…`） | 0 | `CAMERA_DDR_DISPLAY_CANDIDATE_GENERATED_NO_DOWNLOAD` ✅ | 32.5s | bit `b7ef91cf…`（5,224,029 B）；bid `cd551e7e…` |
| ddr1600ctl_20261017_160741 | build | 同脚本 | 0 | 同上 ✅ | 197.1s | gate.db `99020b8d…`（10,063,754 B） |
| ddr1600ctl | route | 同脚本 | 0 | 同上 ✅ | 892.3s | pr db `79aa5678…`；capture_timing `72ead265…` |
| ddr1600ctl | bitgen | 同脚本 | 0 | 同上 ✅ | 34.4s | bit `1447b243…`（5,224,029 B）；bid `46bda1a6…` |

- 工具锚（每次运行断言/记录）：CLI `D:/anlogic/TD_Release_2026.2/bin/td_commands_prompt.exe`=`2629e474…C1223`（断言命中）；td.exe `fa2a5ac6…`、IpTool `5b0654aa…`、arch `939ec294…`、license `dc19fee6…`（复算命中）。
- 无超时、无失败、无覆盖：`native_*` 均为新建；无 `timed_out`；任务栏无残留 TD 进程（运行结束后进程表复核）。

## 3. 最终 STA（route 同口径；bitgen 报告复验一致）

| 候选 | setup/STNS | hold/HTNS | Period WNS | 组数 | 违规端点合计 | ddr_user 周期 | 报告 SHA |
|---|---|---|---|---|---|---|---|
| **1333** | **0.230 / 0** | 0.020 / 0 | **3.201** | 66（33 Path Group 行） | 0 | 166.650 MHz / 6.001 ns | `b7947e91…`（bitgen 复验 `8513ed74…`，数值相同） |
| **1600ctl** | **0.128 / 0** | 0.020 / 0 | **2.200** | 68（34 行） | 0 | 200.000 MHz / 5.000 ns | `72ead265…`（bitgen 复验 `db8121cb…`，数值相同） |
| 002820（6.2.2 冻结） | 0.000 / 0 | 0.020 / 0 | 2.200 | 66 | 0 | 200 MHz / 5.000 ns | route `c82a0385…`；bitgen `b2a78335…` |

- **独立再抽一致**：另写的行扫描解析器（与 runner 正则不同实现）复核两报告，字段、Viol Endpoints 计数（66/68，和=0）、Path Group 行数（33/34）、`Confidence: Routed` 全部一致 → 记入证据 `sta_rechecks`。
- **报告形状人工复核（显式设定 gate 组数）**：1333=66（Path Group 名有序列表与 002820 **完全相同**，66 组统计全部 0 违例）；1600ctl=68（34 行；名称集合与 1333/002820 相同，唯一差异=`mcu_clk→mcu_clk` 组多出现一次 14→15，复现 2026-10-15 记载的 68 组形状变化：APB 回读/transfer_done 端点）。禁止按文件现有组数自证——本判定为**复核后显式设定**。
- 关键端点组（Clock Summary 逐项，1333）：ddr_user **0.291**、mipi_a_byte_clk **0.230**（全局最差）、pclkx1 0.713、mcu_clk 8.208、sys_clk50m 9.551，其余域≥。ctl：ddr_user 0.128、mipi 0.214、pclkx1 0.461、mcu 7.183。
- 资源（route `capture.area`）：1333 LUT 15024/REG 24520/ERAM 77/DSP 2/PLL 3；1600ctl 15317/24260/77/2/3；002820 16171/30825/77/2/3（REG 大幅下降为 **6.2.3 工具效应**，被 1600ctl 对照行证实；1333↔ctl 间差 −293 LUT/+260 REG）。

## 4. 0.300ns 如实评定（探索轮目标口径，非器件保证）

- gate 命令（显式组数）：`check_timing_margin.py <capture_timing.rpt> --min-setup-ns 0.3 --expected-endpoint-groups {66|68}`。
- **1333：`accepted=false`，exit 1**——setup 0.230 < 0.300（差 0.070）；其余条件全过（TNS=0、hold/period≥0、66 组、违规 0）。ddr_user 域 0.291 亦差 0.009。
- **1600ctl：`accepted=false`，exit 1**——setup 0.128 < 0.300（差 0.172）；其余条件全过（68 组、违规 0）。
- 一句话：同工具同脚本下 1333 的 nominal setup 裕量（0.230ns）比 1600（0.128ns）多 +0.102ns，且两者均越过"零违例"，但均**未达 0.300ns 探索目标**——这是本轮合法数据，不产"达标"结论、不产预留实验、不夸大。

## 5. 同口径对比表（摘要；完整字段见证据 JSON `comparison_table`）

| 候选 | 工具 | 最终 setup(route) | hold | period | 组数/违规 | ddr_user | LUT/REG | 脚本(build/route) | 备注 |
|---|---|---:|---:|---:|---|---|---|---|---|
| **1333（新 IP 主候选）** | 6.2.3 | **0.230** | 0.020 | 3.201 | 66/0 | 6.001ns | 15024/24520 | `5aa25fd2`/`019db289` | nominal；唯一变量=IP 闭包+速率 |
| **1600ctl（旧 IP 对照）** | 6.2.3 | **0.128** | 0.020 | 2.200 | 68/0 | 5.000ns | 15317/24260 | 同上 | 同 runner/脚本/工具，隔离工具版本 |
| 002820（冻结基线） | 6.2.2 | 0.000 | 0.020 | 2.200 | 66/0 | 5.000ns | 16171/30825 | `5aa25fd2`/`019db289` | 历史行；有 bit |
| 103222 | 6.2.2 | 0.001 | 0.020 | 2.200 | 68/0 | 5.000ns | 16171/30818 | `5aa25fd2`/`019db289` | 探索；ready-timing 结构改动；无 bit |
| 111134 | 6.2.2 | 0.008 | 0.020 | 2.200 | 68/0 | 5.000ns | 16212/30910 | `a9cdc957`/`019db289` | 探索；TimingUltra；无 bit |
| 114913 | 6.2.2 | −0.177（STNS −1.694） | 0.020 | 2.200 | 68/13 | 5.000ns | 16117/30866 | `a9cdc957`/`aa1f21fb` | 探索；实现期 0.300 预留（guard −0.477）；无 bit |

历史行均为 6.2.2（runner `1886c4fa…`/`5196d62d…`），与 6.2.3 行逐行标注版本、不混合归因；跨工具行差异如实列出（如 period 3.201 vs 2.200、REG 规模、组数形状）。

## 6. bitgen / CWC（条件性延伸）

- 条件：route 最终 STA 全项非负（setup/hold/period≥0 且 TNS=0）+ 4 条 `set_path_skew` 在、无负 slack、无 abnormal 端点 → **两候选均满足**，故对两者都执行 bitgen（fail-closed 由 tcl 门+runner 预检双重执行）。
- 结果：1333 bit `b7ef91cf…`、ctl bit `1447b243…`（均 5,224,029 B；bid 各 74,957 B）；skew 复核 4 约束/36 路径（min 2.926 / 3.067ns ≥0）；abnormal 0。
- **CWC 导出未做**：`not_run`（可选；对比数据不需要；本批无硬件路径）。**未下载、未上板、无 GUI**。

## 7. 观察/边界（如实，供 E3/测试者引用）

1. **TMST-7700 CRITICAL-WARNING（4 SEVERE timing constraint issues）**：TD 6.2.3 route DRC 阶段在**两候选**均出现（place 段 1 条、route 段 2 条；详单未由冻结脚本生成，报文指向 "check_timing report"）；历史 6.2.2 日志（002820/103222/111134/114913）计数为 0。⇒ 属工具版本在本设计上的行为，**非新 IP 缺陷**；但 4 条具体约束问题未定位，列为**未决项**（不改脚本、不加分析脚本，交规划/E3/用户）。
2. STA coverage：1333 96.49%、ctl 96.43% vs 002820 97.99%——观察记录，未在批内解释。
3. `capture_route_drc.rpt` 在两个工具版本下均不落盘（002820 亦无）——脚本既有行为，非本次回归。
4. 6.2.3 与 6.2.2 行对比含工具版本因素；同口径对照对=1333 vs 1600ctl。
5. 板测/真实 DDR 校准/颜色/长稳/HDMI 电气均不在本批。

## 8. 与计划的偏差（如实）

| # | 项 | 说明 |
|---|---|---|
| 1 | 证据文件名双名 | dev-plan §4.2 名 + 派发注记名，同内容两份（互登记），防 E3/测试按不同名字找不到证据 |
| 2 | 阶段超时取派发值 | build 1800s / route 3600s / bitgen 900s（dev-plan 写 2400/5400/1800）；均未触及 |
| 3 | bitgen 范围 | 两候选均满足条件故均执行（dev-plan 允许 1333 与/或 ctl）；CWC 未做（可选） |

## 9. 测试者复现入口

```powershell
# 只读复核（不重跑构建）：
#  1) 证据 JSON：docs/evidence/ddr1333_build_sta_20261017.json（= ddr1333_integration_timing_20261017.json）
#  2) 候选内 native_{build,route,bitgen}.json/.txt（三件套+CWD+SHA）；capture_timing.rpt / capture.area / candidate_*.rpt
#  3) 独立重跑 gate（便宜、只读）：
& 'C:\Program Files\Python311\python.exe' -X utf8 -B `
  'C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道\tools\td\check_timing_margin.py' `
  'D:\TD\work\csi2\prj\camera_rgb565_ddr1333_20261017_160741\capture_timing.rpt' --min-setup-ns 0.3 --expected-endpoint-groups 66
#  （1600ctl 同命令 --expected-endpoint-groups 68；期望均 exit 1、accepted=false）
#  4) runner 负例（不写任何文件）：bad 名/错父目录/-O 均应在写盘前拒绝
#  build/route 复跑需新时间戳候选（E1 派生脚本）并经规划批准（时间墙）；不得覆盖现有 native_*。
```

- 工程边界：所有执行产物在 D 盘两候选内；仓库仅新增 runner + 证据 JSON + 本目录记录；`run_rgb565_native.py`、`check_timing_margin.py`、002820、`_validation` 全部零改动（SHA 复算一致）。

## 10. 修订记录

- 2026-10-17（D1，文书级）：§1 表格证据 JSON 引用由 pass-1 值（`4ff87e81…` / 76,860 B）更正为最终盘面值（`7c633508480a886ed63aa89f14f0195f068cc4f9a3d01e0abed0c2115fee9010` / **81,640 B**；正名与别名同内容，尺寸为 `read_bytes` 实测）。
  - 原因：dev-notes 写于证据生成器 pass-1 之后、pass-2 刷新（补 `run_notes`）之前；且 pass-1/pass-2 打印的"字节数"为写入前字符串长度，而 `Path.write_text` 在 Windows 将 `\n` 落为 `\r\n`（每行 +1 B），故落盘尺寸大于当时打印值。文件 SHA 本身自始正确（对落盘文件计算）。
  - 触发：三名测试者一致记录的 D1 文书缺陷（文书核对项，无需重测）。
  - 范围：仅修订本文件；证据 JSON / runner / 两候选一律未动。注意证据 JSON 内 `run_notes.dev_notes.sha256` 仍指向修订前版本（属派发指令冻结的禁止改动范围），后续引用以本修订记录为准。
