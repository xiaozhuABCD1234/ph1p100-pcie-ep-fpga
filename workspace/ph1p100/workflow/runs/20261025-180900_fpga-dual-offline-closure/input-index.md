# 本轮输入、版本与所有权

实际工程根 `D:\fpga\ph1p100`；本轮 run `workflow/runs/20261025-180900_fpga-dual-offline-closure`。规划冻结日期 2026-10-25；需求唯一原话入口 `request.md`。读写命令从规划第六次读取起以 PowerShell Job 的实际 60 秒 deadline 包围；早先有限本地读取均已结束，没有遗留进程。规划最多 30 次工具调用、15 分钟，不派生。

## 需求与范围依据

- `request.md` 保存“上述两者尝试使用工作流技能派好分配下去做理线闭环”和紧邻“但是我这里目前没接入Rk，所以还是只能是跑单独FPGA相关的，看下情况”，连同上一回复的完整两包说明。这里按其上下文将“理线闭环”理解为既述的 RTL 离线闭环，不改成现场布线任务。
- `D:/fpga/ph1p100/docs/并行工作再评估_2026-10-25.md` 第0/5节：A=双路同步与本地消费，D=完整RAW帧到单A+核调度；A/D消费者互斥。本文是15:00快照，不宣称其b11进度仍为当前状态。
- 根 `AGENTS.md`、`.agents/skills/fpga-planner/SKILL.md`、`fpga-design-guide/SKILL.md`、`fpga-dev/SKILL.md`、`fpga-tester/SKILL.md` 及 orchestrator 的 `work-limits.md`、`relay-contract.md`、`report-contract.md` 是现行单一综合测试者合同。旧三tester示例不生效。

## 已有工程、实际输入

下列路径均相对工程根，SHA256/字节数由 `planning-input-manifest.json` 精确记录；开发必须验证后复制到自身目录再修改，不能按活动树同名文件替代。

|用途|准确路径与采用版本|所有者/边界|
|---|---|---|
|正式RAW双路派生候选|`workflow/runs/20261024-221529_fpga-sim-integration-recovery/T08.sync-production-sim/candidate/`；全部候选文件纳入本轮输入清单|旧run只读，顶层 `rtl/ep_side/ph1p_pcie_ep_top.v`，保持真实checked CSI、writer、仲裁和同步RTL|
|同步集成与环境参考|上项同级 `sync_i2c_config.v`、`sync_frame_gate.v`、`sensor_i2c.sv`、`vendor_env.sv`、`tb_production_sync.sv`、`run_t08.py`、`check_t08.py`、`manifest-r0.json`|旧manifest SHA 6d9d980566997b74945066a8b015308962dcb58cd525ce868ef5837a0b482838；六场景已有独立PASS；环境DDR只有写功能，本轮必须补读|
|旧同步独立报告|`workflow/runs/20261024-221529_fpga-sim-integration-recovery/test-reports/T08.sync-production-sim-r0-integrated.md`|旧G0/G1，不能当本轮双路读回通过|
|正式R10F写者/本地读回|候选内 `rtl/ep_side/ddr/cam_r10f_writer.v`、`ddr_frame_readback_checker.v`、`closedloop/ddr_closedloop_readback.v`|已有cl发布/释放是DHI域；现顶层只给A接CLOSEDLOOP，B未接；已有读回锁定/排空语义应复用|
|带掩码读回配置器|`workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b10-b9-fix/r0/td/src/camera/uisrc/03_ip/ui_imx415_cfg/{ui_cfg_imx415.v,ui_i2c.v,ui_imx415_reg.v}`|b10冻结参考；三文件存在性和SHA均已核对。保留read_mask及事务超时；自动退出standby必须由同步模式安全接管|
|唯一A+ frame/core输入|`work/b10-gap-sim-20261025-132023/inputs/rtl/a1_frame_top.v` SHA c8b24775fa70793f682f1a640be175ec53f304722539cbd89550e0d4aefca65b；同目录 `a1_deflate_core.v` SHA 6797db053cfc47497540d6345e3a46b7e79cc1d34fa25da5a4c501505fbf35bb|与b6已验core相同；冻结不修改两文件；不从b11取源|
|A+独立基线报告|`workflow/runs/20261020-0209_singleA_aplus_closedloop/test-reports/T10.b6-a1-htab-nw-r0-integrated.md`|原候选核级吞吐81.067MB/s，不是双路系统保证；新适配器不继承旧G2|
|软件独立判据|`tools/pcie_integration/r10f_strict.py`、`tools/a1/{a1_pattern.py,pc_decode.py}`|只读参考；pc_decode用zlib.decompress，测试还必须用decompressobj校验eof、unused_data、unconsumed_tail|
|历史故障|`work/b10-gap-sim-20261025-132023/README.md`、`input-manifest.json`、`r1-loss/result.md`、`multi-frame/result.md`|b10含LAST拒收未恢复是真实旧候选反例，不能推定本轮R10F写者同缺陷，也不在本轮修改b10/b11|
|全局主源|`workflow/tasks.json`、`workflow/records/T08/`、`workflow/records/T10/`、根README/CODEX_HANDOFF、`workflow/README.md`5.1|父T08当前ready、T10当前active，离线结果不改父done；板与生产条件留待后轮|

配置表文件已在planning-input-manifest按存在路径枚举；不要仅凭此表大括号形式猜文件名。与旧cfg不兼容的端口只能在本轮命名wrapper内适配，不整体覆盖生产文件。

任务板是并发调度主源，其规划时快照冻结为本run `inputs/task-board-at-plan.json`。开发验证该快照身份，不把其他责任角色后来更新实时任务板视为DUT源漂移；收尾必须重新读取实时主源并发安全追加。

## 工作树与保护

本次 `git rev-parse HEAD=27c596b01cd961dfa9d0850e4fbf879fe249de90`，分支 `codex/ddr-timing-margin`；已有801条已跟踪dirty记录，其中大量历史迁移删除/修改，均非本轮授权处理。旧run/未跟踪生产成果、OpenCode b11、其他工作树均只读，不能清理、覆盖或提交。另一工作树 `C:/Users/czz/.codex/worktrees/bayer-codec-reference/FPGA创新设计赛道` 在 `1994131`，无写授权。

`docs` 为junction，实际目标是OneDrive文档目录，本轮只读。开发仅各自本run任务目录；测试仅各自本run test-reports目录；规划仅本run控制文件和最终相关任务记录的最小追加。禁止批量删除、git clean/reset、盘符映射、TD/bit/CWC/下载/Flash/RK/外部消息、自动化。

## 工具与未决

存在性已核对 `D:/intelFPGA/18.1/modelsim_ase/win32aloem/{vlog,vsim}.exe` 与 `C:/Program Files/Python311/python.exe`；未执行仿真或构建，不把存在性写成许可/工具运行通过。run命令必须实际落实超时，不得使用共享P/W/T/Y/X映射。无需用户补充即可先开展两包离线开发；若必需资料/工具缺失按稳定problem返回，不靠改模型或门槛补PASS。
