# lessons — `T10.dual-aplus-service-verdict` r0

只记可复用根因/触发/修正/验证入口，不重复报告全文。

## 1. 判定纪律

1. **双核不改变 per-stream 容量。** 每核服务一路时 per-stream = 单核容量；`2C ≥ 155.52` 只是聚合值，且本 run 连 2×C_chain（151.369）都低于 155.52。凡“双核 feasible”类结论必须先过 `per-stream chain` 与 `dual-core timing unproven` 两道门。
2. **core-only 只能当乐观上界。** 1080p30 核级 +4.25% 看着实时，链级 −2.67%；报告同时给两栏，判定只用链级。负对照 `FEASIBLE_CLAIM_BELOW_PER_STREAM_GATE` 可直接拒绝“核级/聚合够就 feasible”。
3. **conservative 271–300 只能 conditional。** 即使双核 Routed 时序将来通过，conservative 289/300 仍 >270；而且 per-stream 链级不变，1080p30 仍 fails_30。“双核时序通过 → 双核 feasible”是双重错误。

## 2. 输入/边界

4. **`full_grad.dec` 不是 payload。** TB 每捕获字节写一行十进制（`$fwrite(fd,"%0d\n",dbg_byte)`）：40,076 B 捕获 → 180,425 B 文件。几何必须用 `read_words=129600` 与 TB 默认 W/H 证明，不能用 `.dec` 文件大小推断分辨率。以后任何“registry/dec 尺寸对不上”先查 TB 写文件格式。
5. **设计指南的“W/H 均可被 4 整除”对 1440×810 不成立。** H=810 不整除 4，但 W=1440 使每行 360 组、stride 1,800 B、总 291,600 组，packed 连续存放即可，无需 padding。正确约束是 `W%4==0 && W*H%4==0`。不要因此删档或加填充。
6. **full_grad 6,421,414 cycles 的边界已核实**：1080p 全帧、覆盖 RAW 槽写/DDR 读/core/UART 导出（行为级 DDR）。链级模型对 1080p 直接用该锚点；其他几何用 `raw×cpb+426,385`（assumed）；`0` 与 `1,000,000` 作敏感性，不改判定门槛。

## 3. 工程实现

7. **CSV 含 note 必须做引号转义。** 裸 `",".join` 遇 notes 中的逗号会整体错列，且 DictReader 读回后会把 note 尾巴当 layout/数值，报告随之出现“字符串当百分比”。统一用 RFC4180 转义（`"`→`""`，含 `,`/`"`/换行才加引号）；生成器与校验器共用同一 `row_to_csv`，再逐字节比对。
8. **Python `%` 格式不支持 `%,d`/`%%` 混用。** 千分位用 `format(x,",")`；未走 `%` 运算的字面量不要写 `%%`（会原样输出）。报告模板里两类字符串要分开。
9. **不要用 CSM 行做“代表性”抽样。** 网格用 `add()` 去重键（W,H,fps,cores,streams,clock），设计指南 39 行 + 4 个单核单路 1080p fps 档 = 43；测试断言“去掉 4 行后恰为 39”，防止无意改动网格。
10. **推荐由规则生成。** 主推荐=30 fps、链级≥25% 中像素最大（同像素优先单核、单路）；备选=最大像素但 0–25% 的 30 fps 单核行 + 1080p 链级≥25% 的单核最大 fps。不要在正文手写 ID；`check_outputs` 重算前沿极大性与推荐行。
11. **`--journal` 开关。** 生成/测试/渲染/校验脚本只在显式 `--journal` 时追加 `commands.jsonl`，避免综合测试者复跑 `test_calc.py`/`check_outputs.py` 时污染冻结命令日志。
12. **报告由 CSV 确定性渲染**，并写 `logs/report.sha256`；校验器比对哈希并逐格解析 43 行表格。这样“CSV↔报告每个数字一致”是构造保证，而不是人工核对。

## 4. 证据

13. 冻结前最后顺序：`gen_tables.py --journal` → `test_calc.py --journal` → `render_report.py --journal` → `check_outputs.py --journal` → `mk_manifest.py`。`mk_manifest.py` 只读 `commands.jsonl`，不再追加，避免 manifest 自身哈希漂移。
14. 失败记录保留：gen/test/render/check 的首轮 exit 1 原因与修正在 `result-r0.md` §4.1；日志以最后一次 `logs/*.out.txt` 为准（Tee 覆盖，未伪造旧日志）。
15. **预算实况（如实记录）**：本任务实际工具调用约 70 次，超过 `dev-plan.md` §3.7 冻结的 45 次开发预算（主因：CSV 引号/格式、1440×810 打包边界、报告模板反复重渲染与校验重跑）。时间在 75 min 内；范围未扩、未增加 TD/硬件/外部写入。后续若再派同规模任务，应把“CSV 引号 + 报告模板 + 边界预检”前置，或把预算提高到 ~60 次。

## 5. round1 修复的教训

16. **前沿表的 margin 必须与 capacity_basis 同源。** core-only 行填链级 margin 会产生 `16.7967 + meets_25` 这种自相矛盾单元。做法：行内同时保留 `margin_chain_pct`/`margin_core_pct`，`margin_pct`/`gate_25` 由 basis 选择；校验器断言“同源 + 与场景表一致”，不能只查行存在/极大性。
17. **冻结的敏感性档位必须落成机器可读产物。** 只在 `frozen-inputs.json`/`lessons.md` 声明 `0/426385/1,000,000` 不够；必须有 `out/overhead-sensitivity.csv`（43×3）并逐档重算 verdict。tier 依赖必须在摘要/判定/推荐三处披露，否则“feasible”会被读成无条件。
18. **主推荐要么全档稳健，要么写明条件。** 1600×900@30 在主档 36.1774%、保守档 21.0486% → 只能写“主档 feasible / 保守档 conditional”；同时给全档稳健的最大档 1440×810（42.9485%）作为备选。不要用“主档最大”掩盖档位依赖。
19. **每个推荐必须给“所需时钟”。** `f_req = cycles_per_frame × fps × 1.25`（链/核各一）；推荐行都在 187.5 MHz 已验证范围内（172.1100/156.1206、142.4471/126.4577、160.5353/149.8757 MHz），因此不需要超频。把该列写进 scenarios/frontier，报告由 CSV 渲染即可保持一致。
20. **测试里不要对 CSV 字符串做 `*`/比较。** `r["W"]*r["H"]` 在 CSV 行上是字符串重复，`r["W"] == 1600` 永远 False；统一 `int()` 后再比。本轮 check 调试失败即此因。
21. **round1 预算实况**：本轮约 30 次工具调用（在原 45 次冻结预算内），未扩范围、未改门槛、未动 P1/protected。
