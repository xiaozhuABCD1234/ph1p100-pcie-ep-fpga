# 当前用户原话

把这几项按工作流开始完成

## 紧邻上下文：上一条用户问句（原话）

当前还能并行做什么

## 用户“这几项”所指：上一条助手建议（原文摘录，供规划理解，不替代规划）

| 优先级 | 可并行任务 | 明确交付 |
|---|---|---|
| **1．现在最值得开** | **核对 FPGA 实际发送字节，并做回放验证** | 明确帧头、相机身份、session、有效长度、DMA对齐长度、尾零和CRC；生成模拟PCIe接收文件，复用现有解码工具验证，附预期结果。 |
| **2．有余力再开** | **双路自由运行输入的隔离仿真** | 用不能被反压的CSI输入，验证两路同时到帧、处理忙时整帧丢弃、身份保持；交付独立TB和结果，后续接入板级主线。 |
| **3．后排** | **真实图像压缩收益基准** | 整理来源明确、格式正确的RAW10，统计压缩率、回退比例及解码一致性，为演示和验收准备数据。 |

第1项已有一个具体需要核对的地方：当前协议定义 A1U1 为“44B头＋zlib”，但压缩槽只存 zlib，传输长度按 stream_len 对齐。需要明确实际PCIe路径由谁补头、如何传递元数据，避免 FPGA 发出的内容与队友解析入口不一致。

第2项也有明确依据：当前集成会拉低未获调度通道的 ready，真实自由运行双相机还需要每通道暂存。

板级顶层与真实DDR/PCIe接入继续由现有集成线承接；新增任务独立做字节格式和回放验证，不占TD、板卡，也不改正在修时序的目录。

## 本会话此前用户范围（原话）

现在A、B链路已经通了，再排除现在codex和opencode在做的，还是以推进度优先，稳定性和次优化滞后，只关注于fpga侧，那么加上这些限制，给我一条清晰的后续要干的路径（现在在干的也标注上）

## 机械登记的实际路径

- PROJECT_ROOT: D:\fpga\repos\ph1p100-pcie-ep-fpga
- 权威FPGA checkout: D:\fpga\repos\ph1p100-pcie-ep-fpga
- 权威RK checkout（本轮未授权修改RK/联系队友）: D:\fpga\repos\ph1p100-pcie-ep-driver
- 原活动编排区（只读来源，不搬动、不覆盖）: D:\fpga\ph1p100
- 原活动集成run: D:\fpga\ph1p100\workflow\runs\20261026-2138_fpga-integrated-delivery
- H-only/A+H活动run: D:\fpga\ph1p100\workflow\runs\20261027-055621_fpga-honly-td-and-ah
- 已结束H-only原型run: D:\fpga\ph1p100\workflow\runs\20261026-231711_fpga-a-plus-h-prototype
- 原双路离线run: D:\fpga\ph1p100\workflow\runs\20261025-180900_fpga-dual-offline-closure
- 旧审查run: D:\fpga\ph1p100\workflow\runs\20261026-144617_fpga-chain-detail-review
- 既有真实样例: D:\fpga\repos\ph1p100-pcie-ep-fpga\handoff\rk-a1u1-b18-20261026
- 当前协议路径: D:\fpga\ph1p100\workflow\runs\20261026-2138_fpga-integrated-delivery\INT.P4-protocol.md
- 当前短步骤路径: D:\fpga\ph1p100\workflow\runs\20261026-2138_fpga-integrated-delivery\INT.P4-shortest-steps.md

## 权限与保留约束

用户本轮要求按项目工作流开始完成上列事项。没有新增硬件/TD/JTAG/COM/下载/Flash/外部消息授权。不修改活动run/已有冻结输入，不抢其TD/板卡，不批量删除。新任务在实际权威FPGA checkout独立目录开展；是否及如何发布仍按根AGENTS与当前授权判断，不为完成本轮擅自扩大范围。缺真实输入必须如实记录，不能把合成图冒充实拍。
