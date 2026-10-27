# 用户新输入（原样保存）

> 有这么个问题处理下

（用户附截图：Title=`Warning`，正文=`please ensure that there is only one bit file in the directory: D:\anlogic\runa_runD\t02_ascii_20261019_234035`，按钮=`OK`）

## 主机械登记（非用户原话）

- 收到时间：261019 2344（上海）。
- 截图文字：ChipWatcher/TD 警告——目录中只能有一个 bit 文件；当前 ASCII 目录 `D:\anlogic\runa_runD\t02_ascii_20261019_234035` 存在多个 `.bit`。
- 处理原则：保留与 CWC 配对的 bit（SHA `b68c6e18…`），其余 `.bit` 移到子目录（不删除）；让目录根部只剩一个 `.bit`。
- 硬边界不变：仅 SRAM、不写 Flash、不推送、不接 PCIe/RK；禁止 GUI 自动化；禁止批量删除；不杀他人进程。
