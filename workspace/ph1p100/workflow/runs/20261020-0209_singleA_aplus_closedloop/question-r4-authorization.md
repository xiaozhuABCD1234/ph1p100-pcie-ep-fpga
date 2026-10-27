# 需要用户决定：T10 G2 是否授权 r4（超出三轮实际修复上限）

日期：2026-10-20｜run：`20261020-0209_singleA_aplus_closedloop`｜task：`T10.a1-eng-freeze`

## 当前事实

- **G0/G1 PASS**：P2 13/13、P3 20/20、0 mismatch、`vlog 0/0`；1080p p1d1 103.892 MB/s（≥77.76，对 97.2 约 +6.9%）。
- **G2 FAIL**：r3 S2 综合 **WNS -2.374 ns、TNS -417.972 ns、Fmax 129.752 MHz**（目标 187.5 MHz），508/10,476 端点违例；按停止条件**未 route**。
- 无 Routed、无 bit/CWC、无 Flash/下载、未上板。
- r3 只用 `a1_deflate_core.v`：S_MCHK + abort 阈值预计算 + Adler 宽累加；协议/端口/帧语义未改。
- 唯一候选：core `fb6e59e4…4ecf`，frame `3c32803b…`，manifest `CANDIDATE-MANIFEST-r3.json`。

## 为什么规划不自动开 r4

1. P4 已用满 **round0 首次验收 + 3 轮实际修复**（r1、r2、r3）；r4 会是第 4 轮，超过 work-limits 的三轮上限。
2. 你之前的“接着完成原设置目标”是概括性继续指令，没有给出新的轮数/预算，且已用于授权 r3；按规则不能反复用它续预算。
3. 没有工具/设备/资料/权限/额度等外部条件变化；Fmax 84.7→129.8 MHz 是设计进展，不是外部条件变化。
4. 不允许用新包 ID、改名或新 run 绕过上限。

## 需要你选择

**A. 保持 ⚠，停止 T10（推荐，按现行规则）**
- T10 记为 3/4 PASS + 1 ⚠，不称完成；转需求二/三的板级前置（仍需板窗/真实 RAW/你的下载授权）。
- 保留 r3 候选与全部证据，随时可恢复。

**B. 明确授权 r4（第 4 轮，超出上限）**
- 请写明：“授权 `T10.a1-eng-freeze` r4，超出三轮上限；TD 新预算 X 会话 / Y 分钟”。
- 技术范围（开发已给出）：`bm_a`/`htab` 吞吐中性 1-cycle 预取，拆 `raddr_reg[2] → bm_a → hash3 → htab_rd_addr[2] → htab_v → htab_rvalid` 的 9 级 7.643 ns 路径；不得在 `S_SCAN` 加每周期气泡，match-heavy 必须保持 ≥77.76 MB/s。
- 不放宽 187.5 MHz，不 false path/multicycle，不 seed sweep，不 bitgen/下载。

**C. 其他**：指定只做技术分析/纸面方案，不构建。

## 恢复入口

- `dev-plan.md §12`
- `handoff.md`
- `T10.a1-eng-freeze/p4/result-r3.md`
- `T10.a1-eng-freeze/r3/reports/syn_gate_timing_s2.rpt`
- `T10.a1-eng-freeze/CANDIDATE-MANIFEST-r3.json`

未得到你的明确选择前，规划不派 r4、不再消耗 TD 会话、不下载、不上板。
