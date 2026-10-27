# r1-ruling — 20261027-055621_fpga-honly-td-and-ah（2026-10-27 07:52）

覆盖：Line A 关账；Line B r0 失败性质与配额清算；新包 `T10.ah-honly-synthfix` 的冻结规格；TD r1 重新授权；P3 放行；包/角色/预算账。
规划本轮只读复核 + 文件更新；未跑仿真、未跑 TD。

---

## 1. Line A（`T10.ah-a-plus-h-r2`）：**关闭为 kill_verified / not adopted**

- 审计报告：`test-reports/T10.ah-a-plus-h-r2-r0-integrated.md`，首行 `### 判定：PASS`，语义 = **kill 证据审计通过（kill_verified）**，非被审计任务功能通过。
- manifest `59805d9060a7f3f85629f53ca0d4cf4c3038b0dea2a39aed8d548ea0b12c9132`；70/70 哈希、previous `f752ae09…`。
- 两条 kill 理由各自独立成立：token 流不等价（N/L `stream_len` 与基准差 11,989 / 3,477 等；4/4 `.frm`/`.hdr` SHA 不等；头 36..43 = X）；N4 6,104,484.5 / 增益 92,265 < 100k。
- 测试者结论：并发写、两条 `rc=null` 记录被删、报告计数不一致（D1–D8）**不使任何 kill gate 失效**，只降低叙述性 provenance。
- **关账动作：无后续开发/测试/仿真。** 候选 `f3ee798f…` 与全部产物转为只读证据；A 不进入候选集；H-only r1 仍是唯一候选。
- 重开条件（仅用户新授权时）：重新设计且**先证逐字节等价**，并给新预算；不得沿用本次实现。

---

## 2. Line B（`T10.ah-honly-td`）r0：FAIL 是**工具拒绝**，不是时序结论

### 2.1 事实（规划直接读 `r0/td/run-syn1/`）

- `td_commands_prompt.exe ./01_synth.tcl` 于 07:40:21–07:40:26（**6.49 s**）在 **elaborate** 阶段终止：
  - `HDL-8007 ERROR: net 'cmem_lo[15]' is constantly driven from multiple places ... a1_deflate_core.v(673)`
  - `HDL-5007 WARNING: found another driver here ... a1_deflate_core.v(964)`
- 无 gate DB、无 `.timing`/`.area`/`flow.status`；`read_design.error.f` 存在 → core 变 black box，综合未真正开始。
- 综合 1/1（记入启动次数）、route 0、analysis 0、bitgen 0；manifest 34 artifacts；结论 `not_eligible`（**不可综合**，不是"187.5 MHz 不收敛"）。

### 2.2 根因（规划静态复核，非 RTL 修改）

`cmem_lo[15:0]`、`cmem_lo_pend`、`cmem_lo_addr[11:0]` 被**两个 `always @(posedge clk)` 块**同时驱动：

| 驱动块 | 行 | 内容 |
|---|---|---|
| cmem 写端口块 | 673–687 | `cmem_flush` 分支与 `cmem_we_c` 分支写这三个寄存器（**无复位分支**） |
| 主时序块 | 964 起，复位分支 1042–1044 | `if (!rst_n)` 里把这三个寄存器清零 |

ModelSim 允许（后写胜），TD 按"同一 net 多驱动"直接拒绝 ⇒ vlog 0/0 与 TD 失败并不矛盾。规划用独立静态扫描（`_planner_scan_multidriver.py`）确认：core 内**只有这三个**寄存器跨块驱动；`a1_frame_top.v` **零**跨块驱动。该扫描只是规划侧体量评估，TD 仍是权威。

### 2.3 配额清算（明确回答"上次失败是否计入"）

| 计法 | r0 | 结论 |
|---|---|---|
| TD **启动次数**（lifetime cap 3） | 1（07:40 这次） | **计入**，剩 2 |
| **综合结果次数**（产出净表/DB 才算） | 0 | **不计入**——elaborate 失败无净表、无 DB、无时序报告，不能算一次"综合结果" |
| 实际修复轮（round1–3） | 0 | **不计**——缺陷属 DUT RTL，由新包修复；TD 任务自身无可修配置 |
| route / analysis / bitgen | 0 / 0 / 0 | 未消耗 |

**冻结**：`T10.ah-honly-td` r1 获 **1 次综合结果配额** + ≤2 route + ≤1 analysis-only + 0 bitgen，**lifetime TD 启动 ≤3**（r0 已用 1）。若 r1 综合**再次**在 elaborate 阶段被拒，**不得自动重启第三次**：冻结证据返回，由原规划决定是否动用最后一次启动。

---

