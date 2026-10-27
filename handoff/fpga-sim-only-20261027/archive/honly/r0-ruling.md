# r0-ruling — 20261027-055621_fpga-honly-td-and-ah（2026-10-27 07:30）

本次裁决只覆盖：Line A 的 kill 是否成立与如何关账、Line B 的 TD 租约重新判定与恢复、P3 放行条件、并发/记账异常登记。技术根因仍归开发/测试者，范围与验收归本规划。

规划自测时间：2026-10-27 07:26–07:31。规划本轮工具预算已用尽（15 min / 30 calls 合同），故只读复核 + 文件更新，不跑仿真、不跑 TD。

---

## 1. Line A（`T10.ah-a-plus-h-r2`）：kill 成立

### 1.1 独立复核（规划直接读冻结证据，不依赖开发自述）

| 复核项 | 我看到的 | 结论 |
|---|---|---|
| manifest 完整性 | 70 artifacts、7 refs、19 commands；逐项重算 **missing=0 / sha_mismatch=0**；`stopped_modifying=true`、`active_commands=0` | manifest 自身可信 |
| 候选绑定 | `candidate.core = changed-src/a1_deflate_core.v` `f3ee798f…33adc`；`frame_top` `4afc26e2…e30a`（= H-only r1 **未改**，`frame_top_changed=false`） | 只有 core 改了，符合 A 的范围 |
| 时序绑定 | core 落盘 **06:30:46** < 4 帧 build vlog **06:34:01** < caps **07:14:38/07:14:59**；07:25:02 冻 manifest 时 changed-src 无更新 | caps 产自该冻结候选，非"先跑后改" |
| `n-4f.frm` | `stream_len=1665923`（基准 1,677,912 / 1,677,336）；`header=` 末 16 字符为 `xxxxxxxxxxxxxxxx`（头字节 36..43 = stream_crc/header_crc） | **token 流不等价 + DUT 真的在头 CRC 字节上驱动 X** |
| `l-4f.frm` | `stream_len=2153391/2154993`（基准 2,156,868 / 2,156,300）；同位置亦为 `x` | 同上（L 侧） |
| 输入侧 | `raw_crc` N 3,665,401,424 / L 707,927,594；`xform_crc` N 2,597,442,251 / L 2,647,552,023 —— 与基准相同 | 差异只在 core 的 token/打包/CRC 路径，不在前端 |

### 1.2 判定

两条用户预先冻结的 kill 条件**都已成立**，任一条单独即足以 kill：

1. **逐字节等价破坏**（主因）：N/L 的 `stream_len` 分别少 11,989 / 3,477 B，4/4 帧 `.frm`/`.hdr` SHA 全不等；且头字节 36..43 为 X（合法 DUT 不可能输出 X）。
2. **增益不足**（次因）：N4 S_ss 6,104,484.5 → 相对 H-only 6,196,749.5 仅省 **92,265 < 100,000**。

**裁决：A 不采用（kill / not adopted）。** H-only r1（`8acd20b2…` / `4afc26e2…`，manifest `f752ae09…`）仍是唯一候选。不因"L4 5,700,538.5 过线"改变结论——L 过线但字节不等价，本身即为不合格。

### 1.3 是否要测试者复核：**要，但只做"kill 证据审计"**

理由（不是给 A 翻案的机会）：

1. **并发写**：07:14–07:25 有第二个续接开发会话写同一任务目录（前一会话 06:45:21 后台启动的 `run_4f.ps1` 与续接会话的 `run_tool` 各跑了一次 n-4f，两个 `End time` 落在同一 `n-4f.log`）。必须独立确认"caps ↔ 冻结构建 ↔ manifest 候选"三者绑定。
2. **证据被事后删改**：开发从 `commands-r0.jsonl` 删除了自己 2 条 `rc=null` 重复记录。规划复算：现存 17 + 4f-n 1 + 4f-l 1 = **19 条命令、9 个 vsim**，与 manifest 一致，且已无 `rc=null`；但"运行后删除记录"必须登记并由测试者判断是否影响任何门槛。
3. **文档计数不一致**：`result-r0.md` §6 写"21 条命令"、§4 写"20 条记录"，实际/manifest 为 19。属文档瑕疵，需测试者记录，不影响 kill。

审计边界（写进 dispatch，不得自扩）：

- **不做修复**、不改候选、不重跑 4 帧（预算不够，见 §1.4）。
- 允许一次 ≤300 s 的独立重跑，优先选 **8-bit comp bench**（用 manifest 绑定的候选在其自有库重建，确认重现 `2601d57c…`/304,935 cyc），以证明"冻结候选 = 被测量的候选"；或改跑 adapter 定向 12/12。
- 必须回答：kill 的两条理由是否各自独立成立；哪些结论是"已验证"、哪些是"不可验证"；并发/删除是否使任何 gates 失效。
- 判定语言：`FAIL`（本任务门槛未满足）；关账动作由规划执行，不由测试者执行。

