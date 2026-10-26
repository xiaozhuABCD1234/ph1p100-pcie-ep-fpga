# T02 输入链路细节审查（round0）

本包完成原计划T02的只读审查产物，等待独立综合测试。它不对DUT或整链路作通过判定，不关闭父硬件任务。用户原话、恢复授权、计划和工程指南仍以run根的冻结输入为准。

最优先的源码问题是 **4×10bit样本向量与packed RAW10的入口格式不一致（F01）**，其次是 **CSI好/坏帧裁决未接入A+捕获（F02）**。F03记录最后ROI行几何合同的独立盲区。已知b15缺R、enc/exported=0继续保留，本包没有定位真实MC根因，也不把上述问题描述成旧bit已经实测的像素错误。

## 输入和实际接入

唯一统一基线为 `D:\fpga\ph1p100\workflow\runs\20261026-144617_fpga-chain-detail-review\baseline\source-manifest.json`，SHA256 `c08adc09b364828fee5d94953a89898a3220af8c8f99cdec52404fec06f74c96`。全部287项snapshot本地重算一致。输入工程HEAD为27c596b01cd961dfa9d0850e4fbf879fe249de90，既有dirty/删除全部保护。本包只在自身目录写入。`source-map.json`给出原路径、snapshot路径、SHA与实际编译入口；`checkpoints.csv`为28行包内检查点，不是新增调度任务。

`a1_board.al`的top为p2_a1_board_top，核心源选中changed-src；与candidate manifest比较的crop/camera top/core/board top及.al/SDC哈希一致。统一baseline未收齐相机依赖，于本目录inputs只读补冻13项，并核对复制前/后与副本SHA。该操作没有修改baseline。相机依赖未逐项出现在旧candidate manifest，因此补冻内容只证明本次源工程引用，不认证历史bit内每份依赖；不同SHA的upstream配置器没有被冒充成b15配置器。依赖的原始生成时间/旧bit资格缺口保留。

|分支|实际输入、裁决和范围|
|---|---|
|b15 A+ UART|两路CSI接收，但仅A的40bit tap进入crop→43bit CDC→RAW store→feeder→A+；B无压缩消费者。源3864×2192，ROI(972,556)、1920×1080，966源组/行，480 ROI组/行。cap_frame_end/good/abort在板top悬空。|
|b15 HDMI|实际输出测试图；cam_preview_capture仍在文件表不代表被实例化，cap_sof/valid/last/data常量0。显示Hz不能证明采集fps。|
|upstream RAW/R10F|独立ph1p_pcie_ep_top，A/B各有cam_r10f_writer；显式sample-lanes→packed重打包并消费frame_good/abort。其ROI/skip参数与b15分别绑定，不混作同候选。|
|同步/双路离线轨道|sync_start_ctrl/mailbox/pair与隔离sync_frame_gate、exclusive I2C overlay有源码/交付记录；baseline中的生产top是overlay前输入。b15未编译这些实例；独立离线PASS不证明迁入生产或真实曝光同步。|

## 五步覆盖及判据

1. 编译/分支/参数重建：C01—C02、C26和source-map。实际选中路径优先于仓库同名文件或旧注释。
2. I2C/CSI/RAW/ROI：C03—C15。b15配置器单master/每路独占，先写201表项、选择寄存器masked readback，再退出standby、等待24ms、启动；busy完成后才cfg_done。NACK/事务超时失败锁存，未实现自动重试。SDA开漏；SCL输出不主张clock-stretch/多master。启动默认延迟为50MHz阈值，未重新验证传感器电气。包层VC0、RAW10 DT2b、严格ECC比对（无纠错）、CRC16初ffff/反射8408、低字节keep，逐包同步profile，有idle/frame timeout。IMAGE_WC/EXPECTED_LINES/CHECK_FRAME_ID默认0，故好帧不代表精确3864×2192或帧ID严格校验。四lane同拍有效后进入gearbox。解包按五字节组成四样本，残留在新行丢弃；输出格式必须与下一消费者分别核对。
3. 入口/CDC/序号/同步：C16—C25、C27。CSI不可反压，FIFO满不能要求源重发。现有sticky abort token、sideband原子打包、Gray指针/独立复位释放及skid接受条件已逐条检查；不能为简化删除。局部no_issue_found仅表示静态范围未见矛盾，不是随机stall/reset仿真证明。crop复位释放与PHY重锁缺证据；raw_id是成功准入ID，不等于capture_seq。SOF mailbox计数每次输入并记录拒绝，pairer以控制域到达时间差窗配对，窗口缺路/覆盖会解锁再锁，不保证传感器曝光；丢事件计数要等下一次可接受mailbox提交才随payload可见。
4. 发现与优化：全部见findings.json的结构化证据/触发/收益/代价/验证/处置。所有确定性问题均带冻结源码SHA和行号。见证与算术如下；未提出直接删除状态/缓存/CRC的建议。
5. 交付和冻结：本目录review/checkpoints/findings/source-map/witness/commands/lessons及局部核查，再以manifest-r0.json绑定所有输入/产物；冻结后停止修改和活动。

## 可复查见证及局限

