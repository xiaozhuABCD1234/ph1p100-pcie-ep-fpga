# recovery01：真实新增授权后的有限恢复计划
本文件是2026-10-19原规划/root/fpga_planner_b2对同run的恢复覆盖。用户原文=C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/workflow/runs/20261019-0212_codex_fpga_closedloop_b2/request-followup-01.md：“接着做，给你足够的尝试机会，接着完善”。这是明确新增继续及增加尝试授权；数字由规划冻结，不冒称用户给过具体数字。本文件覆盖前次handoff/question里“尚未授权/只追加1次”的等待描述，不再为默认2次上限重复请求确认。原需求、4包/两级/批2、同任务ID、原角色、硬件边界不变。

## 恢复次序与当前派发
1. B01=[T06.codex-ddr-readback-int,T09.codex-production-int]先恢复原开发/root/fpga_dev_closedloop_b01，完成原联合G1、T09缺项、共享生产G2/CWC及冻结。一批一开发顺序实现；停止全部修改和活动后，首次新建一个fpga-tester统一逐任务r0 integrated验收。
2. 用户又在request-followup-02.md明确“而且现在我在，如果需要我进行操作可以随时停下”。纳入当前在场条件；不是停止全部任务。B01综合通过后，原规划优先派既有T02.codex-singleA-board利用用户窗口，绑定唯一新合格bit/CWC，再给具体可审查的GUI/SRAM步骤；需要人工操作就在该依赖处停下由主原样转达，不能猜测用户已点击。
3. 原规划读取B01报告和新manifest后，仍续原T08开发/root/fpga_dev_sync_offline完成既有离线包；在板包完成或等待人工且无工具/候选冲突时作为独立可继续工作，不新开发者、不新run、不修改B01。T08新增预算已授权但当前不并发派发。用户在场不取消B01的G1/G2/CWC门槛，不提前下载，不以离线PASS算板闭环；全程仅SRAM、不Flash、不推送、不接PCIe/RK。
原规划仍不能写RTL、修TB、代测试；主只机械followup和转返回，不监控。

## 新的有限执行预算（不是无限重试）
| 项 | 当前历史 | recovery01新增/有限上限 |
|---|---|---|
| T06原联合读回编译操作 | 实际2次，原retry已用1 | 追加最多6次纠正尝试；同操作累计最多8次；保留每次argv/cwd/日志/错误/纠正依据 |
| T08原离线编译操作 | 实际2次（路径失败+语法失败） | 追加最多6次；累计最多8次；不因换输出目录/错误类型/任务名清零 |
| recovery01中其它局部G1/静态失败操作 | 既有实际次数照实登记，不能假定0 | 对明确同一失败根因的完整命令最多6次总执行；每次有新证据/参数或代码纠正才可重跑 |
| B01生产TD实现 | 既有0次 | 当前续接与本轮独立核验合计最多3次实现尝试；每次<=1800秒；默认一次成功合并实现，成功后不例行重复构建 |
| T08自身离线TD实现 | 既有0次 | 最多3次，单次<=1800秒；离线小顶不下载 |
| B01 DEV单次本次续接 | 原派发已结束，历史保留 | <=120工具/180分钟；理由：两包联合G1、全帧回归、诊断/CWC和最多3次生产实现，足够纠正常规问题 |
| B01一个新综合TEST | 尚无真实ID | <=60工具/90分钟；独立重跑受影响G1、审查同最终DB与manifest，默认不重建成功DB |
| T08 DEV后续派发 | 原派发已结束 | <=80工具/120分钟；新综合TEST<=45工具/75分钟；理由：完整控制/CDC正负例与必要离线G2 |
| 实际修复与补充机会 | 两问题各补充0、综合r0未发生、实际修复0 | 仍保留独立综合round0后最多round1–3实际修复；本次是未验收开发续接，不伪造round1；不重置problem_id |

本表覆盖本次恢复的默认同失败命令首次+一次、旧角色执行预算和TD两次上限，仅在同一已授权scope。用户已经明确增加尝试，运行角色不得再次仅因旧默认2次上限停止；采用本表剩余次数。其它范围/权限边界未扩。
预算是上限而非必须耗满。每轮必须给出“实际失败→可检查根因/假设→最小纠正→目标检查”的新证据；禁止盲目同参数重复。连续2轮真正无进展、上述新上限、真实缺工具/设备/权限/API/额度或必须扩scope时主动blocked。错误定位已收窄、完成实质纠正或有效编译/仿真推进不能机械误算为无进展。新不同必需case可独立验证，但不得以case/目录更名重试同一失败绕预算。