## 3. 新包 `T10.ah-honly-synthfix`（RTL 修复，0 TD）

### 3.1 目标与候选

- 起点：H-only r1 冻结候选**独立副本**（`a1_deflate_core.v` `8acd20b2…b17b` 85,192 B；`a1_frame_top.v` `4afc26e2…e30a` 29,207 B），复制到本任务 `r0/changed-src/` 后再改；原 run 只读。
- 唯一目标：消除 TD 拒绝的**多驱动**，且**零行为变化**。不改几何、时钟、复位极性、协议、CRC、头布局、H 的 emit/replay 逻辑、匹配/编码算法。

### 3.2 允许的精确 diff（只此两处，白名单）

**编辑 A（必需）**——把三个寄存器的复位并入唯一驱动块（`a1_deflate_core.v` L673 起的 cmem 写端口块）：

```verilog
    always @(posedge clk) begin
        if (!rst_n) begin                  // 新增
            cmem_lo      <= 16'd0;          // 新增
            cmem_lo_pend <= 1'b0;           // 新增
            cmem_lo_addr <= 12'd0;          // 新增
        end else if (cmem_flush) begin     // 原 if (cmem_flush) begin
            ...                            // 原样
```

**编辑 B（必需）**——删除主时序块复位分支里的三条重复驱动（L1042–1044）：

```verilog
            cmem_lo        <= 16'd0;       // 删除
            cmem_lo_pend   <= 1'b0;        // 删除
            cmem_lo_addr   <= 12'd0;       // 删除
```

**硬性禁止**：在该复位分支里给 `cmem`（RAM 数组）赋值（会破坏 RAM 推断）；改变 `cmem_flush` 定义；改 `cmem_we_c` 优先级；把三个寄存器搬到别的块；任何 `ifdef`/`force`/`initial`；任何"顺手"优化。

**同类别扩展（规划授权，限界）**：修复前必须对 `a1_deflate_core.v` + `a1_frame_top.v` 做**全文件多驱动静态扫描**。
- 若只发现上述三个 → 只做 A/B。
- 若发现**同类别**（同一寄存器在"复位分支"和"功能分支"各写一次）的其他实例 → 允许按同一模式修复，但必须在 `SCOPE-EXTENSION.md` 逐条列出（文件/行/寄存器/改法），且总增量 ≤8 行；行为等价的举证责任不变。
- 若发现**不同类别**（功能块之间互驱、wire 多驱、跨模块 force 等）→ **停止**，交原规划，不得自行扩大。

### 3.3 验收门槛（冻结，任一不过即 FAIL）

| 项 | 阈值 |
|---|---|
| 多驱动 | 修复后静态扫描 **0** 跨块驱动（core + frame_top） |
| 编译 | `vlog -sv +define+SIMULATION` 0 errors；warning 不高于 H-only r1 的 21 条同源（新增必须解释） |
| b6 bench | 8b/16b × comp/rand：comp 50,310 B `2601d57c…a7c05` 304,961 cyc；rand 153,766 B `54f262f2…96dd` 161,479 cyc；Python `zlib.decompress` 逐字节还原 |
| adapter | `ADAPTER_PASS cases=12 errors=0` |
| **N4 S_ss** | **= 6,196,749.5**（精确；S_23 6,196,750 / S_34 6,196,749） |
| **L4 S_ss** | **= 5,834,940**（精确，S_23 = S_34） |
| 4 帧逐字节 | `n-4f.frm` `b9cb5359…`、`n-4f.hdr` `c7fe281c…`、`l-4f.frm` `8aad9099…`、`l-4f.hdr` `864d2fba…`，**整文件 SHA 相同**；4/4 帧 header/CRC/length/last byte 相同 |
| stall | 无 `SS_STALL*`/`B11_FULL_TIMEOUT`（1 帧 probe 的 export 后 timeout 伪影不适用，因为本包不跑 probe） |
| TD | **0**（本包不做综合/布线/STA） |

**容忍度**：S_ss 只接受**精确相等**；任何偏差先按确定性仿真问题复跑一次同一输入（仅一次），仍不等即 FAIL。逐字节不接受任何容忍。若确认修复本身导致周期变化（理论上不应），开发须返回 FAIL + 证据，不得改门槛。

### 3.4 预算与角色

