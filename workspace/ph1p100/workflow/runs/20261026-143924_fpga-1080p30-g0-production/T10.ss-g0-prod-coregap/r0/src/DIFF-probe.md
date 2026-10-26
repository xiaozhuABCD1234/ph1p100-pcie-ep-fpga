# DIFF-probe — P2 stage-probe TB vs P1 r1 frozen TB

- 基线：`T10.ss-g0-prod-content/r0/src/tb_ss_4run_wd.v`，SHA256
  `785c3ef1d044f8529b7232ae37ed3a67172b6c4cd512c47a713103675090b79a`（= P1 manifest-r1 值）
- 探针副本：本目录 `tb_ss_4run_wd_probe.v`（module 名保持 `tb_ss_4run`，便于复用同一 vsim 入口）
- 生成（**r1 重生成，R1**）：`git diff --no-index --unified=2 <P1 TB> <probe TB>` → `DIFF-probe.raw`
  = **54 行 / 3 个 hunk / +32 −0**（SHA256 见 `manifest-r1.json`；TB 本体未改，SHA256 `d2aa6cc09b8c091a3581dee02f2d556c2384f67d1ee2ee2a705c250933f86c31`）。
  r0 冻结的 43 行 `.raw` 是**旧版**（`CORE_STAGE` 当时仍在 `SS_STATS` 之后，即 N#1 的 harness 版本），已由本次重生成取代（OBS-1）。
  说明：测试者独立副本 `test-reports/T10.ss-g0-prod-coregap/tester-real-diff.txt` 用的是 `--unified=3`，为 60 行 / 3 hunk；**hunk 内容与本文件逐行相同**，行数差异只来自 context 行数。

## 白名单（本次只允许这 5 项，逐项对应实际 diff）

| # | 位置 | 变更 | 语义 |
|---|---|---|---|
| 1 | 声明区（`ss_pass` 之前） | 新增 `integer probe_t_pub1 = -1; integer probe_t_enc1 = -1; reg probe_dumped = 1'b0; integer probe_dump_wait = 0;` | 仅探针用的观察寄存器，不进入任何 DUT/TB 功能表达式 |
| 2 | `st_pub !== prev_pub` 分支 | 追加 `if (st_pub == 1) probe_t_pub1 = cycles;` | 只读记录 `t_pub(1)`（已有 EVT 打印的同一事件） |
| 3 | `st_enc !== prev_enc` 分支 | 追加 `if (st_enc == 1) probe_t_enc1 = cycles;` | 只读记录 `t_enc(1)` |
| 4 | 同步块内、enc 分支之后（8 拍事件式 dump） | 新增 `probe_dumped/probe_dump_wait` 计数块：commit 后 8 个 `clk_a1` 打印一行 `CORE_STAGE` | 只读层次引用 `dut.u_a1.u_core.stat_*`（9 个 counter 输出）+ `st_expb` + 两个时间戳；8 拍延迟保证 stat 递增已落地 |
| 5 | 注释/命名 | 上述块的注释 | 无功能 |

## 不变量（逐字节未改，测试者可反向重建核对）

- `drive_frame()` / 几何 `CAM_W/H`、`ROI_X/Y`、`W/H`、`RAW40`、`CONTENT=2` 组包路径；
- 时钟/复位（`clk_a1` 5.333 ns、`clk_cam`、`clk_uart`）、`rst_n` 时序；
- `ss_pass` 表达式（仍含 `st_dup == 0`：自然内容下必为 0，**不是验收旗标**，见 guide §3）；
- 看门狗（`WD_LIMIT_COLD` 锚 `t_sof(1)`、`WD_LIMIT` 锚 `last_exp_t`）、`MAX_CYCLES` 判定、
  `SS_STALL*` 分支、`B11_FULL_RESULT` 打印、`SS_STATS` 打印内容、drain 逻辑；
- 12 个 DUT 源与本目录 `a1_*.v`/`camera_*`/`p2_*`/`capture_async_fifo.v` 逐字节 = P1 基线（`dut_mismatch=0`）。

## 禁止项核对

- 无 `force` / `deposit`：`grep -n "force\|deposit" tb_ss_4run_wd_probe.v` → 仅本文件注释无匹配；
- 不改 DUT 源（12 源 SHA 与 P1 manifest-r1 一致）；
- 无 TD / 综合 / 布线 / bitgen / CWC / 下载 / Flash / 板卡 / COM / JTAG / RK / 网络。

## 运行变体（非 TB 改动，命令行参数）

- `-gFRAMES=1`、`-gCONTENT=2`、`-gPACING=0`、`-gSINK=1`、`-gCAPTURE=0`、
  `-gMAX_CYCLES=<N:12800000 / L:13300000>`、`+RAW40=<P1 冻结 raw40_{n,l}.hex>`（只读引用）。
- `MAX_CYCLES` 之所以要显式给：TB 继承的 `while ((st_read < 2*129600) ...)` 是 4 帧信息性等待，
  单帧下永不满足，会让仿真跑到 `MAX_CYCLES` 后由 `B11_FULL_TIMEOUT` 收尾（不影响已发生的事件与
  commit 时打印的 `CORE_STAGE`）。**不改该行**，只调参数。
