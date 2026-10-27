# 配置同步计划
plan_revision：2（新增显式Skill触发与规则正文展示；保留revision1全部限额）。原开发继续同一工作包，先读本修订与trigger-docs.md，保留已做改动并重新冻结；这不是实际修复轮，不增加任务/角色。
恢复附录：原DEV返回局部静态检查300秒超时、未冻结。已按稳定problem_id登记第1/最多2次返回补充机会，详见recovery-opportunity-1.md；只允许同范围一次纠正后的分段检查，300秒总限额及原角色预算不变，尚非实际修复轮。
恢复附录2：A/B已PASS，C的叶文件verbose输出额外断言口径错误已由原规划按Git官方文档核实；最后第2/2机会见recovery-opportunity-2.md。只复用已通过范围并完成剩余可见性/同输入绑定/冻结，当前候选不得修改，原数值阈值不变；同问题再返回即收尾blocked，不开第3机会。
task_id：CFG-SINGLE-TESTER-LIMITS；status：ready；batch_size：1。本轮只有此一工作包，一个开发、一个综合测试静态复核；必要时续原角色，不新增设计审阅、旧三测试或行为压力测试。

## 用户需求与保留边界
当前request.md保存全部用户原话。统一处理一综合测试、按风险选完整检查、细而有限拆分、主只看返回不监控、返回重复问题给予有限机会、展示规则正文与显式触发。保留主仅传输、规划理解/顺序/范围/验收、真实ID、同任务原ID修复、最多三轮实际修复、G层与任务状态分账、必要硬件门槛及原权限边界。仅配置，不启动FPGA任务。

## 显式触发补充（revision2，优先于旧自动入口）
直接采用本目录trigger-docs.md冻结方案及两条官方来源，不再调查/访谈。复用现有fpga-orchestrator，新增其agents/openai.yaml仅policy.allow_implicit_invocation: false；不建MCP服务或重复入口。根AGENTS、Skill description/正文、现行workflow入口同步为条件启用：明确调用Skill并要求执行/恢复才进入本套流程。标准写法是“$fpga-orchestrator 执行：需求”或“$fpga-orchestrator 恢复：原run绝对路径；本轮目标：目标”；选择器显式选择后明确执行/恢复同样接受。普通聊天、引用/解释/查看/比较/修改规则不自动启动本套角色链；仅提技能名不算执行意图。其他通用技能/工具及根项目通用约束照常适用。明确启动的同run按原授权继续，状态/规则讨论不另开新链；当前配置run直接续原开发，无需用户重新触发。
触发政策是配置/指令约定，不声称静态复核等同客户端真实加载验证。MCP适合真实工具服务，本轮不实现/安装/调用自造MCP；Skill与MCP选择理由附官方链接，详见trigger-docs.md。

## 冻结默认规则（开发落实到统一work-limits.md）
- 一次需求本轮只做1个主要可验收目标；最多4个正式工作包，ready/blocked/依赖包均计入，任务总数不因批准合批减少。仅两级：需求→工作包；包内操作是清单，不另建子任务/新代理。
- 每包一个主要可观察结果，通常一个模块、接口或文档主题及必要相邻引用，包内最多5项语义实现步骤。出现两个可独立验收结果、无关接口改动或需要第6项语义步骤时拆窄；修改多份同步引用/读取/改一行/哈希/跑命令等机械动作不单独开包。
- 超过1目标、4包或两级时，规划在首次计划中选依赖闭合的最小可交付切片（<=4包），按用户明确优先级，其次已有依赖顺序，再按需求出现顺序取舍。余项只留最多3条后续主题和原需求路径，不继续展开任务树，本轮不自动续做。无法形成小闭环则只交1个范围/接口冻结包，其余待后轮；不把范围冻结冒充父目标完成。
- 只有用户明确给出本轮新的有限目标数/任务数/层数，才可在dispatch记录覆盖默认值；“全部做完”、合批、时间宽裕均不算覆盖授权。不能用增大BATCH_SIZE、新run、自造子ID或重命名失败包绕上限。用户新需求改变边界时交原规划，不由主选范围。
- 每个新任务默认一个新综合测试者，与开发独立；按范围/风险一次检查相关功能、工程、系统项。文档/配置：语义、格式/入口/哈希、交接兼容；模型/软件：针对性正反向/边界及可复现性、相关接口；RTL/时钟/IP/存储/地址/板上行为：保留所需真实DUT、最终STA/CDC/资源/候选绑定及真实硬件/恢复/稳定性能检查。风险增大先增加检查/缩小包，不自动开多个测试代理；新增角色只由用户明确授权。必需项缺条件直接blocked，所有不适用须规划事先写理由。
- 成本选择：角色/上下文只用最小相关输入；综合tester按需读取旧领域清单；必要验证可复用同输入证据并写依据；一次检查避免重复重建。不得以节约为由免门槛，也不承诺具体token百分比。

