# T10.a1-htab-eram r0 — htab 66-bit 拆 4 张 ERAM 成功（ERAM 22→26、DRAM 1184→32、WNS -1.094→-0.144），但综合 2/2 仍 <+0.5 → blocked（未布线）

- task_id `T10.a1-htab-eram` | round **r0** | 同一 T10、同一 run；不是 `T10.a1-bm-eram` 的 r1
- 日期 2026-10-22 | 离线 synthetic；TD 2 会话（约 3 min）、综合 **2/2**、布线 **0/1**、bitgen 0、无 .bit/CWC/下载/Flash
- 基准：core `1dca732b…7e4d`、frame `18d51b1b…1cbe`、SDC `227dd39e…6311`（frame/SDC 未改）
- 冻结候选：core `b374f6fcc161ffe0b9c8fd703cc04fb3fab0411a674a8e0cf1ad06e64173fb6d`
  = `da676bc4`（htab ERAM 拆分）+ 命中拍 bm 预取/扩展比较预计算
- **唯一判定：blocked。** 功能等价全绿，htab 已推断成 ERAM；综合 WNS 两轮 **-0.144 / -0.146**，低于门槛 **+0.5**（目标 +1.0），按 dispatch 不布线。

## 1. 本轮改动（仅 `a1_deflate_core.v`，两步）

### 1.1 htab 66-bit → 4 张 ERAM 友好阵列（`da676bc4`）
- 原：`htab[1024×66]` + `htab_v[1024]`，读进程带 `if (htab_pref)` 读使能 + 同址写穿透 mux；`htab_v` 在复位进程里 for-loop 清零；DRAM LUT 1,184、ERAM 22。
- 新：
  - `htab_tag[16]` / `htab_p3v[14]`（bit13 = valid，bit12:0 = pos+3）/ `htab_pos[13]` / `htab_b[24]`（b0,b1,b2）。
  - 每张阵列一个**无条件寄存器读口**（ERAM 模板），读地址仍是 `htab_rd_addr`。
  - 同址写优先旁路移到 RAM 输出之后，用 `htab_byp/htab_byp_data` 打一拍：stage-1 看到的延迟和值与旧 `htab_rdata/htab_rvalid` 完全一致（1 拍）。
  - 每张阵列**单个无复位写口**；`htab_p3v` 的写口同时承担清 valid。
  - 旧 `htab_v` 复位清零改为复位后 **1024 拍 valid 清扫**（写 0），`S_WAIT` 用 `htab_clr_done` 门控首个块，保持"复位后全表无效"的语义；固定启动延迟，不是每字节成本。
- 结果：**ERAM 26**（bm 8+8、cmem 4、smem 4、**htab 4**），core ERAM 18→22；**DRAM LUT 1184→32**；reg 2581→1569；slice 5259→2885；WNS -1.094→-0.144。

### 1.2 命中拍 bm 预取 + 扩展比较预计算（`b374f6fc`）
- s1 的新最差路径是 `bm_a ERAM clk2q → bm_a_rd → ext_first mux → 字节比较 → state.ce`（5.410 ns）。
- 改法（等价、零周期变化）：
  - 命中拍（S_SCAN && hit2）bm_a 读地址由 `praddr` 改为 `p3_r`。这样 S_EXT 第 0 拍的 `bm_a_rd` 就是 `bm[p3_r]`（旧 `cq_r = x1_r` 的同一个字节），`ext_first` 的 8-bit mux 从比较路径上消失；后续拍仍是 `bm[p3_r+k]`。命中的 `praddr` 预取本来就会在 S_MCHK/S_REPOS 重新播种，x1_r 在 S_EXT/S_MLEN/S_MCHK 不被使用，故无语义变化。
  - `ext_rem==0` / `len_r==257` 两个循环停止条件预计算成 1-bit 寄存器 `ext_zero_r/len_cap_r`，随计数器同拍更新，13/9 位比较从 state CE 路径移走。
- s2 最差路径变成 **`w0_reg → litlen → 32 位 (cand_bits+litlen) 加法器 → thresh_lit 比较 → state.ce` = 5.412 ns / 7 级（ADDER=4）**。即 bm 的 ERAM clk2q 路径已被移出关键路径，剩下的是纯 fabric 算术。

