# B01生产时序有界续接（同run、同任务、原开发）
原规划/root/fpga_planner_b2；输入dev-return-recovery01-b01.json及recovery01/B01的development-result、problems、attempt-counts-verified、两报告、manual-engineering-review和attempt3实际路径。
用户followup01明确继续完善并给足够尝试；followup02当前在场；followup03偏好多上板。原四包/两级/批2、仅SRAM、不Flash/PCIe/RK/推送不变。本计划只续当前T06/T09，非新run/新任务，不把G4优化加入范围。

## 已核实事实及资格
- B01旧TB编译问题已恢复，原联合writer/checker累计6/8，包含完整1080p words648192、CRC/长度通过；控制20例、实际RAW+算法overflow/坏帧/恢复、top一次注入、varying adapter oracle、core24与HE负对照、1080p两帧服务都有作者本地成功证据。不是独立综合PASS。
- 当前manifest=C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/workflow/runs/20261019-0212_codex_fpga_closedloop_b2/recovery01/B01/candidate/manifest.json，SHA5A5EBF3D5160C28DADB81684BA048BCCA3C1FE6D66091175F09D07D988B1547B，415项规划重哈希0漂移。ready_for_test=false，无独立r0，实际修复0。
- 三次生产命令已真实消耗：attempt1/2各在1800秒超时（已到routed检查点）；attempt3从未改的attempt2 routed检查点完成post-route/导出/CWC。生产命令总3/3，不伪称三次均完整重实现，不自动第4次。上一角色正确停止。
- 最终同库SWNS=-0.766ns/STNS=-38.113ns，HWNS=-0.075ns/HTNS=-1.242ns；实际RAM/DSP/各资源在器件限内，三算法网表保留、CWC物理覆盖exit0、bit配对相同，但这些不能抵消STA失败。bit8048eb88…938与配对CWC只归档为rejected，禁止下载/板验。
- 实际setup最差从HE st状态到demosaic row bank enable，约-0.766ns；当前增加的数据寄存未完整切开反压控制组合路径。hold分布在TL图源、DDR物理IP和部分CWC/CSI路径，最差-0.075ns。引用attempt3/critical-paths.json与manual-engineering-review；这是可检查的物理路径，不是凭报表猜根因已修好。
- 原attempt-ledger开头含早期中间计数，最终以attempt-counts-verified和真实日志为主：controller5/6、T06full6/8、oracle3/6、injection3/6、RAW+algo2/6、core2/6等；不得取陈旧低数重置。

## 为什么可在已有授权下具体继续
旧3次是原规划在用户明确“足够尝试”授权下冻结的执行预算，不是用户指定的固定最大数。当前角色已停止；原规划在新派发前根据新的实际post-route路径及两次1800秒超时证据，作一次明确的有限执行预算修订。本次不是运行角色自行扩预算或偷偷第4次，不换ID/目录清零，也不取消任何验收门槛。
这项修订仍属用户已授权的T06/T09生产接入常规完善，无需重复询问是否允许原范围RTL纠正或SRAM权限。新增次数和更长deadline一次性明确如下，不授权第7次或无限循环。若本次仍不能闭合，必须回原规划，保留失败，转已授权独立T08或明确外部/范围条件，不连续自造新phase增加次数。

## 本次预算（覆盖本次生产3次上限及旧1800秒deadline）
| 操作 | 已用/不清零 | 本次最多 |
|---|---|---|
| B01生产原生命令/实现 | 3次（含2 timeout及1 checkpoint完成） | 追加3次，编号attempt4/5/6，累计最多6；开发与同候选独立核验共账 |
| 每次完整生产实现实际deadline | 已有1800秒超时证据 | 3600秒；包括应执行的原生实现/导出；单独CWC后处理600秒 |
| 本次DEV续接 | 前次调用账保留 | 150工具/240分钟；理由=3×最多60min物理实现+必要局部纠正/验证/冻结；上限非必须耗满 |
| 一个新综合TEST | 还未创建 | 60工具/90分钟，优先检查同DB、目标G1和最终输入，不默认重复成功实现 |
| T06已失败编译操作 | 6/8 | 不额外增加，剩2；输入未受影响的成功证据可绑定新manifest复用 |
| 其余G1操作 | 继承最终真实账，例如controller5/6 | 仍累计最多6，未修改依赖不无谓重跑；独立检查与纠正尝试分别如实登记 |
| 实际修复/问题机会 | 综合r0未发生、实际修复0、补充0 | 保持，不把本次开发续接写成round1；综合之后最多round1–3实际修复 |

