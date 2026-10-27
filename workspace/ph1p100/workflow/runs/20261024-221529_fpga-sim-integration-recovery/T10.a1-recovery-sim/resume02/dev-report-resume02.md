# 原 T10.a1-recovery-sim 续接02 开发交接

状态：ready_for_test；仅开发局部检查完成，尚未进行本任务独立综合 round0。原开发 `/root/fpga_dev_recovery_221529`，runtime=Codex。新候选只在 resume02 写域生成，全部历史r0/resume01及依赖包保持不变。

当前调度 dispatch-recovery-resume02.json、planner-resume02-recovery.md、recovery-dut-binding-resume02.json 为唯一来源。组合DUT直接引用该binding八项路径：top SHA 5d0f9a001747168db39e07a10cfa417a25be797ae4013d07c3990d623310772a；exporter SHA 0f3ae49ee19cc69348024e4fbe25cd3766dfec2cd8435f34f2b117bf313ba097；六项原始SHA不变。本resume没有修改或复制DUT。

## 新鲜矩阵与字节证据

corrected/old各一次全量编译，vlog均Errors0、Warnings0；本次编译2次，原任务累计4次达到冻结上限，没有增量/重编译。corrected为当前组合八项；old仅把top还原到原冻结输入，保留通过的exporter和其他六项。ModelSim Intel FPGA Edition10.5b、Python3.11.5、zlib1.2.13，工具身份在manifest按二进制SHA绑定。

新组合20项逐项实际执行一次，无旧日志、依赖包PASS或旧工作库复用，无仿真重试。全部CASE_PASS且独立严格字节检查通过；操作系统退出码并非唯一判据。共88包，其中80是当次恢复输入，合法前缀与恢复逐项分账。每项4good均恢复4包，最大10042个A1周期，门槛1000000。

|case|ratio|完整包|恢复包|FE后A1周期|合法前缀种子|
|---|---|---:|---:|---:|---|
|clean|slow-final|4|4|10041||
|clean32|slow-final|4|4|10041||
|raw-midwrite-reset|slow-final|4|4|10041||
|encoded-midwrite-reset|slow-final|4|4|10041||
|bad-frame|slow-final|4|4|10042||
|overflow|slow-final|6|4|10041|100,101|
|full-abort|slow-final|5|4|10042|100|
|pending-reset|slow-final|4|4|10042||
|sof-abort|slow-final|5|4|10041|100|
|last-skid-abort|slow-final|4|4|10042||
|clean|fast-final|4|4|10010||
|clean32|fast-final|4|4|10011||
|raw-midwrite-reset|fast-final|4|4|10011||
|encoded-midwrite-reset|fast-final|4|4|10011||
|bad-frame|fast-final|4|4|10011||
|overflow|fast-final|6|4|10011|100,101|
|full-abort|fast-final|5|4|10010|100|
|pending-reset|fast-final|4|4|10011||
|sof-abort|fast-final|5|4|10010|100|
|last-skid-abort|fast-final|4|4|10010||

slow: cam14ns / A1 5.333ns，phase1.7ns；fast: cam3.7ns / A1 5.333ns，phase0.91ns。clean32及两类中写reset为W32/H2、FIFO_AW4；其余W8/H2、FIFO_AW2。UART_DIV4、PREP/PRED1、HB_DIV0、ROI(4,2)、CAM_W=W+8/H8；UART与A1同net。RAW_BASE0、CMP_BASE131072均为256bit word地址。W32 RAW80B在真实store为4个字（每字20B有效）；压缩长度由每包头和实际流核对，不预设固定长度。

TB/model完全沿通过资产的激励和目标断言，源holding在stall保持、43bit真实FIFO token逐项有序scoreboard、abort sideband无像素、真实接受abort写读次数一致。新增audit_verify.py只读取本次证据，确认每例token_w==token_r、最终RAW两槽FREE、RAW/CMP非活动；故障观察时无WRITING遗留。bad-frame两个比例各真实RAW abort一次/drop至少1；last-skid分别命中last_abort_hits1并drop1；SOF碰撞分别命中sof_abort_hits1，碰撞帧不在允许源集合。所有错误/丢beat帧不输出，合法前缀凭SOURCE_END bad0且rejected_delta0判定，未把前缀计入恢复数。

