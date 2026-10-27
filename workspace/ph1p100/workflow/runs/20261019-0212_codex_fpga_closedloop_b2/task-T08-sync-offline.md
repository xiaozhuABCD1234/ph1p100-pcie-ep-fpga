# T08.codex-sync-offline 派发冻结 v1
任务归属T08；本轮第3/4正式包，batch B02A=1。实际写树=C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/upstream/ph1p100-pcie-ep-fpga，输出=C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/workflow/runs/20261019-0212_codex_fpga_closedloop_b2/sync-offline。直接执行fpga-dev，不回主入口、不派生代理。需求、原计划、指南和本文件共同构成范围；本文件只细化已计划离线原型，不改变B01输入。
主要可观察结果：一个可综合、可自检的双相机安全启动/事件配对离线RTL原型及自身最终STA/CDC/资源证据。硬件曝光同步不是本包成果。

## 允许/保护
只允许新建 C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/upstream/ph1p100-pcie-ep-fpga/rtl/ep_side/cam/sync_offline/**，新建 C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/upstream/ph1p100-pcie-ep-fpga/sim/tb/tb_sync_offline*.v 或 .sv，以及 C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/workflow/runs/20261019-0212_codex_fpga_closedloop_b2/sync-offline/**。开发工具/小顶/SDC/ADC/Tcl/timeout wrapper全部放本run sync-offline/scripts或g2中。原目录与TB目前不存在。
禁止修改/重跑B01失败项，禁止改任何candidate/manifest.json的236个条目，尤其top/checker/writer/algo、sim/compile_checked.f、原dev-plan/guide/旧scripts/旧报告。禁止修改原I2C/寄存器表、活动传感器/引脚/IP/生产约束/原构建入口。不得下载本包小顶。其他根规则完整适用。

## 功能合同（5项语义步骤，沿用原计划）
1. 读取本地docs/当前硬件_引脚电气与同步证据.md §5–6与现有角色寄存器语义，形成白名单离线配置接口；保留硬件内部连接、电气及厂商时序歧义。
2. 可综合控制：两路先保持standby/输出HiZ，确认B从角色及HiZ完成后准备A主；B先退出待机等待>=24ms，再允许A开流；A自身退出待机后也须>=24ms，跳过前8帧。异常NACK/timeout/abort/复位走安全停止或错误状态，重复start不重入。
3. 两独立CSI SOF事件经合法CDC到共同控制时基，记录帧号配对/偏差/漏事件/失锁/恢复。偏差只是数字测量，不称曝光时刻。
4. 自检TB验证成功顺序、等待N-1/N边界、前8/第9帧边界、NACK/timeout、单路缺失、busy重入、reset/abort/恢复、异步事件和计数回绕；至少一个能拒绝旧/变异行为的负对照，仅修改隔离副本。
5. 自身小顶G2（不下载）与最终CDC/资源，输入manifest/哈希/命令/日志/报告/恢复缺口冻结。然后停止全部修改/活动，ready_for_test给一个独立综合tester。

## 离线接口与参数
- 建议接口为一个clk_ctrl/rst_n的控制器，最多一个在途I2C请求：req_valid/req_ready、camera_id、16bit reg_addr/8bit reg_data；rsp_valid/rsp_ok；请求受压保持全部字段、NACK/timeout不能当成功。允许等价命名但在接口表逐字冻结。
- 本包不是完整IMX415模式驱动：同模式/SHR0/行帧周期/连续参考时钟由明确前置输入表示；前置不满足不得开始本候选。仿真把其设真必须标注synthetic，不代表物理已证。
- 角色表依据：3003 bit0 A=0/master，B=1/slave；3002 XMSTA控制候选；30C0=2A；30C1低4位HiZ=0F，A主输出=00。保留其它合法固定字段，白名单外禁止写。3000待机语义须从实际本地原表核对后写入本包接口合同，不盲造完整sensor表。
- 30C1是S类，在待机期间配置、退出待机反映；禁止运行中切主从/改驱动并假定即时生效。A主drive配置必须在standby内且B的HiZ已确认；共享网络连接/时钟/参数前提是离线条件，禁止把此原型接到真实相机。
- clk_ctrl逻辑目标50MHz，24ms=1,200,000个周期；WARMUP_FRAMES=8。仿真可缩短等待参数，但必须验证默认常数推导/位宽并分开记录，不能把缩短值带入生产常数。
- SOF源域逻辑目标各187.5MHz（时钟独立），控制公共时间戳为clk_ctrl周期。多位序号通过稳定总线握手/async FIFO，不用多位两级采样当原子。重复/过快事件应显式拒绝/overrun计数，不能静默漏。
- 配对窗口为明确参数，仿真示例值不声明硬件阈值；32bit时间戳回绕按模差定义且有效距离<2^31。SOF同步延迟容差由所用CDC说明，TB预期相应建模；不得宣称0偏差即曝光同步。

## 三维与G层
functional：真实RTL+自检TB/scoreboard，无回放stub；所有正例0 mismatch，vlog无Error、vsim正常退出且PASS标记；有效负对照产生预期失败而非编译错误。控制排序/边界/故障/恢复与配对CDC分别有实际证据。
engineering：G0/G1/G2必要；小顶实际保留控制及CDC逻辑，50MHz/187.5MHz不降；同最终DB Routed，setup/hold WNS>=0、TNS=0、所有适用时钟组0违例，资源<=器件；时钟/约束覆盖/复位/CDC逐项说明，无宽泛豁免。必须记录3个实际时钟约束落点与CDC边界；端口/小顶只作离线载体。已有板候选/原IP不相关，不需要CWC，本包不生成可下载声明。
system：新文件限定范围/B01前后236项哈希不变，离线脚本没有download/Flash/host动作，实际输入manifest与DB/报告绑定，可复现/可恢复；真实连接、电气、寄存器读回、共享XHS/XVS和曝光证据仍未证。
G3/G4不适用理由预冻结：该原型未接活动top/未驱动硬件，不能接受双路真实同步；不是取消父T08硬件门槛。G5不适用=本轮不发布/推送。

## 有限执行与实际deadline
DEV<=30工具/45min；TEST<=30工具/45min。每次工具/worker/命令轮询均计数。读搜60s，局部静态/每TB300s，TD小顶每次1800s。最多1次预定构建；失败后只有新证据/参数纠正才可第2次，总同失败命令首次+一次。连续2轮无进展、预算到限直接blocked。平台yield不是timeout；启动前用本run wrapper落实owned PID树的安全终止，不能杀别人。
构建最多一次成功实现，测试者独立核对同DB并重跑必要G1，不默认重建。若缺控制/工具，返回准确problem，禁止主接管。DeepSeek可做最小相关的有界低风险辅助，但不得代替本角色/复杂架构/最终验证，执行提案严格按根规则审查/resume。
最终返回manifest_path/test_input_paths/artifact_paths/lessons/blocked/retest；不写全局tasks，不修改B01/旧run。缺任何适用门槛不ready_for_test、不PASS。

