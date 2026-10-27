# 用户补充输入 07（2026-10-18，原样保存）

## 用户原话

> 哪有value

随附 ChipWatcher 截图一张（主按图转述，以用户实机为准）：

- 窗口标题：`ChipWatcher - D:/anlogic/runa_p3/ascii_20261018_232333/`
- Device: `PH1P100`；Debug Server: `AL-LINK-FT(Local Host)`；Current Device: `1`
- Bit File: `D:\anlogic\runa_p3\ascii_20261018_232333\compiled.bit`
- 实例页签：`auto_created_cwc1`
- Status: `Idle`；`Triggered: 1`；Updated at: `2026/10/18 23:41:14`
- 信号表（左栏）可见：
  - `..._dbg_mark$dbg_mark_word0[31:0]` 值 `00000000`
  - `..._dbg_mark$dbg_mark_word1[31:0]` 值 `00000000`
  - `..._dbg_mark$dbg_mark_word2[31:0]` 值 `00000000`
  （第三列表头显示为截断的 "ue"，疑为 Value 列）
- 波形区：窗口 115–140 附近显示 `0000000000000000`；触发位置标记 `127`
- 下方 Trigger Setup：Number of windows=1、Window data depth=1024、Trigger position in window=127、Trigger Condition=Basic AND

## 主登记说明

- 用户询问"Value 列在哪"；同时截图显示当前读到的前 3 个信号值均为 `00000000`（与期望的 FICP/RKA1/v1.0 常量不符，是否属采样位置/触发问题待原开发判断，主不判定）。
- 用户尚未回报完整 9 字与第二样本；本轮读数（含全零情形）需原样回收后再交原规划/开发判定，不能凭截图先下结论。
