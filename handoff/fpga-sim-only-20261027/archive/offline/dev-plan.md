# 离线并行交付计划
实际根 D:/fpga/repos/ph1p100-pcie-ep-fpga；原话及优先级见 D:/fpga/repos/ph1p100-pcie-ep-fpga/workflow/runs/20261027-060708_fpga-parallel-offline-delivery/request.md；BATCH_SIZE=1。一个主要目标：完成与活动板级线隔离的 FPGA 离线接入证据与真实收益准备，三个正式包、两级、各最多5步。三个需求由用户明确指向，但不据此增加主目标数/合批。当前前两包ready，可并行；第三包准备动作ready，真实输入门blocked。并行不表示共用开发或测试者。

## 最小计划表
| task_id/父任务 | 问题/产物 | 实际工作树/允许写路径 | 依赖 | functional | engineering | system | 必要G层 | 状态/下一动作 |
|---|---|---|---|---|---|---|---|---|
| T03.pcie-byte-replay（涉及T11） | 当前槽/描述符实际字节定位+规范离线补头/严格回放包 | 本根，仅 D:/fpga/repos/ph1p100-pcie-ep-fpga/workflow/runs/20261027-060708_fpga-parallel-offline-delivery/T03.pcie-byte-replay/** | 固定P2/现有pusher、b18包；不等P4时序 | 长度/4CRC/逆变换/尾零/身份与负对照 | 字节证据源SHA、真实P2仿真、脚本可复现 | 缺口责任清晰，不冒充真实PCIe，旧decoder兼容 | G0/G1/G5；G2不在软件/TB新增范围，G3/4 not_run | ready，新开发→本任务新综合测试 |
| T08.freerun-isolation（涉及T06） | 复用旧真writer隔离源，新增不可反压双路忙/满/恢复矩阵TB及结果 | 本根，仅 D:/fpga/repos/ph1p100-pcie-ep-fpga/workflow/runs/20261027-060708_fpga-parallel-offline-delivery/T08.freerun-isolation/** | 固定T08 mode-fix02；不等T03/P4/H | 自由运行、整帧丢弃、A/B身份/CRC、恢复 | 真源编译精化、输入SHA、静态域/地址、缩参明示 | 非覆盖/全字段release/模型边界，无曝光/实时冒称 | G0/G1/G5；G2因无RTL改动仅not_run，G3/4 not_run | ready，与前包可并行；新开发→本任务新综合测试 |
| T04.real-raw10-benchmark | 合格真实RAW10收益基准（先交可执行输入门/统计工具与缺项清单） | 本根，仅 D:/fpga/repos/ph1p100-pcie-ep-fpga/workflow/runs/20261027-060708_fpga-parallel-offline-delivery/T04.real-raw10-benchmark/** | a1_ref/严格decoder；真实输入门当前缺失 | 已有正确编解码+输入鉴别、真实结果缺则blocked | 有限runner/manifest/provenance/稳定统计口径 | 实拍/合成/历史不混，软件与硬件不混 | G0/G1/G5；纯软件G2不适用，G3/4 not_run | preparation_ready；实测blocked，待前两包开发释放槽位后单独新开发；若仍缺资料冻结并blocked返回 |

## T03.pcie-byte-replay（5步）
1. 核对固定P2/P3 manifest/源码与根真实pusher的路径/字节单位、槽存储和元数据；在本包记录source-binding与slot→descriptor→backend责任图。活动P4只读协议作缺口依据，不能引用其浮动RTL跑正式候选；若必须读取P4特定冻结源则先向原规划返精确需要。
2. 新建runner/TB，实例化真实只读P2（及必要真实后端时只读根pusher），捕获实际输出描述符与slot流。最小证明P2 align(zlib)而非align(44+zlib)、当前无头插入责任归属；未接上的后端写明确missing。禁止用Python生成的A1U1文件假装DUT已输出带头帧。
3. 实现离线reconstruct/replay工具：对精确zlib+明确metadata补原44B A1U1头，输出本指南四文件和expected.json/短步骤；b18真实历史控制加至少一个正确自生小几何向量，区分标签，不增外部协议。
4. 正向/定向负向：四CRC、header版/保留位、截断、非零尾、extra zlib、raw/xform长度不符、错camera/session sidecar、容量不足。至少覆盖zlib_len mod4096在0与4053..4095会因44B改变dma长度的边界（合成长度夹具只能测封装，不能冒充真压缩）。
5. 本地检查、保存原命令/rc/结果/真实假设、字节责任表和handoff，冻结manifest-r0.json/result-r0.md/lessons.md/测试入口；停改返回。

验收：每个有效case 0字节差异、4CRC全匹配，严格zlib/逆变换一致；每个非法case必须非零退出或明确reject；P2描述符有真实RTL日志；未实现头/尾/身份字段写缺口，测试判定仅本离线包，不把“发现硬件缺口”伪装“已补硬件”。独立测试者自己解析一次header并用交接包strict inverse或不同oracle解码一次，变异负对照命中；全部manifest SHA前后0漂移。真实PCIe/TD/板测均0，不因未连pusher构造虚假整链路PASS。

## T08.freerun-isolation（5步）
1. 从checkout快照核对固定旧T08 manifest/source SHA，复用其真实候选/顶层与必要TB结构；在本包重写绝对sources映射、runner与独立库，不写旧run，不重做其已过的同步/I2C或另造writer。
2. 新增持续不可反压CSI源驱动/独立字节oracle，源计划不引用ready；保留真实checked CSI/writer/slot/mailbox/consumer互斥，DDR/消费者模型明确标环境。允许只读hierarchical观察，不force内部功能网来掩盖丢帧。
3. 构成至少6个主题case：同拍SOF、A早/B晚、B早/A晚、消费者忙跨每路>=3个新SOF、四槽持有/满后继续SOF、错误会话释放后恢复；每个busy/full用例观察每路至少6帧或超过两槽容量；恢复每路>=2个完整good发布/校验。
4. 建议加入至少一项移交接口一致性断言，把每路发布/选择/全字段release映射到P3同名语义；不需要合入P4或重新跑旧case全集。输出camera/seq源表、发布/丢弃/恢复/峰值占用矩阵；被丢帧pub=0、持有内存不变、错release=0有效释放、源时序与预定表一致。
5. 跑局部真实RTL编译/定向矩阵、默认几何容量静态校核与模型边界说明；唯一manifest/result/短步骤/lessons冻结并停改。

验收：0身份/CRC/样本错、0held槽覆盖、0被拒帧发布、每路源实际送出的组/标记等预定表，恢复达>=2 good/路；drop数和seq缺口逐一可解释。独立测试者自写一个更长busy或改变相位/错误release的变异检查，可拒绝“让源等ready”的假驱动或破坏camera的负对照。真实DUT不得变为stub；若旧路径不能满足新主题且需要RTL改动，返回blocked/原规划决策，不在TB代修。

## T04.real-raw10-benchmark（5步，输入门不能绕过）
1. 对input-index列出的本地可用来源做一次有界inventory，写provenance表与accept/reject理由；b18必须标source真实但sensor像素oracle未验证，不纳入real-summary。不得全盘搜索、外网抓大图集、安装依赖或拿N/L标签自证。
2. 新建只读参考模型的benchmark runner与输入schema，支持packed RAW10及明确声明的u16→10bit规范化，check W/H/stride/0..1023、SHA/provenance、未知相位模式；失败拒绝。用合成正反向控制检验工具，结果类别synthetic_control。
3. 合格真实输入存在才执行明确模式的a1_ref编码、严格DEFLATE+独立逆变换逐byte核对；输出原始SHA/长度/比率/双回退比例/含头与对齐开销。至少三幅才叫有限真实图集；单幅只写单样本。
4. 生成CSV/JSON和自含报告：qualified_real_count、blocked_inputs、model标识、真实样本统计与controls分表；无合格输入必须ratio=null、benchmark_result=blocked，给准确所需原始路径/格式说明/正确性依据，不伪造。
5. 保存可执行命令、result-r0.md、lessons、输入manifest并停改。若缺输入按blocked元数据返回原规划，不申请综合测试PASS；已实现工具由原规划决定是否以该包partial状态安排有限工具核验，不把父收益结果置完成。

本包最终真实收益PASS门槛：真实样本来源/格式/正确性门通过、全部往返0差异、回退统计可由独立strict parser重算、各比率可重算且候选绑定无漂移；不设置凭空收益下限（如无收益如实报告），不声明RTL硬件吞吐或H/AH收益。

## 共享执行与预算（派发前冻结）
默认每个新任务独立新dev、新integrated tester，BATCH_SIZE=1；同任务修复续原二者。并行只限包目录互斥写，测试/开发均无run根控制文件写权。允许T03/T08同时开发；T04只在一个前述开发槽位释放且未超主并发容量时新建，不能借批共用角色。主不读技术材料、不轮询角色、不催促；只接收事件并按dispatch机械传输。

T03/T04：每次角色turn<=30工具、开发/测试<=45min；T08：开发/测试各<=45工具/75min（派发前有限覆盖：旧真源闭包约81文件、独立映射+compile+6主题case/负对照需要超过默认30工具，避免半途未冻结；不增搜索/修复数或TD）。规划本次仍<=30实际工具/15min。每个实际命令有可执行deadline：读取/搜索60s、局部编译/仿真300s，runner用子进程timeout并仅终止自身进程树；yield不是timeout。T03最多2次compile/8次定向case进程，T08最多2次compile/8次case进程/每进程300s，T04最多6次批处理runner/单进程300s；不满足预算先冻结blocked。一个失败命令首次+有新证据纠正一次；同问题搜索<=3轮；2轮无实质进展停止；最多3轮实际修复，round0初验。
TD/synth/route/bitgen/CWC/硬件/COM/JTAG/Flash/RK写入/外部消息/安装/commit/push=0。不得批量删除或包装删除循环。DeepSeek仅最小有界辅助，project_root必须本checkout；本规划未委派低风险转换，因为当前任务是范围/架构判断。

## 产物与职责
各包开发：source-binding、源码/TB/runner/fixtures/expected、commands.jsonl、result-r0、handoff、lessons、manifest-r0（所有参与文件SHA、工具、参数、边界；stopped_modifying=true、active_commands=0）。综合测试者：D:/fpga/repos/ph1p100-pcie-ep-fpga/workflow/runs/20261027-060708_fpga-parallel-offline-delivery/test-reports/<task_id>-r0-integrated.md 与其同名目录，唯一首行判定、三维/G层、独立oracle、负对照、前后hash。未完成门槛FAIL并区分not_run/blocked，外部缺项不空转修复。

原规划收回报告后更新本run dispatch/records/<task_id>.md、handoff/final-summary/user-summary及准确恢复文本，不改旧主任务板、根生产或旧run。父T03/T08/T04/T10/T11均不因离线子包完成置done。需要全局板同步只交新增run证据路径，后续另授权原维护者处理。
回退：停止采用本run独立产物；旧候选从未替换，无需删除。剩余最多三主题：①板级补头/元数据与真实PCIe接入（原P4后续线）；②自由运行暂存与生产系统接入/时序/真实曝光；③合格实拍图集及硬件压缩收益。不得自动扩大到这些硬件任务。

