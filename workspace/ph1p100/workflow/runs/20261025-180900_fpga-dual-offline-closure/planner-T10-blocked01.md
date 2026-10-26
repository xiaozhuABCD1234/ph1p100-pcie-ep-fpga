# T10停止裁定01：保持blocked，不新增执行次数

依据原开发真实返回与本轮只读复核，T10.dual-aplus-scheduler仍为blocked，不具备ready_for_test条件，不派综合测试者。T08.dual-local-closure与其无技术依赖，原开发 `/root/fpga_dev_dual_local_180900` 继续原派发，不停止或重派。

## 已核实事实

- T10原开发真实ID `/root/fpga_dev_dual_scheduler_180900`；已停止修改、active_commands=0。
- `T10.dual-aplus-scheduler/result-r0.md`、`recovery.md`、`interface-map.md`、`development-state.json`、`problem.json`及`evidence/commands.jsonl`已读。
- `evidence/faults-retry/console.log`实际给出两条vsim-3533文件打开失败，metadata.csv/events.log路径被1024bit/128byte路径缓冲截断；该次TB_DONE、cmp4/rel14、Errors0/Warnings2。四份zlib文件存在不补足未记录的真实core metadata或事件统计，不能从期望值伪造。
- 首次faults在恢复帧发现premature-release断言，开发增加codec-only cleanup reset后第二次运行；该候选变化使此前正常场景证据需要重新绑定/重验。
- 开发实际native+worker工具调用37/60，compile3/4、case进程9/20；development-state的旧局部tool_calls_used=8不是总计，采用明确的actual_native_and_worker_tool_calls=37。时间起18:25:19、止18:37:39，为开发自报本地时间，不冒称完整仪表化墙钟。
- 默认1920x1080双路各一帧、最终普通/故障复验、变异负对照、RID/RLAST和身份边界及最终源/统计检查未齐。G0/G1不完整；G2/3/4 not_run；无独立报告/判定，不升级父T10。

## 合同裁定

稳定problem_id保持 `T10.dual-aplus-scheduler:LIMIT_REACHED:faults-retry-metadata`。同一个faults高层场景已首次+1次重试，不能借新的文件路径、相同case改名、checker整理机会、新角色/新run增加第三次。已有实际元数据不足，不能只做字节后处理而获得所缺硬件统计。没有用户新输入或外部条件变化，规划没有进一步执行授权，不自行扩预算，也不将补充机会当重跑机会。

本次只读裁定不计实际修复轮，round0尚未独立验收；正式包仍2，未新增包。problem机会不重置；这里没有向原开发消费补充机会，机会新增0。原始manifest/源码/证据/输入控制不改。

## 已准备的最小有界恢复方案（尚未授权、尚未应用）

继续真实原开发，局部修正其sim/make_tb.py的路径缓冲为字符串或已验证的相对路径，增加所有必需fopen句柄非0断言；重新生成/编译TB，绑定新manifest。只申请把本faults场景累计上限2改为3（额外1次）；其余原开发总60calls/90分钟、compile4、case20不变，不清零，剩余23calls、1compile、11case。先修测量工具，禁止改DUT或放宽门槛来弥补缺日志。若需要额外RTL修复、第二次额外faults复跑或再增任何上限，继续blocked交规划，不能预先承诺通过。

新授权后，在上述剩余上限内完成未运行的全尺寸、受codec-reset影响的正常场景及必要身份/RID/RLAST/负对照/源核验；所有旧失败保留，各次输出独立。无法在余额内满足则返回真实已做/未做，不改成not_applicable。停止/冻结后才为此任务新建唯一综合测试者；测试预算仍原45calls/60分钟，不因开发停止而耗用或接管开发工作。

准确恢复文本（需用户先明确同意上述有限新增执行次数）：

`$fpga-orchestrator 恢复：D:\fpga\ph1p100\workflow\runs\20261025-180900_fpga-dual-offline-closure；本轮目标：同意T10.dual-aplus-scheduler仅额外1次faults场景复跑，累计上限3；续原开发修正TB路径和文件打开检查，完成原范围剩余离线验证，其余预算不变、不清零，不执行TD或硬件。`

回退仍是暂不采用本隔离候选，生产/板候选未变。question-T10-retry-limit.md供主在用户可回答的边界原样转发；T08事件返回和原链继续，不把本次T10阻塞误作整个run结束。
