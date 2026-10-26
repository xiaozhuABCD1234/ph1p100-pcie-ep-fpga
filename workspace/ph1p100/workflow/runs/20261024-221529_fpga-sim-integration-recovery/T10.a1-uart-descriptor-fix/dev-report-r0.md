# T10.a1-uart-descriptor-fix round0 开发交付

状态：ready_for_test。本报告只说明本地开发检查完成；正式综合判定由一个新的独立综合测试者给出。runtime=Codex，开发会话 /root/fpga_dev_descriptor_221529。授权入口为 dispatch-dq-fix-r0.json 与 planner-amendment-authorized-dq-fix.md。

## 实现与输入身份

唯一 RTL 候选为 candidate/a1_uart_export.v；candidate.diff 列出全部差异。dq_wr/dq_rd 改为1位并在接受时取反；dq_cnt保留2位；reset索引清零；accepted push=desc_push且旧count<2，accepted pop=旧estate IDLE且旧count非0；count按10加1、01减1、00/11保持集中更新。描述符顺序、CRC、帧格式、DDR、时钟、UART握手、编码核和两项容量策略保持。原8项均只读；corrected-dut-index.json由1项修正路径及7项原始SHA路径组成完整DUT，没有复制或修改另外7项RTL。

## 实际复现与局部验证

旧/新各完成一次全部8RTL、真实顶层、DDR模型及两个TB的编译，vlog各Errors0/Warnings0。共2次全量compile，未重试，达到本派发上限。

旧版 boundaries 真实同拍接受 push/pop，目标断言报 old=1 push=1 pop=1 expected=1 actual=0。旧版 wrap 实际第3次出队，目标断言报 expected_id=1003 actual_id=xxxxxxxx。两例均已正确编译、进入真实DUT执行；不是用编译失败作反例。日志各Errors1为预期目标Fatal，ModelSim进程退出0不作为负例判据。

修正版 boundaries：10类合法(old_count,request,pop)组合均有实际hits；两类count0 pop=1不可能组合明确排除。覆盖空/单项/满、单项同拍push/pop、满拒收、full+pop拒收并st_err加1、满队列无push出队。输出1001/1002/1003/1006四包；拒收1004/1005均不输出；queued reset前真实active E_OPEN且queued=2，reset索引/占用/状态/统计清零，已接受未导出的7001/7002/7003被撤销；新epoch只输出2001/2002。共6完整包，严格独立字节检查PASS/mismatch0。

修正版 wrap：真实导出模块顺序输出1001..1012共12个不同ID，经历多次读写回绕；随后重复queued reset并完整输出新epoch的2001/2002。共14包，严格zlib、四CRC、源字节、无X、顺序、零重复、零尾垃圾全部通过。单模块fixture为Python标准zlib生成的20字节RAW/profile0 payload；存储侧由独立fixture队列提供ID/长度和数据，期望不读取DUT描述符内容。

修正版 full-clean：真实camera_a1_uart_top、7项原始RTL及唯一修正导出器实际精化/执行，W8/H2、UART_DIV4、FIFO_AW2、HB_DIV0；camera/A1异相时钟经真实CDC FIFO，UART=A1符合原合同。4个good输入种子1000..1003全部完整输出ID1..4，292B；cap/enc/raw_pub/exported均4，raw/cmp drop/geom/err/FIFO reject/duplicate/old-response均0。原checker的最低2包门槛在本包runner额外强化为精确4包，同时TB等待与完成断言也强化为4包。四个73B包均独立严格zlib/四CRC/RAW像素逐字节通过。

完整管道保留3条原有精化告警：u_cmp_store漏接仅观察输出st_read_words/st_dup_words（一条端口数、两条漏端口）。原7RTL受保护，未屏蔽告警；相关顶层接线无修改。单模块两正例Errors0/Warnings0；full-clean Errors0/Warnings3有上述固定解释。无目标端口、位宽或时钟新告警。

## 工程、隔离与限制

108项规划保护输入before/after逐项SHA一致，漂移0。所有新增文件和工具产物均在本任务目录；不改生产/upstream/fpga/tools、原inputs、其他任务/旧run、docs junction、TD/板候选或共享盘符；无删除、消息或其他进程操作。模型真实成对AW/W握手、周期stall及延迟AR/R响应，DUT reset只门控新请求而不清DDR模型内存/已接受响应；本包full-top仅执行clean，原恢复包的故障case不在本包冒充覆盖。

各编译/仿真实际argv、cwd、拥有PID、退出码、耗时与300s deadline见actual-commands.json及原*.command.json；TB同时有cycle watchdog。库/INI/run.do/WLF/日志均独占；全部命令已wait，无后台活动、超时或杀进程。最初4次小读取/状态命令实际各约1.2–1.5s但未另包60s deadline，这是已披露执行偏差；后续读取审查使用拥有PowerShell Job的60s限制，不将yield时间冒充deadline。

G0/G1仅为本地仿真资格已具备，等待独立综合测试；G2=not_run，G3/G4/G5按规划为not_applicable。TD/综合/route/bitgen/CWC/download/Flash均0。本结果不证明可上板/生产时序或父恢复任务通过。没有扩大为第二RTL/协议/容量修复。

## 冻结、复测和回退

唯一manifest-r0.json列出真实RTL/模型/TB/checker/fixtures/runner/参数/工具与实际证据SHA；corrected-dut-index.json给出恢复包所需完整8RTL映射。冻结最后动作由freeze.py执行并自校验，之后停止修改与所有命令，active_commands=0。freeze-verification.json绑定manifest SHA。retest清单在relay-metadata.json；独立测试须自行建库、重跑所有队列正反例与四帧clean，核对保护输入。测试者不能向本开发目录写入。

回退入口是原只读inputs/a1-r5/src及本run原dispatch；原生产/板候选未改变，保留全部正反例与产物，无清理删除。若未来迁入生产，应另做完整G2/CDC/资源/候选绑定及硬件资格。后续恢复包由原规划保留历史计数并以changed输入恢复原真实开发者。
