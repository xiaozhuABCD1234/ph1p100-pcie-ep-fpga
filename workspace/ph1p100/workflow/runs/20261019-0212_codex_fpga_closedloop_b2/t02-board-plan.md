# T02 单A板级执行冻结 v2

依据：本run request.md、followup01—04、board-priority-supplement.md、两份B01 r0 integrated报告。唯一规划=/root/fpga_planner_b2。B01离线两包现已通过，T02立即优先，不等T08或优化。

## 当前证据与工作包
T06.codex-ddr-readback-int和T09.codex-production-int首次r0 integrated PASS，实际修复0；G0/G1/G2 pass，G3由本包承担，G4后放。正式仍四包、两级，每包最多五项步骤；本包单包batch=1，新开发和一个新综合tester，不跨用B01角色。
最终manifest=C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/workflow/runs/20261019-0212_codex_fpga_closedloop_b2/recovery01/B01/timing-continuation01/remaining-attempts01/candidate/manifest.json；SHA c7a40897166467f2beafb096701dba9cf836e1007d77ae03d90009d06f80d757，699项。生产6/6，不允许第7次或重复成功构建。最终SWNS+0.100ns、HWNS+0.020ns、STNS/HTNS0，完整CWC物理覆盖通过。
T06/T09子包done不能把父T06/T02/T11置done；T08原离线编译2次和恢复授权仍保留。

## 实际范围与五项操作
1. 开发只读核对本计划、两PASS报告、最终manifest全部项、bit/CWC/BID/probe-map和现有单A现场事实/独占板窗。先做无硬件准备，不能把用户数小时前在场当当前电源/接线/占用事实。
2. 当前现场事实齐备且无他人活动后，执行已审阅run_sram.py --execute一次，保存PH1P100身份、PID/cwd/命令/退出码/120s期限/非空日志；不启动服务、不扫描其它线缆、不自动重试。SRAM已经授权，无需再问许可。
3. 下载明确成功后用户打开唯一current.cwc，按question/checklist完成第1采样组：T1、至少20秒后T2；每个时刻camera和DHI分别采样，保留实例/时间/操作者/完整32位原文，不能伪称跨域原子。
4. 同候选核对两不同seq完整读回、实际源几何/ROI/相位依据、一次内部abort拒帧及确切随后good恢复。若现证据不足，先说明具体缺项再最多两组针对性补样（总3组），不盲点、复位重注入或重复下载。
5. 停止活动后冻结T02记录/manifest（引用B01不可变manifest和hash，纳入新现场原始证据），一位新综合tester独立验收同输入。缺门槛明确blocked，不能只给准备文档PASS。

## 写与保护
开发实际工作目录=C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道，仅写C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/workflow/runs/20261019-0212_codex_fpga_closedloop_b2/board/t02/；run_sram.py固定在C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/workflow/runs/20261019-0212_codex_fpga_closedloop_b2/board/sram-b01-<实际时间>/落本次日志，此动态单目录是额外允许输出。T02 tester仅写C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/workflow/runs/20261019-0212_codex_fpga_closedloop_b2/test-reports/下本任务报告及隔离审计。
生产源码/全部旧run/B01已冻结699项、planning-inputs、原报告、bit/CWC/BID、脚本/Tcl、IP/ADC/SDC、T08、其他工作树/D盘工程/工具安装/.git/global均只读。用户经GUI生成的采样只保存到board/t02/。不改传感器表、相位、几何、时钟、接线或电源，不运行构建、编译回归/CLI读回。
planner复核确认B01 manifest不含sync_offline/sync-offline路径；本派发不自动启动T08，避免与首次JTAG下载窗口/当前用户操作交错。原T08仍ready queued，人工依赖若持续由原规划决定其既有独立恢复，不能遗忘或另建任务。

