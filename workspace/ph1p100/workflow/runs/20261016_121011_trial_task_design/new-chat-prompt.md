# 复制以下文本到同一项目目录的本地新对话

请实际执行本项目既有多智能体工作流的两任务离线试运行。先读取根AGENTS.md和`.agents/skills/fpga-orchestrator/SKILL.md`。本项目根为`C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道`。

交接设计在`workflow/runs/20261016_121011_trial_task_design/`，请主智能体仅将其中`request.md`、`dev-plan.md`、`fpga-design-guide.md`、`input-index.md`路径交给真正派出的fpga-planner规划者技术核对；主可以读取dev-plan调度。这是新run的跨会话文件交接，不是resume旧代理。

创建一个新的`workflow/runs/<本次上海时间戳>_offline_trial/trial-artifacts/`作为OUTPUT_DIR；BATCH_SIZE=1。把本需求保存成该目录内request.md，所有新文件（计划、main-log、源码、manifest、测试向量/输出、报告、lessons和交接）只能写在这个trial-artifacts目录内。生产主目录、parallel现有源码、其他worktree及旧设计run只读。不要改workflow/tasks.json或把父任务置done。

任务A（批1，T03.trial-A）：复用现有R10F字段/CRC/RAW10样例，新增严格非压缩接收验收器、文件CLI和正常/异常回归。合法packed/u16样例恢复完全一致；未知codec/版本/格式、坏帧标志、非法phase、几何/长度/CRC/填充/保留字段/样本越界全部拒收，拒绝帧不得发布pixels。交付可复跑入口、fixture、错误原因和证据。

任务B（批2，T03.trial-B，引用T04核心）：A三维PASS后，新增隔离BPR1载荷封装/解码adapter与回环runner，复用`C:/Users/czz/.codex/worktrees/bayer-codec-reference/FPGA创新设计赛道/tools/bayer_codec/codec.py`，不复制重写codec。明确36B内头、内层精确长、外层32B对齐长、原始长度及分层CRC；交付压缩/RAW回退/混合行回环与异常拒收，包含原长大于压缩传输长的情形。扩展仅为trial profile，不宣称正式FPGA/RK协议已冻结。

两项各约1—3小时只是规模预算；需要真实新增可验收工具，不能只跑现有命令，也不扩为整机研发。优先Python标准库，禁用外部源目录的字节码写入；所有临时文件/测试日志保留在新OUTPUT_DIR，拒绝覆盖，不删除文件。

必须真正使用spawn_agent/followup_task/wait_agent/list_agents：主只调度→一个规划者→每批一个开发者→功能、时序与工程、上板与系统三个测试者并行。开发按两批串行，各批冻结且停止修改后才三维并行测试，每个测试者覆盖本批全部任务。角色按对应项目技能执行，不递归派生代理。记录工具实际返回ID；主不开发、不跑测试、不读完整源码/测试报告，只收路径/ID/PASS或FAIL及阻塞状态。

round=0为首次验收；有真实缺陷时复用本批原开发者/测试者修正，最多1—3轮。不要制造实现失败凑轮次；负向测试数据允许明确注错。三轮仍未通过保留⚠，A未过则B保持依赖blocked。每轮同一冻结manifest，不能拼接不同版本PASS。两批完成后统计首次/各轮通过、未通过和待条件数量。

本次不接D盘/TD/ModelSim/板卡/真实DMA，不改位流、RTL、IP、约束，不提交/push或发布，不停止/发送消息给其他聊天。三测试角色仍保留，但按纯软件范围：功能检查数据/拒收，工程检查输入SHA/标准库/复现/写入边界，系统检查CLI/元数据/回环/坏后好恢复。G0/G1适用，G2—G5硬件/整机层按计划明确不适用，不能声称板测或硬件吞吐通过。

我准备自行停其他聊天，这不代表它们已经停止。规划者开工只读重新核对worktree、dirty状态及已有实现，冻结复用输入SHA；若已有等价成果，复用并只补最小缺口。外部codec路径或哈希变化要核对后重冻，缺失则B blocked。不要追赶并发修改、合并别人的成果或覆盖文件。若本次多智能体工具不可用，明确说明并保留待调度计划，不能让主智能体包办。

请从新run规划阶段开始，按两批顺序推进至完成或真实阻塞，并给我产物入口、每批三维判定、修正轮数和未测边界。
