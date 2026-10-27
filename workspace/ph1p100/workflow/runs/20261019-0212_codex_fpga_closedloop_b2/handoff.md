# 当前交接：B01 r0通过，T02板验入口已派发

更新2026-10-19T20:47:16.671006+08:00。本段是当前状态，下面旧收尾保留为历史，不再代表当前B01结果。
两正式包T06.codex-ddr-readback-int/T09.codex-production-int首次r0 integrated PASS，实际修复0，G0/G1/G2 pass；同699项manifest c7a40897166467f2beafb096701dba9cf836e1007d77ae03d90009d06f80d757。生产6/6，禁止第7次。最终setup+0.100/hold+0.020ns、STNS/HTNS0，全部适用组及CWC/资源通过。独立报告和复用账见test-reports/下，B01全部开发/测试活动已停止。
本轮正式包完成2/4（仅本包离线范围），T02 G3 not_run等待当前现场事实和真实GUI样本；父T06/T11 active，G4后放。T08原离线开发2次编译历史保留、仍queued恢复授权内，未综合r0/修复；不代表真实同步完成。
准确下一入口=dispatch-t02-board-entry.json与t02-board-plan.md；先无硬件preflight并原样转user-summary-t02-entry.md，事实满足才一次SRAM；成功后两组>=20s，最多3组针对性样本。不能将B01 PASS外推T02 PASS。
当前用户操作清单=board/t02/two-capture-checklist.md；唯一候选/回退=已冻结remaining-attempts01/board-entry.md。当前问题：单A上电/JTAG独占/操作者当前事实未收，几何/物理相位/内部坏帧恢复仍待板证。停止点与权限不变，不Flash/PCIe-RK/推送/批量删除。

---
# 以下是此前阶段历史

# 交接：20261019-0212_codex_fpga_closedloop_b2
状态blocked，未完成原目标；本轮已停止派发。依据request原文、dev-return-b01.json、dev-return-b02a.json、两批partial manifest与各development-report。完整状态/G层见final-summary.md；当前可读状态=planner-state.json；最终问题账=problem-ledger-final.json（原problem-ledger.json属于T08冻结输入，不改）。

## 接手输入和角色
项目根=C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道
生产检出=C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/upstream/ph1p100-pcie-ep-fpga
当前run=C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/workflow/runs/20261019-0212_codex_fpga_closedloop_b2
实际宿主Codex；不续旧OpenCode session。
原规划/root/fpga_planner_b2；B01原开发/root/fpga_dev_closedloop_b01；T08原开发/root/fpga_dev_sync_offline；综合tester未创建。
B01 manifest=candidate/manifest.json（236项，2B328FC0…FEABE）；T08 manifest=sync-offline/manifest.json（26项，94FF1150…DF06A）。两者ready_for_test=false，bit/CWC/final_database不存在。closeout-freeze-audit记录全量无漂移。

## 每包恢复边界
- T06与T09同B01继续同一候选。联合TB两次编译已到限。开发报告建议仅修声明/使用顺序，但未执行；任何恢复需新增明确有限尝试，仍不得声称DUT通过。随后完整联合G1、受影响回归、算法缺项、共享生产G2/CDC/资源/CWC、统一manifest都要完成。
- T08同task继续原离线范围。第二次编译已发现顶层两个非法位置连接；开发给出named .src_busy()技术建议，未经实施/验证。额外尝试只允许用户明确给有限值，成功后仍须原TB/负对照/G2/CDC资源，不得修改B01冻结输入。
- T02板包不派：没有本轮合格bit/CWC，真实GUI窗口也未收。只保留board-checklist-final.md的NOT_READY清单，不能用旧候选替新候选验收。
- 原T09模块级done保留历史；父T11不置done。4个正式包计数不变，补充机会/实际修复/命令尝试分账。

## 可复制的精确恢复指令（仅示例，尚未授权执行）
$fpga-orchestrator 恢复：C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道\workflow\runs\20261019-0212_codex_fpga_closedloop_b2；本轮目标：完成原T06/T09生产闭环离线验收及T08同步离线原型；本轮新增有限授权：两个已失败编译操作各追加1次纠正尝试，累计为第3次，不清零原计数；成功后按原范围完成G1/G2与独立综合验收，仍仅SRAM、不写Flash、不推送、不接PCIe/RK。

用户可只恢复其中一个；不明确次数时规划先明确有限值，不把“看看状态”当追加尝试。下一次失败即停止；未来新命令仍遵守原首次+一次有证据重试。这里不授予第四次编译或扩大任务/角色。新增用户输入由主原样保存，原规划读后更新dispatch，续真实原开发；无任何自动恢复。

## 上板与回退
当前唯一板操作入口board-checklist-final.md；目前不可执行。旧已验证GUI回退配对：
- bit=C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/workflow/runs/20261018-1631_runA_fpga_side_readchannel/debug-fix3/prj/ph1p_pcie_integration_Runs/phy_1/cw/compiled.bit，SHA bfafdf97ff78d6f6d2646ffc706542a0bbbb7e11869043ba754cf68a270813d0。
- CWC=同cw/compiled.cwc，SHA 8d2998b96ef1763c14a1302118235a687488297ce496692b1f6cd95d76981026。
- 基线manifest=C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/workflow/runs/20261018-1631_runA_fpga_side_readchannel/debug-fix3/candidate-manifest.json。
这些只恢复基线读通道，不证明本轮RAW→DDR闭环。当前板是否仍通电/持有旧SRAM未重新观察；本轮无下载。未来只按明确现场窗口执行SRAM，禁止Flash。发生校准问题由用户按既有SOP，不能自动电源循环。

## 留档与保护
原dev-plan、guide、input-index、b01-return-review、problem-ledger.json、T08任务文件及两批manifest条目全部只读。新收尾文件是状态覆盖，不改历史报告/manifest。生产dirty包含基线4路径和本轮新改动，禁止reset/clean或批量删除。T08未接top；不需要删除任何目录。
workflow/tasks.json与原T任务records写本轮最终证据，run不另立全局任务板。精确全局更新验证见taskboard-update-verification.json，收尾检查见closeout-verification.json。

