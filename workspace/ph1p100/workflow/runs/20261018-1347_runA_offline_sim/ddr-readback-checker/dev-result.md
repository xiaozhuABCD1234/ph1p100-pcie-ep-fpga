# dev-result — T11.runA-readback-checker（P1 离线 DDR 回读校验核心；补收完成）

- 任务：T11.runA-readback-checker（run 20261018-1347_runA_offline_sim，P1 离线包）
- 角色/宿主：fpga-dev（opencode 新建子会话，completion-only 补收）；Windows PC（用户 czz）；2026-10-18（上海时区）
- 判定：**ready_for_test**（离线 RTL+TB；未集成、未构建、不触硬件、不推送）
- 提交：分支 `codex/raw10-rka1`，commit `c89ab75803796ed7e9918aa55071c7df3284aa8f`（parent `48be9f20…`，base `ab811c8f…`；未推送）
- 冻结产物：`candidate.diff`（41,303 B，HEAD~1→HEAD）；`candidate-manifest.json`（生成时脚本复算 SHA256 = 0 不一致；protected 审计见其 `protected_audit`）
- 本轮补收未再出现 `Permission denied`（新会话 shell 正常；上一会话的会话级问题未复现）

## 回归证据（判定口径：vlog `Errors: 0` + vsim `ALL PASS`；单 TB 上限 300 s）

| TB | defines | 结果 | 耗时 | 日志 |
|---|---|---|---|---|
| tb_ddr_frame_readback_checker（新 TB 复跑） | — | `*** ALL PASS ***` | 23.0 s | `regression/tb_ddr_frame_readback_checker/vsim.log` |
| tb_cam_r10f_writer | MIPI_PHY_SIM_STUB | ALL PASS | 78.3 s | `regression/tb_cam_r10f_writer/vsim.log` |
| tb_t11_r10f_e2e | MIPI_PHY_SIM_STUB | ALL PASS | 4.7 s | `regression/tb_t11_r10f_e2e/vsim.log` |
| tb_t11_csi_enable_corner | MIPI_PHY_SIM_STUB | ALL PASS | 4.0 s | `regression/tb_t11_csi_enable_corner/vsim.log` |
| tb_ddr_frame_pusher_rka1 | MIPI_PHY_SIM_STUB | ALL PASS（20387 TLPs） | 6.6 s | `regression/tb_ddr_frame_pusher_rka1/vsim.log` |
| tb_csi_integrity_diff | MIPI_PHY_SIM_STUB | ALL PASS | 4.2 s | `regression/tb_csi_integrity_diff/vsim.log` |
| tb_csi_checked | MIPI_PHY_SIM_STUB | ALL PASS | 6.4 s | `regression/tb_csi_checked/vsim.log` |
| tb_ep_bar_win_rka1 | MIPI_PHY_SIM_STUB | ALL PASS（Errors:0, Warnings:4） | 3.9 s | `regression/tb_ep_bar_win_rka1/vsim.log` |
| tb_ddr_wr_arb（文件 tb_ddr_wr_arb_peer.v） | MIPI_PHY_SIM_STUB | ALL PASS | 4.0 s | `regression/tb_ddr_wr_arb/vsim.log` |

- 原新 TB 首轮证据（上会话）保留：`msim/new_tb/{vlog.log,vsim.log,commands.log}`（`*** ALL PASS ***`）。
- 基线约定更正：8 个既有 TB 全体使用 `-Defines MIPI_PHY_SIM_STUB`（merge run design-guide 约定）；dev-notes §26 原清单只列 2 个 TB 为 stub 不完整（e2e 不带 stub 因缺厂商 PHY 原语失败，死例保留 `regression/tb_t11_r10f_e2e_nostub_fail/`）。
- 补充证据（非判定，保留）：`tb_cam_r10f_writer_nostub`=PASS、`tb_ddr_frame_pusher_rka1_nostub`=PASS、`tb_t11_r10f_e2e_nostub_fail`=预期 FAIL（缺 `PH1P_PHY_LCLK`/`PH1P_LOGIC_BUFG`）。

## 补收期间对受保护文件的唯一写动作（如实登记）

- `sim/compile_checked.f`：上一会话因 OneDrive 同步竞争重写该文件，导致中文注释 mojibake 与换行合并（原 commit 1042ade 的 numstat=13/16，超出“仅允许追加 1 行”）。本补收先证明“有效路径集合 == 父提交 + 唯一追加行”（44→45 行，顺序一致），再恢复为**父提交字节 + 唯一追加行**并 amend 进同一 commit → numstat=`1/0`，`git status` 干净。
- 其余受保护文件（既有 rtl/**、constraints/**、既有 sim/tb/*、docs/protocol/**、tools/**、其它 run/**、tasks.json）未被本会话写入。

## 回退与边界

- 回退：`git reset --hard 48be9f20…`（丢弃该本地 commit）或 `git revert c89ab75…`；候选 bit `e81d353b…`（未重建）不受影响。
- 未测边界（交综合测试者）：独立重跑新 TB（含自建负例）、8 TB 抽验/复跑、manifest 复算、protected 审计；模块集成与上位机读通道不在本包。
- 复测入口：`powershell -ExecutionPolicy Bypass -File tools/pcie_integration/run_sim.ps1 -Tb tb_ddr_frame_readback_checker -OutDir <新目录> -TbFiles tb/tb_ddr_frame_readback_checker.v`（`MSIM_BIN=D:\intelFPGA\18.1\modelsim_ase\win32aloem`）。
