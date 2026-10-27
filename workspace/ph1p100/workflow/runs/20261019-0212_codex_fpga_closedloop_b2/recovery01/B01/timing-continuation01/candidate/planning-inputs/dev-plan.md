# 本轮有限执行计划 v1
冻结时间：2026-10-19；唯一规划角色=/root/fpga_planner_b2；实际宿主=Codex。详细输入见input-index，工程语义见fpga-design-guide。本轮授权来源=request.md：“batch=2…Track A…Track B…仅SRAM…最后回来点两下”。用户要求进度优先；必要完整性/STA/CDC/候选绑定/真实板验不取消。

## 主要目标与合法边界
一个主要可验收目标：交付一个可恢复、可观测、可板验的FPGA侧单A RAW→DDR读回候选，按用户要求将T09生产接入及双相机同步离线准备纳入相邻有限工作包。共4正式包（ready/blocked都计），仅需求→工作包两级，每包<=5项语义步骤。batch=2只授权合批，未覆盖目标数/任务数/层数上限；无新增全局T任务，不改名绕失败轮次。
本轮范围done与父任务done分账：B01离线工程PASS不等于T02/T06板闭环done；T09旧done仅模块级，生产接入另有本包证据；T08离线PASS不等于双路曝光同步done；父T11仍active。原基线run已finished，本轮不是继续消耗其旧修复轮；本轮新集成/板闭环是新成果且各round0起算，不将旧失败成果重新命名。

## 正式包最小表
| task_id | 主要结果/实际写树 | 依赖 | functional | engineering | system | 必要G层 | 当前状态/下一动作 |
|---|---|---|---|---|---|---|---|
| T06.codex-ddr-readback-int | 生产检出单A完整发布帧被板内checker安全读回；生产检出rtl/ep_side/ddr与必要相邻top/debug/sim/filelist | 基线已验checker/当前四项dirty | 完整1080p RAW writer→DDR模型→真实checker CRC/长度一致；坏帧拒绝/下帧恢复；持有不覆盖/AXI仲裁/错误/复位 | 最终共享DB的G2；新读逻辑/CDC/资源/CWC物理映射和冻结身份 | push关闭/不接PCIe；保留旧生产行为/候选；无越界写 | G0/G1/G2；G3归T02，G4留后轮 | ready，B01第1项 |
| T09.codex-production-int | 三真实算法进入生产相机流及最终网表；production新algo目录+必要adapter/top/sim/stage | 已验T09冻结RTL；与T06共同冻结后共享build | 三路逐像素独立oracle0 mismatch，边界/首帧HE/同bin/坏帧/stall/切换；真实适配流不影响RAW；至少一有效负对照；1080p2帧服务 | 同一生产DBG2，3分支不被剪除，原187.5MHz及约束不降，资源在器件内 | 输入来源/ROI/sideband一致，CSI不可反压，算法丢帧和RAW隔离；不声称算法DDR/板测 | G0/G1/G2；G3算法效果本轮未测，G4后轮 | ready，B01第2项并合并构建 |
| T08.codex-sync-offline | 双相机启动/角色/同步测量离线真实RTL+TB；production新cam/sync_offline目录，不接活动top | B01结束释放同写树；本地同步证据 | 两路安全排序/HiZ、24ms/8帧边界、NACK/timeout/单路缺失/复位/恢复、异步SOF配对自检0 mismatch | 离线可综合小顶自身G0/G1/G2，最终STA/CDC/资源；不会进入板候选 | 无线上传感器改动，主从歧义/物理缺口明确；SOF不代替曝光 | G0/G1/G2；G3/G4不适用=未接硬件的离线原型 | queued；原规划收到B01判定后派发 |
| T02.codex-singleA-board | 同候选单A真实RAW→DDR读回/几何/坏帧拒绝与恢复短窗证据；run/board仅记录 | B01两包同候选PASS；用户在场GUI/真实板窗口 | 两次>=20s相干样本，身份匹配、>=2不同seq完整帧校验PASS、bad不发布/下good恢复、实际几何与ROI依据 | 下载/bit/CWC/DB绑定、G2无漂移；采样可复核、无错误冒充PASS | 仅SRAM/无host/操作者与时间/现场恢复记录，失败保留可回退 | G3必要；G0–G2继承同manifest；G4 not_run=用户后放长稳优化 | awaiting_hardware；不阻塞B01与T08离线准备 |

