# T10.a1-eng-freeze r4 — bm/htab 预取后的 G2 结果（blocked）

- task_id: `T10.a1-eng-freeze` | round **r4** | run `20261020-0209_singleA_aplus_closedloop`
- 日期：2026-10-20 | 性质：离线、synthetic、无上板/下载/bitgen/Flash
- 唯一判定：**blocked — G1 回归 PASS；G2 综合仍 WNS<0（S2 SWNS -2.446 ns，Fmax 128.551 MHz，388/12,201 端点违例）；按 stop_conditions 未布线、无 CDC 工具报告、无第 3 次综合。T10 未完成，r4 FAIL 不自动开 r5。**

## 1. 冻结候选

| 文件 | SHA256 |
|---|---|
| `upstream/ph1p100-pcie-ep-fpga/rtl/ep_side/codec/a1_deflate_core.v` | `d76f77edf2cb6e0d9b9444d61f50e02d0d5ec1f6651ee8b30d52dc98034a1a0d` |
| `upstream/ph1p100-pcie-ep-fpga/rtl/ep_side/codec/a1_frame_top.v` | `3c32803b41378629622ae3a709ab64373b2fb13286bfc7ea789e7e1dbf190961`（未改） |
| `r4/td/a1_small_top.sdc` | `227dd39e3dba8834af510013c71242450d4571307267d6bac4938cb8ef696311`（r3 `227dd39e3dba8834af510013c71242450d4571307267d6bac4938cb8ef696311`，未改） |

仅修改 `a1_deflate_core.v`；端口、帧提交/abort、raw/xform/stream 长度与 CRC、zlib/fixed/stored 格式、Bayer 映射、TB 均未变。

## 2. RTL 改动

1. **bm_a 1-cycle 预取**：新增 `pcq_r`，在 `htab_pref` 周期寄存 `bm_a` 读数据；`htab_rd_addr` 的 S_PRE/S_REPOS 分支改用 `hash3(w0,w1,pcq_r)`，S_SCAN 分支改用 `hash3(w1,w2,pcq_r)`；S_SCAN literal 推进的 `w2 <= pcq_r`。这样 htab 地址与 htab 读全部由寄存器驱动，原 `raddr -> bm_a 异步读 -> hash3 -> htab_rd_addr -> htab_v 读 -> htab_rvalid` 链被切断，S_SCAN 仍每周期 1 个位置。
2. **S1 暴露预取地址路径后，S2 改为两拍前瞻**：新增 `praddr`，`praddr <= raddr + 2`，`pcq_r <= bm_a[praddr]`。bm_a 读地址来自寄存器 `praddr`，不再包含 `raddr` 的高 fanout 和 `clamp_addr` 比较/减法；S_PRE/S_REPOS 分别初始化 `praddr=2` / `pos+2`，保持窗口对齐。
3. 第一次 TD 启动因 `pcq_r` 同时出现在 htab always 块和主 always 块，TD 报 `net 'pcq_r[7]' is constantly driven from multiple places`；已改为单驱动（预取赋值移入主 always 块）后重跑。该次为 elaboration 失败，未形成综合结果。

## 3. G1 回归（新候选，未复用 r3 PASS）

| 项 | 结果 | 证据 |
|---|---|---|
| 改动前基线 P2/P3 | PASS | `r4/p2-baseline/result.json`、`r4/p3-baseline/result.json` |
| P2 13/13 | **PASS** | `r4/p2/result.json`（13 case + 2 bp + 2 abort/reset） |
| P3 20/20 | **PASS** | `r4/p3/result.json`（`verdict=PASS`，`failures=[]`） |
| zlib 1.2.13 + 自研 strict | 0 mismatch | P2/P3 日志 |
| `vlog` | Errors 0 / Warnings 0 | `r4/p2/logs/vlog.log`、`r4/p3/logs/vlog.log` |
| 1080p p1d1 | 4,677,941 cycles / 81,707 B / 540 blocks = **103.892 MB/s** | `r4/p3/runs/f1080p_p1d1/stats.txt`；≥77.76，对 97.2 余量约 +6.9% |
| P2 comp / rand | 81.084 / 178.354 MB/s | `r4/p2/result.json`；comp 仍 >77.76 |

与 r3 完全一致（cycles、stream_len、blocks 均未变）；帧/abort/stored/A-B 语义未变，预取未引入 S_SCAN 气泡。

## 4. TD / G2