| 项 | 值 |
|---|---|
| 角色 | **新开发**（不与 A/B 复用）+ 之后 **新综合测试者** |
| 调用/时长 | ≤45 calls / ≤120 min |
| 仿真总墙钟 | ≤7,200 s（各 vsim seconds 之和） |
| 单次 vsim | ≤2,700 s（N4/L4 各一次；H-only 实测 1,700.0 / 1,734.8） |
| bench / adapter | ≤300 s 每次 |
| 1 帧 probe | **不跑**（省 620 s；4 帧即门槛） |
| 产物 | `r0/changed-src/{a1_deflate_core.v,a1_frame_top.v}` + 5 TB 副本、`DIFF-synthfix.md/.raw`、`SCOPE-EXTENSION.md`（如有）、`sim/{logs,caps}`、`sim/commands-r0.jsonl`、`out/*.json`、`manifest-r0.json`、`result-r0.md`、`lessons-r0.md` |

---

## 4. TD r1 重新授权（`T10.ah-honly-td`，同任务新轮）

- **前置**：synthfix 包 `ready_for_test` + 其测试者 **PASS**（冻结 manifest 绑定新 core SHA）。
- **DUT 切换**：TD r1 必须绑定 synthfix 的 `a1_deflate_core.v`（新 SHA）+ `a1_frame_top.v`（必须仍为 `4afc26e2…`，逐字节不变）；`01_synth.tcl` 的 `add_files` 路径必须改为 synthfix 路径并记录新旧 SHA；wrapper 不变但需重记哈希。
- **配额**：1 次综合结果 + ≤2 route + ≤1 analysis-only + 0 bitgen/CWC/下载/Flash/板卡；lifetime TD 启动 ≤3（已用 1）。
- **门槛**（不变）：routed 上 WNS ≥ 0、hold ≥ 0、`NUM_FEPS = 0`（取 `flow.status`）、ERAM+CWC ≤300、slice ≤71680、IO ≤286；记录 STA coverage、`check_timing`/`report_cdc`、≥10 条最差路径归因（frame_top 双 CRC32 / core replay / scan）。
- **209.6 MHz**：仅同一 routed DB 收紧时钟的 analysis-only，必须标注非布线结果。
- **租约**：开 TD 前自检（0 TD 进程 + `INT.P4/td`/`INT.P4/r3` 20 min 静默）；忙则 `blocked=TOOL_UNAVAILABLE`。`T:` 仍不得 remap/-Force。
- **角色**：恢复原 TD 开发会话 `ses_e85b9e73effe3tYbVh2330erSx`（同任务新轮）；完成后**新**综合测试者（不重跑 TD）。

---

## 5. P3（`T10.ah-dual-verdict`）放行

三个条件：**A 已 kill_verified（✅ 本次完成）** + **synthfix 测试者 PASS** + **TD r1 有确定性结果**（测试者判定或明确 blocked）。之后由原规划写 `dual-verdict.md`（0 sim / 0 TD / 新角色 0）。
内容沿用 `dev-plan.md §4`，并新增：H-only 在"修好可综合性后"的候选资格表述——只有 TD `eligible` 才能写"可作为候选进入后续"，且必须带 N 侧 +0.859% 薄裕量、prototype gate ≠ 整机 G0、0 bit/0 板级三条限定。

---

## 6. 包 / 角色 / 依赖账（本轮上限 4 包）

| # | task | 状态 | 角色 | 依赖 |
|---|---|---|---|---|
| 1 | `T10.ah-a-plus-h-r2` | **closed（kill_verified / not adopted）** | 无（不再派） | — |
| 2 | `T10.ah-honly-synthfix` | **ready** | 新开发 → 新测试者 | H-only r1 只读 |
| 3 | `T10.ah-honly-td` | r0 **FAIL（不可综合）**；r1 **blocked** | 恢复原 TD 开发 → 新测试者 | 包 2 PASS |
| 4 | `T10.ah-dual-verdict` | **blocked** | 原规划 | 包 1–3 结果 |

= 4 个正式包，恰在上限；**不再新增包**（TD r1 复用同任务，不新造 ID）。

---

## 7. 风险与预案

| 风险 | 预案 |
|---|---|
| 修复后仍有未被静态扫描捕获的多驱动（break/assign/跨模块） | r1 综合若再报 HDL-8007：不自动重启，冻结证据，用最后一次启动配额；若仍失败则 P3 记 `not_eligible(不可综合)` 并建议独立"elaboration 清理"包 |
| 复位合并改变周期（理论上不应） | N4/L4 必须精确等于 6,196,749.5 / 5,834,940；不等即 FAIL，不调门槛 |
| 修复破坏 byte-exact | 任一 `.frm/.hdr` SHA 不等即 FAIL |
| synthfix 测试者发现 manifest 漂移 | 停止，重新冻结；不拼旧证据 |
| TD r1 实际 WNS<0 | 记 `not_eligible` + 真实数字 + 关键路径，P3 据此提下一包（单锥 retime / 结构方案 / 布局参数），不放宽 |
