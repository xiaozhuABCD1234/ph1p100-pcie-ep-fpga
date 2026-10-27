# T10.a1-eng-freeze r8 — raddr/hent_pos 预计算最终局部轮（blocked）

- task_id: `T10.a1-eng-freeze` | round **r8** | run `20261020-0209_singleA_aplus_closedloop`
- 日期：2026-10-21 | 性质：离线、synthetic、无上板/下载/bitgen/Flash
- 唯一判定：**blocked — G1 回归 PASS；G2 S2 WNS -0.470 ns，仍 <0；2/2 综合、0/1 布线；按 stop_conditions 未 route；r8 为最后一次局部补丁轮，FAIL 不自动 r9。**

## 1. 冻结候选

| 文件 | SHA256 |
|---|---|
| `upstream/ph1p100-pcie-ep-fpga/rtl/ep_side/codec/a1_deflate_core.v` | `4e1e97b8f9c00102447ab1c6de63a26c8b762e57416d0365c7aba837ce99ec9c` |
| `upstream/ph1p100-pcie-ep-fpga/rtl/ep_side/codec/a1_frame_top.v` | `fa64cb487b4241241516183e7b8bfd71f96b30e54f5ed3d53ac239a2771e1ba2`（r7 smem 流水保留，未再改） |
| `r8/td/a1_small_top.sdc` | `227dd39e3dba8834af510013c71242450d4571307267d6bac4938cb8ef696311`（与 r7 相同，未改） |

仅修改 `a1_deflate_core.v`；frame_top 保留 r7 的 smem 写端口寄存。协议/端口/帧语义/CRC/长度/abort/Bayer 未变。

## 2. 本轮 RTL 改动

1. **S_SCAN 的 raddr 改为自增**：`raddr <= raddr + 1` 取代 `clamp_addr(pos+4, blk_n)`。S_SCAN 仍每 cycle 1 个位置；块尾越界读由 `hash_ok` 门控，bm 数组容量足够。该步把 WNS 从 -1.287 推到 **-0.586**、TNS -73.092→**-3.641**、违例端点 165→39。
2. **hent_pos_p3 预计算**：在 htab 读/写旁路时寄存 `hent_pos + 3`，S_SCAN hit 的 `fq_r` 捕获改用 `hent_pos_p3`，去掉 `htab_rdata -> +3 -> bm_b -> fq_r` 的加法链。该步把 WNS 推到 **-0.470**，但新的 `state -> htab_rd_addr -> htab 读 -> hent_pos_p3` 路径成为瓶颈（5.739 ns）。
3. 修正了 `hent_pos_p3` 在 htab always 与主 always 双驱动导致的 TD elaboration 失败（`constantly driven from multiple places`）；把 reset/abort 放入 htab always 后重跑。该失败是工具/流程错误，不构成额外时序综合结果。

## 3. G1 回归（新候选）

| 项 | 结果 | 证据 |
|---|---|---|
| 改动前基线 P2/P3 | PASS | `r8/p2-baseline/result.json`、`r8/p3-baseline/result.json` |
| P2 13/13 | **PASS** | `r8/p2/result.json` |
| P3 20/20 | **PASS** | `r8/p3/result.json`（`failures=[]`） |
| zlib + 自研 strict | 0 mismatch | P2/P3 日志 |
| `vlog` | Errors 0 / Warnings 0 | `r8/p2/logs/vlog.log`、`r8/p3/logs/vlog.log` |
| 1080p p1d1 | 4,677,945 cycles / 81,707 B / 540 blocks = **103.892 MB/s** | `r8/p3/runs/f1080p_p1d1/stats.txt` |
| P2 comp / rand | 81.067 / 178.351 MB/s | `r8/p2/result.json` |

cycles 与 r7 完全相同，无吞吐回退。

## 4. TD / G2

| run | SWNS | STNS | Fmax | 违例端点 | route |
|---|---:|---:|---:|---:|---|
| S1 | **-0.586 ns** | -3.641 ns | 168.947 MHz | 39 / 148,565 | not_run |
| S2 | **-0.470 ns** | -37.591 ns | 172.325 MHz | 147 / 148,604 | not_run |

- S1 关键路径：`htab_rdata_reg[28] -> hent_pos -> bm_b -> fq_r`，5.855 ns（raddr 自增后已不再是 raddr 链）。
- S2 关键路径：`state_reg[23] -> htab_rd_addr -> htab 读 -> hent_pos_p3_reg`，5.739 ns、slack -0.470 ns。`hent_pos_p3` 去掉了 fq_r 捕获加法链，但把 htab 读+p3 加法推到临界。
- `Routed`、routed WNS/TNS/HWNS/HTNS、布线后资源、`report_cdc`、`check_timing`、bitgen：**not_run**。S2 综合 WNS<0，按停止条件未 launch phy。
- 预算：综合 **2/2**、布线 **0/1**、TD wall 约 14 min（S1 419.1 s、S2 409.2 s；另有 1 次 3 s elaboration 失败后重跑），低于 90 min；无 bitgen、无下载、无 Flash、未上板。
- 证据：`r8/td/00_all.tcl`、`r8/logs/td_stdout_s1.log`、`td_stdout.log`、`r8/logs/td_stdout_elab_fail.log`、`r8/logs/syn_elab_fail_run.log`、`r8/reports/syn_gate_timing_s1.rpt`、`syn_gate_timing_s2.rpt`。

## 5. 停止依据

dispatch `stop_conditions`：S2 综合仍 WNS/TNS<0 → 停止，不布线，无第 3 次综合。r8 是最后一次局部补丁轮，FAIL 不自动 r9。未降频、未改 SDC、未加 false path/multicycle、未换 seed、未 bitgen/下载/Flash/上板。

## 6. 最小下一步（需用户明确选择，r9 不自动开）

- 路线 (a) 继续 187.5 MHz：需新的局部/架构轮处理 `state -> htab_rd_addr -> htab 读 -> hent_pos_p3`（例如把 `pos+3` 直接存入 htab 或在 htab 读地址侧再加寄存），但 r8 已是最后一次局部补丁轮，不能自动续。
- 路线 (b) 145–150 MHz + 异步 FIFO/CDC：r8 S2 综合 Fmax 172.3 MHz，150 MHz 有约 15% 综合余量但布线会打折；只保证 ≥77.76 MB/s，不保证 97.2。属时钟架构变更，需用户明确同意。
- 不得降频/false path/multicycle/seed sweep。

## 7. 回退与复现

- 回退：`a1_deflate_core.v` 回到 r7 `24bfb7d5685c95cd27f29c7c51ac9766b06d02a5c2b8297975d97333eb414897`；frame_top 保持 r7 `fa64cb48…1ba2`；删除 `r8/**` 与 `p4/result-r8.md`；r0–r7 manifest 与报告只读保留。
- 复现：
```powershell
upstream/ph1p100-pcie-ep-fpga/tools/codec/run_p2_r8.ps1
upstream/ph1p100-pcie-ep-fpga/tools/codec/run_p3_r8.ps1
subst X: "...\T10.a1-eng-freeze\r8\td"; subst Y: "<PROJECT_ROOT>"
cd X:\; D:\anlogic\TD_Release_2026.2\bin\td_commands_prompt.exe X:/00_all.tcl
```

## 8. 未测 / 不声明

Routed 时序、布线后资源、TD CDC、bitgen、板级、真实 RAW、双路 155.52 MB/s、G3/G4、生产集成：均 not_run/blocked。G1 PASS 不能替代 G2；r8 FAIL 不自动开 r9。