## 量化验收及具体字段
functional/G3：camera instance auto_created_cwc1，DHI instance auto_created_cwc2；源probe-map定义40项完整32位。必取source_good/bad/crc/header/geometry/injected，algo_identity和三complete/crc、overflow/rejected；DHI必取cl_identity/seq/session/base/len/words/flags/header_crc/payload_crc/pass_count/fail_count/writer_good/writer_bad/recovery_count/fault。
cl_identity=0x434c0101，algo_identity=0x414c0101。至少两个不同seq，均words=648192，len=2592768，flags[31]=1，flags[3:0]=15，flags[15:8]=0，fault=0，pass_count推进。CRC数值随真实图像变化，不比较合成常数。
source_geometry={last_lines[15:0],last_wc[15:0]}，即高16位源行数、低16位源RAW字节数；记录原数与解码。源模式/ROI X960/Y540/W1920/H1080/SKIP37和实际输出合规依据须解释，不将源几何误当ROI1920x1080；不擅改数字以凑PASS。最终候选PHASE=3（旧v1文字phase0为历史占位）；物理Bayer相位仍未证，计数/颜色观感不能证明。无有效现有配置/标定/真实图样依据保持unknown，T02完整几何/相位门槛blocked，保留已过读回子结果。
一次内部abort必须source_injected=1，writer_bad及拒发布路径与之后的cl_recovery_count>=1、确切首个合法发布good通过全checker建立因果；旧pending帧不算恢复。该证据不等于物理CSI CRC故障。若只拍到最终sticky计数但不能证明必要因果，记录partial，不以更多无目标点击替代证据。
engineering：复用同manifest B01 G0–G2，下载前后SHA不漂移，SRAM device/命令真实成功，CWC匹配，采样同域相干且可复核。无新构建，无改变的离线检查不重跑。DDR校准异常/无法读到完整校验/身份不符/非零错误立即保留停下，不能继续点击冲淡失败。
system：用户当前在场事实、操作者、实际时间、原接线/供电/单A、负载/窗口/占用、未测边界和回退记录。本轮短窗>=20秒与恢复必要，G4 10分钟/热/长稳性能用户后放，不外推双路/PCIe/RK/算法实际图质。

## 用户等待及失败路径
先原样转question-t02-current-window.md；原开发可同时完成无硬件preflight并返回准确ready_for_operator状态，未收到现场事实不执行SRAM，不空等、不发起反复查询。用户回复由主原样保存并续实际T02原开发，仍同任务/预算账。板测GUI人工，不尝试本机不支持的原生自动化。
缺工具/服务/板卡/用户样本立即blocked，problem_id按task+稳定根因，证据与准确恢复入口齐备；不能以整理机会变设备重试。输入漂移交原规划。下载失败不自动再下；保留日志，按已绑定旧bit/CWC给可审查回退建议；需要断电10s等实际恢复只让用户按明确步骤做，不能自动电源循环。
回退pair来自原board-entry：bit bfafdf97ff78d6f6d2646ffc706542a0bbbb7e11869043ba754cf68a270813d0、CWC 8d2998b96ef1763c14a1302118235a687488297ce496692b1f6cd95d76981026，仅保留入口，不自动执行。

## 有界预算
T02 DEV与TEST各30工具/45分钟每次有限派发（原20/30提升以覆盖699项身份核对、一次120秒下载、成对实际样本及报告；不扩大范围），实际start/deadline先落盘；用户等待到依赖点返回，不作为后台运行。read/search60s；局部静态300s；一次SRAM120s+自有进程树安全终止；采样每组至多5分钟收集；同候选总3组；无构建额度，生产6/6。连续2轮无进展、单问题3轮读取、同失败操作最多首+1有新证据纠正（下载例外：本派发仅1次）到限停。只跟踪本角色拥有的进程，绝不杀他人TD/BW/server。
首次T02 integrated=r0，实际修复0；FAIL且无外部block再按原T02 dev/test真实ID最多round1—3，仍不能自行扩生产6次上限或改B01。根删除禁令/完整DeepSeek约束与仅SRAM、不Flash、不PCIe/RK、不推送继承。
\n计数澄清：一个采样组包含T1/T2两次采样，两时刻间隔>=20秒，每时刻分别保存camera/DHI。先执行1组；最多再补2组，总3组（最多6个采样时刻），每次补样先给明确目的。用户清单中的第一/第二次不是两个独立组。\n