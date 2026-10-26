# readback-criteria.md — 读回判据绑定与记录模板（冻结，T11.runB-debug-spec）

- 权威来源：`upstream/ph1p100-pcie-ep-fpga/tools/bringup/registers-plan.md`（表 + §5 hand-off 规则）与 `expected_rules.json`（R 规则）；阈值 = 本 run `dev-plan.md` §3.4/§5。**本文件不改判据、不新造语义**。
- 适用范围：P3 上板读回判定；P1/P2 只复用其中的字表/映射，不产生板测结论。
- G 层影响（冻结）：本包纯文档 = **G0**；G1/G2/G3 **not_run**（不适用理由：不涉 RTL/构建/硬件）。本判据在 P3 前不构成任何 PASS。旧 bit `e81d353b…2b9a` 与新 debug 位流**并列不混拼**：回退 = 重下旧 bit；不得以旧证据充新候选。

## 1. 规则绑定（A 组必读字 + 本轮相关规则）

| 偏移 | 名称 | 期望/解码 | 规则 id |
|---|---|---|---|
| 0x040 | MAGIC | == `0x50434946`（不符 → 停） | R01_MAGIC |
| 0x118 | EXT_MAGIC | == `0x31414B52`；`0xDEADBEEF` = 扩展缺失 → 停 | R03_EXT_MAGIC |
| 0x11C | EXT_VERSION | == `0x00010000` | R04_EXT_VERSION |
| 0x0A0 | DDR_SEQ_A | 单调不减；采集活时样本间增长（R05/R07/R16 的 when 前提） | —（precondition） |
| 0x0A4 | DDR_BASE_A | seq>0 时非零，且 **128 B 对齐**（低 7 位=0） | R16 / R07 |
| 0x0AC | DDR_LEN_A | seq>0 时 == **2,592,768** | R05 |
| 0x120 | CSI_DIAG_A | 原文 + 解码 `{good[31:24], bad[23:16], hdr_err[15:8], crc_err[7:0]}`（人工诊断，无规则） | — |
| 0x124 | CSI_DIAG_A2 | `{last_lines[31:16], last_wc[15:0]}`（人工诊断） | — |
| 0x044 | CTRL | bit4=0 且 [31:9]=0（mask `0xFFFFFE10`）；调试版另行核验 bit0/bit5/bit6/bit7（`enable-state.md` §3） | R02_CTRL_RESERVED |
| 0x0A8 / 0x0E8 | DDR_STATUS_A/B | mask `0x0000FFE0` == 0 | R09 / R10 |
| 0x0C0 / 0x0C4 / 0x0CC | PUSH_DONE/STATUS/TLP_CNT | 见 R11/R15 | R11 / R15 |
| 0x0C8 | PUSH_ERR | 0..4 | R12 |
| 0x0F4 | CAM_DROP_A3 | mask `0xFFFFFFC0` == 0 | R14 |
| 0x108 | TX_CMD | 读恒 0 | R17 |

- 未列 R06/R08/R13 属 B 路/扩展窗口，非本轮 Tier-1；如现场读回可附注，不升级为门槛。
- 字段字节序 = **左高右低**（与 RTL 拼接一致，registers-plan Notes）；解码前以 `ep_bar_win.v` header 复核（P1/P3 各一次）。
- 偏移为 **dword 偏移**，不传字节地址。

## 2. 板测判定（Tier 划分，与 dev-plan §3.4/§5 一致）

- **Tier-1（硬门槛）**：0x040=`0x50434946`、0x118=`0x31414B52`、0x11C=`0x00010000` **三字全中** + ≥1 组计数可复读（两样本一致或可解释）。任一不符 = Tier-1 FAIL。
- **Tier-2（基线/采集）**：0x0A0 单调且 ≥1；0x0A4 非零且 128 B 对齐；0x0AC=`2,592,768`；CSI 解码原始值 + good 增长（相机活，单 A）。
- Tier-1 过而 Tier-2 为 0/静止：**记录原值**并按“使能默认/采集状态”（`enable-state.md`）归因，交原规划判定；不得改判据求 PASS，不得以目视替代读数。
- 采样要求：**≥2 样本、间隔 ≥10 s**；每样本 9 字原文（十六进制原样）。
- 非原子告示：同一 CWC 实例内信号视为同时；跨实例/跨时刻分开记录，禁止合并成一次“原子快照”（guide §5/§6）。
- 跨域说明：0x120/0x124 经两级同步进入 `tl_clk_user`，跨域瞬间可能差一拍（ep_bar_win.v L123-124）—— 属可解释差异，须原文记录。
- 不适用/禁止（本轮）：PCIe/BAR0 主机读（用户已排除）；`JTAG_REG_ACCESS` 盲试（A0 结论：无文档语义，`cwc-flow.md` §1）；UART（架构不可用）；Flash/efuse/SPI/SVF（禁止，命令审计零命中）。

## 3. 记录模板（复用 `run_record.schema.json` 字段 + 已声明扩展）

- 每条记录字段（字段名沿用 schema）：
  - `schema_version`=1；`run_id`=`20261018-1631_runA_fpga_side_readchannel`；
  - `timestamp`（`YYYY-MM-DDThh:mm:ss` + 时区，pattern 兼容 schema）；
  - `operator`（真实操作者）；
  - `channel`：**扩展值**。原 enum（offline-register-dump / bw-jtag-session-log / pcie-host-bar0 / uart-command / synthetic）无 CWC 值，本 run 内声明扩展值 **`chipwatcher-jtag`** 并保留兼容字段（guide §6 允许“扩展须在 run 内声明”）；如后续要求严格原 schema，可另存并行“原文表”并在 notes 注明映射。
  - `tool`={name:"TD ChipWatcher", version:"2026.2"}；`input`={path:`compiled.cwc`, sha256}；
  - `readings[]`：每字 `{offset, offset_hex, name, value, value_hex, raw:"CWC 原文"}`（offset 为十进制 dword，offset_hex 形如 `0x040`→schema 允许 `0x[0-9A-F]{3}`）；
  - `verdicts[]`：`{rule_id, offset, name, verdict(pass|fail|blocked|not_applicable), detail, source}`；
  - `summary`（pass/fail/blocked/not_applicable 计数 + verdict）；`notes[]`。
- 每条读数必须绑定：通道（CWC 实例名）、bit SHA256 + BID、命令与退出码、输入哈希；目视现象不得单独作判据（guide §6）。
- 失败保留：Idle/Triggered=0/无波形等界面原文原样入 `notes`，不判硬件故障（guide §5）。
- 板测记录必须含：操作者、时间（含时区）、bit/DB 身份、命令与退出码、读数原文、恢复/回退记录（guide §6）。
