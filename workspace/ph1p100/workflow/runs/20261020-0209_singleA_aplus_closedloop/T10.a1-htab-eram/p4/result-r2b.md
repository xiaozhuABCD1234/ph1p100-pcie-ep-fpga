# T10.a1-htab-eram r2-b — stage-1 hent_pos 边界比较在综合中反而变差（-0.548），用尽最后 1 次综合 → blocked（无布线、无 r3）

- task_id `T10.a1-htab-eram` | round **r2** / revision **r2-b**（r2 s1 的范围微调）
- 日期 2026-10-22 | 离线 synthetic；使用 r2 剩余 **1 次综合 + 1 次会话**；布线 0/1、bitgen 0、无 .bit/CWC/下载/Flash
- 基准：r2 候选 `0b084317…5396`（WNS -0.017）；frame `18d51b1b…1cbe`、SDC `227dd39e…6311` 未改
- 冻结尝试候选：`47b131fcadf091896788ad47a0983bd7bb8064ad40c0ecfa7df61dcdc67a3fa3`
- **唯一判定：blocked。** 授权改写已完成且功能逐位不变，但综合 WNS **-0.548**（比 r2 的 -0.017 更差）；r2 的 2/2 综合已用尽，不布线、不自动 r3。**最佳候选仍是 r2 `0b084317`（-0.017）**。

## 1. 本轮改动（只动 htab stage-1 hent_pos 比较）

原：
```
wire [12:0] s1_hdist = s1_pos_r - hent_pos;
wire        s1_rng = (s1_hdist <= MAX_DIST) && (hent_pos < s1_pos_r);
```
改为等价形式（s1_hdist 保留给 hd_r/cand_pos）：
```
wire [12:0] s1_lo = (s1_pos_r > MAX_DIST) ? (s1_pos_r - MAX_DIST) : 13'd0;
wire        s1_rng = (hent_pos < s1_pos_r) && (hent_pos >= s1_lo);
```
等价性：`0 < s1_pos_r - hent_pos <= 2048` ⟺ `hent_pos < s1_pos_r` 且 `hent_pos >= max(s1_pos_r-2048,0)`（13 位无符号，饱和下界）。r2 flag 修复、thresh_lit8/9、htab/bm 存储、协议/帧/SDC 全部冻结。

## 2. 功能等价（全绿，逐位不变）

| 项 | 结果 | 证据 |
|---|---|---|
| P2 | **13/13 PASS**、0 mismatch、`vlog 0/0`、bp/gapbp/abort/reset 全过 | `r2-b/p2/result.json`、`r2-b/p2/logs/vlog.log` |
| P2 等价 | **13/13 stream_sha256、stream_len、run_cycles 与 r2 完全相同** | 逐例比较 |
| P2 comp | **355,261 cycles / 81.067 MB/s**（红线 370,370） | `r2-b/p2/result.json` |
| P3 | **20/20 PASS**、`failures=[]`、0 mismatch、0 X、`vlog 0/0` | `r2-b/p3/result.json`、`r2-b/p3/logs/vlog.log` |
| 1080p | 4,677,945 / 4,866,587 / 4,744,596 / 4,678,533，**与 r2/r1/r0 逐周期相同** | 同上 |
| stored | `worst_stored_bytes` 与 r2 相同（1080p 2,594,706），未增大 | 同上 |

## 3. G2 综合（r2 最后一次综合，2/2 用尽）

| 项 | 目标 | 实测（`47b131fc`） | 结论 |
|---|---|---|---|
| SWNS | ≥0（目标 +0.3） | **-0.548 ns** | **FAIL** |
| STNS | ≥0 | -0.548 ns | FAIL |
| 违例端点 | 0 | **1/4640** | FAIL |
| slice | ≤71,680 | 3061 | PASS |
| ERAM | 26 与实例相符 | 26（core 22） | PASS |
| reg / DRAM LUT | — | 1626 / 32 | — |

**最差路径**：`htab_tag ERAM clk2q (1.515) → hent_pos → lt34 13 位 ADDER（新上界比较被综合成减法器）→ s1_rng → hrg_r_reg.d` = **5.817 ns**（cell 3.724 / net 2.093），6 级（LUT4×3、ADDER×2、LUT3）。
- 与 r2 s1 的 5.286 ns 相比：`hent_pos >= s1_lo` 被 TD 降成 13 位减法器（`lt34`），hent_pos 仍在进位链里；同时新增两个 13 位比较的 AND 和 hrg 逻辑（3 个 LUT4 级），所以反而更差。
- 结论：**“直接比较边界”没有把 hent_pos 移出 carry chain**；该改写被综合否决。

