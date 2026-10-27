# dev-plan — 20261027-055621_fpga-honly-td-and-ah

本轮 1 个主要可验收目标：**在 H-only r1 冻结候选上分别回答两个独立问题——(A) 加 A 后原型是否仍逐字节等价且更省周期；(B) 该候选在 187.5 MHz 是否有实现资格**。两条线各自新开发/新综合测试者，互不复用、不共享源/库/日志/工程/盘符。

- 正式包：**4 个**（A 已 kill_verified 关账；synthfix 修复 ready；B 的 TD r1 blocked 依赖修复；dual-verdict blocked），恰在上限。
- 两级：需求 → 工作包。包内为步骤清单，不建子任务。
- 默认批大小 1；本 run 是用户明确要求的**两条独立并行线**，不是批：每线各 1 任务、各 1 开发、各 1 测试者，逐线判定与修复轮数分别记账。

---

## 1. 工作包总表

| task_id | 问题 / 产物 | 实际工作树 / 允许写路径 | 依赖 | functional | engineering | system | 必要 G 层 | 状态 | 下一动作 |
|---|---|---|---|---|---|---|---|---|---|
| `T10.ah-a-plus-h-r2` | H-only r1 副本上加 A（2-position literal 扫描 + 双符号 packer），N/L 4 帧 ≤6.25M、A1U1/zlib 逐字节不变、adapter 12/12、无 stall；增益 <100k 或破坏等价即 kill | `workflow/runs/20261027-055621_fpga-honly-td-and-ah/T10.ah-a-plus-h-r2/**` + `%TEMP%/opencode/ah-a/**` | 只读 `T10.ah-honly` r0/r1 + coregap 定义 | **fail（kill）**：4 帧逐字节不等 + 头 CRC X；probe/bench/adapter pass | 候选/manifest/命令/SHA/工具版本/预算；**0 TD**（G2 not_applicable） | 接口/字流/头/CRC 语义**已被破坏**（kill 依据）；板级 not_applicable | G0 fail（prototype gate）、G1 | **closed：kill_verified / not adopted** | 无（不再派开发/测试者/仿真） |
| `T10.ah-honly-td` | 用 H-only r1 冻结候选做 TD 综合/PnR/STA（187.5；209.6 仅 analysis），输出 WNS/hold/资源/CDC/关键路径归因，判"是否具备下一阶段资格"；0 RTL 改动、0 bitgen | `.../T10.ah-honly-td/**` | 只读 `T10.ah-honly` r1 + b11/r10 TD 模板；**TD 租约**：07:26 复审已空闲，授予本任务 | r0 准备已到"端口绑定编译 + 输入哈希"；恢复轮补真实 DUT 综合/STA | r0 = G2 not_run；恢复轮 G2 = 真实 TD/STA/资源/CDC | 接口/时钟域/未约束缺口记录；板级 not_applicable | G1（已过）/ G2（恢复轮） | r0 **FAIL（不可综合）**：TD 6.49 s `HDL-8007 cmem_lo[15]` 多驱动（L673/L964）；无 gate DB/时序/面积/flow.status；route/analysis/bitgen 0。r1 **blocked** | r0 = G2 **fail（elaborate 拒绝，非时序结论）**；r1 = 真实 TD | 接口/时钟域记录；板级 not_applicable | G1（r0 pass）/ G2（r1） | **r1 blocked（TOOL_UNAVAILABLE）/ eligibility not_evaluated** | 已执行：synth 成功（WNS +0.029、0/4,969、ERAM 27、IO 121）；route 2/2 在 `import_db→Import ChipWatcher` coredump，无 routed DB。转 `final-summary.md`/`dual-verdict.md`，不再派发 |
| `T10.ah-honly-synthfix` | **RTL 修复**：在 H-only r1 候选独立副本上**只**消除 `cmem_lo/_pend/_addr` 的多驱动（复位分支并入唯一驱动块；精确 diff 见 §11），零行为变化：N4 6,196,749.5 / L4 5,834,940 精确、4/4 `.frm/.hdr` 逐字节相同、adapter 12/12；**0 TD** | `.../T10.ah-honly-synthfix/**` + `%TEMP%/opencode/ah-synthfix/**` | 只读 H-only r1 候选 | 必须 pass：4 帧 S_ss 精确 + 逐字节 + adapter + 0 多驱动 | manifest/命令/SHA/DIFF/静态扫描；0 TD | A1U1 头/字流/CRC 语义不变；板级 not_applicable | G0（prototype gate 复现）、G1 | **closed（PASS）** | 无（包已关账；TD r1 依赖已满足） |
| `T10.ah-dual-verdict` | 合并两线：A 保留/放弃、是否需要 TD 后续、下一阶段资格与边界 | 本 run 根（规划写 `dual-verdict.md`） | A、B 均返回 | 由规划据两线报告汇总，不新增判据 | 引用两线 manifest/报告，不重算 | 交接口径与回退 | 全 not_applicable（0 sim/0 TD） | **closed（`dual-verdict.md`，2026-10-27 10:05）** | 已完成，无后续 |

---

## 2. `T10.ah-a-plus-h-r2`（Line A，离线仿真）

