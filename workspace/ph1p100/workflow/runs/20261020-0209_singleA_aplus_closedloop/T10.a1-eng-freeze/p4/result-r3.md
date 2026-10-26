# T10.a1-eng-freeze r3 — G2 时序收敛结果（blocked）

- task_id: `T10.a1-eng-freeze` | round **r3** | run `20261020-0209_singleA_aplus_closedloop`
- 日期：2026-10-20 | 性质：离线、synthetic、无上板/下载/bitgen/Flash
- 唯一判定：**blocked — G1 回归 PASS；G2 综合仍 WNS<0（S2 SWNS -2.374 ns，Fmax 129.752 MHz，508/10,476 端点违例）；按 stop_conditions 未布线、无 CDC 工具报告、无第 3 次综合。T10 未完成。**

## 1. 冻结候选

| 文件 | SHA256 |
|---|---|
| `upstream/ph1p100-pcie-ep-fpga/rtl/ep_side/codec/a1_deflate_core.v` | `fb6e59e44544bb06faab868cdb759664fbf53b66c34a9ca271dcfb171efb4ecf` |
| `upstream/ph1p100-pcie-ep-fpga/rtl/ep_side/codec/a1_frame_top.v` | `3c32803b41378629622ae3a709ab64373b2fb13286bfc7ea789e7e1dbf190961`（未改） |
| `r3/td/a1_small_top.sdc` | `227dd39e3dba8834af510013c71242450d4571307267d6bac4938cb8ef696311`（r2 `227dd39e3dba8834af510013c71242450d4571307267d6bac4938cb8ef696311`，未改） |

仅修改 `a1_deflate_core.v`；外部端口、帧提交/abort、raw/xform/stream 长度与 CRC、zlib/fixed/stored 格式、Bayer 映射、TB 均未变。

## 2. 本轮 RTL 改动

1. **S_MCHK（state 26）替换原 S_MDIST 的 abort 比较**：`S_MLEN` 只寄存 `dval_r/dtot_r/pos_next_r/rem_next_r/thresh_match_r`；`S_MCHK` 用寄存后的 `cand_bits + dtot_r` 与 `thresh_match_r` 比较，再决定 `S_DECIDE` 或 `S_REPOS/S_EOB`。match 路径仍为 2 cycle，没有引入每 match 的额外气泡。
2. **abort 预测阈值预计算**：新增 `thresh_base/thresh_lit`。`S_SCAN` literal 判断改为 `cand_bits + litlen >= thresh_lit`，去掉原 `blk_n-pos-len` 的 13-bit 减法/移位/加法链；`thresh_match_r = thresh_base + (len_r<<3)` 在 `S_MLEN` 寄存。
3. **Adler-32 宽累加 + 块末折叠**：输入字节先寄存到 `adler_data_r`，块内用 `adler_a_w[21:0]/adler_b_w[34:0]` 累加，块末 3 cycle 按 `2^16≡15、2^32≡225 (mod 65521)` 折叠；去掉每字节两次 modulo 比较/减法。块末 `in_ready` 拉低约 6 cycle/块（540 块，吞吐影响 <0.1%）。
4. **S_SCAN literal 数据路径与 hit/hash_ok 解耦**：`cp_value/cp_nbits` 在 S_SCAN 恒为 literal 码，`cp_en` 仍由 `!hit && pos<blk_n` 控制；去掉 hash_ok 到 cmem 写数据的 mux。

## 3. G1 回归（新候选，未复用 r2 PASS）

| 项 | 结果 | 证据 |
|---|---|---|
| 改动前基线 P2/P3 | PASS | `r3/p2-baseline/result.json`、`r3/p3-baseline/result.json` |
| P2 13/13 | **PASS** | `r3/p2/result.json`（`verdict=PASS`，13 case + 2 bp + 2 abort/reset） |
| P3 20/20 | **PASS** | `r3/p3/result.json`（`verdict=PASS`，`failures=[]`） |
| zlib 1.2.13 + 自研 strict | 0 mismatch | P2/P3 日志 |
| `vlog` | Errors 0 / Warnings 0 | `r3/p2/logs/vlog.log`、`r3/p3/logs/vlog.log` |
| 1080p p1d1 | 4,677,941 cycles / 81,707 B / 540 blocks = **103.892 MB/s** | `r3/p3/runs/f1080p_p1d1/stats.txt`；≥77.76，对 97.2 余量约 +6.9% |
| 1080p 全 stored | 2,594,706 B / 103.879 MB/s | P3 |
| P2 comp / rand | 81.084 / 178.354 MB/s | `r3/p2/result.json`；comp 仍 >77.76 |

