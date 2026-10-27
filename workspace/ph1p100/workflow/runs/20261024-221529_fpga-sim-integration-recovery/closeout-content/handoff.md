# 已完成交接（2026-10-25）

PROJECT_ROOT=`D:\fpga\ph1p100`；run=`D:\fpga\ph1p100\workflow\runs\20261024-221529_fpga-sim-integration-recovery`；runtime=Codex，batch1，4/4正式包已round0独立PASS、实际验收后修复0。当前机械入口 `dispatch-finished.json`，状态finished、needs_user_input=false，无下一开发/测试/硬件动作。

## 唯一身份与入口

- 双路：`T08.sync-production-sim/manifest-r0.json`，SHA `6d9d980566997b74945066a8b015308962dcb58cd525ce868ef5837a0b482838`；独立报告同task的r0-integrated。
- A+恢复最终：`T10.a1-recovery-sim/resume02/manifest-resume02.json`，SHA `628579eae2b6b2c1afc66a477799960a6b180b213e848bdbc0e1e955437d82e1`；完整8RTL是 `recovery-dut-binding-resume02.json`，来源为第四包corrected-dut-index。top `5d0f9a00...10772a`、exporter `0f3ae49e...3ba097`及原6项。不得用原坏exporter/top、旧P2/r4或活动树同名文件替换。
- 两依赖包manifest：descriptor `fd0cb6e7...c33e1`，abort `db84411d...fa5dcd`。准确全SHA、所有绝对路径和独立报告见 `candidate-binding-final.json`、`delivery-index.md`、`input-index-final.md`。
- 原 `fpga-design-guide.md`、`input-index.md`、各阶段dispatch/manifest/blocked/失败日志都保持不变；最终指南是 `fpga-design-guide-final.md`，不能覆盖已验控制输入。旧待确认/额度blocked入口只留历史，不再处于当前状态。

## 真实角色与计数

原规划 `/root/fpga_planner_sim_221529`。T08开发 `/root/fpga_dev_sync_221529`、tester `/root/fpga_tester_sync_221529`；descriptor开发 `/root/fpga_dev_descriptor_221529`、tester `/root/fpga_tester_descriptor_221529`；abort开发 `/root/fpga_dev_abortcdc_221529`、tester `/root/fpga_tester_abortcdc_221529`；原恢复开发 `/root/fpga_dev_recovery_221529`、其唯一tester `/root/fpga_tester_recovery_221529`。均为当前宿主真实工具返回ID，不假称跨宿主resume。

原恢复开发60calls/4compile/27sim、载入前失败1；tester quota前9calls+续接20=29，2compile/21sim/17checker；实现修复均0。两个稳定problem机会：`T10.a1-recovery-sim:SCOPE_CLARIFICATION:fixed-r5-descriptor-index`=1，`...:crop-abort-cdc-loss`=0，技术条件均由修正候选解除，历史不清零。`user-feedback-01-continue.md`、`user-feedback-02-continue.md` 和main-log保留真实继续/额度恢复；quota不是最终阻塞。各原账索引见budget-ledger-final.json，准确起始未仪表化的角色不编造耗时。

## 证明边界和复现

G0/G1全部pass，三维按离线范围均pass；G2 not_run，G3/4/5本包N/A，父T08/T10硬件状态不升级。恢复20case/88包/80当次good、最大FE后10042周期；额外旧AR未完成的reset边界未命中。没有1080p满速、真实DDR/物理CDC/STA/资源/板级/长稳/压缩收益或新bit资格。

实际复现命令/参数/工具SHA/独占库和原始证据均在各独立报告、actual command index。现有runner可能写既有输出目录，任何将来的复现都应先在新隔离证据子目录绑定同输入，由原责任角色执行，不能盲覆盖当前frozen库/日志。当前finished不自动复测，不重建/上板。

只读复核的准确用户入口：

`$fpga-orchestrator 恢复：D:\fpga\ph1p100\workflow\runs\20261024-221529_fpga-sim-integration-recovery；本轮目标：只读核对 delivery-index.md 与四份既有独立报告，不新增开发、测试、TD或硬件操作。`

需要未来生产或额外交错新目标时必须另行明确有界范围；本run已用满4包，不自动开第5包、改ID或新run绕过原账。没有发外部消息/安排监控/下载/Flash的延伸授权。

## 回退

生产、原输入、旧run、D:\TD、D:\fpga_work、板候选/bit/CWC/DB、共享盘符和其他工作树没有改变。直接停止使用本run副本即可回退，不需硬件/生产文件操作；保留全部失败证据，禁止批量删除。统一任务板仅更新离线子包和证据，父任务state保持原值。