读搜60秒、局部静态/每TB300秒保持；未来SRAM下载120秒保持。所有命令启动前执行真实timeout/owned PID树终止并留日志，yield不是timeout。只终止本次启动的进程，不杀他人GUI/BW/hwserver。发生无新证据重复、连续2轮真正无进展、预算到限、工具设备/权限/额度或范围冲突立即返回。成功实现后不为新seed重复构建。

## 纠正方向及受影响验证（具体实现归原开发）
1. 按实际setup起终点检查ready/valid组合回路，形成真实弹性RGB/sideband边界或等价局部结构，使前向数据和反压控制都满足切分要求；不能只再插数据寄存而保留同一ready长链。保留四像素顺序、接受条件、同拍take/refill、stall保持、abort/FE/LUT发布、RAW与算法隔离。不得改算法算术、拆掉分支/诊断或以断接输出改善时序。
2. hold在protected DDR/IP及TL/CWC多处，先审查native实现阶段是否完整执行、工具已有真实hold修复/优化入口及对应报告。只用本机工具help/官方本地文档证明的合法命令/选项，不猜参数、不纯换seed盲赌。允许修改本run专用实现Tcl/脚本和原允许的closedloop专用stage；不编辑al_ip源码、原ADC/生产SDC/旧debug SDC，不降低频率或新增宽泛false_path/multicycle豁免。
3. 每个新生产attempt前写精确修正假设、变动文件/依赖、预期路径/指标；至少检查setup与hold同时改善以及时钟覆盖，不能只看WNS一个数。若结构修正改变受压/延迟，先重跑真实三算法core/varying adapter/负对照/sideband hold/abort/overflow/RAW隔离与连续1080p服务；检查oracle未被修改成迎合新实现。
4. T06writer/checker/控制未受影响的实际DUT依赖不变可由最终tester写依据绑定复用；不把整个compile列表含未用模块变化简单当全库必须重跑。失败和受影响项必测。已通过且同输入的证明不循环重做，更不为可选G4/观察矩阵延迟首次合格候选。
5. G1满足后运行实际完整实现。原时钟、setup/hold WNS>=0/TNS0、适用时钟组0违例、约束覆盖/CDC/复位/资源/CWC物理覆盖与bit配对都必要；check_timing遗留PLL-lock/TL-CE/dummy pad/no-I/O-delay逐项给边界依据，不能一概当已豁免或覆盖PASS。成功才冻结并ready_for_test；final DB/report/bit/CWC必须来自同一实际成功候选。

## 产物历史、允许写和下一步
本次OUTPUT_DIR=C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/workflow/runs/20261019-0212_codex_fpga_closedloop_b2/recovery01/B01/timing-continuation01（仅同run证据子目录，不是新run或计数重置）。旧recovery01/B01目录的报告/账/415项manifest/失败bit与DB不覆盖；新报告/日志/attempt4–6输出/manifest在本次OUTPUT_DIR，manifest推荐candidate/manifest.json。实际源文件修改前保存上一冻结版本与SHA/diff；变更后旧manifest标历史，不能假称仍当前匹配。
源写范围不扩大：原B01实际closedloop/algo/top相邻接口/TB/专用SDC/stage名单；保护T0826项、原IP/ADC/旧SDC/旧stage/协议/根规则/另工作树/D盘工程。不能为时序直接改受保护DDR物理RTL、传感器表、时钟或IO电气。实现设置只保存在本run专用脚本，不能改安装/全局配置。DeepSeek仍只能有界低风险辅助，不能代替复杂时序判断/原角色/最终验证。
当前阻塞不是GUI操作，用户在场无需先点击。新候选满足必要G1/G2/CWC及独立综合验收后，原规划立即优先T02实际单A几何/读回/坏帧恢复，遵守board-priority-supplement；T08不挡首次上板。若T06/T09最终仍因范围外IP/工具条件或本次6次总上限无法过，则保留blocked，原规划可续已授权T08原开发，不下载rejected候选。
返回严格合同与最终真实attempt账、失败/受影响检查清单/复用依据。仍未发生独立r0，不新增tester直到真正ready_for_test。
