# lessons-learned.md — T11.runB-debug-rtl

只记可复用根因/触发/修正/验证入口。

## L1 生产文件表不可变时的"构建变体"实现模式
- 根因/触发：`00_all.tcl` 文件表受保护（逐字节不变），但 debug 构建需要额外的顶层参数覆盖与新模块；任何被生产文件引用的新模块都会让生产构建缺模块。
- 修正（可复用模式）：① 只读镜像/诊断字全部**内联**在既有文件（ep_bar_win.v，仅插入）；② 构建期差异用**独立顶层包装 + 参数沿层透传**实现，包装只被新 stage tcl 编译；③ 新 tcl 仅用 `add_files` + `top_module` 两个既有用法（不依赖 `defparam`、宏定义、未文档化的 run 参数）。
- 验证入口：包装端口机械生成脚本（`debug-rtl/gen_dbg_top.ps1`，43/43 回读一致）+ TB 双实例对照（param=1 / 默认 0）+ 既有 8 TB 回归全 PASS。

## L2 Windows/PowerShell 与工具链坑
- 触发：PS 5.1 执行**无 BOM 的 UTF-8 .ps1** 时按 ANSI(GBK) 解析 → 脚本内中文路径损坏（`ReadAllLines` DirectoryNotFound）。
- 修正：子脚本一律**纯 ASCII**（路径经参数传入）或写 BOM；`[System.IO.File]::*` 相对路径按**进程 CWD** 而非 PS `Set-Location` 解析 → 脚本内一律绝对路径（`Join-Path $args[0] …`）。
- 验证入口：脚本首行打印解析后的实际路径；生成物回读校验。

## L3 本环境 git commit 被权限拒绝（PERMISSION_MISSING）
- 触发：子会话 shell 中 `git commit` 两次 `permission.rejected`；`git add`/只读 git 命令正常；未尝试绕过（合规）。
- 修正/规避：候选先 **git add 全量暂存**（index 即冻结候选集）+ 用 `git diff --cached` 导出 candidate.diff；把"一次 `git commit`"留作恢复入口交原规划/用户（无需再 add）。
- 验证入口：`git status --porcelain` 全为 `A/M` 暂存项即视为冻结完整；commit 后以 `git rev-parse HEAD` 更新 manifest。

## L4 预算（30 次工具调用）对"读多写少"包的适配
- 触发：本包 11 个必读输入 + 仓库/工具链只读调查（run_td/00_all/.al/TD 安装）在写第一行代码前即用 ≈34 次 → 超出冻结 ≤30。
- 修正建议：规划在派发同类离线 RTL 包时，将"必读输入数 + 调查项"计入并显式给出读取预算（或把调查项列入 input_paths 摘要）；开发侧把预算检查点前置（每 10 次自检），调查阶段先合并批读、后深挖。
- 验证入口：manifest `notes` 记录实际调用量；lessons 记录偏差原因。

## L5 判据口径：vlog Warnings 随文件表变化
- 现象：既有 TB 的 vlog 汇总 Warnings 数会随编译文件表变化（本次 1 条 `vlog-2600` @ pcie_ep_engine.v L125，属既有代码、非本包改动区域）。
- 修正：判定只取 `Errors: 0` + `ALL PASS`；Warnings 逐条核对是否与本次改动相关并写进证据，不追零、也不忽略。
