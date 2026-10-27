# 仓库体积与可重建大文件清理（2026-10-27）

本仓当前 23526 个跟踪文件、约 444 MB，其中 371 MB 在 `workspace/ph1p100/workflow/runs/`。
按 [AGENTS.md 第 12 节](../AGENTS.md)「工具安装、许可证、凭据、缓存和可重建的大型构建输出不纳入 Git；
保留小型真实证据、来源与 SHA」，下面这些**可重建**产物不应继续占索引。

## 统计（`git ls-files` 实测）

| 类别 | 文件数 | 体积 | 是否可重建 | 建议 |
| --- | ---: | ---: | --- | --- |
| `workflow/runs/**/trace.txt`（仿真 trace） | 181 | 90.7 MB | 是，重跑 iverilog 台即可 | 移出索引 |
| `workflow/runs/**/*_routed_netlist.v`（布线后网表） | 4 | 14.1 MB | 是，TD 重新布线 | 移出索引 |
| `workflow/runs/**/board/captures*/**.bin`（板上抓包） | 34 | 12.7 MB | 是，重新抓即可 | 移出索引 |
| `docs/sync-20261027-manifest.json` 等同步清单 | 3 | 16.3 MB | 否（是来源证据） | **保留**：AGENTS 要求「原始 manifest 保持原样」 |
| `artifacts/*/a1_board.bit` | 2 | 10.4 MB | 是，但属候选证据 | 待定：与 CWC/BID 成对才有意义，删前请确认 |
| `handoff/**.a1u1`、`**.dma` | 21 | 13.0 MB | 部分 | **保留**：队友复现用的真实样例，并由 `SHA256SUMS` 绑定 |

合计可移出索引的**纯可重建**产物：**219 个文件、117.5 MB**（`workflow/runs/` 下三类）。

## 为什么本次没有直接执行

[AGENTS.md](../AGENTS.md) 明文禁止批量删除，包括包装成循环/脚本/子进程；一次只允许删除一个明确路径的文件，
需要批量时停手交用户手动处理。这个清理动 219 个路径，属批量操作，因此本文件只给出清单与命令，未改索引。

## 交给用户的执行方式（任选其一）

逐个路径（严格按 AGENTS）：

```bash
cd <本仓>
git ls-files 'workspace/ph1p100/workflow/runs/**/trace.txt' \
             'workspace/ph1p100/workflow/runs/**/*_routed_netlist.v' \
             'workspace/ph1p100/workflow/runs/**/board/captures*/**/*.bin' \
  | while read -r p; do git rm --cached -- "$p"; done
git commit -m "chore(repo): 可重建的仿真 trace / 布线网表 / 板上抓包移出索引"
```

只想先看会动哪些文件：把上面的 `git rm --cached` 换成 `echo`。

删完后再确认：

```bash
git status --short | wc -l            # 应约等于 219
git ls-files | wc -l                  # 应约 23307
git count-objects -vH                 # 观察 .git 体积
```

## .gitignore 已同步加固

`.gitignore` 已加入同样的三类模式（见「可重建的工作流产物」一节），避免以后重新 `git add` 回来；
它们只影响未跟踪文件，不影响已入库路径 —— 已入库的仍要按上面的命令移出。
