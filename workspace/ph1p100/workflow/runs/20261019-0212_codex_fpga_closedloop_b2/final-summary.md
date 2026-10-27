# 当前交接：B01 r0通过，T02板验入口已派发

更新2026-10-19T20:47:16.671006+08:00。本段是当前状态，下面旧收尾保留为历史，不再代表当前B01结果。
两正式包T06.codex-ddr-readback-int/T09.codex-production-int首次r0 integrated PASS，实际修复0，G0/G1/G2 pass；同699项manifest c7a40897166467f2beafb096701dba9cf836e1007d77ae03d90009d06f80d757。生产6/6，禁止第7次。最终setup+0.100/hold+0.020ns、STNS/HTNS0，全部适用组及CWC/资源通过。独立报告和复用账见test-reports/下，B01全部开发/测试活动已停止。
本轮正式包完成2/4（仅本包离线范围），T02 G3 not_run等待当前现场事实和真实GUI样本；父T06/T11 active，G4后放。T08原离线开发2次编译历史保留、仍queued恢复授权内，未综合r0/修复；不代表真实同步完成。
准确下一入口=dispatch-t02-board-entry.json与t02-board-plan.md；先无硬件preflight并原样转user-summary-t02-entry.md，事实满足才一次SRAM；成功后两组>=20s，最多3组针对性样本。不能将B01 PASS外推T02 PASS。
当前用户操作清单=board/t02/two-capture-checklist.md；唯一候选/回退=已冻结remaining-attempts01/board-entry.md。当前问题：单A上电/JTAG独占/操作者当前事实未收，几何/物理相位/内部坏帧恢复仍待板证。停止点与权限不变，不Flash/PCIe-RK/推送/批量删除。

---
# 以下是此前阶段历史

# 本轮收尾：blocked，目标未完成
日期2026-10-19；原规划/root/fpga_planner_b2。正式包4个，主要目标1个，两级；B01明确合批2，独立T08为B02A单包。主仅传输。未创建综合测试者，不能把作者本地结果称为独立验收。

## 最终判定与G层
| 正式包 | 结果 | G0 | G1 | G2 | G3 | G4 |
|---|---|---|---|---|---|---|
| T06.codex-ddr-readback-int | ⚠开发blocked，未验收 | partial | standalone局部通过；联合TB两次编译失败，DUT未运行 | not_run | not_run，归T02 | not_run |
| T09.codex-production-int | ⚠开发blocked，未验收 | partial | core/ROI adapter作者本地通过，overflow动态覆盖等仍缺 | not_run，共享B01门槛 | not_run | not_run |
| T08.codex-sync-offline | ⚠开发blocked，未验收 | partial/fail：顶层语法 | blocked，未运行vsim/负对照 | not_run | not_applicable：离线未接硬件 | not_applicable：离线原型 |
| T02.codex-singleA-board | 待条件，未派发 | 无新候选可继承 | 无新候选可继承 | blocked_by_B01 | awaiting_hardware，未测 | not_run=用户后放 |

统计：正式包4，独立验收PASS=0/4；首次PASS=0，修复1/2/3轮PASS均0；开发blocked未验收3包，待条件未派发1包。综合round0从未发生，实际修复round1–3均0；两处“命令重试一次”不是实际实现修复轮，也未消耗问题补充机会。不存在综合FAIL报告，亦没有独立综合PASS。
父任务不虚报：T02板验仍awaiting_hardware，T06/T08本轮blocked；T09既有done仅历史模块级，本次生产集成blocked；T11仍active，不因局部源码或旧位流置done。

## 已有部分产物与实际证据
B01=C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/workflow/runs/20261019-0212_codex_fpga_closedloop_b2/candidate/manifest.json，SHA256=2B328FC0A23ECAE57E8D95C6CA66E2C9726CC95B9D536EDD673380BCACFFEABE，236项，ready_for_test=false。单A读回控制/持有释放/checker保护与生产三算法/CSI ROI适配/诊断sink已经写入生产检出，最终联合行为和实现未证。作者本地原回归、checker完整1080p、算法oracle/core/adapter正例与HE负对照有日志；不得替代失败的联合读回与新生产G2。
T08=C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/workflow/runs/20261019-0212_codex_fpga_closedloop_b2/sync-offline/manifest.json，SHA256=94FF1150859062081461D7B083731B2906FD28927A71377FB50A00676B7DF06A，26项，ready_for_test=false。启动/角色/SOF mailbox/配对/复位及TB仅实现意图，尚未编译通过；无成功仿真/负对照/G2。父T08曝光同步完全未证。
原规划收尾重哈希B01 236项与T08 26项均0漂移，旧回退bit/CWC身份一致，见closeout-freeze-audit.json。该核对只证明留档身份，不是功能/工程通过。原dev-plan/guide/problem-ledger.json等已包含在冻结输入，保持原文；最终计数另存problem-ledger-final.json，避免漂移。

## 两个有界停止点
1. T06.codex-ddr-readback-int:LIMIT_REACHED:integrated-tb-compile：首次联合TB声明/变量错误；纠正后第二次rb_*重复/隐式声明8个编译错误。attempts=2/retry_used=1，未执行DUT。
2. T08.codex-sync-offline:LIMIT_REACHED:offline-tb-compile：首次非ASCII路径sqlite失败；纠正ASCII映射后的第二次在sync_offline_top.v两处非法“()”位置连接报语法错误。attempts=2/retry_used=1，未执行vsim。稳定problem_id不因错误从路径变为RTL语法而改名。
两处补充机会均0、实际修复均0、TD尝试均0。开发已停止修改和自身活动，无第三次编译，无换ID/新run绕限。role工具调用实际总数未完整返回，不能伪填；已冻结预算保存在各dispatch与计划。

## 板清单与当前边界
本轮没有新生产bit/CWC/最终DB，未下载、未做任何新板测；“回来点两下”当前入口=C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/workflow/runs/20261019-0212_codex_fpga_closedloop_b2/board-checklist-final.md，状态NOT_READY，不可执行。本轮保留旧GUI通道，CLI读回保持关闭。
仅在未来同候选G0/G1/G2/CWC物理映射合格且用户在场时，清单的两次GUI触发才开放。两样本需>=20s、不同seq、校验完整、实际几何与坏帧拒绝/恢复证据；不是点两下就自动PASS。内部abort只证明数字拒帧，不冒充物理链路CRC故障。G4长稳/性能优化未做。

## 安全、写范围与恢复
无Flash、PCIe/RK、推送、物理连接/电源操作；无批量删除。保留生产检出HEAD b0282d2a8dfdf11e6e63779510fe380dfffb5e83及原四项dirty，新增部分源码worktree-only；本轮没有提交。T08新文件未接活动top，保留不引用即可，不必删除。B01未验证源码不能当稳定生产版本；不自动reset/clean/逆向全部dirty，来源由manifest/基线逐项核对。
没有剩余独立可派包：T02依赖缺失的新合格候选，T06/T08均命令到限，T09共享B01门槛。run状态blocked，等待明确有限恢复输入。
准确恢复入口见question-restore-limits.md与handoff.md；原规划/root/fpga_planner_b2、B01原开发/root/fpga_dev_closedloop_b01、T08原开发/root/fpga_dev_sync_offline。无测试ID；未来只有ready_for_test才创建对应单一综合tester。真实ID实际失效才按文件恢复并登记映射，不探测旧OpenCode会话，不清零计数。

