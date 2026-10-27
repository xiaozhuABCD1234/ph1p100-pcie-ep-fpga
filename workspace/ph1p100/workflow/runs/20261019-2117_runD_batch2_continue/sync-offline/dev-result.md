# T08 开发结果 — `T08.codex-sync-offline`（runD batch2）

日期：2026-10-19 21:34–21:46 +08:00｜角色：fpga-dev｜状态：**ready_for_test**（G1/G2 通过；G3/G4 不适用）

## 1. 结论

双相机安全启动/SOF 配对离线原型已可编译、可自检、可综合：修复 `sync_offline_top.v` 两处非法空位置连接后，ModelSim 正例 `SYNC_OFFLINE_PASS mismatch=0`、`vlog Errors:0`；隔离负对照在 tx=5 被预期拒绝且编译 0 错误；TD 小顶 `Confidence: Routed`，SWNS **+0.294 ns**/STNS 0、HWNS **+0.043 ns**/HTNS 0，50/187.512/187.512 MHz，资源 872 slices（1.22%），B01 699 项 0 漂移。未接活动 top、未下载、未写 Flash、未 commit/push。

## 2. 实际改动（仅允许范围）

1. `upstream/ph1p100-pcie-ep-fpga/rtl/ep_side/cam/sync_offline/sync_offline_top.v`
   - 原两行：`sync_sof_mailbox ma(...,a_lost,());` / `mb(...,b_lost,());`（第 9 端口字面空位置连接，vlog-13069）。
   - 改为 ma/mb 全部 named 端口，未用的 `src_busy` 用合法 `.src_busy()`。**仅连接语法**，未改功能/参数/时钟/复位/接口语义。
   - diff：`sync-offline/top-port-fix.diff`。
2. `upstream/ph1p100-pcie-ep-fpga/sim/tb/tb_sync_offline.sv`
   - 仅“无 SOF 锁超时”场景：`reset_all();boot();ticks(180);` → `reset_all();boot();mode=1;ticks(180);`。
   - 原因：该场景故意触发 FRAME_TIMEOUT 清理，旧 TB 仍按正常 14 笔顺序检查，先报 `SYNC_FAIL ordered role writes cycle=828 tx=14`。改后正常 boot 的 14 笔顺序检查仍全部保留。
   - diff：`sync-offline/tb-timeout-scenario-fix.diff`。

未改：活动 top、`sim/compile_checked.f`、I2C/寄存器表、生产约束/IP/ADC、B01 699 项、0212 旧 run 文件。

## 3. G1（ModelSim 10.5b / Intel 18.1 ASE）

- 正例（最终复验）：`sync-offline/g1/positive-r2-final/`，`vlog Errors:0, Warnings:0`；vsim 输出
  `SYNC_OFFLINE_PASS mismatch=0 scenarios=prereq,hold,busy,order,wait,warmup,nack,timeout,missing,abort,reset,relock,overrun,wrap`。
  支持证据：`positive-r1/` 为同一修复版本的首次 PASS。
- 覆盖：角色顺序/白名单、WAIT_B/WAIT_A 24 ms 缩放边界、前 8 帧/第 9 帧、NACK、accepted-request timeout + transport poison、单路缺失、abort 清理、reset/恢复、失锁重锁、mailbox overrun、32-bit 时间戳回绕、背压保持、busy 重入忽略、前置门禁。
- 负对照：`sync-offline/g1/negative-r1/`，隔离副本把 `30C1` step 5 的 `0F` 变异为 `00`；`vlog Errors:0`，vsim 在 tx=5 报 `SYNC_FAIL ordered role writes`（预期拒绝，不是编译错误）。
- **外部改写记录（证据完整性）**：21:39:29 发现 `tb_sync_offline.sv` 被外部恢复为未修复版（SHA `bc99c72…`，5720 B，行 110 无 `mode=1`），而 `positive-r1` 日志对应修复版 PASS。21:48 重放同一修复（SHA `dd03c079…`，5727 B），以 `positive-r2-final` 重新编译/运行，结果一致 PASS；冻结前另存 `sync-offline/tb/tb_sync_offline_frozen.sv` 作为字节副本。该改写非本角色操作，已保留记录。
- 计数：正例编译 3 次（首次编译成功但 TB 场景时序缺陷；第二次修正后 PASS；外部改写后第三次复验 PASS）；负对照隔离编译单独计。
- 诊断保留：`g1/positive-r0/vsim.log`（首次失败证据，不删除）。

