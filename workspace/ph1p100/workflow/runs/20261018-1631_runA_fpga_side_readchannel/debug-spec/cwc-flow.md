# cwc-flow.md — A0 手段核实 + CWC 读回工具链可行性（T11.runB-debug-spec）

- run: `20261018-1631_runA_fpga_side_readchannel`；任务: `T11.runB-debug-spec`（离线方案冻结包）。
- 编写: fpga-dev 子会话（opencode），2026-10-18，上海时区；宿主 PC（用户 czz）。
- 范围与安全: **只读**本地文件/安装目录；**未启动 TD、未调用 bw/hwserver、未连板、未启仿真、未用网络**；上游仓零写入。
- 本文件冻结“路径与判定条件”，不替代 P1 的 RTL/TB 证据或 P2 的 G2 实测；文中事实均给只读出处。

## 1. A0 手段核实：是否存在“无调试核的 JTAG 只读用户寄存器”路径

检索（2026-10-18，全部只读、单步 ≤60 s）：

| # | 对象 | 方式 | 结果 |
|---|---|---|---|
| 1 | 上游 KIT 既有文档级初核 | `upstream/ph1p100-pcie-ep-fpga/tools/bringup/registers-plan.md` §2.3 | 结论 = unavailable：`JTAG_REG_ACCESS`/`JTAG_REG_ACCESS_VEC`/`JTAG_AXIS_APB_ACCESS` 仅命令名，无参数/读写语义文档；本候选位流无 CWC/调试核；写入副作用未知；**禁止盲试** |
| 2 | TD 6.2.2 安装文本（`D:/downlaod`） | grep `*.{tcl,txt,md}`，模式 `(?i)(setup_debugger|JTAG_REG_ACCESS|JTAG_AXIS_APB_ACCESS)` | 4 处命中，全部是 `setup_debugger`（`scripts/MultiSeed.tcl` L138/139、`scripts/DefaultFlow.tcl` L228/229）；**无任何 JTAG_REG_ACCESS 文档** |
| 3 | TD 2026.2 安装文本（`D:/anlogic/TD_Release_2026.2`） | grep `*.{tcl,txt,md}`，模式 `(?i)(setup_debugger|JTAG_REG_ACCESS|chipwatcher)` | 命中 `setup_debugger`（`scripts/DefaultFlow.tcl` L265/266、`scripts/MultiSeed.tcl` L138/139）与 ChipWatcher IP（`ip/depot/ChipWatcher_1.0/ChipWatcher/Other/plugin_end.tcl` L41–59）；**无任何 JTAG_REG_ACCESS 文档** |
| 4 | B1 命令表证据（引用既有结论，本包未重读日志） | `workflow/runs/20261018-1347_runA_offline_sim/board-selfcheck/logs/03-bw-command-list.txt` | 只有命令名；语义无文档（见 registers-plan §2.3；channel-notes §4） |

限制（必须随结论一并报告）：
- 检索覆盖 tcl/txt/md 文本与既有项目文档；**未检索 PDF/二进制/在线手册**。因此本核实**不是**对厂商语义的全量否定，只是“当前可用的文本层证据不支持存在该路径”。
- 不下结论于未证实语义：不推断 `JTAG_REG_ACCESS` 的潜在只读/只写行为，不试命令、不测试副作用。

结论（冻结）：
- **无文档证据支持“无调试核的 JTAG 只读用户寄存器”路径**；维持 registers-plan §2.3/§4 状态：**unavailable、禁止盲试**。
- 仅当后续出现厂商文档明确“只读语义 + 可复核读回机制”时，才交原规划评估一次性只读检查；本包不派发、不执行。
- 本 run 沿用唯一已证 FPGA 侧机读读通道：**ChipWatcher（CWC）调试核 + JTAG**（见 §2）。

## 2. ChipWatcher（CWC）工具链可行性（TD 2026.2，只读核实）

已核实事实：

