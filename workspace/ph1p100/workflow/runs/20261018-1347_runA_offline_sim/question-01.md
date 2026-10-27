# question-01.md — 需用户回来决策的事项（不阻塞本轮 KIT/P1）

日期：2026-10-18。背景：`T11.runA-board-selfcheck` 已按 blocked 接受——**下载链路与器件 ID 已证**（BW/JTAG，SRAM，当前 bit `e81d353b…2b9a`），但**用户寄存器读通道在本 bit/本板不存在**（UART 架构不可用：EP top 将 uart rx 固定 1，COM8 实测 0 字节；无 PCIe 主机；无 CWC 调试核；BW JTAG 寄存器读语义未证实）。因此 `T11.runA-board-capture-readback` 无法机读执行，已置 awaiting_conditions。用户不在场期间，KIT（工具包）与 P1（离线 RTL/TB）继续推进，不需要等待回答。

- **2026-10-18 更新（user-input-03）**：用户已回到现场并答复：**PCIe 通道不验证（未接）**、验证**严格限制在 FPGA 侧**。可行手段、代价与推荐顺序见 `next-round-proposal.md`；待拍板=**是否授权重建“调试诊断位流”并临时替换板上 SRAM 位流（换 bit、可回退 `e81d353b…`、不写 Flash）**；**相机是否已接（单 A）**由用户现场确认。

## 请回来后就以下问题给指令（可只答复选择）

1. **寄存器读通道选择（user-input-03 后更新）**：
   - (a) ~~用户在场时接 PCIe 主机（RK 或 PC）读 BAR0~~ → **用户已排除（PCIe 未接、不验证）**；
   - (b) 授权构建带 **CWC/调试核**的新候选 bit（bit 更替，需重新冻结候选与 G1/G2）；
   - (c) 协助确认 BW `JTAG_REG_ACCESS` / `JTAG_AXIS_APB_ACCESS` 的**只读**语义（本项目 KIT 会先做文档级初核；若成立，原规划再派一次有界只读补充）；
   - (d) 授权 **bring-up bit**（rdx 引出/回环，需改线；agent 不做物理改线）。
2. **相机是否已接（单 A）**？供电/线序现状如何？（读通道缺失，无法机读判断，只能现场确认。）
3. 是否接受本轮板级验证**停在“SRAM 下载 + 器件 ID”**，其余（身份寄存器、采集统计、100 帧/短稳、读回）留到用户在场的下一轮？
4. 若选 (b)/(d)：确认知悉 **bit 更替/接线变更**与重新冻结流程；Flash 仍默认不写。

说明：无需现在回答；用户回来后按 `/fpga-orchestrator 执行：<新需求>`（或恢复本 run）启动上板轮，本文件作为输入。
