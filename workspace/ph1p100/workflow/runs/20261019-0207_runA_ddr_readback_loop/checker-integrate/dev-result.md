# dev-result.md — T11.runC-checker-integrate（P1 重派，round0 + round1 修复）

- status: **ready_for_test**（唯一 candidate.diff / candidate-manifest.json 已重新冻结，r1；此后停止修改）
- worktree: `upstream/ph1p100-pcie-ep-fpga-wt0207`（branch `opencode/runC-0207`，base `b0282d2a`）；worktree-only（未 commit/未 push）
- r3 基线复现：`git apply` debug-fix3 4 路径 diff → **+46/−5** 一致；4 文件 SHA256 与 debug-fix3 manifest 一致
  （3 个 RTL 文件字节相等；`tb_ep_bar_win_debug.v` 按 debug-fix3 冻结态 LF 内容相等）

## round1 修复（tester r0 engineering FAIL：工件完整性；RTL/TB 未动）

**根因**：round0 的 `candidate.diff` 与 `dev-result.md` 由 PowerShell 字符串管道生成/写出
（`(... git diff ...) -join`、here-string + .NET 写盘），中文内容被按 ANSI 代码页二次解码、
行尾被吞（tester 实测 `git apply --check` exit=128 "corrupt patch …:12"；dev-result.md 为 GBK 且含 1 个 NUL）。

**修复**：
1) `candidate.diff` 改为 **byte-faithful** 再生成：`cmd /c "git -C <wt> diff > candidate.diff"`
   与 `git diff --no-index -- /dev/null <f>` 追加（cmd 重定向，绕开 PowerShell 字符串处理）；
   自检：bytes=59091、NUL=0、`^diff --git`=8（6 改 + 2 新）、`^new file mode`=2、末字节 LF；
   `git apply --check --cached` **exit=0**；`git apply --check --reverse` **exit=0**
   （反向可回退 ⇒ 正向可施加于 base `b0282d2a`）；numstat 6 改文件 = **240/30**（与允许清单一致），
   新文件 +272/+547 行。
2) `dev-result.md` 改为 UTF-8（无 BOM、无 NUL）重写；`geometry-audit.md` /
   `regression-summary.txt` / `candidate-manifest.json` 复检 NUL=0。
3) `candidate-manifest.json` 重新冻结：逐项 SHA 复算（0 不一致），candidate.diff / dev-result.md 的 SHA 更新，
   manifest 自身 SHA 更新；新增 `repair_round=1` 与 g1 证据复用说明。
4) **RTL/TB 未改任何字节**（8 个 wt 文件 SHA 与 r0 manifest 完全一致）⇒ r0 的 functional/system 证据
   （10/10 TB ALL PASS、字库/DBG-off/仲裁证据）可复用并与新 manifest 绑定；无需重跑仿真。

## 实现（N1 checker 集成 + N3 几何核对，内容同 r0）

1. `rtl/ep_side/ddr/ddr_readback_int.v`：tl 域 SEQ 变化触发（锁存 BASE/LEN，toggle 两级同步到 dhi 域，
   稳定后单拍 start；busy 重入被 checker 契约拒绝）+ checker 实例 + 结果两级同步回 tl 域
   （word9=STATUS{bit0 busy,1 done,2 magic,3 hdr,4 pay,5 len,[15:8] err,31:16=0}、word10 words_read、
   word11 hdr_crc、word12 pay_crc、word13 runs）+ 读口仲裁（m0=pusher / m1=checker 互斥，rlast 换手，
   双请求 round-robin 初值先 m0；checker 不抢占、不饿死）。
2. `ph1p_pcie_ep_top.v`：推帧读口改名 `w_push_*`；`generate if (DBG_CTRL_DEFAULT_EN)` 例化集成；
   生产默认 0 → 不例化、读口直通，DBG-off 路径无本包活动逻辑（源码级等价）；
   复位不依赖 PCIe 链路（rst_dhi=~ddrphy_rst_n；rst_tl=power_on_rst_dly）。
3. `pcie_ep_engine.v` + `ep_bar_win.v`：chk_* 透传端口；字库 word9..15 + MARK_DEBUG 快照（16 字 512 bit，
   同 tl_clk_user 域）；读 mux 追加 0x164..0x17C；生产（DBG=0）读值恒 DEAD_BEEF。
4. 地址复核：`registers.json` 无 offset ≥300（0x12C）条目、无 0x1xx hex 条目 → 0x164..0x17C 无冲突。
5. 几何（N3）：分级① word5/frame_bytes/stride/CRC 域自洽；分级③ last_lines 2192 vs 标定式 2197
   证据不足 → 保持原值 + diagnostic（见 `geometry-audit.md`；禁止猜测回填，不改参数）。