### 2.1 目标与冻结输入

- 起点：`T10.ah-honly/r0/changed-src/{a1_deflate_core.v, a1_frame_top.v}`（SHA `8acd20b2…b17b` / `4afc26e2…e30a`）**复制**到本任务 `r0/changed-src/` 后再改；原 run 目录只读。
- 定义：`fpga-design-guide.md §2`（A = 2-position literal 扫描 + ≤16 bit 双符号 packer；只改调度）。
- 期望值（**不是证据**）：coregap A+H = 6,008,078 cycles/frame（2.3179 c/B，+4.03%，45.034% envelope）。实际以实测为准。

### 2.2 步骤（5 项，顺序执行）

1. **建独立副本并实现 A**：复制 core/frame_top + 5 个 TB（r0 的 `tb_ss_4run_wd.v`、`tb_ss_4run_wd_probe.v`、
   `tb_a1_deflate_core_{8b,16b}.v`，加 r1 的 `tb_adapter_directed.v`）；只改 core 的扫描/packer 路径（必要时 frame_top 仅跟随 `OUT_BYTES=2` 的既有接口，不改语义）；
   写 `r0/DIFF-a.md` + 机器 diff（`out/DIFF-a.raw`）。
2. **b6 bench 逐字节 + adapter 定向**（最早的廉价闸门）：8b/16b × comp/rand 四组，SHA/长度必须等于冻结值（`2601d57c…` / `54f262f2…`），
   cycles ≤ 冻结上限且记录；Python `zlib.decompress` 独立还原；adapter 12/12。任一不等 → **立即 kill**，不进入长仿真。
3. **N 1 帧 stage probe**：`core_interval = t_enc(1) − t_pub(1)`；闸门：≤6,197,186（不得比 H-only 差）且 cycles/B ≤2.411（coregap 要求）。
   未过 → 停，不跑 4 帧，返回 kill（附真实数字）。
4. **N/L 4 帧**：S_ss ≤6,250,000（各自）；N4 必须 ≤6,096,749.5（相对 H-only 至少 100k cycles 增益）；L4 必须 ≤5,834,940（不得倒退）；
   4/4 header/CRC/length/last byte 与冻结基准整文件 SHA 相同；无 `SS_STALL*/B11_FULL_TIMEOUT`。
5. **冻结与返回**：`r0/manifest-r0.json`（全部 artifact/命令/reference/候选 SHA、`stopped_modifying=true`、`active_commands=0`）、
   `result-r0.md`、`lessons-r0.md`、`out/` JSON；给出 `ready_for_test` 或 `blocked`（kill 也要冻结证据）。

### 2.3 验收阈值（测试者按此判，不得改）

| 项 | 阈值 |
|---|---|
| N4 S_ss | ≤6,250,000 **且** ≤6,096,749.5 |
| L4 S_ss | ≤6,250,000 **且** ≤5,834,940 |
| 逐字节 | 4 帧 `n-4f.{frm,hdr}` = `b9cb5359…`/`c7fe281c…`；`l-4f.{frm,hdr}` = `8aad9099…`/`864d2fba…`；b6 bench 8b+16b 四组 SHA 全等；zlib 解码成功 |
| adapter | `ADAPTER_PASS cases=12 errors=0` 且独立重跑一致 |
| stall | 无 `SS_STALL/SS_STALL_COLD`；4 帧无 `B11_FULL_TIMEOUT`（1 帧 probe 的 export 后 timeout 仅可作已知伪影并明确标注） |
| manifest | 42+ 项 100% 哈希可复算；候选 SHA 与返回声明一致；`previous` 链指向 H-only r1 `f752ae09…` |
| 预算 | 见 §6；超预算的失败尝试必须记账而非抹掉 |

### 2.4 kill / partial 规则（冻结）

- 任一逐字节不等（bench、4 帧 header、zlib）→ **kill A**（不可用"放宽到 CRC 相同"替代）。
- N1 probe 无增益（>6,197,186）或 cycles/B >2.411 → 停，kill（省下 4 帧预算）。
- N4 增益 <100,000（即 >6,096,749.5）→ kill；H-only r1 仍是唯一候选。
- L4 倒退（>5,834,940）→ 判 A+H 不达标（即使 N 达标）。
- 任何为达门槛而改格式/几何/CRD、加宽输出口 >2 B/周期、换算法、改时钟的行为 → 视为越界，返回 blocked 交原规划。
- kill 时**不需要**再跑未跑的仿真；保留已产生的证据与真实数字，写 `result-r0.md` 的 kill 理由。

### 2.5 回退

- 不达标即回退到 H-only r1 冻结候选（`8acd20b2…`/`4afc26e2…`，manifest `f752ae09…`）；本任务所有产物为 append-only 新目录，不覆盖任何旧文件。

### 2.6 r0 结果与关账（2026-10-27 07:30，详见 `r0-ruling.md §1`）

