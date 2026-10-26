# dev-notes — T11.runA-readback-checker（P1 离线 RTL+TB 回读校验核心）

- 角色/宿主：fpga-dev（opencode 新建子会话）；Windows PC（用户 czz）；2026-10-18（上海时区）。
- 工作树：upstream/ph1p100-pcie-ep-fpga（分支 codex/raw10-rka1；base=ab811c8f；进入时 HEAD=48be9f20，KIT 提交）。未推送。
- **结果摘要（核心）**：新 TB **ALL PASS** —— `msim/new_tb/vsim.log` 含 `*** ALL PASS ***`、`Errors: 0`，vsim exit=0（vlog Errors: 0）。
  - 正例：小帧（fbytes=4096/P=640）=hdr d716c1a4 / pay 4bbb8c6b / words 1024；1080p 全帧（2,592,768/P=2,592,000）=hdr 6b326735 / pay ae423f2e / words 648192；6 抽样字、busy/done、busy 重入拒绝（wcnt 5000→6780 单调）全通过。
  - 负例（fail-closed）：N1 magic(err=1)、N2 长度(err=4)、N3 头 CRC(err=2)、N4 载荷 CRC(err=3)、N5 AXI SLVERR(err=5)、T8 读超时(err=6)、T9 abort(err=7)、T0 参数非法(err=8) 全部按冻结 err_code 命中。
- 交付物（实际磁盘状态）：
  - `upstream/ph1p100-pcie-ep-fpga/rtl/ep_side/ddr/ddr_frame_readback_checker.v`（新建）
  - `upstream/ph1p100-pcie-ep-fpga/sim/tb/tb_ddr_frame_readback_checker.v`（新建）
  - `upstream/ph1p100-pcie-ep-fpga/sim/compile_checked.f` 末尾追加 1 行 `../rtl/ep_side/ddr/ddr_frame_readback_checker.v`
  - 日志：`workflow/runs/20261018-1347_runA_offline_sim/ddr-readback-checker/msim/new_tb/{vlog.log,vsim.log,commands.log}`（**判定以 vsim.log**）
  - git status 实测（本会话最后一次成功命令）：`M sim/compile_checked.f`、`?? rtl/ep_side/ddr/ddr_frame_readback_checker.v`、`?? sim/tb/tb_ddr_frame_readback_checker.v`；**无其它改动**。
- 冻结口径（细节见 RTL 头注释）：R10F magic=0x46303152；header_crc32=128B 内 word22 置 0；payload_crc32 覆盖 packed 载荷；长度=4KiB 对齐且 P>0 且 frame_bytes-(128+P)<4096；抽样 smp0..smp5 固定为头 word 0/20/21/22、载荷首字、含载荷末字节字；超时 TIMEOUT_CYCLES=2^21（单次等待；最坏 1080p 读 8×81,024=648,192 拍，阈值≥2×）；busy 重入忽略；abort→err=7；err_code 0..8 优先级 abort>timeout>AXI>magic>长度>头CRC>载荷CRC；words_read=已处理 32bit 字数；8 周期/拍串行字处理（STA 友好）。

## 未完成（工具权限拒绝，非技术问题）

- **开发侧“既有 8 TB 回归重跑”未执行**；**本地 commit、candidate.diff、candidate-manifest.json 未生成**：本会话 shell 连续 3 次 `Permission denied: shell`（含最简单的同形命令；此前同形命令被允许），按有界规则停止，未扩权、未绕过、未重试格式化。
- 影响评估（可检验依据）：本包只新增 2 文件 + .f 追加 1 行；共享编译清单**全量**编译在 new_tb 运行中 Errors: 0（vlog.log），既有 RTL/TB 逐字节未改；既有 8 TB 判定由综合测试者按 dev-plan §4 独立重跑（其原职责）。
- **恢复入口（原规划/用户手工，commands）：**
  1. 本地 commit（不推送）：
     `git -C upstream/ph1p100-pcie-ep-fpga add sim/compile_checked.f rtl/ep_side/ddr/ddr_frame_readback_checker.v sim/tb/tb_ddr_frame_readback_checker.v`
     `git -C upstream/ph1p100-pcie-ep-fpga commit -m "T11.runA-readback-checker: offline DDR frame readback checker RTL + TB (not integrated)"`
  2. candidate.diff：`git -C upstream/ph1p100-pcie-ep-fpga diff HEAD~1 HEAD > workflow/runs/20261018-1347_runA_offline_sim/ddr-readback-checker/candidate.diff`（或 `git show` 等价）
  3. candidate-manifest.json：按 design-guide §6 规范重算 SHA256（files=RTL/TB/.f/candidate.diff/msim 日志；0 不一致）；本会话未能计算任何 SHA256。
  4. 8 TB 回归：对 tb_cam_r10f_writer、tb_t11_r10f_e2e、tb_t11_csi_enable_corner、tb_csi_checked（`-Defines MIPI_PHY_SIM_STUB`）与 tb_ddr_frame_pusher_rka1、tb_csi_integrity_diff、tb_ep_bar_win_rka1、tb_ddr_wr_arb（文件 tb/tb_ddr_wr_arb_peer.v）逐个 `run_sim.ps1`，判定以 vsim.log。