| 项 | S1 | S2 |
|---|---:|---:|
| 综合 SWNS | **-2.107 ns** | **-2.446 ns** |
| 综合 STNS | -328.569 ns | -183.480 ns |
| Fmax | 134.409 MHz | 128.551 MHz |
| 违例端点 | 489 / 12,162 | 388 / 12,201 |
| 综合 wall | 75.589 s | 67.505 s |
| route | not_run（WNS<0） | not_run（WNS<0） |

- 工具/器件/约束：TD `Release_2026.2` build `6.2.3.210850`，`PH1P100SBG484 -3`，`a1_eng_top`，187.5 MHz（5.333 ns），SDC 未改；无 false path/multicycle/clock group/seed sweep。
- S1 关键路径：`raddr_reg[0] -> clamp_addr -> bm_a 异步读 -> pcq_r`，10 级、7.376 ns（预取地址本身成为新瓶颈）。
- **S2 关键路径**：`len_r_reg[1] -> 长度码/extra bits -> candidate packer shift (`left_shift1036`) -> cstage/accw -> cmem 写数据`，11 级、7.578 ns、slack -2.446 ns。原 htab 路径已不再是关键路径；TNS 从 r3 的 -417.972 改善到 **-183.480 ns**，违例端点 508→388，但 WNS 因新暴露的 packer 路径略差。
- `Routed`、routed WNS/TNS/HWNS/HTNS、布线后资源、`report_cdc`、`check_timing`、bitgen：**not_run**。`report_cdc` 只在 phy 完成后调用，本轮未进入 phy；只能声明结构为单时钟 `clk`，不能声明 TD CDC 工具 PASS。
- 证据：`r4/td/00_all.tcl`、`r4/logs/td_stdout_s1.log`、`r4/logs/td_stdout.log`（S2）、`r4/logs/td_stdout_elab_fail.log`、`r4/logs/syn_elab_fail_run.log`、`r4/logs/syn_s2_run.log`、`r4/reports/syn_gate_timing_s1.rpt`、`syn_gate_timing_s2.rpt`。
- 预算：实际综合 2 次（S1/S2），布线 0/1，总 wall 约 2–3 min；无 bitgen、无下载、无 Flash、未上板。
- r3 证据完整性：r3 manifest: only the expected core RTL hash differs (r3 fb6e59e4 -> r4 d76f77ed); all other r3 artifacts still match.

## 5. 停止依据

dispatch `stop_conditions`：S2 综合仍 WNS/TNS<0 → 停止，不布线，无第 3 次综合。未降频、未改 SDC、未加 false path/multicycle、未换 seed、未 bitgen/下载/Flash/上板。

## 6. 最小下一步（需用户/规划新授权，r5 不自动开）

在不增加 S_SCAN 每周期的前提下拆 `len_r -> 长度码/lval -> left_shift -> cstage/accw -> cmem` 的 candidate packer 路径：可把 `len_r` 对应的 `lval/ltot` 或 `accw` 的移位结果加一拍流水，并保持 match 路径 2 cycle；也可把长度码/extra-bit 生成与 packer 移位分到不同周期。htab/bm 预取保留。match-heavy P2 comp 当前 81.084 MB/s，余量很小，任何新流水都必须复核 ≥77.76 MB/s。不得用降频/false path/multicycle/seed sweep 换 PASS。

## 7. 回退与复现

- 回退：`a1_deflate_core.v` 回到 r3 `fb6e59e44544bb06faab868cdb759664fbf53b66c34a9ca271dcfb171efb4ecf`；删除 `r4/**` 与 `p4/result-r4.md`；r0–r3 manifest 与报告只读保留。
- 复现：
```powershell
upstream/ph1p100-pcie-ep-fpga/tools/codec/run_p2_r4.ps1
upstream/ph1p100-pcie-ep-fpga/tools/codec/run_p3_r4.ps1
subst X: "...\T10.a1-eng-freeze\r4\td"; subst Y: "<PROJECT_ROOT>"
cd X:\; D:\anlogic\TD_Release_2026.2\bin\td_commands_prompt.exe X:/00_all.tcl
```

## 8. 未测 / 不声明

Routed 时序、布线后资源、TD CDC、bitgen、板级、真实 RAW、双路 155.52 MB/s、G3/G4、生产集成：均 not_run/blocked。G1 PASS 不能替代 G2；r4 FAIL 不自动开 r5。