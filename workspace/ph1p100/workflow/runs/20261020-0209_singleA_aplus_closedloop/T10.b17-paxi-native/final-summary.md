# T10.b17-paxi-native — final-summary（规划冻结阶段，2026-10-26）

> 本文件是**规划冻结的最终摘要**，不是开发/测试/板级执行结果。实际 PASS/FAIL 以 `r0/result-r0.md`、综合测试报告和 `CANDIDATE-MANIFEST-b17-paxi-native-r0.json` 为准。

## 1. 本轮结论

- 已冻结唯一工作包 `T10.b17-paxi-native`（1 个主要目标、1 个正式包、5 个语义步骤），状态 **ready**，`needs_user_input=false`。
- 方向：**停止在 b15 的“读重试/AR 归属”上继续加变量，回到原生 PAXI 边界合同**。
- 已冻结三项接口修正：
  1. 地址：只在 bridge 的 PAXI 输出做 `{word_index[23:0],3'b000}`（AW/AR），内部保持 256-bit 字单位；
  2. mask：`paxi_wstrb=32'h0000_0000`（mask 0 写整字），模型真实执行 mask；
  3. 命令：默认 `ALLOW_CONCURRENT=0`，AW/W 与 AR 互斥；`1` 只作后续对照。
- 已冻结 v6 状态包：273 B / 67 字段 / VER=6 / LEN 低字节 0x11 / XOR 0..271；新增 `last_issued_ar_addr`、`last_issued_ar_low3`、`timeout_ar_addr`、`timeout_ar_low3`、`same_aw_ar_cnt`、`same_w_ar_cnt`、`inflight_state`、`diag_flags`。
- 已冻结仿真矩阵：16 字写-停-读回 → 整帧 → 两帧 → 丢 1 R → P1 三黄金 → v6 结构 → 负对照（b15 旧桥必须失败、全 1 mask 必须不写、低 3 位/越界/并发必须被计数）。
- 已冻结构建/板级：Routed 0 违例、WNS 目标 ≥+0.05（薄余量按 b13 口径）、1 bitgen+1 CWC、先下载后 COM8 150 s；失败留 v6 AR 证据并停止。

## 2. 为什么是这三项

b15 板级事实：`cap_frames/raw_pub +4,500`、`crop_short=0`、`crop_geom_err=0`，但 `timeout/retry/giveup +13,500/+9,000/+4,500`（3/2/1 每帧）、`enc/exported=0`、`ar−r=13,740=尝试数`、`stale=0`。

审计已证实：

- store/bridge 发 `0,1,2`，原生参考发 `0,8,16`，链路无 ×8；
- bridge 全 1 mask，原生完整写 mask=0，现有模型忽略 mask；
- 读写命令可同拍握手，原生参考单命令仲裁；
- 五组小实验中，只有“外部加地址×8、mask=0”的对照读回 0 错。

因此本包不是“再试一次读重试”，而是修复模型一直没覆盖的接口合同。

## 3. 交付与判定（预期，不是已完成）

| 项 | 预期证据 |
|---|---|
| 16 字小图样 | 地址 0,8,…,120；16/16 数据一致；`n_bad_low3=n_oob=n_mask_nonzero=n_same_req=n_same_hs=0`；`last_issued_ar_addr=120` |
| 整帧 S1 | `ar=r=rlast=210,685`、`enc=exported=1`、四 CRC+zlib、`timeout=retry=giveup=0` |
| 两帧 S2 | `ar=r=rlast=421,370`、`exported=2`、两帧四 CRC+zlib |
| 丢 R S3 | `timeout=1 retry=1 giveup=0 exported=1`、四 CRC+zlib、晚到 R 只计 stale |
| P1 三黄金 | 压缩字节 SHA256 与 b15 caps 逐字节一致 |
| v6 | 273 B/67/VER=6/LEN=0x11/XOR；v5 兼容；坏 XOR 拒绝 |
| 构建 | Routed 0 违例、WNS 按 §6、ERAM+CWC≤300、1 bitgen+1 CWC |
| 板级 | ≥120 v6 包、`timeout/retry/giveup` 增量 0、`enc/exported` 增量>0、≥1 帧四 CRC+zlib、v6 地址低3位=0/同拍=0 |

## 4. 明确不能说的话

- 不能再说“b15 的仿真 PASS 证明接口正确”——模型已证明会漏检地址/mask/并发。
- 不能把“地址×8、mask=0”当成已经修好板级问题；**只有板级 150 s 结果**才能说这套合同在真实 MC 上通过。
- 不能把 `ALLOW_CONCURRENT=1` 的对照结果当作原生合同通过。
- 不能把 v6 的 `last_issued_ar_addr` 当成“最后一笔失败 AR”以外的证明；若仍缺 R，只说明该地址未被应答，不直接等于 MC 损坏。
- 不能声明 DDR sustained、双路、PCIe/RK、Flash、长期稳定性或生产签核。

## 5. 预算与边界

- 开发 150 min / 70 calls；TD 3 会话、综合 ≤3、布线 ≤2、bitgen 1、CWC 1、下载 1、Flash 0；综合测试 45 min / 30 calls。
- 只写 `workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b17-paxi-native/**`；b15/b13/生产/旧 manifest/`workflow/tasks.json` 不动；父 T10 仍 blocked/not done。
- 不写 Flash、不 PCIe/RK、不做双路/G4、不批量删除。

## 6. 下一步

1. 主按 `dispatch.json` 派 `fpga-dev` 执行本计划。
2. 开发冻结候选后，主另派 **1 个新的综合测试者**，按同一 manifest 覆盖 functional/engineering/system；round0 首验，同任务失败续原开发/原测试，最多 3 轮实际修复。
3. 板级若仍缺 R，保留 v6 证据并由规划决定是否另开 DDR MC/IP 调查 run。

## 7. 关键入口

- 计划：`D:/fpga/ph1p100/workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b17-paxi-native/dev-plan.md`
- 设计冻结：`.../fpga-design-guide.md`
- 派发：`.../dispatch.json`
- 交接：`.../handoff.md`
- 用户小结：`.../user-summary.md`
- 基线：`.../T10.b15-ddr-pace/r0/**`（桥 `EB9DF41F…954E3`）
- 审计：`D:/fpga/ph1p100/docs/OpenCode_b15根因审计与定位建议_2026-10-26.md`
