# T11.export-arm-sim — result r0c（dev iteration 2 / round0-attempt3，**blocked**）

- 状态：**blocked**（`SCOPE_CLARIFICATION`：证据指向生产适配器 `aplus_pcie_egress_adapter.v`，属本轮禁止修复位置）。
- 已冻结 `manifest-r0c.json`；`manifest-r0.json`、`manifest-r0b.json`、`result-r0.md`、`result-r0b.md` **字节未改**。
- 口径更正（按规划 §4 要求）：上一轮把 F4 报成"单帧达成"属**过度报喜**。正确口径是：
  - r0b：**载荷逐字节 pass / TLP 头字段 fail（hdr_err=65）** → F4 = partial。
  - r0c（本轮）：**载荷 + 头字段同时 pass（`hdr_err=0`）**，但仅 1 帧导出，F4 整体仍 **partial**（"≥2 帧"不满足）。
- 全局口径未越界：仅仿真内板级数据通路；G2/G3/G4 = `not_run`。

## 1. 判定 ①：TLP 头字段 = **TB 解析位置错**（已修 TB，非 DUT 错）

**原始值（`RAW_SOP`，按 256-bit 拍 MSB→LSB 打印，`sim\logs\a3-close_0_20261027_175211.log`）**

```
RAW_SOP t=144152000 MSB..LSB = 60000020 010000ff 00000000 01000000 00000000 00000000 00000000 00000000
RAW_SOP t=144248000 MSB..LSB = 60000020 010000ff 00000000 01000080 00000000 00000000 00000000 00000000
```

- `hdr_dw0 = 0x6000_0020`：`MWR_FMT_4DW|MWR_TYPE` + `PAY_LEN=0x20`（**32 DW**，符合约定）。
- `hdr_dw1 = 0x0100_00ff`；`hdr_dw2 = 0x0000_0000` = `addr[63:32]`；`hdr_dw3 = 0x0100_0000` = `{addr[31:2],2'b00}` → 地址 `0x0100_0000`，第二拍 `0x0100_0080`（**+128B/TP**，符合约定）。
- 引用：`ddr_frame_pusher.v` L566-567 `utx_data = {hdr_dw0, hdr_dw1, hdr_dw2, hdr_dw3, 128'd0}`（k==0）→ 头 DW 落在拍的**高半部**（`dw_all[7..4]`），低半部为 0；L542-547 `hdr_dw0/hdr_dw2/hdr_dw3` 定义；载荷拍为低 DW 优先（`dw_all[8]` 起）。
- 原 TB 按 `dw_all[0..3]` 解析头 → 恒读到 0（`length 0`、`addr 0`），32×2+1 = **65** 条 header 失败全部由此产生。**不是 DUT 头字段错误**。
- 修复（仅 TB 模型侧）：头改读 `dw_all[7]=hdr_dw0..dw_all[4]=hdr_dw3`，门铃载荷改读 `dw_all[3]`（`{db_dw0..3, bswap32(db_val), 96'd0}`），地址比较用 `{dw_all[5],dw_all[4]}`。
- 修复后：`PAYLOAD_COMPARE frame=1 seq=2 exact_bytes=3965 compared=3965 mismatch=0 tlps=32 doorbell=1 db_val=1 hdr_err=0` / `FRAME_RESULT frame=1 PASS`（`sim\logs\a3-ack_0_20261027_175427.log`）。
  → **F4-header-fields 对已导出帧 pass**：`length==32DW`、`addr==base+128B×i`、doorbell 地址 `0x0200_0000` 与载荷一致、`hdr_err==0`。

## 2. 判定 ②：ACK 约定 = **值已对齐，但适配器未接受**（指向禁止位置）

**约定（引用）**

- `brd_cdc_mailboxes.v` L362-363：`o_pcie_held_seq <= i_arm_seq; o_pcie_held_sess <= i_arm_sess;`
- `brd_board_datapath.v` L489-499：`tl_arm_seq <= m_capture_seq`（ARM 时的 **capture_seq**），`tl_arm_sess <= m_session_id`。
- 适配器 `S_HELD`：`ack_pulse && (ack_seq==held_seq_r) && (ack_session==held_sess_r) && (ack_session!=0)` → `slot_release`。
- ⇒ 正确约定 = **ACK(seq = 该帧 capture_seq, session = cfg_session_id)**。（doorbell 载荷是 pusher 的 push 计数，**不是** ACK seq：本轮 `db_val=1` 而 capture_seq=2。）

