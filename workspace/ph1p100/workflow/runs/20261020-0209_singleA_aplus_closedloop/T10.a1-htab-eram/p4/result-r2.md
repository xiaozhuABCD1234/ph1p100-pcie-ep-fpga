# T10.a1-htab-eram r2 — S_EXT flag 修复成功（违例端点 3→1、TNS -0.465→-0.017），但 WNS -0.017 仍 <0 → blocked（未布线）

- task_id `T10.a1-htab-eram` | round **r2**（r1 的收口轮，同一包）
- 日期 2026-10-22 | 离线 synthetic；TD 2 次调用（1 次在 BOM 处立即中止、1 次完成综合）、综合 **1/2**、布线 **0/1**、bitgen 0、无 .bit/CWC/下载/Flash
- 基准/复用候选：`3326a1fa…e532`（r1）；frame `18d51b1b…1cbe`、SDC `227dd39e…6311` 未改
- 冻结候选：`0b084317db0608a56865a77fd18e7312add3ddb87c2a465a48f60816d8545396`
- **唯一判定：blocked。** 授权的 flag 修复完成，违例端点 3→1、TNS -0.465→-0.017；但 WNS **-0.017** 仍低于 **0** 的布线门槛，剩余唯一端点是 r2 范围外的 htab stage-1 距离路径。

## 1. 本轮改动（只动 S_EXT flag 更新）

r1 的最差路径是 `bm_b ERAM clk2q → S_EXT byte compare → ext_zero_r_reg.d`（5.514 ns）：`ext_zero_r/len_cap_r` 只在“字节匹配且继续扩展”的 else 分支里更新，使能依赖 bm_b_rd。

改法（`0b084317`）：
- 把
  `ext_zero_r <= (ext_rem == 13'd1);`
  `len_cap_r  <= (len_r == 9'd256);`
  从 else 分支移到 `S_EXT` 开头，**每个 S_EXT 周期无条件更新**。
- 语义证明：两个 flag 在每次 hit 时重装（`ext_zero_r <= (ext_rem_new==0); len_cap_r<=0`）；离开 S_EXT 后是 don't-care，直到下一次 hit 重装。S_EXT 内继续扩展时 ext_rem/len_r 各减 1/加 1，`(ext_rem(k)==1)` 正是下一拍的 `(ext_rem(k+1)==0)`，`(len_r(k)==256)` 正是下一拍的 `(len_r(k+1)==257)`；停止/失配分支离开 S_EXT 后 flag 值无关。因此功能逐位不变，且 bm_b_rd 不再进入 flag 的 D/使能路径。
- 其他全部冻结：`thresh_lit8/9`、htab/bm 存储、stage-1/协议/端口/帧/CRC/长度/abort/Bayer/SDC 均未改。

## 2. 功能等价（全绿，且与 r1/r0 逐位一致）

| 项 | 结果 | 证据 |
|---|---|---|
| P2 | **13/13 PASS**、0 mismatch、`vlog 0/0`、bp/gapbp/abort/reset 全过 | `r2/p2/result.json`、`r2/p2/logs/vlog.log` |
| P2 等价 | **13/13 stream_sha256、stream_len、run_cycles 与 r1 完全相同** | 逐例比较 |
| P2 comp | **355,261 cycles / 81.067 MB/s**（红线 370,370） | `r2/p2/result.json` |
| P3 | **20/20 PASS**、`failures=[]`、0 mismatch、0 X、`vlog 0/0` | `r2/p3/result.json`、`r2/p3/logs/vlog.log` |
| 1080p | 4,677,945 / 4,866,587 / 4,744,596 / 4,678,533，**与 r1/r0 逐周期相同**（门槛 6.25M） | `r2/p3/result.json` |
| stored | 各例 `worst_stored_bytes` 与 r1/r0 相同（1080p 2,594,706），未增大 | 同上 |

## 3. G2 综合（1/2 次，WNS <0 停止）

| tag | 候选 | SWNS | STNS | 违例端点 | slice | ERAM | core ERAM | reg | DRAM LUT | 最差路径 |
|---|---|---|---|---|---|---|---|---|---|---|
| s1 | `0b084317` | **-0.017** | -0.017 | **1/4640** | 3068 | **26** | 22 | 1626 | 32 | `htab_tag ERAM clk2q (1.515) → hent_pos → 13 位减法器 (lt33/s1_hdist) → s1_rng → hrg_r_reg.d` = 5.286 ns（cell 3.535 / net 1.751）/ 5 级 |

