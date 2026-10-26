# lessons — T11.runC-checker-integrate（fpga-dev，blocked 轮）

> 只记可复用根因/触发/检出/处置，不写过程流水。

## L1 并行 run 共享工作树：冻结描述失效 → INPUT_CONFLICT（非实现问题）

- **根因**：两个 run（本 run 20261019-0207 OpenCode；并行 20261019-0212 Codex）对同一 git 工作树、同一目标（DDR 读回校验集成）并发写入，且后者在本 run 规划冻结**之后**才落盘改动（02:23 起），使 dispatch/input-index 的"继承=4 路径+46/−5"与实况（7 改动+6 新增、持续变化）不符。
- **触发条件**：用户同一任务在两个宿主并行启动；两个 run 的 write_scope 均含 `upstream/ph1p100-pcie-ep-fpga` 同批文件；无独占锁/无时隙约定。
- **检出（开工首步，3 条命令级检查）**：
  1. `git status --porcelain` + `git diff --stat` 与 dispatch 冻结的"继承路径数/行数"逐项比对；
  2. 全部修改/新增文件的 mtime 与规划时间线比对（mtime 晚于规划→外来改动）；
  3. 对可疑改动在 `workflow/runs/*/scripts`、`*/dev-result*`、`main-log.md` 内检索特征串（如 `CLOSEDLOOP_EN`）定位所有者 run。
- **处置**：外来**在本途/未完成**改动 → 不合并、不覆盖、不擅自另建 worktree/分支规避；按 `INPUT_CONFLICT` blocked，把去重/时隙/隔离决策交原规划。冻结前可先算 `status_hash`/`diff_hash`（`git status --porcelain=v1 | git hash-object --stdin` 等）作为快照锚点。
- **预防（供规划）**：同一工作树的并行 run 应事先冻结"独占写树或只读基线快照"，并在 dispatch 记录 base 快照哈希（status/diff hash），开发开箱即比对；发现不一致即 blocked，成本约 10 分钟，远低于误合并风险。
