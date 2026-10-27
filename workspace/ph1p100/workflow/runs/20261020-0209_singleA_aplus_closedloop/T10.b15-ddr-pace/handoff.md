# T10.b15-ddr-pace — handoff（规划冻结，2026-10-26）

## 1. 状态

| 项 | 值 |
|---|---|
| task_id | `T10.b15-ddr-pace` |
| 状态 | **ready**（已冻结，待派开发） |
| 父任务 | T10 **保持 blocked**，本包不关闭 T10 |
| 批大小 | 1 |
| `needs_user_input` | **false** |
| 派发 | `T10.b15-ddr-pace/dispatch.json` → `spawn_agent` / `fpga-dev` |
| 规划预算 | 15 min / 30 calls（本冻结已完成） |

## 2. 为什么开这一包（b14 r0 板级事实）

- `CAP sel=0`、`sysstat bit20=0`：A 路；A 相机**已恢复**：`cap_frames=4470`、`pix_beats` 正常、`crop_short=0`、`crop_geom_err=0`、`raw_pub=4470`。
- A+ 读每帧**必然失败**：`timeout=13,410`（3/帧）、`retry=8,940`（2/帧）、`giveup=4,470`（1/帧）、`enc=0`、`exported=0`。
- `ar=17,213,681`、`r=17,200,031` → **每次尝试都少回 1 个 R**（H4 稳定复现，不是随机延迟）。
- 证据：`T10.b14-cam-b/r0/board/captures/status_v5.txt`（150 包，`bad_xor=0`）。

## 3. 根因假设（有源码依据，不是猜测）

`p2_ddr_bridge.v`（`BFF1A358…49731`，自 b13 起未改）中：

- `ar_pending` 在**首个** `paxi_rvalid && paxi_rready` 就清零，而不是 `paxi_rlast` → “单笔 AR”只是名义上的：一笔 burst 还没回完就可能放行下一笔 AR；
- `paxi_rready = rd_hold ? 1 : (r_expected ? rf_wready : 1)`、`rf_push = paxi_rvalid && r_expected` → 当 `ar_pending=0` 时到达的 R 拍被 `rready=1` **吞掉**（不入 RF、不入帧）；
- 结果：每次读尝试的最后一笔 burst 尾部少 1 拍，帧永远读不完 → 8192 超时 → 重试 2 次同样少 1 拍 → giveup，`enc/exported=0`。

本包不直接承诺“这就是唯一根因”，而是按用户指令把它**结构性消除**：严格单笔、`rready` 常开、每拍必入队；若仍失败，用 `ar/r/rlast` 三元组与地址证据定位。

## 4. 冻结的改动（只 1 个 RTL）

| 规则 | 内容 |
|---|---|
| R1 | `ar_busy` 在 AR 握手置位，**只在 `rvalid && rready && rlast` 清零**（purge/guard 强清保留） |
| R2 | 新 AR 仅在 `!ar_busy && af_rvalid && rf_path_empty && ddr_rdy && !rd_hold` 时发；`rf_path_empty` = RF 占用 0 且 skid 空（跨域 toggle+2FF） |
| R3 | `paxi_rready` **恒 1**；不靠背压保数据 |
| R4 | 一笔 burst 的每一拍都 `rf_push`；孤立/晚到 R 只计 `stale` 不入队 |
| R5 | b13 `TIMEOUT=8192` / `RETRY_MAX=2` / `A1_GUARD_N=70000` / `BRIDGE_GUARD_N=65536` / purge 语义**逐条保留**为兜底 |
| R6 | `MAX_OS=1`；2 笔仅当仿真证明 1 笔达不到 ≥77.76 MB/s 且 R 归属无歧义，且书面记录 |

- **10 个 RTL 文件逐字节不变**（核 `C9DE0D9C…05089`、`p2_a1_board_top.v` `48881D57…E561B` 等）；SDC diff 必须为空；v5 **241 B / 59 字段不变**。
- **CAM_SEL 不引入**：b14 r0 板级跑的是 **A-only** `p2_a1_board_top`（与 b13 r1 同哈希），本包保持该基线；b14 的 B 选择 diff 挂起为后续主题；B 前端代码（`u_cfg_b`/`u_csi_b`）仍在核内，只是不被选中。

