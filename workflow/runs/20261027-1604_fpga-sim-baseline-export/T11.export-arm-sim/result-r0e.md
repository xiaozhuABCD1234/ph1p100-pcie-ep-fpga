# T11.export-arm-sim — result r0e（round1 实际修复，**blocked**）

- 状态：**blocked（LIMIT_REACHED）**。测试 FAIL 的核心缺陷**已定位到地址标度**并有决定性证据，但本轮预算（30 调用 / 45 min / vsim ≤6）耗尽，未能完成"读取地址对齐 + 闭合回归"。
- 已冻结 `manifest-r0e.json`；`manifest-r0{,.b,.c,.d}.json` 与 `result-r0{,b,c,d}.md` **字节未改**。
- 口径更正：测试者判定正确。r0b/r0c/r0d 的"载荷逐字节通过"是**自比较**（TB 用 pusher 同源 `u_mem.mem` 作期望），**不得再引用**。本轮已把期望改为**写侧独立基准**，并因此第一次看到真实 `mismatch`。

## 1. 测试 FAIL 项的处理进展

| 测试发现 | 本轮状态 |
|---|---|
| F4 载荷自比较（vacuous） | **已修**：期望改为在 store 写侧抓取压缩流（`u_dut.u_p4.core_out_data/core_out_keep`，经 `wr_begin` 分帧），与 `u_mem.mem` 完全解耦 |
| 载荷全 0 | **已定位到地址标度**（见 §2），尚未修完 |
| F6 两帧载荷相同 | **同时修正**：新增 `STREAM_DIFF`（两帧写侧流逐字节比较）与 `STREAM_EXP`（帧内长度=exact_bytes）断言；因载荷仍全 0，本轮如实输出 `FAIL stream: the two frames carry identical compression streams` / `POS_RESULT=FAIL stream_identical` |
| F4-header | 保持 pass（`hdr_err=0`，`length=32DW`，`addr=+128B×i`，doorbell 正确） |
| F3/F5/F7、E1–E8 | 未回归（预算耗尽）；E5/E7/E8 与独立解析器/变异重注入可由测试者按新 manifest 复用 |

## 2. 决定性证据：写侧有真数据、读侧地址不同

新增只读探针（`AWDBG`/`ARDBG`/`MEMDBG`，`sim\logs\r1-mem_0_20261027_184412.log`）：

```
AWDBG t=9315000  addr=00040000 data0=78 strb=00000000     <- store 写：字节地址 0x40000，数据非零
ARDBG t=56805000 addr=00040000 len=0                      <- store 排空读：同一 0x40000
MEMDBG mem[2048]=0000…0000  mem[8192]=ad728d728d07738d…ff5f00a0009c78
```

- **写侧真实**：`mem[8192]` 已含该帧压缩流（`ad 72 8d 72 …`），与写侧抓取基准一致 → 压缩/存储/写通路**都能工作**。
- **读侧错位**：pusher 用描述符 `slot_word=2048 → 0x10000` 读取，因此读到 `mem[2048]`（全 0）。写侧实际落在 `mem[8192]`（= `slot_word×4` 的字节 0x40000）。
- 即：**store 写/排空路径与 pusher 读路径的地址标度相差 ×4**，与设计指南已记录的"DDR 地址 ×4 重映射（仅仿真模型成立）"是同一处未闭合项。
- 已排除：压缩流为空（否）、写数据通路为零（否）、写地址=读地址（否）、写握手丢词（`wr_beats` 与 `mem[8192]` 内容均正常）。

## 3. 本轮改动（工作根副本，均带行内理由）

| 文件 | 改动 | 改后 SHA256 |
|---|---|---|
| `rtl\board\p2_ddr_bridge.v` | `paxi_awaddr`/`paxi_araddr` 由 `{idx,3'b000}`（×8）改为 `{idx,5'b00000}`（×32）：256-bit 字索引 → 字节地址，与 pusher 的字节寻址统一 | 见 manifest |
| `rtl\int\integrated_delivery_top.v` | store `BASE_WORD(32'd0)` → `BASE_WORD(SLOT_BASE_WORD)`：store 必须写在该帧描述符声明的 P2 槽基址 | 见 manifest |
| `tb\tb_brd_g1.v` | 写侧独立基准（`expbuf`）、`STREAM_EXP`/`STREAM_DIFF` 断言、`AWDBG`/`ARDBG`/`MEMDBG` 只读探针 | 见 manifest |

未改：`rtl\p4\**`（14/14 仍与包1 `manifest-r0b.json` 全等）、`rtl\ref\**`、`aplus_pcie_egress_adapter.v`（工作副本=生产源=`39301dc7…a71c`）、生产源。

## 4. 未完成与最小下一步（单点，1 处改动）

**唯一阻塞**：pusher 读取基址应为 `slot_word × 128`（0x40000）而不是 `slot_word × 32`（0x10000），以与 store 写/排空路径一致。

- 最小改法（工作根副本 `rtl\board\brd_board_datapath.v`）：`m_slot_base_bytes = {m_slot_base_word[26:0], 5'b0}` → 按 ×4 生成（`slot_base_word × 128`），并同步 `PUSH_BASE0/PUSH_BASE1` 的 `par_valid` 参数，使 `claim_base_ok` 语义不变（`ddr_base!=0 && ddr_base[11:0]==0` 仍成立：0x40000 低 12 位为 0）。
- 之后须跑：SCEN=0(NF=3) 两帧（每帧 `compared==exact_bytes>0`、`mismatch==0`、`hdr_err==0`、`STREAM_EXP` 长度相符、`STREAM_DIFF>0`）、SCEN=3 反压、`tb_brd_neg_both`、E4 复跑；再复核 rel_src=ACK 与错误 ACK 不释放。
- 若该改动使 `claim_base_ok` 或 ARM 判据语义需要变化 → 按规停止交规划（本候选的 ARM 判据不得放宽）。

## 5. 阻塞与预算

- `reason_code=LIMIT_REACHED`；`problem_id=T11.export-arm-sim:LIMIT_REACHED:ddr-addr-scale`
- 本轮：约 27 次调用 / 44 min；vsim 4 次（r1-close、r1-addr、r1-mem、+1 次编译失败的重试不计场景）。
- 未运行/未复测项一律 `not_run`，未写成通过；F4/F6 仍 **fail**（载荷全 0），F3/F5/F7 未回归。
- 交原规划的判断点：是否就此停止并由规划决定"仅补这一处地址标度后复测"，还是转用户裁定。
