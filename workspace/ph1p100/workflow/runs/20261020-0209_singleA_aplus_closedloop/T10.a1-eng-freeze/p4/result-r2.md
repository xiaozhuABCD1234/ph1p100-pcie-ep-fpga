# T10.a1-eng-freeze r2 — 最终有限修复结果（G2 仍 FAIL）

- task_id: `T10.a1-eng-freeze`｜round **r2**（最终）｜run `20261020-0209_singleA_aplus_closedloop`
- 日期：2026-10-20｜性质：离线、synthetic、无上板/下载/bitgen
- 唯一判定：**blocked — G1 回归 PASS；G2 时序仍 FAIL（综合 WNS -3.792 ns，Fmax 109.589 MHz）；按 stop condition 2 在综合后停止，未布线，无第 5 次会话/r3。**
- 187.5 MHz 未放宽；无 false path/multicycle；生产构建 0、下载 0、bit/CWC 0。

## 1. 本轮改了什么

仅 `upstream/ph1p100-pcie-ep-fpga/rtl/ep_side/codec/a1_deflate_core.v`：

- 在 `S_MLEN` 与 `S_MDIST` 之间新增一级流水寄存器：
  - `dval_r` / `dtot_r`：把 `dist_r → dist_code/dist_base/dev/dval/dtot` 的组合距离编码提前寄存；
  - `pos_next_r = pos + len_r`、`rem_next_r = blk_n - pos_next_r`：把位置推进与剩余长度提前寄存；
- `S_MDIST` 改用 `dval_r/dtot_r` 发 distance code，用 `pos_next_r` 更新 `pos`、判断块尾；abort 比较改为 `cand_bits + dtot_r + (rem_next_r<<3) >= stored_bits`。
- 外部端口、帧提交/abort/CRC/长度、zlib/fixed/stored 格式、Bayer 映射、TB 均未改。
- `a1_frame_top.v` hash 未变：`3c32803b41378629622ae3a709ab64373b2fb13286bfc7ea789e7e1dbf190961`。
- 新 `a1_deflate_core.v` hash：`585664deb28c24bd08708c134347c2624d9068b2f2edca60d522ad6745d84f18`。
- r0/r1 manifest 与报告未覆盖；r2 证据在 `r2/**` 与 `p4/result-r2.md`。

## 2. G1 回归（新候选，未复用旧 PASS）

| 回归 | 结果 | 证据 |
|---|---|---|
| P2 13/13 | **PASS** | `r2/p2/result.json`（`verdict=PASS`） |
| P3 20/20 | **PASS** | `r2/p3/result.json`（`verdict=PASS`，`failures=[]`） |
| zlib 1.2.13 + 自研 strict | 0 mismatch | P2/P3 日志 |
| `vlog` Errors 0 / Warnings 0 | PASS | `r2/p2/logs/vlog.log`、`r2/p3/logs/vlog.log` |
| 1080p A/B、stored、abort/reset、2 帧 | PASS | `r2/p3/runs/**/stats.txt` |

关键帧：

| case | cycles | stream_len | blocks | commit |
|---|---:|---:|---:|---:|
| f1080p_p1d1 | 4,677,941 | 81,707 | 540 | 1 |
| f1080p_rand（全 stored） | 4,678,532 | 2,594,706 | 540 | 1 |
| multi1080p ×2 | 9,355,887 | 2×81,707 | 2×540 | 1,1 |

与 r1 完全相同（流水只作用于 match 路径，未改变块/帧级周期统计）。

## 3. G2：综合仍不收敛

TD `Release_2026.2` / build `6.2.3.210850`，`PH1P100SBG484 -3`，同一 `a1_eng_top`、187.5 MHz SDC。单会话 **461.4 s**，`exit=0`。

| 指标 | r1 | **r2** | 变化 |
|---|---:|---:|---:|
| SWNS | -3.816 ns | **-3.792 ns** | +0.024 ns |
| STNS | -680.559 ns | **-777.523 ns** | -96.964 ns |
| HWNS / HTNS | 0 / 0 | **0 / 0** | — |
| Fmax | 109.302 MHz | **109.589 MHz** | +0.287 MHz |
| LUT | 11,180 | **11,263** | +83 |
| FF | 2,064 | **2,108** | +44 |
| ERAM | 4/300 | **4/300** | 0 |
| DSP | 0/220 | **0/220** | 0 |
| Slice | 10,548 (14.72%) | **10,587 (14.77%)** | +39 |