两类reset通过已接受部分外部AW/W、尚未发布且WRITING活动的断言命中；计数及槽在reset断言期清零，恢复使用不同epoch种子。完整源RAW逐字节、标准zlib严格EOF/unused_data/unconsumed_tail、header/stream/transform/raw四CRC、唯一帧/源、零未知/重复/旧epoch字节/尾垃圾全部检查。

## 负对照与边界

原top实际重新编译并运行bad-frame slow，目标Fatal ABORT_ONLY_LOST_OR_SLOT_NOT_RELEASED命中，非编译/载入错误，也不是RECOVERY_BOUND_FAIL抢先。result为EXPECTED_REJECTION；旧负例的stats尚未产生完整good字段，所以通用包checker记录KeyError(good_sent)，有效性只按独立明确目标断言和原始trace判定，不以该解析错误充反例。其余七RTL仍是本次组合绑定。

17项检查器反例全部拒绝：尾字节、重复包、截断payload、合法CRC/zlib的旧epoch源、四项CRC分别破坏（其余头CRC按需重算）、合法CRC但zlib串接，以及八类故障各删除inject_hit。变异使用本次新捕获，在内存中生成；未改动正例capture。完整结果在checker-negatives-resume02.json。

DDR模型真实paired AW/W、周期stall、延迟AR/R，数据和已接受pending/held响应跨DUT reset保留，不隐式清空。两类中写reset的四次命中实际pending/rvalid均0：old-AR-at-reset状态为not_covered，未新增目标，不能外推所有复位交错。

## 来源、保护与工程检查

五个资产先逐字节复制，再记录copy-source-map.json及source-copy-adapter.diff。Windows文本写入把LF正规化为CRLF，故TB/model字节SHA变化；独立归一化比较确认内容逐字节相同，source-eol-normalization.json保存两侧换行计数。TB/model无刺激或断言修改；checker只改参考路径；runner改当前run/binding和原top负例路径；matrix runner仅改输出路径并将通过包历史19+retry选择改为本次完整20个全新场景，没有引用历史fast SOF成功日志。新audit_verify仅作本次证据和负例核验。

660项唯一保护路径逐项SHA前后相同；运行时声明核验729项（含重复绑定），drift0。包括本次全部规划控制/八RTL、108规划冻结输入、依赖包manifest绑定、原r0/resume01产物。复制前后源hash、当前被测输入与工具SHA均进唯一manifest；未声称扫描未列明的整盘文件。

每次编译/仿真实际subprocess300秒+TB A1/绝对时间watchdog；读取/静态检查均有Job60秒控制。25个本次子进程记录（4个vlib/vlog及21个vsim）全已wait，无实际超时、无他人进程操作。actual-commands-resume02.json保存argv/cwd/PID/退出码/秒数，case目录保存原始console/transcript/capture/trace/stats/WLF。实际最长进程6.375秒。精化均保留3条既有告警：u_cmp_store两个纯观察输出st_read_words/st_dup_words漏接及汇总端口数告警，非控制/时钟输入，未屏蔽。

功能/工程/系统局部门槛已形成新组合证据，正式判定交一个新独立综合测试者。G2=not_run；G3/G4/G5=N/A沿规划。TD/综合/route/bitgen/CWC/download/Flash/生产写回均0，无板级、1080p满速、STA/实现CDC/资源或长稳资格声明。无代理派生、删除、共享盘符或外部消息。

## 累计账与下一步

原账42calls、compile2、clean3、fault3、载入前失败1、实际修复0保留。本次最终18native调用（含冻结），compile2、clean4、组合fault16、原top反例1；原任务累计60native调用、compile4、clean7、组合fault19、原top反例1，实际仿真共27；载入前失败仍1、实际修复仍0。两个稳定problem机会分别1/0保持。execution-ledger-resume02.json按历史、本次、累计分账，不算新任务/第五包。

停止修改、所有活动结束后唯一冻结manifest-resume02.json，input_status=changed。主随后新派原恢复任务的一个独立综合测试者，重新编译和复跑20项、不同源/字节/槽判据及有效反例；不得拼本地或依赖包PASS。恢复入口为当前dispatch和本manifest。回退无需动生产或板候选，全部历史与新证据保留。