与 r2 的 4,677,941 cycles、81,707 B、540 blocks 完全一致；帧/abort/stored/A-B 语义未变。

## 4. G2 / TD

| 项 | S1 | S2 |
|---|---:|---:|
| 综合 SWNS | **-2.853 ns** | **-2.374 ns** |
| 综合 STNS | -531.286 ns | -417.972 ns |
| Fmax | 122.160 MHz | 129.752 MHz |
| 违例端点 | 515 / 10,478 | 508 / 10,476 |
| 综合 wall | 55.453884 s | 58.451159 s |
| route | not_run（WNS<0） | not_run（WNS<0） |

- 工具：TD `Release_2026.2` build `6.2.3.210850`，`PH1P100SBG484 -3`，`a1_eng_top`，187.5 MHz（5.333 ns）SDC 未改；无 false path/multicycle/clock group，无 seed sweep。
- S1 关键路径：`pos_reg[2] → hash_ok → mux → shift → cmem ERAM`（11 级，7.642 ns）。S2 改动后该路径消失。
- **S2 关键路径**：`raddr_reg[2] → bm_a 异步读 → hash3 → htab_rd_addr[2]（fanout 1025） → htab_v 读 → htab_rvalid_reg`，9 级、7.643 ns、slack -2.374 ns。剩余瓶颈是 hash 表预取（块 RAM 读 → 组合 hash → 块 RAM 读）。
- `Routed`、routed WNS/TNS/HWNS/HTNS、布线后资源、`report_cdc`、`check_timing`、bitgen：**not_run**。`report_cdc` 只在 phy 完成后调用，本轮未进入 phy；只能声明结构为单时钟 `clk`，不能声明 TD CDC 工具 PASS。
- TD 记录：`r3/td/00_all.tcl`、`r3/logs/td_stdout_s1.log`、`r3/logs/td_stdout.log`（S2）、`r3/reports/syn_gate_timing_s1.rpt`、`syn_gate_timing_s2.rpt`。两次均以 `A1_TD_R3_DONE` 结束；Start-Process 包装未取到 ExitCode，未据此声称 exit=0。
- 一次即时启动因 tcl UTF-8 BOM 报 `invalid command name "锘?"`，改为 ASCII 后重跑；该次未进入综合，不计综合尝试。实际综合 2 次、布线 0 次，TD 总 wall 约 2–4 min，远低于 120 min 预算。

## 5. 停止依据

dispatch `stop_conditions`：S2 综合仍 WNS/TNS<0 → 停止，不布线，无第 3 次综合。未降频、未改 SDC、未加 false path/multicycle、未换 seed、未 bitgen/下载/Flash/上板。

## 6. 最小下一步（需规划新授权 / r4）

在不增加 S_SCAN 每周期的前提下拆掉 `raddr → bm_a 异步读 → hash3 → htab_rd_addr → htab 读 → htab_rvalid`：可把 bm 读数据或 htab 读地址做 1-cycle 预取（利用 `w0/w1/w2/cq` 已有的流水关系），或把 htab 查找改成基于寄存后地址的两级预取；必须保持 77.76 MB/s（match-heavy 数据当前仅 81.08 MB/s，余量很小）。不得用降频/false path/multicycle/seed sweep 换 PASS。

## 7. 回退与复现

- 回退：`a1_deflate_core.v` 回到 r2 `585664deb28c24bd08708c134347c2624d9068b2f2edca60d522ad6745d84f18`；删除 `r3/**` 与 `p4/result-r3.md`；r0/r1/r2 manifest 与报告只读保留。
- 复现：
```powershell
upstream/ph1p100-pcie-ep-fpga/tools/codec/run_p2_r3.ps1
upstream/ph1p100-pcie-ep-fpga/tools/codec/run_p3_r3.ps1
subst X: "...\T10.a1-eng-freeze\r3\td"; subst Y: "<PROJECT_ROOT>"
cd X:\; D:\anlogic\TD_Release_2026.2\bin\td_commands_prompt.exe X:/00_all.tcl
```

## 8. 未测 / 不声明

Routed 时序、布线后资源、TD CDC、bitgen、板级、真实 RAW、双路 155.52 MB/s、G3/G4、生产集成：均 not_run/blocked。G1 PASS 不能替代 G2。