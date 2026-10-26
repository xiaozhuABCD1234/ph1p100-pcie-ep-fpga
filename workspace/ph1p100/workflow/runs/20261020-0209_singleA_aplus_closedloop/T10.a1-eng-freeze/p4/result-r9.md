# T10.a1-eng-freeze r9 — htab pos+3 最终局部轮（blocked）

- task_id: `T10.a1-eng-freeze` | round **r9** | run `20261020-0209_singleA_aplus_closedloop`
- 日期：2026-10-21 | 性质：离线、synthetic、无上板/下载/bitgen/Flash
- 唯一判定：**blocked — G1 回归 PASS；G2 综合 WNS -0.434 ns / TNS -45.639 ns（2/2 综合，0/1 布线，按 stop_conditions 未 route）。r9 FAIL 不自动 r10。**

## 0. 中断续接与基线恢复

接管时 `a1_deflate_core.v` mtime 2026-10-21 13:34，sha256 `e213c001…43b5`，与 r9/p2、r9/p3（02:15/02:23）记录不一致，且两份旧结果为 FAIL（p2 边界匹配缺失、p3 stall_abort `p1_no_pending_word`）。该状态是中断会话留下的中间态：S_SCAN 的 htab 写入仍是旧打包 `{tag,pos,w0,w1,w2}`（53 bit 零扩展），而旁路/读侧已按 `{tag,pos+3,pos,w0,w1,w2}` 解释，导致 tag/字段错位。

r8 冻结 core 的精确字节在 run 内无快照，upstream codec 目录未纳入 git，无法按哈希还原 `4e1e97b8…ec9c`。因此按“先恢复可工作基线”的意图重建：修正打包一致性后重跑，P2/P3 结果与 r8 **逐字节一致**（`result.json` sha256 与 r8 相同），据此认定功能基线已恢复为 r8 等价。

## 1. 冻结候选

| 文件 | SHA256 |
|---|---|
| `upstream/…/rtl/ep_side/codec/a1_deflate_core.v` | `af6ab54b47556d0051548ff40eea56ee3957602ad35440fb3eeb25dabf310b03` |
| `upstream/…/rtl/ep_side/codec/a1_frame_top.v` | `fa64cb487b4241241516183e7b8bfd71f96b30e54f5ed3d53ac239a2771e1ba2`（锁定，未改） |
| `r9/td/00_all.tcl` = `r9/td2/00_all.tcl` | `34192532973bb86a3d1a7e5fc81549593a16df11012ef5fbd55e87440c1a388e` |
| `r9/td/a1_small_top.sdc` | `227dd39e3dba8834af510013c71242450d4571307267d6bac4938cb8ef696311`（与 r8 相同，未改） |

仅修改 `a1_deflate_core.v` 的 htab 读地址 / pos+3 路径；协议/端口/帧语义/CRC/长度/abort/Bayer/时钟均未改。

## 2. 本轮 RTL 改动（一条实现路径：pos+3 存入 htab）

1. **htab 同时存 pos+3 与 pos**：条目 `{blk_tag, pos+3, pos, w0,w1,w2}`，旁路数据 `htab_we_data` 与 S_SCAN 写入统一使用同一打包，hit 侧 `fq_r <= bm_b[hent[49:37]]` 直接取 pos+3，去掉 htab 读后加法。
2. **cq_r 捕获改用寄存器地址**：`cq_r <= bm_a[{enc_bank, raddr}]`。S_SCAN 期间恒有 `raddr == pos+3`（S_PRE/S_REPOS 末尾装入 clamp(pos+3)，逐位置自增；`pos+3 >= blk_n` 的边界由 hit 分支提前转 S_MLEN，不读 cq_r），因此与 `bm_a[pos+3]` 等效，但移除了 pos 扇出 + 加法器。

## 3. G1 回归

