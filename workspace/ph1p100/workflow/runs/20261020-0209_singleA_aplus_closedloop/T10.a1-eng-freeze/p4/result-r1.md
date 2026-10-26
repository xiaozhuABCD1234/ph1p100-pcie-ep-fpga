# T10.a1-eng-freeze r1 — 有限修复结果（G2 仍 FAIL）

- task_id: `T10.a1-eng-freeze`｜round **r1**｜run `20261020-0209_singleA_aplus_closedloop`
- 日期：2026-10-20｜性质：离线、synthetic、无上板/下载/bitgen
- 唯一判定：**blocked — G1 回归 PASS；G2 时序仍 FAIL（综合 WNS -3.816 ns，Fmax 109.302 MHz）；按 stop condition 2 在综合后停止，未布线。**
- 生产构建 0、下载 0、bit/CWC 0；187.5 MHz 约束未放宽，无 false path/multicycle。

## 1. 本轮改了什么

仅修改 `upstream/ph1p100-pcie-ep-fpga/rtl/ep_side/codec/a1_deflate_core.v`：

| 原实现 | r1 实现 | 目的 |
|---|---|---|
| `htab[1024×53]` 组合读（1024:1 LUT mux） | 同步读寄存器 + **下一窗口组合地址预取** + 同地址 write-first bypass | 去掉 htab 组合读长路径，同时保持每位置 1 cycle 的匹配查找与 distance-1 语义 |
| `cmem[4096×16]` 组合读 `crq <= cmem[rb_word]` | 同步读 `cmem_rdata` + 新增 `S_REPLAY_RD` 等待态 | 去掉 4096:1 组合 mux；每 16-bit word 多 1 cycle |
| `hent/hent_v` 直接来自数组 | 来自 `htab_rdata/htab_rvalid` 寄存器 | ERAM/同步读推断 |

- 外部端口、帧提交/abort/CRC/长度语义、zlib/fixed/stored 格式、Bayer 映射、TB 均未改。
- `a1_frame_top.v` hash 未变：`3c32803b41378629622ae3a709ab64373b2fb13286bfc7ea789e7e1dbf190961`。
- 新 `a1_deflate_core.v` hash：`faacdbc0e80f821ed7dfdfa099153b6475f5c05155bd34a7cad324236cc46ad5`。
- 旧 r0 `CANDIDATE-MANIFEST.json` 与 `p4/result.md` 未覆盖；新证据全部在 `r1/**` 与 `p4/result-r1.md`。

## 2. G1 回归（新候选，未复用旧证据）

| 回归 | 结果 | 证据 |
|---|---|---|
| P2 13/13 模块用例 | **PASS** | `r1/p2/result.json`（`verdict=PASS`，`manifest_files=136`） |
| P3 20/20 帧级用例 | **PASS** | `r1/p3/result.json`（`verdict=PASS`，`failures=[]`） |
| zlib 1.2.13 + 自研 strict 双解 | 0 mismatch | P2/P3 日志 |
| `vlog` Errors 0 / Warnings 0 | PASS | `r1/p2/logs/vlog.log`、`r1/p3/logs/vlog.log` |
| 1080p A/B、stored、abort/reset、2 帧 | PASS | `r1/p3/runs/**/stats.txt` |

关键帧统计（新候选）：

| case | cycles | stream_len | blocks | commit |
|---|---:|---:|---:|---:|
| f1080p_p1d1 | 4,677,941 | 81,707 | 540 | 1 |
| f1080p_rand（全 stored） | 4,678,532 | 2,594,706 | 540 | 1 |
| multi1080p ×2 | 9,355,887 | 2×81,707 | 2×540 | 1,1 |

与 r0 相比 1080p p1d1 只多 100 cycles（4,677,841→4,677,941），`S_REPLAY_RD` 被输出 FIFO 吸收，未造成可见吞吐下降。

## 3. G2：综合通过但时序仍不收敛

TD `Release_2026.2` / build `6.2.3.210850`，器件 `PH1P100SBG484 -3`，同一 `a1_eng_top` 与 187.5 MHz SDC。单会话 132 s，`exit=0`。

| 指标 | r0 | **r1** | 变化 |
|---|---:|---:|---|
| SWNS | -6.471 ns | **-3.816 ns** | +2.655 ns |
| STNS | -1133.864 ns | **-680.559 ns** | +453.305 ns |
| HWNS / HTNS | 0 / 0 | **0 / 0** | — |
| Fmax | 84.717 MHz | **109.302 MHz** | +24.585 MHz |
| LUT | 11,026 | **11,180** | +154 |
| FF | 1,995 | **2,064** | +69 |
| ERAM | 4/300 | **4/300** | 0 |
| DSP | 0/220 | **0/220** | 0 |
| DRAM LUT | 5,240 | **5,240** | 0 |
| Slice | 9,983 (13.93%) | **10,548 (14.72%)** | +565 |