实际执行Python3.11标准库 `witness/check_input_contract.py`，解析冻结producer的Verilog concat切片，再独立构造规范RAW10并按消费者位域重算。结果：源[0,1,2,3]对应wire=e400000000，解包word=00c0200400，被A+读为[0,16,128,768]。4096个逐lane/0…1023数值组合中4089个不保持样本；全0/全1023可假通过，故不能只用极值平场。显式重打包负对照恢复原样本。该检查拒绝的是接口值不等价，未执行RTL、DDR或整帧编码。

第二个源锚定时序见证：最后ROI行零起编号1635，最后ROI组722，源行仍有243组后缀。crop立即置done/out_last，new_line和frame_fall检查均要求!done；该行CRC更晚才知，且CSI abort端口在board top未接A+。因此ROI计数完成不是CSI帧合格证明。此见证是算术/状态条件轨迹，未声称cycle-accurate RTL仿真；独立测试者应使用不同判据复核最高风险F01，并核对F02/F03的源码链。

## 按优先级的后续工作

|优先级|发现|收益与代价|必须验证|
|---|---|---|---|
|正确性1|F01格式契约|恢复样本值；在明确边界重打包的组合逻辑/时序代价待测，无压缩比收益估算。|跨真实checked unpack→crop→store/feeder→解码后像素oracle；混合LSB/lane顺序；新候选绑定。|
|正确性2|F02/F03事务裁决|防坏帧发布；pending verdict可能延长slot持有，需与T06容量/所有权审查衔接。|最后ROI行CRC/短长后缀/坏或缺FE/重复FS/恢复；只OR晚abort不足以撤销已发布帧。|
|可观测性|F04/F09|capture/admission/export ID、epoch、ROI/CFA有明确来源；增加元数据与版本兼容成本。|准入拒绝/丢帧/reset/retry/回绕、CFA标靶及方向比对。|
|工程与系统门槛|F05/F06/F07|明确本域复位、PHY适用范围及曝光同步；需未来真实设备/时序/CDC验证。|停clk_cam reset、PHY重锁、I2C清理/晚响应、真实曝光与稳定性。|
|低优先冗余候选|F08|先清理入口说明；无综合网表差分不能估资源收益。|实例/消费者/约束/网表证明后才考虑删自动扫描或文件引用。|

建议不实施优化、不修改生产源，不接入b17/另一1080p30 run。父T02及整链路仍保留后续包与硬件门槛；本包未展开新调度任务。

## 既有证据与G层资格

|对象|G0/G1|G2|G3/G4/G5边界|
|---|---|---|---|
|本审查|本地输入哈希/语义/算术见证已完成，独立综合测试尚待执行。|本轮新执行not_applicable：规划已冻结纯只读，无新RTL/IP/约束/bit。|本轮新执行均not_applicable，理由同dev-plan：不交新候选/不签核硬件。|
|b15旧诊断|原result报告模型/构建通过；仅其原输入范围。|reported pass with caveat：SWNS+0.012ns诊断薄余量，原routed报告未由本包重跑。完整CDC/输入依赖bit绑定not_run/证据缺口。|G3旧记录SRAM下载/150s采集reported pass for observation；G4整帧编码/导出blocked H4_UNRESOLVED，enc/exported=0；G5生产稳定性/吞吐not_run。读根因、确定第1239字和L_max=1均不签核。|
|T08隔离同步|冻结delivery-index记离线G0/G1 PASS；源码/README显示真实I2C/checked CSI和writer，仅明确环境stub。此包未重跑原矩阵或复用它为b15通过。|原交付G2 not_run。|原离线G3/G4/G5 not_applicable；当前生产迁入、真实曝光和板级恢复仍not_run。|
|双路local closure|冻结delivery-index记独立离线PASS，两套独立实现；本包仅作为资格索引引用。|真实生产G2 not_run in this audit。|当前板级曝光、双路A+生产闭环与稳定性not_run。|

G0在本工作流指接口层；性能讨论另称P1080。77.760/155.520MB/s是目标packed payload预算，非本包实测；u16长度4,147,200B和DDR存储129600×32B也不当作packed payload2,592,000B。此处只固定输入语义，详细搬运/吞吐在T06/T11。

## 执行、风险和回退

全部读/复制通过自有PowerShell Job的60秒deadline，见证Python进程WaitForExit(60000)，超时仅Kill本进程树；yield不作为timeout。探索中遇到.al内UsedInP&R未转义导致XML解析失败，改为精确File Path正则读取；一次Select-String未转义方括号失败，改为SimpleMatch。它们没有修改任何生产文件，也没有被当作成功验证。初次角色根技能读取为短直接Get-Content，未套本合同deadline；其余命令均落实deadline，该执行记录限制保留。

DeepSeek未用于本包：可分离的文本整理工作不足以抵消额外上下文发送/审查开销；复杂接口判断及最终核验均在本角色完成，没有声称代理审查。硬件/TD/bitgen/Flash/COM/JTAG/RK/网络下载/删除/commit/push均0。未动其他活动run、docs junction、workflow/tasks.json或baseline。源目录存在不代表本审查取得写权。

回退为保留现有方案与全部旧候选；本轮无生产改动。若综合测试发现文档/见证错误，续同任务开发并新冻轮次，保留当前输入和证据。下一位综合测试者在其允许目录复核manifest所有SHA、全部高风险发现、其余检查点引用和完整覆盖，至少一个不同于本开发的独立判据；不得将审查PASS解释为被审查DUT或四包整链路PASS。
