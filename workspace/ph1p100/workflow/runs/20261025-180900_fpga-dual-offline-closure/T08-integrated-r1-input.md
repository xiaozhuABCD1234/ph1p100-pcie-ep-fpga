# T08原唯一综合测试者：正式r1验收

task_id `T08.dual-local-closure`；dimension=integrated；round1。真实原测试者 `/root/fpga_tester_dual_local_180900`；PROJECT_ROOT `D:/fpga/ph1p100`；OUTPUT_DIR `D:/fpga/ph1p100/workflow/runs/20261025-180900_fpga-dual-offline-closure`。续原会话，不新建第二测试视角、不派生、不跨任务复用。

## 唯一新输入与就绪边界

实际manifest：`T08.dual-local-closure/r1/mode-fix02/manifest-mode-fix02.json`，SHA256 **38e0615341330aa5b8f1e0e1f9ecf4e169abbdc6bc4856912b9e4f929bdfcce3**。本角色必须以此候选实际source闭包测试，不能误用旧r0、旧r1或static-closeout01的blocked源码。

开发已ready_for_test、stopped_modifying=true、active_commands=0。原规划 `T08-r1-readiness01.json`核了314项绑定文件、79项实际编译源，漂移0，12份局部receipt对应SHA和通过声明齐备。这只说明具备交独立测试条件，**没有给独立PASS**，不替代你的前后完整输入核验、独立编译/运行/数据与接口检查。

先读fpga-tester技能、现行report/relay/work-limits、本run冻结指南/dev-plan与 `descriptor-corrections01-plan.md` T08段；再读当前开发result/source-map/reuse-proposal/实际源码、原r0报告与自己原独立TB/数据oracle。保留所有原错误/证据；r0 integrated仍FAIL，已经做实际实现修复1，现在没有r2，也未出r1 integrated。

## 原未消费r1预算与写域

本次正式r1：**30次实际工具调用、45分钟、最多2次compile、14个case进程**。从本次真实followup收到起记录start/absolute-deadline(+45分钟)，开工先冻结自己的实际计数和进程清单；工具包装层与内部native保守合计，不借长脚本绕case/compile预算。读搜60s、编译/局部/单case实际300s并有TB cycle watchdog；不支持实际安全控制就不启动。

原tester r0保守calls44/45、compile2/2、case20/20、19:57截止和一次quota中断保留。那一窗口已经结束，本次是原已排定但尚未开始的真实r1验收，不能回写成r0继续或抹旧账。**原tb_tester_edges已真实失败1次，只有1次修正输入复跑余量**；新源下该次不论成功/失败/工具路径问题均不能自动再加一次。启动前静态确认源/参数/路径/库，避免用实验探路径。

只写 `test-reports/T08.dual-local-closure/r1/**` 和 `test-reports/T08.dual-local-closure-r1-integrated.md`。原tester证据、开发全部来源、planning控制和兄弟任务均只读。自己的新TB/检查器/变异副本/库/日志仅在本次写域。禁止RTL修复、TD/硬件/盘符/COM/RK/下载/Flash/Git/外部消息/批量删除。API/额度/容量错误直接blocked交原规划，不自动重试、换模型或创建替代。

## 必须独立完成的检查（14进程内）

建议如下单次列表，前期先审查完整闭包与输入，必要组合只改变执行组织不降低覆盖：

1. 新模式/发布矩阵：A/B、两slot，2→1/1→2与pub同拍拒切且保留pub；正常空闲切换仍有效，busy/offer/held/AR/R在途拒切；本地读回释放后再切mode2无phantom/旧身份，双pub和reset都正确。
2. 原tester_edges：原独立刺激对应的F01/F02，在新实际源码上仅一次复跑；stall全部字段保持、同拍ext_take排斥释放。原assertion/期望不能降低。
3. 所有camera/slot/status矩阵：12种AR-release竞争、同拍take/refill、双pub、错camera/旧epoch/重复release及所有权完整；与模式矩阵互补，必要可用原独立tb_repair_matrix/tb_dual_contract，但必须实际绑定新DUT。
4. case16真实overlap：从已接受AR至实际最后R记录两路新SOF和其他槽pub；每路≥2 SOF、≥1完整pub真重叠，保护满整帧丢弃/计数/seq缺口，随后≥2对good完整读回释放，实际R字节/CRC/源图案/尾零与身份对应。
5. normal six-pair/槽复用。
6–11. case10、11、12、13、14、15：真实载荷CRC损坏、安全排空/恢复，两种AR时序abort，缺R LOCK/共同reset，饱和/模式拒绝，旧epoch释放；不能只复用开发结果。
12. contract独立同拍pub/接口/释放路由。
13. legacy默认关闭路径。
14. 有效B-release-to-A变异被拒绝；独立不同判据要能发现实际路由/所有权错误。

case15和独立contract不是本次开发12项中的单独新跑case，**已明确要求你在新输入fresh执行，不予豁免**。旧mode反例可检查开发已记录的旧fixture触发/源码差异，并由你独立增加模式判据，避免另加第15个进程。若你判断必须额外独立old-mode进程才能证明门槛，先在14之内合理组织一个有限矩阵；不可超额或静默删必要项。

独立数据检查复用你自己的 `independent_oracle.py` 作为起点，适配在自己的写域，不能只跑开发check_t08/r10f_oracle；用实际R/AR/释放日志核标准CRC、packed样本图案、完整身份/长度/尾零、无提前/重复/错路释放，不能只看exit0或PASS字符串。ModelSim对Fatal仍可能exit0，预期变异拒绝和真实DUT失败严格区分。

旧I2C专属case1–9只允许由你在新manifest下明确做逐源SHA/时钟/参数/刺激/影响映射后复用自己的r0独立证据，写入本轮reuse-decision；变更模块的模式/offer/AR/所有权/重叠证据不能旧PASS拼新源。不能把开发的矩阵声明替代你自己的接口判据。物理STA/资源/CDC、真实曝光/板级恢复/长稳/吞吐继续按原离线边界not_run/awaiting_hardware，不冒称完整硬件资格。

## 构建/脚本注意

实际source闭包是新候选 `run_mode_fix.py compile_all`对应的 `local/build/sources.json`，79项含隔离fixture；这里是文件/编译参数参考，**不能直接运行开发run_mode_fix.py**：它含旧开发截止并向冻结local写输出。你应在自己独占模型库/INI/cwd/log中独立编译实际新DUT与所需TB、原独立TB和变异副本。不要导入会改写command全局或夹带开发deadline的runner来替代自己的timeout控制。审查重复模块/alias、include、参数与MIPI环境替代，不能错用stub替代writer/checker/sync。

## 报告与返回

本轮报告首行唯一PASS或FAIL，路径 `test-reports/T08.dual-local-closure-r1-integrated.md`；同manifest覆盖三维/G层、实际命令/工具/退出码/标记/非空证据、前后漂移、独立判据、变异/有效缺陷、复用映射、真实本轮及历史计数。必要门槛有一项未满足不能PASS；新的缺陷或预算不足如实FAIL/blocked，不再修改开发源或自动重跑旧edges。

只回task_id、dimension=integrated、dimension_results、verdict、report_path、manifest_path、blocked、retest与实际计数。全部结果交原规划决定后续，不自行再派开发。T10外部capacity仍blocked，本角色不得读取/恢复/换模型或挪用其预算。