1. **TD 2026.2 安装含 ChipWatcher IP**：`D:/anlogic/TD_Release_2026.2/ip/depot/ChipWatcher_1.0/ChipWatcher/Other/plugin_end.tcl`（L41–59 生成 `${IP_COMPONENT_NAME}_ChipWatcher.sv` 导出文件）。
2. **构建流末端存在 `setup_debugger` 调用**（调试后处理入口）：
   - `D:/anlogic/TD_Release_2026.2/scripts/DefaultFlow.tcl` L265–266：`setup_debugger -prj $prj_name` / `setup_debugger $chipDebugger -prj $prj_name`（条件分支）；
   - `D:/downlaod/scripts/DefaultFlow.tcl` L228–229：同构（6.2.2 备用）。
3. **官方例程存在**：`D:/TD/03_F9P_CA05_PH1P50_PH1P100/V2026/HW-MLK-F9P-CA05-PH1P100/01_start/00_for_starter/04_use_ChipWatcher/`（glob 只读确认：含 `fpga_prj.al`、`uisrc/`、`log/td_2026-05-27_*.log(.logw)`、`al_ip/ui_cwc/ui_cwc.xml`；未逐项哈希）。
4. **`cw/compiled.cwc`/`cw/compiled.bit` 生成条件（项目历史证据）**：必须经 TD `setup_debugger -prj <prj>` 后处理生成；单独 `export_chipwatcher` 缺物理 ERAM 读回映射 → **空白波形**（来源：`docs/ChipWatcher空白波形_读回映射修复_2026-10-14.md` L11、L17–L31；该修复已获实际读回反馈）。例程 `fpga_prj_Runs/phy_1/cw/compiled.cwc` L82–85 含物理 ERAM 的 RID/WID/数据位置/工作模式（同文档 L11 记录）。
5. **映射校验器**：`tools/td/check_chipwatcher_readback.py` 逐项比对 RID/WID、实例名、逻辑/物理尺寸、数据偏移、工作模式，缺块/错 RID/错偏移/缺逻辑 RAM/部分深度/错误物理工作深度六类故障被拒；**仅支持单段/全深几何**，多段需另证或改单段（来源：`docs/ChipWatcher空白波形_读回映射修复_2026-10-14.md` L31；guide §2）。
6. **位宽先例（规模参照，非保证）**：历史单实例 449×1024（`auto_created_cwc1`，同文档 L27）；本包 A 组探针 9 字=288 bit 在同类量级内；最终容量以 P1 elaboration / P2 构建为准。

### 2.1 判定条件（冻结）

- **主路径**：P2 用 TD 2026.2 构建并执行 `setup_debugger` 生成配对 `compiled.cwc` + `compiled.bit`；随后 `check_chipwatcher_readback.py` 校验 **0 失败**；bit 与 CWC 同一构建来源（SHA 记录；若两者 SHA 不同需说明，历史例中曾逐字节相同）→ 进入 P3。
- **回退触发条件**（任一命中，先记录实际报错证据再交原规划裁决）：① TD 2026.2 `setup_debugger` 缺失/报错不可修；② CWC IP 不可用；③ 校验器因几何（多段）判不可用且改单段不可行。
- **备用工具顺序**（仅原规划批准后执行，本文件不预授权换版）：TD 6.2.2（`D:/downlaod`，`DefaultFlow.tcl` L228–229）→ 6.2.3 系；guide §4 冻结构建工具 = TD 2026.2。
- **禁止**：把单独 `export_chipwatcher` 当成功；CWC 与 bit 混拼不同构建；在 2026.2 下静默换工具不记录。

## 3. 与后续包的绑定

- P1（`T11.runB-debug-rtl`）：按 `probe-map.md` 实现字库/探针；新 TB 证明镜像值 = 寄存器原值（含边界帧）且无副作用。
- P2（`T11.runB-debug-build`）：产物齐 + 校验 0 失败 + CWC/bit 配对 SHA 记录；`hardware-ready.md` 引用本文件与 `board-runbook.md`。
- P3（`T11.runB-board-readback`）：按 `board-runbook.md` 操作，按 `readback-criteria.md` 判定（G3 partial→pass 按 tier）。