## 各包实施清单（语义步骤）
T06：
1. 在当前基线四项SHA之上固定单A已发布帧触发/身份及buffer持有/释放合同，保留pusher接口和B范围。
2. 接checker与独占/仲裁读口，锁存coherent seq/base/len，错误/timeout/abort可收束；新增控制CDC合法化。
3. 完成诊断相干快照、完整32bit关键计数与debug-only一次坏帧注入/恢复可观测性，保留link-independent reset。
4. 用真实writer/DDR模型/checker联合TB完成1080p与上述负向、所有权/AXI/重置回归。
5. 与T09共同生产构建、CWC/STA/CDC/资源/回退与manifest冻结（机械hash不是另包）。
T09：
1. provenance逐项SHA引入已有真实RTL到生产algo目录，修正本轮副本runner陈旧锚点/输出路径，不写旧资产。
2. 接同ROI的单A CSI输入和三实际诊断sink，处理不可反压/忙碌拒帧与RAW隔离。
3. 独立模型逐像素回归（三算法/边界/首帧/坏帧/同bin/停顿）和实际adapter正负例。
4. 验证硬件并行/1920×1080两帧服务及长期忙碌边界，明确相位未板证；同一B01生产最终构建验证真实保留。
5. 停止全部修改/活动，统一batch manifest、变更/复测影响/板验两点击清单与lessons。
T08：
1. 按本地冻结依据生成白名单主从角色/HiZ配置接口及前置未决项，不改活动传感器表。
2. 实现B先准备/A后开流、24ms和8帧等待、NACK/timeout安全退出/复位重入的可综合控制。
3. 实现两独立SOF事件合法CDC到同一时基的配对/偏差记录，仅作测量原型。
4. 自检TB覆盖正常/边界/缺路/失锁/复位/异常恢复与有效负对照；缩短等待用参数且核验生产常数映射。
5. 离线自身G2/CDC/资源，冻结manifest和硬件缺口；不接/不下载。
T02：
1. 复核B01唯一bit/CWC/DB/manifest与GUI窗口、操作者、现有单A接线，不根据旧板状态猜测。
2. 必要时一次受控SRAM下载并保存器件/命令/退出码；新候选独占，旧位流保留。
3. 用户执行两次Instant Trigger间隔>=20s，导出原文与截图；核对CRC/seq/几何/坏帧拒绝与恢复。
4. 按冻结阈值记录真实PASS/FAIL/blocked与短窗恢复，缺实际坏帧触发或有效几何证据不升PASS。
5. 冻结板记录与恢复清单；综合测试独立核验同输入，不修改候选。

## batch与排程
B01批大小2=[T06.codex-ddr-readback-int,T09.codex-production-int]：一新开发顺序实现，停止后一个新综合测试覆盖全批，逐任务一份integrated报告。共享生产候选一次构建，冻结唯一manifest，不把两个部分候选拼成PASS。
B02候选=[T08.codex-sync-offline,T02.codex-singleA-board]；需原规划读B01报告后更新dispatch。T02外部窗口不具备时，允许只派T08默认单包batch=1（不扩大已授权batch=2/四包上限、不跨任务复用B01角色），T02保持awaiting_hardware，最后把可执行两点击清单交用户。不得因硬件缺失重新构造无限准备包。
测试输入共享DB但逐任务判定；同任务FAIL续本批真实原dev/test；round0首次、round1–3最多三轮实际修复，任务分账（另一项未受影响证据由同tester绑定新manifest说明复用）。缺工具/设备/授权/额度不空转修复轮，直接回规划。任何共享输入漂移整批冻结失效。

