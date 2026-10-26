# T10 唯一首次独立综合验收：round0

PROJECT_ROOT `D:/fpga/ph1p100`；OUTPUT_DIR `D:/fpga/ph1p100/workflow/runs/20261025-180900_fpga-dual-offline-closure`；task_id `T10.dual-aplus-scheduler`；dimension=integrated；BATCH_SIZE=1。你是本任务首次新建、独立于原开发的唯一综合测试者，不派生、不跨任务复用。主会登记实际工具返回的ID，今后同任务修复复用你。不要接管T08或向其他角色发消息。

先读根AGENTS、`.agents/skills/fpga-tester/SKILL.md` 和现行work-limits/report/relay合同，再读本run `inputs/T10.dual-aplus-scheduler-tester.md`、`fpga-design-guide.md`、`dev-plan.md` T10及公共检查、当前 `dispatch-T10-integrated-r0.json`。本文件把初始合同定位到实际最终候选；不能误用旧manifest或旧未修正源码。

## 唯一冻结输入及历史

实际manifest：`T10.dual-aplus-scheduler/cmp-stall-fix01/static-closeout02/manifest-cmp-stall-fix01.json`。准确SHA和规划核验在 `T10-round0-readiness01.json`、dispatch；启动前自行核对。实际DUT三个文件位于 `cmp-stall-fix01/candidate/`：

- `a1_deflate_core.v`：6797db053cfc47497540d6345e3a46b7e79cc1d34fa25da5a4c501505fbf35bb。
- `a1_frame_top.v`：c8b24775fa70793f682f1a640be175ec53f304722539cbd89550e0d4aefca65b。
- `dual_aplus_scheduler.sv`：8d6c2517966466df62cdcac2ede29a931f2ddf350c453fba9f5ae9f2da93100a。

原开发已stopped_modifying=true、active_commands=0；新作者声明、source-map、compiled-source、全部关键字节/日志和静态说明已manifest绑定。规划只核就绪，不给独立PASS。新增CMP修复是首次验收前收敛；尚无T10 integrated round0，也没有post-FAIL修复，不能虚构round1。

旧容量错误、过期绝对deadline、原faults3/3、compile5/case16、CMP已知24calls/完整未知、完整历史calls未知及静态6calls全部保留。原开发24正确帧和两个负对照仅作局部证据。不能借你启动开发faults第4次、重置开发账或补跑开发实验。你的**首次独立检查**使用早已预留、尚未消耗的独立预算，须实际覆盖原合同，不能拼开发PASS成综合PASS。

## 执行预算与独占写域

原首次验收预算：最多**45保守实际工具调用、60分钟、2次compile、20个case进程**。这不是一组可在失败/新目录后重置的数；wrapper/native/wait和所有自己实际操作按现行合同保守记账。接到实际派发时记录start与绝对deadline(+60分钟)，每次新进程启动前核可完成剩余时间和预留报告空间。单问题最多3轮读取/搜索，连续2轮无实质进展停止。相同失败命令最多首次+1次有新证据纠正后的重试，路径/库/参数错误也占实际尝试。API/usage/capacity错误立即blocked交原规划，不自动重试、换模型或创建替代。

读搜60秒，compile/静态/小几何每进程300秒；只有默认1920×1080 A/B双帧case可600秒，TB另有实际cycle watchdog。必须落实subprocess timeout和安全终止自己拥有的进程树，exec yield不是timeout。工具控制不足不启动，TOOL_CONTROL_MISSING。

只写 `test-reports/T10.dual-aplus-scheduler/**` 和 `test-reports/T10.dual-aplus-scheduler-r0-integrated.md`。开发所有候选/源/TB/runner/manifest/历史证据只读，规划控制及T08只读。没有TD/synth/route/bit/CWC、板卡/COM/RK、映射、下载/Flash、外部服务/消息、Git或删除授权。

## 独立构建与数据检查

在你自己的写域创建私有modelsim.ini/库/cwd/log及自有runner、TB/模型/字节oracle；独立编译实际三文件DUT，记录每个实际编译输入哈希/参数/命令。可参考或复制开发TB/生成器/检查器到自己的域作起点；DUT字节必须与唯一候选相同。不能用旧工作库、stub、重写core、软件压缩器或强制内部frame_commit/frame_abort替代真实DUT。正常/故障刺激须由真实descriptor/native AR/R/ACK产生；仅明确标注的验证变异允许在私有fixture中注错。

**不能原地运行开发run.py或finish.py**。run.py会生成TB、改sources.f和写冻结evidence；finish.py含旧guard且改旧元数据。你应另写/适配自己域的路径、日志和截止控制，记录映射；即使复制，也静态确认所有写入/库/生成文件离开冻结候选且不夹带旧deadline。`sources.f`只是三个真实DUT的接入清单，实际TB/fixture还需自己的编译源绑定。

使用Python标准zlib严格解码：要求eof、unused_data=0、unconsumed_tail=0，精确消费stream_len，不接受串接流/尾垃圾/截断。独立数学图案及A+逆变换逐byte核全部RAW10，独立计算raw/xform/stream CRC及长度，不只调用开发check.verify或看PASS/exit0。再核实际DDR输入/AR-R日志、payload分组、keep/last、release/ACK完整身份与无提前/重复/错路释放。ModelSim $fatal可能exit0，显式断言/完成/命中/数据证据一起判断。

