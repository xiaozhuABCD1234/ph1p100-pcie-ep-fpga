# T10.a1-eng-freeze r5 — candidate packer/输出级架构重排（blocked）

- task_id: `T10.a1-eng-freeze` | round **r5** | run `20261020-0209_singleA_aplus_closedloop`
- 日期：2026-10-20 | 性质：离线、synthetic、无上板/下载/bitgen/Flash
- 唯一判定：**blocked — G1 回归 PASS；G2 综合 best WNS -0.949 ns（S2），仍 <0；3/3 综合、0/1 布线；按 stop_conditions 未 route；r5 FAIL，不自动 r6。**

## 1. 冻结候选

| 文件 | SHA256 |
|---|---|
| `upstream/ph1p100-pcie-ep-fpga/rtl/ep_side/codec/a1_deflate_core.v` | `a6f323ab96c408c667728138719f8370bb50ef402f3f76373049cd76d0f6dcae` |
| `upstream/ph1p100-pcie-ep-fpga/rtl/ep_side/codec/a1_frame_top.v` | `3c32803b41378629622ae3a709ab64373b2fb13286bfc7ea789e7e1dbf190961`（未改） |
| `r5/td/a1_small_top.sdc` | `227dd39e3dba8834af510013c71242450d4571307267d6bac4938cb8ef696311`（与 r4 相同，未改） |

当前 RTL 是 **S2 最佳候选**（`a6f323ab…`）；S3 的 `ext_end_r` 实验已回退。仅修改 `a1_deflate_core.v`；端口、帧提交/abort、raw/xform/stream 长度与 CRC、zlib/fixed/stored 格式、Bayer 映射、TB 均未变。

## 2. 架构重排

1. **candidate packer 三级流水**：p0 寄存码值/bit 数/预符号 bit offset；p1 寄存 `left_shift` 结果；p2 做 `cacc` 合并与 16-bit word 选择。`cmem` 写数据先进入 **4-entry write FIFO**，由 FIFO head 写入 cmem，ERAM 写路径不再与 shift/accumulate 同拍。
2. **输出 skid FIFO**：新增 4-entry `opq_mem`。FSM 只负责把 `{last,bits,value}` 入队，bit packer 从队头取数并写 `fifo_mem`；`S_TRAIL` 等待 `opq_count==0` 后再做最终对齐。
3. **控制/数据分离**：块尾 `S_EODONE` 用 `p0_valid/p1_valid/wq_count` 等待流水与 FIFO 排空，再用 `pbit_off` 写最终 partial word；abort/reset 清空所有 packer/opq 状态。
4. 调试中修正了三个功能问题：nbw=1/clane=0 时 `cstage` 未装载、`p2_we` 条件过宽、opq 入队侧缺少 `opq_bit_off` 导致 S_SALIGN 用错 `obits`。最终 P2/P3 全通过。

## 3. G1 回归（新候选，未复用 r4 PASS）

| 项 | 结果 | 证据 |
|---|---|---|
| 改动前基线 P2/P3 | PASS | `r5/p2-baseline/result.json`、`r5/p3-baseline/result.json` |
| P2 13/13 | **PASS** | `r5/p2/result.json`（13 case + 2 bp + 2 abort/reset） |
| P3 20/20 | **PASS** | `r5/p3/result.json`（`verdict=PASS`，`failures=[]`） |
| zlib 1.2.13 + 自研 strict | 0 mismatch | P2/P3 日志 |
| `vlog` | Errors 0 / Warnings 0 | `r5/p2/logs/vlog.log`、`r5/p3/logs/vlog.log` |
| 1080p p1d1 | 4,677,945 cycles / 81,707 B / 540 blocks = **103.892 MB/s** | `r5/p3/runs/f1080p_p1d1/stats.txt`；≥77.76，对 97.2 余量约 +6.9% |
| P2 comp / rand | 81.067 / 178.351 MB/s | `r5/p2/result.json`；comp 仍 >77.76 |

与 r4 相比仅 +4 cycles（4,677,941 → 4,677,945），无每符号气泡；stored/abort/reset/A-B/multi-frame 语义未变。

