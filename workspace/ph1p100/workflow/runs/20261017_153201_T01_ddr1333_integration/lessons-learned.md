# lessons-learned — T01（E1/E2 执行期间可复用结论，2026-10-17）

范围：仅记录本任务 E1/E2 实际踩到/观察到的、对后续（E3、板测候选、其它 run）可复用的条目；不重复 dev-plan/guide 已有规则。

1. **TD 6.2.3 route DRC 新增 TMST-7700（"4 SEVERE timing constraint issue(s)"）**：6.2.3 下在 1333 新 IP 与 1600 旧 IP 对照**两候选均出现**（place 段 1 条 + route 段 2 条），历史 6.2.2 日志计数为 0。
   - 触发：`place`/`route` 后 `Report DRC` 阶段；报文指向 "check_timing report"，冻结脚本未生成该详单。
   - 复用修正：跨工具版本对比 DRC/日志消息**不可直接按消息码对照**；route 清洁度以 STA 数字 + coverage + 端点违例为准；如需详单需另生成 check_timing 报告（本批不做，交规划决策）。
   - 验证入口：`camera_rgb565_ddr1333_20261017_160741\native_route.txt` / `camera_rgb565_ddr1600ctl_20261017_160741\native_route.txt` 中 `TMST-7700` 检索。

2. **同一批、同工具、同脚本下最终报告形状仍可按候选漂移**（66 vs 68 端点组）：1333=66（与 002820 有序同名），1600ctl=68（`mcu_clk→mcu_clk` 组多一次）。
   - 复用规则（已在 2026-10-15 提出、本次再验证）：`check_timing_margin.py` 的 `--expected-endpoint-groups` 必须**逐报告人工复核后显式设定**，禁止按文件现有组数自证完整。

3. **6.2.3 综合的 REG 规模与 6.2.2 显著不同**（同 RTL：002820=30825 → 1600ctl@6.2.3=24260），属工具版本效应；跨版本资源对比必须用同版本对照行（E2b 式控制）才可归因。

4. **`report_route_status -drc -file ./capture_route_drc.rpt` 在 6.2.2/6.2.3 均不落盘**（002820 亦无）——脚本既有 quirk，勿当回归，勿引用该文件。

5. **runner 进程树超时杀**：新 runner 使用 `CREATE_NEW_PROCESS_GROUP` + `taskkill /F /T /PID`（本轮未触发超时，路径未实测；触发时以 `timed_out:true` + `timeout_kill` 落档）。

6. **证据文件双名共存**（正名 dev-plan + 别名派发注记，同内容互登记）可消除"规划/派发命名漂移"导致的找不到证据问题；代价是两份同内容文件，需在 notes 显式说明。

7. **文档引用文件字节数须取落盘实测（`read_bytes()` / `Get-Item .Length`）**：`Path.write_text` 在 Windows 将 `\n` 落为 `\r\n`（每行 +1 B），用写入前字符串长度报的"字节数"会偏小（本次 79,948 → 落盘 81,640 B），而文件 SHA 无误；两者不一致最易被判为文书缺陷（E2 的 D1）。验证入口：同一文件同时 `len(read_bytes())` 与 SHA，写文档时两者同源。

8. **跨 run 引用"滚动文件"（tasks.json/main-log/decision-register）必须登记观测时点 SHA**：这类文件被并行线持续更新（本次 tasks.json 从规划观测 `91cdfe22…` 漂移到 E2 观测 `832a4b85…`，17:06:44）；引用时写"观测时点 SHA+时间"，编辑 tasks.json 时改前重新观测、以任务专属锚点唯一匹配编辑，改后 JSON 解析自检。验证入口：编辑前后 `Get-FileHash workflow/tasks.json` + 唯一匹配 grep。
