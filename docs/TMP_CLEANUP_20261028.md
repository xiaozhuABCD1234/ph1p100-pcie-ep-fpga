# fpga 工作区 tmp 清理清单（2026-10-28）

本次只做两件事：**加固 `.gitignore`**、**列出待删清单与命令**。
实际删除留给用户执行，原因见文末「为什么没有直接删」。

## 实测清单

所有数字来自本次 `ls` / `du` / `git` 实测（仓库根 = `fpga/`）。

| # | 类别 | 位置 | 文件数 | 体积 | Git 状态 | 可否重建 |
| --- | --- | --- | ---: | ---: | --- | --- |
| 1 | TD 运行日志 | 根目录 `td_*.log` / `td_*.logw` | 236 | 2.3 MB | 未跟踪、已忽略 | 是，重跑即生成 |
| 2 | TD 崩溃栈转储 | 根目录 `.tmp_<pid>_1` | 9 | 36 KB | 未跟踪、**原先未忽略** | 否，但无价值 |
| 3 | 仿真比对数据 | 根目录 `t11_writer_*.bin` | 3 | 12 KB | 未跟踪、**原先未忽略** | 是，tb `$fopen(...,"wb")` 生成 |
| 4 | TD/bw 运行日志 | `log/` | 116 | 472 KB | 未跟踪、已忽略 | 是 |
| 5 | 过期构建目录 | `ph1p_pcie_ep_top_Runs/*.stale_*` | 3 | 27 MB | 未跟踪、已忽略 | 是，TD 重新布局布线 |

合计约 **30 MB**，全部**不在 Git 索引里**，删掉不影响任何已提交内容。

### 第 2 类：9 个崩溃转储的确切路径

```
.tmp_1089585_1  .tmp_1093324_1  .tmp_637985_1  .tmp_654562_1  .tmp_669339_1
.tmp_696637_1   .tmp_698206_1   .tmp_716855_1  .tmp_719377_1
```

内容是被截断的 gdb 栈帧，形如
`td(_Z11sig_handleriP9siginfo_tPv+0x9e)` → `projmngrWaitRun`（等待运行阶段被打断），
或 `bw(...)` → `TD_BITBANG_IF::write_full`（下载位流阶段被打断）。
它们是 TD 工具收到中断信号时由 `sig_handler` 写在 CWD 的副产物，**不含任何可复现信息**。

### 第 5 类：只有 3 个 stale 目录，当前构建产物不要动

```
ph1p_pcie_ep_top_Runs/syn_1.stale_203706/   27 MB   <- 可删
ph1p_pcie_ep_top_Runs/phy_1.stale_203706/   48 KB   <- 可删
ph1p_pcie_ep_top_Runs/phy_1.stale_203618/   44 KB   <- 可删
ph1p_pcie_ep_top_Runs/{syn_1,phy_1,best_result}/     <- 保留，这是当前结果
```

## 保护区（本次明确不动）

| 路径 | 原因 |
| --- | --- |
| `rtl/ep_side/cam/ui_imx415_reg.v`、`rtl/ep_side/ddr/cam_r10f_writer.v` | 已修改未提交（+73/−41） |
| `docs/FIX_STALL_20261028.md`、`sim/tb/tb_wdt_stall_general.v`、`sim/tb/tb_wdt_tail.v` | 新增未提交 |
| `workspace/ph1p100/**` 下 347 个 `td_*` 日志（全仓已入库共 351 个） | **已入库证据**，非垃圾；`.gitignore` 对已跟踪文件无效，别按模式一刀切 |
| `handoff/**/td_*.log`（8 个） | 已入库，队友复现证据 |
| `ph1p_pcie_ep_top_Runs/{syn_1,phy_1,best_result}` | 当前构建结果 |

## 已执行：.gitignore 加固

在「TD 日志（写在 CWD，跑完即弃）」一节后新增两条规则，堵住第 2、3 类反复污染 `git status` 的漏洞：

```gitignore
# TD 工具崩溃时由 sig_handler 写在 CWD 的栈转储 `.tmp_<pid>_1`：
# 内容只有被截断的 gdb 栈帧，不含可复用信息（见 docs/TMP_CLEANUP_20261028.md）。
.tmp_*

# 仿真 testbench 用 $fopen(...,"wb") 直接写到 CWD 的比对数据，每跑一次即重建。
t11_writer_*.bin
```

验证结果：

- `git status --porcelain` 从 17 项降到 **7 项**，只剩真正的未提交工作。
- `git check-ignore -v` 确认 `.tmp_*`、`t11_writer_*.bin`、`td_*.log` 均命中预期规则。
- `git ls-files | git check-ignore --stdin` 输出为空 → **没有任何已入库文件被新规则误伤**。

## 交给用户的删除命令（按类别，先预览再删）

按 [workspace/ph1p100/AGENTS.md](../workspace/ph1p100/AGENTS.md) 的禁批量删除约束，下面命令由用户手动执行。
每一类都先跑预览行，确认数量对得上再删。

```bash
cd fpga

# 1) TD 运行日志（236 个，2.3 MB）
ls -1 td_*.log td_*.logw | wc -l        # 预览，应为 236
rm -f td_*.log td_*.logw

# 2) TD 崩溃转储（9 个，36 KB）
ls -1 .tmp_* | wc -l                    # 预览，应为 9
rm -f .tmp_1089585_1 .tmp_1093324_1 .tmp_637985_1 .tmp_654562_1 .tmp_669339_1 \
      .tmp_696637_1 .tmp_698206_1 .tmp_716855_1 .tmp_719377_1

# 3) 仿真比对数据（3 个，12 KB）
rm -f t11_writer_1080p_header.bin t11_writer_1080p_tail.bin t11_writer_small_content.bin

# 4) TD/bw 运行日志目录（116 个，472 KB）
ls -1 log/ | wc -l                      # 预览，应为 116
rm -f log/*

# 5) 过期构建目录（3 个，27 MB）—— 只删 stale_*
ls -d ph1p_pcie_ep_top_Runs/*.stale_*   # 预览，应为 3 个目录
rm -rf ph1p_pcie_ep_top_Runs/syn_1.stale_203706 \
       ph1p_pcie_ep_top_Runs/phy_1.stale_203706 \
       ph1p_pcie_ep_top_Runs/phy_1.stale_203618
```

不做第 5 类也完全没问题，它已被 `*_Runs/` 忽略，只是占 27 MB 磁盘。

## 删完后的验收

```bash
cd fpga
git status --short          # 应只剩 7 项：.gitignore + 2 个 RTL + 3 个新文件 + 1 个新文档
du -sh .                    # 应从 750 MB 降到约 720 MB
git ls-files | wc -l        # 应仍为 25637（删的都是未跟踪文件）
```

## 为什么没有直接删

[workspace/ph1p100/AGENTS.md](../workspace/ph1p100/AGENTS.md) 第 12、19、42 行规定：

> 禁止批量删除文件或目录。不得将批量删除包装成循环、脚本或子进程。
> 确需删除时，只能一次删除一个明确路径的文件；需要批量删除则请用户手动处理。

本次待删 367 个路径，属批量操作，因此只出清单与命令，未动磁盘。
（与 [REPO_HYGIENE_20261027.md](REPO_HYGIENE_20261027.md) 的处理方式保持一致。）
