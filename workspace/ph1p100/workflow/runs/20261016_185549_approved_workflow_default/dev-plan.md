# DEFAULT-RELAY-V2：已批准逻辑的项目默认配置同步

状态：complete（配置同步及三维静态复核完成）。BATCH_SIZE=1，仅一项配置任务。输入为同目录`request.md`及本计划中的已批准规则；不重新设计、不再核对原图、不执行旧试任务或试跑完整工作流。

PROJECT_ROOT=`C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道`。
OUTPUT_DIR=`PROJECT_ROOT/workflow/runs/20261016_185549_approved_workflow_default`。
主只读`dispatch.json`并转发路径；本详细计划由开发和三测试读取。

## 必须同步的批准规则

1. 主Agent只原样转发用户原话、路径、真实ID、判定和状态，机械保存需求/日志并执行固定分支；不理解技术需求、不选题/设计/拆任务、不读原始材料/完整计划/源码/报告、不开发/修复/跑测试、不判断根因/复测影响、不写技术总结。保留系统要求的权限与路径范围检查。
2. 规划Agent读材料理解需求，拆可验收任务，确定依赖/顺序/修改范围/三维验收/工具设备/停止/回退，写用户问题和简短dispatch；主不从dev-plan选任务。PASS后原规划者更新任务和dispatch；三轮后仍FAIL或阻塞时也由原规划者决定后续可运行任务。
3. 默认每任务新开发Agent、新三测试Agent；同任务FAIL才续接原开发/测试。只有用户明确指定批大小>1，才由规划者定义批，每批一个开发者、三个测试者各覆盖全批。角色不跨任务复用对话；必要成果只传明确文件路径。
4. 三维仍functional/engineering/system，适用G层由规划预先限定。冻结同一输入、开发停止修改后再三测试并行；只回任务/维度/PASS-FAIL/报告路径/阻塞及续接元数据。详细内容留文件。round0首次验收，最多1—3轮实际修复；缺设备/工具/用户输入直接交原规划者备条件并原样转用户，不空转三轮。
5. 复测影响由开发/测试给清单，主不判断；不拼不同输入PASS。缺输入、疑问、状态矛盾回对应原角色；范围/验收问题归原规划，复现/报告问题归原测试，实现问题归原开发。用户反馈保持原话，主不重解释。无效或过长返回交原角色整理，不由主解析长报告。
6. 原规划者收尾，读判定矩阵/报告路径/轮数，写本轮任务记录、handoff、final-summary及用户短总结，主原样转发。经验由开发写lessons。run内控制文件不替代全局任务板；本配置任务禁止改全局任务状态。
7. 使用实际spawn_agent/followup_task/wait_agent/list_agents/send_message，真实返回ID即时登记，fork_turns="none"传技能和输入路径；collaboration直接调用，不放functions.exec。send_message只送消息，空闲角色新轮用followup。原会话能续则续；跨会话失效交规划者文件恢复、记录新旧映射，不假称resume。无多agent工具不得主接管。所有子角色禁止递归派生。
8. 保留不批量删除、不覆盖无关修改、有限DeepSeek低风险辅助边界；DeepSeek不能替代三个测试。不得扩大下载/Flash/发布/外部消息授权，不改全局配置。

## 开发写范围及步骤

以下均相对PROJECT_ROOT，未列路径只读；在现有工作树修改，先核对dirty/并发变化和路径，保留他人改动，不提交/push、不删除。

- 根`AGENTS.md`：仅`## 后续任务的默认工作流`段；其前删除禁令和完整DeepSeek块逐字保留。
- 七技能的`SKILL.md`：`.agents/skills/fpga-orchestrator/`、`fpga-planner/`、`fpga-design-guide/`、`fpga-dev/`、`fpga-tester-functional/`、`fpga-tester-engineering/`、`fpga-tester-system/`；允许同步其references。设计指南是配套技能，不新增常驻角色。
- `workflow/FPGA多智能体工作流_使用说明.md`、`workflow/AI协作与工具接入.md`、`workflow/AGENTS接入片段.md`、`workflow/README.md`：只同步默认入口/角色/调用/交接约定，不改硬件技术门槛和DeepSeek权限。
- 本OUTPUT_DIR：实现说明、候选manifest、三报告、lessons、handoff、final-summary和用户短总结。