## 量化验收与不适用理由
- G1每正例mismatch=0，vlog无Error，vsim正常终止且明确PASS标记；负对照必须出现指定失败并无仿真错误，不能以exit0当正证。B01保留基线8TB+checker+debug新TB与新增集成TB的受影响回归；至少完整1080p用真实DUT，缩小模型只辅助边界。
- T06完整读回word_count=648192、magic/header_crc/payload_crc/length四ok全真、err=0；CRC/长度/AXI/RID/rlast/timeout/abort负例必须拒绝，busy重入忽略，旧响应不泄入新会话，持有buffer不覆盖。读回错误帧不能作为正式完整帧发布。
- T09参考使用已有oracle/冻结向量；三分支逐像素/sideband0 mismatch；并行接收计数>0且最终网表均存在；每帧518400个4px输入beat，持续1080p两帧含HE帧末必须完整；记录实际stall/drop，单A30fps服务预算可满足，不外推双路或旧小顶748Mpx/s为板实测。
- G2最终Routed，setup/hold WNS>=0、TNS=0、各适用clock组0违例；所有新增时钟/复位/CDC有分析和约束覆盖，无不受控新路径/广泛豁免；各类资源<=器件限。完整CWC与BID覆盖校验0失败，同源bit一致。输入/DB/报告/bit/CWC/工具版本哈希链完整；工作流5.1适用项必检。
- T02真实G3至少2不同seq完成校验pass_count推进；原始几何/ROI/Bayer相位的有效性依据明确，未知保持未证；自然坏帧或受控debug内部abort至少一次，拒发布并随后good恢复。内部abort证据不能称传感器电气CRC故障。观察短窗>=20s，不冒充10分钟长稳。
- B01不要求G3：专门板包T02承担真实硬件，不以offline PASS称板闭环done。T08 G3/G4不适用：只交离线未接顶层原型，真实双路曝光同步明确后轮。G4长稳/优化由用户明示后放；本轮最小恢复/连续两帧/短窗口要求仍保留。G5发布/推送不适用：用户明确不推送。

## 允许写与保护
DEV唯一生产写树=C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/upstream/ph1p100-pcie-ep-fpga。B01允许rtl/ep_side/ddr/（checker相邻适配/仲裁）、新rtl/ep_side/img/algo/、新增rtl/ep_side/debug/closedloop诊断wrapper；必要最小修改rtl/ep_side/ph1p_pcie_ep_top.v、pcie_ep_engine.v、img/ep_bar_win.v和cam_r10f_writer.v（仅ownership/诊断接口；改几何/算术须回规划）；sim/compile_checked.f、sim/tb/受影响/新增TB；新tools/pcie_integration/td/00_all_closedloop.tcl及必要run-local辅助脚本；新同层closedloop SDC只允许层级映射和明确新CDC约束，禁止放松目标。
B01允许本run内ddr-integration/、algo-integration/、build/、candidate/、scripts/、board/准备文件、lessons-learned.md。TEST只写test-reports/及其隔离副本，不修冻结输入。T08待派发只允许新rtl/ep_side/cam/sync_offline/与对应新sim/tb/、run/sync-offline/，不动活动top/I2C表/引脚。
规划允许本run计划/dispatch/收尾及必要workflow/records原T任务记录；workflow/tasks.json仅规划收尾时最小追加本轮证据，保留旧信息，DEV/TEST禁止写。
保护：所有旧run/基线证据/根dirty/技能/全局配置、源fpga/csi2/src/img/及tools/algo/、parallel/、另工作树、D盘活动工程/工具安装、al_ip/**、约束ADC、原00_all.tcl/00_all_debug.tcl、原production/debugSDC、协议合同、RK代码、.git对象/refs/index及未经批准的HEAD变化。禁止批量删除/reset/clean、Flash、推送、下载旧任务/无关硬件、外部消息/自动监控。新候选在run内并列保存；仅本任务有明确必要时修改允许文件，不提交基线dirty，worktree-only+manifest可接受。

## 执行预算与停止
规划本次<=30工具/15min；读取搜索由Start-Job Wait-Job -Timeout60实际控制。
B01 DEV预冻结<=80次工具/90min，TEST<=45次工具/60min；理由是明确批准两RTL任务共用一个约10–12min生产实现与完整1080p回归，扩大的是有限执行预算而非范围。每次实际修复上限同值，但不得自动耗完。T08 DEV/TEST各<=30次/45min；T02 DEV/TEST各<=20次/30min（用户等待不冒充命令仍在跑）。
命令deadline/可安全终止要求严格按guide；每批最多1+1次有新证据的TD尝试，不为成功产物重复构建。单问题<=3轮目标读搜；同失败命令首次+1次有新证据重试；连续2轮无进展/时间工具到限主动blocked。Worker调用/命令轮询计数。DeepSeek仅有界低风险辅助；遇API错误不自动重试，不替代角色/硬件/最终核验。
共享bit/CWC/DB/板卡唯一候选/独占窗口，发现他人活动/来源漂移即停止，不杀他人进程。恢复入口：本run request+dev-plan+guide+最新manifest/报告交原规划；不得探测旧OpenCodeID/重置修复与机会计数。

## 之后主题（最多3条，不自动续做）
1. G4长稳/持续吞吐/剩余优化（request原文“后放”）。
2. 双相机真实主从/电气/曝光同步板验（T08父范围）。
3. 压缩与PCIe/RK集成（本轮明确不接；不得复活在途旧队列）。

