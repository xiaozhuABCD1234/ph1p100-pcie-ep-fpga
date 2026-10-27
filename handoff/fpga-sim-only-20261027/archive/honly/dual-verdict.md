# dual-verdict — T10.ah-dual-verdict（P3，2026-10-27 10:05）

**本文件 0 simulation / 0 TD / 0 新角色**：只合并本 run 两条线的既有冻结证据。不重算、不重跑、不改任何候选。执行者：原规划。

---

## 0. 一句话结论

| 线 | 结论 |
|---|---|
| **A（A+H 原型）** | **不采用（kill / not adopted，kill_verified）**。A 破坏 zlib 逐字节等价，且 N4 增益 92,265 < 100,000。 |
| **H-only（唯一候选）** | **prototype 4 帧 G0 gate 通过**（N 6,196,749.5 / L 5,834,940，A1U1 头逐字节相同）；**可综合性已修复，187.5 MHz gate-level 综合为正余量（+0.029 ns）、资源低**；**routed TD/STA 未完成**（TD 6.2.3 工具崩溃），**实现资格 = not_evaluated**。 |
| **G0 整机** | **未闭合、未证明**；本 run 只到 prototype 4 帧 gate + 综合级证据。 |

---

## 1. Line A：`T10.ah-a-plus-h-r2` — kill_verified，A 不采用

### 1.1 做了什么

在 H-only r1 冻结候选的独立副本上实现 A：2-position literal 扫描（双端口 htab、每周期两个相邻位置各自判定）+ ≤16 bit 双符号 packer，按 P2 coregap model 定义；只改 core（`+173/−122` 行、8 hunks），`a1_frame_top.v` 未改。仅 ModelSim，0 TD。

### 1.2 两条 kill 事实（各自独立成立，测试者 `kill_verified`）

| 事实 | 数值 | 证据 |
|---|---|---|
| **token 流不等价** | N `stream_len` 1,665,923（基准 1,677,912 / 1,677,336）；L 2,153,391 / 2,154,993（基准 2,156,868 / 2,156,300）；4/4 `.frm`/`.hdr` 整文件 SHA 全不等；A1U1 头字节 **36..43 = `x`**（DUT 真的驱动 X） | `r0/sim/caps/{n,l}-4f.frm`；规划与测试者各自直读 |
| **增益不足** | N4 **6,104,484.5** vs 6,196,749.5 → **92,265 < 100,000**（门槛 6,096,749.5） | `r0/out/a-4frame-gate.json` |
| 附带 | L4 **5,700,538.5** 数值过线，但字节同样不等价 → 不构成补救理由 | 同上 |

- 输入侧完全一致（`raw_crc`/`xform_crc` 与基准相同）；差异只在 core 的 token/pack/CRC 路径。
- `bench`（8b/16b × comp/rand 逐字节相同）、`probe`（6,104,479，2.355 c/B）、`adapter 12/12` 均通过 → **bench 通过不能替代 4 帧等价性**（差异依赖真实 1080p 的 literal/match/块边界交互）。

### 1.3 结论与重开条件

- **A 不采用**；H-only r1 仍是唯一候选。A 的 `f3ee798f…` 候选、manifest `59805d90…`、全部 caps 转只读证据，无后续动作。
- **未解问题（明确标为假设，未验证）**：成对提交改变了 htab 的插入 epoch（lane-B 在 `p+2` 提前写入），使后续查表看到与逐符号算法不同的表状态 → 匹配/literal 判定漂移。若成立，则 "2-position 双 hash 扫描" 在**不改变 token 流**的前提下与当前 htab 结构天然冲突。
- **重开条件**：只有用户新授权 + 新预算 + 先证明"插入 epoch 与逐符号算法严格等价"的设计；不得沿用本次实现。

---

## 2. Line B：`T10.ah-honly-td` — 综合成功、布线被工具崩溃阻断

### 2.1 三轮事实

