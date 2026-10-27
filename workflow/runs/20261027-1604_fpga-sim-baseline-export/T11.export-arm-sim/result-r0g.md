# T11.export-arm-sim — result r0g（round3 最后额度，**blocked / SCOPE_CLARIFICATION**）

- 状态：**blocked**。T03 70B oracle **复现成功**（逐字节 0 差异），因此禁止改 store；但由此确认存在**两处规范/RTL 冲突**（地址单位、32B beat 字节序），修复点落在本轮禁止位置（b20 store / 参考 pusher），按规停止。
- 已冻结 `manifest-r0g.json`；r0..r0f 与全部旧 result **字节未改**。

## 1. 第一步（必须先做）：T03 70B oracle 复现 **PASS**

在同一工作根用**同一** `rtl\b20\a1_ddr_slot_store.v`（= 本候选 DUT 用的那份）+ 同一 TB DDR 模型约定，跑 T03 冻结样例（`t03oracle\`，源：`handoff/…/archive/offline/T03.pcie-byte-replay/r0/{stream.mem,rtl-slot-read.bin}`）：

```
REAL_STORE published=1 errors=0 exact_len=70 first_word=02c2…0c79c40cc797979be55a4e204ac4810cab49c4015a4a4a48629c78
BYTE_REPLAY_RTL PASS descriptors=48 slot_bytes=70
PRODUCED_LEN=70 FROZEN_LEN=70 BYTE_DIFF=0
FIRST8_PRODUCED=78 9c 62 48 4a 4a 5a 01
FIRST8_FROZEN  =78 9c 62 48 4a 4a 5a 01
```

- 结论：store 写/读的端序是 **LSB-first（低地址先）**，slot[0:70] 与 `rtl-slot-read.bin` **完全一致**，`78 9c` 开头符合 T03 基线。**store 不是缺陷源**，其字节序不得改（与规划禁止一致）。
- 证据：`t03oracle\t03.log`、`t03oracle\rtl-slot-read.bin`（重现件）、`t03oracle\sources.f`。

## 2. 第二步：槽基址 ×32 **未采纳**，附反证（需裁定）

- 设计指南 §3.6 修订为"word→byte = ×32"，但本候选**写/排空路径实测为 word×128**：
  - `AWDBG addr=00040000`（写侧，word 2048）；`MEMDBG mem[8192]=ad728d72…ff5f00a0009c78`（有真数据）、`mem[2048]=全0`。
  - 当 pusher 基址为 ×32（`0x10000`）时读到 `mem[2048]` → **全 0**（`sim\logs\r1-mem_0_20261027_184412.log`）。
- 即：*写入侧实际落点 0x40000* 与 *规范 0x10000* 不一致；把 pusher 改回 ×32 会重新变成全 0 读，故本轮**未强行回退**（回退会制造已知失败），改为报告冲突。
- 要让三者（store 写/排空、描述符 base、pusher 读）同标度到 ×32，只能改 store 的 `BASE_WORD` 语义或其字索引↔字节换算（b20 只读），或改 `p2_ddr_bridge` 的 ×32 之外再加换算（但那等于把 word 地址当 byte 接线，规范明令禁止）。

## 3. 核心阻塞：32 字节 beat 字节序（T03 已证 store 侧为 LSB-first）

- 导出载荷首字节 = 该 beat 的**最后**一个字节：`payload[0]=0xad = exp[31]`、`payload[1]=0x72 = exp[30]`（`sim\logs\r2-seg_*.log`：`got ad/72/8d/72` vs `exp 78/9c/00/a0`），`mismatch≈3594/3965`。
- 结合 §1：store 侧流首 4 字节 `78 9c 00 a0`（与 T03 oracle 一致的前两字节 78 9c）；pusher 发出 `ad 72 8d 72` = 同一 32B beat 的逆序 ⇒ **pusher 的 beat 解包为 MSB-first**，与 store/ T03 的 LSB-first 相反。
- 该逆序与地址无关（地址已对齐、数据非零、写握手与 `wr_bytes` 均正常，均已排除）。
- 修复位置二选一，均禁止：`a1_ddr_slot_store`（推翻 T03 基线，须用户单独裁定）或 `rtl\ref\ddr_frame_pusher.v`（改其解包语义）。在 `integrated_delivery_top`/TB 模型里加 32B 字节交换 = 规明令禁止的"掩盖接缝错误"。

## 4. 第三/四步状态

- exp_len 抓取多 1 字节：仍 **open**（本轮预算用于 T03 与字节序判定，未完成"按 keep 计数 + 单脉冲分帧 + 消除 `cap_end[]` X"）。
- 闭合回归（SCEN=0 两帧 / SCEN=3 / neg_both / E4）：**not_run**（本轮 vsim 1/4，因根因越界提前停止）。
- 上轮已确证可复用（须绑定新 manifest）：F3（两帧 32 MWr + doorbell）、F4-header（`hdr_err=0`）、F7（`rel_src=ACK` 754 tl cycles、错误 ACK 不释放）、F2 变异重注入、E1/E3/E5/E7。

## 5. 阻塞

- `problem_id`: `T11.export-arm-sim:SCOPE_CLARIFICATION:store-pusher-beat-order`
- `reason_code`: `SCOPE_CLARIFICATION`
- `new_information`: true
- `evidence_path`: `…\T11.export-arm-sim\t03oracle\t03.log`（T03 PASS、BYTE_DIFF=0）＋ `…\sim\logs\r2-seg_0_20261027_185806.log`（载荷逆序）
- `requested_action`（需用户/规划裁定其一）：
  1. **规范侧**：确认 A1U1 在 256-bit DDR beat 内的字节序（LSB-first 还是 MSB-first）。若为 LSB-first，则参考 pusher 的 beat 解包是缺陷 → 需授权改 `rtl\ref\ddr_frame_pusher.v` 的解包顺序，或
  2. **接线侧**：若真实系统的 A1 store 与 pusher 之间另有 beat 端序适配（如板级 DDR 字节通道映射），需给出该适配的 RTL/依据，允许在工作根 `p2_ddr_bridge`/`integrated_delivery_top` 内实现；
  3. **地址单位**：确认 §3.6 的 ×32 与实测写侧 ×128 何者为准（同样需要 store 或规范裁定）。
- `resume_input_path`: `…\manifest-r0g.json` + `result-r0g.md` §1–§3

## 6. 不得表述

本轮未达成载荷逐字节通过；F4/F6 仍 **fail**；SCEN=3/neg_both/E4 = `not_run`；G2/G3/G4 = `not_run`；不称真实 PCIe/时序/双路。
