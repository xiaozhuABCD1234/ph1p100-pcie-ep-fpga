# T10.a1-area-map r0 — cmem 单写口/ERAM 修复成功（slice 15,108，容量问题解决）；187.5 MHz 布线后 setup 失败（WNS -1.115 / TNS -466.545 / 1398 违例），blocked

- task_id `T10.a1-area-map` | round **r0**（新资源/QoR 包，同一 T10 同一 run；不是 `T10.a1-g2-2cyc` 的 r2）
- 日期 2026-10-22 | 离线 synthetic，无 bit/CWC/下载/Flash/上板
- 基准：core `47db3057…e0a2`、frame `18d51b1b…1cbe`、SDC `227dd39e…6311`
- **唯一判定：blocked。** 设计容量问题已彻底解决（cmem 不再是 65,536 寄存器，ERAM 8/300，slice 16,182 = 22.58%），但唯一一次布线在 187.5 MHz 下 setup 不收敛：**Routed SWNS -1.115 ns、STNS -466.545 ns、1,398 个违例端点**（hold 通过：HWNS +0.025 / HTNS 0.000）。布线 1/1、会话 3/3、综合 3/3 已用尽，不再有 TD 动作。

## 1. 冻结候选（SHA256）

| 文件 | SHA256 | 状态 |
|---|---|---|
| `upstream/…/rtl/ep_side/codec/a1_deflate_core.v` | `58b216dfcb711a09a597dfe4023ef9a7a0caa49cd217d1b1cce87b8531a0fd47` | 本包唯一 RTL 改动 |
| `upstream/…/rtl/ep_side/codec/a1_frame_top.v` | `18d51b1b80002e3549b6afd74956cff9d323d0a0272a7a08d617365a01611cbe` | 未改（锁定） |
| `r0/td/a1_small_top.sdc` | `227dd39e3dba8834af510013c71242450d4571307267d6bac4938cb8ef696311` | 未改（锁定） |
| `r0/td/a1_eng_top.v` | `544cecfc2eb34a3ab5c03ebf3965730b4ce60b2ff73ac4c2ec2d87772faaf9aa` | 与 r1 完全相同 |

manifest：`T10.a1-area-map/CANDIDATE-MANIFEST-area-map.json`（含全部证据哈希）。改动全文：`r0/candidate.diff`；设计说明：`r0/design-note.md`。

改动前已用可复现方式确认工作区 core 等于 r1 冻结值：把本次改动逐步反向替换后重算 SHA256 = `47db3057…e0a2`（与 r1 manifest 一致），故本包改动是干净增量。

## 2. RTL 改动（两步，均在 `a1_deflate_core.v`）

### 2.1 cmem 单写口 → ERAM（核心修复，hash 8044fdcc…）
- 原状：`cmem[4096×16]` 的写在**主时序进程（异步复位 + abort 分支）内分散三处**：写 FIFO 排空、`S_EODONE` 的 `cstage` 尾字、`S_EODONE`/`S_EODONE2` 的 `cacc` 尾字。
- 改法：三处合成唯一组合写口 `cmem_we_c / cmem_waddr_c[11:0] / cmem_wdata_c`（尾字优先，与原“最后赋值优先”一致；尾字只在前级/队列全空时产生，实际不并发），并由**独立、无复位**的写进程 `if (cmem_we_c) cmem[..] <= ..` 落实；读口从 htab 进程移出为独立 `always @(posedge clk) cmem_rdata <= cmem[cmem_raddr];`。该结构与 `a1_frame_top.v` 的 `smem` 同型（同器件已推断为 ERAM20K），未靠 `ram_style` 属性。
- 等价性：写地址/数据/使能逐拍等价；`cwptr ≤ 2700`（`S_DECIDE` 上界）故 12 位地址覆盖 4096 字全域；读延迟仍 1 拍（`S_REPLAY_R`→`S_REPLAY_RD`→`S_REPLAY_E`），无新增等待；replay 读取发生在整块打包完成之后，无同拍读写旁路需求。

### 2.2 bm_a 读地址 clamp 预计算（时序修复，hash 58b216df…）
- 2.1 后综合 SWNS 变 -0.283（r1 为 +0.134），最差路径 `pos → +k → 与 blk_n 比较 → mux → raddr_reg`（`a1_deflate_core.v` S_REPOS）。
- 改法：新增 `lim1 = blk_n-1`、`lim3 = blk_n-3`、`last_a = blk_n-1`（饱和到 0，`lim2` 复用 r1 已有），S_REPOS 三处由 `clamp_addr(pos+k, blk_n)` 改为 `(pos < limk) ? (pos+k) : last_a`，使 13 位加法与比较从 `pos` **并行**出发而非串行。等价性：`pos+k < blk_n ⟺ pos < blk_n-k`，`blk_n ≤ 4800` 无溢出，饱和后 `blk_n ≤ k` 时两式同为假（与 `clamp_addr` 返回 `blk_n-1` 一致）。仅触碰 bm 读地址/端口生成，未改协议、帧、CRC、长度、abort、Bayer、SDC。