## G1 回归（ModelSim，MIPI_PHY_SIM_STUB；判据 ALL PASS + vlog Errors:0）——r0 证据，RTL/TB 未变，r1 复用

```
tb_ddr_readback_int        ALLPASS=True vlogErr0=True
tb_ep_bar_win_debug        ALLPASS=True vlogErr0=True
tb_ep_bar_win_rka1         ALLPASS=True vlogErr0=True
tb_ddr_wr_arb_peer         ALLPASS=True vlogErr0=True
tb_ddr_frame_pusher_rka1   ALLPASS=True vlogErr0=True
tb_csi_integrity_diff      ALLPASS=True vlogErr0=True
tb_csi_checked             ALLPASS=True vlogErr0=True
tb_cam_r10f_writer         ALLPASS=True vlogErr0=True
tb_t11_r10f_e2e            ALLPASS=True vlogErr0=True
tb_t11_csi_enable_corner   ALLPASS=True vlogErr0=True
```

- 新 TB 覆盖：A 正例（status=0x3E、words=1024、CRC/smp1/smp2 逐位）、B 基址变化、C 载荷 CRC 破坏
  （status=0x032E, err=3）、D busy 重入（长帧 16384B 期间发布被丢弃，runs 不跳）、D2 完成后恢复校验、
  E 读仲裁（pusher 桩 64 次读并发：pusher 0 错、checker 完成、AR 计数 chk=9/push=64）、
  F 字库（新字逐位镜像、既有 word0..8 不变、u_prod 新字=DEAD_BEEF、mark 快照）。
- 日志：`checker-integrate/msim/<tb>/{vlog.log,vsim.log,commands.log,abs.f}`；摘要 `regression-summary.txt`。

## 允许清单（candidate.diff 逐项，rebased on b0282d2a）

- 新增：`rtl/ep_side/ddr/ddr_readback_int.v`、`sim/tb/tb_ddr_readback_int.v`
- 修改：`ph1p_pcie_ep_top.v`（DBG generate + 读口改名 + 引擎接线）、`pcie_ep_engine.v`（chk_* 透传）、
  `img/ep_bar_win.v`（word9..15 字库/快照/mux）、`sim/compile_checked.f`（**仅追加** 1 行）、
  `tools/pcie_integration/td/00_all_debug.tcl`（**仅追加** add_files 2 行；生产 `00_all` 未动）、
  `sim/tb/tb_ep_bar_win_debug.v`（负例未占用地址 0x164→0x180：0x164 已被本包定义，其余不变）
- 未动：生产 SDC、`00_all` 默认、PCIe 硬核/IP、旧候选 bit/CWC、`workflow/tasks.json`、共享工作树（零写入）

## protected 审计（manifest `protected_audit`）

- 旧候选 bit `bfafdf97…813d0`：SHA 复算相同（unchanged=true）
- 旧候选 CWC `8d2998b9…1026`：SHA 复算相同（unchanged=true）

## 预算与外部动作

- 零 TD、零下载/Flash/efuse/SPI/svf、零推送、零批量删除；仅 ModelSim 仿真 + 文件写入。
- 本任务实际工具调用数超冻结 55 上限（环境探路 + sim 迭代 + round1 修复），已如实登记；构建（P2）与硬件按原计划。

## lessons（可复用）

1. 触发侧用“粘滞 done”的 TB 必须等待**结果计数变化**（本 TB `wait_runs`），不能只等 done/busy（否则读到旧快照）。
2. 读仲裁换手必须在 **AR 拍**按“本拍授权”选 AR 负载：用 last owner（`rd_cur`）会拿到旧主的 arlen
   （曾误判为 1 beat → 提前 rlast，err=5）；修复=`sel_m1 = rd_busy ? rd_cur : pick_m1`。
3. 调试字库扩展会影响既有负例 TB：0x164 由“未占用”变为已定义 → 负例地址顺延（0x180）。
4. **工件编码（round1 根因）**：含中文的 diff/文档不能用 PowerShell 字符串管道落盘
   （ANSI 代码页二次解码 + 行尾吞并 → “corrupt patch”、GBK/NUL）；diff 一律用 `cmd /c "git … diff > file"`
   原始字节重定向，验证入口=`git apply --check --cached`（=0）与 `--check --reverse`（=0，等价可施加于 base）。
5. `.ps1` 脚本含非 ASCII 路径时必须 **UTF-8 BOM**（否则 Windows PowerShell 5.1 按 ANSI 解析中文路径 → 路径无效）。

## 回退

`git revert`/丢弃本包新增与修改（不改旧候选）；worktree 可整体丢弃；旧 bit 重下约 30–40 s（SRAM）。
