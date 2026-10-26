# 回来点两下：NOT_READY，当前不可执行
这是本轮唯一上板清单入口。现状：新生产bit=不存在，新CWC=不存在，最终DB/STA=未运行，独立综合验收=未开始。不能下载partial源码，不能沿用旧bit作为本轮成果。原board/两份模板只作历史输入，本文件给出当前就绪状态。

## 开放条件（当前均未满足）
原B01同候选完整G1/G2由一个独立综合tester验收；CRC/所有权/坏帧恢复与算法门槛通过；同最终DB STA/CDC/资源合格；CWC经setup_debugger产生且完整BID物理映射校验0失败、bit配对逐字节一致。开发给唯一新bit/CWC/manifest绝对路径与SHA，用户在场并确认单A/板窗口。本轮没有这些新文件。

## 条件满足后回来做两次点击
1. 打开该唯一新CWC，在其对应新bit已按清单仅SRAM下载后，第一次Instant Trigger；导出DDR同域结果、camera源域原始样本与截图，记录时间/操作者。
2. 至少20秒后第二次Instant Trigger；同样导出。跨域/实例独立解读，不拼成原子快照。

预期至少两个不同seq完整帧：cl_words=648192、四ok=1、err=0、32bit pass_count推进，seq/base/len与相干结果对应。还要真实几何/ROI/Bayer相位有效依据、内部一次abort或自然坏帧确实拒发布并随后good恢复；缺任一项仍未通过。内部abort不是传感器电气CRC故障实测；两样本不是10分钟长稳。
身份/配对/校准异常或错误码立即保存原文并停止，不反复点击补出PASS。GUI是唯一已证读回通道，CLI读回关闭。不接PCIe/RK、不改线、不写Flash、不推送。

## 保留的旧回退配对（不是本轮新候选）
bit：[compiled.bit](<C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/workflow/runs/20261018-1631_runA_fpga_side_readchannel/debug-fix3/prj/ph1p_pcie_integration_Runs/phy_1/cw/compiled.bit>)，SHA bfafdf97ff78d6f6d2646ffc706542a0bbbb7e11869043ba754cf68a270813d0。
CWC：[compiled.cwc](<C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/workflow/runs/20261018-1631_runA_fpga_side_readchannel/debug-fix3/prj/ph1p_pcie_integration_Runs/phy_1/cw/compiled.cwc>)，SHA 8d2998b96ef1763c14a1302118235a687488297ce496692b1f6cd95d76981026。
基线：[candidate-manifest.json](<C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/workflow/runs/20261018-1631_runA_fpga_side_readchannel/debug-fix3/candidate-manifest.json>)。收尾只重核文件身份，没有重新下载/观察板状态。

## 2026-10-19 B01 r0通过后的T02即时板验
旧禁止下载模板仅为历史。当前已经离线独立验收合格，T02仍待现场事实/板证；使用board/t02/two-capture-checklist.md与t02-board-plan.md，不重复SRAM许可，不自动执行回退。