## 3. G1 功能回归（全部 PASS，且与 r1 逐位相同）

| 项 | 结果 | 证据 |
|---|---|---|
| P2 | **13/13 PASS**（+bp/gapbp/abort/reset，共 17 例） | `r0/p2/result.json` |
| P3 | **20/20 PASS**，`failures=[]` | `r0/p3/result.json` |
| mismatch / X / BTYPE | **0 mismatch**；negative 用例 reason 全部符合 | 两侧 result.json |
| vlog | **Errors 0 / Warnings 0**（P2、P3） | `r0/p2/logs/vlog.log`、`r0/p3/logs/vlog.log` |
| stream SHA / run_cycles | **33 例（P2 13 + P3 20）与 r1 完全相同**；`result.json` 字节哈希与 r1 一致（P2 `6ab4d148…`、P3 `c7c0045e…`） | 逐例比较脚本输出 |
| P2 comp | **355,261 cycles、81.067 MB/s**（= r1，红线 370,370/77.76） | `r0/p2/result.json` |
| 1080p p1d1 | **4,677,945 cycles、103.892 MB/s**，SHA `b769cc66…08ff`（= r1） | `r0/p3/result.json`、`r0/p3/runs/f1080p_p1d1/stats.txt` |

结论：2.1+2.2 两步均**不改变任何码流、周期数与吞吐**；G1 在最终候选上重新实测通过（不是沿用旧证据）。

## 4. G2：综合通过、布线后 setup 不收敛

| 阶段 | 结果 | 证据 |
|---|---|---|
| s1（仅 2.1） | SWNS **-0.283**、STNS -4.216、27 违例；slice **15,058**、reg **2,549**、ERAM **8** | `r0/td/syn_gate_timing_s1.rpt`、`syn_gate_area_s1.rpt`、`syn_run_s1.log` |
| s2（2.1+2.2） | SWNS **+0.104**、STNS **0.000**、**0 违例**（16,328 端点）；slice **15,108**、LUT **16,414**、reg **2,575**、ERAM **8/300**、DRAM LUT 8,432 | `r0/td/syn_gate_timing_s2.rpt`、`syn_gate_area_s2.rpt`、`syn_run_s2.log` |
| s3 综合 | 与 s2 完全复现：+0.104 / 15,108 / 8 / 2,575 | `r0/td/td_stdout_s3.log` |
| s3 布线（1/1） | **Routed 完成但 setup 失败**：SWNS **-1.115**、STNS **-466.545**、**1,398 违例**、Fmax **155.087 MHz**；hold 通过 HWNS **+0.025**、HTNS 0.000、0 违例 | `a1_am_r0f_Runs/phy_1/a1_am_r0f_pr.timing`、`route.qor`、`route_flow.status` |
| 布线后资源 | slice **16,182/71,680 = 22.58%**、LUT6 15,456 (21.56%)、reg 3,710、ERAM **8/300**、DRAM LUT 8,432、f7mux 279 | `a1_am_r0f_phy.area` |
| check_timing | **已执行**：no clock 0、clock definition 0、combinational loop 0、dummy node 1、no input delay 47、no output delay 73 | `a1_am_r0f_chk.timing` |
| report_cdc | **未执行**（默认 phy 流程不含 report_cdc；`wait_run` 先因 bitgen 失败返回，我的 tcl 后续报告未跑到）。无 `cdc.rpt` | — |
| bitgen | 默认 phy 流程末步自动调用，被 **BIT-8123**（存在未约束 IO）拒绝；**未生成 .bit、未下载** | `phy_1/run.log` |

### 布线后最差路径（关键证据）
- `p3_r_reg[*] → praddr_reg[3].imb`：6.150 ns（cell 2.192 / **net 3.958 = 65%**，6 级，LUT6×4+LUT3+**DRAM**），slack -1.115。
- `p3_r_reg[*] → cq_r_reg[4].imb`：6.094 ns（net 3.960 = 65%），slack -1.064。
- 1,398 个违例集中在 **bm_a/bm_b 的分布式 RAM（DRAM LUT 8,432）组合读**：地址寄存器 → 长线 → DRAM → 读数据寄存器，布线前估计 2.9 ns、布线后 3.96 ns，物理延迟被综合阶段显著低估。

### 门槛判定（G2）
| 门槛 | 目标 | 实测 | 结论 |
|---|---|---|---|
| slice | ≤71,680 | 综合 15,108 / 布线 16,182 | **PASS** |
| ERAM 与实例相符 | cmem+smem | 8/300（smem 4 + cmem 4） | **PASS** |
| cmem 不展开 65,536 FF | 无 SYN-5114 | `#reg` 2,549（=RTL DFF），SYN-5114 消失 | **PASS** |
| synth WNS/TNS | ≥0 | +0.104 / 0.000，0 违例 | **PASS** |
| Routed | 完成 | Routed 完成 | **PASS** |
| Routed WNS/TNS | ≥0 | **-1.115 / -466.545** | **FAIL** |
| Routed hold | ≥0 | +0.025 / 0.000 | PASS |
| 0 违例 | 0 | **1,398** | **FAIL** |
| report_cdc | 实际执行 | 未执行 | **FAIL（证据缺失）** |
| bitgen | not_run | 流程自动尝试被拒，无 .bit | 见偏差 |