- **结果：kill（A not adopted）。** 两条预注册 kill 条件同时成立：4 帧 token 流不等价（N `stream_len` 1,665,923、L 2,153,391/2,154,993；`n-4f.frm`/`l-4f.frm` 头字节 36..43 为 `x`）＋ N4 增益 92,265 < 100,000。
- **不设修复轮**：剩余仿真预算 ~1,245 s（7,200 − 5,955 实际消耗），不足以再跑一次 N+L 4 帧；且用户规则为"失败/增益<100k 即 kill"。
- **关账前唯一动作**：一个新测试者做 **kill 证据审计**（≤35 calls / 60 min；≤300 s 独立重跑；只判证据绑定与门槛，不修复、不重跑 4 帧）。审计结论用于记录"已验证/不可验证"，**不改变 A 不被采用**。
- **L4 过线不作任何补救理由**：L 虽 5,700,538.5 ≤5,834,940，但字节不等价，任务整体不合格。
- **回退**：H-only r1 仍是唯一候选，未被本任务触碰。

---

## 3. `T10.ah-honly-td`（Line B，TD/STA）

### 3.1 依赖与租约（决定性约束）

- 06:06 初次实测：`20261026-2138_fpga-integrated-delivery` round3 正在用 TD（`INT.P4/td/r3_run1` 06:01:41→06:04:16 第 1 次综合），故 r0 只做 TD-free 准备——**已完成**（0 TD 调用、1 次 vlog 0/0/0、scaffold 就绪）。
- **07:26:43 复审：租约空闲**。`INT.P4-r3-manifest.json` 06:10:50 创建（SHA `43EBFF3D…26F1`）；该 run `run_state=closed` / `status=needs_user_input` / `task_ids=[]`，`handoff.md` 06:53 冻结；TD 进程 0；`INT.P4/td` 最新写入 06:07:52、`INT.P4/r3` 06:08:17（静默 78 min）。
- **裁决：租约授予 `T10.ah-honly-td`**，恢复原开发会话（同一任务、不新建）。开 TD 前仍须自检：0 TD 进程 + 上述两目录 20 min 静默；发现忙 → `blocked=TOOL_UNAVAILABLE`，不抢、不 `-Force`、不 kill 他人进程。
- 配额不变：1 次综合 + ≤2 次布线 + 0 bitgen/CWC/下载/Flash；TD 会话串行，不并行开第二个会话。
- `T:` 仍映射 b20 旧工程（陈旧）：**不得 remap / 不得 -Force**；tcl 全用绝对路径，`T:` 非必需。

### 3.2 步骤（5 项；r0 已执行 1–4 并在第 4 步被 TD 拒绝 → 见 §2/§12 与 `r1-ruling.md §2`）

> **r0 实际结果（2026-10-27 07:40）**：步骤 1–3 完成；步骤 4 的综合在 **6.49 s** 被 TD 以 `HDL-8007 cmem_lo[15]` 多驱动拒绝（L673 / L964），无 gate DB/时序/面积/`flow.status`，core 成 black box → **r0 FAIL（不可综合，不是时序结论）**。步骤 5 未执行（route/analysis/bitgen = 0/0/0）。修复由新包 `T10.ah-honly-synthfix` 承担，TD 执行改为 **r1**（见 §12）。

1. **输入核验与 repo binding**：重算并记录 DUT 2 文件、TB、content、b11/r10 模板的 SHA；写 `r0/prepared/REPO-BINDING.md`
   （声明：使用冻结旧候选绝对只读路径、新仓未迁移、0 commit/push）。
2. **TD 工程脚手架（不调 TD）**：`r0/td/a1_ah_eng_top.v`（build-only wrapper，含 `dbg` 绑定）、`a1_ah_small_top.sdc`（5.333 ns、无例外）、
   `01_synth.tcl`（绝对路径 + `flow.status` 端点统计）、`02_route.tcl`、`03_2096_analysis.tcl`、`README.md`（准确命令与预期产物）。
3. **端口绑定编译检查**：一次 `vlib`+`vlog -sv +define+SIMULATION` 编 wrapper + 2 个冻结候选（**不跑 vsim、不跑 TB**），Errors 0 且无 undriven 端口；记录日志与耗时（≤300 s）。
4. **（恢复轮）187.5 MHz 综合**：1 次；采集 `flow.status` NUM_FEPS/WNS/TNS/hold、area（slice/reg/eram/fifo20k/DSP/IO）、coverage、
   最差 ≥10 条路径归因、`check_timing`/`report_cdc`。若 synth WNS < −0.50 ns → 不再布线，记 `route=not_run` + 原因。
5. **（恢复轮）布线 + STA + 209.6 analysis + 冻结**：布线 ≤2 次（第 2 次须写明参数差异）；routed DB 上出最终 STA；
   WNS≥0、hold≥0、0 violated endpoints 且资源在预算内 → `eligible_for_next_stage`；否则 `not_eligible`（真实数字，不粉饰）。
   209.6 MHz 只做同一 DB 收紧时钟的 analysis-only 并显式标注。冻结 `manifest-r0.json`/报告族，`stopped_modifying=true`。

### 3.3 验收阈值