## 实际命令deadline与终止
读取/搜索60秒；每个局部静态/每个TB300秒；TD每次1800秒；setup_debugger/CWC后处理300秒；未来获派发的SRAM下载120秒。用run-local Python subprocess wait(timeout)加仅本次owned PID树安全终止，或Process.WaitForExit+own taskkill树；日志记录PID/时间/exit/超时/终止。旧run_td.ps1的TimeoutMin未落实，不能当deadline。exec yield不是超时。不杀他人TD/BW/hwserver，保留已有GUI/盘符。长命令执行者自身按沟通要求回报，主不监控。

## 有证据的纠正策略（实现归原开发）
B01第一步只做已定位编译纠正：tb_closedloop_writer_checker的全部rb_*与c_*声明必须先于实例/过程首次使用；将新增声明与memory行为过程分开，检查所有引用/重复/implicit-net，保持真实writer/DDR模型/checker联合结构。先复核符号/模块端口与ASCII映射，再执行下一次真实编译，保留第三次开始的唯一日志目录。不能跳过联合TB、改成回放或用standalone PASS替代。
编译通过后验证完整1080p CRC/length/words=648192、buffer持有不覆盖/释放、旧响应排干/新会话隔离、RID/RLAST/timeout/abort/复位错误与恢复；debug一次内部abort须证明拒发布和下good恢复。T09补适配器overflow等缺项与RAW隔离，保持真实三分支/独立oracle/负对照/全帧服务。实际功能失败由原开发最小修正并保存各次证据，利用新增有限机会完成原要求。
G1满足后才合并生产实现；不放松原时钟/约束/STA/CDC/资源、无宽泛豁免。诊断信号在最终网表保留，CWC完整BID物理覆盖与同源bit配对。必要工具故障不能伪造PASS。
T08后续第一纠正是将两处非法位置空输出连接改为有效命名端口等最小合法连接；先静态核对同模块全部端口与ASCII工作库，再真实编译。随后完整启动排序/24ms与8帧边界/ACK-NACK-timeout/故障恢复、SOF CDC/回绕/overrun/配对正负例及自身G2。所有行为目前未验，不能只修语法即ready_for_test。

## 输入历史、写范围与新冻结位置
本次恢复入口审计recovery01-input-audit.json：旧B01 manifest236项、旧T08 manifest26项均0漂移。实际生产HEAD b0282d2a...、基线dirty与现有部分改动必须保留。
旧candidate/manifest.json、sync-offline/manifest.json与旧development-report/evidence/日志、原dev-plan/guide/problem-ledger.json等保持不覆盖。它们代表恢复前partial状态，实施修改后其源路径可能有意变化，必须标historical/superseded而不能声称旧hash仍当前匹配。首次修改每个旧冻结源文件前，在本run recovery01/prechange/保存副本与原SHA；保存旧manifest字节副本、前后diff与改变输入清单，不批量删除。
新的B01报告、日志、scripts、manifest全部写recovery01/B01/；新manifest固定推荐recovery01/B01/candidate/manifest.json，含本次用户新增指令/本文件/实际所有源码、IP、约束、ROM、工具/参数/DB/报告/bit/CWC。新冻结后重新全量hash，停止所有活动才ready_for_test。
源代码允许写范围仍为原B01 whitelist（包含已有closedloop、algo、top/必要相邻接口、TB/filelist、新stage/专用SDC），不得改原保护IP/ADC/原SDC/旧stage/协议/另工作树/D盘工程。新输出只增recovery01/与必要本轮board最终清单，不提交既存dirty，不推送。
T08后续使用recovery01/T08/新报告/脚本/manifest，旧26项仅历史。T08保护的B01输入以届时最新实际合格B01新manifest为准，原规划派发前绑定准确路径/SHA；不能用已被合法恢复改动的旧236项作为静态当前源。当前B01开发禁止顺手改T08源码/报告。
工作流5.1适用项不变；真实硬件/曝光/G4/PCIe/RK边界不扩。

## 返回
B01 ready_for_test只回严格合同：task_ids、status、artifact_paths、manifest_path、test_input_paths、lessons_path、blocked/retest；两任务统一候选，逐任务integrated。若在本表新有限上限前仍有可验证纠正就继续，无需回用户确认常规修正。到新上限才回真实problem与逐项尝试账、恢复路径，不换ID。
