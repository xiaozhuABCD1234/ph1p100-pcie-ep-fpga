# T11.rk-align-base — lessons learned（round0）

只记可复用的根因/触发/修正/验证入口。

## L1. PowerShell 参数后的字符串拼接必须加括号（字段截断陷阱）

- 触发：`Add-Record -Summary "文本: " + $var + "）"`——参数模式下 `"文本"` 是 `-Summary` 的值，后面的 `+ $var + "）"` 不会拼进去（首轮实测：`td_cli_probe.command` 与 `inventory_consistency.summary` 被截断）。
- 修正：整段拼接加括号：`-Summary ("文本: " + $var + "）")`。
- 验证：读回 JSON，检查字段完整（本包首轮/终轮日志都保留，可对照）。

## L2. 捕获原生命令输出时的编码：只对确知 UTF-8 输出的工具临时切 UTF-8

- 触发：`git status --porcelain` 输出 UTF-8 文件名，被按 GBK 解码 → 中文路径乱码（`docs/TD鍛戒护…`）。
- 修正：捕获期间临时 `[Console]::OutputEncoding = [System.Text.Encoding]::UTF8`，`finally` 恢复；**只对 git 启用**——`subst` 等系统工具输出是控制台编码（GBK），切成 UTF-8 反而乱码。
- 验证：对比 JSON 里 `dirty_sample` 的中文文件名可读性（本包终轮已正常）。

## L3. TD 会在 cwd 写 `td_<时间戳>.log/.logw` → 探针/构建 cwd 必须被限定

- 触发：TD CLI 在 cwd 落盘自己的日志；若 cwd 是项目根/桌面，会污染非授权位置。
- 修正：探针用临时 subst 把 `env/logs` 映射为盘符，TD 以该盘符为 cwd（`finally` 撤销）；探针 tcl 与 stdout 也落在 `env/logs`，实现"除 env/logs 外不写任何位置"。
- 验证：探针运行后 `env/logs/` 里同时出现 `td_*.log/.logw` 与 `td_probe_stdout.log`；`subst` 复查无残留。

## L4. tclsh 无参数会读 stdin 挂住 → 版本探针用脚本文件

- 触发：`tclsh`（无参数）等待 stdin，自动化里会挂死。
- 修正：把 `puts [info patchlevel]` 写到 `env/logs/tcl_version_probe.tcl`，用 `tclsh <file>` 探测。
- 验证：探针返回 `8.6.12`、exit 0。

## L5. 编码吞行的自检法：脚本内哨兵计数（比"看 BOM"更强）

- 背景：PS5.1+ACP936 会把"无 BOM UTF-8 + 中文注释"按 GBK 解码吞行（T07 F1）；BOM 在，也不能保证编辑过程没破坏。
- 做法：脚本里放 N 个 `$script:SelfCheck++` 哨兵（分散在中文注释密集处之后），检查点前计数必须等于 N；任何一行被吞都会少计 → 自检记录 FAIL。
- 验证：终轮 `selfcheck_encoding` = `SelfCheck=6/6`、自身 BOM=True。

## L6. 只读证明的可复用做法：快照 + 冻结 manifest 逐条交叉核对

- 做法：`input-snapshot.json` 记录被读文件的 SHA/mtime；再把其中生产输入与冻结清单（`raw/candidate-manifest.json`）逐条比对；同时实算两个 manifest 自身的 SHA。
- 本包结果：36 文件快照、17 条生产输入 17/17 一致、两个 manifest SHA 实算与登记值一致 ⇒ 强证据"未触碰冻结输入"。
- 复用：任何"只读勘察/评审"包都可照做。

## L7. 生成物可复现性验证：用冻结生成器 `--out` 到本包目录再比 SHA

- 做法：`python tools/pcie_integration/gen_crc16_flat.py --out env/verify/crc16_upd4.regen.v`（crc32 同理），与生产文件逐字节比对。
- 结果：crc16/crc32 均与生产文件 SHA 完全相同（20520D04… / 89B04F75…；自检 4×20030 / 4×20040 例 0 失配）。
- 意义：无需重跑 TD 即可证明"生成物 ↔ 生成器 ↔ 冻结输入"自洽；同时证实 `backend/g1/crc16_upd4.generated.v`（3,475 B / 82551E02…）确非生产文件副本。

## L8. 自检脚本"先记录事实、再写清单、再复跑验证"的三段式

- 顺序：① 首轮 env_check（清单不存在 → WARN 属预期）→ ② 用首轮事实写 `environment-inventory.json` → ③ 复跑 env_check（`inventory_consistency` PASS）。
- 文档中必须写明首轮 WARN 是预期，否则会被误判为缺陷。

