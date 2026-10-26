# input-index.md — 20261019-0207_runA_ddr_readback_loop

原规划者编写（2026-10-19，无人值守轮）。本文件=本轮采用的准确输入、版本与未决事项；不是状态快照，不覆盖旧证据。

## 1. 当前需求

- 用户原话（原样保存）：本 run `request.md`。
- 需求要点（按原话）：继续 FPGA 侧闭环验证，进度优先、稳定性/优化后放；今晚无人值守推进 N1→N2→N3→N4→N5（DDR 读回校验集成→重建→几何回填→坏帧/100 帧仿真→证据与上板清单）；最后留“回来点两下”的上板清单；仅 SRAM、不写 Flash、不推送；不接 PCIe/RK/三算法；用户提示“若规划认为 N1/N3 可合并成一次构建会更省时间”。
- 规划裁定（详见 `dev-plan.md` §0 与 `dispatch.json.merge_decision`）：**N1（checker 集成）与 N3（几何回填）合并为一个 RTL 包（`T11.runC-checker-integrate`），只做一次构建**；BATCH_SIZE 仍=1，正式包 4 个、每任务新开发+一个新综合测试者、修复轮分账不变。

## 2. 采用的版本与关键输入（准确路径）

### 2.1 基线 run（已 finished，只读参照）

`workflow/runs/20261018-1631_runA_fpga_side_readchannel/`

| 项 | 值/路径 |
|---|---|
| 终态 | 4 包全 PASS；G3=partial、G4=not_run；父 T11 不置 done |
| 关键文件 | `dev-plan.md`（§3/§7）、`handoff.md`、`final-summary.md`、`input-index.md`、`user-input-13.md`、`dispatch.json`、`test-reports/T11.runB-board-readback-r1-integrated.md` |
| 板载候选（SRAM） | bit `bfafdf97ff78d6f6d2646ffc706542a0bbbb7e11869043ba754cf68a270813d0`（5,224,027 B）；CWC `8d2998b96ef1763c14a1302118235a687488297ce496692b1f6cd95d76981026`（81,063 B）；BID `02c5cfdf…` |
| 旧候选（并列保留） | `e81d353b…2b9a`（回退，5,224,023 B）、`2385cded…1873`（NOT_MATCHED 证据）、`AFFC4396…`（仅证据） |
| 板证读数（P3 两样本） | word0/1/2=`50434946/31414B52/00010000`、word3 `B1BE→B2EA`(+300)、word4=`00900000`、word5=`00279000`(2,592,768)、word6 `BE000000→EA000000`（good 190→234，bad/hdr/crc=0）、word7=`089012DE`（last_lines=2192/last_wc=4830）、word8=`00000021` |
| 读回通道现状 | **CLI 读回永久关闭**（4 次尝试均无样本）；GUI 两样本为唯一读回路径 |
| 冻结件 | `debug-fix3/candidate-manifest.json`（`fadbf3f0…`）、`debug-build2/candidate-manifest.json`（`e6d63702…`，`FROZEN_READY_FOR_P3`）、`board-readback/candidate-manifest.json`（v11 `BC27553A…`/23,415 B）、`debug-spec/probe-map.md`、`debug-spec/readback-criteria.md`、`debug-spec/enable-state.md`、`debug-spec/board-runbook.md` |

### 2.2 上游工作树（本轮唯一 RTL 写树）

- `upstream/ph1p100-pcie-ep-fpga`，分支 `codex/raw10-rka1`，**未推送**。
- HEAD=`b0282d2a8dfdf11e6e63779510fe380dfffb5e83`（`T11.runB-debug-rtl` P1-fix 提交）。
- **继承的未提交改动（r3 复位域修复，4 路径 worktree-only，+46/−5）**：
  `rtl/ep_side/img/ep_bar_win.v`、`rtl/ep_side/pcie_ep_engine.v`、`rtl/ep_side/ph1p_pcie_ep_top.v`、`sim/tb/tb_ep_bar_win_debug.v`。
