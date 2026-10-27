# 本轮工程冻结指南 v1
项目根=C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道
生产写树=C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/upstream/ph1p100-pcie-ep-fpga
输出根=C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/workflow/runs/20261019-0212_codex_fpga_closedloop_b2
依据本 run input-index、dev-plan 与既有 R10F/KIT；不创建新传输协议。

## 数据、几何与帧语义
- 正式存储继续 packed RAW10（四像素40bit按既有 writer 打包），R10F v1 128B 头，小端；W=1920,H=1080，payload_bytes=2,592,000，header+payload=2,592,128，DMA/frame_bytes=2,592,768，尾零640B。不得把 u16 容器或 Gray8 输出写入同一 RAW10 类型。
- 源配置仍4K模式；ROI X0=960,Y0=540,SKIP_ROWS=37 均为待板证配置值。基线实读 last_lines=2192,last_wc=4830 仅原始诊断。保留完整源几何与 ROI几何的区别；不擅改传感器、翻转、SKIP_ROWS或相位以凑 PASS。相位0占位须明确；几何/相位不符时回规划，保存原样本。
- 完整帧发布须等 good/CRC/FE与所有写响应成立；abort/CRC/缺FE/溢出拒整帧，下一合法帧恢复。CSI不可反压；算法阻塞不能回压传感器或损坏 RAW writer。
- 保持既有地址 A 0x00100000/0x00900000、B 0x01100000/0x01900000，实际 DDR_CAP_BYTES=0x10000000（256MB），AXI窗口29bit并不等于物理容量。检查地址高位、base+len溢出及互不重叠。

## 读回与所有权（T06）
复用 ddr_frame_readback_checker 原核与独立 CRC 校验。AXI读 256bit/32B拍、INCR、arsize=5、burst<=128，不能跨4KiB。header_crc=头word22置零后的128B；payload_crc覆盖精确packed载荷；尾零不进CRC。完整1080p读取81,024拍/648,192个32bit字。
- 仅对已完整发布的单A帧开始，锁存 seq/base/len/session；读期间对应buffer必须持有，writer不得覆盖。完成/错误/abort后按明确协议释放；不能用两次读seq相等代替所有权。复用现有保护/释放机制时，必须证明不会误释放 pusher 或B的槽位。
- 同DDR读口与既有 pusher 仲裁：事务/突发边界锁定owner、RID/响应/last归属正确、背压保持、无串响应；关闭诊断时原 pusher 行为等价。当前无PCIe主机，不启动push/TX/doorbell；不删除已有接口。
- 自测只在本轮诊断候选参数开启，生产缺省保持旧控制语义；debug-only 自动采集/校验不得受 PCIe link_up 复位钉死。已有 dbg_por_rst 修复保留。
- timeout沿用2^21拍单次无进展上限；不无限重启。读错、abort、异常RID/rlast、参数非法 fail-closed，错误不补全ok位。
- 板级坏帧证据可用明确标注的 debug-only、一次性、可恢复的内部 abort 注入，在真实采集的一帧上拒发布，并观察随后真实good帧恢复；不得称为物理链路CRC故障实测。自然坏帧为0只证明短窗观测，无注入/自然触发就把坏帧门槛记blocked/not_run。禁止在原生传感器配置或外部线路制造故障。

## 三算法生产接入（T09）
- 只读引入已冻结 fpga/csi2/src/img 真实RTL及 provenance 到 production 新目录 rtl/ep_side/img/algo/；不重写已验算术，不用回放stub。共享 Bayer->RGB8->4px灰度前端，灰度/高斯/CDF-min前帧HE三分支独立硬件并行。
- 输入四像素40bit，cfg_width/height12bit、phase2bit；沿用 W%4=0、8<=W<=MAX_WORDS*4、2<=H<=2048。以与 RAW writer 相同的 ROI语义适配单A真实CSI流。
- 接受=valid&&ready；stall保持data与sof/eol/eof/abort；三输出独立32bit Y8流。前帧HE首帧identity、合法完整前帧才发布LUT、CDF-min舍入/饱和及四同bin补偿沿用参考。
- 实例必须在最终生产工程文件表、真实相机数据路径与最终实现网表中保留；三个输出接实际计数/CRC诊断sink以防优化掉，不得只拷贝源文件、只实例小顶、常数输入、黑盒、串行复用或断接输出。
- RAW存储仍独立；算法长stall/忙碌须拒本算法整帧并计数，不回压CSI、不影响RAW发布；partial算法帧不得对外当完整输出。不得声称算法输出已写DDR或已被RK接收。

## 同步离线起步（T08）
范围是新增离线可综合配置/同步控制RTL与TB，不接生产顶层、不改当前传感器表/引脚、不下载。候选A主/B从；启动前B输出Hi-Z，A准备后才能输出；B先准备、A后开流；退出待机>=24ms、前8帧初始化期以参数化计数实现。沿用本地硬件证据表，仅白名单角色寄存器允许生成。
必须用 I2C 应答/超时仿真验证两路安全排序、NACK/timeout/单路缺失/复位停机与重入恢复；两个独立CSI SOF事件经合法CDC进共同测量时基记录配对/偏差。SOF配对只作数字逻辑正确性，不能代表曝光同步。模块内部联系/电气/厂家歧义及真实双相机窗口未满足，硬件集成维持blocked。
离线模块仍需自身 G2：TD综合/最终实现STA及CDC/资源审查；不借“离线”免 RTL门槛。若可与本轮唯一生产实现共享数据库且确有真实约束/保留实例才可复用，否则小顶单次实现，独立候选不下载。

