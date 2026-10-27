# T10.a1-eng-freeze r6 — S_EXT/cq 1-cycle 预取结果（blocked）

- task_id: `T10.a1-eng-freeze` | round **r6** | run `20261020-0209_singleA_aplus_closedloop`
- 日期：2026-10-21 | 性质：离线、synthetic、无上板/下载/bitgen/Flash
- 唯一判定：**blocked — G1 回归 PASS；G2 综合 S2 WNS -1.346 ns，仍 <0；2/2 综合、0/1 布线；按 stop_conditions 未 route；r6 FAIL，不自动 r7。**

## 1. 冻结候选

| 文件 | SHA256 |
|---|---|
| `upstream/ph1p100-pcie-ep-fpga/rtl/ep_side/codec/a1_deflate_core.v` | `24bfb7d5685c95cd27f29c7c51ac9766b06d02a5c2b8297975d97333eb414897` |
| `upstream/ph1p100-pcie-ep-fpga/rtl/ep_side/codec/a1_frame_top.v` | `3c32803b41378629622ae3a709ab64373b2fb13286bfc7ea789e7e1dbf190961`（未改） |
| `r6/td/a1_small_top.sdc` | `227dd39e3dba8834af510013c71242450d4571307267d6bac4938cb8ef696311`（与 r5 相同，未改） |

仅修改 `a1_deflate_core.v`；端口、帧提交/abort、raw/xform/stream 长度与 CRC、zlib/fixed/stored 格式、Bayer 映射、TB 均未变。r5 的 packer/opq 结构保留。

## 2. 本轮 RTL 改动

1. **S_EXT 1-cycle 预取 + 寄存比较**：S_SCAN hit 时直接捕获 `cq_r/fq_r`（首个扩展字节），并初始化 `ext_raddr/ext_faddr=pos+4/hent_pos+4`、`ext_rem=blk_n-(pos+4)`（饱和到 0）。
2. **S_EXT 循环**：每 cycle 比较上一拍捕获的 `cq_r/fq_r`，同时用**已寄存的** `ext_raddr/ext_faddr` 读下一字节；match 继续时只更新 `len_r/ext_rem/ext_raddr/ext_faddr`。state 决策不再经过 `bm_a` 异步读，也没有每字节气泡。
3. **S1 的 `raddr+1` 组合读地址被 S2 的 `ext_raddr/ext_faddr` 寄存器替代**：消除了 `raddr` 高 fanout 和加法器进入 `cq_r` 捕获路径的问题。
4. `ext_rem` 用递减计数代替 `pos+len_r+1>=blk_n` 的加法/比较；`len_r==257` 处理 258 上限。

## 3. G1 回归（新候选）

| 项 | 结果 | 证据 |
|---|---|---|
| 改动前基线 P2/P3 | PASS | `r6/p2-baseline/result.json`、`r6/p3-baseline/result.json` |
| P2 13/13 | **PASS** | `r6/p2/result.json` |
| P3 20/20 | **PASS** | `r6/p3/result.json`（`failures=[]`） |
| zlib + 自研 strict | 0 mismatch | P2/P3 日志 |
| `vlog` | Errors 0 / Warnings 0 | `r6/p2/logs/vlog.log`、`r6/p3/logs/vlog.log` |
| 1080p p1d1 | 4,677,945 cycles / 81,707 B / 540 blocks = **103.892 MB/s** | `r6/p3/runs/f1080p_p1d1/stats.txt` |
| P2 comp / rand | 81.067 / 178.351 MB/s | `r6/p2/result.json` |

与 r5 完全一致（4,677,945 cycles、81,707 B、540 blocks），预取没有引入每符号气泡。

## 4. TD / G2

| run | RTL | SWNS | STNS | Fmax | 违例端点 | route |
|---|---|---:|---:|---:|---:|---|
| S1 | `3ab1565f…` | **-1.466 ns** | -133.195 ns | 147.080 MHz | 413 / 148,460 | not_run |
| S2 | `24bfb7d5…`（当前） | **-1.346 ns** | -416.270 ns | 149.723 MHz | 404 / 148,512 | not_run |

- S1 关键路径：`raddr_reg[2] -> cq_r_reg`，6.735 ns、9 级；`raddr+1` 和 `raddr` fanout 进入捕获路径。
- **S2 关键路径已移出 core**：`byte_k_reg[2] -> smem we`（`a1_frame_top.v`），6.574 ns、9 级、slack -1.346 ns。core 的 `cq -> S_EXT/state` 路径已不再是关键路径；但 frame_top 的 Bayer `smem` 写使能路径成为新瓶颈。
- `Routed`、routed WNS/TNS/HWNS/HTNS、布线后资源、`report_cdc`、`check_timing`、bitgen：**not_run**。S2 综合 WNS<0，按停止条件未 launch phy；CDC 只能声明结构为单时钟 `clk`。
- 证据：`r6/td/00_all.tcl`、`r6/logs/td_stdout_s1.log`、`td_stdout.log`（S2）、`r6/reports/syn_gate_timing_s1.rpt`、`syn_gate_timing_s2.rpt`。
- 预算：综合 **2/2**、布线 **0/1**、TD wall 约 14 min（S1 420.8 s、S2 430.1 s），低于 90 min；无 bitgen、无下载、无 Flash、未上板。

## 5. 停止依据

dispatch `stop_conditions`：S2 综合仍 WNS/TNS<0 → 停止，不布线，无第 3 次综合。未降频、未改 SDC、未加 false path/multicycle、未换 seed、未 bitgen/下载/Flash/上板。

## 6. 最小下一步（需用户/规划新授权，r7 不自动开）

S2 的新瓶颈在 `a1_frame_top.v` 的 `byte_k -> smem we`（Bayer 2 行对缓存的写使能/地址/数据路径），不是 core。若继续，需要对 frame_top 做**纯流水适配**（寄存 smem 写使能/地址/数据，保持 Bayer 映射、2 行对边界、CRC/长度/abort 语义不变），并重新做 P2/P3 与吞吐证明；这超出 r6 的 core-only 范围，需要新的授权/预算。r5 最佳候选 `a6f323ab…` 仍为 -0.949 ns，r6 的 `24bfb7d5…` 为 -1.346 ns；不要在没有新证据时继续在 core 内加流水。

## 7. 回退与复现

- 回退：`a1_deflate_core.v` 回到 r5 best `a6f323ab96c408c667728138719f8370bb50ef402f3f76373049cd76d0f6dcae`；删除 `r6/**` 与 `p4/result-r6.md`；r0–r5 manifest 与报告只读保留。
- 复现：
```powershell
upstream/ph1p100-pcie-ep-fpga/tools/codec/run_p2_r6.ps1
upstream/ph1p100-pcie-ep-fpga/tools/codec/run_p3_r6.ps1
subst X: "...\T10.a1-eng-freeze\r6\td"; subst Y: "<PROJECT_ROOT>"
cd X:\; D:\anlogic\TD_Release_2026.2\bin\td_commands_prompt.exe X:/00_all.tcl
```

## 8. 未测 / 不声明

Routed 时序、布线后资源、TD CDC、bitgen、板级、真实 RAW、双路 155.52 MB/s、G3/G4、生产集成：均 not_run/blocked。G1 PASS 不能替代 G2；r6 FAIL 不自动开 r7。