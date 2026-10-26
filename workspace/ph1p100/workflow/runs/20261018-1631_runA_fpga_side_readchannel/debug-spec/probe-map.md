# probe-map.md — 读回字 ↔ 探针/调试字库映射（冻结，T11.runB-debug-spec）

- 依据：`fpga-design-guide.md` §1/§2；`upstream/ph1p100-pcie-ep-fpga/tools/bringup/registers-plan.md` 表；`rtl/ep_side/img/ep_bar_win.v`（2026-10-18 检出工作树；行号=该版本）；`rtl/ep_side/ph1p_pcie_ep_top.v`、`rtl/ep_side/pcie_ep_engine.v` 只读核对。
- 本表**不新造寄存器语义**：期望值/解码全部来自 registers-plan / expected_rules.json；探针名是层次路径，P1 以 elaboration/仿真复核后回写（guide §2）。

## 1. 冻结决策

1. **CWC 实例**：1 个；时钟域 = `tl_clk_user`（ep_bar_win 所在域；`ph1p_pcie_ep_top.v` L254 注释“ep_bar_win ↔ 安全门，都是 tl_clk_user 域，直连”）。同实例内信号视为同时采样。
2. **载体**：采用**调试字库** `dbg_bank`（只读）承载 A 组 9 字（§2）；位宽 9×32 = **288 bit**；历史单实例 449 bit 为规模参照（≠保证）。
3. **降级路径**（P1 判定触发，须记 candidate diff）：① 单实例容量/位宽不足 → 同域**第二实例**拆分（B 组默认方式）；② 字库方案不可行 → 直探 §4 信号清单。**降级不得改变 A 组判据**。
4. **B 组加装条件**：A 组读回稳定后，或现场需定位丢帧/推帧/状态位图问题时，按需加第二同域实例（默认候选：`cam_drop_a` 丢弃计数）；**B 组不并入 A 组样本，跨实例分开记录**。

## 2. 调试字库（dbg_bank）冻结契约

- 形式：只读组合镜像；源 = ep_bar_win 内部信号/编译期常量；**无副作用**（不驱动任何控制/总线/外发路径，不改变既有复位、计数、仲裁行为）。
- **BAR0 读地址表**（dword 偏移；属非合同 diag，先例 = 0x120..0x12C 同类“不在合同里”；按 `docs/protocol/rka1-r10f-v1/contract/registers.json` 十进制偏移只读检索，无 ≥320（0x140）占用）：

| 字库偏移 | 字序 | 镜像原偏移 | 名称 | 源（ep_bar_win.v） |
|---|---|---|---|---|
| 0x140 | word0 | 0x040 | MAGIC | 参数 `MAGIC=32'h5043_4946`（L129；读 mux L435） |
| 0x144 | word1 | 0x118 | EXT_MAGIC | 参数 `MAGIC_RKA1=32'h3141_4B52`（L133；L499） |
| 0x148 | word2 | 0x11C | EXT_VERSION | 参数 `VERSION_RKA1=32'h0001_0000`（L134；L500） |
| 0x14C | word3 | 0x0A0 | DDR_SEQ_A | `ddr_ro[31:0]`（端口 L163；L479） |
| 0x150 | word4 | 0x0A4 | DDR_BASE_A | `ddr_ro[63:32]`（L480） |
| 0x154 | word5 | 0x0AC | DDR_LEN_A | `ddr_ro[127:96]`（L482） |
| 0x158 | word6 | 0x120 | CSI_DIAG_A | `csi_diag_a`（端口 L200；L502） |
| 0x15C | word7 | 0x124 | CSI_DIAG_A2 | `csi_diag_a2`（端口 L201；L503） |
| 0x160 | word8 | 0x044 | CTRL（读回字） | `{23'd0, ctrl_cam_ab, ctrl_push_src, ctrl_push_en, ctrl_ddr_en, 1'b0, ctrl_pattern_r, ctrl_trigger, ctrl_enable}`（L439-440） |

- 契约：
  1. 每 word 值必须**逐位等于**对应原偏移的读回复现值（P1 用 TB 证明，覆盖正常帧与边界帧）；
  2. 字序固定，不得重排；只读，禁止可写别名；
  3. 插入新 case 不得改变任何既有偏移读值（`default: 32'hDEAD_BEEF`，L506）；
  4. 选址顺延规则：若 P1 以 elaboration/顶层解码复核发现 0x140..0x160 冲突（合同未来偏移/保留区），顺延到下一连续未占用 dword 段，并记 candidate diff；字序与判据不变。
  5. `csi_diag_a/a2` 系 checked CSI 字节域经两级同步后的同域快照（ep_bar_win.v L123-124），跨域瞬间可能差一拍；允许解释性差异，原文记录（guide §6）。

## 3. CWC 探针表（主选：字库载体，1 实例）

- 层次链（只读推导，**P1 必须用 elaboration/仿真复核并回写**）：`<工程顶层>/…/pcie_ep_engine（实例名待 P1 确认；例化见 `pcie_ep_engine.v` L389/L394：`ep_bar_win #(…) u_ep_bar_win (…)`）/u_ep_bar_win/dbg_bank[...]`。
- 探针信号（建议名；以 TD 生成为准）：

