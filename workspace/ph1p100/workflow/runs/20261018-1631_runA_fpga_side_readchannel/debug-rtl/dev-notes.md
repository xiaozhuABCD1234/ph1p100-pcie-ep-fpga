# dev-notes.md — T11.runB-debug-rtl（离线 RTL/约束 + 仿真；不构建位流、不启动 TD、不触硬件）

- run: `20261018-1631_runA_fpga_side_readchannel`；task: `T11.runB-debug-rtl`（P1）
- 作者: fpga-dev 子会话（opencode），2026-10-18（上海时区）
- **状态: 实现/局部检查/回归完成并冻结；上游本地 commit 被本环境 shell 权限拒绝（`git commit` PERMISSION_MISSING，`git add` 正常，未尝试绕过）→ 候选 7 路径已全部暂存于 index，文件 SHA 已冻结；交付状态按 blocked 回报，恢复入口见 §5。**
- 依据: dispatch.json、dev-plan v1.1 §3.2、fpga-design-guide §1—§4、debug-spec/ 冻结件（probe-map / enable-state / cwc-flow / readback-criteria / board-runbook）、P0 r0 integrated 报告

## 1. 候选物（7 路径，逐条在 candidate.diff）

| 文件 | 类型 | 内容 |
|---|---|---|
| `rtl/ep_side/img/ep_bar_win.v` | 改（仅插入） | ① 参数 `DBG_CTRL_DEFAULT_EN=1'b0`；② 复位分支 **仅 2 行**：`ctrl_enable/ctrl_ddr_en <= DBG_CTRL_DEFAULT_EN`；③ `dbg_bank_word0..8`（= MAGIC / MAGIC_RKA1 / VERSION_RKA1 / ddr_ro[31:0]/[63:32]/[127:96] / csi_diag_a / csi_diag_a2 / CTRL 读回字）与 288 bit `dbg_bank`；④ 读 mux 新增 `0x140..0x160` 九个 case（default 仍 DEAD_BEEF） |
| `rtl/ep_side/pcie_ep_engine.v` | 改（仅插入） | 参数声明 + `.DBG_CTRL_DEFAULT_EN(DBG_CTRL_DEFAULT_EN)` 透传给 `u_ep_bar_win` |
| `rtl/ep_side/ph1p_pcie_ep_top.v` | 改（仅插入） | 模块头 `#(parameter DBG_CTRL_DEFAULT_EN = 1'b0)` + 透传给 `u_pcie_ep_engine` |
| `rtl/ep_side/debug/ph1p_pcie_ep_top_dbg.v` | 新 | debug 构建专用顶层包装（43 端口与 top 逐条同 dir/width/name），`ph1p_pcie_ep_top #(.DBG_CTRL_DEFAULT_EN(1'b1)) u_top`；仅 debug 入口编译 |
| `sim/tb/tb_ep_bar_win_debug.v` | 新 TB | 见 §3 覆盖清单；双实例（param=1 / 默认=0）对照 |
| `sim/compile_checked.f` | 改（追加 4 行） | 追加 debug 包装编译行（仅语法检查；无 TB 例化） |
| `tools/pcie_integration/td/00_all_debug.tcl` | 新入口 | 00_all 的 debug 变体：+包装 add_files、`top_module ph1p_pcie_ep_top_dbg`、`T11_DBG_ALL_DONE`（保留 `T07_ALL_DONE`）；**00_all.tcl / run_td.ps1 / run_sim.ps1 未改** |

## 2. 关键设计决策（依据/理由）

1. **dbg_bank 内联在 ep_bar_win 内**（不新建被生产编译引用的模块）：`00_all.tcl` 文件表逐字节不可改（受保护），ep_bar_win 若引用新模块会使生产构建缺模块；内联使 00_all 输入零变化。字库为纯组合 `wire`（探针名 `dbg_bank_word0..8` / `dbg_bank[287:0]`），只读、无副作用，未加任何合成属性（如 P2 发现被折叠，按 probe-map §4 降级直探并记 diff）。
2. **debug-only 默认使能机制 = 参数透传 + debug 专用顶层包装**（不用 `defparam`、不依赖 TD 未证实的宏/参数设置能力）：仅用 TD 既有 `add_files` + `top_module`；生产默认参数 0 → 行为与旧构建一致；debug 覆盖 1 → 复位仅 bit0/bit5=1，bit1/2/3/6/7/8 与 TX/push/cam_ab 域保持 0（R02 mask 仍成立）。
3. **包装端口机械生成**：`debug-rtl/gen_dbg_top.ps1` 解析 top 端口段生成，回读校验 43/43 一致，避免手抄错位。
4. **前置只读复核（dispatch ②要求）已做**：`img_frame_src.v` L145 `start = (enable|trigger) && !hold && ...` 确由 CTRL bit0 门控；`ph1p_pcie_ep_top.v` L149 `w_cam_ddr_want = img_ddr_en`（CTRL bit5）门控 DDR 搬 → 最小 debug 使能确有意义。
5. **TB 双实例**：`u_dbg`（参数覆盖=1）验证 debug 默认；`u_prod`（默认=0）作为生产不变负例（含写 CTRL 后语义不变）。

