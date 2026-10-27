# T10.a1-eng-freeze r7 — frame_top smem 写端口寄存结果（blocked）

- task_id: `T10.a1-eng-freeze` | round **r7** | run `20261020-0209_singleA_aplus_closedloop`
- 日期：2026-10-21 | 性质：离线、synthetic、无上板/下载/bitgen/Flash
- 唯一判定：**blocked — G1 回归 PASS；G2 S1 WNS -1.287 ns，仍 <0；S1 后关键路径已转移到 core（r7 禁止改 core），按 stop_conditions 未用 S2、未布线；r7 FAIL，不自动 r8。**

## 1. 冻结候选

| 文件 | SHA256 |
|---|---|
| `upstream/ph1p100-pcie-ep-fpga/rtl/ep_side/codec/a1_deflate_core.v` | `24bfb7d5685c95cd27f29c7c51ac9766b06d02a5c2b8297975d97333eb414897`（r6 锁定，未改） |
| `upstream/ph1p100-pcie-ep-fpga/rtl/ep_side/codec/a1_frame_top.v` | `fa64cb487b4241241516183e7b8bfd71f96b30e54f5ed3d53ac239a2771e1ba2`（本轮修改） |
| `r7/td/a1_small_top.sdc` | `227dd39e3dba8834af510013c71242450d4571307267d6bac4938cb8ef696311`（与 r6 相同，未改） |

仅修改 `a1_frame_top.v`；core 保持 r6 hash。Bayer 映射、2 行块边界、CRC/长度/abort 语义未变。

## 2. 本轮 RTL 改动

- 在 `a1_frame_top.v` 增加 **寄存的 smem 写端口**：`smem_we_r/smem_waddr_r/smem_wdata_r`。I_EXP 仍每 cycle 处理 1 个输入字节，但把写使能/地址/数据寄存一拍，由独立 always 块在下一 cycle 写入 `smem`。
- 这样 `byte_k -> Bayer 地址/数据 -> smem we` 的组合链被切断；最后一个字节的写与块发布同沿完成，drain 侧的首读至少晚一拍，P3 整帧/A-B/stored/abort 均通过。
- 没有增加每字节气泡：1080p p1d1 仍 4,677,945 cycles，P2 comp 仍 81.067 MB/s。

## 3. G1 回归（新候选）

| 项 | 结果 | 证据 |
|---|---|---|
| 改动前基线 P2/P3 | PASS | `r7/p2-baseline/result.json`、`r7/p3-baseline/result.json` |
| P2 13/13 | **PASS** | `r7/p2/result.json` |
| P3 20/20 | **PASS** | `r7/p3/result.json`（`failures=[]`） |
| zlib + 自研 strict | 0 mismatch | P2/P3 日志 |
| `vlog` | Errors 0 / Warnings 0 | `r7/p2/logs/vlog.log`、`r7/p3/logs/vlog.log` |
| 1080p p1d1 | 4,677,945 cycles / 81,707 B / 540 blocks = **103.892 MB/s** | `r7/p3/runs/f1080p_p1d1/stats.txt` |
| P2 comp / rand | 81.067 / 178.351 MB/s | `r7/p2/result.json` |

cycles 与 r6 完全相同，未引入吞吐损失。

## 4. TD / G2

| run | SWNS | STNS | Fmax | 违例端点 | route |
|---|---:|---:|---:|---:|---|
| S1 | **-1.287 ns** | -73.092 ns | 151.057 MHz | 165 / 148,565 | not_run |

- S1 关键路径已**不在 frame_top**，而是 core：`pos_reg[2] -> hash_ok -> raddr_reg[10]`，9 级、6.556 ns、slack -1.287 ns（`raddr <= clamp_addr(pos+4, blk_n)` 的更新链）。
- frame_top 的 `byte_k -> smem we` 路径已被移除；TNS 从 r6 的 -416.270 改善到 **-73.092**，违例端点 404→165，但 WNS 仍 -1.287。
- 按 dispatch：r7 只允许改 `a1_frame_top.v`；S1 关键路径需要 core 修改，属于 `stop_conditions` 的“needed change outside a1_frame_top.v”，因此**不使用 S2、不布线**。`Routed`/routed WNS/TNS/HWNS/HTNS/资源/`report_cdc`/bitgen 均 **not_run**。
- 证据：`r7/td/00_all.tcl`、`r7/logs/td_stdout.log`、`r7/reports/syn_gate_timing_s1.rpt`、`r7/reports/syn_gate_timing.rpt`。
- 预算：综合 **1/2**、布线 **0/1**、TD wall 约 6.4 min（382.3 s），低于 90 min；无 bitgen、无下载、无 Flash、未上板。

## 5. 停止依据

dispatch `stop_conditions`：S1 关键路径需要 core 修改（r7 禁止），停止，不用 S2、不布线。未降频、未改 SDC、未加 false path/multicycle、未换 seed、未 bitgen/下载/Flash/上板。

## 6. 最小下一步（需用户/规划新授权，r8 不自动开）

剩余路径 `pos_reg[2] -> hash_ok -> raddr_reg[10]` 在 core：`raddr <= clamp_addr(pos+4, blk_n)` 与 `hash_ok`/S_SCAN 更新共用；需要 core 侧的寄存/预计算（例如把 raddr 更新拆成寄存的 +1 计数或消除 clamp 的比较链），并重新证明每符号 1 cycle 与吞吐。r7 的 frame_top smem 寄存可以保留。若不再改 core，则应向用户提交 route b（~150 MHz + CDC/异步 FIFO，硬门槛 ≥77.76 成立、97.2 不成立）的明确选择。不得降频/false path/multicycle/seed sweep。

## 7. 回退与复现

- 回退：`a1_frame_top.v` 回到 r6 `3c32803b41378629622ae3a709ab64373b2fb13286bfc7ea789e7e1dbf190961`；core 保持 r6 `24bfb7d5…4897`；删除 `r7/**` 与 `p4/result-r7.md`；r0–r6 manifest 与报告只读保留。
- 复现：
```powershell
upstream/ph1p100-pcie-ep-fpga/tools/codec/run_p2_r7.ps1
upstream/ph1p100-pcie-ep-fpga/tools/codec/run_p3_r7.ps1
subst X: "...\T10.a1-eng-freeze\r7\td"; subst Y: "<PROJECT_ROOT>"
cd X:\; D:\anlogic\TD_Release_2026.2\bin\td_commands_prompt.exe X:/00_all.tcl
```

## 8. 未测 / 不声明

Routed 时序、布线后资源、TD CDC、bitgen、板级、真实 RAW、双路 155.52 MB/s、G3/G4、生产集成：均 not_run/blocked。G1 PASS 不能替代 G2；r7 FAIL 不自动开 r8。