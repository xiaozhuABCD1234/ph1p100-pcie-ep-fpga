# T10.a1-g2-2cyc r0（rev r0-c）— frame_top dq_r 读地址寄存已修好；残留违例转入 core stage-1 路径，综合预算 3/3 用尽，blocked

- task_id `T10.a1-g2-2cyc` | round **r0**（新包首次验收，不是 r11）| 范围修订 **r0-c**（规划窄扩：仅 frame_top 的 dq_r 读数据/rd_issue 扇出）
- 日期 2026-10-22 | 离线 synthetic，无 bitgen/下载/Flash/上板
- 唯一判定：**blocked — G1 与 r10 逐位一致（P2 13/13、P3 20/20、0 mismatch、vlog 0/0；13+20 用例 stream SHA 与 run_cycles 全部相同；1080p 4,677,945 cycles、P2 comp 81.067 MB/s）；G2 S3 WNS -0.156 ns / TNS -10.977 ns / 92 违例端点，且 S3 中 frame_top 的 dq_r/rd_issue 路径已完全消失（r0-c 生效），残留 10 个最差端点全部转为 core 的 `s1_pos_r → s1_ok → htab_rd_addr → htab_rdata/rvalid` 路径；综合 3/3 用尽，无第 4 次，按 stop_conditions 不布线（布线 0/1）。**

## 1. 冻结候选（SHA256）

| 文件 | SHA256 | 状态 |
|---|---|---|
| `upstream/…/rtl/ep_side/codec/a1_deflate_core.v` | `e3484a6072bd0fd9a3f82e15920b203f880363348436a0bcf257ede96f960aee` | r0-b 起锁定，r0-c 未改 |
| `upstream/…/rtl/ep_side/codec/a1_frame_top.v` | `18d51b1b80002e3549b6afd74956cff9d323d0a0272a7a08d617365a01611cbe` | r0-c 唯一改动 |
| `r0/td/a1_small_top.sdc`（锁定字节拷贝） | `227dd39e3dba8834af510013c71242450d4571307267d6bac4938cb8ef696311` | 未改 |

manifest：`T10.a1-g2-2cyc/CANDIDATE-MANIFEST-g2-2cyc.json`（S1/S2 报告与日志全部保留）

## 2. r0-c RTL 改动（仅 dq_r 读地址/扇出）

1. 新增 `function [15:0] raddr_of(idx, ns, bank) = (idx < ns) ? (idx + (bank ? NSAMP : 0)) : 16'd0;` 与 `reg [15:0] rd_addr`：把原先组合读索引
   `smem[(rd_issue < n_samp) ? (rd_issue + (rd_bank ? NSAMP : 0)) : 16'd0]`
   在 4 个 `rd_issue` 赋值点（D_IDLE / D_GATH-primed / D_GATH / D_EMIT）同条件提前一拍算入 `rd_addr`，读口改为 `dq_r <= smem[rd_addr]`。
2. 语义不变：地址表达式相同、n_samp/rd_bank 在赋值点与读点取值相同（n_samp/rd_bank 只在 D_IDLE / 块末 D_EMIT 变化，而这两处不产生新读地址），读延迟仍为 1 拍；未改端口/帧语义/CRC/长度/abort/Bayer/valid-ready。
3. 效果：把 `rd_issue → fanout-1920 → smem DRAM → dq_r` 的 5.361 ns/7 级组合路径变为“寄存器地址 → DRAM → dq_r”。

## 3. G1 回归（r0-c 改动后实测，全部 PASS 且与 r10 逐位一致）

| 项 | 结果 | 证据 |
|---|---|---|
| P2 | **13/13 PASS**（+bp/gapbp/abort/reset PASS） | `r0/p2/result.json`（01:02） |
| P3 | **20/20 PASS**，`failures=[]` | `r0/p3/result.json` |
| zlib + strict | 0 mismatch | P2/P3 日志 |
| vlog | Errors 0 / Warnings 0 | 两侧 `logs/vlog.log` |
| SHA / cycles | 13 P2 + 20 P3 用例 stream SHA 与 run_cycles 与 r10 **完全相同**（`diffs=[]`）；1080p p1d1 `b769cc66…08ff`、**4,677,945** cycles | 逐用例比较 |
| P2 comp / rand | **81.067 / 178.351 MB/s** | `p2/result.json` |
| 门槛 | 4.678M ≤ 5.0M（97.2）≤ 6.25M；comp ≥ 77.76 | 全部满足 |

## 4. TD / G2（综合 3/3、布线 0/1、3 会话、wall ≈ 38.8 min）

