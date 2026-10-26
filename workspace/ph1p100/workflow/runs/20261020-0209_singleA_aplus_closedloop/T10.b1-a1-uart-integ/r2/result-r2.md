# T10.b1-a1-uart-integ r2 — BLOCKED：header_crc 已修好；整帧 0 mismatch 的剩余原因已定位为 raw 回读**首字重复**，其修复点不在 r2 授权写域

- task_id `T10.b1-a1-uart-integ` | revision **r2** | 2026-10-23 | run `20261020-0209_singleA_aplus_closedloop`
- 授权 `dispatch-b1-r2.json`（收口轮；TD/bitgen/下载 0；不改 core bf6af390 / frame 18d51b1b / DEFLATE / SDC）
- 判定 **BLOCKED**：`header_crc` 时序修复**已验证通过**（44 B 头在 8×2 与 64×8 两帧均 `header_crc_ok=true`）；8×2 微型几何 **DUT raw 与独立参考完全一致**（origin (2,4)），证明参考 ROI 约定与 crop 均正确；整帧剩余 2,077,900 B 差异的根因已定位为 **raw 回读把第 0 个 256-bit 字重复送了一次**（后续全部字节 +20 B 平移，`raw[i]==exp[i-20]` 对 i≥20 全部 2,591,980 B 成立）。该缺陷位于 `a1_ddr_slot_store.v` 读状态机 / `a1_ddr_arb2.v` / `camera_a1_uart_top.v` 馈送器，**三个文件均不在 r2 `write_scope.modify_existing`**，按 dispatch「只修证明原因」与停止条件 **BLOCKED 交规划**，未越界修改。

## 1. 步骤 1（header_crc，≤5 min）：已修并验证

`a1_uart_export.v` 改为在 `hdr_idx==39` 同拍完成 `crc_r <= crc32b(crc_r, hdr_byte)` 与 `crc_fin <= ~crc32b(crc_r, hdr_byte)`，字节 40 起读到的 `hw10=crc_fin` 即为最终值。仅动这一处。

| 帧 | header_crc | zlib | stream_crc | xform_crc | raw_crc |
|---|---|---|---|---|---|
| 8×2 微几何（CAM 32×4, ROI 4,2, W=8,H=2） | **true** | true | true | true | true |
| 64×8（CAM 128×16, ROI 0,0） | **true** | true | true | true | true |

## 2. 步骤 2（8×2 诊断，≤8 min）：参考与 crop 均正确

`r2/micro8x2_diag.json`：DUT raw `1f2418 1d00 1116 0a0f 00 2421 1d1a 2216 130f 0c22` 与参考**逐字节相同**；2×8 样本网格 `[[124,144,96,116,68,88,40,60],[146,132,118,104,90,76,62,48]]` 两侧一致；穷举 (y0,x0) 得唯一匹配 `origin=(2,4)`，即 ROI 原点精确。**结论：`a1_pattern.roi_samples` 的 x0/行约定与 `a1_raw_crop` 的 `eff_line/eff_grp` 都正确**，无需修改参考或 crop。

## 3. 剩余整帧差异的根因（已证明，修复点越界）

证据链（全部在既有 r1 全帧捕获 + r2 小几何复现上）：

1. r1 全帧 raw 与参考：`raw[i]==exp[i-20]` 对 i≥20 **2,591,980/2,591,980 全成立**；0 平移仅 514,100 B 相同 → **帧首恰好多出 20 B（一个 4 组字）**。
2. 64×8 复现（32 字）：`shift +20 → 620/620` 全匹配，`shift 0 → 116/640`，`head DUT == head REF`，`blk0==blk1` → 与尺寸无关、发生在帧首。
3. 8×2（仅 1 字）不受影响（无第二字可偏移）→ 说明是**字级**重复，而非组/样本级。
4. **DDR 模型内存探针**（`r2/memprobe.do`，64×8，`run 6us`）：`mem(0)=…29241f1a0015100b0600231e1914000f0a0500`、`mem(1)=…35302b2600211c1712002f2a2520001b16110c`、`mem(2)`、`mem(3)` 各不相同且严格递增为栅格顺序；`waddr=31`（32 字全部写入）、`rd_idx=25`、`rd_words=32`。
   → **写入侧与 DDR 内容完全正确**；重复发生在**回读/馈送侧**（读 FSM 或馈送器把第 0 字用了两次，导致最后一字未被读取，帧尾丢失）。
