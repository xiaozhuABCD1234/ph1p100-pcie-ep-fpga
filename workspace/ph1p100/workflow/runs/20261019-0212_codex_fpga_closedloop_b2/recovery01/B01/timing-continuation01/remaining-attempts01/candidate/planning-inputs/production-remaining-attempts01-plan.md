# B01剩余attempt5/6的有界执行窗
原规划/root/fpga_planner_b2；同run、同T06.codex-ddr-readback-int/T09.codex-production-int、同开发/root/fpga_dev_closedloop_b01。用户followup01/04明确继续及足够尝试；02可配合、03适宜板验偏好保持。只调整执行窗及受影响检查预算，不新增生产尝试/目标/包/角色，不降低原验收。

## 新证据与当前真实状态
依据dev-return-quota-resume01.json、C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/workflow/runs/20261019-0212_codex_fpga_closedloop_b2/recovery01/B01/timing-continuation01/quota-resume01/attempt-reconciliation.json、两development-report、manual-engineering-review、attempt4-hypothesis、reuse-evidence与attempt4实际critical-paths。527项manifest SHA076F0B1A5EE2EAC7610154A173C3949436CA6CE46B19F2A5551BA847409EBAF2规划重哈希0漂移，全部活动停止。
- 生产累计4/6：attempt4实际exit0、未超时、1985.059秒（33.09min）；attempt5/6未启动。完整3600秒deadline已证可用。未下载、未综合r0、实际修复0、补充0。
- 新两槽RGB/sideband边界已切断原HE→前端ready组合链；native显式fix_hold真实执行，最终HWNS+0.020ns/HTNS0。CWC物理校验/bit配对及资源合格，但setup仍失败，因此bit仍rejected。
- SWNS=-0.645/STNS=-35.220ns。最差A路径为front/t_valid→row/rb2 memory控制；其它实际A路径包含gray DSP mult→m_y、局部RGB占用/行窗enable。B有-0.091ns：u_csi_b/u_integrity/tail→u_gear_box/O_word_out。不能继续把已经切断的旧HE链当唯一根因。
- 受影响算法G1最新通过；T06 writer/checker/controller实际elaborated依赖未变，reuse-evidence列11个检查和每源SHA。作者提供复用依据不等于独立tester已接受。
- 原240min绝对窗从15:05:51到19:05:51保守延续跨quota；核账时229.417min已过、约10.58min剩余，且未知quota区间没有偷偷清零。原工具账只给“合并原生/外层保守预留100次使用”上界，未伪造精确值。本次不改写旧窗或未知区间，上一开发停止正确。

## 本次一次明确时间/工具窗
原规划在派发前依据真实33分钟构建时长和两次尚未启动名额，给原开发新增一段：
- 本次followup开始起最多150分钟、最多150次工具；在第一条执行前写真实start/UTC deadline（start+9000秒）。旧240min窗/工具实际账完整保留，这不是把旧窗重新写成未使用；两个授权时间窗总上界240+150=390分钟，本次不承接旧窗剩余再叠加。
- 工程角色原150工具上限保留历史，本次追加最多150，工程角色累计工具授权上限300；同时本次最多150约束。先核对上次实际/保守tool记录并逐条累计，不能声称旧精确使用=100。
- 生产仍累计最多6：本次只用剩余编号5/6，不授予7，不增加native会话名额。每完整生产3600秒，CWC后处理600秒；读取60秒、局部每TB300秒。预计2×最多60min生产+最多30min必要G1/审阅/冻结，因此150min足够有界执行。
- 两个新生产会话每次前固定真实假设/修正/受影响检查/预期路径；若attempt5合格即停止构建并冻结，不能例行再跑attempt6。attempt6只能基于attempt5新证据，禁止仅换seed盲赌。
- 原G1计数不清零。仅因接下来真正的生产管线结构修正而受影响的T09检查允许累计最多8：algorithm_core/none当前4，oracle4，ROI negative3，HE samebin2，rate2，adapter_big2，RAW+algo3，injection4。它们有新源码/时序行为要复测，允许有限纠正/独立复核；不是新case改名归零。
- T06 full writer/checker仍6/8、controller仍5/6，其余未影响旧检查保持原上限；先用真实依赖SHA决定复用，不全库无信息重跑。独立tester最后决定复用并绑定新manifest。
- 首次独立tester仍60工具/90min，不随本窗增加。综合r0尚未开始、实际修复/补充0保留；之后实际修复仍最多3轮。
- 连续2轮真正无进展、任何本次预算耗尽、生产6次总上限、必须改保护IP/频率/电气或工具/额度缺失即返回原规划。本窗不预授权再次延期/第7次；可转原T08独立已授权包，不无限延长B01。

