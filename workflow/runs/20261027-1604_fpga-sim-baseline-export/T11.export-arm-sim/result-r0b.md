# T11.export-arm-sim — result r0b（dev iteration 1，**blocked**，冻结交接）

- task_id `/` run `/` 轮次：`T11.export-arm-sim` / `20261027-1604_fpga-sim-baseline-export` / **round0-attempt2（dev iteration 1）**
- 状态：**blocked**。已冻结 `manifest-r0b.json`；`manifest-r0.json` 与 `result-r0.md` 保持原字节未改。
- 上轮文档笔误更正：r0 冻结的 manifest 实际为 **76 文件**（非 46；46 是排除 `sim/logs` 之前的计数）。本文件与 r0b manifest 均按 **76/76** 口径。
- 口径未越界：仅仿真内板级数据通路；G2/G3/G4 = `not_run`；不称真实 PCIe/最终时序/双路实时。

## 1. D3 三分法判别（**结论已达成**，12 次检查点内）

探针为 TB 内只读层次观测（`-voptargs=+acc`，无 force/无层次赋值）。判别日志：`sim\logs\d3-probe_0_20261027_173326.log`。

| 支路 | 原始值（`TXDBG`，usr_clk 域） | 结论 |
|---|---|---|
| AR 是否发出 | `ar_hs=1`（pusher `m_axi_arvalid & m_axi_arready` 恰 1 次），之后 `p_arvalid=0` | **已发出**（1 个 128-beat burst 覆盖整帧） |
| R 是否返回 | `ddrR_hs 124→252`（+128），`m_rvalid` 有拍、`mem_rd_busy` 归 0、`mem_rd_left=0` | **已返回 128/128** |
| 消费是否推进 | `puR_hs=128`（`m_axi_rvalid & m_axi_rready`） | **已全部消费** |

→ 排除 arb 未授权、排除 DDR 模型未回数。停滞在**消费之后**：`p_st=2`（`S_HEAD`）冻结、`utx_req` 不推进。

## 2. D3 根因与修复（允许位置 `rtl\board\brd_board_datapath.v`）

- 根因：`ddr_frame_pusher` 把 `utx_sel` 当作 TL 发送**授权**输入（`utx_ack = utx_sel && !tl_tx_wait && beat_present && beat_ready`），而板级外壳把 `utx_sel` 声明为**输出**并把这条无驱动网络接回 pusher 的输入 → `utx_ack` 永不成立 → 读完整帧后永久停在 `S_HEAD`，无 MWr、无 doorbell。
- 修复（最小，不改任何判据）：新增内部 `wire pu_tl_grant = link_up;`，pusher 接 `pu_tl_grant`，并 `assign utx_sel = pu_tl_grant;` 保持端口可观测。语义=缩尺数据通路内"链路 up 即 TL 口常授权"，只驱动原先悬空的 DUT 输入。
- 修复后（`sim\logs\d3-close-nf3_0_20261027_173839.log`、`d3-close2_0_20261027_174056.log`）：
  `PAYLOAD_COMPARE frame=1 seq=2 slot_word=2048 exact_bytes=3965 compared=3965 mismatch=0 tlps=32 doorbell=1 db_val=2`
  → **F4 单帧达成**（`compared==exact_bytes>0`、`mismatch==0`，32×128B MWr + 1 doorbell）。

## 3. 未闭合：≥2 帧（F3/F6 仍 fail/not_run）

`ADMIT gs=0 free_v=1 has_rdy=0 eg_busy=1 dr_busy=0 ap_busy=0 wr_started=0 cfg_dirty=0 admit_ok=0 slot_st=00000010 b_act=1`

- 第 1 帧导出、doorbell、释放都发生（`rel_count` 2），但 **`egress_busy=1`**：`aplus_pcie_egress_adapter` 未回到 `S_IDLE`，`admit_ok=0` → 不再准入新描述符 → 第 2 帧永不发布（`desc_timeout`）。
- 该释放来自 `integrated_delivery_top` 的 `GS_WAIT_REL` 看门狗（`ACK 后 27834 tl cycles ≈ 66750 core cycles ≈ 0xFFFF`），**不是** ACK 被接受；即 ACK 的 `seq` 约定仍不匹配：TB 用 doorbell 载荷 `db_val`（=2）回 ACK，而 adapter 比对的是 `brd_pcie_track` 送来的 `pcie_held_seq`（由 `tx_status`/done 派生），两者当前不等 → 误判为 bad ACK、停在 `S_HELD`。
- 这是下一轮唯一剩余阻断（单点，1 条探针 + 1 处取值/接线即可判定），但**本轮预算已用尽**（约 29 次调用 / 50 min / 6 次 vsim 场景已用 5 次），按合同停止，不再试参。