| 轮 | 结果 |
|---|---|
| r0 | TD elaborate 拒绝：`HDL-8007` `cmem_lo[15]` 多驱动（L673 写端口块 / L964 主时序块）；6.49 s、无 gate DB。**不是时序结论**。 |
| **synthfix**（新包） | 只把三个寄存器的复位并入唯一驱动块（+4/−3 行、2 hunks），`frame_top` 逐字节不变；**PASS**：core `d2960cfe…`（85,221 B），N4 **6,196,749.5** / L4 **5,834,940** 精确，4/4 `.frm/.hdr`（且 `.evt/.stats`）整文件 SHA 相同，bench/adapter 全等，独立重跑 8b comp 304,961 cyc。0 TD。 |
| r1 | **综合 SUCCESS**（43.47 s，无 HDL-8007）；**route 2/2 均在 `import_db` → `Import ChipWatcher` coredump**，无 routed DB。 |

### 2.2 r1 综合实测（gate-level，唯一真实实现数据）

| 指标 | 值 |
|---|---|
| Setup WNS / TNS | **+0.029 ns** / 0.000 |
| Setup 违例端点 | **0 / 4,969**；STA coverage **97.06%** |
| Hold | `flow.status` sentinel（0 failing hold endpoints）；HWNS/HTNS 0.000 |
| Period Check WNS | 2.533 ns |
| 时钟 | 单时钟 clk 5.333 ns（187.512 MHz）；gate R-Period 5.304 ns → **188.537 MHz**（gate Fmax 上界，非布线结果） |
| 资源 | slice **3,337 / 71,680**；reg 1,663；LUT 4,188（LUT6 1,978）；**ERAM 27 + CWC 0 / 300**；DSP 0；**IO 121 / 286** |
| 最差路径归因 | 10 条中 frame_top 2 条（`grp_in_row → smem_waddr_r`，+0.029/+0.071）；core 8 条（`htab_b→hb_r`、`sdata_ptr→state` replay/emit、`len_r→cand_bits`）；**frame_top 双 CRC32 链不在最差 10** |

### 2.3 布线阻断（工具缺陷，非时序失败）

- 两次 route 都在 `import_db ./a1_ah_Runs/syn_1/a1_ah_gate.db` 的 **`Import ChipWatcher`** 语句崩溃（`minidump-20261027-093503.dmp` 78,531 B / `minidump-20261027-093540.dmp` 80,243 B），**发生在 placement 之前**；两次 console 差异只有 Run Date 与 minidump 名。
- 无 `phy_1` 产物、无 `*_pr.db`、无 `routed_*.rpt`、无 QoR/`check_timing`/`report_cdc`；无 `analysis_2096_*`；全 r1 目录 **0 bit/CWC**。
- 唯一 gate DB SHA `169d5937…`（两次 route 用同一 DB，无跨综合拼接）。
- 按 `r2-ruling §2.2`：记 **`TOOL_UNAVAILABLE`**，**不得**记成候选缺陷或"时序失败"，也未做第 3 次（route 2/2、无剩余可辨参数、禁止 seed 扫描）。
- 测试者判定：证据/eligibility 结论正确（**PASS**，`test-reports/T10.ah-honly-td-r1-integrated.md`），**G2 = blocked**（synth pass / routed blocked / analysis not_run），manifest `8325f230…`（83 artifacts，83/83 一致）。

---

## 3. H-only 候选的正式状态

**可作为"临时候选（provisional）"保留，但必须带以下全部限定：**

1. **功能/性能**：prototype **4 帧** S_ss gate 通过 —— N **6,196,749.5**（+0.859%）、L **5,834,940**（+7.113%），A1U1 头/长度/CRC/末字节与基线逐字节相同；**N 侧余量仅 0.859%**，很薄。
2. **可综合性**：已修复（`d2960cfe…`），TD 2026.2 可 elaborate + 综合，0 违例端点，资源低。
3. **实现/时序**：**未评估**。`+0.029 ns` 只是 gate-level 综合，net delay 已占数据通路 52–58%，**布线后为负是合理假设（不是测量）**。
4. **G0**：这只是 prototype 4 帧 gate，**不是整机 G0 闭合**；自然 sensor RAW / 生产 sink / 双路未覆盖。
5. **位流/板级**：0 bitgen、0 CWC、0 下载、0 板卡。

