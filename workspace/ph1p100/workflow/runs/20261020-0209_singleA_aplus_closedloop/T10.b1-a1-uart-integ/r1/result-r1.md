# T10.b1-a1-uart-integ r1 — BLOCKED：导出链路已打通并完成整帧自洽解码，但逐样本参考比对未通过、header_crc 仍有 1 字节时序缺陷

- task_id `T10.b1-a1-uart-integ` | revision **r1** | 2026-10-23 | run `20261020-0209_singleA_aplus_closedloop`
- 授权：`dispatch-b1-r1.json`（单次有界续跑；无 TD/bitgen/下载；不改 core `bf6af390`/frame `18d51b1b`/DEFLATE/SDC）
- 判定 **BLOCKED**：`MODE=2` 与 `MODE=0` 均能跑完并产出字节流；整帧 1920×1080 经 PC 端 **zlib 解压成功、stream/xform/raw 三个 CRC 全对、raw_len/长度/最坏膨胀上界正确**；但 **逐样本与独立参考比对有 2,077,900 B 不一致**（0 mismatch 未达），且 **header_crc 校验失败**（已定位为 1 字节时序缺陷，未在冻结前改动）。**不宣称 PASS**，不提交测试者。
- 预算：**calls 38/40；wall ≈ 80 min > 60 min（超时，见 §8）**。

## 1. 探针结论（≤15 min 步骤）：导出 FSM 卡死的原因（已修）

`MODE=2` 200 µs 探针（`r1/probe_r1.do` + `logs/probe_r1.log`）显示 `estate=E_PAY, sent=32, wbuf_valid=0, cmp_store rd_idx=1/rd_words=1, st_err=1, w_stream_len=203`：导出状态机在 E_PAY 等第二个 256-bit 字，而压缩槽只发布了 1 个字。
根因**不在等待逻辑，而在存储长度**：`a1_ddr_slot_store` 的 `wr_keep[0]+wr_keep[1]+wr_keep[2]+wr_keep[3]` 是 **1-bit + 1-bit = 1-bit（截断）加法**，keep=0xF 时得 0，`slot_len` 只有 1 B 而不是 203 B。修：先拓宽到 3 bit 再相加。修后 200 µs 处 `sent=116`，1.2 ms 处 `st_exp=1 / exp_bytes=203`，导出完成。

第二个导出侧缺陷（探针证实）：描述符 `frame_id` 用 `cmp_id-1`，而 `wr_begin` 是寄存脉冲，槽实际锁存的是自增后的 `cmp_id` → 恒差 1，`cmp_id != w_frame_id` 触发 `st_err`。修：`d_fid <= cmp_id`。

第三个是 **TB 等待缺陷**（探针证实，dispatch 允许修）：`wait_export(n)` 用绝对计数，而相位 C 的帧中复位把 DUT 的 `st_exp` 清零，`wait_export(2)` 永远等不到（`when` 事件表显示 `EXP1` 出现两次）。修：改为相对目标 `target = st_exp + n`，并把相位 D 的调用改为 `wait_export(1)`。

## 2. 整帧 1080p 结果（MODE=0，默认几何，187.5 MHz 口径）

| 项 | 值 |
|---|---|
| 仿真 | 6,417,909 cycles（34.2 ms @187.5 MHz），wall 3m24s，`vlog` 0/0，无 abort |
| crop/A+/store | `cap=1 enc=1 raw_pub=1 exported=1 geom=0 err=0` |
| 捕获字节 | 56,498 B（44 头 + 56,454 payload），`exp_bytes=56,454` 一致 |
| PC 解码 | `zlib_ok=true`，`stream_crc_ok=true`，`xform_crc_ok=true`，`raw_crc_ok=true`，`raw_len_ok=true`，`trailing=0` |
| 头字段 | 1920×1080、prep=1 pred=1、raw_len=2,592,000、xform_len=2,592,000、stream_len=56,454（全部正确） |
| 最坏膨胀 | `stream_len 56,454 ≤ 2,594,706` ✓（容量参数 `cmp slot = 81,085×256bit`） |
| 逐样本 | **mismatch 2,077,900 B / 2,592,000**（raw 与 `tools/a1/a1_pattern.py` 参考不等）→ **未达 0 mismatch** |
| header_crc | **false**（见 §3） |

