# T10 算法与压缩细节只读审查（round0）

本包完成五步审查材料，等待独立综合测试；未实施优化，也未签核被审查DUT。33个检查点覆盖计划语义簇，11项发现保留已知问题和证据缺口。唯一候选是本任务审查材料，不是新bit或生产实现。

## 分支与输入

源映射和SHA见source-map.json。b15 .al选changed-src的camera_a1_uart_top/a1_frame_top/a1_deflate_core，单A RAW捕获→DDR→feeder→A+→CMP→UART；与三算法没有串接。三算法在独立upstream CLOSEDLOOP_EN分支，Bayer10 sample lanes→demosaic RGB8→Gray8，然后Gray直接输出、Gaussian(Y8)、HE(Y8)并行，各自obuf与诊断sink。另一RAW/R10F PCIe分支不等于压缩已接通。BPR1/Rice是历史文档和另一Bayer工作树参考，b15编译不选；不重开旧codec。bounded Gaussian frame是原型，不能作为流式持续服务证明。

T02/T06已验manifest及报告分别重新核验，同输入资格见dependency-qualification.json。T02错误packed入口、晚CSI裁决与raw_id语义，T06发布顺序/写可见/guard无epoch/取消状态均继续保留。编码CRC/Adler和逆变换即便一致，也不证明传感器原像素或完整有效帧。没有重跑存储穷举，没有把默认调度成功例当作模块合同证明。

## 五步覆盖

1. C01—C04、C16与source-map分列当前A+/LZ77/DEFLATE、RAW变换旁路、历史BPR1/Rice及三算法；实际编译实例优先于10/15指南。prep0仍zlib，stored回退的是xform字节；不是整个帧无压缩RAW模式。
2. C05—C15覆盖Gray位宽和两级stall、Gaussian普通replicate与一次舍入、rowwin严格sideband、HE四bank/两级转发/首帧identity/前帧LUT/坏帧/原子发布/clear及空窗。Gray最大65408、Gaussian含舍入最大4088；HE24bit bank、26bit合并、32bit乘255在最大几何足够。HE全同灰常量帧den0采用identity。cfg只接收一次，动态模式并未实现，不能造一个切换测试声称已接入编码。
3. C17—C30覆盖2行块/奇数尾、plane anchor与10bit modulo预测、匹配长度3..258/距离1..2048、block tag和hash bypass、投机候选abort、fixed反码/extra bits/LSB打包/EOB、stored LEN/NLEN与尾零、32bit keep/精确长度、CRC/Adler覆盖、abort与描述符/恢复。发现详见下一节和findings.json。原始/变换/码流CRC分别在不同接受边界更新，Adler覆盖xform，不覆盖头或原始RAW。不能重算CRC给已错帧赋予good资格。
4. 自写witness/check_transform_contract.py复查15个软件向量/几何模式、两类非规范码流变异、abort布尔裁决、bit offset归纳与队列反模型、标量位宽/四lane计数。zlib标准库与另源strict inflater是不同解码判据；冻结a1_ref软件tokenizer与RTL hash/插入策略不同，未声称其字节等同真实RTL。没有RTL仿真或四帧矩阵。旧吞吐/资源按下节限定。
5. 标准review/checkpoints/findings/source-map/witness/commands/lessons、控制副本、依赖资格与局部核查齐备后停止修改，机械冻结唯一manifest-r0.json。正式三维结论由下一位综合测试者给出。

## 主要发现与资格

F02：最后字已valid并ready时，同时abort/重复SOF仍commit，源码明确让完成优先，与注释合同冲突。见证是源码锚定布尔真值，不是cycle-accurate RTL可达性测试；b15默认调度和板上是否触发未证。后续需要同时定义store发布、descriptor与取消优先级，不能只改一个输出信号。

F03：真实PC消费者的inverse_xform假定每plane长度可被4整除且总有四plane。W12H2 prep1错像素，W8H3/W16H3 prep1越界；W8H2和prep0为正对照。RTL GEOOK允许W4倍数和奇数H，因此不是这些向量本身违反RTL几何。旧expected_xform还对奇数尾生成额外零行，不能用它来否认RTL一行尾合同。默认1920×1080不触发该软件边界。

F05：码流追加00或stored对齐位置1，重算外层精确长度/CRC后，pc_decode全部布尔检查仍true，而strict inflater拒收。它证明实际消费入口的严格性不足，不证明RTL产生过非法流。损坏Adler的负对照被zlib拒绝，检查不是恒接受。

F04：若每块选择成本相对真实起始offset准确，ceil累计bit成本每块最多增加n+5B，因此1920×1080流长≤2,594,706B、32bit补齐2,594,708B、CMP槽2,594,720B。物理无效word lane不承诺清零，只认keep/精确长度。容量14B余量只在成本前提成立时有效。RTL在末尾操作入opq后可直接S_WAIT，而成本seed取已消费obits；未等待队列排空/未证明与opq_bit_off等价。符号off6+pending2的反模型可使比较偏大2bit；其真实RTL可达性仍未证明。本包将其列evidence_gap，不把宽松界2,594,841B反说成已发生溢出。存储没有硬容量截止的T06缺口因此不能忽略。

F11：16bit block tag在65536块回绕；1080p540块/帧约121.36帧、4.05秒@30fps。reset清valid不等于每次回绕清理；旧hash条目是否必然被刷新缺证据。需针对冷门hash跨回绕的真DUT或形式判据；本包没有可达溢出/错码反例，禁止把风险写成板上事实。

F06：Gaussian stream注释混入Bayer parity clamp，实际PARITY_CLAMP0普通replicate；HE当前14相位×256，仅LUTGEN已3584周期，大于注释约3.3k，尚加merge/clear。属于明确文档/预算过时，不主张改现算法数学。F07标量静态未见问题，RAM转发遇长stall、连帧/坏帧LUT版本及本域复位仍需真实DUT覆盖；不能用同bank纯软件计数代替。

