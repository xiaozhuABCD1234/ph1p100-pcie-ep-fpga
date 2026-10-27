# final-summary — 20261027-055621_fpga-honly-td-and-ah

- run：`D:/fpga/ph1p100/workflow/runs/20261027-055621_fpga-honly-td-and-ah`
- 收尾时间：2026-10-27 10:10（+08:00）；`dispatch.status = finished`
- 需求：`request.md`（用户原话：并行开两条线——一条做 A+H，一条做 H-only 的 TD/STA）
- 角色：原规划（本文件）汇总；四个正式包，逐包一个开发 + 一个独立综合测试者（不复用）

---

## 1. 逐包结论

| # | task | 结论 | 关键数字 | manifest / 报告 |
|---|---|---|---|---|
| 1 | `T10.ah-a-plus-h-r2` | **closed：kill_verified / A not adopted** | N4 6,104,484.5（增益 **92,265 < 100k**）；L4 5,700,538.5；token 流不等价（N 1,665,923 vs 1,677,912/1,677,336；L 2,153,391/2,154,993 vs 2,156,868/2,156,300）；头字节 36..43 = `x` | `59805d90…` / `test-reports/T10.ah-a-plus-h-r2-r0-integrated.md` |
| 2 | `T10.ah-honly-synthfix` | **closed：PASS** | core `d2960cfe…`（85,221 B，+4/−3 行/2 hunks）；frame_top `4afc26e2…` 未变；N4 **6,196,749.5** / L4 **5,834,940** 精确；4/4 `.frm/.hdr`（及 `.evt/.stats`）整文件 SHA 相同；bench/adapter 全等；0 跨块驱动 | `034777c5…` / `test-reports/T10.ah-honly-synthfix-r0-integrated.md` |
| 3 | `T10.ah-honly-td` | r0 **FAIL（elaborate 拒绝）**；r1 **blocked = TOOL_UNAVAILABLE，eligibility not_evaluated** | r1 synth：**WNS +0.029 ns**、TNS 0、**0/4,969** 端点、coverage 97.06%、Period 2.533、IO 121/286、slice 3,337/71,680、reg 1,663、LUT 4,188（LUT6 1,978）、**ERAM 27 + CWC 0**、DSP 0；route **2/2** 在 `import_db → Import ChipWatcher` coredump（placement 之前），无 routed DB | r1 `8325f230…` / `test-reports/T10.ah-honly-td-r1-integrated.md` |
| 4 | `T10.ah-dual-verdict` | **closed（本文件 + `dual-verdict.md`）** | 0 sim / 0 TD | `dual-verdict.md` |

---

## 2. 三轮 TD 的配额账（`T10.ah-honly-td`）

| 计法 | 值 | 说明 |
|---|---|---|
| TD 启动（lifetime cap 3） | **2 已用**（r0 elaborate 拒绝；r1 综合+2 route 同一轮） | 剩 1，仅应急 |
| 综合**结果** | **1 已用**（r1，43.47 s，成功） | r0 的 6.49 s 失败不产净表/DB/报告 → 不计结果 |
| route | **2/2 已用**（1.44 s / 1.22 s，均 coredump） | 第 2 次唯一差异：在原工程目录而非复制目录 |
| 209.6 analysis | 0/1 | 需 routed DB |
| bitgen / CWC / 下载 / Flash / 板卡 / 网络 / git | **0 / 0 / 0 / 0 / 0 / 0 / 0** | 未尝试 |

**结论**：r1 的综合是**成功的真实测量**；布线失败是**工具缺陷**（TD 6.2.3 导入自身 gate DB 时在 ChipWatcher 阶段崩溃，两次同点、有 minidump），**不是候选缺陷、不是时序失败**。

---

## 3. 预算实绩

| 角色 | 上限 | 实绩 |
|---|---|---|
| A 开发（r0） | 45 calls / 120 min / 仿真 7,200 s / 单次 2,700 s | 9 个 vsim；实际墙钟合计 **5,955 s**（含 1 次重复 n-4f 1,777.7 s）；单次最大 1,777.7 s ✅ |
| A 测试者（kill 审计） | 35 calls / 60 min / 1 次 ≤300 s 重跑 | 1 次 10.2 s 独立重跑 ✅；不跑 4 帧 ✅ |
| synthfix 开发 | 45 calls / 120 min / 仿真 7,200 s / 不跑 probe | 15 条命令 rc=0（详见其报告 §1.2）；bench + N4 + L4 + adapter ✅ |
| synthfix 测试者 | 35 calls / 60 min | 93/93 检查；自有扫描器；独立 8b comp 5.7 s ✅ |
| TD 开发（r0+r1） | 60 calls / 180 min（r1）；synth 1,800 s、route 2,400 s/次、analysis 600 s | r1 窗口 09:33–09:38；synth 43.47 s、route 1.44/1.22 s ✅ |
| TD 测试者（r1） | 35 calls / 60 min，不重跑 TD | 0 TD 调用；独立解析 `flow.status/.area/.timing` ✅ |

