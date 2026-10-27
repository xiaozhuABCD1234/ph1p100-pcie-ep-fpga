# T11.export-arm-sim — result r0f（round2 实际修复，**blocked / SCOPE_CLARIFICATION**）

- 状态：**blocked**。地址标度主点**已修且有证据生效**（pusher 读到真实数据，不再是全 0）；但载荷逐字节仍 **fail**，根因是**32 字节 beat 内的字节序**（store 写 vs pusher 发），修复点落在本轮禁止位置（b20 `a1_ddr_slot_store` 或参考 `ddr_frame_pusher`），按规停止。
- 已冻结 `manifest-r0f.json`；r0/r0b/r0c/r0d/r0e 与各 result **字节未改**。

## 1. ① 地址标度（主点）：已改、已生效

`rtl\board\brd_board_datapath.v`：
- `m_slot_base_bytes`：`{m_slot_base_word[26:0], 5'b0}`（×32）→ `{m_slot_base_word[24:0], 7'b0}`（**×128**，word 2048 → `0x40000`）
- `PUSH_BASE0/1`：`SLOT_BASE_WORD*32` / `(SLOT_BASE_WORD+SLOT_WORDS)*32` → **×128**

`claim_base_ok`（`ddr_base!=0 && ddr_base[11:0]==0`）与 ARM 语义未变（0x40000 低 12 位为 0）；容量检查未改；TB `DDR_CAP_BYTES` 未改（0x41000 < 0x100000）。

**生效证据**（`sim\logs\r2-seg_0_20261027_185806.log`，此前为全 0）：
```
MISMATCH tlp 0 byte 0: got ad exp 78      <- 载荷已是真实压缩流
MEMDBG mem[8192]=ad728d728d0738…ff5f00a0009c78   （r1 日志）
AWDBG addr=00040000 data0=78 …           （写侧落点与读侧一致）
```

## 2. 新的（也是唯一的）阻塞根因：32B beat 字节序反置

- 写侧顺序（store 送入 DDR 的第 1 字节）= `0x78`（`AWDBG data0=78`；`cap` 基准 `exp[0..3]=78 9c 00 a0`）。
- 导出顺序（TLP 载荷第 1 字节）= `0xad` = 该 32B beat 的**最后一个**字节（`mem[8192]` 的 MSB 端）。
- 即每个 32 字节 beat 被**整体反序**发出：`payload[i] == capture[31-i]`（`got ad/72/8d/72` vs `exp 78/9c/00/a0`）。
- 已排除：地址（读写同 `0x40000`）、写数据（非零且与写侧一致）、写握手（`wr_beats` 与 `mem[8192]` 一致）、压缩流为空、TB 期望同源（本轮基准为 store 写侧，E9 `baseline_source=store_write_side`）。
- 修复位置二选一，均**不在本轮允许范围**：
  - `a1_ddr_slot_store.v`（b20 只读输入）改 beat 打包字节序；
  - `rtl\ref\ddr_frame_pusher.v` 的 `data_beat` 解包字节序（本轮明令禁止改其语义）。
  - 在 `integrated_delivery_top` 里给 `wr_data` 插字节交换 = 改数据语义，未授权，不做。

## 3. ② exp_len=3966 vs exact_bytes=3965（部分结论 + 未闭合项）

- r1 观测：写侧抓取 `exp_len=3966`、描述符 `exact_bytes=3965`，差 1 字节，且多出的那 1 字节在写侧流的**末尾**（属末字填充/终止字节，不在 TLP 载荷比较范围内——比较按 `exact_bytes` 截断）。
- 本轮把分帧键从 `wr_begin`/`core_commit` 改为 `pub_pulse` 后，`E9 … exp_len=x`（`cap_end[]` 出现 X），说明该分帧计数仍有 TB 缺陷，**未能在本轮给出最终定论**；不据此改断言、不把期望改成 3966。
- 结论：该项 **open**，需在字节序问题解决后，用"写侧长度 + 末尾填充字节值"证据收尾。

## 4. ③ frame2 写侧抓取为空：已定位为 TB 分帧缺陷（已改，但未收尾）

- 原因：`wr_begin` 在同帧可多次脉冲（`GS_BEGIN` 重试/复用），按它开窗会把第 2 帧落到空窗口，导致 `STREAM_DIFF frame1(3966) vs frame2(0)` → 误报"两帧流相同"。
- 本轮先改为 `core_commit`、再改为 `pub_pulse`（每完成帧一次），`mismatch` 从 3619 降到 3594、第 2 帧不再为空；但 `cap_end[]` 仍有 X（见 §3），分帧计数未定稿。

## 5. 回归状态（本轮 2 次 vsim）

| 场景 | 结果 |
|---|---|
| SCEN=0 NF=3（`r2-close`） | 两帧均导出（32 MWr + 1 doorbell/帧）、`hdr_err=0`、`rel_src=ACK`（754 tl cycles）、错误 ACK 不释放（`NEG2_RESULT=PASS`）；**载荷 mismatch 3619/3578 → fail** |
| SCEN=0 NF=3（`r2-seg`，分帧改 pub_pulse） | 同上，`mismatch=3594/3578`、`compared==exact_bytes`；`exp_len=x` |
| SCEN=3 / neg_both / E4 | **not_run**（预算用于定位） |

## 6. 阻塞

- `problem_id`: `T11.export-arm-sim:SCOPE_CLARIFICATION:beat-byte-order`
- `reason_code`: `SCOPE_CLARIFICATION`
- `new_information`: true
- `evidence_path`: `…\T11.export-arm-sim\sim\logs\r2-seg_0_20261027_185806.log`（`got ad/72/8d/72` vs `exp 78/9c/00/a0`）
- `requested_action`: 裁定哪一侧是规范——
  (a) 允许改 `rtl\int\a1_ddr_slot_store` 副本的 beat 打包字节序（需把该 b20 文件纳入工作根 rtl 副本与 manifest），或
  (b) 允许在 `integrated_delivery_top` 的 store 写口加 32B beat 字节交换（数据语义变更），或
  (c) 由规划/队友确认参考 pusher 的 `data_beat` 解包字节序才是规范、TB 的 DDR 模型应做字节通道映射（则改 TB 模型，需给出依据）。
- 预算：约 15 次调用 / 30 min；vsim 2/5（其余额度未用，因根因已越界）。

## 7. 未运行 / 不得表述

`SCEN=3` 反压、`tb_brd_neg_both`、E4 两次复跑 = `not_run`；F4/F6 仍 **fail**；不得表述为"载荷通过"。G2/G3/G4 = `not_run`。