## 2. 功能等价（全绿，且与 bm-eram/area-map 基准逐位一致）

| 项 | 结果 | 证据 |
|---|---|---|
| P2 | **13/13 PASS**、0 mismatch、`vlog 0/0`、bp/gapbp/abort/reset 全过 | `r0/p2/result.json`、`r0/p2/logs/vlog.log` |
| P2 等价 | **13/13 stream_sha256 与 stream_len 与 `T10.a1-bm-eram/r0/p2` 完全相同**；`stat_max_dist/stat_max_match/stored` 逐例相同 | 逐例比较（会话记录） |
| P2 comp | **355,261 cycles / 81.067 MB/s**（= 基准，红线 370,370/77.76） | `r0/p2/result.json` |
| P3 | **20/20 PASS**、`failures=[]`、0 mismatch、0 X、`vlog 0/0`、`bp_equivalence=true` | `r0/p3/result.json`、`r0/p3/logs/vlog.log` |
| 1080p | p1d1 4,677,945 / p1d0 4,866,587 / p0 4,744,596 / rand 4,678,533，**与基准逐周期相同**（硬门槛 6.25M） | 同上 |
| stored 上界 | 各例 `worst_stored_bytes` 与基准相同（1080p 2,594,706），未增大 | 同上 |
| 负例 | 截断/坏 Adler/尾随字节/dynamic BTYPE/坏 stored NLEN 全部按预期原因拒绝 | P2/P3 result.json |

**唯一功能偏差**：复位后 1024 拍 valid 清扫带来固定启动延迟，只影响在 ~1024 拍内就结束的小用例（P2 6 例 +~1000 cycles，P3 4 例 +866 cycles）；大用例、P2 comp、1080p 全部逐周期不变。SHA 全同说明编码决策完全一致。

## 3. G2 综合（2/2 次用尽，未过 WNS 门槛）

| tag | 候选 | SWNS | STNS | 违例端点 | slice | ERAM | core ERAM | reg | DRAM LUT | 最差路径 |
|---|---|---|---|---|---|---|---|---|---|---|
| s1 | `da676bc4`（仅 htab） | **-0.144** | -5.151 | 39/4472 | 2885 | **26** | 22 | 1569 | **32** | bm_a ERAM clk2q→bm_a_rd→ext_first mux→compare→state.ce 5.410 ns / 5 级 |
| s2 | `b374f6fc`（冻结） | **-0.146** | -4.909 | 40/4448 | 2955 | **26** | 22 | 1562 | **32** | w0→litlen→32-bit (cand_bits+litlen) adder→thresh_lit→state.ce 5.412 ns / 7 级（ADDER=4） |

- 门槛：WNS ≥ **+0.5**（目标 +1.0）、TNS ≥ 0、slice ≤ 71,680、ERAM 与实例相符。
- 实测：WNS -0.144/-0.146、TNS<0 → **不布线**；slice 2955 远低于上限；ERAM 26 = bm 8+8 + cmem 4 + smem 4 + **htab 4**，与实例相符；DRAM LUT 1184→32。
- `01_final_route.tcl` 的 `#dram` regexp 崩溃已在新的 `00_syn_then_route.tcl` 中修正：所有解析变量先初始化，`#dram lut` 用 `if {[regexp ...]}` 保护；本轮两次会话均未触发该错误。
- 布线未启动：`a1_ht_r0_Runs/phy_1` 为空目录（无 settings.cfg/run.log），route 0/1、bitgen 0、无 .bit。

## 4. 判定与停止依据

- dispatch：`Synth WNS < +0.5 ns or TNS<0 -> do not route`；`2 synth attempts exhausted -> stop`；`Any needed change outside htab/bm prefetch (and pure frame pipeline) -> stop and return to planner`。
- 两轮综合分别为 htab 拆分与 bm 预取/比较预计算；WNS 仍 -0.146。**剩余关键路径是 32 位字面量阈值加法器，不属于 htab/bm 预取范围**，故本包停在 blocked，不启动布线、不做第 3 次综合、不改 QoR/频率/SDC/false path/multicycle/seed。