**无论审计结论如何，A 都不会被采用**：即使审计认为"字节不等价的证据不可绑定"，N4 增益 92,265 < 100k 仍成立（同一 caps/事件序列），且剩余预算不足以再做一次 N+L 4 帧复验。若审计判"证据不可绑定"，则记录改写为"**A 不采用（证据受限）**"，而不是"A 通过"。

### 1.4 预算账（规划采用的口径）

| 口径 | 秒 | 说明 |
|---|---:|---|
| 唯一进程实际消耗（probe 619.9 + n-4f 1,777.7 + **n-4f 重复 1,777.7** + l-4f 1,756.5 + bench 20.8 + adapter 2.4） | **5,955.0** | 规划采纳此口径：重复启动的那次 n-4f 真的占了主机时间 |
| 严格唯一（重复不计） | 4,177.3 | 开发报告的主口径 |
| manifest 记录的保守求和 | 5,921.0 | 含 1 条重复记录 |
| 全部 20 条记录直接求和 | 8,296 | 把 probe、l-4f 的重复**记录**也计入，属重复计数，不采用 |

**结论**：实际 ≤7,200 s（5,955 s），单次最大 1,777.7 s ≤2,700 s，probe 619.9 ≤1,200 s，bench/adapter ≤300 s。**预算合规**，但**重复启动 n-4f 属流程偏差**（见 §4），且余量仅 ~1,245 s，不足以再做一次完整 N+L 4 帧，故不设 A 的修复轮。

---

## 2. Line B（`T10.ah-honly-td`）：TD 租约**已空闲**，恢复原开发会话

### 2.1 三项条件（规划 07:26:43 实测，比 dev-plan §8 更严）

| 条件 | 实测 | 判 |
|---|---|---|
| (a) round3 已冻结 | `INT.P4-r3-manifest.json` **存在**（mtime **06:10:50**，SHA `43EBFF3D110234A225DD2A449804BC863F47EC5D7AFAE89966C970B5EA9526F1`）；该 run 的 `dispatch.json` = `status=needs_user_input` / `run_state=closed` / `task_ids=[]`，`handoff.md` 06:53 冻结 | ✅（比"manifest 存在"更强：整个 run 已关） |
| (b) 无 TD 进程 | `pnmain/td/td_commands_prompt/run/tdsynth` = **0**；`vsim/vsimk` = **0** | ✅ |
| (c) 20 min 静默 | `INT.P4/td` 最新写入 **06:07:52**、`INT.P4/r3` 最新 **06:08:17** → 距 07:26 已 **78 min** | ✅ |

**裁决：租约授予 `T10.ah-honly-td`**，恢复原开发会话 `ses_e85b9e73effe3tYbVh2330erSx`（同一任务，不新建）。

### 2.2 06:06 与 preflight 的"不一致"已解释

- 规划 06:06:13 记录 `INT.P4-r3-manifest.json` **不存在**；
- 该文件实际创建于 **06:10:50**；
- Line B 的 preflight（06:20）看到它存在。

→ 不是记录错误，也不是 Line B 越界，是状态在两者之间变化。`input-index.md §4` 与 `dev-plan.md §3.1` 已据此更新，**不追责**。

### 2.3 恢复轮的冻结配额与门槛（不得自扩）

| 项 | 值 |
|---|---|
| 综合 | **1 次**（`01_synth.tcl`，187.5 MHz / 5.333 ns，≤1,800 s） |
| 布线 | **≤2 次**（`02_route.tcl`；第 2 次仅在首次失败时，且必须写明参数差异；每次 ≤2,400 s） |
| 209.6 MHz | **≤1 次 analysis-only**（`03_2096_analysis.tcl`，同一 routed DB 只收紧时钟；≤600 s；报告必须标注非布线结果） |
| bitgen / CWC / 下载 / Flash / 板卡 / COM / JTAG / RK / 网络 | **0** |
| 调用/时长 | ≤60 calls / ≤180 min（含等待） |
| 判定 | routed WNS ≥ 0、hold ≥ 0、0 violated endpoints、ERAM+CWC ≤300、slice ≤71,680、IO ≤286 → `eligible_for_next_stage`；否则 `not_eligible` 并给真实数字 |
| 关键路径 | 必须回答最差路径是否落在 frame_top 双 CRC32 链 / core replay 锥 / scan 锥，并列 ≥10 条 |
| CDC | `report_cdc` + `check_timing`（或 `report_check_timing`）必须留报告；未约束路径/生成时钟/loop 全部列出 |
| 工具冲突 | 开 TD 前仍须自检：0 TD 进程 + `INT.P4/td`/`INT.P4/r3` 20 min 静默；发现忙 → `blocked=TOOL_UNAVAILABLE`，不抢、不 `-Force`、不 kill 他人进程 |
| `T:` | 仍指向 b20 的旧工程（陈旧）。**不得 remap、不得 -Force**；tcl 全用绝对路径，`T:` 非必需 |