| 项 | 阈值 |
|---|---|
| 输入绑定 | DUT SHA = `8acd20b2…b17b` / `4afc26e2…e30a`；`INT.P4/td`/`INT.P4/r3` 未被本任务写入（时间戳证据） |
| 本轮（r0 准备） | 脚手架文件齐全可执行；wrapper 编译 0 error；`preflight-r0.json` 记录租约状态与时间 |
| 恢复轮（G2） | 真实 TD：`flow.status` 的 NUM_FEPS/WNS/TNS/hold；routed WNS≥0、hold≥0、0 endpoints；ERAM+CWC ≤300；slice ≤71,680；IO ≤286；STA coverage 记录；无 false_path/multicycle |
| 报告 | 关键路径必须回答"最差路径是否在 frame_top 双 CRC32 / core replay / scan 锥"；CDC 与未约束路径必须列出 |
| 禁止 | bitgen/CWC/下载/Flash/上板/改 RTL/改时钟求过/抢占 `T:`/kill 他人进程 |

### 3.4 停止与 blocked 条件

- r0（准备轮）已按计划返回 `blocked`（`DEVICE_MISSING`，语义=TD 独占资源被占用），产物：`preflight-r0.json`、`manifest-inputs-r0.json`、`result-blocked-r0.md`、`lint/`。
- 恢复轮：TD 进程冲突/`T:` 被占/license RUN-8008（`RUN-8008` 退化为 `PRJ-5303/8806`）→ `blocked=TOOL_UNAVAILABLE`，不重试、不扩权、不 `-Force`。
- 综合报告缺失/端点统计不可得 → 判证据不完整，停在综合，不布线。
- 两次布线无改善或 WNS 仍负 → 停，保留真实数字与关键路径，返回 `not_eligible`。
- 达到 60 calls / 180 min → 冻结当前证据返回，列明未运行项。

---

## 4. `T10.ah-dual-verdict`（第 3 包，0 sim / 0 TD）

- 执行者：**原规划**（收尾时），不新建开发/测试者；不占测试者名额；不重算、不重跑。
- **放行条件**（三者同时满足）：(1) Line A 的 kill 审计报告已返回；(2) Line B 有确定性结果（真实 TD 证据的 `ready_for_test` + 测试者判定，或明确的 `blocked` 且原因不是"再等等"）；(3) 若 B 仍 blocked，P3 只记边界，不得代替 TD 结论。
- 产物 `dual-verdict.md` 必含：
  1. **A 最终处置**：kill/not adopted；事实（bench/probe/adapter 通过；4 帧 token 不等价；头 CRC X；增益 92,265）；未解问题（htab 插入 epoch 漂移属未验证假设）；重开条件（重新设计并证明逐字节等价）。
  2. **B 最终处置**：187.5 MHz 是否 `eligible`；WNS/hold/TNS/端点/资源/覆盖率；Fmax（由 routed 报告与 209.6 analysis-only 共同界定，注明非布线结果）；关键路径归因（frame_top 双 CRC32 / core replay / scan）；CDC 与未约束缺口。
  3. **H-only 是否可作候选进入后续**：
     - B `eligible` 且审计无漂移 → 可作候选，但必须带限定：N 侧仅 +0.859% 余量、4 帧 prototype gate ≠ 整机 G0、0 bitstream/0 板级。
     - B `not_eligible` → **不能**写作"时序已收敛的候选"；按真实失败锥提下一包。
  4. **下一包建议**（不派发）：
     - 负裕量集中在单一锥 → "单锥 retime 的独立 TD 包"（同一 DUT + 固定延迟等价性证明）；
     - 负裕量广泛或 Fmax 距 187.5 差 >5% → 结构方案（新算法/更宽流水/降频+吞吐重算）；
     - 仅差 <0.05 ns → 可提布局/布线参数包，**禁止** seed 扫描或伪造 IO 约束。
  5. **不证明**：整机 G0、板级、真实 sensor RAW、生产 sink、双路、RK/PCIe。
- 依赖：A/B 冻结 manifest + 两份综合测试报告 + `r0-ruling.md`。此包不计入执行预算（无命令）。

---

## 5. 并行隔离（硬约束）

| 项 | Line A | Line B |
|---|---|---|
| 源 | 自己的 `r0/changed-src/`（H-only 副本）+ 只读引用 `T10.ah-honly/r0/src/` | 只读 H-only 候选原始路径 |
| work 库 | `%TEMP%/opencode/ah-a/**` 各自 build 目录 | 无（本轮 0 TD；恢复轮为 TD 工程目录） |
| 日志 | 自己的 `r0/sim/logs/` | 自己的 `r0/lint/`、`r0/td/` |
| TD | **0**（不用 T:、不碰 D:/TD） | 本轮 0 会话；恢复轮独占 |
| 盘符 | 不得映射/使用 `T:`、`X:` | 需要时只用 `td_env.ps1 -TdDir 本任务td`（无 -Force） |
| 互不干扰 | 不读对方中间产物；不 kill 对方或其他 run 的 vsim/TD 进程 | 同左 |

---

## 6. 预算（冻结；运行角色不得自扩）

### 6.1 Line A 开发（≤45 calls / 120 min）