## L9. 绝对断言纪律："全库检索无 X" 必须先实测并写清范围，否则写"待验证"

- 触发（round0 F1）：survey S1-1 写「全库检索无 +5.058 来源」——实际同一份 `final_timing.rpt` 内就有：`Path Group: tl_clk_user → tl_clk_user` 的 SWNS 5.058ns（L2073-2081，Min Period 10.942=16.000−5.058；L2087/L2210 Slack=5.058）。
- 根因：把"时钟摘要行（clk1=+1.141）"与"Path Group 统计节（tl_clk_user→tl_clk_user=5.058）"混为一谈，未按节区分引用；"无来源"是推断而非实测。
- 修正：跨节误引的准确表述 + 分别核对两个节的来源；绝对断言要么实测（写清检索范围/命令），要么标"待验证"。
- 验证：round1 functional 复测按修正后的行号逐条复核。

## L10. 文档化示例必须实跑验证；OutDir 一律用 scratch

- 触发（round0 SYS-D1/D2）：手册 §0 示例 `-TbFiles sim/tb/…` 原样执行必失败（run_sim.ps1 会再拼一层 `sim/`）；两例 `-OutDir` 指向 `raw/` 冻结证据/候选目录（按原样执行会覆盖）。
- 修正：示例改成实跑通过的形态（`tb/…`），OutDir 改为临时 scratch（`test-reports/scratch/…`）并加显式警示；修复后按文档原样实跑 1 次（ALL PASS）留证。
- 验证：修复后命令 exit 0 + `vlog Errors: 0` + `vsim ALL PASS` + 产物齐（本包 `test-reports/T11.rk-align-base-r1-doc-example-evidence/`）。

## L11. `run_sim.ps1 -TbFiles` 相对路径基准 = `fpga/csi2/pcie_integration/sim/`

- 触发：相对 `-TbFiles` 会拼在 `…/pcie_integration/sim/` 之后 → 写 `tb/tb_x.v`（不是 `sim/tb/tb_x.v`；绝对路径亦可）。
- 备注：`run_sim.ps1` 头部注释里的 `sim/tb/…` 示例与其实现不一致（该文件属 T07 冻结输入，本包不改，已登记给后续触碰它的包）。

## L12. 跨任务绝对断言必须做项目级全量统计（范围不同是常态）

- 触发（round1 F1-r1）：handbook 写「既有 G1 证据的 TB 命令**全部**带 `-Defines MIPI_PHY_SIM_STUB`」——项目级实核为假：本 run/raw G1 22/22 带，T07 backend G1 仅 5/31 带（全部 `tb_csi_checked` 各轮），其余 26 条不带。
- 根因：把"本 run 的 22 条"超范围概括为"全部 G1 证据"；未跨任务统计。
- 修正：写"全部/均"前先全量统计（含其它任务/轮次的证据目录），并把范围写进句子里（如"本 run/raw G1"）；不确定就分列或标"待验证"。
- 验证：round2 functional 复测按修正后的范围表述逐条复核（22/22 与 5/31 均可独立统计复现）。

## L13. 证据目录的"额外产物"要么入清单、要么声明

- 触发（round1 观察）：r1 doc-example 证据目录除清单 6 文件外，另有 TB `$fopen` 输出 `.bin` 3 个与 ModelSim `work/` 库 6 文件，未入清单、未声明。
- 修正：确定性产物（`.bin`）入清单；工具运行库（`work/`）在清单 `logs_note` 里登记为"未入清单（工具运行库）"，与既有 volatile 排除惯例一致。
- 验证：清单重冻后自检全对；测试者按清单核对该目录无"未声明"文件。

## L14. 重冻 manifest 时同步元数据（round/notes/frozen_at）

- 触发（round1 观察 1 / system 观察 2）：r1 重冻时 `round` 字段仍为 0（frozen_at/notes/dev-result 都写了 round1）——绑定虽以 SHA 为准，但元数据不精确。
- 修正：round2 重冻时置 `round: 2` 并同步 notes。
- 验证：清单解析后 `round` 字段与 dev-result 一致。

## 边界与未做

- round0 未运行 TD 构建/ModelSim TB/verilator；round1 仅按手册示例跑了 1 次写者 TB（文档可执行性验证）；round2 仅文档修正；未下载、未写 Flash、未操作硬件；未安装/改全局/写 D 盘；未删除任何文件。
- `T1`（字节域时序重构）与 `T2`（B 路诊断出口）的收益为量级判断，实施与实测属 `T11.rk-align-opt`。
- round1/round2 修复只动本包文档/记录（survey/handbook/change-report/lessons/snapshot/manifest/dev-result）；`env_check.ps1` 与 `environment-inventory.json` 未改。
