# T11.export-arm-sim — result r0d（dev iteration 3 / round0-attempt4）**ready_for_test**

- 状态：**ready_for_test**。已冻结 `manifest-r0d.json`；`manifest-r0.json` / `manifest-r0b.json` / `manifest-r0c.json` / `result-r0.md` / `result-r0b.md` / `result-r0c.md` **字节未改**。
- 口径：仅"仿真内完整帧导出"证据；G2/G3/G4 = `not_run`；不称真实 PCIe / 最终时序 / 双路实时。
- 判据未放宽：E8（POS 断言口径）、F7（rel_src）、F4-header（hdr_err）均按规划增补执行。

## 1. ① S_HELD 归因（8 次内结论）：**比较/接受失败，根因在板级 ACK 跨域打包，不在适配器**

- 排除"未被采样"：`ACK_PROBE xack_cnt=1`（r0c 日志）证明 `x_ack` 脉冲已到 clk_core，且 `ack_free=1`。
- 定位（静态逐位比对）：
  - `brd_ack_xing` 写侧 `in_bus = {cancel_pulse, ack_seq, ack_session}` → **LSB 半字是 `ack_session`、高半字是 `ack_seq`**。
  - 读侧原为 `o_ack_seq <= out_bus[31:0]` / `o_ack_session <= out_bus[63:32]` → **seq/session 互换**。
  - 适配器 `S_HELD` 用 `ack_seq==held_seq_r && ack_session==held_sess_r` 判定 → 收到的 `ack_seq` 实为 session（`0xA5A50001`），必然不等 → 每次 ACK 都被判坏，帧只能靠 `GS_WAIT_REL` 看门狗释放。
  - 这解释 r0b/r0c 的全部现象：`held_seq=2`/`held_sess=0xA5A50001` 与 TB 发送值相同却不释放，释放延时恰为 0xFFFF core cycles。
- **归因更正**：问题不在 `aplus_pcie_egress_adapter.v`（该文件未改，SHA 前后一致），而在板级 `brd_ack_xing` 的跨域位序。按规裁定 §2「若归因显示问题不在适配器而在板级接线 → 按既有允许位置修」执行。

## 2. ② 改动（仅 `rtl\board\brd_cdc_mailboxes.v` 的 `brd_ack_xing` 读侧切片）

| 项 | 值 |
|---|---|
| 文件 | `rtl\board\brd_cdc_mailboxes.v`（工作根副本） |
| 改前 SHA256 | `0f47df97bcd65139b3c882c7a8f5ace4ac7699ea15e076e515b75255b46d8e16` |
| 改后 SHA256 | `588c28fd2174159401359a757fddbc638d44bdbc2a15e847db759bbd68b859c7` |
| diff（有效 2 行 + 注释） | `o_ack_seq <= out_bus[31:0]` → `out_bus[63:32]`；`o_ack_session <= out_bus[63:32]` → `out_bus[31:0]` |
| 逐行理由 | 与写侧打包 `{cancel, ack_seq, ack_session}` 对齐；仅修正"取哪一半"，不改端口、不改 seq/session 比较语义、不改状态机骨架、不改输出定义 |
| 生产源 | **未改**：`aplus_pcie_egress_adapter.v` 工作副本 SHA 改前=改后=`39301dc7…a71c`，且与 `workspace/ph1p100/.../aplus_pcie_egress_adapter.v` 生产源**字节相同**；未写 `workspace/**`、`rtl/**`、`handoff/**` |

其它改动（均在既有允许范围）：
- `tb\tb_brd_g1.v`：ACK 双脉冲（先 `capture_seq`，再 doorbell 载荷；宿主同时知道两者，供 pusher 的 push 计数比较），E8 断言（`+REQ`）、X 计数（E2）、逐帧 TLP 索引（每帧从 `cfg_dst_lo` 重新开始）、错误 ACK 负例并入 SCEN=0、非法条件负例合并 top。
- 未改：`rtl\p4\**`（14/14 仍与包1 `manifest-r0b.json` 全等）、`rtl\ref\**`、`brd_board_datapath.v` 本轮无改动。

## 3. ③ E8：POS 断言口径修正 + 负对照

- 规则：`POS_RESULT=PASS` 仅当 `frame_fail==0 && x_cnt==0 && frame_ok==REQ`（`REQ` 默认 `NF-1`，可用 `+REQ=` 覆盖）。
- 负对照（同一 run 内自检，不作为独立运行）：`E8_NEGCTL gate(ok=2,req=2)=1 gate(ok=2,req=3)=0 expect 1_then_0` → 少一帧即判 FAIL，断言非空转。
- r0c 的 `POS_RESULT=PASS frames=1 of 2` 缺陷已消除（本轮 `a4-close` 在只有 1 帧通过时输出 `POS_RESULT=FAIL frames_ok=1 fail=1 req=2`）。

## 4. ④ 闭合回归（本轮 5 次 vsim，全部 exit 0）

