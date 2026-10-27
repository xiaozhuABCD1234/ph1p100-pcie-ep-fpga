# 本轮唯一综合测试者的冻结输入
plan_revision：2；追加显式触发静态验收，原限额与原检查项不变。读取trigger-docs.md官方依据与冻结入口合同；当前request、计划与指南必须重新哈希绑定本修订，不能沿用revision1输入PASS。
恢复附录：原DEV曾在冻结前300秒静态检查超时；恢复合同为recovery-opportunity-1.md。正式测试只接收之后完整冻结的manifest及实际新检查证据，原timeout不得当通过；恢复附录和本输入需绑定新manifest，独立测试仍按本清单完整复核。
恢复附录2：读取recovery-opportunity-2.md及Git官方依据。原C的check-ignore exit1且空输出不是被忽略，不要求叶文件verbose打印目录否定行；以真正not_ignored及Git精确可列出结果判可见性。原失败证据保持，复用A/B/C已通过项须有相同输入绑定。本测试仍独立执行原全部适用静态复核，不以开发自检代替正式判定。
任务：CFG-SINGLE-TESTER-LIMITS；round0；只做静态配置复核，不派生代理、不改候选。
你是与开发独立的一个综合tester。读根AGENTS、当前request.md、本目录dev-plan.md与fpga-design-guide.md、本目录config-baseline.json、开发返回的candidate-manifest.json/candidate.diff/dev-notes.md，再读新`.agents/skills/fpga-tester/SKILL.md`及涉及的现行配置。新技能是待验产物，本文件与规划合同优先，不能让错误新条文缩减验收。
默认预算：30次实际工具调用、45分钟；读/搜索deadline60秒，局部静态检查5分钟。遵守dev-plan防循环/机会合同，自己有限执行和主动返回。不能让主监控自己，不运行生产/旧试任务、TD、硬件或行为压力测试，不另开审阅角色。

## 必须逐项复核
1. functional：三条用户原话都落实；一个综合tester承担相关三维，必要门槛/不适用理由保留；一目标/最多4包/两级/最多5项语义步骤/超大需求切片及余项边界完整，禁止batch/newrun/ID重命名绕限；机械动作不派独立代理；例外有有限值及授权来源。
2. engineering：manifest文件SHA实核、输入未漂移；本包修改清单/差异只在允许范围；AGENTS工作流段之前的原字节SHA与config-baseline一致，DeepSeek块/删除规则保留；.gitignore只加新技能精确目录白名单，`git check-ignore -v --no-index <新SKILL路径>`及跟踪可见性正确；Markdown相对链接实际存在、JSON可解析、技能frontmatter名称/路径一致。旧三个技能仍在且明确仅参考，专业必要检查未丢；旧并行/角色/报告语句不能覆盖当前合同。
3. system：AGENTS、orchestrator、planner/dev/newtester、relay/report/codex-calls与workflow当前入口/流程图/模板一致；默认spawn_single_tester逻辑一次原生spawn，dimension=integrated与一份报告/三维结果、同ID修复/证据复用/blocked/G层分账、scope与停止规则链接一致。main不轮询/扫描日志/催促，wait超时无检查动作；子角色数字停止条件可执行且不声称平台硬限；返回problem_id/reason_code/new_information及最多2次收到返回才触发的机会，与修复1—3分账；无新信息/限额/API外部阻塞分支完整，无额外监控/定时/审阅代理。
4. 历史旧报告可保留三维模式，不要求批量改历史；当前生效指令若仍要求三个测试/监控即FAIL。解释性历史文字须明确标识，不作机械关键词“零出现”要求。
5. G0/G1为本包所需；G2—G5不适用，理由引用本规划；配置PASS不能外推实际多agent运行、RTL、时序或板测完成。不运行额外行为压力测试，不作token节省百分比承诺。
6. 显式入口：根AGENTS不再“所有新任务/恢复任务自动启用”；只有明确调用fpga-orchestrator并要求执行/恢复启动。本地Skill name/目录不改、不新建重复编排器；agents/openai.yaml解析为policy.allow_implicit_invocation=false（布尔值），现有精确目录白名单允许追踪，执行git check-ignore覆盖该YAML。description、正文、workflow当前入口与触发/非触发示例一致：普通聊天、解释/引用/查看/比较/修改规则不启动该角色链，选中技能或引用$名称不等同执行；明确执行/恢复才启动。此项只做静态分支/文本核验，不另开聊天压力测试，不声称客户端自动加载已验证。
7. 不存在自造MCP执行/安装/调用或新增全局配置；Skill/MCP选择说明与trigger-docs.md两条官方来源一致，明确本方案是需求判断。收尾规则正文由原规划在测试后生成，不要求开发代写，不因正文尚未生成判开发失败；规划收尾须原样覆盖触发和已冻结所有规则。

输出：`C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/workflow/runs/20261017_202845_single_tester_scope_limit/test-reports/CFG-SINGLE-TESTER-LIMITS-r0-integrated.md`，首行唯一`### 判定：PASS`或`### 判定：FAIL`，内部覆盖functional/engineering/system，真实命令/退出/证据/哈希/未测边界。回主仅task_id、dimension=integrated、dimension_results、verdict、report_path、manifest_path、blocked、retest；有重复问题补problem对象。缺条件为FAIL+blocked，与实测缺陷区分；不自行修生产或配置。复测续本原ID并建新轮报告。