## 5. 预算与停止

| 项 | 用/上限 |
|---|---|
| TD 会话 | 3/3（s1 综合 5.5 min、s2 综合 1.3 min、s3 综合+布线 16.7 min） |
| 综合 | 3/3 | 
| 布线 | 1/1（已 Routed，WNS<0 即用尽） |
| TD 墙钟 | 23.5/150 min |
| bitgen/下载/Flash | 0 / 0 / 0（bitgen 仅被流程自动调用并拒绝） |

停止依据：dispatch「route 未 Routed / routed WNS/TNS<0 / 资源溢出 / CDC 未同步 → 停；布线 1 次用尽」，且会话/综合次数同时用尽。**不**做第 2 次布线、不 seed sweep、不降频、不改 SDC、不加 false path/multicycle、不改 QoR 策略（`add_map_lut_struct` 等一律未用）。

## 6. 根因与最小下一步（交规划）

- **已解决**：容量。cmem 由 65,536 寄存器 → 4×ERAM20K；全设计 reg 68,085 → 2,575（综合）；slice 72,904 → 15,108；ERAM 4 → 8。评审的 cmem 假设被实验证实（多写来源 + 复位进程内写导致无法推断 RAM）。
- **新暴露（r1 无法暴露，因为 r1 从未布通）**：真实物理时序缺口约 1.1 ns，全部集中在 **bm_a/bm_b 的 DRAM 组合读**（地址散开、DRAM 阵列铺开导致长线，净延迟占 65%）。综合阶段 `+0.104` 的估算偏乐观约 1.2 ns，**不能**用综合 WNS 代表 G2。
- 最小下一步（需规划/用户授权，本包无权做）：把 `bm_a`/`bm_b`（2×16K×8）改为**同步读 ERAM + 预取寄存器**（每拍端口需求：S_SCAN 需 1 读/拍 + 1 读给 x1/x2 预取；S_MCHK/S_EXT/新块预取另有读），用固定 1 拍延迟换掉 8,432 个 DRAM LUT 的长线；这会改变读取时序，必须按 P2/P3 逐位回归并重新核 P2 comp ≤370,370 cycles。约需 1–2 次综合 + 1 次布线的独立包。
- 备选（更保守）：先只改 `bm_a`（当前/参考双读口之一），或把 bm 拆成 ERAM 双 bank 复制读口；`htab`（1,024×66 寄存器）在布线后不是最差路径，暂不动。

## 7. 偏差与未测（诚实记录）

1. **report_cdc 未执行**：默认 phy 流程无该命令；`wait_run` 因 bitgen 失败返回，`01_final_route.tcl` 的 `open_run`+报告段未运行。会话 3/3 用尽，未擅自开第 4 个会话补报告 → 该项证据缺失，需规划决定是否授权一次"只读报告"会话。
2. **bitgen 被流程自动调用**：TD 默认 PhysicalDesign 流程末步执行 `bitgen -bit`，因 build-only 顶层存在未约束 IO 报 `BIT-8123` 而拒绝；**未产出任何位流、未下载、未写 Flash**。与 dispatch"bitgen not_run"存在流程性偏差，功能性后果为零。
3. 综合阶段 WNS 估算与布线结果相差 1.2 ns：本包只对最终 Routed 数值负责，综合数值仅作检查点。
4. 未测：板级、真实 RAW、双路、PCIe/RK、G3/G4、生产集成、bit/CWC。

## 8. 复现

```powershell
# 仿真（P:=项目根，W:=包 r0）
powershell -NoProfile -ExecutionPolicy Bypass -File upstream\ph1p100-pcie-ep-fpga\tools\codec\run_p2_areamap.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File upstream\ph1p100-pcie-ep-fpga\tools\codec\run_p3_areamap.ps1
# TD（T:=包 r0\td，Y:=项目根；先 tools\td\td_env.ps1）
cd T:\; $env:A1_TD_TAG="s2"; D:\anlogic\TD_Release_2026.2\bin\td_commands_prompt.exe T:/00_syn_check.tcl   # 仅综合检查点
cd T:\; $env:A1_TD_TAG="s3"; D:\anlogic\TD_Release_2026.2\bin\td_commands_prompt.exe T:/01_final_route.tcl # 综合+门闩+唯一布线
```

## 9. 回退

唯一改动文件 `a1_deflate_core.v`；回退即恢复 `47db3057…e0a2`（r1 候选）。frame_top/SDC 未改，`r1/` 与 `r0/` 旧证据全部保留未覆盖。
