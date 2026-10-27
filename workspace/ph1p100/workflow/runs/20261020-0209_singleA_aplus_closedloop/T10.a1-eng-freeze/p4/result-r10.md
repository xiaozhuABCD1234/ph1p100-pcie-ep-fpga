# T10.a1-eng-freeze r10 — htab/bm 读地址寄存（最后结构性尝试，blocked）

- task_id: `T10.a1-eng-freeze` | round **r10** | run `20261020-0209_singleA_aplus_closedloop`
- 日期：2026-10-21 | 性质：离线、synthetic、无上板/下载/bitgen/Flash
- 唯一判定：**blocked — G1 回归 PASS；G2 综合 S1 WNS -0.450 ns / TNS -51.634 ns、144 违例端点；1/2 综合、0/1 布线（WNS<0 不布线）。关键路径已离开读地址结构、转入 hit/使能逻辑，继续修复需越界，按 stop_conditions 停止；r10 FAIL 不自动 r11。**

## 1. 冻结候选

| 文件 | SHA256 |
|---|---|
| `upstream/…/rtl/ep_side/codec/a1_deflate_core.v` | `7a10917d1f698c6dd408c14a19a4779ddf11ac85c68d937b6cdaee3aa4a5aed8`（54165 B） |
| `upstream/…/rtl/ep_side/codec/a1_frame_top.v` | `fa64cb487b4241241516183e7b8bfd71f96b30e54f5ed3d53ac239a2771e1ba2`（锁定，未改） |
| `r10/td/a1_small_top.sdc` | `227dd39e3dba8834af510013c71242450d4571307267d6bac4938cb8ef696311`（锁定，未改） |

仅修改 `a1_deflate_core.v` 的 htab/bm 读地址结构；frame_top、SDC、协议/端口/帧语义/CRC/长度/abort/Bayer 未改。

## 2. 本轮 RTL 改动

1. 新增 `reg [12:0] p3_r`：S_SCAN 期间的 `pos+3` 寄存器，S_WAIT/S_PRE 装入 3、每个字面量推进 `p3_r <= p3_r + 1`、S_REPOS 首拍 `p3_r <= pos + 3`。
2. S_SCAN hit 分支改用 `p3_r`：块尾判据 `p3_r >= blk_n`（去掉 `pos+3` 加法比较）、`cq_r <= bm_a[p3_r]`、`ext_raddr <= p3_r+1`、`ext_rem` 由 `p3_r+1` 计算；`faddr`/`ext_faddr` 直接取 htab 里的 `pos+3` 字段，去掉 `hent_pos+3/4` 加法。
3. 保留 r9 的 pos+3 存表与 66-bit 打包；每符号仍 1 cycle（P2/P3 cycles 与 r9 完全一致）。

## 3. G1 回归

| 项 | 结果 | 证据 |
|---|---|---|
| P2 | **13/13 PASS** | `r10/p2/result.json` |
| P3 | **20/20 PASS**, `failures=[]` | `r10/p3/result.json` |
| zlib + strict | 0 mismatch | P2/P3 日志 |
| vlog | Errors 0 / Warnings 0 | `r10/p2/logs/vlog.log`、`r10/p3/logs/vlog.log` |
| P2 comp / rand | 81.067 / 178.351 MB/s | `r10/p2/result.json` |
| 1080p p1d1 | **4,677,945 cycles / 103.892 MB/s**，stream sha `b769cc66…08ff`（与 r9/r8 相同） | `r10/p3/result.json` |

吞吐与 r9/r8 完全一致，无回退、无每符号气泡。

## 4. TD / G2

| 尝试 | SWNS | STNS | 违例端点 | 结果 |
|---|---:|---:|---:|---|
| S1 | **-0.450 ns** | -51.634 ns | 144 / 148,921 | 不布线（停止条件） |

- S1 关键路径已从 r9 的 `pos → (+3) → bm_a → cq_r/raddr` 移开，新路径为 `pos_reg[1] → hdist = pos - hent_pos → hit/阈值使能 → thresh_base_reg[3].ce`，7 级、5.716 ns（ADDER=4）。
- 读地址寄存本身已生效（原 8 级 5.703 ns 的地址/加法链不再是最大路径），但 WNS 仅由 -0.434 变为 -0.450，TNS 由 -45.639 变为 -51.634：新瓶颈在 **hit 比较/使能逻辑**（`pos - hent_pos` 减法链），不属 dispatch 允许的“htab/bm 读地址结构”范围。
- `Routed`、routed WNS/TNS/HWNS/HTNS、布线后资源、`report_cdc`、`check_timing`、bitgen：**not_run**。
- 预算：综合 **1/2**、布线 **0/1**、TD wall ≈ 14.0 min（单会话），无 bitgen/下载/Flash/上板。
- 证据：`r10/logs/td_stdout.log`、`r10/reports/syn_gate_timing_s1.rpt`、`r10/td/a1_eng_freeze_r10_Runs/syn_1/`。

## 5. 停止依据

dispatch `stop_conditions`：综合 WNS/TNS<0 → 不布线；且继续修复需要改 hit/使能逻辑（越出“htab/bm 读地址结构”），按规定停下交原规划，不用第二次综合做越界改动。未降频、未改 SDC、未加 false path/multicycle、未换 seed。

## 6. 证据偏差说明（诚实记录）

- r10 期间一次 P2 误写：`run_p2_r10.ps1` 初版 `` 仍指向 `r9`（替换漏项），加上 `subst W:` 未及时释放，导致首两次 r10 P2 运行把 **r9/p2** 的 `runs/` 与 `logs/vlog.log` 重写、r10/p2 只有空 run 目录（verdict FAIL）。
- 影响：`r9/p2/result.json` 字节未变，仍等于 r9 manifest 的 `6ab4d148…d130`；但 `r9/p2/logs/vlog.log` 现为 `58d0ebaa…a61`，与 r9 manifest 记录的 `02dfece1…4996` **不再一致**（内容仍是同一命令的 0/0 输出，绝对路径不同）。r9 其余 manifest 项未受影响。修正 `` 后 r10 P2 重跑 PASS。
- r9 证据如需严格冻结，请测试者以 `CANDIDATE-MANIFEST-r9.json` 复核时按此偏差处理，不要据此判 r9 功能漂移。

## 7. 最小下一步（需用户明确选择，r10 不自动开 r11）

- 路线 (b)：145–173 MHz A+ 小顶 + 异步 FIFO/CDC 桥接 187.5 MHz 系统；需用户明确同意时钟架构变更，并接受只保证 ≥77.76 MB/s。
- 或接受 G2 未闭合的 ⚠ 并保留 r8/r9/r10 证据。
- 若要继续 187.5 MHz，需新的范围授权覆盖 **hit/hdist 比较与使能逻辑**（例如 hdist 预计算/比较树重排），已超出本次 dispatch。

## 8. 复现

```powershell
upstream/ph1p100-pcie-ep-fpga/tools/codec/run_p2_r10.ps1
upstream/ph1p100-pcie-ep-fpga/tools/codec/run_p3_r10.ps1
subst X: "...\T10.a1-eng-freeze\r10\td"; subst Y: "<PROJECT_ROOT>"
cd X:\; D:\anlogic\TD_Release_2026.2\bin\td_commands_prompt.exe X:/00_all.tcl
```

## 9. 未测 / 不声明

Routed 时序、布线后资源、TD CDC、bitgen、板级、真实 RAW、双路 155.52 MB/s、G3/G4、生产集成：均 not_run/blocked。G1 PASS 不能替代 G2。