## 主不监控与子角色防循环
- 主不轮询list_agents、不扫描目录/日志估计进度、不问进度/催促、不做超时后的反复盯控。只接收返回事件/完成消息与明确元数据；wait_agent仅等事件，单次<=60000ms，等待超时不产生检查、催促、故障或重试动作。真实ID从spawn返回登记；ID失效以实际工具错误交原规划恢复，不预防性探测。
- 每角色每次派发/续接默认最多30次实际工具调用；规划15分钟、开发/综合测试各45分钟的自我停止预算。本包采用该默认。计调用包括自己的命令轮询和worker调用；规划可在派发前按必需构建/长稳时长明确不同的有限预算和理由，运行角色不得自行扩预算，更不能因此扩大4包/两级边界。
- 单一未决问题最多3轮有目标的搜索/读取；同一失败命令最多首次+1次有新证据或参数纠正的重试。缺资料/工具/设备/授权/额度直接blocked；DeepSeek/API错误不自动重试，根AGENTS规则不变。不能改关键词/ID/目录绕计数。
- 连续2次工作循环没有新证据、实质产物变化、有效验证结果或可检查的假设收窄，主动停止并返回blocked；仅换措辞、记日志或重复同输入不算进展。达到工具/时间/搜索预算，或发现必须扩范围时同样停止。返回原因、已做/未做、最后实际结果路径、最小下一步和准确恢复入口，由原规划处理。
- 命令默认明确deadline：读取/搜索60秒，局部静态/仿真5分钟，FPGA构建30分钟；规划可在派发前针对必要工作冻结其他有限值。角色只跟踪自己发起的命令；不以exec的yield_time_ms冒充执行超时。启动前落实工具支持的超时/可安全终止机制；不支持且无法安全控制则返回tool_control_missing，不启动无界命令。达到deadline安全停止本角色拥有的进程，保留日志/退出信息并返回，不能杀他人进程。不要新建监控Agent、定时任务或常驻执行器。
- 上述为提示词/角色执行合同，并非平台保证的硬时限；失联且无返回时主不代替监控，不伪造blocked/PASS或称平台已自动终止。

## 收到重复问题后的有限机会（与实际修复轮数分账）
- 子角色返回problem_id（同任务同根因稳定，例如task_id:INPUT_CONFLICT:manifest）、reason_code、new_information布尔值、evidence_path、requested_action及resume_input_path。reason_code采用固定枚举：RETURN_FORMAT/INPUT_CONFLICT/SCOPE_CLARIFICATION/REPRO_DETAIL/TOOL_UNAVAILABLE/DEVICE_MISSING/PERMISSION_MISSING/API_ERROR/QUOTA/TOOL_CONTROL_MISSING/NO_PROGRESS/LIMIT_REACHED。相同问题换措辞、修复轮次或转交角色不改problem_id；真正不同问题由原责任角色说明不同证据，主不读长文猜身份。
- 主只在收到返回后，按task_id+problem_id登记最多2次续原责任角色机会；仅字段齐备、new_information=true、证据/恢复路径齐备且requested_action为原授权范围的补充/整理时可机械续接。信息真假/技术根因由责任角色核验，主仅检查元数据。
- new_information=false、字段缺失/矛盾、无法稳定归类或已给2次机会后仍返回同问题，直接交原规划blocked/备条件；规划也受同问题计数，不靠往返转交重置机会。到上限后仅真实新增用户输入/工具设备条件变化可由原规划明确恢复，不能自行再试。
- 设备、工具、资料、权限、API/额度错误等明确外部阻塞不走机会循环；不给自动重试/扩权。PASS/FAIL实际实现修复仍单独按round0、round1—3计数，不能把修复改名为“回答机会”绕三轮。以上机会只用于返回内容补充/整理，不由主提供技术答案或监控兜底。