## 3. 新 TB 覆盖（tb_ep_bar_win_debug.v）

- 9 字逐位镜像：`0x140..0x160` == 对应原偏移读回复现值（每字双重检查：==期望值 且 ==原偏移读回）；正常帧 + 3 组边界帧（全 F / 全 0 / 交叉模式）。
- CTRL 读回字：写 `0x0→0xED→0xFFFF_FFFF→0x2(trigger)→0x21` 后 `0x160` 与 `0x044` 逐位一致；trigger 自清、bit4/bit[31:9] 读 0（0x1ED 期望）。
- 只读/无副作用：对 `0x140/0x144/0x160` 写无效；`ptr/scratch/last_wr/0x44/tap` 前后不变；`req_wr` 计数 = 显式写数（读 0 写）；bank 读不推进 ptr。
- 负例（≥2，实 4 类）：`0x13C/0x164/0x1F0` 仍 `DEAD_BEEF`；`0x158 != csi_diag_b`（防错接 B 路，`0x128` 直读 B 值对照）；`u_prod` 复位默认全 0。

## 4. 局部检查与证据（命令/退出码/标记/产物）

| 检查 | 命令（入口） | 结果 | 产物 |
|---|---|---|---|
| 新 TB | `run_sim.ps1 -Tb tb_ep_bar_win_debug -OutDir …/msim/new_tb -TbFiles tb/tb_ep_bar_win_debug.v -Defines MIPI_PHY_SIM_STUB` | rc=0，`*** ALL PASS ***`，vlog Errors:0 Warnings:1（`vlog-2600` @ pcie_ep_engine.v L125，非本包改动区域），5.4 s（≤5 min） | `msim/new_tb/{vlog,vsim,commands}.log` |
| 8 TB 回归 | 同上对既有 8 TB（MIPI_PHY_SIM_STUB） | **8/8 rc=0 ALL PASS，vlog Errors:0**，组 112.1 s（≤15 min） | `msim/regression/<tb>/*`、`regression-summary.txt` |

- 回归清单（与上轮基线同口径）：tb_cam_r10f_writer / tb_t11_r10f_e2e / tb_t11_csi_enable_corner / tb_ddr_frame_pusher_rka1 / tb_csi_integrity_diff / tb_csi_checked / tb_ep_bar_win_rka1 / tb_ddr_wr_arb(tb_ddr_wr_arb_peer.v)。
- `tb_csi_integrity_diff` 中 `FAIL` 模式命中为 `payload mismatches = 0`（信息行，非失败）。
- 编码完整性：3 个改动的 RTL 以 UTF-8 读回无 U+FFFD；新文件全部可编译（vlog Errors:0）。
- 未运行项（明确）：TD 构建/CWC/setup_debugger（P2）；板上读回（P3）；位流（不在本包）；**`git commit`（被权限拒绝，见 §5）**。

## 5. 阻塞与恢复（git commit）

- 现象：本子会话 shell 中 `git commit` 被环境权限层拒绝两次（`permission.rejected: Permission denied: shell`）；`git add` / 只读 git 命令正常；未做任何绕过尝试（合规要求）。
- 当前状态：**index 已完整暂存 7 个候选路径**（`A/M` 各就位，工作树与 index 一致、无其它改动），`candidate.diff`（含 `--cached --stat`）已按该 index 导出。
- 恢复入口（任一，由原规划/用户执行即可）：
  1. 在 upstream 仓执行一次 `git commit -m "T11.runB-debug-rtl: dbg_bank 9-word read-only mirror + debug-only CTRL default enable + debug top/entry + new TB (offline, no bitstream)"`（无需再 add；commit 后即得候选 SHA）；
  2. 或放行 shell `git commit` 权限后，由本任务续接（同任务续原开发）补 commit 并更新 manifest 的 `commit_sha`。
- 回退：`git reset` 或单文件删除候选（遵根 AGENTS 单文件删除令），无对既有文件/旧候选/证据的副作用。

