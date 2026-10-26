# 用户补充输入 08（2026-10-18，原样保存）

## 用户原话

> 看到3个是因为框不够大，实际情况如图，但是还是不尽人意都死0，是否有什么我没注意的，操作是否有误

随附 ChipWatcher 截图（主按图转述，以用户实机为准）：

- 标题：`ChipWatcher - D:/anlogic/runa_p3/ascii_20261018_232333/`
- Device `PH1P100`；Debug Server `AL-LINK-FT(Local Host)`；Current Device `1`；Bit File `D:\anlogic\runa_p3\ascii_20261018_232333\compiled.bit`
- 实例 `auto_created_cwc1`；Status `Idle`；`Triggered: 1`；Updated at `2026/10/18 23:43:39`
- 左表 9 行齐全：`dbg_mark$dbg_mark_word0[31:0]` … `word8[31:0]`，Value 列均为 `..00000000`（应为 0x00000000）
- 波形区 115–140 全为 `0000000000000000`，触发标记 127
- Trigger Setup：Number of windows=1、Window data depth=1024、Trigger position in window=127、Trigger Condition=Basic AND

## 主登记说明

- 用户操作看起来符合清单（9 个信号已加、已触发 1 次）；读到的 9 个字全为 0，与期望常量（FICP/RKA1/v1.0）不符。
- 用户询问是否操作有误/有遗漏。
- 需要原开发判断：采样时钟/触发窗口/探针映射/CTRL 使能/位流运行状态等哪一环导致全零；并给出下一步（是否需要用户在 GUI 改触发设置或重采第二样本）。主不判定技术原因。