**因此：不得写 "H-only 已过 TD/STA"、不得写 "时序收敛"、不得写 "Fmax 188.5 MHz 可用"、不得写 "G0 整机通过"。**

---

## 4. 能说 / 不能说

| 能说（有证据） | 不能说（无证据） |
|---|---|
| H-only 4 帧 prototype S_ss 达 6.25 M 门槛且逐字节正确 | G0 整机闭合 / 1080p30 生产吞吐达标 |
| H-only（synthfix 版）在 187.5 MHz gate-level 综合为正余量、资源远低于器件 | routed 时序收敛 / 布线后 WNS≥0 / hold≥0 |
| 布线未完成的原因是 TD 6.2.3 的 ChipWatcher 导入崩溃（可复现 2 次、有 minidump） | "H-only 时序失败"或"设计不可布局" |
| A 破坏 zlib 逐字节等价、且增益不足，A 不采用 | "A+H 不可行"（只证明本次实现不满足；理论方案未被否证） |
| gate Fmax 上界 188.537 MHz（R-Period 5.304 ns） | 真实 Fmax（布线后可能显著更低） |
| TD/bitgen/板卡/网络 = 0，无位流 | 任何板级、CWC、RK/PCIe 结论 |

---

## 5. 下一包建议（本轮不派发）

**优先级 1（推荐）：TD 布线绕行包 `T10.ah-honly-td-route`（需用户授权新 TD 配额）**
- 目标：绕开 `Import ChipWatcher` 崩溃，取得 **routed DB → routed STA**，这是当前唯一缺失的关键事实。
- 允许尝试（每项写明参数差异，≤3 次 TD 启动）：① 生成/导入时排除 ChipWatcher/debug 负载；② 换导入方式（直接 `open_project` + `launch_runs phy_1` 而不先 `import_db`，或先 `import_db` 后 `-no_chipwatcher` 类选项）；③ 换 TD 版本或重装/最小工程复现（先用 2 文件 + wrapper 的最小 DB 复现崩溃）。
- 门槛不变：routed WNS≥0、hold≥0、`NUM_FEPS=0`、资源 ≤ 预算；209.6 只做 analysis-only；**0 bitgen**。
- 若绕行仍失败 → 记录 `implementation not evaluated (tool defect)`，候选止步于 gate-level。

**优先级 2：H-only diff 迁移评审（只读，不 push/commit）**
- 在 `D:/fpga/repos/ph1p100-pcie-ep-fpga`（`main`）上做 diff 映射评审：H-only（synthfix 版）相对 `main` 的 `rtl/ep_side/codec/` 的差异、文件归属、是否需要适配；产出评审文档与迁移清单，**不写入仓库、不 commit/push**（需用户单独授权才能落库）。

**不建议**：在 routed STA 缺失时重开 A、加宽 A 方案、或直接做板级/bitgen。

---

## 6. 本 run 的边界（冻结）

- 0 bitgen / 0 CWC / 0 下载 / 0 Flash / 0 板卡 / 0 COM / 0 JTAG / 0 RK / 0 网络 / 0 git。
- 4 个正式包：A（closed kill_verified）、synthfix（closed PASS）、honly-td（r1 blocked=TOOL_UNAVAILABLE，not_evaluated）、dual-verdict（本文件）。
- 唯一候选：**H-only synthfix 版**（core `d2960cfe…` + frame_top `4afc26e2…`），临时状态，未实现资格。
- 回退：任何后续失败可回退到 H-only r1 冻结证据（`f752ae09…`，`8acd20b2…`/`4afc26e2…`）的 4 帧 prototype 结论与 synthfix 的可综合性修复；两者都有完整 manifest。