## 时钟、约束与构建
保留原生产/调试 SDC 的 sys_clk 20ns、cam_*_clk_lane 1.333ns、cam_*_byte_clk divide_by4（约187.5MHz）、IP派生时钟与已有异步分组。新控制多位跨域用稳定总线握手/异步FIFO；两级采样多位诊断不作控制或完整性真值。新增CDC列出源/目的/复位/方案并检查最终实现；不能增加宽泛false_path、multicycle或降低频率求PASS。
B01优先一次合并 TD生产诊断候选构建：沿用 run_td.ps1 入口，新增 -Stage 00_all_closedloop，独立tcl/顶层/输出目录；不能覆盖基线bit/CWC/DB。原00_all/00_all_debug入口及生产SDC保持原文；新stage可列新增模块与必要新debug wrapper。run_td.ps1 的TimeoutMin参数当前未落实等待，不能当有效deadline！
实际命令必须在新run记录精确cwd、入口、参数、PID与进程树deadline控制。读取/搜索60s；每个局部静态/TB300s；TD构建1800s；ChipWatcher后处理300s；一次SRAM下载120s。用 Process.WaitForExit(ms) + 只终止本次启动PID及其子树（例如taskkill /PID <own> /T /F），或Python subprocess超时且可安全终止自身子树。exec yield只是回显。不得杀他人TD/BW/hwserver；不支持控制则不启动并reason=TOOL_CONTROL_MISSING。
每批最多1次预定最终构建，只有新证据明确支持的失败修正才允许第2次；同失败命令总计最多2次。成功后测试者核对同DB并重跑必要G1，不默认再构建。若独立审阅发现必须重建则说明原因、绑定新manifest，受同轮有限预算。

## 验收、候选与上板
G0=冻结输入/局部静态；G1=真实DUT仿真/独立oracle；G2=最终同DB Routed、setup/hold WNS>=0、TNS=0、全部适用clock组0违例、约束覆盖/CDC/资源在器件内；不降低原目标。新逻辑必须在最终网表存在。
G3仅T02板包：新候选相机实采，读回CRC/长度/seq、真实几何、一次坏帧拒绝与恢复；G4保留后轮10分钟/长稳性能，本轮只做G3所需的最小连续短窗与恢复。旧G3/G4不得挪用。
CWC须 setup_debugger -prj 生成，完整BID物理ERAM覆盖校验（真实多片用现有 --multipiece 口径），配对bit/CWC/DB同源。开发在构建前冻结 probe-map：至少含身份、seq/base/len、checker done/ok/err、通过/失败/拒帧/恢复计数、源几何和完整32bit帧计数、三算法有效完成/拒绝与校验诊断。位宽/实例可用一个或少量同域CWC；跨域/实例不得伪称原子。优先保持两次GUI触发即可看完关键结论；两张图不保证门槛足够。
“回来点两下”清单由开发填唯一新bit/CWC/manifest/预期/停止/回退，仍缺证据时不能填PASS。GUI人工；CLI读回关闭。仅SRAM、不写Flash、不接PCIe/RK、不推送，不改线/电源/相机物理连接。出现校准异常保留证据，由用户现场按既有断电10s SOP；不得自行反复电源循环。

## 冻结结尾
已冻结：本文件接口/参数/范围/三维/G层与deadline。待板证：真实有效图几何、Bayer相位、短窗坏帧触发/恢复、硬件在场窗口、双相机曝光证据。不适用：压缩/PCIe/RK、真实双路同步、深度/NPU、长稳优化/Flash。本轮三维边界与逐包门槛见dev-plan，缺条件直接blocked，不能中途改不适用换PASS。

## 2026-10-19 B01 r0通过后的T02即时板验
当前最终PHASE=3，旧phase0文字为早期占位；真实物理Bayer相位仍未证，不将计数或外观当相位证明。B01离线G0/G1/G2同699项输入独立通过，门槛与约束没有降低；setup+0.100ns、hold+0.020ns、两TNS0。生产6/6不重建。
T02采样camera auto_created_cwc1、DHI auto_created_cwc2，source_geometry高16位last_lines/低16位last_wc；跨域非原子。完整帧words648192/len2592768、两个不同seq、flags[31]=1/低4位15/error0/fault0、通过计数推进、真实几何/ROI/相位有效依据、一次内部abort拒帧及确切随后good恢复全为必要门槛。未知项blocked，不能把准备文档PASS。
当前唯一入口/保护/期限/用户操作见t02-board-plan.md与board/t02/two-capture-checklist.md，旧“无新bit/CWC”模板失效。B01快照planning-inputs不修改；新指南当前原文与快照版本分别保留。G4长稳后放。