**偏差登记（不改变任何结论）**
1. A 任务曾有**两个开发会话**先后/并发写同一目录（07:14–07:25）、删了 2 条 `rc=null` 重复记录、重复启动 1 次 n-4f、报告命令计数写 21/20（实际 19）→ 审计判定不影响 kill gates（`r0-ruling.md §4`；`T10.ah-a-plus-h-r2` 报告 §4.7/§5）。
2. r1 route 第 2 次在 synth 运行目录内执行，route 产物与 synth 证据同目录（OBS-5，证据卫生问题，无数据混拼）。
3. TD 命令 manifest 未记 `rc`（OBS-4），以 `end_marker`/`seconds`/`timed_out` + 脚本 `exit 0` 分支替代。
4. TD 租约与**新并行的 board-integration run** 存在资源竞争：v1 规则（只看 INT.P4）会被误判，r2 起升级为 holder-agnostic **v2** 并披露残余风险；本 run 未 remap/未 -Force `T:`、未 kill 他人进程。

---

## 4. G 层（逐包）

| 包 | G0 | G1 | G2 | G3 | G4 |
|---|---|---|---|---|---|
| A | **fail**（prototype gate：字节不等价 + 增益不足） | pass（70/70 artifacts、previous `f752ae09…`） | not_applicable（0 TD，规划事先理由） | not_applicable | not_applicable |
| synthfix | **pass**（prototype gate 精确复现） | pass（75/75、31 refs、15 commands） | not_applicable（0 TD） | not_applicable | not_applicable |
| honly-td r1 | not_applicable（不产新周期结论） | pass（83/83、DUT 切换绑定、r0 未改） | **blocked**：synth 子项 pass（0 端点 / +0.029 ns / coverage 97.06%）；routed 子项 blocked（无 DB）；analysis not_run | not_applicable（0 bitgen） | not_applicable |
| dual-verdict | 全 not_applicable（0 sim / 0 TD） | — | — | — | — |

---

## 5. 什么被证明了 / 什么没有

**证明（有冻结证据）**
- A 的本次实现在真实 1080p 帧上**不保持 zlib 逐字节等价**，且 N4 增益 <100k → 按预注册规则不采用。
- H-only 的 **4 帧 prototype S_ss gate** 通过：N 6,196,749.5（+0.859%）、L 5,834,940（+7.113%），A1U1 头/长度/CRC/末字节逐字节相同。
- 修复多驱动后，H-only 可被 TD 2026.2 **elaborate + 综合**；187.5 MHz **gate-level** 有正 setup 余量（+0.029 ns）、0 违例端点、资源低（ERAM 27、IO 121、slice 3,337）。
- 布线未完成的原因是 **TD 6.2.3 在 `import_db → Import ChipWatcher` 的 coredump**（2 次同点、placement 之前、有 minidump）。

**未证明（不得越界表述）**
- routed WNS/hold/TNS、真实 Fmax（gate R-Period 5.304 ns → 188.537 MHz 只是 gate 上界）。
- 时序收敛、实现资格（`not_evaluated`）、G0 整机闭合、1080p30 生产吞吐、双路、自然 sensor RAW、生产 sink。
- 位流/CWC/下载/Flash/板卡/COM/JTAG/RK/PCIe/网络（全 0）。
- "A+H 方案不可行"——只证明**本次实现**不满足等价性；理论方案未被否证。

---

## 6. 剩余风险

1. **N 侧余量仅 +0.859%**（6,196,749.5 / 6,250,000），原型 gate 已贴线；即使布线通过，余量也薄。
2. **布线后时序可能为负**：gate-level net delay 已占数据通路的 52–58%（合理假设，非测量）。
3. **TD 工具缺陷未解决**：ChipWatcher 导入崩溃可能与 DB 内 debug 负载有关；绕行方案未验证。
4. **A 的失败根因只是假设**（htab 插入 epoch 漂移），未定位到具体行；未来若重开 A 需重新设计并证明等价性。
5. **并行 run 竞争**：board-integration run 仍活跃并持有 TD 余额；未来 TD 包须先做 holder-agnostic preflight。

---

## 7. 下一包（本轮不派发，需用户授权）

1. **推荐**：`T10.ah-honly-td-route` —— TD 布线绕行包，取得 routed DB + routed STA（187.5 MHz），必要时 209.6 analysis-only；配额建议：TD 启动 ≤3、synth ≤1、route ≤2、**bitgen 0**、analysis ≤1。门槛不变，失败出口 `implementation not evaluated (tool defect)`。
2. **可选**：新权威仓 `D:/fpga/repos/ph1p100-pcie-ep-fpga`（`main`）的 H-only diff **只读迁移评审**（不写、不 commit、不 push；落库需单独授权）。
3. 不建议：routed STA 缺失时重开 A、加宽 A、或直接 bitgen/上板。

启动文本见 `handoff.md §5`。

---

## 8. 唯一候选与回退

- **候选（provisional）**：`T10.ah-honly-synthfix/r0/changed-src/`（core `d2960cfe…` 85,221 B + frame_top `4afc26e2…` 29,207 B），manifest `034777c5…`。
- **功能口径回退**：H-only r1（`f752ae09…`）的 4 帧 prototype 结论。
- **实现口径**：无 routed 结论 → 不得作为"时序已收敛"候选使用。
- 本 run 未改写任何旧候选/旧报告；所有任务目录 append-only。