- 本轮新改动**在此之上叠加**；构建绑定与冻结以“HEAD + 累计 worktree diff”为准（详见 `fpga-design-guide.md` §8）。
- **2026-10-19 02:32 修订（去重裁定 CR-20261019-0207-01）**：上记“4 路径 +46/−5”继承描述**已失效**——02:23 起并行 run `20261019-0212_codex_fpga_closedloop_b2`（Codex，用户改派）在同一工作树持续写入（02:31 实况=7 M + 8 ??，HEAD 仍 `b0282d2a`），本 run **不再写入上游**；任何未来重派必须以当时快照（status/diff 哈希）重核。证据：本 run `checker-integrate/blocked-report.md`、0212 run `request.md`/`main-log.md`、本 run `dispatch.json.coordination_ruling`。
- **2026-10-19 13:1x 再修订（CR-02 重锚）**：用户要求两线互不影响并行推进；本线改用**独立 worktree** `upstream\ph1p100-pcie-ep-fpga-wt0207`（base `b0282d2a` + r3 diff 复现）承接 Track A 全链；共享树归 0212（只读）。上一条“本 run 不再写入上游”修订为：**不写入共享树，只写本线 worktree**；TD/板卡窗口与 0212 串行互斥（详见 dispatch `coordination_ruling.shared_resource_rules`）。

### 2.3 待集成组件（N1 对象）

| 项 | 路径 | 状态 |
|---|---|---|
| DDR 读回校验核心 RTL | `upstream/ph1p100-pcie-ep-fpga/rtl/ep_side/ddr/ddr_frame_readback_checker.v` | commit `c89ab758…`（T11.runA-readback-checker PASS）；**未集成顶层**；接口/语义见文件头注释（本规划已只读核对） |
| 模块 TB | `upstream/…/sim/tb/tb_ddr_frame_readback_checker.v` | PASS（23.0 s；正例+负例 ≥4） |
| 交付记录 | `workflow/runs/20261018-1347_runA_offline_sim/ddr-readback-checker/`（`dev-result.md`、`candidate-manifest.json`、`candidate.diff`、`regression/`） | ready_for_test 已完成 |
| 集成要点（模块注释 §一） | 单时钟 `dhi_clk`（100 MHz）；AXI4 读主 256bit/INCR；参数 base/frame_bytes 须 32B 对齐；`frame_bytes`=发布长度（1080p=2,592,768）；err_code 0—8；busy 重入拒绝；abort 仅 busy 有效 | — |

### 2.4 几何/相位回填依据（N3 对象）

| 项 | 值/路径 |
|---|---|
| 板证输入 | 基线 run `board-readback/readback-record.md` + `tier-evaluation-p1fix3.md`：word5=2,592,768（=633×4096；⇒ 载荷 P=2,592,000 = 1920×1080×1.25，与 stride 2400 一致）、word7 last_lines=2192 / last_wc=4830、word6 good=234 |
| RTL 现状（只读核对） | `ph1p_pcie_ep_top.v` L103/L108/L1518-1519：`CAMDDR_SKIP_ROWS=16'd37`、W=1920、H=1080、x=960、y=540，注释“T07 实测来源，未板证”；`cam_ddr_writer.v` L106 标定规则“SKIP_ROWS + 2160 = 2197；不等于它说明 SKIP_ROWS/H 要重新标定”；`cam_r10f_writer.v` L60-71 同口径 |
| 规则来源 | `docs/planning/2026-10-17-master-plan/01_后续小任务清单.md` MP07（测清实际包几何/帧率）、MP08（固定 1080p ROI/RAW10/Bayer 相位）；`workflow/runs/20261018-0001_merge_raw_into_upstream/user-precheck.md` §7 |
| 边界 | 今晚无人值守→无新板测；回填**仅以既有板证 + RTL 自洽核对为限**，证据不足项保持原值并标 diagnostic（禁止猜测回填） |

### 2.5 工具与入口（只读复用）

