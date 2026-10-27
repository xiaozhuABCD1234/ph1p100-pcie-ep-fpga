# T02 SRAM工具入口纠正与一次有限恢复

当前问题ID=T02.codex-singleA-board:TOOL_UNAVAILABLE:sram-entry-timeout，保持不换。用户request-followup-05.md已经确认当前在场、单A上电、JTAG空闲；followup01“足够的尝试机会/完善”和followup04“继续做”覆盖本范围内有证据的有限纠正，无需再次询问是否允许SRAM。本计划不扩大硬件/Flash/接线/推送权限。

## 已审查事实
- 原SRAM第1次：2026-10-19 20:59:46启动，120s期限，elapsed121.309s、timeout=true、exit1。download.log仅元数据/OWN_PID30416/终止记录，没有TD banner、Tcl开始、器件身份或成功标记。不能确定实际停在哪一步，更不能判断板测通过/硬件失败；加载状态unknown。
- 原角色PID8832/30416均停止，25/30工具，采样0/3，SRAM1/1（旧上限历史），B01699项前后0漂移。未创建T02tester、T02 r0未开始、实际修复0。B01两项r0 PASS、生产6/6保持。
- 有实质新证据的入口差异：冻结run_sram.py调用D:/anlogic/TD_Release_2026.2/bin/bw.exe；同版本真实成功日志baseline board-readback/cwc-cli/phaseP3R_stdout.txt明确Executable=.../td_commands_prompt.exe，read_device_id=PH1P100，download -mode jtag rc0/28.356s。此前phaseFINAL也证实该原生CLI下载成功；CLI ChipWatcher读回失败并永久关闭，本轮不恢复读回。
- 本机docs/TD命令行使用说明.md明确批处理为td_commands_prompt.exe ./file.tcl、ASCII cwd/正斜杠路径、显式exit并检查标记。三个程序文件都存在。本次工具入口不匹配是待验证的具体假设，不把它直接宣布为全部超时根因。原B01board-entry/699项/报告保持历史原文；只在T02新隔离路径纠正操作封装。

## 仅五项操作
1. 续原T02开发/root/fpga_dev_singlea_board，先将旧失败结果/25工具账/1次尝试与0组采样引用到新ledger；记录本次真实start+1800s deadline。全部新增封装/日志仅写C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/workflow/runs/20261019-0212_codex_fpga_closedloop_b2/board/t02/tool-entry-recovery01/；不覆盖原开发冻结的失败快照。
2. 在本角色新ASCII映射cwd准备纯软件CLI探针：D:/anlogic/TD_Release_2026.2/bin/td_commands_prompt.exe ./cli-probe.tcl，stdin关闭，脚本仅puts/flush、Tcl版本和info commands检查connect_cable/read_device_id/download存在，显式exit。不得执行任何connect/download/capture/hwserver；60s原生进程树deadline，退出0且明确探针成功标记才通过。不用-help（本机把它当文件）。失败一次即回规划，不盲换入口。
3. 只读检查现有5555监听/其明确进程路径与必要已有GUI状态。沿用用户05的当前单A/JTAG空闲事实，不重复问SRAM许可；若服务缺失、进程所有权/占用不明、GUI已有阻塞提示或事实有变化，立即保存并返回需用户具体操作。不得启动/重启server、杀他人进程、扫描其它cable或新端口；不要求用户盲关进程。此时可原样转question-t02-tool-state.md收截图/时间。
4. 只有上述软件自检通过且现有服务/独占条件可证明，执行一次纠正后原生SRAM入口。新Tcl/runner由原开发实现在新目录，不改冻结wrapper。精确相同bit可单文件复制到新ASCII映射目录并复核SHA b68c6e183e97eb0d465db77078f5049feca3a947fac51f99633621dd99b3f9bf；不写D盘工程。调用绝对td_commands_prompt.exe、相对正斜杠Tcl、stdin=DEVNULL、stdout/stderr留日志，显式Tcl开始/每阶段puts+flush/exit。仅连接现有127.0.0.1:5555，不传启动server参数；读取PH1P100身份后才download -mode jtag -spd7 -cable0一次，关闭本会话连接。native120s/outer180s真实deadline及自有PID树安全终止；native exit0+具体PH1P100+download rc0+成功标记/实际完整进度为成功依据，不以单纯退出0代替。未知/失败再次保留，累计2/2到限停，不第三次、不回退重下。
5. 仅下载确认成功后转原T02同候选GUI人工采样：先1组成对T1/T2>=20秒，每时刻camera/DHI分别保存；最多另外2组有明确缺项的补样，总3组。原G3全部读回/两seq/长度CRC/真实几何与物理相位依据/一次内部abort与确切首个合法good恢复阈值不变；失败或缺项不升PASS。停止修改/活动且完整新T02manifest后才ready_for_test，后续仍同任务一位新综合tester。

## 角色、预算与写范围
本次新增一次20工具/30分钟窗口；保留旧25/30工具及旧45分钟窗口原账，不沿用旧剩余量来叠加执行。授权工具上界原30+新20=50，实际已用25+本次最多20=45；时间窗原45+新30=75分钟授权上界，本次deadline按真实续接开始+1800秒。读搜60秒；纯软件探针60秒；局部静态300秒；原生SRAM120秒/外层180秒；每采样组收集300秒。单问题本次最多3个目标读取轮，连续2无进展停。工具/worker调用均计；API错误不自动重试。
SRAM总上限由1明确修订为2，只新增1次且有上述前置条件；旧1次不清零，若硬件前置缺失不消耗第2次。生产6/6不增、G1不重跑、实际修复0/r0未开始不变，补充整理机会0不当设备重试。原dev-board冻结artifact只读；新改动全部限新tool-entry-recovery01目录，另仍允许后续用户原样文件进入board/t02新唯一路径；不改任何B01699项。
所有新路径先resolve/junction审查留在本项目；临时subst映射只属于新输出目录且结束释放，不能把TD日志写回B01冻结目录。不删除文件/目录，不改工具安装/环境/全局配置、生产RTL/IP/ADC/SDC、T08或其他工作树。
T02 tester预算仍原30工具/45分钟、只写test-reports；不得为本操作封装修正新开测试角色或把准备材料提前验成G3。新操作脚本/复制bit/hash/实跑日志须进入T02最终manifest，由唯一综合tester检查；B01不可变输入及两报告被同manifest引用。

## 独立后续与人工等待
本次优先原T02入口纠正，因为已有明确可验证差异且可先无硬件推进；不并发启动原T08以免打断首次下载/现场窗口。若原开发证实GUI/server外部条件缺失，直接返回原规划；下一派发优先让用户补具体现场状态，同时由原规划在原四包内明确安排原T08离线恢复，不让主自行选题，也不让T02空等。
准确恢复输入：原board/t02/development-result.json + 本计划 + 新C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/workflow/runs/20261019-0212_codex_fpga_closedloop_b2/board/t02/tool-entry-recovery01/development-result.json（责任角色生成）；问题ID不变。硬件/服务未知交用户当前截图，不要求重新许可；必要启动/关闭哪一进程只能在识别所有权和具体事实后由规划给可审查步骤，不自动扩权。