## 最小修改范围
允许：AGENTS.md仅默认工作流段；.gitignore仅追加`!/.agents/skills/fpga-tester/`；下列技能及引用；workflow默认说明；当前run开发产物。
- .agents/skills/fpga-orchestrator/SKILL.md及references/relay-contract.md、report-contract.md、codex-calls.md；新增references/work-limits.md、agents/openai.yaml（仅关闭隐式调用；现有目录白名单已覆盖，不额外放宽.gitignore）。
- .agents/skills/fpga-planner/SKILL.md、fpga-design-guide/SKILL.md、fpga-dev/SKILL.md；新增fpga-tester/SKILL.md。
- 三个旧fpga-tester-functional/engineering/system的SKILL.md：仅历史参考定位/冲突调度无效说明及链接，不删专业检查内容、不删除文件。
- workflow/FPGA多智能体工作流_使用说明.md、workflow/README.md（默认入口/步骤和5.1第6项角色称谓，不改G层与硬件门槛）、workflow/AI协作与工具接入.md、workflow/AGENTS接入片段.md。README第5.1第6项的独立审阅和工程复核由同一综合tester依次承担，独立性针对开发者，无需额外审阅代理；AI协作文件的审阅职责同步标为综合tester的职责，不再暗示必开另一角色。
- 当前run开发可写candidate-manifest.json、dev-notes.md、candidate.diff、lessons-learned.md及自身静态检查证据。不得改request、规划文件、baseline、main-log、dispatch或测试报告；主/规划/测试各自维护自己的文件。
保护：删除禁令、完整DeepSeek块、生产源码/脚本/外部工程/任务板状态/其他dirty、旧run/旧证据、全局配置；不提交/推送/发布/下载硬件、不添加授权。

## 一个可验收工作包
| task_id | 产物/实际工作树 | 依赖/状态 | functional | engineering | system | G层/下一动作 |
|---|---|---|---|---|---|---|
| CFG-SINGLE-TESTER-LIMITS | 当前根内上述配置及新综合tester/统一限额规范 | 无/ready | 全部原话落实；单tester完整且按风险缩放；数值/触发/例外清楚 | 语法/链接/精确白名单/YAML显式政策/冻结哈希/差异范围/保护块 | 显式执行入口/非触发、派发返回、同ID修复、停止与有限机会合同一致；无自造MCP | G0/G1；原开发续→重新冻结→一个综合tester静态复核 |

开发可用4项语义步骤完成：同步显式入口/YAML；同步角色/派发报告；统一范围/停止与返回机会规则并链接；静态核对/冻结。多文件是一配置合同，不拆成逐文件代理；此前一目标/4包/两级/5步骤/30调用/时间/机会/修复阈值不变。

## 冻结与派发
开发停止修改后交本目录candidate-manifest.json，包含所有现行配置输入的绝对路径/SHA、工作树/HEAD/dirty、本包写列表、规划输入SHA及实际静态检查证据；candidate.diff只含本包范围改动。正式测试由一个新综合tester按本目录tester-input.md执行，与新技能自身条文冲突时本规划冻结合同优先。
主按dispatch.after_development直接一次spawn_agent(fork_turns=none)派`fpga-tester`；把实际manifest路径原样交其，不开旧三测试。当前新技能尚未存在为预期产物，不可现在派测。同任务FAIL续实际原开发/原综合tester；round0首次验收，最多3轮实际修复。缺外部条件立即交本run原规划，不空转。
停止/回退：范围冲突、保护块漂移、无法安全控命令或缺输入即停止；只恢复本包自行改动的配置原内容，不reset/clean、不覆盖既有dirty、不删除文件。配置包不提升任何父硬件任务状态。PASS后原规划核验报告/manifest、写handoff/final-summary/user-summary及workflow-rules-for-user.md；后者是可原样贴给用户的完整精简规则正文，含触发/非触发、全部具体限额、三维选项、主不监控、子自控、重复问题机会与实际修复分账、Skill/MCP选择及两条来源。主原样展示，不自行重写。本轮不再派其他任务。