| 尝试 | 版本 | SWNS | STNS | 违例端点 | 最差端点/路径 | 布线 |
|---|---|---:|---:|---:|---|---|
| S1 | r0-a(core pcq2) | -2.424 ns | — | — | core：`raddr → bm DRAM → hash3 → htab_rd_addr(fanout 1409)` 7.693 ns | 否 |
| S2 | r0-b(core x1/x2) | -0.092 ns | -3.070 ns | 35 | **frame_top**：`rd_issue_reg[8] → fanout1920 → smem DRAM → dq_r_reg[0..9].d` 5.361 ns | 否 |
| S3 | **r0-c(+frame_top rd_addr)** | **-0.156 ns** | -10.977 ns | 92 | **core**：`s1_pos_r[4] → s1_pos_r+2<blk_n(s1_ok) → bypass select → htab_rd_addr(fanout 1042) → 存储 → htab_rdata/htab_rvalid` 5.425 ns/7 级；**frame_top 的 dq_r/rd_issue 端点 0 个** | 否 |

- **r0-c 目标达成**：S2 的 frame_top `dq_r` 路径（当时 WNS）在 S3 中完全消失，说明 `rd_addr` 寄存有效。
- **残留**在 core：`s1_ok = (s1_pos_r + 13'd2 < blk_n)`（13 位加法+比较）驱动 `hins_ok_r` 与同址 bypass select，再经 `htab_rd_addr`（扇出 1042）到 `htab_rdata/rvalid`。S2 时该路径的 slack 优于 -0.092，S3 变为 -0.156 —— core RTL 两次完全相同（e3484a60），差异来自综合解/优化路径（S3 运行 24.3 min vs S2 8.1 min），属综合方案方差。
- `Routed` 时序/资源/`report_cdc`/`check_timing`/bitgen：**not_run**（三次综合 WNS<0，禁止布线）。
- 未降频、未改 SDC、无 false path/multicycle、无 seed sweep、未做第 4 次综合。

## 5. 停止依据与最小下一步（交原规划）

- dispatch：综合 ≤3 且 WNS/TNS≥0 才布线；S3 仍 <0 → 停止并 blocked。综合预算已 3/3 用尽。
- 下一轮（新包/新授权，本包不再动 RTL）最小具体改动：
  1. 在块装载（S_WAIT）预计算 `lim2 = blk_n - 13'd2` 存寄存器，改 `s1_ok = (s1_pos_r <= lim2)`，去掉 13 位加法（S3 该链约 1.6 ns 的 ADDER 段），只保留一次比较；
  2. 可选：把 `s1_ok` 从同址 bypass select 中移出（bypass 仅用地址相等 + 已寄存的 `hins_ok_r`；插入本身仍由 s1_ok 门控），进一步缩短 `htab_rd_addr → htab_rdata` 的 mux 选择；
  3. 再综合并（WNS/TNS≥0 时）用 1 次布线。frame_top 已无需再改。
- 不建议：降频、放宽 5.333 ns、false path/multicycle、seed sweep、第 4 次综合。

## 6. 复现

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File upstream\ph1p100-pcie-ep-fpga\tools\codec\run_p2_g2r0.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File upstream\ph1p100-pcie-ep-fpga\tools\codec\run_p3_g2r0.ps1
subst X: "<...>\T10.a1-g2-2cyc\r0\td"; subst Y: "<PROJECT_ROOT>"
cd X:\; $env:A1_TD_TAG="s3"; D:\anlogic\TD_Release_2026.2\bin\td_commands_prompt.exe X:/00_all.tcl
```

## 7. 证据偏差（诚实记录）

- r0-a 期间 `a1_p2_gen_r3.py` 因 `A1_P2_RUN` 多一级 `..` 把 cases 写到 `workflow/runs/T10.a1-g2-2cyc/r0/p2`；该目录已**移动**（未删除）到 `C:\Users\czz\AppData\Local\Temp\opencode\stray-T10.a1-g2-2cyc-r0-p2-cases`，随后用 `../T10.a1-g2-2cyc/r0/p2` 在本包重新生成并通过。
- S3 综合墙钟 24.3 min（S1/S2 约 6–8 min），本文已注明；同一 core RTL 在 S2/S3 的 core slack 相差约 0.06 ns，归因于综合方案差异而非 RTL 变化。

## 8. 未测 / 不声明

Routed 时序、布线后资源、CDC 报告、bitgen、板级、真实 RAW、双路、G3/G4、生产集成：**not_run**。G1 PASS 不代表 G2。
