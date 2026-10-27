# T10.b17-paxi-native — handoff（规划冻结，2026-10-26）

## 1. 状态

| 项 | 值 |
|---|---|
| task_id | `T10.b17-paxi-native` |
| 状态 | **ready**（已冻结，待派开发） |
| 父任务 | T10 **保持 blocked**；本包不关闭 T10 |
| 批大小 | 1 |
| `needs_user_input` | **false** |
| 派发 | `T10.b17-paxi-native/dispatch.json` → `spawn_agent` / `fpga-dev` |
| 规划预算 | 15 min / 30 calls（本冻结已完成） |

## 2. 为什么开这一包

b15 的读严格单笔候选在板上仍是 `timeout/retry/giveup = 3/2/1 每帧`、`enc/exported=0`、`ar−r=13,740=尝试数`、`stale=0`：缺失的 R 从未到达 PAXI R 通道。b15 的仿真全绿，但根因审计证明它的模型把三个原生合同差异全部忽略了：

1. **地址单位**：b15 发字下标 `0,1,2`；原生参考发 `0,8,16`（`{word_index,3'b000}`）；链路无 ×8。
2. **写 mask**：b15 恒发全 1；原生完整写 mask=0（mask 0 写整字）；模型忽略 mask。
3. **命令接纳**：b15 读写可同拍握手；原生参考单命令仲裁。

因此 b15 的 PASS 不能排除真实接口使用错误。本包先修接口合同，再决定是否进入 MC/IP。

## 3. 冻结的改动

| 文件 | 改动 |
|---|---|
| `p2_ddr_bridge.v` | 唯一边界地址转换 `{word_index[23:0],3'b000}`（AW/AR）；`paxi_wstrb=0`；`ALLOW_CONCURRENT=0` 单命令互斥；保留 b15 读严格性/超时/重试/purge；v6 诊断与 512-bit `dbg_a1` |
| `camera_a1_uart_top.v` | `i_dbg_bridge` 256→512；`sts_ext` 512→768；v6 #60..#67 追加；v5 #44..#59 位序不变 |
| `p2_a1_board_top.v` | `dbg_bridge` 256→512 |
| `a1_uart_export.v` | 状态包 v6：273 B / 67 字段 / VER=6 / LEN=0x11 / XOR 0..271；v5 #1..#59 不变 |
| 其余 7 个 RTL | **逐字节不变**（含 `f9p_camera_display_core`、store、arb、frame、deflate、crop、mailbox） |
| `p2_board.sdc` / ADC / 帧格式 / 几何 / 时钟 / DDR IP | **不动** |

v6 新增：`last_issued_ar_addr`、`last_issued_ar_low3`、`timeout_ar_addr`、`timeout_ar_low3`、`same_aw_ar_cnt`、`same_w_ar_cnt`、`inflight_state`、`diag_flags`。

## 4. 验收要点

- **先做 16 字写-停-读回**：内部字 0..15、停写 ≥32 周期、逐字读回；模型必须看到地址 0,8,…,120、mask=0、无低3位/越界/同拍、16/16 数据一致。
- **再整帧/两帧/丢 R**：A 几何 3864×2192 → ROI 972/556 → 1920×1080；S1 `ar=r=rlast=210,685`、S2 `421,370`、S3 `timeout=1 retry=1 giveup=0 exported=1`；四 CRC+zlib、无半帧。
- **P1 三黄金**：`micro8x2`/`mid64x8`/`full_grad` 压缩字节与 b15 caps 逐字节一致。
- **模型负对照**：b15 旧桥对 b17 模型必须失败；全 1 mask 必须不写；低3位/越界/并发必须被计数且不挂死。
- **构建**：Routed 0 违例、WNS 目标 ≥+0.05（+0.003..+0.05 接受为诊断候选并记 thin margin；<+0.003 或违例即停）；ERAM+CWC≤300；1 bitgen + 1 CWC。
- **板级**：FTDI 在位 → 先 1 次 SRAM 下载，成功后再开 COM8 150 s；`timeout/retry/giveup` 增量全 0、`enc/exported` 增量>0、≥1 帧四 CRC+zlib；v6 地址低3位=0、同拍计数=0。
- **仍缺 R**：保留 v6 失败 AR 证据（`last_issued_ar_addr`、`timeout_ar_addr/low3`、同拍/在途、`ar/r/rlast/stale` 差分），判 `PAXI_NATIVE_STILL_UNRESOLVED`，**不第二次下载**。

## 5. 预算

开发 **150 min / 70 calls**；TD **3 会话**、综合 ≤3、布线 ≤2、bitgen 1、CWC 1、下载 1、Flash 0；综合测试 45 min / 30 calls。禁止批量删除。

## 6. 未决 / 已挂起

1. 若 WNS 落在 +0.003..+0.05，按 b13 口径接受为诊断候选并记录 caveat；不删 v6 字段、不放宽 SDC。
2. `ALLOW_CONCURRENT=1` 的单命令 vs 并发吞吐对照**不在本包**；本包 bitgen/板级固定 0。
3. 若板级仍缺 R，下一包才进入 DDR MC/IP 读响应侧调查；本包不猜、不换 bit、不二次下载。
4. `workflow/tasks.json` 本冻结未改；父 T10 仍 blocked/not done。
5. FTDI/板卡是外部条件：不在位即 `board=blocked`，不是 FAIL，也不问用户。

## 7. 下一次准确启动/恢复文本

> 恢复 `20261020-0209_singleA_aplus_closedloop` 的 **`T10.b17-paxi-native` r0**（ready；1 bitgen+1 CWC；SRAM 下载 ≤1）。
> 先读 `T10.b17-paxi-native/{dev-plan.md,fpga-design-guide.md,handoff.md,dispatch.json}`、审计文档 `docs/OpenCode_b15根因审计与定位建议_2026-10-26.md`、b15 `T10.b15-ddr-pace/r0/changed-src/**`、b15 `r0/td/**`、b15 `r0/sim/**`、b15 `r0/board/**`。
> 目标：只在 bridge 的唯一 PAXI 边界做 `{word_index[23:0],3'b000}`（AW/AR），`paxi_wstrb=0`，AW/W 与 AR 单命令互斥（`ALLOW_CONCURRENT=0`），保留 b15 严格单笔读/超时/重试；v6 273 B/67 字段加失败 AR 证据；模型真实执行低3位/越界/mask/单命令；先 16 字写-停-读回，再整帧/两帧/丢 R/P1 三黄金；重建 Routed 0 违例、WNS 按 §6、1 bitgen+1 CWC；先下载后 COM8 150 s，timeout/retry/giveup 归零、enc/exported 增量>0、≥1 帧四 CRC+zlib；仍缺 R 则留 v6 证据停止，不第二次下载。
> 150 min/70 calls；TD 3 会话/综≤3/布≤2/bitgen 1/CWC 1/下载 1；失败即停，不自扩预算，不批删。
