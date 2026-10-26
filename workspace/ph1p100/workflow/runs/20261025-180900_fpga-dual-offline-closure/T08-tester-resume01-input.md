# T08原唯一综合测试者恢复01：保留已有证据和全部计数

真实原测试者 `/root/fpga_tester_dual_local_180900`；task_id `T08.dual-local-closure`；round0；PROJECT_ROOT `D:/fpga/ph1p100`；OUTPUT_DIR `D:/fpga/ph1p100/workflow/runs/20261025-180900_fpga-dual-offline-closure`。这是quota中断后的原会话续接，不新建测试者，不新开轮，不派生代理。

## 恢复依据与范围

用户真实新原话“接着做”保存在 `user-feedback-continue01.md`；主原生错误为本角色usage limit、提示7:41 PM后再试；主在19:44:32收到继续指令。此条件变化允许续原角色一次；不自动重复API错误，不增加任何工具/case/compile/时间预算，不授权新scope。

开发已停改，active_commands=0；唯一输入 `T08.dual-local-closure/manifest-r0.json`，SHA256 `264b067bc4f363cb835616ce7f15fa4db996f0a0621ab3c7a6725ab7ff72058e`，与自身`freeze-before.json`记录一致。现已有18条suite结果、baseline与mutant两次compile记录、一条tester-edges仿真、一条B-release变异仿真。它们占**compile2/2、case20/20**，不能重置或再启动仿真/编译来重做有效证据。

工具调用仍原上限45、时间仍原60分钟。规划无法从产物推定你已消耗的全部工具调用数；请从你原会话上下文恢复实际累计值，不把未知写0。余量不足或计数无法可靠恢复时只按真实状态blocked返回，不能自行补满/扩额。主日志记原派出18:57；保守沿用绝对截止2026-10-25 **19:57:00 Asia/Shanghai（UTC11:57:00）**，不因quota暂停或新一轮续接延长。记录自身实际开始/额度中断和原计数，不冒充平台保证的硬限。

## 只完成尚缺的证据判读和报告

1. 先恢复原上下文与真实计数，确认没有自身遗留活动。复用已完成、同manifest且适用的证据，不重复编译/仿真，也不修改开发候选。API/额度再次失败直接blocked交原规划，不自动重试。
2. 读取自身 `suite-results.json`、`negative-result.json`、`tester-edges/sim-result.json`、相应原日志和已有独立oracle/静态结果。suite18项各有正常完成标记；negative_rejected=true。**tester-edges的sim_pass=false，必须如实判读**：识别有效DUT缺陷还是验证环境/刺激无效，给出触发、期望、实际和必要门槛影响，不以其他正例掩盖；规划未作技术结论。若必须再跑case才能满足门槛，现次数已满，报告FAIL并blocked，不能临时增加一次。
3. 在剩余工具/时间内完成原要求的独立字节/CRC等既有采集后处理、源/CDC/所有权静态审查、最终前后SHA核验和证据复用说明；纯读取/字节检查无需新增仿真，仍计工具调用且落实60s读取/300s局部检查deadline。规划只核了manifest文件SHA，不能代替你对其参与文件的最终漂移检查。
4. 新建原规定 `test-reports/T08.dual-local-closure-r0-integrated.md`，首行唯一PASS或FAIL。覆盖functional/engineering/system、必要G0/G1、G2/3/4真实not_run/awaiting_hardware边界；列出有效/无效/未跑/blocked项，保留失败证据，不强行PASS。若因预算/证据不足必须停止，写实际完整程度与准确恢复入口。不得把“尚无报告”或quota中断当成DUT已通过。
5. 按原fpga-tester/relay-contract仅回task_id、dimension=integrated、dimension_results、verdict、report_path、manifest_path、blocked、retest及真实累计计数。真实FAIL由原规划按现有计数决定后续；本续接不是修复轮1，也不改变原开发compile/case上限。

允许写域仍仅本run `test-reports/T08.dual-local-closure/**`及本任务综合报告；原生产/候选/另一任务/规划控制全部保护。禁止TD/硬件/盘符/COM/RK/下载/Flash/外部消息/Git/批量删除。T10保持自己的原角色、原授权与19:55:19.126669绝对截止，不由你读取/监控或接管。
