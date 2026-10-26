# 需要用户决定：r5 已用尽，是否明确授权 r6（需会话数/分钟数）

日期：2026-10-20｜run：`20261020-0209_singleA_aplus_closedloop`｜task：`T10.a1-eng-freeze`

## 当前事实

- **G0/G1 PASS**：P2 13/13、P3 20/20、0 mismatch、`vlog 0/0`；P2 comp **81.067 MB/s**；1080p 103.892 MB/s（较 r4 仅 +4 cycles）。
- **G2 FAIL（但已大幅收敛）**：r5 S1 WNS -0.957 ns / Fmax 158.983 MHz；S2（best，冻结）WNS **-0.949 ns**、TNS -303.718 ns、Fmax **159.185 MHz**、420/143,419 端点；S3 `ext_end_r` 实验 -1.864 ns，已回退。
- 关键路径：`raddr_reg[2] → bm_a 异步读 → cq → S_EXT/state_reg.ce`，8 级 **6.215 ns**；r4 的 packer 长路径已拆掉。
- 候选：core `a6f323ab…dcae`，frame `3c32803b…`，manifest `CANDIDATE-MANIFEST-r5.json`；未 route、无 CDC 报告、无 bit/CWC、无下载、未上板。
- 进展：84.7 → 109.3 → 109.6 → 129.8 → 128.6 → **159.2 MHz**；剩余 **-0.949 ns**。

## 为什么“接着做”不够授权 r6

1. r5 预算是 **3 会话 / 150 min**；**3/3 会话已用尽**。虽然实际 wall 仅约 18 min，但“会话数”和“分钟数”是双重上限，剩余分钟不等于第 4 个会话。
2. work-limits §4：只有用户明确给出新的有限目标数、任务数或层数，规划才可记录覆盖值；“全部做完/接着做/时间宽裕”不是授权。你两次“接着做”都没有给出会话数或分钟数。
3. 无工具/设备/资料/权限/额度等外部条件变化；WNS 从 -2.446 改善到 -0.949 是设计进展，不是外部条件变化。
4. 不得用新 ID/改名/新 run 绕限。

**结论**：r5 收尾为 FAIL/blocked；T10 仍 **3/4 PASS + 1 ⚠**，不完成；**不自动开 r6**。

## 请选择

**A. 保持 ⚠，停止 G2 时序收敛**
- T10 记 3/4 PASS + 1 ⚠；保留 r5 候选/证据；转需求二/三板级前置。

**B. 明确授权 r6（建议 2 会话/90 min）**
- 请原话写明，例如：**“授权 r6：2 会话/90 分钟”**（或给出你决定的会话数与分钟数）。
- 建议范围：只做 `bm_a`/`cq → S_EXT/state` 的吞吐中性 1-cycle 预取+寄存，把 `S_EXT` 的 state 决策从 `cq` 组合路径分离；保留 r5 packer/opq 结构。
- 建议预算：2 会话、单会话 ≤75 min、总 ≤90 min；综合 ≤2、布线 ≤1；综合 WNS/TNS≥0 才布线；route 只 1 次、不 seed sweep；若 r6 best WNS<-1 ns 或仍 <0，停止，不自动 r7。
- 门槛：187.5 MHz、`Routed`、WNS/TNS/HWNS/HTNS≥0、0 违例、资源在器件内、`report_cdc` 实际执行、bitgen `not_run`；每符号 1 cycle，P2 comp/1080p ≥77.76 MB/s。
- 禁止：降频、false path/multicycle、seed sweep、bitgen、下载、Flash、C/RK/双路/G4、生产集成。

**C. 只做离线架构方案/评审**
- 不写 RTL、不构建；输出剩余 0.949 ns 的闭合方案与吞吐预算文档。

**D. 转板级需求二/三**
- 仅在你到场且板窗可用时；当前无 Routed A+ bit，只能先做基线/真实 RAW 导出前置。
- 最小前置：板窗与你在场；供电/JTAG/相机/存储可用；对现有生产 B01 bit 的一次性 SRAM 下载授权（不生成 bit、不 Flash/efuse/SPI/svf）；非 PCIe 大块导出通道与主机校验脚本；真实 ROI/相位/曝光确认。
- 本轮不派下载、不假设板窗。

## 恢复入口

- `dev-plan.md §16`
- `handoff.md §13`
- `final-summary.md §12`
- `T10.a1-eng-freeze/p4/result-r5.md`
- `T10.a1-eng-freeze/r5/reports/syn_gate_timing_s2.rpt`
- `T10.a1-eng-freeze/CANDIDATE-MANIFEST-r5.json`

未得到明确会话数/分钟数之前，规划不派 r6、不再消耗 TD 会话、不下载、不上板。
