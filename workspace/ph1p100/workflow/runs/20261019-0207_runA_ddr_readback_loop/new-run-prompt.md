# new-run-prompt.md — 新对话启动文本（可直接复制，无需改字）

## 用法

- **OpenCode**：复制下面「OpenCode 版」整段（含第一行命令），粘贴到新对话发送。
- **Codex**：把第一行换成 `$fpga-orchestrator 执行：...`，其余需求文本完全相同（见文末「Codex 变体」）。

---

## OpenCode 版（整段复制）

```
/fpga-orchestrator 执行：推进 T10 压缩 RTL 与 RAW 回退。进度优先；长稳（G4）与 RK/PCIe 主机侧先放一放；不接 PCIe/RK、不写 Flash、不推送；如涉板仅 SRAM。压缩路线按 2026-10-20 用户决策：先 A+（Bayer 可逆预处理 + LZ77/DEFLATE 标准流 + 块级 RAW 回退；容器预留 Rice 第二模式），阶段 1 全 PASS 后再做 C（逐块自适应：标准子流 / 有界 Rice / RAW 三选一）。

【项目根】C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道

【只读参照】
- workflow\runs\20261019-0207_runA_ddr_readback_loop\next-task-and-progress.md（下一任务定义、进度口径）
- workflow\runs\20261019-0207_runA_ddr_readback_loop\compression-options.md（A/B/C 组合对比、用户决策记录 §10）
- workflow\runs\20261019-0207_runA_ddr_readback_loop\final-summary.md、dispatch.json（本线 Track A 终态）
- workflow\tasks.json（T10 条目：ready；depends_on T03/T04）
- docs\planning\2026-10-17-master-plan\01_后续小任务清单.md（MP20—MP31 压缩相关）
- workflow\runs\20261019-0212_codex_fpga_closedloop_b2（并行线 Track B；只读、不合并、不触碰其文件）

【任务与路线】
- 全局任务：T10 压缩 RTL 与 RAW 回退（沿用任务板 T10；不新增全局任务 ID）。
- 阶段 1（本 run 必做，4 包）：A+ = Bayer 相位重排 + 可选同色预测（A/B 开关）→ LZ77 匹配/字典 → DEFLATE/GZIP 兼容（fixed/dynamic Huffman、位打包）→ 块级 RAW 回退用 stored blocks（整帧仍是合法标准流）；容器预留 Rice mode 位；独立软件解码 round-trip（zlib/第三方 + 自研双解）；资源与吞吐证据（单A 1080p30 = 77.76 MB/s 目标；双路 155.52 MB/s 只记录差距，不声称达成）。
- 阶段 2（阶段 1 全 PASS 后，由原规划在同一 T10 run 追加 2–3 包；或经用户确认另起 run）：C = 统一块容器 + 逐块模式选择 {标准子流（DEFLATE）、有界 Rice、RAW/stored}；含 Rice 编码器/解码器扩展、选择器、正负例、比率增益与最坏膨胀、资源/吞吐复核。
- 阶段 2 启动条件（全部满足）：阶段 1 G0/G1/G2 全 PASS；软解 round-trip 0 mismatch；单A 吞吐达标；资源余量足够（粗略 LUT ≥15k、ERAM ≥20，以实测为准）；时间窗允许；Rice/自描述格式的规则口径已明确（否则 Rice 只作扩展/演示，提交口径用“标准子流 + stored”合规子集）。
- 若阶段 2 条件不满足：C 转后续主题/后续 run，阶段 1 候选为交付；不得静默丢弃 C，须在收尾交接写明。

【范围与边界】
- 建议写域：上游生产仓新 worktree/分支（例如 upstream\ph1p100-pcie-ep-fpga-wt-<run>），不与 0212/其他线共享写树；不碰对方文件；TD 会话与板卡窗口与其他线串行互斥；如涉板仅 SRAM、≤1 次下载、零 Flash。
- 不分配压缩枚举（T03 合同）；不碰 T11 冻结输入；不做 PCIe/RK 实机、双路 60fps/4K、G4 长稳、发布材料。
- 不改 workflow\tasks.json（由新 run 原规划按既有规则在收尾决定是否更新）；不批量删除；不推送。
- 先按 fpga-orchestrator 流程完成规划与冻结，再派开发；默认 batch=1、1 主要目标、≤4 包、两级、每包 ≤5 语义步骤；每包新开发 + 一个独立综合测试者。

【期望产出（阶段 1，粗划 4 包）】
1. codec-core：格式/块结构冻结；LZ77 匹配/字典；fixed/dynamic Huffman/位打包；Bayer 前端 A/B；块头/CRC/长度 + RAW 回退；模块 TB + 负例。G0/G1。
2. codec-decode：独立软件解码器；冻结向量 round-trip 0 mismatch；尾块/截断/坏 CRC/非规范尾部；A/B 比率 + 最坏膨胀上界（RAW/stored = 原长 + 块头）。G0/G1。
3. codec-top：小顶 + 流式/反压/首帧/持续输入；资源/吞吐估算；G2 小顶构建（≤30 min，≤2 次）。G0/G1/G2。
4. codec-freeze：manifest/哈希链；T11 集成接口（格式/块头/长度/CRC 覆盖范围/枚举不自行分配）；回退/新旧并列。G0。

【验收门槛】G1：TB ALL PASS、vlog Errors:0、负例全部拒收、round-trip 0 mismatch；G2：Routed、SWNS/STNS/HWNS≥0、0 违例、资源在器件内；吞吐：单A 1080p30 持续 ≥77.76 MB/s（或给出经证据的降速/并行方案），双路只记录差距；膨胀：最坏膨胀上界有证明（平均值不作门槛）；证据：manifest 0 不一致、软解码器可复跑、不得自定义 token 冒充 zlib。
【当前进度参考】完整赛题交付口径约 40%（±8）；FPGA 侧当前主线约 80%。T10 是最大缺口。
```

---

## Codex 变体

把上面第一行替换为：

```
$fpga-orchestrator 执行：推进 T10 压缩 RTL 与 RAW 回退。进度优先；长稳（G4）与 RK/PCIe 主机侧先放一放；不接 PCIe/RK、不写 Flash、不推送；如涉板仅 SRAM。压缩路线按 2026-10-20 用户决策：先 A+（Bayer 可逆预处理 + LZ77/DEFLATE 标准流 + 块级 RAW 回退；容器预留 Rice 第二模式），阶段 1 全 PASS 后再做 C（逐块自适应：标准子流 / 有界 Rice / RAW 三选一）。
```

其余（项目根、参照、任务与路线、范围与边界、期望产出、验收门槛）与 OpenCode 版相同，原样保留即可。

---

## 说明（不用复制）

- 本文件只含启动文本；0207 run 未派发任何开发/测试、未改 `workflow\tasks.json`、保持 finished。
- 若新对话的规划角色认为阶段 1 的 4 包需要调整，以新 run 的规划冻结为准；本文件只固定“T10 + A+→C + 边界/验收”的意图。
