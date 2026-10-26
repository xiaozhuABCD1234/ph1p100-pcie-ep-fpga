# 有界开发与验收计划

run=`20261024-221529_fpga-sim-integration-recovery`，runtime=Codex，batch=1。主只按dispatch机械传输；角色不派生代理。根删除禁令及DeepSeek最小输入规则继续有效。

## 范围与任务最小表

本轮一个主要目标：把用户图片所列 FPGA 相机链路离线仿真缺口转成可独立复跑的正式证据；两正式包、需求→工作包两级，各≤5语义步骤。两包分别对应用户两条，使用不同源码线，各自验收，不能互相拼证据。无新全局T编号。

|task_id|问题/产物|实际工作树/允许写路径|依赖|functional|engineering|system|必要G层|状态|下一动作|
|---|---|---|---|---|---|---|---|---|---|
|T08.sync-production-sim|真实生产RAW顶层派生同步I2C/双路数据仿真overlay、TB/runner/结果/manifest|仅本run `T08.sync-production-sim/**`，输入只读`inputs/production-raw/**`|现有同步小顶/生产RAW源码已冻结|14笔引脚I2C/独占接管；warmup/整帧门控；A/B数据逐字节；NACK/缺路/reset；有效负对照|真实top精化Errors0；CDC/reset/参数/格式审计；真实deadline；唯一manifest漂移0|无共享树写、设备/TD/盘符；环境桩边界完整|G0/G1；G2=not_run；G3/4/5=N/A，理由见guide|ready|新开发→冻结→一个新综合测试者|
|T10.a1-recovery-sim|固定r5真实DUT的中写reset/坏帧/overflow恢复TB与可定位结果|仅本run `T10.a1-recovery-sim/**`，输入只读`inputs/a1-r5/**`|输入齐备；与T08无技术依赖，batch1仅顺序|注入命中；拒坏/整帧drop；有界恢复；真实解码四CRC/0重复/0尾|固定8RTL SHA；明确epoch/延迟响应/握手；每case deadline；变异负对照|不改板候选/核心吞吐/协议；故障计数与reset清零分轮|G0/G1；G2=not_run(固定RTL测试)；G3/4/5=N/A|queued_ready|T08回原规划收束后新开发，不跨任务复用|

## 每包语义步骤（不再拆子ID）

T08：1. 从冻结生产树建立最小同步接管overlay并形成差异，保持sync关闭旧行为；2. 用真实ui_i2c与引脚sensor模型、包层数据源、DDR环境建立真实top集成TB；3. 按guide完成正常/故障/数据门控及反例，输出机器可读结果；4. 记录实际命令/范围/限制，停止全部修改和活动并冻结唯一候选manifest。

T10：1. 给固定r5真实DUT建立握手/epoch观测和DDR故障模型；2. 新建明确clean/raw-midwrite-reset/encoded-midwrite-reset/bad-frame/overflow用例与命中断言；3. 完成有界恢复/独立字节解码和针对性反例；4. 输出场景结果与复现入口，停止全部修改和活动并冻结manifest。禁止顺手修RTL或优化吞吐。若真实RTL缺陷导致失败，交付定位证据并blocked交规划，不改DUT掩盖结果。

## 门槛与独立验收

- 公共：所有必须场景实际运行；vlog/elaboration Errors0，无未说明的目标端口/宽度/时钟告警；正例明确PASS且mismatch=0、无Fatal/错误断言/超时。不能仅exit0判通过。反例必须正确编译后被目标断言拒绝。
- T08：双路初始化安全且唯一I2C所有者，14笔及两次等待、8帧warmup、首次完整放行、连续≥3对可接受帧，A/B源标识、地址、字节、长度/CRC和单次发布正确；NACK、单路缺失、重启/全局reset场景不误ready、不发布半帧，恢复重新warmup。引脚独立解码检查不能读取DUT内部期望表。至少一项角色写值或A/B路交换变异会失败。
- T10：guide五类case全部命中；每个异常之后≤4个good输入且≥2正确完整输出、最后good FE后≤1,000,000 clk_a1，四CRC/严格zlib、0重复/0旧epoch字节/0尾垃圾；坏帧/overflow至少一个真实相应计数增量，复位前后分别记录。至少一项把旧epoch输出冒充恢复或删除故障触发的检查器负例被拒。
- 一个独立综合测试者独立重编译、重跑关键正常与全部故障case，另用引脚解析/标准zlib或checker变异等不同判据；不得只审开发日志。验证输入前后SHA=manifest、保护输入漂移0，报告各自三维/各G层/未测边界。
- G2/G3/G4不因本包PASS自动升级；真实硬件父T08/T10保持未完成。若新增生产实现/写域才可做完，本包应blocked，不能临场改不适用来PASS。