| 场景 | 日志 | 结果 |
|---|---|---|
| SCEN=0 NF=3（正例，E4-A） | `sim\logs\a4-e4a_0_20261027_181513.log` | 2 帧 PASS |
| SCEN=0 NF=3（E4-B，同命令复跑） | `sim\logs\a4-e4b_0_20261027_181558.log` | 与 A 摘要逐项一致 |
| SCEN=3 NF=3（主机 `tl_tx_wait` + DDR stall 窗口） | `sim\logs\a4-bp_3_20261027_181607.log` | 2 帧 PASS |
| `tb_brd_neg_both`（非 4KiB 基址 + 容量不足） | `sim\logs\a4-neg_0_20261027_181614.log` | `POS_RESULT=NEG_PASS id=1/2` |
| 归因/中间态 | `sim\logs\a4-close_0_20261027_181405.log` | 1 帧通过（含错误 ACK 负例），POS 正确判 FAIL |

关键逐帧数据（A/B 与反压场景一致）：

```
frame=1 seq=2 slot_word=2048 exact_bytes=3965 compared=3965 mismatch=0 tlps=32 doorbell=1 db_val=1 hdr_err=0
frame=2 seq=3 slot_word=2048 exact_bytes=3966 compared=3966 mismatch=0 tlps=32 doorbell=1 db_val=2 hdr_err=0
INFO frame=1 ACK(seq=1) released the slot after 754 tl cycles (rel_count=2)
INFO frame=2 ACK(seq=2) released the slot after 754 tl cycles (rel_count=3)
INFO summary frames_ok=2 frames_fail=0 req=2 x_cnt=0 ddr_wr_beats=372 ddr_rd_beats=628
POS_RESULT=PASS frames=2 req=2 x_cnt=0
```

- **F3**：2 帧各 32×MWr + 1 doorbell，`st_exported` 递增（rel_count 2→3）。
- **F4**：每帧 `compared==exact_bytes>0`（3965/3966）、`mismatch=0`。
- **F4-header**：每帧 `hdr_err==0`；`length=32DW`；`addr=cfg_dst_lo+128B×i`（帧内重新起算）；doorbell 地址 `0x0200_0000` 与载荷（push 计数 1/2）正确。
- **F5**：反压场景 2 帧仍逐字节通过，释放 753/754 tl cycles，无死锁（自然结束，未触看门狗）。
- **F6**：两帧复用同一槽（`slot_word=2048`），第 2 帧 3966 字节全符，无上一帧残留（两帧激励内容不同，seed 0 / 370）。
- **F7**：`rel_src` = **ACK**——释放 754 tl cycles，而看门狗路径为 27810 tl cycles（0xFFFF core）；错误 ACK（`seq^1`）不释放（`NEG2_RESULT=PASS`）。
- **E2**：`x_cnt=0`（`utx_data` 有效拍与 `st_frames_committed` 无 X）。
- **E4**：两次同命令运行摘要逐项一致（上表）。
- **E1/E3/E5/E6/E7/E8**：编译 0 error；闭包 SHA 见 manifest；P4 14/14 全等；G2–G4 not_run；静态 `sources.f` 37 条；E8 见 §3。

## 5. 三维 / G 层

functional（G1）：F1 pass / F2 pass（D1–D4 根因 + 错误 ACK、非法基址、容量负例）/ F3 pass / F4(+header) pass / F5 pass / F6 pass / F7 pass。
engineering（G0+G5）：E1 pass / E2 pass（计数器型 X 扫描，非形式化）/ E3 pass / E4 pass / E5 pass / E6 pass（not_run 明示）/ E7 pass / E8 pass。
system：S1 模型边界、S2 未实现协议 6 条、S3 缩尺参数、S4 口径 —— 沿用 `result-r0.md` §5–§7，本轮未新增实现。

## 6. 边界与未实现（不因本轮通过而改变）

- 模型：相机=合成栅格、DDR=AXI 从模型（含 stall）、TLP=主机模型、BAR=TB 直驱；无真实链路/时序/ECC。
- 未实现协议 6 条：44B A1U1 头、页尾零填充、BAR `0x130..0x13C`/`CTRL[9..11]`、DDR ×4 重映射、A 路/双路、ACK 后全身份释放链与错误 session/epoch 负例。
- ACK 约定 `(seq=capture_seq, session=cfg_session_id)` 为**本候选冻结工作约定**，仍待队友在 RK/实机侧确认；doorbell 载荷=pusher push 计数，宿主同时知道两者，TB 以双脉冲建模（测试模型选择，非协议定版）。
- `not_run`：TD 综合/布线/STA/bitgen/CWC/下载/Flash（本机禁止）；真实 C2H、真实 DDR、双路、长稳。

## 7. 下一动作

交独立综合测试者（`input_status=changed`），报告 `OUTPUT_DIR\test-reports\T11.export-arm-sim-r0-integrated.md`；PASS 后由规划收尾（仍不 commit/push）。
