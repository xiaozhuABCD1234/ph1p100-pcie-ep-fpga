# input-index.md — 20261018-1631_runA_fpga_side_readchannel

原规划者编写（2026-10-18，≈16:31 起）。本文件=本轮采用的准确输入、版本与未决事项；不是状态快照，不覆盖旧证据。

## 1. 当前需求

- 用户原话（原样保存）：`request.md`（本 run）。
- 拍板（主登记，用户 2026-10-18 答复）：
  1. **授权**重建“调试诊断位流”并**临时替换板上 SRAM 位流**（可回退 `e81d353b…`、**不写 Flash**）；
  2. **相机已接（单 A）**；
  3. **PCIe 通道不验证**；
  4. **严格 FPGA 侧**（板 + JTAG/串口线缆，不依赖 RK/PC 主机）。
- 本轮目标（原规划冻结）：**FPGA 侧读通道成立 + 读到身份/写者基线/CSI 计数**（相机已接，延伸采集统计）。全程无 PCIe、仅 SRAM、不写 Flash。
- 用户额外要求：产出“小白语言”说明（`plain-words.md`，本 run），供主原样转发。

## 2. 采用的版本与关键输入（准确路径）

### 2.1 板/位流现状（只作来源与回退）

| 项 | 值 | 证据 |
|---|---|---|
| 板上当前位流（SRAM，易失） | bit `E81D353B…2B9A`（5,224,023 B） | `workflow/runs/20261018-1347_runA_offline_sim/board-selfcheck/`（manifest `0cbe3fe2…`；SHA 复核、BW 器件 ID=PH1P100、`download -mode jtag` rc=0/29.52 s） |
| 配对设计 commit | `ab811c8f820c3ae6601507b54ec45a74c6607855`（未推送） | 同上 + `workflow/runs/20261018-0001_merge_raw_into_upstream/repo-build/` |
| 新 debug 位流规则 | **与 `e81d353b…` 并列、不混拼**；旧候选只作来源/回退 | 本 run `fpga-design-guide.md` §7 |

### 2.2 生产原仓检出（本轮唯一 RTL 工作树）

- `upstream/ph1p100-pcie-ep-fpga`，分支 `codex/raw10-rka1`，worktree clean，均未推送：
  - `ab811c8` RAW10/R10F/DDR/PCIe 合入（13 RTL + sim + tools + 协议镜像）；
  - `48be9f2` `tools/bringup/**`（KIT，14 文件）；
  - `c89ab75` `rtl/ep_side/ddr/ddr_frame_readback_checker.v` + `sim/tb/tb_ddr_frame_readback_checker.v`（未集成）。
- 构建入口（可复跑）：`tools/pcie_integration/run_td.ps1 -Stage 00_all -OutDir <out>`；上一轮实测单会话 ≈9 min 43 s（wrapper 2026-10-18T01:14:17→01:23:59）。
- 仿真入口：`tools/pcie_integration/run_sim.ps1 -Tb <tb> -OutDir <dir> -TbFiles tb/<file>.v`；`MSIM_BIN=D:\intelFPGA\18.1\modelsim_ase\win32aloem`；既有回归统一 `-Defines MIPI_PHY_SIM_STUB`。
- 既有 8 TB 回归清单（口径=上一轮 `ddr-readback-checker/regression/`，vlog `Errors: 0` + vsim `ALL PASS`）：
  `tb_cam_r10f_writer`(78.3 s)、`tb_t11_r10f_e2e`(4.7 s)、`tb_t11_csi_enable_corner`(4.0 s)、`tb_ddr_frame_pusher_rka1`(6.6 s)、`tb_csi_integrity_diff`(4.2 s)、`tb_csi_checked`(6.4 s)、`tb_ep_bar_win_rka1`(3.9 s)、`tb_ddr_wr_arb`(4.0 s)（+ 上轮新增 `tb_ddr_frame_readback_checker` 23.0 s）；整组 ≈2.3 min。

### 2.3 读回依据与工具（只读）

