# 用户补充输入 04（2026-10-18，原样保存）

## 用户原话

> 我按A做了，以及后续我会给你开放相关权限

随附一张 PowerShell 截图。主按图转述（以用户实机为准）：

```text
[codex/raw10-rka1 8e1ef05] T11.runB-debug-rtl: dbg_bank 9-word read-only mirror + debug-only CTRL default enable + debug top/entry + new TB (offline, no bitstream)
 7 files changed, 619 insertions(+), 6 deletions(-)
 create mode 100644 rtl/ep_side/debug/ph1p_pcie_ep_top_dbg.v
 create mode 100644 sim/tb/tb_ep_bar_win_debug.v
 create mode 100644 tools/pcie_integration/td/00_all_debug.tcl
PS C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道\upstream\ph1p100-pcie-ep-fpga> git log -1 --format="%H %s"
```

- 可见短 SHA：`8e1ef05`（分支 codex/raw10-rka1）；完整 40 位 SHA 与 `git status --porcelain` 的空输出在截图中未显示（`git log -1` 一行停在命令处）。提交说明与预期一致。
- 用户附加信息：后续会给本环境开放相关权限（shell git 权限）。

## 主登记说明

- 选项 A 已执行：本地 commit 成功（7 files changed, 619 insertions(+), 6 deletions(-)；3 个 create mode 为新文件）。
- 交原规划：核对 commit 真实性/完整 SHA；按其先前口径回填 manifest（commit_sha/commit_status）与 dev-notes；随后 ready_for_test → 综合测试者。
- 仍不推送；板子不受影响。