| CWC 信号（建议） | 位宽 | 覆盖字 |
|---|---|---|
| dbg_bank_word0[31:0] | 32 | 0x040 MAGIC |
| dbg_bank_word1[31:0] | 32 | 0x118 EXT_MAGIC |
| dbg_bank_word2[31:0] | 32 | 0x11C EXT_VERSION |
| dbg_bank_word3[31:0] | 32 | 0x0A0 DDR_SEQ_A |
| dbg_bank_word4[31:0] | 32 | 0x0A4 DDR_BASE_A |
| dbg_bank_word5[31:0] | 32 | 0x0AC DDR_LEN_A |
| dbg_bank_word6[31:0] | 32 | 0x120 CSI_DIAG_A |
| dbg_bank_word7[31:0] | 32 | 0x124 CSI_DIAG_A2 |
| dbg_bank_word8[31:0] | 32 | 0x044 CTRL 读回字（使能核验） |

合计 288 bit；单实例建议名 `cwc_a`（或 `auto_created_cwc`，以 TD 生成为准）；触发方式：**Instant Trigger**（异步观察，不设复杂条件；与 10-14 文档流程一致）。
- 记录要求：每样本记录实例名 + TD 版本 + `compiled.cwc` SHA；同实例内 9 字视为同时；跨实例/跨时刻分开记录，禁止拼成“原子快照”（guide §6）。

## 4. 降级直探清单（仅当 P1 判定字库不可行）

| 内部信号 | 位宽 | 覆盖字 |
|---|---|---|
| `ddr_ro[127:0]` | 128 | 0x0AC/0x0A8/0x0A4/0x0A0（字序 `{len,status,base,seq}`，top.v L161；L479-482） |
| `csi_diag_a[31:0]`、`csi_diag_a2[31:0]` | 64 | 0x120 / 0x124（L200-201） |
| `ctrl_*` 位集合（9 位，L439-440） | 9 | 0x044 |
| `cam_drop_a[95:0]` | 96 | 0x0DC/0xF0/0xF4（B 组，L152、L466-468） |
| `push_ro[127:0]` | 128 | 0xCC/0xC8/0xC4/0xC0（B 组，L165、L488-491） |
| `ddr_ro_b[127:0]` | 128 | 0xEC/0xE8/0xE4/0xE0（B 组，L147、L469-472） |

- 直探模式下 MAGIC/EXT_MAGIC/EXT_VERSION 为编译期常量，无稳定信号可探：需 P1 增加只读常量线，或明确由 G1/G2 的 RTL 复核承担；**不得以未证实读数代替**。该取舍记 candidate diff。
- B 组直探默认第二同域实例：优先 `cam_drop_a`（丢弃计数）；其余按现场需要。

## 5. 名字来源复核（只读，2026-10-18）

- 端口/内部名：`ddr_ro`（L163）、`ddr_ro_b`（L147）、`csi_diag_a/a2`（L200-201）、`cam_drop_a`（L152）、`push_ro`（L165）、`ctrl_enable/ctrl_trigger/ctrl_pattern_r/ctrl_cam_ab/ctrl_ddr_en/ctrl_push_en/ctrl_push_src`（L154-167 端口、L272-278 复位、L310-317 写入）。
- 例化：`pcie_ep_engine.v` L389-394 `ep_bar_win #(…) u_ep_bar_win (…)`；域注释 `ph1p_pcie_ep_top.v` L254。
- 注意：registers-plan 引用的 `ep_bar_win.v:350` 等行号与本工作树版本不一致（本工作树 MAGIC 读 case 在 L435）；**以偏移/期望值为权威**，行号只作定位线索。

## 6. P2 elaboration 复核结果（追加，2026-10-18）

- 复核环境：frozen commit `8e1ef05f…`、TD 2026.2 `00_all_debug` 单会话构建（`debug-build/prj_frozen`，exit 0，637 s）。
- **探针路径未能成立（blocked）**：冻结 RTL 中 `dbg_bank` 是“定义但未被使用”的组合 concat（读 mux 只用 `dbg_bank_word0..8`），且没有任何 `mark_debug`/ChipWatcher IP。`insert_debugger` 报 `KIT-2501: No mark_debug exists in the netlist`；`setup_debugger` 虽在 bitgen 后执行（run.log L2119），但未生成 `cw/compiled.cwc|bit`。
- **结论**：P2 无法在“RTL/约束冻结”范围内生成 CWC 探针；本表 §3 的 CWC 信号映射未实现，不得作为已验探针使用。修复需新 RTL/约束 commit（保留顶层层级 + mark_debug 或 CWC IP），见 `debug-build/candidate-manifest.json` 的 blocked_summary 与 `hardware-ready.md`。

## 6. P1-fix 验证构建复核（构建结果，2026-10-18）

- 实例：auto_created_cwc1（TD 流程 insert_debugger 自建）：9 view nodes / 288 trigger nets / 288 data nets；时钟 tl_clk_user。
- 探针源：u_top/u_pcie_ep_engine/u_ep_bar_win/g_dbg_mark/dbg_mark_word0..8（RTL MARK_DEBUG 寄存快照；仅 debug 顶层参数=1 时存在）。
- 产物：phy_1/cw/compiled.cwc（81,063 B，sha fa24e258…）+ cw/compiled.bit（与 phy bit 同 SHA 2385cded…）。
- 校验：check_chipwatcher_readback.py 判 BID width mismatch（单段/全深宽度等式假设与 TD 2026.2 自动 CWC 几何不符）→ 本候选 NOT READY，待原规划裁定（见 debug-fix/candidate-manifest.json）。