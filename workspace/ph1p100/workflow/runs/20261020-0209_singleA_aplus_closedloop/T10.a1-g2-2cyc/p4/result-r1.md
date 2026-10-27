# T10.a1-g2-2cyc r1 — 时序综合已闭合（WNS +0.134 / TNS 0.000）；布线因器件 slice 容量溢出失败，blocked

- task_id `T10.a1-g2-2cyc` | round **r1**（新包修复轮，2 会话/60 min 预算）| 日期 2026-10-22
- 离线 synthetic，无 bitgen/下载/Flash/上板
- 唯一判定：**blocked — G1 与 r10 逐位一致（P2 13/13、P3 20/20、0 mismatch、vlog 0/0；33 个用例 stream SHA 与 run_cycles 全部相同；1080p 4,677,945 cycles；P2 comp 81.067 MB/s）；G2 综合 S1 达到 WNS +0.134 ns / TNS 0.000（时序门槛首次通过），但唯一一次布线在 packing 阶段以 `PHY-9053 slice number = 83072 > 71680` 失败（综合后 slice 已 72,904 = 101.71%，ERAM 仅用 4/300），属器件容量而非时序，布线 1/1 已用尽。**

## 1. 冻结候选（SHA256）

| 文件 | SHA256 | 状态 |
|---|---|---|
| `upstream/…/rtl/ep_side/codec/a1_deflate_core.v` | `47db3057933a66241544c86e0f3522bc8704914938db2844a3081713ae28e0a2` | r1 唯一改动 |
| `upstream/…/rtl/ep_side/codec/a1_frame_top.v` | `18d51b1b80002e3549b6afd74956cff9d323d0a0272a7a08d617365a01611cbe` | 锁定未改 |
| `r1/td/a1_small_top.sdc` | `227dd39e3dba8834af510013c71242450d4571307267d6bac4938cb8ef696311` | 锁定未改 |

manifest：`T10.a1-g2-2cyc/CANDIDATE-MANIFEST-g2-2cyc-r1.json`（r0 全部证据保留）

## 2. r1 RTL 改动（仅 lim2/s1_ok）

1. 新增 `reg [12:0] lim2`；S_WAIT 装载块时 `lim2 <= (sel_len > 13'd2) ? (sel_len - 13'd2) : 13'd0;`
2. `wire s1_ok = (s1_pos_r < lim2);` 取代 `(s1_pos_r + 13'd2 < blk_n)`，去掉 13 位加法（约 1.6 ns ADDER 段）。
3. 等价性：`s1_pos_r+2 < blk_n ⟺ s1_pos_r < blk_n-2`；`blk_n≤2` 时 lim2=0 → 两种写法均为 false。未改 bypass select、协议/端口/帧语义/CRC/长度/abort/Bayer；frame/SDC 未动。

## 3. G1 回归（全部 PASS 且与 r10 逐位一致）

| 项 | 结果 | 证据 |
|---|---|---|
| P2 | **13/13 PASS**（+bp/gapbp/abort/reset PASS） | `r1/p2/result.json` |
| P3 | **20/20 PASS**，`failures=[]` | `r1/p3/result.json` |
| zlib + strict | 0 mismatch | P2/P3 日志 |
| vlog | Errors 0 / Warnings 0 | 两侧 `logs/vlog.log` |
| SHA / cycles | 13 P2 + 20 P3 用例与 r10 **完全相同**（`diffs=[]`）；1080p `b769cc66…08ff`、**4,677,945** cycles（≤5.0M） | 逐用例比较 |
| P2 comp | **81.067 MB/s** ≥ 77.76 | `p2/result.json` |

## 4. TD（1 会话 / 47.7 min；综合 1/2、布线 1/1）

| 阶段 | 结果 | 证据 |
|---|---|---|
| syn_1 | **SWNS +0.134 ns, STNS 0.000 ns** → 时序门槛通过，自动进入 phy_1 | `r1/td/syn_gate_timing_s1.rpt` |
| syn 资源 | `#slice* 72904 / 71680 = 101.71%`；`#lut 107906`；`#eram 4/300 (1.33%)`；`#dram lut 8432`；`QOR-3001 HIGH LUT 101.71%` | `a1_g2_r1_Runs/syn_1/run.log` |
| phy_1 | **失败/未 Routed**：`PHY-9053 slice number = 83072 > 71680`（前置 `PHY-7022` estimated slice utilization 107 > 95），packing 后即退出，1515 s | `a1_g2_r1_Runs/phy_1/run.log`、`td_stdout_s1.log` |
| Routed WNS/TNS/HWNS/HTNS、资源、`report_cdc`、`check_timing` | **not_run**（open_run 未到达） | — |
| bitgen | not_run | 未调用 |

**根因（容量，不是时序）**：a1_eng_top 的存储几乎全部映射成 LUT/DRAM（ERAM 仅 4/300），slice 需求在综合后已超 1.71%，packing 后 83,072（116%）。r0-c（未改 lim2、时序 -0.156）综合就已 73,461 slice (102.48%)，因此这是 **a1_eng_top 既有的容量缺口，不是 r1 回归**；r1 反而略降（73,461→72,904）。

## 5. 停止依据与最小下一步

- dispatch：布线 ≤1，route 失败 → 停止并 blocked；无第 2 次布线、不 seed sweep/降频/false path。综合预算剩 1 次，但容量问题不是综合时序问题，且 60 min 会话预算仅剩 ~12 min，不足以做“综合+布线”。
- **时序已闭合**（synth WNS +0.134 / TNS 0.000），下一轮只需解决容量：
  1. 把 `a1_deflate_core.v` 的 bm_a/bm_b（2×16K×8）、htab（1024×66+valid）、cmem（4096×16）改为可推断 ERAM 的同步读/寄存输出风格（或 ram_style 属性），frame_top 的 smem（7680×10）同理（ERAM 目前 99% 空闲）；
  2. 或使用面积导向的 map/综合设置（QoR 建议 `set_param gate add_map_lut_struct on`）——属策略变更，需规划明确授权；
  3. 或换更大器件；4) 或接受 G2 ⚠。
- 不建议：降频、放宽 SDC、false path/multicycle、seed sweep、第 2 次盲目布线。

## 6. 复现

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File upstream\ph1p100-pcie-ep-fpga\tools\codec\run_p2_g2r1.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File upstream\ph1p100-pcie-ep-fpga\tools\codec\run_p3_g2r1.ps1
# TD（按 2026-10-22 PATH_CONTRACT：T:=r1\td，Y:=项目根）
subst T: "<...>\T10.a1-g2-2cyc\r1\td"; subst Y: "<PROJECT_ROOT>"
cd T:\; $env:A1_TD_TAG="s1"; D:\anlogic\TD_Release_2026.2\bin\td_commands_prompt.exe T:/00_all.tcl
```

## 7. 证据偏差（诚实记录）

- 本次 TD 启动时仍沿用旧约定（X: → r1/td）；仓库 2026-10-22 已发布新 PATH_CONTRACT（TD 用 T:/Y:，仿真用 P:/W:），本次失败原因是容量溢出而非盘符，但后续应改用 `tools/td/open_td.ps1`/`td_env.ps1`。
- r0-a 期间的 `A1_P2_RUN` 多一级 `..` 写错目录事件已记录在 r0 manifest/result 中（目录已移到 temp，未删除）。

## 8. 未测 / 不声明

Routed 时序、布线后资源、CDC 报告、bitgen、板级、真实 RAW、双路、G3/G4、生产集成：**not_run**。综合 WNS≥0 不等于 Routed 通过；G2 未达成。