| 项 | 上限 | 依据 |
|---|---|---|
| 总工具调用 | 45 | 用户本轮指定 |
| 总时长 | 120 min | 用户本轮指定 |
| 仿真总墙钟（各 vsim 的 seconds 之和） | **7,200 s** | 用户本轮指定；与 H-only r1 同口径（并发时仍按每 run seconds 求和，另记主机墙钟） |
| 单次仿真 | **2,700 s**（硬超时，超时即安全停止并记账） | 用户指定；H-only r1 N4 1,700.0 s / L4 1,734.8 s 实测 |
| N 1 帧 probe | ≤1,200 s（`MAX_CYCLES=13300000`；H-only 实测 609.6 s） | 用户指定 |
| b6 bench（2 组 ×2 TB） | ≤300 s/次 | 用户指定 |
| adapter 定向 | ≤300 s | 用户指定（r1 实测 2.1–2.3 s） |
| 读取/搜索 | 60 s/次 | 有界规则默认 |
| 同一失败命令重试 | 首次 +1 次且必须参数纠正/新证据 | 有界规则 |

**执行顺序理由**：bench（秒级）与 probe（10 min 级）放在 4 帧（2×~28 min）之前，使 kill 发生在最便宜的闸门，避免把 7,200 s 预算耗在注定不达标的实现上。

**r0 实际消耗（已发生，记账）**：probe 619.9 + N4 1,777.7 + **N4 重复 1,777.7** + L4 1,756.5 + bench 20.8 + adapter 2.4 = **5,955.0 s ≤ 7,200**；单次最大 1,777.7 ≤2,700；9 个 vsim；调用数未超 45（开发自报，规划未反推）。重复 N4 属流程偏差（见 `r0-ruling.md §4 OBS-A2`），**不追加预算**；余量 ~1,245 s 不足以再跑 N+L 4 帧，故不设修复轮。

### 6.2 Line B 开发（≤60 calls / 180 min；本轮准备子集 ≤20 calls / 45 min）

| 项 | 上限 | 依据 |
|---|---|---|
| 综合 | 1 次（`td_commands_prompt` 单次调用 ≤1,800 s） | 用户指定 1 次综合；构建默认 30 min |
| 布线 | ≤2 次（单次 ≤2,400 s） | 用户指定 1–2 次；b11 实测 13m49s（place 10m01s + route 3m33s） |
| 209.6 analysis | 1 次（≤600 s） | 同一 DB，仅改时钟报告 |
| 总时长 | 180 min（含等待） | 用户指定 |
| r0 准备（**已完成**） | 实际 06:16–06:22（约 6 min），0 TD 调用，1 次 vlog 0/0/0 | 规划冻结：只做准备，不进入 TD |
| 恢复轮（本次） | ≤60 calls / ≤180 min（含等待） | 规划冻结；TD 单会话串行 |
| 读取/搜索 | 60 s/次 | 有界规则 |

### 6.3 综合测试者（每线独立一个，≤35 calls / ≤60 min）

| 项 | 上限 | 依据 |
|---|---|---|
| Line A 测试者（**kill 证据审计**） | ≤35 calls / 60 min；**最多 1 次 ≤300 s 独立重跑**（优先 8-bit comp bench 复现 `2601d57c…`，或 adapter 12/12）；**不重跑 4 帧**、不修复 | 用户指定；本任务只审计"caps↔冻结构建↔manifest 候选"绑定与门槛 |
| Line B 测试者（恢复轮） | ≤35 calls / 60 min；只读复核 TD 报告并至少 1 项独立判据（如独立解析 flow.status / 独立锥分析），**不重跑 TD** | TD 配额不因测试者增加 |

### 6.4 修复轮次

round0 首次验收；同任务最多三轮实际修复（round1–3），分别按线记账。外部阻塞（TD 被占、license 缺失、工具不可用）直接 blocked，不空转。

---

## 7. 测试者适用项（规划事先冻结，不得临场改判）

### 7.1 Line A（`T10.ah-a-plus-h-r2`）

- **functional**：4 帧 N/L S_ss 与阈值；逐字节等价（4 帧整文件 SHA + 8b/16b bench 四组 + zlib 独立解码）；adapter 12/12（含测试者独立重跑）；
  无 stall/timeout；A 语义检查（块边界分割、匹配不被投机吞掉、计数器语义）；至少 1 项独立判据（第三方 zlib 解码 / 独立 header 解析 / 变异负对照证明 TB 能拒绝"输出差 1 字节"）。
- **engineering**：manifest 100% 哈希、命令簿记（rc/timeout/seconds）、工具版本、预算实测、写范围漂移（不得写生产源/旧 run/其他 run）、**0 TD/板卡/网络**。
- **system**：对外 32-bit 字流/`out_keep`/`out_last`/44 B 头/CRC/UART 语义未变；板级 `not_run/not_applicable`（0 bit/CWC/下载/Flash）；回退路径与候选唯一性。
- **G 层**：G0 = pass/fail **仅限 prototype 4 帧 S_ss gate**；G1 = manifest/命令/证据；G2/G3/G4 = `not_applicable`（0 综合/0 位流/0 板卡）。
- **独立性**：测试者不得只读开发自述；至少重解一次 header/CRC 或重跑一次短 bench。

### 7.2 Line B（`T10.ah-honly-td`）