## 5. 验收要点（详见 dev-plan）

- 仿真：**正常整帧**、**丢 1 R→超时→重试→整帧**、**连续 3 帧**、**full 两帧**、P1 三黄金逐字节、**b12/b13 回归**、抗逆例（末拍 `rlast` 丢失/晚到重复 R/`arready` 压低 100 拍/`rvalid` 空 64 拍）、v5 结构、`if_max_os==1`。
- 构建：Routed 0 违例、hold≥0、period 正、ERAM+CWC≤300；WNS 目标 ≥+0.05（+0.003..+0.05 接受并记 `timing_caveat`；<+0.003 或违例即停）；1 bitgen + 1 CWC。
- 板级：FTDI 预检 → 在位则**1 次 SRAM 下载成功后再开 COM8**，150 s；目标 **timeout/retry/giveup 增量全 0**、`enc_frames/exported` 增量 >0、≥1 帧四 CRC+zlib、`ar_cnt − rlast_cnt ≤ 1`。
- 若仍每帧丢 R：停止、留证（`ar/r/rlast/stale` 差分、失败帧/尝试号、`last_ar_addr`），**不第二次下载**。

## 6. 预算

开发 **120 min / 60 calls**；TD **3 会话**、综合 ≤3、布线 ≤2、bitgen 1、CWC 1、下载 1、Flash 0；综合测试 45 min / 30 calls。禁止批量删除。

## 7. 未决 / 已挂起

1. `L_max`（PAXI 每笔 AR 的 burst 拍数）**未取证**，由开发在 W1 从 IP/波形确认后写入 `r0/diag/paxi-read-facts.md`；若 `L_max > 16` 才允许改 RF 实例 `ADDR_BITS=5`。
2. b14 的 `CAM_SEL` + B tap/SDC 变体：**挂起**，不在本轮合并（避免与 DDR 卡点混变量）。
3. `workflow/tasks.json` **本冻结未改**（b 系列细目历来在收尾时由原规划统一登记）；父 T10 仍是 blocked/not done。
4. FTDI/板卡是外部条件：不在位即 `board=blocked`，不是 FAIL，也不问用户。

## 8. 下一次准确启动/恢复文本

> 恢复 `20261020-0209_singleA_aplus_closedloop` 的 **`T10.b15-ddr-pace` r0**（ready；1 bitgen+1 CWC；SRAM 下载 ≤1）。
> 先读 `T10.b15-ddr-pace/{dev-plan.md,fpga-design-guide.md,handoff.md,dispatch.json}`、`T10.b13-ddr-retry/r1/td/src/p2_ddr_bridge.v`（`BFF1A358…49731`）、`T10.b13-ddr-retry/r0/changed-src/**`、`T10.b13-ddr-retry/r1/td/**`、`T10.b14-cam-b/r0/board/captures/status_v5.txt`。
> 已确认：A 相机 4,470 帧正常、几何无误、`raw_pub` 正常；唯一卡点是 DDR 读每笔 AR 少回 1 个 R（`timeout/retry/giveup = 3/2/1` 每帧，`ar−r=13,650`，`enc=exported=0`）。
> 目标：**只改 `p2_ddr_bridge.v`** —— 严格单笔 AR（`ar_busy` 到 `rlast` 才清）、`paxi_rready` 恒 1、RF 保证有空间、每拍必入队、孤立 R 只计数；b13 超时/重试/purge/guard 语义不变；v5 241 B/59 字段不变；其余 10 个 RTL 逐字节不变。
> 仿真：正常整帧、丢 1 R、连续 3 帧、full 两帧、P1 三黄金、b12/b13 回归、抗逆例、v5 结构、`if_max_os==1`。
> 构建：Routed 0 违例（WNS 按 dev-plan §6）、ERAM+CWC≤300、1 bitgen+1 CWC。
> 板级：FTDI 在位 → 1 次 SRAM 下载成功后再开 COM8 150 s；`timeout/retry/giveup` 归零、`enc/exported` 增量>0、≥1 帧四 CRC+zlib；仍每帧丢 R 则停止留证，不第二次下载。
> 120 min/60 calls；TD 3 会话/综≤3/布≤2/bitgen 1/CWC 1/下载 1；失败即停，不自扩预算，不批删。
