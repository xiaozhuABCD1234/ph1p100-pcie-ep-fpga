# T10原开发恢复01：只增加一次faults复跑

真实原开发 `/root/fpga_dev_dual_scheduler_180900`；task_id `T10.dual-aplus-scheduler`；PROJECT_ROOT `D:/fpga/ph1p100`；OUTPUT_DIR `D:/fpga/ph1p100/workflow/runs/20261025-180900_fpga-dual-offline-closure`。只能续此原角色，不新增任务或开发者，不派生。

## 新授权与原计数

先读 `user-feedback-T10-retry01.md`：用户对明确限定问题答复“允许额外复跑 1 次”。此文件是唯一新增授权来源：**仅你的faults场景累计上限2→3，额外一次**；可以在原剩余预算内补完1080p和其余原必要验证。不得扩大其他预算、目标或权限。

原记录完整保留：native+worker实际工具调用37/60，compile3/4，case进程9/20，faults已2次，独立综合验收尚未开始，实际验收后修复轮0；补充机会未因本次交回清零。现在剩余23calls、1compile、11个case进程、1次faults；工具调用包括你自己的读取、命令与worker操作。若额外faults启动即计第3次，无论成功、断言失败、文件失败或超时都不能再跑第4次。

原90分钟也不重置。以你原记录开始2026-10-25 18:25:19.126669（Asia/Shanghai）保守沿用绝对截止19:55:19.126669（UTC11:55:19.126669）；若已到时先blocked，不能以恢复新轮延长。原单问题搜索3轮、其他失败命令首次+1次有新证据重试、2次无进展停止均不变；这里唯一例外是上述faults额外一次。保留全部失败，不能靠改case名或目录重置次数。

## 原范围内的有限动作

1. 读既有 `planner-T10-blocked01.md`、自身`recovery.md/result-r0.md/evidence/commands.jsonl`，核对当前候选与停改manifest，排除未登记变化。
2. 在原允许任务目录修正 `sim/make_tb.py` 的1024bit路径截断：使用SV string或已验证的相对路径；所有必需fopen返回0必须立即fatal。先静态确认实际输出路径长度和目标目录存在，不用一次faults启动去探路径。
3. 一次剩余compile内绑定更新后的TB/runner，真实frame/core SHA不变，硬件候选不动。按原计划在余量内运行一次额外faults及未完成的默认尺寸双帧、受codec-cleanup影响的正常回归/必要边界/有效负对照和最终源核验。原faults日志缺失的真实core metadata不得从期望值重建；新faults必须真实记录且全部核验。RID/RLAST、旧身份/重复、CMP持有等原门槛不得改为N/A。
4. 不改变core，不另增目标；若还需要额外faults或compile、工具/时间/case超限，或本有限路径不能满足必要门槛，停止并返回blocked及实际余项，不续跑。原报告列出的未实现/未测内容仍须真实说明，不能隐去。
5. 保留原`manifest-r0.json`及失败证据，新候选以`manifest-resume01.json`和新结果/命令目录冻结。实际命令、工具/参数/源SHA、额外尝试计数、原控制输入和新增授权SHA须齐备；完成后stopped_modifying=true/active_commands=0才ready_for_test。若未完成，冻结blocked状态，不宣称PASS。

局部小case/compile实际timeout300s、读搜60s、T10全尺寸600s以及TB cycle watchdog不变，终止仅自己拥有的进程。无TD/综合/STA/bit/CWC/盘符映射/板卡/COM/下载/Flash/RK/外部消息/Git/批量删除授权。T08原开发继续，不能修改其目录或要求它替代缺失验证。

输出仍按fpga-dev及relay-contract的简短元数据，附本次新增/累计实际计数。新问题稳定标识；相同LIMIT_REACHED元数据问题保留原problem_id，不能通过换ID扩次数。主在ready_for_test后才新建本任务唯一综合测试者，不能借测试者接管未完成开发。