- 本轮 r0（准备轮）：functional 仅 `pass/not_run` 到"wrapper 编译 0 error + 端口绑定正确"，**不得**声称 DUT 功能；
  engineering = 输入哈希、脚手架齐全、租约证据（时间戳）；system = 接口/时钟域记录 + 未约束缺口；G2 = `not_run`。
- 恢复轮：engineering = 真实 TD 同一 DB 的 setup/hold/TNS/endpoints/资源/coverage/CDC/未约束路径；**禁止混拼不同 run 的报告**；
  functional = 由同一冻结候选的 DUT 身份与 Line A 的仿真证据交叉引用（不作为本轮重跑）；system = 关键路径归因、板级 not_applicable；
  G2 = pass/fail 按 §3.3。测试者可用独立脚本解析 `flow.status`/`.area`/`.timing` 作为独立判据，**不重跑 TD**。

---

## 8. 停止 / blocked / 恢复入口

| 触发 | 处理 |
|---|---|
| Line A 触发 §2.4 kill | 已发生：kill 成立 → 冻结证据 + 一次独立证据审计 → 原规划关账（不修复） |
| Line A 超过 calls/time/仿真预算 | 安全停止自己的 vsim（只停自己启动的 PID），保留日志与 exit 信息，返回 blocked=`LIMIT_REACHED` |
| Line B r0 准备轮 | 已完成：`blocked`（TD 租约），产物 `preflight-r0.json` + scaffold + lint |
| Line B 恢复轮 TD 冲突/license | `blocked=TOOL_UNAVAILABLE`（不重试、不扩权、不 -Force） |
| 任一角色发现必须扩范围（改格式/改时钟/改生产源） | 停，交原规划 |

**Line B 恢复判据（2026-10-27 07:26 已全部满足，租约已授予）**：
1. ✅ `INT.P4-r3-manifest.json` 存在（06:10:50，`43EBFF3D…`），且该 run 已 `run_state=closed` / `task_ids=[]`；
2. ✅ `Get-Process pnmain,td,td_commands_prompt,run` = 0；
3. ✅ `INT.P4/td/**`（06:07:52）与 `INT.P4/r3/**`（06:08:17）静默 >20 min。

恢复方式：**followup 原开发会话 `ses_e85b9e73effe3tYbVh2330erSx`（同一任务，不新建）**，dispatch 见 `dispatch.json`。

若后续再次被占，恢复文本：

```
恢复：D:\fpga\ph1p100\workflow\runs\20261027-055621_fpga-honly-td-and-ah；本轮目标：继续 T10.ah-honly-td 的 TD 执行（先核 TD 租约：r3 manifest 冻结 + 0 TD 进程 + 两目录 20 min 静默）
```

Line A 若用户要求重开（需新预算；当前余量 ~1,245 s 不足）：

```
恢复：D:\fpga\ph1p100\workflow\runs\20261027-055621_fpga-honly-td-and-ah；本轮目标：按 T10.ah-a-plus-h-r2 的 kill 报告与审计结论处理 A 是否重开（新预算、先证逐字节等价）
```

---

## 9. 后续主题（本轮不做，≤3 条，保留原需求路径）

1. **A+H 的 TD/STA**：A 若达标，需要与 Line B 同口径的 187.5/209.6 实现评估（新一轮，各自配额）。
2. **迁移 H-only/A+H diff 到新权威仓** `D:\fpga\repos\ph1p100-pcie-ep-fpga`（需用户授权 commit/push；本轮只读）。
3. **G0 整机口径**：4 帧 prototype gate 之后的真实 sensor RAW / 生产 sink / 双路 / 板级恢复与稳定性（远超本轮）。

---

## 10. 本轮明确不做

- 不改任何 RTL 生产源、不改 H-only r1 候选/报告、不改 b18/b19/b20、不碰 integrated delivery 与 chain review。
- 不 TD（Line B 本轮）、不 bitgen/CWC/下载/Flash/上板、不 COM/JTAG/RK/网络、不 commit/push、不改 `workflow/tasks.json`/`docs`/`.agents`。
- 不批量删除；不新建监控/定时/常驻角色；不派生代理。

---

## 11. `T10.ah-honly-synthfix`（Line B 前置修复包，0 TD）——r1 追加（2026-10-27 07:52）

依据 `r1-ruling.md §3`。**这是新的正式包（第 2 包），不新造父任务 ID。**

### 11.1 目标

在 H-only r1 冻结候选的**独立副本**上，只消除 TD elaborate 拒绝的多驱动，**零行为变化**。TD 的原始错误（规划已读 `r0/td/run-syn1/a1_ah_Runs/syn_1/run.log` L112–113）：

```
HDL-8007 ERROR: net 'cmem_lo[15]' is constantly driven from multiple places ... a1_deflate_core.v(673)
HDL-5007 WARNING: found another driver here ... a1_deflate_core.v(964)
```

### 11.2 允许的精确 diff（白名单，只有这两处）

在 `a1_deflate_core.v`（副本）：

1. **L673 起的 cmem 写端口块**加复位分支（**不得**在该分支里给 `cmem` 数组赋值，否则破坏 RAM 推断）：

