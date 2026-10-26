# 同范围有界恢复清单：返回补充机会1
task_id：CFG-SINGLE-TESTER-LIMITS；plan_revision=2；recovery_revision=1。
problem_id：CFG-SINGLE-TESTER-LIMITS:NO_PROGRESS:local-static-deadline；reason_code=NO_PROGRESS。
本问题机会已用1/最多2；实际修复round仍0（尚无独立测试）。原DEV继续，不新开角色/任务，不改变任何冻结规则。

## 依据与判定
已读static-timeout.json、dev-notes.md、lessons-learned.md及static-check.ps1。原整段作业Start-Job/Wait-Job 300秒无stdout，退出1，已按作业deadline停止。证据不能定位某一具体语句，不能声称已知根因。原脚本将文件断言、全仓库git status、多个Git异步输出等待和差异导出全装在单作业内，且仅末尾写结果；更换为有限精确文件/分段即时结果，能提供新判别信息，不必重复原无输出执行。
本次范围/工具/输入齐备，无权限/API问题；可在现有范围和限额内作一次纠正后检查。任何再次超时/无新信息/无法安全停止均立即返回，不能自动再跑或重置计数。

## 恢复执行边界
- 仍用原30次实际工具调用/45分钟角色预算；本恢复静态检查合计deadline仍300秒，精确文件读取/搜索及每个Git子进程最多60秒，启动前检查剩余时间并取更小值。不通过“每段各5分钟”扩大总时限。
- 不重跑原static-check.ps1整段，不重启原Start-Job包装，不重复全仓库git status、不递归扫生产/旧证据/其他dirty，不扩大API权限、安装依赖/服务、起监控器或新角色。这里只完成配置自检和冻结。
- 由原DEV确认原先自己启动的作业确已终止；仅使用已知作业/进程身份与启动命令核对，PID号码本身不足以证明归属。若仍活且无法证明可安全停止，不继续/不杀他人进程，返回TOOL_CONTROL_MISSING；主不查进程。
- 新辅助检查入口只写dev-evidence，直接执行精确的小段。需要子进程时可用本机原生Process/Start-Process，隐藏窗口并把stdout/stderr重定向到本run明确文件；使用有限WaitForExit(deadline)及自身进程安全终止，终止后的等待也必须有限。避免旧Git函数的ReadToEndAsync().Result及无界WaitForExit；不用yield_time_ms代替deadline。没有可控制的执行方式就blocked。
- 每段开始/结束及每条原生命令立即写实际结果（输入、cwd、退出码、是否超时、日志路径）；任何必检失败即停止并保留结果，绝不把“检查跑起来”记PASS。这里不授权为获得PASS放宽断言或继续盲改反复测试。

## 最多三个检查段（机械清单，同一个工作包）
A. 精确文件保护与格式：以dispatch的19个配置路径和dev-evidence/before为唯一源；核对原16份before哈希、AGENTS保护前缀、.gitignore仅约定一条目录白名单、最小YAML布尔false、技能frontmatter名称及存在性。只读这些小文件，保存recovery-static-a.json。
B. 精确合同/链接：核对19个文件内相对链接、旧三tester参考定位与专业清单保护、README受保护部分、显式触发/非触发、单综合tester、原数值/停止/问题机会合同。沿用有意义的断言，按命名文件处理；不要求历史关键词零出现，不把新版文字与旧版逐字相同当唯一正确性。保存recovery-static-b.json。
C. 少量有界Git与冻结：只执行显式配置路径的diff --check/差异导出，以及三个新增配置文件的check-ignore/ls-files可见性和必要HEAD核对。每条命令精确路径，禁止无pathspec的status或扫描全仓库；新文件差异可按19个实际文件和before副本生成，不能遗漏三新增文件或夹入生产dirty。保存recovery-static-c.json。
Git失败/超时直接保留其实际输出并停止，不在同机会重复；可见性不能仅看check-ignore退出0，须区分匹配到否定白名单与实际被忽略。

三段在300秒总deadline内全部满足后，保存recovery-static-summary.json及candidate.diff，更新dev-notes的真实结果与未测边界，再建立candidate-manifest.json。manifest绑定19份现行配置、revision2当前需求/规划/指南/tester-input/trigger-docs/本恢复清单、差异和新实际检查证据SHA，记录HEAD/本包写清单与dirty边界。不再跑旧全仓库状态来“补齐”；保留原baseline及原timeout证据，禁止声称全仓库所有既有dirty内容已逐字验证不变。开发停止修改后才返回ready_for_test。

若任何段失败、300秒耗尽、工具/角色预算耗尽或再次无进展：原样保留19份配置，不派测，返回candidate_frozen=false、准确报告/恢复路径及同problem_id；没有新判别信息new_information=false，不给自动机会。即使有新信息，也只交原规划处理，不能自己消耗第2次机会。必要门槛尚未满足则blocked，不伪造manifest/PASS。