## 工具与有限预算（派发前冻结）

ModelSim Intel FPGA Edition10.5b入口 `D:\intelFPGA\18.1\modelsim_ase\win32aloem\{vlib,vlog,vsim}.exe`；Python `C:\Program Files\Python311\python.exe`。本轮只调用仿真/静态/标准解码；TD/综合/route/bitgen/CWC/download/Flash=0。无板卡或PCIe主机需求，不占用硬件/共享TD会话。

T08开发每次派发≤60工具调用/75分钟；独立综合测试每次≤45调用/60分钟。T10开发≤45调用/60分钟；测试≤40调用/45分钟。此为有限覆盖值：完整生产顶层环境、引脚级I2C/真实A/B writer和故障注入比旧小顶需要更多一次性准备，未扩大目标/包数/层数/硬件权限。规划仍30调用/15分钟。

每读/搜实际timeout60s；每局部静态/编译/单case仿真实际300s。runner启动前用subprocess timeout/拥有进程PID树安全终止或等效工具实施；yield不是timeout。每case TB同时有cycle watchdog。进程终止只针对本角色创建的PID及可证实子进程；不能扫杀全局vsim/TD。无实际控制直接TOOL_CONTROL_MISSING。

单问题搜索≤3轮；同失败命令首次+至多1次新证据纠正重试；同一输入盲重跑禁止。开发每包每次最多2次全量compile，每个冻结case最多首次+1次有新证据重试。测试每次1次独立compile，必要新证据纠正最多1次；不是自动重试授权。连续2次无进展、工具/时间到限、源漂移、缺输入/设备/权限/API/额度立即blocked；不自动扩预算。每次派发完整记账，不以shell内循环绕调用/次数限制。

round0首次验收，round1—3最多3轮实际修复，续真实原开发/原综合测试；只修本包允许的overlay/TB/model/checker。固定r5 DUT缺陷不在本包修复范围，直接原规划备下一轮条件。缺工具/权限不空转修复轮。相同problem按relay-contract稳定身份/固定reason_code登记最多2次有新信息补充机会，元数据与实际修复分账。

## 写域、保护、冻结与回退

根、upstream、fpga/csi2、tools、所有旧run/探索work、D:\TD、D:\fpga_work、docs junction、其他工作树、共享盘符完全受保护；本轮不替换另会话输入/候选，不做git操作、不批量删除、不发消息、不安装工具/自动化。

开发只写各任务目录，测试只写本run `test-reports/<task_id>/**`及该任务`<task_id>-r<round>-integrated.md`；测试不改开发候选。规划写本run控制文档与新`workflow/records/T08/20261024-221529-sim-plan.md`、`T10/...`记录，收尾在最新任务板上只增相关证据/状态说明（保留其他字段和父任务状态，检测并发变化）。

开发manifest必须列真实source→overlay差异、参数/所有RTL/模型/TB/include/checker/runner/工具版本/命令及SHA、独占工作库、环境模型限制；`stopped_modifying=true`和`active_commands=0`。仅此之后主spawn一个综合测试者。仿真环境文件也进manifest，厂商stub不能被隐去。报告绑定manifest SHA，不沿用旧输入PASS。

回退=原生产/板候选从未改变，保留全部失败日志和本轮overlay；不删除任何目录。T08包无论PASS或blocked，原规划记录实际证据后可派无技术依赖的T10，不重复耗尽失败包。全局任务板在两包/阻塞明确后最小追加，父T08/T10不置done。

剩余主题最多3条：①同步overlay迁入生产的完整G2和真实曝光同步/恢复；②固定r5若发现的RTL恢复缺陷修复与相应G2；③既有压缩吞吐缺口（本轮不修）。原需求入口保持request.md，不自动续做。