```verilog
    always @(posedge clk) begin
        if (!rst_n) begin                  // 新增
            cmem_lo      <= 16'd0;          // 新增
            cmem_lo_pend <= 1'b0;           // 新增
            cmem_lo_addr <= 12'd0;          // 新增
        end else if (cmem_flush) begin     // 原: if (cmem_flush) begin
            ...                            // 其余原样
```

2. **删除**主时序块复位分支中的三条重复驱动（L1042–1044）：

```verilog
            cmem_lo        <= 16'd0;       // 删除
            cmem_lo_pend   <= 1'b0;        // 删除
            cmem_lo_addr   <= 12'd0;       // 删除
```

`a1_frame_top.v` **必须逐字节不变**（`4afc26e2…e30a`）。

**禁止**：改 `cmem_flush` 定义/优先级、改 `cmem_we_c` 优先级、把寄存器搬去别的块、`ifdef`/`force`/`initial`、任何无关"顺手"改动、任何算法/几何/时钟/协议/CRC/H 逻辑改动。

**同类别扩展**（规划授权，限界）：修复前必须做全文件多驱动静态扫描（core + frame_top）。
- 只有这三个 → 只做上述两处；
- 另有**同类别**（复位分支 + 功能分支各写一次）实例 → 可同模式修复，但须在 `SCOPE-EXTENSION.md` 逐条列出（文件/行/寄存器/改法），总增量 ≤8 行；
- 出现**不同类别**（功能块互驱、wire 多驱、跨模块 force）→ **停止**，交原规划。
- 规划侧参考：本规划用 `_planner_scan_multidriver.py` 扫描结果为"仅这三个、frame_top 零"，但 TD 是唯一权威，开发必须自行复扫并写结果。

### 11.3 门槛（任一不过即 FAIL）

| 项 | 阈值 |
|---|---|
| 多驱动 | 修复后静态扫描 **0** 跨块驱动 |
| 编译 | 0 errors；warning ≤ H-only r1 的 21 条同源；新增须解释 |
| bench | 8b/16b × comp/rand：comp `2601d57c…a7c05` / 50,310 B / 304,961 cyc；rand `54f262f2…96dd` / 153,766 B / 161,479 cyc；zlib 还原 |
| adapter | 12/12，`ADAPTER_PASS cases=12 errors=0` |
| N4 S_ss | **精确 = 6,196,749.5** |
| L4 S_ss | **精确 = 5,834,940** |
| 4 帧逐字节 | `n-4f.frm b9cb5359…`、`n-4f.hdr c7fe281c…`、`l-4f.frm 8aad9099…`、`l-4f.hdr 864d2fba…` 整文件 SHA 相同 |
| stall | 无 `SS_STALL*`/`B11_FULL_TIMEOUT` |
| TD | **0**（本包不做综合/布线/STA/bitgen） |

容忍度：S_ss 只接受精确值；若不等，允许**一次**同输入复跑确认是否确定性，仍不等即 FAIL。逐字节零容忍。不得调门槛。

### 11.4 步骤（5 项）

1. 建独立副本（core + frame_top + 5 个 TB 副本）+ 修复前多驱动扫描 + `SCOPE-EXTENSION.md` 结论。
2. 施加两处白名单编辑 + 修复后扫描（0 多驱动）+ `DIFF-synthfix.md/.raw`。
3. 编译 + bench 四组 + zlib + adapter 12/12。
4. N4 与 L4 4 帧：S_ss 精确、4/4 逐字节、无 stall；`SS_STATS cap=enc=exported=4`、`read=518,400`、`raw_bad=err=wd=drops=0`。
5. 冻结 `manifest-r0.json`（含 previous `f752ae09…`、candidate 新 SHA、命令 argv/rc/seconds、`stopped_modifying=true`）、`result-r0.md`、`lessons-r0.md`；返回 `ready_for_test`。

### 11.5 预算/角色

- **新开发** + 之后**新综合测试者**（不复用 A/B 的角色）。
- ≤45 calls / ≤120 min；仿真总 ≤7,200 s；单次 vsim ≤2,700 s；bench/adapter ≤300 s 每次；**不跑 1 帧 probe**（4 帧即门槛，省 ~620 s）。
- 写范围：`.../T10.ah-honly-synthfix/**` + `%TEMP%/opencode/ah-synthfix/**`。

---

## 12. `T10.ah-honly-td` r1 重新授权（TD/STA）——r1 追加

依据 `r1-ruling.md §2.3/§4` + **`r2-ruling.md §2–§3`（2026-10-27 09:30 放行）**。