不得修改生产RTL/IP/约束/模型/parallel、`workflow/tasks.json`、其他工作树/聊天、旧run和历史证据、D盘工程、全局设置。此前旧规划文件仅历史，不作为本轮新增范围或试跑要求。

执行：按以上8条同步全部入口，去除“主读详细计划/选题/排依赖/写技术收尾/任意FAIL自动三轮”等冲突文字；用简短dispatch/返回字段集中约定固定分支，保持现有报告首条`### 判定：PASS/FAIL`。保留已有FPGA规范，只按任务相关范围读材料，配置包不强制读取生产源码或跑TD/板测。开发做必要静态自查，写`implementation.md`和`candidate-manifest.json`（列实际候选文件SHA及保护检查），停止修改后仅返回任务ID、冻结路径和状态。

## 三个配置静态复核（不试跑完整逻辑）

| 角色 | 必须复核 | PASS阈值 |
|---|---|---|
| functional | 以上8条在入口/七技能/说明中一致；需求理解拆分归规划；默认新任务新DEV/TEST、FAIL原ID、三维并行、blocked不空转、用户原话、规划收尾；无主职责回流 | 必需规则无缺失/矛盾；不降低必要验收、不伪造通过 |
| engineering | 七SKILL frontmatter/name/description、链接/路径和调用模板；实际工具参数、fork_turns none、直接collaboration调用、真实ID留档；同候选manifest；保护文件/根AGENTS前缀 | 格式和本地链接可解析；无虚假可执行参数/缓存猜ID；未改受保护范围 |
| system | 项目根AGENTS新聊天默认入口→主技能→规划派发链；旧可选片段/角色说明无冲突；新聊天只在本项目生效；恢复/无工具/权限/外部动作边界清楚 | 静态入口可达且一致，无主接管/递归派生/扩大权限；明确此次未实际创建新聊天或运行完整工作流 |

报告：`OUTPUT_DIR/test-reports/DEFAULT-RELAY-V2-r0-<dimension>.md`，首条唯一判定；修正轮新建r1—r3报告，旧报告保留。三者读同一manifest独立静态复核，向主仅回判定/路径/阻塞及续接元数据。G0配置合同/G1静态一致性适用；G2—G5硬件/整机不适用，因为只改文档配置。

真实配置缺陷交本任务原开发者修复、原测试者按影响清单复核，最多三轮；外部条件/额度不可用直接blocked，不自动重试或主接管。发现并发改动、范围/验收矛盾回原规划者，保留现场；回退只准备本轮具体文件差异，不自动reset或清理。

三维完成后原规划者依据结果写本OUTPUT_DIR的handoff.md、final-summary.md及user-summary.md，写清仅配置静态复核范围和未运行项；主原样转发用户短总结。不更新`workflow/tasks.json`或把FPGA父任务置done。

## 本轮最终状态

DEFAULT-RELAY-V2在round0首次静态验收三维均PASS，input_status=same；共同候选为本目录`candidate-manifest.json`，SHA256=`2b81f3b9c65f28cc30bf2cb3f7e65a47ef54cddb1c5595b39cf368e873d3cc14`。实际修正轮数0，blocked=0，⚠未通过=0。报告为`test-reports/DEFAULT-RELAY-V2-r0-{functional,engineering,system}.md`。

原规划者已据判定矩阵及三报告收尾，产物为`handoff.md`、`final-summary.md`、`user-summary.md`；dispatch改为仅转发用户短总结，无下一开发/测试动作。本次收尾只更新run控制状态，不修改已验收的16个候选配置、冻结manifest或全局任务板。报告与manifest记载的是验收时输入；run控制文件的收尾状态不能当作候选配置漂移。

配置已成为本比赛项目后续本地新对话的默认入口；三维PASS只证明配置静态范围。完整工作流行为、实际新聊天加载、旧两项试任务及FPGA/硬件操作均未执行。