RAW合同仍为R10F v1 codec0、128B头、紧密RAW10；实际payload5B组必须跨32B边界连续，不能拿b10/b11 padded raw代替。默认每帧raw2592000/content2592128/dma2592768，81024 native256-bit读字、518400组；全部native地址/单位、4KiB/29bit边界、源身份及8MiB槽按冻结指南核对。A+输出不能只改外层R10F codec枚举宣称传输格式已兼容。

## 20进程以内的完整检查

建议14个主要进程组织，余量只用于确有必要的未覆盖原合同边界或一次有证据纠正重试，不要求用满额度。可改组织，但不得减少必要门槛、藏子进程或重复已有有效检查：

1–6. W8H2、W8H3、W64H8各PREP/PRED关闭及所选A+启用路径。每组两路不同图案各≥4帧，实际core、同拍A/B、连续descriptor、只A/只B再双路、奇数高度尾块、跨32B/5B/行界。公平检查必须在**确实两路持续待服务**条件下连续≥8次严格交替；记录每路等待界及每帧实际服务周期。检验随机确定种子的背压、valid全部字段stall、末拍、同拍take/refill、序号缺口不被压平。
7. 默认1920×1080 A/B各一完整不同帧，真实core输出、严格还原和raw/xform/stream字段一致。记录完整AR读bytes/words/518400组/末beat keep/stream长度。实际超时或预算不能完成就blocked，不改小尺寸求PASS。
8. 原完整fault矩阵：头CRC、payload CRC、错相机/session/seq/geometry身份、base/高位越界/长度截断、RRESP、编码中abort、AR pending/迟R排空、永久缺R LOCK、RID/RLAST协议错误、共同reset和旧epoch拒绝，失败不发布半码流，RAW/CMP所有权正确，后续至少2good（原恢复矩阵4good可保留）。**必须隔离被检查条件**：单测header CRC时其他魔术/字段有效；测错身份时重算正确header CRC，避免先被另一校验拒绝却误标identity已测。对release status和每个恢复路径有对应断言/命中。可在一个有限矩阵进程内组织，不把fault子项另起不记账的进程。
9. CMP容量不足及等于边界的静态/动态适用检查，不应成功读/发布，不越8MiB；失败释放与恢复正确。
10. phase/prep兼容性及无效phase拒绝。合法头/descriptor与CRC一致后独立注无效条件，不能以通用CRC错误冒充phase门槛。
11. 新CMP反压真实matrix：合法slot1保持期间ACK0/重编码commit0，反向slot0保持，慢sink持两slot/RAW保护，错误ACK、同拍take/refill/commit/ACK、premature ACK拒绝。**cmp_valid stall的全部描述符字段**必须保持；take只能推进实际呈现slot，reset取消pending且无phantom/旧身份。用真实core/native输入，不force内部slot状态。
12. 旧实际scheduler仅重命名fixture的同一合法反例，必须命中原CMP descriptor stall断言且无正常完成，验证新checker有效；严格区分预期负对照与真候选失败。旧fixture不会成为新候选。
13. 有效跨word分组/相机身份交换之一的私有变异被独立判据拒绝；不只改expected结果或靠环境编译错误拒绝。保存变异diff/实际编译SHA/触发条件/对应拒绝证据。
14. 自己补强的接口/所有权边界矩阵：描述符和release反压全字段稳定、双camera/slot身份、同拍接受/释放、重复/错误/旧ACK与rel、held CMP/RAW不覆盖、reset清 pending。把既有TB未隔离到的原合同fault检查放在此矩阵或其他剩余预算内，不能用开发矩阵代替你自己的接口判据。

必须先静态核验测试生成/参数/路径长度（TB已修为2048bit path）和实际库，避免用实验探路径。若采用不同几何/seed/组合，列明原门槛如何覆盖，不能放宽完整帧数、几何、断言或独立oracle。无关的扩展测试不进入本轮。

## 三维、证据复用与报告

functional核数据/接口/公平/故障；engineering核真实DUT独立重编译、源闭包/宽度/容量/时钟复位所有权、异常警告与可复现性；system核RAW→编码→CMP→ACK全生命周期、反压/排空/LOCK/reset与服务预算。G0/G1必须通过。G2最终STA/物理CDC/资源、G3曝光/板级恢复、G4硬件稳定吞吐仍not_run/awaiting_hardware，不能拿旧bit/报告补当前候选资格。

你没有本任务此前独立PASS可复用。开发证据可用于定位/对照，必要新候选完整类别仍需自己运行、解析；静态不变core身份可绑定新manifest作为工程证据，不等于运行免测。写明确reuse-decision，所有当前实际输入在测试前后hash无漂移；写私有测试输入/参数/编译源的补充manifest并引用唯一开发manifest。

报告实际cycles/队列/最坏stored、输入与输出容量、100MHz TB服务率；约48.46MB/s历史局部服务与双路155.52MB/s需求存在差距，RAW写+读至少311.04MB/s另有开销。离线通过不证明双路实时或板上表现，不完成父硬件T10。

正式报告唯一 `test-reports/T10.dual-aplus-scheduler-r0-integrated.md`，首行 `### 判定：PASS` 或 `### 判定：FAIL`。同manifest覆盖三维/G层，实际工具/命令/退出/标记/非空字节/负对照/输入前后hash、当前真实counts/超时/原历史未知项齐备。必要检查缺条件则FAIL+准确blocked；有缺陷就保存最小反例，不自行改开发源码/核或修断言掩盖。停止修改且自己活动命令结束后，只回原合同integrated元数据、真实计数及必要blocked/retest给原规划；不自动进入修复或换模型。