| 项 | 路径 | 用途 |
|---|---|---|
| 寄存器计划（含 R01—R17 期望规则） | `upstream/…/tools/bringup/registers-plan.md`、`expected_rules.json`、`parse_dump.py`、`run_record.schema.json`、`runbook.md`、`fixtures/` | 读回字表/判据/记录 schema 唯一依据；本 run 复用不重造 |
| 协议合同 | `upstream/…/docs/protocol/rka1-r10f-v1/contract/registers.json` | 地址/字段权威 |
| 寄存器解码 RTL（只读引用） | `rtl/ep_side/img/ep_bar_win.v`（0x040/0x0A0…/0x118/0x11C/0x120… header） | 期望值来源 |
| CWC 映射校验器 | `tools/td/check_chipwatcher_readback.py` | 校验 `compiled.cwc` 与原生 BID 的物理读回映射（注意：仅支持单段/全深几何） |
| ChipWatcher 历史文档 | `docs/参考色条正常但无实时图_ChipWatcher读取步骤_2026-10-13.md`、`docs/ChipWatcher空白波形_读回映射修复_2026-10-14.md`、`参考资料/选题三_ChipWatcher详细操作.md` | 流程/踩坑：必须经 `setup_debugger -prj` 生成 `cw/compiled.cwc`（单跑 `export_chipwatcher` 会缺物理 ERAM 映射→空白波形）；官方例程 `D:/TD/03_F9P_CA05_PH1P50_PH1P100/V2026/…/04_use_ChipWatcher/` |
| 历史 CWC 产物（只读参考） | `D:\TD\work\csi2\prj\camera_rgb332_reference_20261013_215134\camera_ddr_display.cwc` 等 | 格式样例（**不是本轮候选**） |
| TD | `D:\anlogic\TD_Release_2026.2\bin\td_commands_prompt.exe` | 唯一构建工具（2026.2） |
| BW/JTAG | `D:\downlaod\bin\bw_commands_prompt.exe`（6.2.2）、TD 2026.2 `bin\bw_commands_prompt.exe`（备用）、`D:\downlaod\bin\hwserver.exe -r -s 5555 -f 12 -v -w 5556 -i 0` | 下载/器件 ID；命令与判据见 `board-selfcheck/channel-notes.md` §3 |
| DDR 校准异常 SOP | 同上 + 决策登记 rev5 M5.8 | D37 灭 → **用户物理断电 10 s** → 上电 → 重下同 bit |

### 2.4 上一 run（已 finished）输入

- `workflow/runs/20261018-1347_runA_offline_sim/`：`next-round-proposal.md`（A0—A4 手段、P0—P3 推荐、bit 影响说明）、`question-01.md`、`handoff.md`、`board-selfcheck/`、`bringup-kit/`、`ddr-readback-checker/`。
- 关键事实（带进本轮）：UART rx 架构不可用（EP top `uart rx=1'b1`，`rtl/ep_side/ph1p_pcie_ep_top.v` L155/L757）；BW `JTAG_REG_ACCESS/…` 仅命令名、**无只读语义文档（KIT 已做文档级初核=不可用，禁止盲试）**；本候选 bit 无 CWC/调试核 → 寄存器读不可用。
- KIT 已闭合项：registers-plan 全表 + dump 判定器 + run_record schema；**读通道恢复后直接消费，不需重做**。

### 2.5 项目级约束（只读）

- `AGENTS.md`：禁止批量删除；主只传输；`workflow/tasks.json`（T11=active 父任务，最近 run=`20261018-1347_runA_offline_sim`）。
- 旧候选（`14b32037…`/`0943cb36…`/`002820`/`b7ef91cf…`）只作来源/回退、不得与新候选混拼。

## 3. 已有成果与所有者

| 成果 | 位置 | 所有者/状态 |
|---|---|---|
| KIT（寄存器计划+判定器） | 上游 `tools/bringup/`（commit `48be9f20`，未推送）+ run `bringup-kit/` | T11.runA-bringup-kit **PASS(r0)** |
| DDR 读回校验核心（未集成） | 上游 `rtl/ep_side/ddr/ddr_frame_readback_checker.v` 等（commit `c89ab758`） | T11.runA-readback-checker **PASS(r0)**；集成留后续主题 |
| 板级通道结论 | run `board-selfcheck/channel-notes.md` | B1 blocked 已接受 |
| 调试核读者（历史） | 上述 ChipWatcher 文档 + `tools/td/check_chipwatcher_readback.py` | 项目历史资产，只读复用 |

## 4. 未决事项（不阻塞本次派发）

1. **板级窗口**：P3 上板需用户现场（相机已接、物理断电可执行）；P2 完成时若用户不在场 → 该包置 `awaiting_hardware`，不空转。
2. **ChipWatcher 画面读数操作者**：GUI 步骤若无法脚本化（历史 CLI `rdbk_cwc_data` 参数未证实），由用户按清单操作、原样回报；执行者须记录在案（不预设 CLI 可行）。
3. **调试版默认使能改动范围**：由 P0 依据 RTL 复位默认值裁定（若需 debug-only 默认开启采集，必须最小化并写入 candidate diff）；不得 arm TX/面向主机动作。
4. 所有旧候选/证据只读；`workflow/tasks.json` 本轮由原规划收尾时统一更新（保护范围）。
