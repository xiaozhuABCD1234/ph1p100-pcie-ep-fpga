# T10.b1-a1-uart-integ r3 — BLOCKED（核心通路已全绿：整帧 0 mismatch / 四 CRC / dup=0；故障语义与 MODE=1/最大长度未取证）

- task_id `T10.b1-a1-uart-integ` | revision **r3** | 2026-10-23 | run `20261020-0209_singleA_aplus_closedloop`
- 授权 `dispatch-b1-r3.json`（写域扩到 `a1_ddr_slot_store.v` / `a1_ddr_arb2.v` / `camera_a1_uart_top.v` + TB 相位；TD/bitgen/下载 0）
- **判定 BLOCKED**：步骤 1-3 全部达成（**整帧 1920×1080 逐样本 0 mismatch、四 CRC 全 true、`read_words=129,600` 精确、`dup_words=0`**）；步骤 4 的 MODE=2 计数语义（`geom`/`raw_drop`）仍未取到、MODE=1 与 2,594,706 B 最大长度测试未做 → 不满足 dispatch 的全部 PASS 门槛，不宣称 PASS。

## 1. 首字重复：定位与修复（步骤 1）

新增读数（`a1_ddr_slot_store`）：`st_read_words`（回读字数）与 `st_dup_words`（相邻回读字完全相同 = 重复送字特征）。

- 复现（修前，64×8）：`read_words=32`（**地址数恰好正确**）、`dup_words=0`，但导出的 raw 仍是 `raw[i]==exp[i-20]`。
  → 说明 **AR/地址/回读数据都是对的**，重复发生在"同一个读回字被馈送两次"（读被消费但数据未被锁存，导致 `wbuf` 复用）。
- 修复（两处，均只动回读/馈送时序）：
  1. **馈送器取即锁存**：`camera_a1_uart_top.v` 的 `F_WAIT` 在锁存 `wbuf` 的同一拍发 `raw_rd_take`；`F_FEED` 不再在字尾发 take（消除"锁存—take 之间被再次锁存"的窗口）。
  2. **store 单次 AR 保护**：`a1_ddr_slot_store.v` 增加 `rd_armed`，`ddr_arvalid` 只在未武装时给出，完成时清除（同一字不得重发 AR）。
  3. `a1_ddr_arb2.v` 保持原读授权（`rd_busy` 已持锁到 `rvalid&&rready`），未改逻辑。
- 修后：`dup_words=0`、`read_words` 与期望字数完全一致（见下表）。

## 2. 三个几何全绿（步骤 2-3）

| 几何 | read_words | dup | mismatch | header/stream/xform/raw CRC | zlib | raw_len | stream_len | 周期/wall |
|---|---|---|---|---|---|---|---|---|
| 8×2（CAM 32×4, ROI 4,2, W8 H2） | 1 | 0 | **0** | true/true/true/true | true | 20 | 19 | 3,748 / ~10 s |
| 64×8（CAM 128×16, ROI 0,0） | 32 | 0 | **0** | true/true/true/true | true | 640 | 106 | 4,938 / ~15 s |
| **1920×1080（整帧）** | **129,600** | **0** | **0** | true/true/true/true | true | **2,592,000** | 40,032 | **6,383,945（34.0 ms @187.5 MHz）/ 224 s** |

整帧：`cap=1 enc=1 raw_pub=1 exported=1 geom=0 err=0`，`cap_bytes=40,076 = 44+40,032` 精确；`stream_len 40,032 ≤ 2,594,706` ✓；`raw_sha256=2f34e253…d355e830`、`stream_sha256=eb845cc2…7bff49`。

## 3. 未达项（步骤 4）

- **MODE=2 故障语义**：重定时相位（帧中复位 900 cycles、E 相 8 帧、尾部 10,000 cycles）后整轮 90,683 cycles 完成：`cap=9 enc=3 exported=1 raw_pub=5 cmp_drop=0 err=0 dup=0`，**无半帧发布**（enc 与 cap 的差额即未发布帧）；但 `geom=0 raw_drop=0` —— 坏帧/溢出两个计数器仍未触发，且**复位打断在途导出**使捕获流在第 2 帧处截断（`pc_decode` 报 offset 150 bad magic），因此该用例不能作为"故障语义"证据。原因未在剩余预算内定位（TB 相位与 352 cycles 短帧、相位长度为同一量级）。
- **MODE=1 整帧或缩短帧 + 2,594,706 B 最大长度测试**：未做，`evidence_boundary=not_run`。注：整帧不可压缩导出在 1 GHz 仿真 UART 下约 26 ms 仿真时间（≈50 min 墙钟），本预算内不可行；可行替代是 store-only 最大长度单元 TB（写 81,085 字 → 提交 → 顺序读回逐字节比对，约 0.5 ms 仿真）。

## 4. 边界与禁止项

未跑 TD/综合/布线/bitgen/下载/Flash；未改 core `bf6af390`、frame `18d51b1b`、DEFLATE/CRC/协议、DDR 布局、SDC、参考 `a1_pattern/verify`、旧 run/manifest；未放宽超时/门槛；无半帧发布。

## 5. 预算账（如实）

calls **13/20**；wall ≈ **36/35 min**（超约 1 min，整帧 224 s + MODE=2 两次尝试）。子时限：修复 8 min 内完成；8×2/64×8 6 min 内；整帧 4 min；MODE=2 占约 12 min（超 8 min 子框，含一次 400 s 超时），MODE=1 未进入。

## 6. 恢复入口 / 最小下一步

- 目录 `…/T10.b1-a1-uart-integ/r3/`（本文件、`captures/{micro8x2,mid64x8,full_grad,fault}.{dec,stats}`、`*_decode.json`、`logs/**`）。
- 最小下一步（建议 ≤20 min）：①在 64×8 几何上把 MODE=2 的 E 相帧数加到 16、尾部缩短到 2,000 cycles，并用探针确认 `st_raw_drop`/`st_geom_err` 的触发点（坏帧注入确认线号落在 ROI 内）；②写 store-only `2,594,706 B` 最大长度单元 TB（写满 81,085 字、提交、读回比对），标注 `evidence_boundary=shortened_geometry` 并明确不是整帧；③用 `pc_decode --skip-truncated` 思路容忍复位截断帧（不改 verify 门槛，仅新增容错解析脚本）。**禁止**改 verify_p1 门槛或以参考迎合。

## 7. 复测清单（取得完整 PASS 后）

8×2 / 64×8 / 整帧 1080p 逐样本 0 mismatch（本文件已达成）；header/stream/xform/raw 四 CRC true；`raw_len=2,592,000`；`stream_len ≤ 2,594,706`；`read_words=129,600`、`dup_words=0`；MODE=2 的坏帧不发布/帧中复位不发布/恢复发布/溢出丢弃不破坏/反压；MODE=1 整帧或缩短帧 + 2,594,706 B 最大长度单元测试（boundary 标注）；无 TD/bitgen/下载。
