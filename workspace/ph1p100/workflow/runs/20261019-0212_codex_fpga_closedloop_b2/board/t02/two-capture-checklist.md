# 当前候选上板两次采样清单

这是通过B01独立r0后的入口，替代旧“新bit不存在”模板。T02板测尚未执行，不能先填PASS。

1. 先回答当前现场事实问题。仅在责任开发报告本次SRAM下载成功后，打开[唯一current.cwc](C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/workflow/runs/20261019-0212_codex_fpga_closedloop_b2/recovery01/B01/timing-continuation01/remaining-attempts01/candidate/current.cwc)。这是最终699项manifest的候选，SHA=b28e3d4ee476731b118da0b12c3bad8dcca1dadfbd9b7ae4dc418c4d225a74ce；不要另点GUI下载、换线或改传感器配置。
2. 第1采样组的第一次：在ChipWatcher中对auto_created_cwc1（camera）及auto_created_cwc2（DDR）分别Instant Trigger，保存各自完整32位原始数值、实例名和时间。若软件有导出功能保存原始文件，否则截图须能读完下列字段。至少20秒后以相同步骤保存第二次，两个域分别记录，不宣称同时。
3. camera保留source_good/bad/crc/header/geometry/injected，algo_identity、三路complete/CRC和overflow/rejected；DDR保留全部cl_*（15项）。可以保存整个实例而不用手抄。看到cl_identity应为434c0101、algo_identity应为414c0101；完整记录words=648192、len=2592768、seq/pass/recovery/flags/fault，判定由责任角色完成。
4. 立即发回这两次原文或清晰截图及“操作者、采样时间、单A接线/供电是否有变化”。身份不符、校准异常、非零fault/error、软件失败时保存原样并停下；不要靠反复点击、重下或断电消除证据。最多额外两组须由规划/责任角色给出明确缺项和触发目标。
5. 本次检查包含一次内部abort及随后good恢复，source_injected=1不代表物理CSI CRC故障；几何/ROI/物理Bayer相位仍需有效依据。这一组两次采样可能只完成部分门槛，届时如实记录。无Flash、PCIe/RK或推送操作。

已合格bit：[current.bit](C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/workflow/runs/20261019-0212_codex_fpga_closedloop_b2/recovery01/B01/timing-continuation01/remaining-attempts01/candidate/current.bit)，SHA=b68c6e183e97eb0d465db77078f5049feca3a947fac51f99633621dd99b3f9bf。
准确恢复入口：C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/workflow/runs/20261019-0212_codex_fpga_closedloop_b2/t02-board-plan.md，以及T02责任角色返回的board/t02/development-result.json（尚未生成）。旧回退pair见[board-entry](C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/workflow/runs/20261019-0212_codex_fpga_closedloop_b2/recovery01/B01/timing-continuation01/remaining-attempts01/board-entry.md)，不自动回退。
\n组数口径：这一组=T1/T2两次、每次分别camera/DHI；最多针对明确缺项再补2组，总共3组，不把每个域/每次点击单独算组。\n