## 4. TD / G2

| run | RTL | SWNS | STNS | Fmax | 违例端点 | route |
|---|---|---:|---:|---:|---:|---|
| S1 | `8e9e674c…`（opq 前） | **-0.957 ns** | -157.278 ns | 158.983 MHz | 434 / 143,394 | not_run |
| S2 | `a6f323ab…`（当前） | **-0.949 ns** | -303.718 ns | 159.185 MHz | 420 / 143,419 | not_run |
| S3 | `bb935bdc…`（ext_end，已回退） | **-1.864 ns** | -177.386 ns | 138.947 MHz | 405 / 143,419 | not_run |

- S2 关键路径：`raddr_reg[2] -> bm_a 异步读 -> cq -> S_EXT/state_reg.ce`，8 级、6.215 ns、slack -0.949 ns。packer 的 `len_r -> lval -> shift -> cmem` 长路径已被拆掉；当前瓶颈转移到 match-extension 的 `cq` 比较与 state 使能。
- S3 的 `ext_end_r` 预计算没有改善，反而把 WNS 推到 -1.864；已回退到 S2 RTL（`a6f323ab…`）。
- `Routed`、routed WNS/TNS/HWNS/HTNS、布线后资源、`report_cdc`、`check_timing`、bitgen：**not_run**。`report_cdc` 只在 phy 完成后调用，本轮未进入 phy；只能声明结构为单时钟 `clk`。
- 证据：`r5/td/00_all.tcl`、`r5/logs/td_stdout_s1.log`、`td_stdout_s2.log`、`td_stdout.log`（S3）、`r5/reports/syn_gate_timing_s1.rpt`、`syn_gate_timing_s2.rpt`、`syn_gate_timing_s3.rpt`。
- 预算：综合 **3/3**、布线 **0/1**、TD wall 约 18 min（S1 353 s、S2 353 s、S3 385 s），低于 150 min；无 bitgen、无下载、无 Flash、未上板。

## 5. 停止依据

dispatch `stop_conditions`：S3 综合仍 WNS/TNS<0 → 停止，不布线，无第 4 次综合。best WNS -0.949 ns 虽 > -1 ns，但任何 WNS<0 都是 FAIL/blocked，不自动 r6。未降频、未改 SDC、未加 false path/multicycle、未换 seed、未 bitgen/下载/Flash/上板。

## 6. 最小下一步（需用户/规划新授权，r6 不自动开）

剩余路径是 `raddr -> bm_a 异步读 -> cq -> S_EXT/state`。下一轮需要**新的微架构**，而不是再局部预计算：例如对 match-extension 的下一字节/比较做吞吐中性的寄存器切片（speculative 1-cycle lookahead，必须证明每符号 1 cycle），或把 S_EXT 的 state 决策从 `cq` 组合路径中分离；同时保留当前 packer/opq 结构。match-heavy P2 comp 仅 81.07 MB/s，任何新流水都必须复核 ≥77.76 MB/s。不得降频/false path/multicycle/seed sweep。

## 7. 回退与复现

- 回退：`a1_deflate_core.v` 回到 r4 `d76f77edf2cb6e0d9b9444d61f50e02d0d5ec1f6651ee8b30d52dc98034a1a0d`；删除 `r5/**` 与 `p4/result-r5.md`；r0–r4 manifest 与报告只读保留。
- 复现：
```powershell
upstream/ph1p100-pcie-ep-fpga/tools/codec/run_p2_r5.ps1
upstream/ph1p100-pcie-ep-fpga/tools/codec/run_p3_r5.ps1
subst X: "...\T10.a1-eng-freeze\r5\td"; subst Y: "<PROJECT_ROOT>"
cd X:\; D:\anlogic\TD_Release_2026.2\bin\td_commands_prompt.exe X:/00_all.tcl
```

## 8. 未测 / 不声明

Routed 时序、布线后资源、TD CDC、bitgen、板级、真实 RAW、双路 155.52 MB/s、G3/G4、生产集成：均 not_run/blocked。G1 PASS 不能替代 G2；r5 FAIL 不自动开 r6。