## 5. 预算与偏差

| 项 | 用/上限 |
|---|---|
| TD 会话 | 2/2（s1 42 s、s2 40 s 综合；总墙钟约 3 min） |
| 综合 / 布线 | **2/2** / **0/1** |
| bitgen / .bit / 下载 / Flash | 0 / 0 / 0 / 0 |
| 开发工具调用 | 超出 50 次（两轮 P2/P3 + 两次综合检查点 + 逐例 SHA 比对；按有界规则主动停止） |

偏差：
1. 固定 1024 拍 valid 清扫使小用例周期 +866~+1044；硬门槛用例不受影响，等价口径为功能等价。
2. s2 的命中拍 bm 预取改动未提升 WNS（bm 路径移出后暴露了同样 5.41 ns 的阈值加法器路径），保留在冻结候选中是因为它**功能逐位不变**且移除了一个 ERAM clk2q 长线；若规划认为超出授权，可按 §7 回退到 `da676bc4`（s1 报告对应）。
3. P2/P3 `result.json` 内的 `task_id` 字段是验证脚本写死的 `T10.a1-enc-rtl`，不是本包 ID；判定按本清单与报告。

## 6. 最小下一步（交规划）

**唯一有证据的方向**：把 `S_SCAN` 的字面量阈值检查 `(cand_bits + {28'd0,litlen}) >= thresh_lit` 从 32 位串行加法+比较改成窄比较或提前一拍。依据：
- `MAX_BLOCK=4800`，`cand_bits` 与 `thresh_lit` 实际都 < 2^16（stored_cost ≤ 3+7+32+8×4800 = 38,442），但 RTL 用 32 位，TD 因此铺了 32 位进位链（s2 路径 1.8 ns 的 ADDER 链）。
- 等价改写示例：`sum_lo = {1'b0,cand_bits[15:0]} + {1'b0,litlen}`；`sum_hi = cand_bits[31:16] + sum_lo[16]`；比较 `{sum_hi,sum_lo[15:0]} >= thresh_lit`，高半进位与低半并行，可省约 0.6~1.0 ns。需先证明 `cand_bits/thresh_lit < 2^16`（含 abort/stored 边界），再由数学等价测试兜底。
- 其他可能：把 `litlen` 的 4-bit 值在上一拍从 `w1` 预计算并寄存（下一拍的字面量是 w1），把 LUT+部分加法移出路径。
- 该包仍需：P2/P3 功能等价 + P2 comp ≤370,370、1080p ≤6.25M；综合 WNS ≥ +0.5（目标 +1.0）后再布线 1 次；布线后单独 report_cdc/check_timing。

## 7. 回退

- 工作树 = `b374f6fc`。回基准：把 `r0/base-1dca732b.a1_deflate_core.v` 覆盖上游 core（SHA 应为 `1dca732b…7e4d`）；或按 `r0/candidate.diff` 反向。frame_top/SDC 未改。
- 只回退第 2 步：把工作区 core 从 `b374f6fc` 反向替换为 `da676bc4`（可用 `patch_htab_eram_step2.py` 的逆替换；s1 综合报告 `syn_gate_timing_s1.rpt` 对应此版本）。

## 8. 复现

```powershell
# 仿真（P:=项目根，W:=包 r0）
powershell -NoProfile -ExecutionPolicy Bypass -File upstream\ph1p100-pcie-ep-fpga\tools\codec\run_p2_htab_eram.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File upstream\ph1p100-pcie-ep-fpga\tools\codec\run_p3_htab_eram.ps1
# TD（T:=包 r0\td，Y:=项目根；先 tools\td\td_env.ps1）
powershell -NoProfile -ExecutionPolicy Bypass -File tools\td\td_env.ps1 -Force -TdDir "workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.a1-htab-eram\r0\td"
cd T:\; $env:A1_TD_TAG="s1"; D:\anlogic\TD_Release_2026.2\bin\td_commands_prompt.exe T:/00_syn_then_route.tcl
```