## 4. PRJ-8806（再次出现，已按 r2 规范保留）

- r2-b s1 综合父 tcl 再次报 `PRJ-8806 ERROR: Run syn_1 has exited unexpectedly`；r2-b tcl 已把 `wait_run` 包在 catch，打印 `SYN_WAIT_ERR`（空消息）后继续复制/解析 gate 报告并执行 WNS 门控。
- raw 证据：`r2-b/td/a1_ht_r2b_Runs/syn_1/`
  - `run.log` `73afe6de…db1c`、`flow.status` `25ddec31…30ac`、`a1_ht_r2b_gate.timing` `fc21da90…8f19`、`a1_ht_r2b_gate.area` `46ebbb2a…a54c`、`a1_ht_r2b_gate.db` `4259d8e0…d7c9`。
  - 复制件 `syn_gate_timing_s1.rpt` / `syn_gate_area_s1.rpt` / `syn_flow_status_s1.rpt` / `syn_run_s1.log` 与 raw 文件 SHA256 相同。
- 该异常不改变综合结果的完整性：run.log/flow.status 显示 opt_gate 已完成（约 40 s），gate.timing/area/db 均已导出。

## 5. 预算与停止依据

| 项 | 用/上限 |
|---|---|
| r2-b 会话 | **1/1 剩余**（45 min 上限内） |
| 综合 | **1/1 剩余**（r2 合计 **2/2**） |
| 布线 | **0/1**（WNS<0 不布线） |
| bitgen / .bit / 下载 / Flash | 0 / 0 / 0 / 0 |
| 开发 | 约 20 min / 10 calls（低于 30 min / 20 calls） |

停止依据：dispatch `Synth WNS <0 -> do not route; no further synth in r2`、`remaining 1 synth / 1 route exhausted -> stop; no r3`。本轮综合已用尽，**不启动布线、不做第 3 次综合、不 seed/QoR/降频/SDC 变更**。

## 6. 结论与建议

- **r2-b 不是更好的候选**：功能全同但 WNS -0.548，劣于 r2 的 -0.017。建议把工作树回退到 **r2 `0b084317`**（当前最佳：1 个端点、WNS -0.017、TNS -0.017、ERAM 26、slice 3068）。
- 若未来（新的用户/规划授权）还要继续，需要换一种真正能把 hent_pos 移出进位链的机制（例如寄存 hent_pos 一级并重新验证 3 级 hit 流水，或完全不同的 stage-1 range 表达），而不是把 `>=` 交给综合成减法器；且需要新的综合/布线预算，禁止 seed sweep 或放宽 187.5 MHz。
- 本轮无 routed 证据，G2 不能 PASS；按规则 blocked，无 r3。

## 7. 回退

- **收口后工作树 = `0b084317`（r2 最佳候选）**：r2-b 的 `47b131fc` 作为被综合否决的尝试候选保存在 `r2-b/candidate-47b131fc.a1_deflate_core.v`，不留在工作树。
- 回最佳 r2：把 `r2/candidate-0b084317.a1_deflate_core.v` 覆盖上游 core（SHA `0b084317…5396`）；回 r1/r0 同理使用各自 candidate。frame/SDC 未改。
- 只回退本轮：按 `r2-b/candidate.diff` 反向（47b131fc → 0b084317）。

## 8. 复现

```powershell
# 仿真（P:=项目根，W:=包 r2-b）
powershell -NoProfile -ExecutionPolicy Bypass -File upstream\ph1p100-pcie-ep-fpga\tools\codec\run_p2_htab_eram_r2b.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File upstream\ph1p100-pcie-ep-fpga\tools\codec\run_p3_htab_eram_r2b.ps1
# TD（T:=包 r2-b\td，Y:=项目根；先 tools\td\td_env.ps1）
powershell -NoProfile -ExecutionPolicy Bypass -File tools\td\td_env.ps1 -Force -TdDir "workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.a1-htab-eram\r2-b\td"
cd T:\; $env:A1_TD_TAG="s1"; D:\anlogic\TD_Release_2026.2\bin\td_commands_prompt.exe T:/00_syn_then_route.tcl
```
