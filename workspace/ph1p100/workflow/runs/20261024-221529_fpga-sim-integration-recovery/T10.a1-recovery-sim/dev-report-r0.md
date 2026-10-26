# T10.a1-recovery-sim round0 开发阻塞证据

状态：blocked；不是 ready_for_test，不宣称综合验收 PASS。开发实际会话 `/root/fpga_dev_recovery_221529`，runtime=Codex。唯一入口是本 run 的 `dispatch-t10-r0.json`，并绑定 `planner-update-t08-pass-t10-ready.md`。

## 已完成与实际发现

已编写独立 `tb_recovery.sv`、`ddr_recovery_model.sv`、`check_recovery.py` 和 `run_recovery.py`，八项 DUT RTL 均直接从冻结 `inputs/a1-r5/src/` 编译，未复制修改或补丁。108 项规划冻结输入最终 SHA 均相同，详见 `protected-input-check.json`。

一次全量编译完成，vlog Errors 0 / Warnings 0。ModelSim 精化有三条固定 DUT 自带告警：u_cmp_store 漏接两个仅观察输出 st_read_words/st_dup_words，产生一条连接数和两条端口告警；这些输出未参与功能接线，未屏蔽告警。UART 与 A1 同时钟符合 r5 导出器的明示合同；camera 与 A1 独立相位，保留真实 CDC FIFO。UART_DIV=4、FIFO_AW=2，DDR 单次 AW/W 同拍接受、周期 stall，读请求/响应保持至真正握手。模型没有 DDR reset 输入，DUT reset 只阻止新请求，内存和已接受读响应不会被隐式清空。

正常场景实际输入 4 个 good 帧，种子 1000..1003，无故障、无 FIFO 拒绝、geom/drop/error/duplicate/旧 epoch 响应计数均 0。第一和第二包各 73 字节，frame_id=1/2；独立严格 zlib、四 CRC 和原始像素逐字节检查全部通过。第三个包从偏移 146 开始，其 flags（偏移 151）即为 X，frame_id/长度/CRC 字段随后均未知。总捕获 1097 个 token，实际 exported 仅 2，cap/raw_pub/enc 各 4。TB 的计数型 CASE_PASS 被严格字节检查拒绝，不能作为通过依据。

定位到受保护 `inputs/a1-r5/src/a1_uart_export.v`：数组为 `reg [255:0] dq [0:1]`，但 dq_wr/dq_rd 为两位，并分别按 `+ 2'd1` 递增，第三次访问索引 2，超出两项数组。前两包正确及第三包的未知描述符字段与此直接对应。证据见 `defect-evidence.json`、`clean/capture.dec`、`clean/trace.txt`、`clean/stats.txt` 和 `clean/console.log`。这是固定 DUT 的实际缺陷，不能用只发送两帧、丢弃第三包或修改 RTL 达成本轮验收。

静态负对照把前两项真正有效包冒充下一 epoch 的种子 1100..1103，检查器以 `wrong source / stale epoch / corrupt bytes` 明确拒绝，详见 `negative-control.json`。该反例证明即使包的 zlib/四 CRC 全部正确，也不会仅凭 CRC 把旧图案当恢复。

## 未运行和范围限制

遇到固定 DUT 缺陷后按 dispatch 停止继续仿真；raw-midwrite-reset、encoded-midwrite-reset、bad-frame、overflow 都是 **not_run**，不把源码中的分支当成覆盖。其代码仅为待审准备，未验证注入命中、恢复界限或无旧响应条件。reset 分支准备 W16/H2（仍小几何），因为 W8/H2 RAW 只有一个 DDR 字，无法在已接受一个真正 DDR AW/W 之后且尚未发布时触发中写复位；编码小包也需多字才能建立同样前置条件。这一准备参数没有取得通过证据，若原规划要求严格固定 W8/H2，须先明确采用存储入口接受数还是外部 AW/W 作为中写定义，不能临场降低命中断言。

无 reset 的坏帧/overflow 分支分别记录故障计数差值；reset 分支分别保存复位前状态并要求清零/slot ownership 释放。overflow 仅通过有限 FIFO 与 DDR 写 stall 触发，不 force 内部状态。恢复最多输入 4 个不同图案帧，最后 FE 后 1,000,000 A1 周期界限、进程实际 300 秒和 TB cycle watchdog 均保留。这些尚未运行，不能称通过。

功能 G1 未满足；工程仅局部编译及冻结输入检查已运行，剩余需要综合测试者独立判定。G2=not_run、G3/G4/G5=not_applicable 均沿原规划，不能提升父硬件任务状态。TD、板卡、下载、Flash、生产/旧 run 修改、共享盘符及他人进程操作均为 0。

## 实际执行与有界停止

实际工具 Python 3.11.5、ModelSim Intel FPGA Edition 10.5b；完整 argv、cwd、PID、实际退出码、运行秒数、300 秒上限在 `vlib.command.json`、`vlog.command.json`、`clean/launch-failed.command.json` 和 `clean/console.command.json`。工作库为本目录 `lib/`，INI 与 run.do 均独占。

初次 vsim 在设计载入前因反斜杠 -modelsimini 路径被旧版 ModelSim 加花括号而失败（exit 12），未执行 DUT；原始失败记录保留。根据该具体新证据改为正斜杠后启动成功（exit 0），实际 clean 仿真只运行一次，未盲重跑。随后严格字节检查失败并停止。compile 1/2；其他 case 各 0 次；实际修复轮 0，problem 补充机会 0。

读取/静态检查的后续命令均有拥有的 PowerShell Job 60 秒控制；最初两次纯文件读取实际各约 1 秒完成，但没有附加显式 60 秒终止包装，此执行偏差如实保留。仿真/编译由本目录 runner 的 subprocess timeout=300 控制；超时终止仅针对该 runner 创建的 PID 树。本次无超时终止。所有本角色子进程均已 wait 完成，无后台活动。

## 最小下一步与回退

原规划登记固定 r5 描述符索引越界为后续 RTL 修复条件；本包不获得修改 DUT 授权。修复若被另行排期，应另建冻结 DUT 输入并执行适用 G2，随后原规划再明确恢复本包的输入身份、geometry/命中定义与保留的 round/problem 计数。准确恢复入口为本 run 的 `dispatch-t10-r0.json` 和本报告。当前生产及板候选未改变；全部失败与准备代码保留，无删除操作。