即：**端到端数据通路自洽**（DUT 的 raw_crc 与 PC 用 zlib+逆变换独立重算的 raw CRC 完全一致），但与我方参考图案的逐样本比对不通过。

## 3. 本轮定位并已修的 3 个 RTL 缺陷（+1 已定位未修）

1. `a1_raw_crop`：`out_cnt` 为 16 bit，而整帧 `W*H/4 = 518,400 > 65,535` → `out_last` 永不触发、帧被判短（`cap=0 geom=1`）。修：`out_cnt[19:0]`。
2. `a1_ddr_slot_store`：`wr_keep` 1-bit 截断加法（见 §1）。修：3-bit 拓宽相加。
3. `a1_ddr_slot_store`：256-bit 组字**通道顺序反转**（`{pack_r[..], wr_data}` 把最新字放最低位），PC 侧表现为 payload 非 zlib 流（首字节 `d3` 而非 `78`）。修：`pack_r | ({...} << (wcnt*32/40))`，第 k 字落第 k lane。修后 zlib/CRC 全对。
4. **未修（已定位）header_crc**：`u_export` 在 `hdr_idx==40` 才 `crc_fin <= ~crc_r`，而同拍 `tx_byte_r <= hdr_byte`（`hw10 = crc_fin`）读到的是**旧值 0** → 头部第 40 字节错。修法（1 行）：把 `crc_fin` 改为在 `hdr_idx==39` 时计算 `~crc32b(crc_r, hdr_byte)`。冻结前未改动，避免未仿真 RTL 进 manifest。

## 4. 未达项与最小下一步

- **逐样本 2,077,900 B 不一致**：DUT 自洽，故差异必在"参考图案/ROI 约定"与"实际驱动/裁切"之间。最小下一步（≤10 min）：用 8×2 微型几何（CAM 32×4, ROI 4,2, W=8,H=2）跑一帧，打印 DUT raw 前 16 B 与参考前 16 B、以及 `(y,x)` 归属，二选一确认是 (a) `a1_pattern.roi_samples` 的 x0/行索引约定，还是 (b) crop 的 `eff_line/eff_grp` off-by-one。禁止用改参考去迎合 DUT，必须以 OE 推导为准。
- `MODE=1` 不可压缩整帧**未运行**（时间不足），`evidence_boundary=not_run`；`2,594,706 B` 最坏长度**仅有容量参数与上界比较**，无标配/导出实测单元测试。
- `MODE=2` 故障轮可跑完（6 s，558 B 捕获、3 次 commit、1 次导出、err=0），但 `geom=0 raw_drop=0`：坏帧与溢出两相**未产生预期计数**（TB 相位时序与 352 cycles 的短帧不匹配，复位与 3000 cycles 延迟错位），语义未取证。

## 5. 边界与禁止项

未运行 TD/综合/布线/bitgen/下载/Flash；未改 `a1_deflate_core.v`、`a1_frame_top.v`、SDC、旧 run/manifest、tasks.json；未放宽任何超时或阈值；未把缩短帧当整帧。

## 6. 恢复入口

`workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b1-a1-uart-integ/r1/`（本文件、`probe_r1.do`、`probe6.do`、`captures/full_grad.{dec,stats}`、`full_grad_decode.json`、`logs/**`）。恢复文本：`恢复 T10.b1-a1-uart-integ r1：先读 result-r1.md §3-§4，再修 header_crc（hdr_idx==39 预算 crc_fin）+ 8×2 微型几何定位逐样本差异；仍无 TD。`

## 7. 复测清单（取得 PASS 证据后）

`MODE=2`（400 s）/`MODE=0`（900 s）/`MODE=1` 或"缩短帧 + 2,594,706 B 最大长度单元测试（标注 `evidence_boundary=shortened_geometry`）"；逐样本 0 mismatch、header/stream/xform/raw 四 CRC、长度、最坏膨胀上界、坏帧不发布、复位不发布、溢出丢弃不破坏内容、无半帧；无 TD/bitgen/下载。

## 8. 证据偏差（如实）

- r1 wall ≈ 80 min（dispatch 60 min）；calls 38/40。
- 探针阶段做了 6 次定向探针（含 2 次 `when` 语法失败），超出 15 min 子预算；整帧仿真重跑 3 次（16 bit 计数、通道顺序各一次失败后修正）。
- `MODE=0` 两次全帧运行均以 900 s 超时上限内的实际完成时间（209 s / 206 s）结束，未放宽超时。