| 项 | 结果 | 证据 |
|---|---|---|
| P2 | **13/13 PASS**，verdict PASS | `r9/p2/result.json`（sha256 与 r8 相同 `6ab4d148…d130`） |
| P3 | **20/20 PASS**，`failures=[]` | `r9/p3/result.json`（sha256 与 r8 相同 `c7c0045e…b2a4`） |
| zlib + 自研 strict | 0 mismatch | P2/P3 日志 |
| `vlog` | Errors 0 / Warnings 0 | `r9/p2/logs/vlog.log`、`r9/p3/logs/vlog.log` |
| P2 comp / rand | 81.067 / 178.351 MB/s | `r9/p2/result.json` |
| 1080p p1d1 | 4,677,945 cycles / 540 blocks = **103.892 MB/s** | `r9/p3/result.json` |

P2/P3 的 result.json 与 r8 逐字节相同（含全部 `stream_sha256`、cycles、统计），即功能与吞吐相对 r8 无变化，p1d1 循环数等于 r8 且远低于 4,677,945 门槛要求的上限。

## 4. TD / G2

| 尝试 | SWNS | STNS | 结果 |
|---|---:|---:|---|
| S1（首次，rebuild 前） | -0.789 ns | -22.934 ns | 69 违例端点；不布线 |
| S2（末次） | **-0.434 ns** | **-45.639 ns** | 不布线（停止条件） |

- S1 关键路径为 `pos_reg[1] -> (+3) -> bm_a -> cq_r_reg[1]`（8 级、6.058 ns），据此做第 2 项修正。
- S2 关键路径仍为 8 级、5.703 ns（含 2 个 ADDER），WNS -0.434 ns。
- `Routed`、routed WNS/TNS/HWNS/HTNS、布线后资源、`report_cdc`、`check_timing`、bitgen：**not_run**（综合 WNS<0，按停止条件不 launch phy）。
- 预算：综合 **2/2**、布线 **0/1**、TD wall ≈ 7.3 + 10.7 min（含 1 次 `create_project` 后 PRJ-8642 工具错误、换 `r9/td2` 目录重跑，未产生综合结果，不计为综合尝试），总 < 90 min；无 bitgen/下载/Flash/上板。
- 证据：`r9/logs/td_stdout.log`、`td_stdout_s2.log`、`td_stdout_s2b.log`、`r9/reports/syn_gate_timing_s2.rpt`、`r9/td2/a1_eng_freeze_r9_Runs/syn_1/`。

## 5. 停止依据

dispatch `stop_conditions`：S2 综合仍 WNS/TNS<0 → 停止，不布线，无第 3 次综合；r9 为绝对最后一次局部补丁，FAIL 不自动 r10。未降频、未改 SDC、未加 false path/multicycle、未换 seed、未 bitgen/下载/Flash/上板。

## 6. 最小下一步（需用户明确选择，r9 不自动开）

- 路线 (b)：145–165 MHz A+ 小顶 + 异步 FIFO/CDC 桥接到 187.5 MHz 系统；需用户明确同意时钟架构变更，并接受只保证 ≥77.76 MB/s、不保证 97.2。
- 或接受当前 ⚠（G2 未闭合）并保留 r8/r9 证据。
- 不得降频、false path/multicycle/seed sweep 或自动 r10。

## 7. 回退与复现

- 回退：`a1_deflate_core.v` 恢复到 r8 `4e1e97b8…ec9c`（需 r8 期间的实际副本；本 run 无快照，只能按结果哈希等价重建）；frame_top 保持 `fa64cb48…1ba2`。
- 复现：
```powershell
upstream/ph1p100-pcie-ep-fpga/tools/codec/run_p2_r9.ps1
upstream/ph1p100-pcie-ep-fpga/tools/codec/run_p3_r9.ps1
subst X: "...\T10.a1-eng-freeze\r9\td2"; subst Y: "<PROJECT_ROOT>"
cd X:\; D:\anlogic\TD_Release_2026.2\bin\td_commands_prompt.exe X:/00_all.tcl
```

## 8. 未测 / 不声明

Routed 时序、布线后资源、TD CDC、bitgen、板级、真实 RAW、双路 155.52 MB/s、G3/G4、生产集成：均 not_run/blocked。G1 PASS 不能替代 G2。
