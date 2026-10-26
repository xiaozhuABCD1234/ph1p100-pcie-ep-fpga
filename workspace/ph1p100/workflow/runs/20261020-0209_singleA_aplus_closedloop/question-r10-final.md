# 需要用户决定：T10 G2 最终处置（A 保持 ⚠ / B 路线 b / C 新架构包）

日期：2026-10-21｜run：`20261020-0209_singleA_aplus_closedloop`｜task：`T10.a1-eng-freeze`

## 最终事实

- **G0/G1 PASS**：P2 13/13、P3 20/20、0 mismatch、`vlog 0/0`；P2 comp 81.067 MB/s、rand 178.351 MB/s；1080p 4,677,945 cycles = 103.892 MB/s。
- **G2 FAIL**：r10 S1 WNS **-0.450 ns**、TNS **-51.634 ns**、144/148,921 端点；1/2 综合、0/1 布线；未 Routed、无 CDC 报告、无 bit/CWC。
- **平台期确认**：r8 -0.470 → r9 -0.434 → r10 -0.450 ns；TNS 约 -37 ~ -52；端点 147/144。r10 已把读地址链移开，但新瓶颈是 `pos_reg[1] → hdist = pos - hent_pos → hit/阈值使能 → thresh_base_reg[3].ce`，7 级 5.716 ns（4 个 ADDER）。
- **候选**：core `7a10917d…aed8`；frame `fa64cb48…1ba2`；SDC `227dd39e…6311`；manifest `CANDIDATE-MANIFEST-r10.json`。
- **证据偏差（如实登记）**：r10 早期一次 P2 误用 r9 subst 目录，重写了 `r9/p2/runs/*` 与 `r9/p2/logs/vlog.log`（`02dfece1…4996` → `58d0ebaa…a61`）。`r9/p2/result.json` 未变且仍匹配 r9 manifest（`6ab4d148…d130`）；r9 其余 manifest 项未受影响。r9 功能结论仍有 result.json 与 stream sha 支撑，但原始 vlog 日志不再可按 r9 manifest 复核。r10 P2/P3 修正后 PASS。

## 技术结论

1. **187.5 MHz 继续局部/结构补丁已不值得**：连续三轮 WNS 在 -0.43 ~ -0.47 ns 平台，TNS 仍 -37 ~ -52、约 144 个端点；r10 的读地址寄存已生效，瓶颈转到 `hdist`/hit/阈值使能（4 个 ADDER）。继续逐条打补丁只会把瓶颈推到下一条 5.7 ns 级路径；要闭合 187.5，需要多周期 hash/threshold 或换匹配微架构，不是当前范围内的局部修改。
2. **路线 (b) 145–173 MHz + 异步 FIFO/CDC**：
   - 按 1.8047 cycles/B：145 MHz ≈ **80.3 MB/s**、150 ≈ 83.1、160 ≈ 88.7、165 ≈ 91.4、170 ≈ 94.2、173 ≈ **95.8 MB/s**。
   - **77.76 MB/s 可满足**（145 MHz 已有约 3.3% 余量；150 MHz 约 6.9%）。
   - **97.2 MB/s 余量目标必须放弃**：需要 ≥175.4 MHz，而 r9/r10 的 WNS 反推 Fmax 仅约 172.9–173.4 MHz（综合值，布线后更低）。
   - 代价：新增 A+ 时钟域（MMCM/PLL）、异步 FIFO（双时钟 BRAM）、CDC 同步/复位序列、跨域约束、系统集成与板上验证；这是**时钟架构变更**，不是当前 T10 G2 的局部修补，需新 run/新包与单独预算。
3. **新架构包（C）**：若仍要 187.5，需要覆盖 `hdist`/hit/阈值比较与使能逻辑，做多周期 hash/threshold 或匹配引擎重排；工作量和风险显著大于当前轮，需新 run/新授权，且不保证收敛。

## 请选择

**A. 保持 ⚠，收尾 T10（推荐，按现行规则）**
- T10 记 **3/4 PASS + 1 ⚠**，不称完成；保留 r0–r10 证据与回退。
- 不再消耗 TD 会话；转需求二/三板级前置（仍需板窗、真实 RAW、下载授权）。

**B. 明确同意路线 (b)（时钟架构变更）**
- 请原话写明，例如：
  **“同意路线(b)：A+ 小顶运行在 145–150 MHz，异步 FIFO/CDC 桥接 187.5 MHz 系统；接受 ≥77.76 MB/s 成立、97.2 余量目标放弃；授权新 run/新包及预算 X。”**
- 必须明确：目标频率（建议 145–150 MHz，布线余量更稳）、是否放弃 97.2、授权新 run/新包、TD/板上预算。
- 该路线只证明 A+ 在较低时钟域可服务 ≥77.76 MB/s，**不能把当前 T10 G2 改判 PASS**。

**C. 另行新架构包，继续冲 187.5**
- 需新 run 或明确的新授权；范围覆盖 `hdist`/hit/阈值比较与使能逻辑（多周期 hash/threshold 或匹配引擎重排）。
- 不保证收敛；需要新的预算、停止条件和独立测试计划。

## 恢复入口

- `dev-plan.md §22`
- `handoff.md §19`
- `final-summary.md §12`
- `T10.a1-eng-freeze/p4/result-r10.md`
- `T10.a1-eng-freeze/r10/reports/syn_gate_timing_s1.rpt`
- `T10.a1-eng-freeze/CANDIDATE-MANIFEST-r10.json`

未得到你的明确选择前，规划不派 r11、不再消耗 TD 会话、不下载、不上板。
