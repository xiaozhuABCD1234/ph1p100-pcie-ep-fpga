# 权威仓库与同步入口（2026-10-27）

用户指定且要求直接在原仓库 main 推进，不创建 fork：

| 责任 | 远端 | 本地完整 checkout |
|---|---|---|
| FPGA | https://github.com/xiaozhuABCD1234/ph1p100-pcie-ep-fpga | D:\fpga\repos\ph1p100-pcie-ep-fpga |
| RK 驱动、接收和解码 | https://github.com/xiaozhuABCD1234/ph1p100-pcie-ep-driver | D:\fpga\repos\ph1p100-pcie-ep-driver |

`D:\fpga\ph1p100` 仍是当前活动 run 的编排工作区；其 Git 远端是早期项目历史，不能据此认定为队友主仓库。不会因本次同步终止、迁移或重置活动 run。

## FPGA 发布映射

- 现有 FPGA 子仓已提交分支与未提交源码：同步到 FPGA 主仓原路径，保留原有 Git 历史。
- 本工作区源码、工具、文档、技能、任务记录和候选：按原相对布局保存到 FPGA 仓库 `workspace/ph1p100/`，避免覆盖不同实现。
- b18 真帧与 RK 解码交接：两仓均提供 `handoff/rk-a1u1-b18-20261026/README.md`。
- b18/b20 已生成位流：FPGA 仓库 `artifacts/`；各自产物、SHA和板级状态分别记录，不因同步取得新验收。
- 排除工具安装、许可证、缓存、数据库、波形、重复生成大向量；索引记录省略原因及本地来源。manifest原件不改写。

## RK 发布映射

从已核验交付中的11项 RKA1/R10F 改动同步到 RK 主仓原路径，附协议镜像、严格检查工具、真实 A1U1 文件样例及参考脚本。队友现有成功程序继续保留；新 A1U1 兼容和实机连续链路以队友实际结果验收。

后续拉取、协作和发布明确使用以上两仓。运行旧候选时读取其冻结来源；新任务使用当前 checkout 的路径，不照抄历史记录中的绝对路径。