## 6. P2/P3 提示（本包不执行）

- P2 入口：`run_td.ps1 -Stage 00_all_debug -OutDir <run>/debug-build/prj`（新 tcl 已就位；00_all 默认行为未动）。
- P2 后处理：`setup_debugger` → `cw/compiled.cwc|bit` → `check_chipwatcher_readback.py` 0 失败（cwc-flow §2.1）。
- 探针预期路径（P2 以 elaboration 复核并回写 probe-map）：`ph1p_pcie_ep_top_dbg/u_top/u_pcie_ep_engine/u_ep_bar_win/dbg_bank[287:0]` 与 `dbg_bank_word0..word8`。
- 判据/流程：readback-criteria.md、board-runbook.md（P3；仅 SRAM、不写 Flash）。

## 7. 预算记账（如实，供规划复核）

- 冻结预算：≤45 min / ≤30 次工具调用。实际：**约 59 次工具调用**（读取/调查阶段 ≈34，实现+验证+收束 ≈25），用时明显低于 45 min。超支主要发生在读取与前期调查（11 个必读输入 + run_td/00_all/.al/TD 安装只读核对，目的是保证 00_all 输入零改动与机制可执行）；调查为有界序列、无空转/无重复同输入。改进项见 lessons-learned.md。

## 8. 补收记录（原规划回填，2026-10-18）

- 事件：有界补收两次均被工具权限层拒绝（同 problem_id=`T11.runB-debug-rtl:PERMISSION_MISSING:git-commit`、`new_information=false`）→ 原规划记 blocked-pending-external 并请用户处置；用户按选项 A 于 upstream 检出**手动执行一次 commit**（截图原样保存于本 run `user-input-04.md`）。
- 原规划只读核对（2026-10-18，未写仓、未推送）：`git log -1 --format="%H %s"` → `8e1ef05f12831e94311c6cc593090198b0e258fc`、subject 与 §5 规定命令一致；`git rev-parse HEAD~1`=`c89ab75803796ed7e9918aa55071c7df3284aa8f`（未 amend/rebase）；`git show --stat HEAD`=7 files/619+/6-（3 create mode）；`git status --porcelain` 空（clean）。
- 回填：`candidate-manifest.json` 的 `commit_sha`=完整 SHA、`commit_status`=COMMITTED；notes 附回填说明；**其余字段未动**（candidate 文件 SHA/回归证据保持冻结）。用户告知后续将开放 shell git 权限（登记在案；本轮其余步骤不依赖）。
- 状态：本包 **ready_for_test**；交本 run 原综合测试者出 `test-reports/T11.runB-debug-rtl-r0-integrated.md`。

## 9. round1 修复记录（开发续接，2026-10-18；触发=综合测试者 r0 FAIL）

- 触发（唯一非符合项）：`test-reports/T11.runB-debug-rtl-r0-integrated.md` §5 —— `candidate-manifest.json` 的 `run_files[debug-rtl\dev-notes.md]` 仍记录 §8 回填前旧值（`e6ceec33…/7861 B`）；§8 回填后实测 `e9a3b182…/9047 B`（20:42:54 同一次回填写入的副作用，属记录侧不一致；候选与仿真结论不受影响）。
- 修复动作（本轮，2026-10-18）：
  1. **先**在本文件追加本节（round1 记录：原因、边界、刷新方式）；随后对 `debug-rtl\` 全部冻结条目全量复算（候选 7 + run_files 5 + sim_logs 27 = 39 条；复算前实测仅本条不一致，其余 38/39 一致）→ 将 `candidate-manifest.json` 中过期哈希/字节刷新为**当前实际值**（本轮仅 dev-notes.md 一条）；除该条 sha256/bytes 外，manifest 其余语义字段（commit_sha/commit_status/notes/candidate/日志/审计）保持不变。
  2. 刷新后本轮自检复算 **39/39 一致（0 不一致）**，自检输出随本轮返回；刷新后 `candidate-manifest.json` 自身 SHA256/字节数同样随本轮返回并由 round1 综合测试者复算——**不在本文件内回填该值，避免自引用循环**；刷新时点以 `candidate-manifest.json` 文件 mtime 为准。
- 边界确认：候选 RTL/TB/入口与 upstream commit `8e1ef05f…` 未再改动（`git status` clean）；不推送、不启 TD、不触硬件、不用网络、无批量删除。
- 回退：丢弃本轮 manifest 刷新（单文件级）即回到 r0 记录态；候选文件不受影响。