**关键路径已换，但没有消失**：
`u_dut/u_core/pos_reg[5].clk` → `u_dut/u_core/cand_abort_reg.d`，13 级（ADDER×8 + LUT），
对应 `S_MLEN` 的 abort 预测：
`(cand_bits_n + ((blk_n - pos - len_r) << 3)) >= stored_bits`。

- 说明：r1 的 `dist_r → pos_reg[*].ce` 已被流水切断；当前瓶颈是 `S_MLEN` 的“剩余字节全 literal”预测比较，不是距离编码。
- 按 stop condition 2「综合 WNS<0 → 停止，不布线」，**未 launch phy_1**；`Routed`、routed WNS/TNS、布线后资源、bit/CWC 均 `not_run`。
- 无第 5 次 TD 会话，无 r3。

## 4. CDC

- 结构：单时钟 `clk`，同步复位；综合 STA 仅 `clk0`，`CC-From/CC-To=no`。
- TD `report_cdc`：**not_run**。脚本只在 phy 完成后调用；本轮未进入 phy。复现入口：`r2/td/00_all.tcl` 的 `report_cdc -file cdc.rpt`。
- 只声明结构化单时钟结论，不声明 TD CDC 工具 PASS。

## 5. 服务率（新候选）

| 场景 | cycles | cycles/B | MB/s @187.5 | ≥77.76 | ≥97.2 |
|---|---:|---:|---:|---|---|
| 1080p p1d1 | 4,677,941 | 1.80474 | **103.892** | PASS | PASS |
| 1080p ×2 聚合 | 9,355,887 | 1.80474 | **103.892** | PASS | PASS |
| 1080p rand（全 stored） | 4,678,532 | 1.80497 | **103.879** | PASS | PASS |

- 77.76 预算 2.4113 cycles/B；97.2 预算 1.9290 cycles/B；实测 1.8047 → 97.2 余量约 +6.9%。
- 仅 2 帧背靠背（帧间 5 cycles），无长稳/热态/随机反压跨帧；16 行小帧仍约 88.9 MB/s（r0 口径）。
- 仿真换算，不是 STA/板上；G2 未收敛前不作可上板结论。

## 6. 已知限制与下一轮最小下一步

1. 当前瓶颈：`S_MLEN` 的 abort 预测比较（`pos`/`len_r` → 减法 → 移位 → 加 `cand_bits` → 比较 → `cand_abort` 寄存器）。
2. 下一轮最小改动（本轮不再做）：新增 `S_MCHK` 状态，在 `S_MLEN` 只寄存 `pos_next/rem_next` 与 `cand_after_len`，下一 cycle 在 `S_MCHK` 计算 `proj >= stored_bits` 并决定 `S_MDIST`/`S_DECIDE`；或对 `len_r` 查表预计算 `remaining<<3`，避免 13-bit 减法链。必须重跑 P2/P3 并重新申请 TD 会话。
3. 不得降低时钟、改 SDC、加 false path/multicycle。
4. `Routed`、routed 资源/时序、CDC 工具报告、bit/CWC、板级、真实 RAW、双路 155.52：**not_run/blocked**。
5. 回退：r2 只改 `a1_deflate_core.v`；回退到 r1 `faacdbc0e80f821ed7dfdfa099153b6475f5c05155bd34a7cad324236cc46ad5` 或 r0 `6cd35881a864faec3a7fe9f8355d71a66f775bf2c037202959f315d42a799d9f`。r0/r1 manifest 保持只读。

## 7. 复现

```powershell
upstream/ph1p100-pcie-ep-fpga/tools/codec/run_p2_r2.ps1
upstream/ph1p100-pcie-ep-fpga/tools/codec/run_p3_r2.ps1
subst X: "...\T10.a1-eng-freeze\r2\td"; subst Y: "<PROJECT_ROOT>"
cd X:\; D:\anlogic\TD_Release_2026.2\bin\td_commands_prompt.exe X:/00_all.tcl
```

- 综合报告：`r2/reports/syn_gate_timing.rpt`、`syn_gate_area.rpt`。
- 日志：`r2/logs/td_stdout.log`、`syn_run.log`；原始 run：`r2/td/a1_eng_freeze_r2_Runs/syn_1/`。
- 新 manifest：`T10.a1-eng-freeze/CANDIDATE-MANIFEST-r2.json`（不覆盖 r0/r1）。