**实测（`sim\logs\a3-ack_0_20261027_175427.log`）**

```
ACK_SEND  frame=1 seq=2 db_val=1 sess=a5a50001 | held_seq=2 held_sess=a5a50001
          tl_arm_seq=2 tl_arm_sess=a5a50001 m_sess=a5a50001 eg_state=3 wd_cnt=587
ACK_PROBE frame=1 xack_cnt=1 ack_start=0 ack_free=1 ack_valid=0 x_ack=0 eg_state=3 wd_cnt=651 slot_rel=0
INFO frame=1 ACK(seq=1) released the slot after 27810 tl cycles (rel_count=2)
```

- TB 已按约定发 ACK（seq=capture_seq=2, session=0xA5A50001）；`xack_cnt=1` 证明 ACK 脉冲**已跨到 clk_core**（`brd_ack_xing` 正常）。
- 适配器侧寄存器快照 `held_seq_r=2`、`held_sess_r=0xA5A50001`、`state=S_HELD` 与 ACK 值**完全相等**，但 `slot_release` 未脉冲（`slot_rel=0`，60 core cycles 后仍 `S_HELD`），释放仍由 `GS_WAIT_REL` 看门狗产生（27810 tl cycles ≈ 0xFFFF core cycles）。
- 已排除：ACK 未跨域（`xack_cnt=1`）、seq/session 取值错（快照与发送值相等）、`ack_free` 卡死（`ack_free=1`）、适配器未进入 `S_HELD`（`eg_state=3`）、doorbell/载荷/头字段（见 §1）。
- 未排除但无法在允许位置内继续：`ack_pulse` 与 `S_HELD` 的采样边沿关系、或适配器 `S_HELD` 接受条件本身的实现。二者都落在 **`aplus_pcie_egress_adapter.v`（本轮禁止修改）**，按指令**停止并 blocked**，不自行改生产适配器。

## 3. 三维 / G 层（本轮）

| 项 | 结果 |
|---|---|
| F1 before-fix 见证 | pass（沿用 r0 冻结日志，未改） |
| F2 根因 + 变异负例 | D1/D2/D3 见 r0/r0b；**本轮变异负例未运行** |
| F3 ≥2 帧 | **fail**（1 帧导出后 `eg_busy=1` 阻断准入） |
| F4 载荷 | pass（`compared=3965==exact_bytes`、`mismatch=0`） |
| F4-header-fields | **pass（已导出帧）**：`hdr_err=0`、`length==32DW`、`addr==base+128B×i` |
| F5 反压 | not_run |
| F6 槽复用 | not_run（依赖 F3） |
| F7-release-source | **fail**：正常场景释放仍 `rel_src=WDG`（要求 ACK） |
| E2 X 扫描 / E4 复跑 / neg_base / neg_cap | not_run（本轮 vsim 3/5，预算耗尽） |
| E1/E3/E5/E6/E7 | pass（编译 0 error；P4 14/14 SHA 全等；静态 `sources.f` 37 条） |

## 4. 未实现协议 6 条 / 模型边界

沿用 `result-r0.md` §5–§6，本轮未新增实现；离线补头/模型填零未写成硬件实现。

## 5. 阻塞与最小下一步

- `reason_code=SCOPE_CLARIFICATION`；`problem_id=T11.export-arm-sim:SCOPE_CLARIFICATION:ack-adapter`
- 需规划裁定：是否允许改 `aplus_pcie_egress_adapter.v`（生产 EP 侧）的 `S_HELD` ACK 接受路径，或新增一个可观测的内部信号以区分"脉冲未被采样"与"比较失败"。当前 `result` 不能据此判 DUT 坏，也不能在禁止位置内继续。
- 若获准：改动点仅在 `S_HELD`（保持 seq/session 比较语义不变），然后跑 SCEN=0(NF=3)、SCEN=3、neg_base、neg_cap、E4 复跑，冻结 `manifest-r0d.json`。
- 若不准：本证据包已可交付——同一冻结候选真实产生 32×MWr + 1 doorbell，载荷 3965/0 + 头字段 0 错误，D1/D2/D3 三处板级缺陷已定位并修复；剩余为 ACK 接受失败（1 处，定位到适配器 `S_HELD`）。
