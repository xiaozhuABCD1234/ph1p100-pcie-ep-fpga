# 用户补充输入 05（2026-10-18，原样保存）

## 用户原话

> 你不能尝试操作chipwatcher吗

## 主登记说明

- 用户询问：我方能否尝试自动/直接操作 ChipWatcher（而不是让用户手工点击读 9 字）。
- 当前状态：debug bit `2385cded…` 已仅 SRAM 下载成功、板保持上电；P3 开发判定 ChipWatcher 仅 TD GUI 交互、无法自动读回（blocked，TOOL_UNAVAILABLE），已给用户 GUI 清单。
- 交原规划判定是否授权一次有界的 ChipWatcher 自动化尝试（如 TD Tcl/命令行接口、已有 tools/td 脚本、或受控的 GUI 自动化），并给边界/停止条件/回退；若不可行，如实说明并以 GUI 清单为准。
