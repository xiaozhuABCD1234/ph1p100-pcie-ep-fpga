# DECISION — r0g 裁定（2026-10-27，用户拍板 + r3 复核）

本页冻结 r0g 的两个口径，并记录 r3 用 T03 oracle 对 pusher 映射做的一次**实测复核**。它不改变 r0g/旧 run/旧 manifest 的任何字节，也不把 r3 说成板级结论。

## 1. A1U1 槽内字节序：LSB-first（低地址先）

- 依据：T03 冻结 70 B oracle（`workflow/runs/20261027-1604_fpga-sim-baseline-export/T11.export-arm-sim/t03oracle/`）。真实 store 写出的 stream 首字节是 `78`，zlib 头必须是 `78 9c`；r0g 已逐字节复现 `PRODUCED_LEN=70, BYTE_DIFF=0`。
- 裁定：256-bit DDR beat 内 **byte 0 = bit[7:0]**，低地址先；`a1_ddr_slot_store.v` **不改**。
- 推论：pusher 从 DDR 读到的 `beat_data[7:0]` 就是 stream 的第 0 字节；任何"整 beat 反序"的解读都必须有独立依据，不能靠 TB 约定。

## 2. 地址单位：256-bit word × 32 总换算

- 唯一换算链：P4 输出 **word 索引** → `p2_ddr_bridge` **×8**（`{wf_rdata[279:256],3'b000}` / `{af_rdata[23:0],3'b000}`）→ 板级 `brd_paxi_remap` **×4**（`{br_awaddr,2'b00}`）→ **×32 字节/word**。
- 保留 r2 的 `+SLOT_BASE_WORD` 写/读偏移：word 2048 → 写 byte `0x1_0000`，pusher 读 `0x1_0000`。
- 拒绝 export 工作副本的 `×32`（`{wf_rdata[276:256],5'b00000}`）+ 板级 `×4` = **×128**（word 2048 → `0x4_0000`：双重换算）。
- 拒绝 export 副本的 pusher base `×128`；r3 保持 `PUSH_BASE0 = SLOT_BASE_WORD * 32`。
- 不引入第三个乘数；`a1_ddr_slot_store.v` 的 `BASE_WORD`/字索引语义不变。

## 3. pusher data beat 映射：实测后**保持** `bswap256`

r3 没有"按预期改"，而是先写小 TB（`workflow/runs/20261027-2359_fpga-r3-merge/tb/tb_t03_pusher_map.v`）把 T03 70 B 流经 store 写入 DDR（word 2048），再让 `ddr_frame_pusher` 读同一块内存，用项目既有的 host 模型解码（lane 7→0、DW 内 MSB 先；即 `sim/tb/tb_ddr_frame_pusher_rka1.v`、`sim/tb/tb_t11_r10f_e2e.v`、`sim_do/tb_ddr_frame_pusher.v` 的 `push_beat()`），对同一批 beat 计算三种候选：

| 候选 | 含义 | FIRST8 | BYTE_DIFF |
|---|---|---|---|
| **A（现状）** | 保留 `bswap256` | `78 9c 62 48 4a 4a 5a 01` | **0 / 70** |
| B | 去掉 `bswap256` | `02 c2 02 40 2d 0c 79 c4` | 69 / 70 |
| C | 只反转 32-bit DW 顺序、保留 DW 内字节序 | `40 02 c2 02 c4 79 0c 2d` | 67 / 70 |

结论：**A 是唯一逐字节等于 `rtl-slot-read.bin` 的映射**。因此：

- `rtl/ref/ep_side/ddr/ddr_frame_pusher.v` 的 `data_beat = bswap256(beat_data)` **不改**（r3 只加了一段说明注释，行为零变化）。
- r0g 观察到的 `ad 72 8d 72` 不是 DUT 反序，而是 r0g 新 TB 的 **payload 解码**用了"lane 0 先 + DW 内 LSB 先"，与它自己的 header 解码（lane 7 = DW0）以及上述三个项目 TB 都相反。该 TB 的 host 模型在 r3 中修正，并保留 `+HOST_MODEL=1` 开关复现 r0g：legacy 模式 mismatch=3830/3845，修正模式 mismatch=0。
- 这不推翻 r0g 的 blocked 记录：r0g 的结论绑定的是它自己的 TB 和 manifest；r3 是新的输入、新的 manifest、新的证据。旧文件一个字节未改。

## 4. 由此产生的 r3 最小 delta

| 文件 | 语义变化 |
|---|---|
| `rtl/brd_cdc_mailboxes.v` | `o_ack_seq <= out_bus[63:32]` / `o_ack_session <= out_bus[31:0]`（r0d ACK 切片） |
| `rtl/brd_board_datapath.v` | `a_seq/b_seq` 复位为 `32'd1`（r0d capture identity 从 1 起） |
| `rtl/ref/ep_side/ddr/ddr_frame_pusher.v` | 仅注释（映射复核依据），`bswap256` 不变 |

保留 r1 的 C8/C9 2FF、r2 的 `+SLOT_BASE_WORD` 和 release 极性（`rel_camera_id=0→A, 1→B`）、r2 的 `brd_export_seq` F1、r2 的 bridge ×8；不改 store/deflate/frame_top/P4/constraints。

**副作用（已实测、已记录）**：capture identity 从 1 起使 A1U1 header 的 `frame_id` 0→1，因此 header CRC 从 `5436BF73` 变为 `A5ECBAD9`（PREP 从 `981E85CF` 变为 `69C48065`）。压缩流本身不变：`stream_len=2470`、`stream_crc=9909B919`。

## 5. 证据入口

- `workflow/runs/20261027-2359_fpga-r3-merge/evidence/verify-t03.log`（A/B/C 三映射 + 地址检查）
- `workflow/runs/20261027-2359_fpga-r3-merge/evidence/verify-slot-r3.log`（r2 G1 六场景，150 项）
- `workflow/runs/20261027-2359_fpga-r3-merge/evidence/verify-export-r3.log`（两帧/反压/ACK/负例 + legacy 复现）
- `workflow/runs/20261027-2359_fpga-r3-merge/evidence/static-checks.log`（64 项静态 + r3-vs-r2 delta）
- `workflow/runs/20261027-2359_fpga-r3-merge/manifest-r3.json`

## 6. 边界

本裁定与 r3 全部证据都是**本机仿真/静态**；没有 TD 综合、布局布线、STA、bitgen、CWC、下载、Flash，也没有真实 PCIe/RK/板卡/1080p/长稳。G2p/G3/G4 仍是 `not_run` / `teammate_required` / `awaiting_hardware`。队友构建前先跑 `handoff/brd-p1-r3-20261027/build/check_filelist.py`，再 `gen_al.py`，再 `01_synth → 02_route → 03_bitgen`。
