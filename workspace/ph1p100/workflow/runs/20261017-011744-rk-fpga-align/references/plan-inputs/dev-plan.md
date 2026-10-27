# 可验收工作包与持续派发

run=20261017-011744-rk-fpga-align，batch_size=1。用户授权推进适配和必要板验；主只转发。每包新开发/三测试，所有角色禁止递归派生；本规划者持续更新。

| task_id | 问题/产物 | 实际工作树/允许写路径 | 依赖 | functional | engineering | system | 必要G层 | 初始状态/下一动作 |
|---|---|---|---|---|---|---|---|---|
| T03.rk-align-freeze | 先完整备份可恢复起点，固定三仓版本，生成分工/接口/RK修改包和后续输入 | 当前根；本run的backup/references/contract/artifacts/evidence/lessons；不改生产RTL | 无 | 重新计算尺寸/寄存器，检查分层头和CRC，列出旧行为负例 | 备份zip+git bundle校验、dirty归属、pin SHA、工具真实版本、恢复清单 | 对应实际peer源逐项交叉检查，RK清单可执行、硬件窗口与回退明确；G3不适用纯备份合同 | 局部G0/G1，G2—5不适用；双方正式签收仍待 | ready→新开发 |
| T07.rk-align-backend | 真正引入匹配EP核/后端，接入本方checked CSI，修DMA边界/锁存/所有权/包内反压；可构建独立候选 | 新`fpga/csi2/pcie_integration/`、`tools/pcie_integration/`，本run candidate/evidence；不改旧主线 | 上包PASS | peer TB+独立TLP oracle，BAR/endian/CRC、+16负例、容量/4K/反压/timeout/reset，checked真实连接 | TD6.2.3最终DB/STA/资源/约束/CDC/IP与bit manifest；旧代码不漂移 | top完整连线、RK补丁/参数一致、回退和板测准备；G3留给单独实际硬件包 | G0(局部)/G1/G2；G3—5不适用此component产物，不声称DMA实收 | waiting_dependencies |
| T11.rk-align-raw | 1080p packed RAW10+R10F零填充→AXI缓存→peer发送，全帧CRC/持有/ACK，RK局部补丁及严格解析工具 | 同新目录；本run交付包 | 后端PASS；真实几何待板测前核实 | 缩小+完整几何仿真，逐样本/CRC、EOF坏帧禁止发布、RAW尾/容量高位/溢出/序号、consumer慢和复位 | 同候选最终STA/CDC/资源/bit，所有构建入口与参数冻结 | 驱动/用户态补丁apply-check、64/32地址、槽布局/ACK/严格解析，实际板验包可操作 | G0局部/G1/G2；G3/G4单列下包，G5未完成 | waiting_dependencies |
| T07.rk-align-board | 同一最终bit真实SRAM板验：链路/BAR/合成PCIT或R10F固定数据、UART/JTAG计数、恢复 | 只允许本run证据/工具；硬件system独占 | 后端/RAW至少一个最终G2候选；可用JTAG/主机通道 | 固定块/帧预期字节与实际一致，CRC/长度/计数 | 最终DB/bit与板用SHA相同，CWC适用检查 | G3真实器件/时间/操作者/下载日志；若RK可达则实收100帧零CRC错，恢复1次；无RK时仅板内证据不可当DMA实收 | G3必需；G4短稳10min，记录负载/错误/帧率，无法实收保留blocked | 条件待查询；不阻塞上方代码包 |
| T11.rk-align-release | 用户可审阅组合版、RK修改清单/patch/样例/命令、完整备份回退、界限与下一入口 | 本run release、handoff/final-summary/user-summary；规划可定向更新tasks T03/T07/T11/records | 有已冻结产物即独立整理；真实硬件未过明确⚠ | 发布内容与验证身份一致 | 清单hash/重现命令/原始证据/失败留存 | 将RK必须修改、可选优化、未测条件清楚列出 | 仅G5交付可恢复性子范围；不等于端到端G5 | 待上一包结果后派发 |

上述局部标签沿用原T任务，不新增全局ID。单包“done/PASS”只对预设子范围成立。T03全局仍待双方签收；T07全局仍待真实主机DMA；T11全局仍待压缩/真实端到端，不能因本轮非压缩版完成而转done。

## 首包开发具体要求

读`task-T03.rk-align-freeze.md`；仅本run内写。先保护dirty和回退，后产生合同/后续输入，不应耗时重做旧工具安装或DDR1333调参。本包只收工具和硬件接入事实，不运行生产构建、不下载硬件。

## 修复、停止与回退

round0首次验收，round1—3最多三轮实际修复。FAIL按原开发/原测试；每次重冻manifest与复测维度清单，不拼不同输入PASS。缺必需工具、板、资料/额度直接blocked交原规划，不消耗修复轮。三轮未过保留⚠，派发仍可独立RK包/交付包。

备份未独立校验前不做生产修改。禁止删除、reset/clean、覆盖旧候选/其他run、外部D写入、向peer推送/发消息、Flash与自动化。只在新文件新工程实现，恢复通过新目录解包/选回既有002820 bit，不把备份覆盖到dirty目录。发现源漂移/别的硬件操作者停止共享资源动作并交原规划。

板验不是因为“明天”而省略；“明天看到组合版”以实际候选状态、已验证范围与未测条件交付，不预言完整双路性能通过。系统具备条件则直接执行已授权SRAM板验。无RK通道先交FPGA板内证据和RK必改包，缺口不阻塞本地适配。