| 项 | 值 |
|---|---|
| 前置 | ✅ 已满足：synthfix 测试者 PASS（manifest `034777c5…`，core `d2960cfe…` 85,221 B） |
| DUT | synthfix 的 `a1_deflate_core.v` `d2960cfe…`（85,221 B）+ `a1_frame_top.v` `4afc26e2…`（29,207 B）；`r1/td/01_synth.tcl` **只改** 两行 `add_files` 路径与头部 DUT/SHA 注释；wrapper/SDC 为 r0 版本的逐字节副本；`r1/BINDING.md` 记旧→新 SHA 与 synthfix manifest SHA |
| 综合 | **1 次结果**（elaborate 失败不计结果；lifetime TD 启动 ≤3，r0 已用 1，本次为第 2 次） |
| 布线 | ≤2（第 2 次须写明参数差异；synth WNS ≥ −0.50 ns 才布线） |
| 209.6 | ≤1 analysis-only（同一 routed DB 收紧时钟，标注非布线结果） |
| bitgen/CWC/下载/Flash/板卡 | 0 |
| 门槛 | routed WNS ≥ 0、hold ≥ 0、`NUM_FEPS = 0`（flow.status）、ERAM+CWC ≤300、slice ≤71680、IO ≤286；coverage/check_timing/report_cdc/≥10 条最差路径归因（frame_top 双 CRC32 / core replay / scan） |
| 租约（**v2，holder-agnostic**） | 开 TD 前自检并记 `r1/preflight-r1.json`：0 TD 进程 **且** `INT.P4/td`、`INT.P4/r3`、**`20261027-0726_fpga-board-integration/T11.BRD.P1/td`** 三处均 ≥20 min 静默；忙 → `blocked=TOOL_UNAVAILABLE`；**`T:` 已属 board-integration run，不得 remap/-Force**；若窗口内他人启动 TD：不 kill、只让在跑的命令结束、不再启第二条、记重叠；单席位冲突不重试 |
| 角色 | **恢复原 TD 开发会话 `ses_e85b9e73effe3tYbVh2330erSx`**（同任务新轮）→ 完成后**新**综合测试者（不重跑 TD，≤35 calls/60 min） |
| 预算 | ≤60 calls / ≤180 min；synth ≤1,800 s；route ≤2,400 s/次；analysis ≤600 s |
| 再失败 | 若再次 elaborate 失败：**不自动重启第三次**，冻结证据返回，由原规划决定是否动用最后一次启动配额，或把 P3 记为 `not_eligible(不可综合)` |
| 残余风险 | board-integration run 活跃且持有 synth 2/route 2/bitgen 1 余额，可能在窗口内启动 TD；本规划已披露，冲突按上格处理 |

---

## 13. P3 放行条件（r1 更新）

`T10.ah-dual-verdict` 放行需三者同时满足：
1. **A 已 kill_verified**（✅ 2026-10-27 07:45，报告 `test-reports/T10.ah-a-plus-h-r2-r0-integrated.md`，manifest `59805d90…`）；
2. **synthfix 测试者 PASS**（✅ 2026-10-27 09:13，manifest `034777c5…`，core `d2960cfe…`）；
3. **TD r1 有确定性结果**（测试者判定或明确 blocked）。

之后由原规划写 `dual-verdict.md`（0 sim / 0 TD / 0 新角色），内容除 §4 全部条款外，新增：
- H-only 修好可综合性后的候选资格只能由 **TD r1 `eligible`** 支撑；未 eligible 时不得写"可作为候选进入后续"；
- 必须保留三条限定（N +0.859% 薄裕量、prototype gate ≠ 整机 G0、0 bit/0 板级）；
- 若 r1 仍 `not_eligible`，给出真实 WNS/Fmax/资源/关键路径与下一包建议（单锥 retime / 结构方案 / 布局参数），不得用放宽时钟或例外求过。

---

## 14. 包/角色/依赖账（r1）

| # | task | 状态 | 角色 | 依赖 |
|---|---|---|---|---|
| 1 | `T10.ah-a-plus-h-r2` | closed（kill_verified / not adopted） | 无 | — |
| 2 | `T10.ah-honly-synthfix` | **closed（PASS）** | 无 | — |
| 3 | `T10.ah-honly-td` | r0 FAIL（不可综合）；r1 **blocked（TOOL_UNAVAILABLE）/ not_evaluated** | 无（已收尾） | 包 2 ✅ |
| 4 | `T10.ah-dual-verdict` | **closed（`dual-verdict.md`）** | 原规划（已执行） | 包 1 ✅ / 2 ✅ / 3 结果 ✅ |

---

## 15. 收尾（2026-10-27 10:10，`dispatch.status=finished`）

- 合并判定：`dual-verdict.md`（0 sim / 0 TD）。
- 技术收尾：`final-summary.md`；接手/下一步：`handoff.md`；用户短总结：`user-summary.md`。
- 逐包终态：A closed（kill_verified / not adopted）；synthfix closed（PASS）；honly-td r1 blocked（TD 6.2.3 ChipWatcher coredump，`not_evaluated`）；dual-verdict closed。
- 唯一候选（provisional）：core `d2960cfe…`（85,221 B）+ frame_top `4afc26e2…`（29,207 B），synthfix manifest `034777c5…`；**未获实现资格**。
- 下一包建议：`T10.ah-honly-td-route`（TD 布线绕行，新配额，需用户授权，bitgen 0）或新仓只读 diff 迁移评审；两者均给出准确启动文本（`handoff.md §5`）。
- 本 run 全程 0 bitgen/CWC/下载/Flash/板卡/COM/JTAG/RK/网络/git；未改写任何旧候选/旧报告/其他 run。

= 4 个正式包（上限），不新增；TD r1 复用同任务 ID。