---

## 3. P3（`T10.ah-dual-verdict`）：放行条件与内容

**放行条件**（三者全部满足才派给原规划，且 0 sim / 0 TD / 不新建开发或测试者）：

1. Line A 的 kill 审计报告已返回（`test-reports/T10.ah-a-plus-h-r2-r0-integrated.md`）；
2. Line B 已有确定性结果：真实 TD 证据的 `ready_for_test` + 其测试者判定，或明确的 `blocked`（含原因）；
3. Line B 若 `blocked` 且原因仍是 TD 被占/工具缺失，则 P3 只写"未取得 TD 结果"的边界，不得代替 TD 结论。

**内容（0 sim）**：

1. A 的最终处置：kill/not adopted；证据事实（bench/probe/adapter 通过；4 帧 token 不等价 + 头 CRC X + 92,265 增益）；未解问题（htab 插入 epoch 漂移只是未验证假设）；重开条件（必须重新设计并证明逐字节等价，不能沿用本次实现）。
2. B 的最终处置：187.5 MHz 是否 `eligible`；WNS/hold/TNS/端点/资源/覆盖率/Fmax（由 routed 报告与 209.6 analysis 共同界定）、关键路径归因、CDC 与未约束缺口。
3. **H-only 能否作为候选进入后续**：
   - B `eligible` **且**审计无漂移 → H-only r1 可作为候选进入下一阶段，但必须带三条限定：N 侧仅 +0.859% 余量、4 帧 prototype gate ≠ 整机 G0、0 bitstream/0 板级。
   - B `not_eligible` → H-only **不能**作为"时序已收敛"的候选；下一包由规划按真实失败锥提出（见 4）。
4. 下一包建议（不在本轮派发）：
   - 若 187.5 负裕量集中在单一锥（如 core replay/emit 或 frame_top 双 CRC32）→ 建议"单锥 retime 的独立 TD 包"，用同一 DUT + 固定延迟等价性证明（可复用测试者判据）。
   - 若负裕量广泛或 Fmax 距 187.5 差 >5% → 建议回到结构方案（新算法/更宽流水/降频与吞吐重算），不以放宽时钟或加例外求过。
   - 若合规且仅差 <0.05 ns → 可提"布线参数/布局约束"包，但**不得**用 seed 扫描或伪造 IO 约束。
5. 明确不证明：整机 G0、板级、真实 sensor RAW、生产 sink、双路、RK/PCIe。

---

## 4. 流程异常登记（不改变 A 的 kill 结论，但必须留痕）

| ID | 异常 | 证据 | 处置 |
|---|---|---|---|
| OBS-A1 | 同一任务有**两个开发会话**并发/先后写同一目录（07:14–07:25） | `main-log` 主记录 + `result-r0.md §4` + `n-4f.log` 两个 `End time`（07:14:05 / 07:14:59） | 已由规划复核候选与 caps 的时序绑定；测试者审计确认；后续 run 应在续接前显式登记旧会话终止 |
| OBS-A2 | **同一参数 n-4f 被启动两次**（一次 06:45:21 后台 `run_4f.ps1`，一次续接会话 `run_tool`），多耗 1,777.7 s | 同上 + `commands-4f-n.jsonl` 1 条 + `run_tool` 记录 | 记账已并入 §1.4；不追加预算；后续 run 必须在启动长仿真前声明"单一启动者" |
| OBS-A3 | 开发**删除**自己 2 条 `rc=null` 重复记录 | `result-r0.md §4`；规划复核现存 19 条、无 `rc=null` | 记录保留在 result；测试者判断是否影响门槛；后续 run 禁止在冻结前删除命令记录，只能标注 |
| OBS-A4 | 报告命令计数写 21 / 20，实际 19 | `result-r0.md §4/§6` vs manifest/jsonl | 文档瑕疵，测试者记录，不改判定 |
| OBS-A5 | Line B preflight 与规划 06:06 的 r3 manifest 记录不一致 | manifest mtime 06:10:50 | 已解释（§2.2），非违规 |
| OBS-A6 | `T:` 仍映射到 b20 旧 TD 目录 | `subst` 输出 | 陈旧映射；本轮禁止 remap，Line B 用绝对路径 |

---

## 5. 本轮裁决后的状态

| task | 状态 | 下一动作 |
|---|---|---|
| `T10.ah-a-plus-h-r2` | **kill（A not adopted）**，待一次独立证据审计 | `spawn_single_tester`（kill 审计，≤35 calls/60 min，≤300 s 独立重跑，不修复） |
| `T10.ah-honly-td` | **ready（恢复）**，TD 租约已授予 | `followup_task` → `ses_e85b9e73effe3tYbVh2330erSx`，1 synth + ≤2 route + 0 bitgen |
| `T10.ah-dual-verdict` | **blocked（待 A 审计 + B TD 结果）** | 原规划在两者都返回后写 `dual-verdict.md`（0 sim / 0 TD） |