## 4. G2（TD Release_2026.2，一次设计、不下载）

- 小顶：`sync-offline/g2/sync_offline_g2.v`（显式 named 连接；独立载体，不做板级声明）。
- 约束：`sync_offline_g2.sdc`：50.000 MHz `clk_ctrl`、187.512 MHz `clk_a`、187.512 MHz `clk_b`；三组 asynchronous clock groups；ctrl/SOF I/O delay；仅 `rst_n` 异步 false path。
- 结果：`Confidence: Routed`，final timing `SWNS 0.294 ns / STNS 0`、`HWNS 0.043 ns / HTNS 0`；3 个时钟 0 违例；`route.qor` 872 slices（1.22%）、752 LUT6、964 regs、0 RAM/0 DSP、81 IO（28.32%）、3 GCLK。
- DRC：`chk.timing` 无 no-clock/clock-def/dummy/invalid-constraint/PLL/组合环/soft-fifo/no-path/shadowed 问题；5 个 MEDIUM no-input-delay 为 `rst_n`（有意异步）与 `select_diag[3:0]`（静态诊断选择），已在 manifest 明确说明，无宽泛豁免。
- **bitgen 说明**：独立小顶无 ADC 引脚位置，bitgen 被 TD 拒绝；本轮不使用/不声明任何 bit/CWC。Routed DB 与 timing 报告在 bitgen 前已生成，G2 只取 Routed/时序/CDC/资源。
- TD 会话透明记录：第 1 次脚本变量导致 `add_files` 空路径；第 2 次 `.v` 载体使用 SystemVerilog `.*` 被拒；第 3 次综合完成但 bitgen 因未约束 IO 中止；第 4 次按 TD 文档 `set_param bitgen unconstr_io on` 完成 route。**未放宽任何时序/约束门槛，未为 G2 改设计 RTL**；前三次均未产生可用 G2 结果，第四次为最终证据。

## 5. 身份/漂移与安全

- B01 manifest 改前/改后均为 `c7a40897166467f2beafb096701dba9cf836e1007d77ae03d90009d06f80d757`、699 项、0 漂移。
- 本轮新增/修改文件全部在允许范围；未写 0212 旧 run、活动 top、`compile_checked.f`、I2C/约束/B01。
- 0 次下载、0 Flash/efuse/SPI/svf、0 CLI 读回、0 GUI 自动化、0 commit/push、0 批量删除。

## 6. 预算与未测边界

- 时间约 12 min（预算 40 min）；工具调用约 27 次（预算 35）。T02 实际约 26 次（预算 20，超出 6 次，主要花在两次只读探测与证据落盘；batch 总计仍在 55 次内，实际以文件为准）。
- 未测：真实双路主从/电气/曝光同步、接活动 top、寄存器读回/硬件配置；这些是父 T08 的 G3/G4，不在本离线包。
- 回退：本轮改动可按单文件丢弃/保留 worktree-only；旧 26 项 manifest 不覆盖。

## 7. 复测清单（交综合测试者）

必复测：独立重编译（同一 DB）+ 正例 `SYNC_OFFLINE_PASS mismatch=0`；负对照预期拒绝且编译 0 错误；24 ms 默认常数推导/位宽；角色顺序/8 帧/NACK/timeout/单路/reset/恢复/SOF 配对/回绕；G2 报告三时钟/ Routed/WNS/TNS/CDC/资源；manifest 0 不一致；B01 699 项 0 漂移。
输入变化：`sync_offline_top.v`、`tb_sync_offline.sv`、`sync-offline/**`。
未影响可复用：B01 699 项/G0–G2、T06/T09 报告、0207 证据（只读）。