## 复测入口（综合测试者）

`powershell -ExecutionPolicy Bypass -File tools/pcie_integration/run_sim.ps1 -Tb tb_ddr_frame_readback_checker -OutDir <dir> -TbFiles tb/tb_ddr_frame_readback_checker.v`（`MSIM_BIN=D:\intelFPGA\18.1\modelsim_ase\win32aloem`；判定看 vsim.log 的 `*** ALL PASS ***`）。负例已内建（≥4）；测试者可另建负例。

## 环境异常观察（重要，供后续规避）

- `compile_checked.f` 出现“写入后短时间内在另一路径视角下缺行/回滚”的现象：前两次 run 编译不到新模块，而同一文件用 Select-String 可见新行、行数计数不一致（66→67）——疑似 OneDrive 同步竞争。处置：复核后重写该文件并复跑，最终 3 次连跑（最后一次 ALL PASS）确认当前磁盘状态可复现。
- 本会话末段 shell 连续被拒（见上）。

## lessons（并入本文件；dispatch：必要时 lessons-learned.md）

1. 状态“粘滞位”必须**命中时置位、收尾状态清除**：只粘不清会活锁并吞掉下一次 start（T8→T9 相邻用例实测暴露：timeout 后 tmo_r 残留在 go_fin 条件中 → ST_IDLE 被反复压回 ST_FIN，start 永远不被采样）。
2. 仅单拍有效的组合命中（如“计数器==阈值”）不可直接用于 done 时判码，必须注册为粘滞位；修一是 tmo_r，修二是 ST_FIN 清 tmo_r。
3. TB 负例顺序要覆盖“上一用例的残留状态”（相邻用例交换常暴露 FSM 收尾缺陷）。
4. OneDrive 下仓库文件写入后，务必以同一绝对路径复核（git diff / 重读）再编译、再提交。

## 补收记录（completion pass，2026-10-18，新 fpga-dev 会话；原文以上保留未删改）

- 结果：**ready_for_test**（离线；判定口径 vlog Errors:0 + vsim ALL PASS）。新 TB 复跑 `*** ALL PASS ***`；既有 8 TB 全体按基线约定 `-Defines MIPI_PHY_SIM_STUB` 8/8 ALL PASS（日志 `regression/<tb>/{vlog.log,vsim.log,commands.log}`；单 TB ≤300 s 实测最长 78.3 s）。上一会话的 `Permission denied` 未复现（判为会话级属实）。
- commit：`c89ab75803796ed7e9918aa55071c7df3284aa8f`（分支 codex/raw10-rka1，未推送；parent=48be9f20）。原 commit `1042ade` 已 amend：diff 仅 3 路径，numstat = RTL 414/0、`.f` **1/0**、TB 466/0。
- 对受保护文件的**必要修复**：上会话 OneDrive 重写 `sim/compile_checked.f` 造成中文注释 mojibake 与换行合并（numstat 13/16，违反“仅允许追加 1 行”）。补收脚本先证明“有效路径集合 == 父提交 + 唯一追加行”（44→45，顺序一致），随后恢复为父提交字节 + 唯一追加行并 amend（工具脚本 `completion_tools.py prep`）。
- 冻结：`candidate.diff`（41,303 B）、`candidate-manifest.json`（生成时复算 0 不一致；含 protected 审计）。（如与上述任一字节不符，以 manifest 为准。）
- 新增 lessons：
  1. 任何“重写既有文本文件”的操作后，必须用 `git diff --numstat` 复核：除预期追加外不应出现其它增减；1+/0- 以外即编码/换行损伤。
  2. 中文 Windows 下不要对 UTF-8 文件做 `Get-Content`/`Set-Content` 往返（默认 ANSI 造成 mojibake 与未知换行变化）；需字节级重写时用 Python `open(...,'rb'/'wb')`。
  3. 回归 define 约定以 merge run design-guide 为准：8 TB 全体 `+MIPI_PHY_SIM_STUB`（e2e 不带 stub 必失败，缺厂商 PHY 原语）。
- 恢复入口：本记录即终态；后续仅剩“新建一个综合测试者”步骤（复测入口见上）。