## 4. 本轮实际运行与产物

| 项 | 值 |
|---|---|
| vsim 场景 | 5 次：`d3-probe`(NF=2)、`d3-fixed`(NF=2)、`d3-close-nf3`(NF=3)、`d3-close2`(NF=3)、+ r0 的 before-fix 不计入本轮 |
| 编译 | `COMPILE_OK`，0 error / 0 warning |
| 修复点 | `rtl\board\brd_board_datapath.v`：D1（`a_seq/b_seq` 复位 1）、D2（释放身份极性）、**D3（`utx_sel` 授权）**；三处均带行内理由 |
| 未改 | `rtl\p4\**`（14/14 SHA 仍与包1 `manifest-r0b.json` 全等）、`rtl\ref\**`、pusher 任何判据 |
| TB 变化（仅模型侧） | 多帧/反压/负例 harness；TLP 解析改为 pusher 实际拍格式（header 在 beat0 DW0..3，载荷从 beat1 起）；`utx_valid!=0` 限定；门铃按"单拍 TLP"识别；新增 `TXDBG`/`ADMIT` 只读探针 |

## 5. 三维与 G 层（规划门槛逐条）

**functional / G1**

| 项 | 结果 | 依据 |
|---|---|---|
| F1 before-fix 见证 | **pass** | `evidence\before-witness\before-fix_0_20261027_170306.log`（r0 冻结），`committed=1/pub=1/drain=124/arm=0/exported=0/tlp=0/db=0`，`not_executed` |
| F2 根因 + 变异重现 | **pass（D1/D2/D3）** | D1/D2 见 `result-r0.md` §3；D3 见本文件 §1–§2，判别日志为原始探针；变异负例=`tb_brd_neg_base`/`tb_brd_neg_cap`（本轮未运行，见 §3 预算） |
| F3 ≥2 帧导出 | **fail** | 单帧成立；第 2 帧被 `eg_busy=1` 阻断 |
| F4 逐字节 | **pass（已导出帧）** | `compared=3965 == exact_bytes=3965`、`mismatch=0`；未导出帧显式 `NOT_EXECUTED=1` |
| F5 反压 | **not_run** | SCEN=3 harness 已写，未运行 |
| F6 槽复用 | **not_run** | 依赖 F3 |
| F7 ACK/释放 | **partial** | 描述符释放发生但来自看门狗；正常 ACK 未被接受（§3） |

**engineering / G0+G5**

| 项 | 结果 |
|---|---|
| E1 编译展开 0 error | **pass** |
| E2 关键路径 0 X | **partial**（首轮 `integer` 未初始化致 `x` 已修；系统性 X 扫描未做） |
| E3 闭包 SHA + 一次复跑 | **pass**（`manifest-r0b.json`） |
| E4 两次运行一致 | **not_run** |
| E5 P4 14 份 SHA 全等 | **pass**（`mismatch=0`） |
| E6 G2/G3/G4 not_run | **pass** |
| E7 静态 `sources.f` | **pass**（37 条） |

**system**：S1–S3 见 `result-r0.md` §5–§7（仍有效）；S4 口径未越界。

## 6. 未实现协议责任（6 条，未变）

见 `result-r0.md` §6；本轮未新增实现，未把离线补头/模型填零写成硬件实现。

## 7. blocked 与最小下一步

- `reason_code=LIMIT_REACHED`（本轮约 29 次调用 / 50 min；vsim 场景 5/6）。12 次检查点目标（D3 三分法判别）**已达成**，非无进展。
- 剩余单点：`pcie_held_seq`/`pcie_held_sess`（`brd_pcie_track`）与 doorbell 载荷的 ACK 约定必须对齐；对齐后 `egress_busy` 归 0 → 第 2 帧可准入；随后跑 SCEN=0(NF=3) 两帧、SCEN=3 反压、`tb_brd_neg_base`/`tb_brd_neg_cap`、E4 复跑，再冻结 `manifest-r0c.json`。
- 建议下一轮预算：判别 4 次、修复 4 次、回归 8 次（含 4 个 vsim 场景）、收尾 4 次。
