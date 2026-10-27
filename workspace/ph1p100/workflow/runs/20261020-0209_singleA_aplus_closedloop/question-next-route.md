# 需要用户确认：T10 后续路线（推荐 B：187.5 MHz 单时钟 + 2-cycle hash/threshold）

日期：2026-10-21｜run：`20261020-0209_singleA_aplus_closedloop`｜当前 task：`T10.a1-eng-freeze`

## 现状

- **G0/G1 PASS**：P2 13/13、P3 20/20、0 mismatch、`vlog 0/0`；1080p 4,677,945 cycles = 103.892 MB/s @187.5；P2 comp 81.067 MB/s。
- **G2 FAIL**：r10 S1 WNS -0.450 ns、TNS -51.634、144 端点；r8/r9/r10 WNS 平台 -0.43~-0.47。
- r10 瓶颈：`pos_reg[1] → hdist = pos - hent_pos → hit/阈值使能 → thresh_base_reg[3].ce`，7 级 5.716 ns、4 ADDER；继续局部补丁会把瓶颈推到下一条 5.7 ns 路径。
- 当前候选：core `7a10917d…aed8`、frame `fa64cb48…1ba2`、SDC `227dd39e…6311`；manifest `CANDIDATE-MANIFEST-r10.json`。

## 三条路线对比

| 路线 | 时钟/架构 | 预期吞吐 | 时序收敛概率 | 工作量 | 对需求二/三板级影响 | 97.2 余量 |
|---|---|---|---|---|---|---|
| **A. 150 MHz + 异步 FIFO/CDC** | A+ 独立 150 MHz，CDC 接 187.5 系统 | 83.1 MB/s（145 MHz 为 80.3） | 较高：150 MHz 低于当前综合 ~172.9，但布线/CDC 另算 | 中高：PLL/双时钟 BRAM、CDC 同步/复位、跨域约束、系统集成 | 大：新增时钟域与 CDC，板级/生产集成需重做验证 | **放弃**（需 ≥175.4 MHz） |
| **B. C-lite：187.5 单时钟 + 真实 2-cycle hash/threshold** | 单时钟 187.5；新增状态/valid 握手，不用 false path/multicycle | 目标 ≥77.76；97.2 取决于新增 cycles（预算 6.25M / 5.0M） | **高**：2-cycle 预算 10.666 ns，当前路径 5.716 ns，布线余量充足 | 中：FSM/valid 握手、吞吐实测；无 CDC/PLL | 小：保持 187.5 单时钟，生产集成接口不变 | **可争取，但不保证**；仅 322k cycles 余量（+6.9%） |
| **C. C-full：新匹配/哈希微架构** | 187.5 单时钟，重排 hash/match 数据路 | 目标 103.9（保 97.2） | 不确定：需重新收敛多条 5–6 ns 路径 | 高：新微架构、多轮综合 | 小（单时钟）但周期长 | 可能保住 |

## 推荐：B（C-lite）

理由：
1. **唯一不改变 187.5 MHz 单时钟架构**的路线；不需要 PLL/CDC/跨域约束，生产集成接口不变，板级风险最小。
2. **时序预算充足**：2-cycle 路径 10.666 ns，当前关键路径 5.716 ns；把 `hdist`/hit/阈值使能拆成两拍有很高概率过 0（估计 >80%）。
3. **吞吐有明确上限**：77.76 对应 6,250,000 cycles/帧，当前 4,677,945，余量 1,572,055（+33.6%）。只要新增气泡不超过该预算，就能满足硬门槛；97.2 对应 5,000,000 cycles，仅余 322k（+6.9%），是“争取项”，不是硬承诺。
4. **比 A 更符合“跑通”**：A 虽时序压力小，但放弃 187.5 与 97.2，并引入 CDC/双时钟集成；B 若成功可同时守住 187.5 和硬门槛，97.2 仍有机会。
5. **比 C 风险低**：C 需要重排匹配/哈希微架构，工作量和收敛风险最高；B 是对现有路径的局部两拍化，改动面可控。

**诚实结论**：B 的时序收敛概率高，硬门槛 77.76 概率高；97.2 只有约 6.9% cycles 余量，**不保证**。如果实测 cycles 在 5.0M–6.25M 之间，则 187.5 G2 可成立、硬门槛满足，但 97.2 未达；如果在 6.25M 以上，B 失败，应停止并回到 A/C 选择。

## 建议的新包（需你确认）

- **包 ID**：`T10.a1-g2-2cyc`（同一 T10 全局任务下的新工作包；不新 run、不重置 P4 修复计数）。
- **允许写**：`upstream/ph1p100-pcie-ep-fpga/rtl/ep_side/codec/a1_deflate_core.v`；`sim/tb/codec/**`、`tools/codec/**`、run 新包目录；frame_top/SDC 锁定。
- **≤5 项语义步骤**：
  1. 在 core 新增真实两拍 `hdist`/hit/阈值使能通路（寄存器 + valid/state 握手，禁止 false path/multicycle）。
  2. 与现有 S_SCAN/match 流水重叠；定义需要等待时的 stall/backpressure，保证不丢符号。
  3. 吞吐实测：1080p p1d1、P2 comp、stored；报告 cycles，硬门槛 ≤6,250,000，97.2 目标 ≤5,000,000。
  4. TD：187.5 MHz，综合 WNS/TNS≥0 才布线；Routed WNS/TNS/HWNS/HTNS≥0、0 违例、资源在器件内、report_cdc 实际执行、bitgen not_run。
  5. 冻结 manifest/result/rollback；独立综合测试。
- **建议预算**：开发 60 min / 40 calls；TD **3 会话 / 120 min**（综合 ≤3、布线 ≤1）；测试 45 min / 30 calls。
- **停止**：吞吐 >6.25M cycles、P2/P3 mismatch、二次/三次综合仍 <0、route 失败、资源/CDC 问题 → 停；不自动续包。
- **禁止**：降频、false path/multicycle、seed sweep、bitgen、下载、Flash、C/RK/双路/G4、生产集成；不改协议/端口/帧语义/CRC/长度/abort/Bayer/SDC。

## 请确认（原话示例）

> **“同意新包 T10.a1-g2-2cyc：187.5 MHz 单时钟、2-cycle hash/threshold；开发 60 min/40 calls；TD 3 会话/120 min；接受先保证 ≥77.76 MB/s，97.2 尽力；不 false path/multicycle/降频/bitgen/下载。”**

或直接选择 A / C。未确认预算前，规划不派新包、不消耗 TD。

## 恢复入口

- `dev-plan.md §23`
- `handoff.md §20`
- `final-summary.md §12`
- `T10.a1-eng-freeze/p4/result-r10.md`
- `T10.a1-eng-freeze/r10/reports/syn_gate_timing_s1.rpt`
- `T10.a1-eng-freeze/CANDIDATE-MANIFEST-r10.json`
