# b6 最终摘要（2026-10-24）

**T10.b6-a1-htab-nw r0 = PASS（带 caveat）。吞吐回归关闭；T10 父任务仍 blocked。**

## 完成
- 目标：去掉 r5 “每 match +1 拍”的等待，恢复 355,261 cycles / 81.067 MB/s，字节不变。
- 结果：comp 355,261（SHA `2601d57c…a7c05`）、rand 161,479（SHA `54f262f2…496dd`）、P1 三例逐字节；负对照 374,461 可区分。
- 工程：Routed 0/19,779、SWNS +0.119、STNS 0、hold +0.020、Period +2.200、ERAM 102/300；`htab_p3v→bm_b.addrb` 端点组消失。
- 候选：bit `a2757d40…ffa2`、cwc `dc477c8f…dc57`、bid `2bf011c5…d730`；compiled==parent；1 bitgen + 1 CWC；0 下载/0 Flash。
- 唯一 RTL 变更：`r0/changed-src/a1_deflate_core.v`（`6797db05…35bb`）。

## 未完成 / 不在本包
- G4 板级 not_run；本 PASS 不证明上板、相机链路、P3 或整机行为。
- 需求二（真实 RAW 与参数校准）、需求三（板级端到端）仍未完成。
- 板级诊断（b5 r1-diag）8 计数器全 0、`cap_frames=0`：故障在相机前端，已另立 `T10.b7-cam-diag`。

## 回退
- 若需严格照指南 §4.1 重做：保留本包证据，另开新包替换 `changed-src`；**不得**回退到 r5 当 PASS（r5 吞吐 FAIL）。

## 恢复入口
- 本包：`workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b6-a1-htab-nw/`
- 下一包：`workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b7-cam-diag/dispatch.json`
- 全局任务板：`workflow/tasks.json`（T10 条目）

---

# T10.b6-a1-htab-nw 规划收尾（final-summary）

日期：2026-10-24。结论：**计划与派发已冻结；本轮规划阶段结束，尚无开发候选、尚无 PASS、无 manifest/bit/CWC。** 状态 `ready`，`needs_user_input=false`。

## 1. 为什么开这个包

用户确认的并行仿真结论：

- r5 压缩数据正确，但 P2 comp 为 **374,461 cycles / 76.910546 MB/s**，比 r4 的 355,261 / 81.067159 MB/s 多 **19,200 拍**，正好等于 19,200 个 match 的 1 拍/match；低于 77.76 MB/s 门槛。
- 根因：r5 为闭合 `htab_p3v_q[12:0] → htab_q[49:37] → bm_raddr_b → bm_b.addrb`，把 bm_b 候选地址寄存为 `bm_b_spec_q`，导致 hit 拍拿不到 `bm[ref+3]`，S_EXT 增加 `ext_first` 等待拍。
- P1 三例逐字节一致，但匹配密度低/喂数间隔掩盖了吞吐损失；旧整帧回归只有 +24 拍，不能代表无间隙编码核服务率。
- 其他仿真（奇数尾块 8×3、随机 stored 回退、双路配对 11 项、负对照）均通过；这些不是吞吐回归的证明。

## 2. 本包决策

- 任务 ID：**T10.b6-a1-htab-nw**，新包 r0；不把 b5 r0 追认为 PASS，也不以“续 b5 r2”模糊新结构。b5 r0 保留为历史 FAIL/薄余量候选。
- 唯一 RTL 变更：`a1_deflate_core.v` 的 htab/bm_b 读地址结构。允许提前一拍的 p3v 影子读和一级 `bm_a_rd3` 预取；保留 r5 的 `bm_b_spec_q`/flop-only `bm_raddr_b`；恢复 r4 的 hit 拍首字节比较，删除 `ext_first` 等待。
- 不改协议/帧/CRC/DDR/SDC/UART 状态包；不下载、不 Flash。
- 相机 `cap_frames=0` 是独立问题，本轮不混入。

## 3. 冻结验收

| 项 | 门槛 |
|---|---|
| P2 comp | **355,261 cycles**；50,310 B；流 SHA `2601d57c…a7c05`；zlib/strict 0 差异 |
| P2 rand | 流 SHA `54f262f2…496dd`；cycles ≤161,479 |
| P1 | 三例逐字节：63 B `fa513a2b…`、150 B `ee61e620…`、40,076 B `b992a8ad…`；cycles ≤ r4 3,809/5,172/6,421,414 |
| 边界 | 奇数 8×3、随机 stored 64×8 core 相关项通过；双路 RTL 未改，复用并注明 |
| 工程 | Routed 0 违例；WNS ≥ +0.05 ns、TNS=0、hold ≥0、period 0、无组合环/无时钟网；资源在器件内；记录 caveat |
| 候选 | 1 bitgen + 1 CWC；bit/CWC/BID SHA 记录；`compiled.bit/cwc` 一致 |
| 系统 | 仅接口/协议不变 + 板级 not_run；**本轮 0 下载** |

## 4. 预算

- 开发 90 min / 50 calls。
- TD 3 sessions / 150 min；综合 ≤3；布线 ≤2；bitgen 1；CWC 1；下载 0。
- 综合测试 45 min / 30 calls；不重跑 TD、不下载。

## 5. 实际完成/未完成

已完成（规划）：
- 读 r5/b5 结果、TD 模板、P2 向量与 P1 金标，确认根因与可用证据。
- 冻结 `dev-plan.md`、`fpga-design-guide.md`、`handoff.md`、`dispatch.json`、本收尾与 `user-summary.md`。
- 更新 T10 任务板为 active（b6 唯一活动包；P3/板级仍独立）。

未完成（需后续角色）：
- RTL 实现、P2/P1 实测、TD syn/route、bitgen/CWC、独立综合测试。
- 板级下载/采集/真实吞吐：本轮明确不做；相机前端 `cap_frames=0` 另案。
- 无候选 manifest、无 bit/CWC、无 PASS 声明。

## 6. 剩余主题（最多 3 条）

1. b6 开发与综合测试（本 dispatch）。
2. 若 b6 仍不能闭合，下一独立主题只能是更深的结构性重排或器件/QoR 授权，需用户明确批准；不在本包自动续做。
3. 相机前端 `cap_frames=0`、真实曝光同步、板级吞吐/稳定性：独立问题，需另立任务和硬件窗口。

## 7. 下一次准确启动文本

```text
$fpga-orchestrator 执行：按 D:\fpga\ph1p100\workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.b6-a1-htab-nw\dispatch.json 派发 T10.b6-a1-htab-nw 开发；目标 P2 comp 355,261 cycles、P1 三例逐字节、Routed 0 违例 WNS≥+0.05、1 bitgen+1 CWC、不下载。
```

恢复入口：`D:\fpga\ph1p100\workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.b6-a1-htab-nw\handoff.md`。