- 与 r1 对比：最差端点 3→1、TNS -0.465→-0.017、WNS -0.245→-0.017；flag 路径（bm_b→ext_zero_r）已从关键路径消失。
- 门槛：WNS ≥ **0**（目标 +0.3）、TNS≥0、slice ≤71,680、ERAM 26。实测 **WNS -0.017 <0** → **不布线**。
- 剩余唯一端点属于 **r0 htab ERAM 的 stage-1 距离判断**（`s1_hdist = s1_pos_r - hent_pos; (s1_hdist<=2048) && (hent_pos<s1_pos_r)`），不是 r2 授权的 flag 更新范围；按 stop condition 停。

## 4. PRJ-8806 记录（供独立核验）

- r1 s2 的 PRJ-8806 原始文件保存在 `r1/td/a1_ht_r1_Runs/syn_1/`，SHA256：
  - `run.log` `cbd34868…0339`、`flow.status` `24f79751…9782`、`a1_ht_r1_gate.timing` `c0e40dab…3860`、`a1_ht_r1_gate.area` `fd5d9fff…be9`、`a1_ht_r1_gate.db` `101e5829…aa51`。
  - 复制件 `r1/td/syn_gate_timing_s2.rpt`、`syn_gate_area_s2.rpt`、`syn_flow_status_s2.rpt` 的 SHA256 与 raw 文件逐一相同。
- r2 s1 综合**正常完成**（`PRJ-1406 Run syn_1 finished`，无 PRJ-8806）；r2 tcl 仍把 `wait_run` 包在 catch 中，若再报 PRJ-8806 会继续解析已有 gate 报告。
- 本轮另有 TD 调用异常：首次调用的 tcl 被 PowerShell 写成 UTF-8 BOM，TD 报 `invalid command name` 并在任何 TD 命令前退出；去掉 BOM 后第二次调用正常。该次未消耗综合/布线。

## 5. 预算与停止依据

| 项 | 用/上限 |
|---|---|
| TD 调用 | 2 次（1 次 BOM 中止、1 次综合会话）；综合 **1/2**、布线 **0/1** |
| bitgen / .bit / 下载 / Flash | 0 / 0 / 0 / 0 |
| 开发 | 约 25 min / 12 calls（低于 60 min / 40 calls） |

停止依据：dispatch `Synth WNS <0 or TNS<0 -> do not route`、`Any needed change outside S_EXT ext_zero_r/len_cap_r flags -> stop and return to planner`。剩余 17 ps 在 htab stage-1 距离路径上，属于范围外；不启动第二次综合、不做 QoR/seed/频率/SDC 变更。

## 6. 最小下一步（交规划）

- 只差 **1 个端点 / 17 ps**。唯一有证据的方向：把 stage-1 距离判断从 `s1_pos_r - hent_pos` 的 13 位减法器里解放出来。等价改写示例：
  - 预计算 `s1_pos_r` 与 `s1_pos_r - 2048`（饱和）两个边界，比较 `hent_pos < s1_pos_r && hent_pos >= s1_pos_r-2048`；减法从寄存器并行出发，`hent_pos` 只进比较树。
  - 或把 `hent_pos` 在 htab 读出后先打一拍到 fabric（htab 数据已是 ERAM 输出，再加一级会改变 stage-1 时序，需按功能等价重测）。
- 该改动在 r2 授权范围外，需规划/用户明确；综合/布线预算剩余 1 次综合（本轮 1/2）、1 次布线，但按 dispatch 本轮不再自动续做。
- 保持本轮 flag 修复与 `thresh_lit8/9` 不变；功能回归必须仍是 33/33 逐位相同 + 吞吐门槛。

## 7. 回退

- 工作树 = `0b084317`。回 r1：把 `r1/candidate-3326a1fa.a1_deflate_core.v` 覆盖上游 core；回 r0：`r0/candidate-b374f6fc…v`；回基准：`r0/base-1dca732b…v`。frame/SDC 未改。
- 只回退本轮：按 `r2/candidate.diff` 反向（0b084317 → 3326a1fa）。

## 8. 复现

```powershell
# 仿真（P:=项目根，W:=包 r2）
powershell -NoProfile -ExecutionPolicy Bypass -File upstream\ph1p100-pcie-ep-fpga\tools\codec\run_p2_htab_eram_r2.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File upstream\ph1p100-pcie-ep-fpga\tools\codec\run_p3_htab_eram_r2.ps1
# TD（T:=包 r2\td，Y:=项目根；先 tools\td\td_env.ps1）
powershell -NoProfile -ExecutionPolicy Bypass -File tools\td\td_env.ps1 -Force -TdDir "workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.a1-htab-eram\r2\td"
cd T:\; $env:A1_TD_TAG="s1"; D:\anlogic\TD_Release_2026.2\bin\td_commands_prompt.exe T:/00_syn_then_route.tcl
```