**关键路径已从 htab 读 mux 移走**：
`u_dut/u_core/dist_r_reg[7].clk` → `u_dut/u_core/pos_reg[0].ce`，13 级（ADDER×6 + LUT×7），
对应 `pos + len_r` / 剩余长度与 `stored_bits` 的比较及 `pos` 更新链。

- 结论：内存读路径修复有效，但剩余组合算术链仍有 -3.816 ns。
- 按 dispatch stop condition 2「综合 WNS < 0 → 停止，不布线、不换 seed」，**未 launch phy_1**；`Routed`、routed WNS/TNS、布线后资源、bit/CWC 均 `not_run`。
- 没有第 4 次 TD 会话；本包 TD 会话总数 3/3。

## 4. CDC

- 结构：单时钟 `clk`，同步复位；综合 STA 仅 `clk0`，`CC-From/CC-To=no`。
- TD `report_cdc`：**not_run**。脚本在 phy 完成后才调用它，而本轮按 stop condition 未进入 phy。未执行说明与复现入口：`r1/td/00_all.tcl` 的 `report_cdc -file cdc.rpt`。
- 因此只声明结构化单时钟结论，**不**声明 TD CDC 工具 PASS。

## 5. 服务率（新候选，187.5 MHz 仿真换算）

| 场景 | cycles | cycles/B | MB/s | ≥77.76 | ≥97.2 |
|---|---:|---:|---:|---|---|
| 1080p p1d1 | 4,677,941 | 1.80474 | **103.892** | PASS | PASS |
| 1080p ×2 聚合 | 9,355,887 | 1.80474 | **103.892** | PASS | PASS |
| 1080p rand（全 stored） | 4,678,532 | 1.80497 | **103.879** | PASS | PASS |

- 77.76 MB/s 预算 2.4113 cycles/B；97.2 预算 1.9290 cycles/B；实测 1.8047 → 97.2 余量约 +6.9%。
- 2 帧背靠背、帧间 5 cycles；无长稳/热态/随机反压跨帧数据。16 行小帧仍约 88.9 MB/s（r0 口径，未重跑长帧外内容）。
- 所有数字是仿真换算，不是 STA/板上；G2 未收敛前不得作为可上板结论。

## 6. 已知限制与最小下一步

1. 剩余关键路径是匹配长度/位置更新算术链（`pos + len_r`、`stored_bits` 比较、`pos` 更新），不是内存读。
2. 下一步最小改动：在 `S_MLEN`/`S_MDIST` 之间插入一级寄存器，把 `pos_next = pos + len_r`、`remaining = blk_n - pos_next` 和 `stored_bits` 比较分段；或将 `pos` 更新与候选位计数比较拆到两个 cycle。任何改动都必须重跑 P2/P3 并重新申请 TD 会话（本轮预算 3/3 已用尽）。
3. 不得用降低时钟、false path、multicycle 或改 SDC 的方式过关。
4. `Routed`、routed 资源/时序、CDC 工具报告、bit/CWC、板级、真实 RAW、双路 155.52：**not_run/blocked**。
5. 回退：新候选仅 `a1_deflate_core.v` 变化；回退到 r0 候选即恢复 `6cd35881a864faec3a7fe9f8355d71a66f775bf2c037202959f315d42a799d9f`，r0 manifest/报告保持只读。旧 P2/P3 manifest 未被覆盖。

## 7. 复现

```powershell
# G1（新候选）
upstream/ph1p100-pcie-ep-fpga/tools/codec/run_p2_r1.ps1
upstream/ph1p100-pcie-ep-fpga/tools/codec/run_p3_r1.ps1

# G2（仅综合；WNS<0 时不布线）
subst X: "...\T10.a1-eng-freeze\r1\td"; subst Y: "<PROJECT_ROOT>"
cd X:\; D:\anlogic\TD_Release_2026.2\bin\td_commands_prompt.exe X:/00_all.tcl
```

- 综合报告：`r1/reports/syn_gate_timing.rpt`、`syn_gate_area.rpt`。
- 日志：`r1/logs/td_stdout.log`、`syn_run.log`；原始 run：`r1/td/a1_eng_freeze_r1_Runs/syn_1/`。
- 新 manifest：`T10.a1-eng-freeze/CANDIDATE-MANIFEST-r1.json`（不覆盖 r0）。