## 吞吐、资源与G层

| 证据候选 | 可引用事实 | 保留限制 |
|---|---|---|
| P4冻结单核187.5MHz | C1合成slot-free Sss4,677,970；同内容strict-serial6,449,405；comp代理5,928,286 | R3随机raw为93.75MB/s sink受限；自然内容、最坏全内容、生产slot-free与双路未证。冷启动Lcold与稳态分开，proxy不是自然图。|
| P1080预算 | 每路77.760MB/s、6.25M周期；两路155.520MB/s；25%只是参考 | 不放宽硬门槛。A+理想最坏输出77.84118MB/s，双路155.68236MB/s，外头另计。RAW20/32 DDR搬运及四次读写沿用T06，不能按压缩比抹掉。|
| b15旧诊断 | 原报告G2 reported pass，SWNS+0.012ns，ERAM+CWC102/300 | 仅诊断薄余量；完整CDC/实际MC/生产双路不因此通过。G3旧下载/150秒观察仅reported observation；G4 blocked H4_UNRESOLVED、enc/exported0；G5生产稳定性not_run。|
| upstream旧T09集成 | 原报告选定内部STA+0.100ns、ERAM200/300及full1080p算法模型服务 | 属另一manifest/DB/时钟与实现版本；不能拼到b15或当前2级Gray/8slot副本。G3原计划不适用该离线包，G4原报告not_run/deferred，G5依原报告不适用；生产板级仍未证。|
| 双核旧231/289预算 | 来源索引可引用 | assumed_from_single_core，共享PAXI及Routed unproven，不是当前资源/时序实测。|

本轮G0是审查工作流接口，G1是离线见证；性能名为P1080。新G2/G3/G4/G5执行not_applicable，事先理由为只读、不改RTL/时钟/IP/约束、不交新bit、不签核硬件。未执行TD/bitgen/CWC/COM/JTAG/Flash/板卡/RK，不代做b17或143924活动线。

## 优化、复核入口与回退

正确性优先：F01输入真值与最终裁决→F02取消原子性→F03/F05实际消费者边界→F04/F11最坏成本及字典回绕证明；可观测性保持raw_id/cmp_id/capture_seq/epoch区别；持续服务/资源由F09保留后续门槛。只给有依据的收益与验证，不报虚构百分比。

F10仅建议未来收口构建白名单/来源文档。raw/xform/stream/header CRC与Adler消费者和故障模型不同；row banks提供重叠/多端口，obuf解耦不同sink，不能直接删。所有“删除候选”都要求消费者、故障模型、接受事件、所有权、恢复等价及综合网表差分；当前没有删除建议可立即执行。

局部执行见commands.json与本目录native stdout/stderr；统一baseline287项和已验T02/T06全部manifest项重新核对。首个根/角色短读已在1.2秒完成但没有显式Job deadline，后续全部读搜使用60秒自有Job；最初大批输出有截断，之后定向补读，未当成完整语义证据。生成器初次因obuf引用尾行88超出实际83而停止；见证初次因将decode_stream返回的(frames,off)当frames而停止。依据实际行数/类型各纠正一次，原失败日志保留为attempt1；不属于DUT实测失败。DeepSeek仅有界算术建议，其错误/过松推断拒绝，详见deepseek-review.md。全部补充源复制前/后/副本SHA一致。

测试者须用不同判据复核全部高风险F01/F02/F03/F04/F09/F11及其余引用，不以运行本见证本身代替独立验收；建议另写时序/几何oracle及offset状态解析。没有生产变更需回滚；发现审查结论错误时保留本轮证据，在新修复轮改本包并重冻。父T10、未验T11及整链路/硬件仍不关闭。

补充合同限定：HE自身的good_evt只核对总beats/rows及EOF/EOL，不独立检查每行长度或active重SOF；严格几何依赖前级rowwin/demosaic。F07 no_issue_found限定为已列标量/静态条件，不能外推任意独立畸形HE输入。

## 20261026-195235 恢复与冻结补充

用户在usage limit后明确“接着做”，续原开发、原任务、round0，实际修复仍0；没有新建替代角色或重跑非幂等prepare。旧controls/dispatch.json保留原开工合同；恢复派发/用户授权/规划说明/账户只读快照另存controls下带日期副本，recovery-control-bindings.json绑定它们。账户快照仅为恢复时条件，非未来可用性保证。

worktree-after.json和prepare-stdout.txt中的TRACKED_STATUS_UNCHANGED=False原样保留。前后均801项tracked状态，但字符串哈希不同；本角色不能据此归因并发修改或编码表现差异，也不把它改为true。实际写命令/脚本仅指向本任务目录；没有reset、覆盖或删除他人成果。统一baseline与已验依赖内容逐文件SHA再次一致，输入快照资格见recovery-verification.json。当前全仓库内容是否由其他角色改变不由本审查宣称。

恢复前开工UTC未单独落盘；首份任务文件09:05:19 UTC、最后只读记录09:49:42 UTC，不能据此证明原45分钟全部合规。原调用与首次失败证据保留，恢复按规划新增30调用/45分钟派发自行停止，不重置同一失败命令/搜索/实际修复计数。原build/witness各首次失败后一次纠正重试，prepare一次成功；本次只校验/绑定/冻结，不追加重试。

冻结前所有本角色自有native工作均已有退出记录、无待执行worker操作、无构建/仿真/硬件进程；随后只机械创建活动结束记录及唯一manifest。ready_for_test只表示审查包可供独立测试，不表示审查PASS或DUT通过。