## 具体纠正方向，实施归原开发
1. 以attempt4真实setup路径分组定位：front/row行窗的valid/占用/地址-enable高扇出组合，gray乘法/加和到输出的数据路径，及小幅camB residual。原HE链已被切断，保留正确的两槽边界，不为“插级”而盲目移动同一瓶颈。
   允许在原生产副本img/algo目录内做必要局部管线/enable拆分/寄存复制或等价结构调整，包含row-window/demosaic/rgb8_gray_stream在内；数据数学定义、系数/舍入/饱和/Bayer边界/LUT发布和像素顺序不变，四lane与全部sideband同token移动。允许结构改变不意味着源字节仍等同：更新provenance为生产管线变体，原参考RTL/oracle/vector只读。不能改oracle让错误值过关。
2. ready/valid和RAM时序必须真正正确：stall保持、同拍可接受take/refill、满队列安全、abort/FE、行bank切换/首末像素、坏帧拒绝与下good恢复；新增延迟须由真实DUT逐样本与独立模型验证。CSI仍不可反压，算法忙/溢出不能破坏RAW。
3. camB legacy路径不在本包RTL允许改动范围，保留受保护接收/PHY/IP/ADC/旧SDC；只可用已证的合法native setup/布线优化入口解决物理残差。若需要改原相机接收逻辑、传感器表、时钟/IO或宽泛false path才能过，停止交原规划；不擅扩scope。
4. 保留已证的显式native fix_hold完整流程；每次新放置都重新核对setup/hold全部适用clock组及TNS，不能借上次hold PASS不检查新候选。原cam5.332ns、DHI10ns、TL16ns、约束覆盖/CDC/资源/CWC物理映射与bit配对门槛不变。不能把exit0或资源合格当G2通过。
5. 行窗/gray管线改动后只重跑其必要逐像素/负向/hold与sideband/24case/溢出与RAW隔离/完整1080p和连续两帧服务等受影响项。测试副本允许刺激相位覆盖新增延迟，但保留全部原assertion和独立oracle，不用扩大可选矩阵延迟构建。未变T06依赖用reuse-evidence明确绑定。

## 输出与恢复
本次developer_output_dir=C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/workflow/runs/20261019-0212_codex_fpga_closedloop_b2/recovery01/B01/timing-continuation01/remaining-attempts01（同run证据子目录，不重置任何ID或计数）。上一527项manifest/报告/DB/失败bit/恢复核账均留历史，不覆盖；实际源首次改前snapshot+SHA/diff。新attempt5/6脚本/日志/工程、报告、role-window-ledger、attempt-counts及最终新manifest写此处。源写仍原B01名单；保护T08、vendor IP、原SDC/ADC/stage、协议、其他工作树/D盘工程/全局配置。
初次新输出必须把旧4次生产、原G1真实累计、旧角色窗与新窗分账写入；不从attempt1开始，也不推断quota等待用了0或制造精确tool数。
全部必要G1/G2/CDC/资源/CWC与候选身份合格，活动结束、停止修改并冻结新唯一manifest后才ready_for_test；随后恰好一个综合tester。当前不需要用户GUI动作，失败bit禁止下载。独立综合通过后立即由原规划优先T02真实几何/RAW读回/坏帧恢复，不等T08/可选优化；仅SRAM、不Flash、不PCIe/RK、不推送。