5. 该现象与 r2 已修的 lane 顺序/keep 位宽无关（写入侧已自证正确）；`header_crc` 无关。

**修复点定位**（供规划授权）：`fpga/csi2/src/a1/a1_ddr_slot_store.v` 读路径（R_IDLE→R_AR→R_RW→R_HOLD 的 AR/rd_idx 时序）、`a1_ddr_arb2.v` 读授权（`g0r`/`rd_busy`/`rd_last`）、或 `camera_a1_uart_top.v` 馈送器 F_WAIT/F_FEED 的 `rd_take` 时点。最可能的稳健修法：馈送器改为**取即锁存**（在 F_WAIT 锁存 `wbuf` 同拍发 `rd_take`），并在 store 侧对“同一 AR 重发”加一次性保护；两者都需先加 `st_read_words`/`st_dup_words` 计数确认。**上述三文件均不在 r2 写域**，故本轮不修改。

## 4. 未执行（因上一条阻塞）

- 步骤 3 `MODE=2` 故障语义（坏帧/帧中复位/恢复/三快帧丢弃/反压）**未重跑**：raw 比对必然失败，语义证据无意义；TB 相位时序修改亦未做。
- 步骤 4 `MODE=1` 整帧或缩短帧 + 2,594,706 B 最大长度单元测试：未做，`evidence_boundary=not_run`。
- 步骤 5 整帧 1080p 重跑：未做（同上；即使跑也不会 0 mismatch）。

## 5. 边界与禁止项

未跑 TD/综合/布线/bitgen/下载/Flash；未改 core `bf6af390`、frame `18d51b1b`、DEFLATE、SDC、旧 run/manifest、tasks.json；未放宽任何超时/门槛；未把缩短帧当整帧；未以“改参考迎合 DUT”代替定位（参考已被 8×2 证明正确）。

## 6. 恢复入口与最小下一步

- 目录 `workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b1-a1-uart-integ/r2/`（本文件、`micro8x2_diag.json`、`probe`/`memprobe.do`、`captures/{micro8x2,mid64x8}.{dec,stats}`、`logs/**`）。
- 恢复文本：`恢复 T10.b1-a1-uart-integ r2 收口：读 result-r2.md §3；授权 a1_ddr_slot_store.v/a1_ddr_arb2.v/camera_a1_uart_top.v 修 raw 回读首字重复（先加 read/dup 计数确认，再改取即锁存）；随后 MODE=2 语义 + MODE=1/最大长度 + 整帧 0 mismatch。`
- 预算账（如实）：calls **14/25**；wall ≈ **30 min / 40 min**；子时限：header 修复 ~6 min（含编译）、8×2 诊断 ~7 min、根因探针 ~10 min（超出诊断 8 min 子框，用于 DDR 内存取证）；步骤 3-5 因阻塞未进入。

## 7. 复测清单（取得 PASS 后）

`MODE=2`（400 s）/`MODE=0`（900 s）/`MODE=1` 或缩短帧+2,594,706 B 最大长度单元测试（标注 `evidence_boundary=shortened_geometry`）；四 CRC（header/stream/xform/raw）全 true、逐样本 0 mismatch、`raw_len=2,592,000`、`stream_len ≤ 2,594,706`、坏帧不发布、复位不发布、溢出不破坏、无半帧；无 TD/bitgen/下载。