| 项 | 路径/值 |
|---|---|
| 仿真入口 | `tools/pcie_integration/run_sim.ps1 -Tb <tb> -OutDir <dir> -TbFiles tb/<file>.v`；`MSIM_BIN=D:\intelFPGA\18.1\modelsim_ase\win32aloem`；既有回归统一 `-Defines MIPI_PHY_SIM_STUB` |
| 构建入口 | `tools/pcie_integration/run_td.ps1 -Stage 00_all -OutDir <out>`（生产默认，不得改）；debug 构建沿基线 `tools/pcie_integration/td/00_all_debug.tcl`（debug SDC 变体 `constraints/ph1p_pcie_case_ep_dbg.sdc`；单会话 ≤30 min、≤2 次） |
| CWC 校验 | `tools/td/check_chipwatcher_readback.py --multipiece`（多片等效口径沿用基线裁定；strict 默认保持拒绝多片） |
| TD | `D:\anlogic\TD_Release_2026.2`（只读；零写入） |
| BW/hwserver | `D:\downlaod\bin\bw_commands_prompt.exe`、`hwserver.exe -r -s 5555 -f 12 -v -w 5556 -i 0`（仅 P4 可选 SRAM 预加载用；先例命令见基线 `debug-spec/board-runbook.md` §5） |
| 寄存器/判据权威 | `upstream/…/tools/bringup/registers-plan.md`、`expected_rules.json`、`run_record.schema.json`；协议合同 `docs/protocol/rka1-r10f-v1/contract/registers.json` |
| 读回字基线表 | 基线 run `debug-spec/probe-map.md`（9 字 0x140..0x160；探针 `u_top/u_pcie_ep_engine/u_ep_bar_win/g_dbg_mark/dbg_mark_word0..8`） |

### 2.6 上一 run 输入（程序性）

- `workflow/runs/20261018-1347_runA_offline_sim/next-round-proposal.md`（A0—A4；A4=“checker 集成到调试位流”即本轮 N1 来源）。
- `workflow/runs/20261018-0001_merge_raw_into_upstream/user-precheck.md` §7（后两步 run 拆分建议；第一步含“板内 DDR 读回校验”与“几何/相位回填并重跑 G1/G2”）。

### 2.7 项目级约束（只读）

- 根 `AGENTS.md`：禁止批量删除（本 run 全程不删文件）；主只传输；DeepSeek 块不适用本轮（不派外部）。
- `workflow/tasks.json`：T11=active 父任务；**本轮规划/开发/测试不写**，由原规划收尾时统一处置（沿用基线保护范围）。
- 其他工作树、`workflow/records/**`、`parallel/**` 本轮不涉及、不写入。

## 3. 已有成果与所有者

| 成果 | 位置 | 所有者/状态 |
|---|---|---|
| DDR 读回校验核心（未集成） | `upstream/…/rtl/ep_side/ddr/ddr_frame_readback_checker.v`（`c89ab758`） | T11.runA-readback-checker PASS(r0)；集成=本轮 N1 |
| 调试读回通道（9 字） | 基线 run `debug-fix3/`、`debug-build2/`、`board-readback/` | T11.runB-* 全 PASS；板载 `bfafdf97…` |
| KIT（registers-plan/判定器/schema） | `upstream/…/tools/bringup/`（`48be9f20`） | T11.runA-bringup-kit PASS(r0)；直接消费，不重做 |
| 读回判据/runbook/使能状态 | 基线 run `debug-spec/**` | 冻结件；本轮沿用并按新字扩展（新 run 内，不覆盖） |
| CWC 映射校验器 | `tools/td/check_chipwatcher_readback.py` | 项目资产；只读使用（不重建候选） |

## 4. 未决事项（不阻塞本次派发；均已有兜底）

1. **板是否仍上电/位流是否仍在**：未知；P4 的 SRAM 预加载为“尽力而为、失败不阻塞”，清单同时覆盖“板已断电→回来先重下”分支。
2. **几何/相位完整板证（MP07/08 余项：OB/起点/镜像/phase 实测）**：今晚无板测，不能闭合；本轮只做“既有板证 + RTL 自洽”的离线核对与条件回填，缺项标 diagnostic。
3. **word6 good 稳定性归因与 G4 长稳**：用户明确后置，本轮 not_run。
4. **commit 口径**：HEAD 仍为 `b0282d2a` + 继承 4 路径 worktree-only；本轮允许本地 commit（不推送）；若权限拒绝则接受 worktree-only 冻结（不阻塞、≤1 次尝试）。
5. **CWC 实例名/探针名变化**：新字加入后以 TD 实际生成为准（基线为 `auto_created_cwc1`）；P4 清单以冻结产物实际名为准。
