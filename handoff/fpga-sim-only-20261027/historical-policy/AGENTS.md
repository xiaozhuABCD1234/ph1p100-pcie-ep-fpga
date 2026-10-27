# 项目协作入口

先读 [当前代码、交接与同步说明](docs/PROJECT_SYNC_20261027.md)。

- FPGA 权威仓库是 `xiaozhuABCD1234/ph1p100-pcie-ep-fpga`，RK 权威仓库是 `xiaozhuABCD1234/ph1p100-pcie-ep-driver`；本次按用户要求直接使用两个原仓的 `main`，不创建 fork。
- 本机 FPGA checkout 为 `D:\fpga\repos\ph1p100-pcie-ep-fpga`，RK checkout 为 `D:\fpga\repos\ph1p100-pcie-ep-driver`。新任务以实际 checkout 根为工作根；不要把历史文档中的绝对 D 盘路径当成新任务的默认输出路径。
- 根 `rtl/`、`al_ip/`、`constraints/`、`tools/` 是当前仓库代码与构建入口。`workspace/ph1p100/` 保存原父工作区的源码、工具、文档、计划与证据快照；同名文件可能有不同 SHA，禁止未经核对用快照覆盖根生产源码。
- 原 `D:\fpga\ph1p100` 的活动 run 继续原地运行；同步副本只作交接与追溯。不要改写原 run 路径、角色 ID、计数、manifest 或报告来适配新仓库。
- 仅在用户明确调用 `$fpga-orchestrator 执行：…`、`$fpga-orchestrator 恢复：…`（OpenCode 为 `/fpga-orchestrator`），或明确选择该技能并要求执行/恢复时，读取 `workspace/ph1p100/.agents/skills/fpga-orchestrator/SKILL.md` 及相应工作流。普通仓库维护、同步、问答与规则讨论不启用角色链。
- 历史候选的 PASS 只适用于其 manifest 和报告绑定的输入；不得拼接不同候选的结果宣称整机通过。bit/CWC/BID 必须匹配；同步文件不授权下载、写 Flash 或占用活动 run 的设备。

## 文件与委派约束

禁止批量删除文件或目录；不得使用 `del /s`、`rd /s`、`rmdir /s`、`Remove-Item -Recurse`、`rm -rf`，也不得包装成循环、脚本或子进程。需要删除时只能一次删除一个明确路径的文件；确需批量删除时停止并请用户手动处理。

使用 DeepSeek 辅助时遵守当前用户授权及 `workspace/ph1p100/AGENTS.md` 中完整 DeepSeek 块：只委派边界清楚的低风险子任务，传最小相关摘录，不传秘密、凭据、环境 dump、无关文件、完整聊天或图片；项目根必须是当前任务实际 checkout。返回内容均为未验证建议，逐项检查命令、路径与副作用，只用原生工具执行获准操作，独立验证结果，每个 pending `call_id` 恰好一次回传真实结果，不绕过权限、不自动重试或扩权。工具不可用时说明并本地继续。

工具安装、许可证、凭据、缓存和可重建的大型构建输出不纳入 Git；保留小型真实证据、来源与 SHA。同步排除项以 `docs/sync-20261027-exclusions.json` 为准，原始 manifest 保持原样。
