# 本轮两包离线闭环完成

run `20261025-180900_fpga-dual-offline-closure`；实际工程根 `D:/fpga/ph1p100`。本轮两个原正式工作包均由各自唯一、独立于开发的综合测试者验收通过，范围仅规划事先冻结的离线G0/G1。本run完成，无下一实验或新任务派发；父硬件任务不置done。

|工作包|当前正式独立判定|实际实现修复|候选与当前报告|
|---|---|---|---|
|T08.dual-local-closure|round1 integrated PASS；functional/engineering/system pass|1|`T08.dual-local-closure/r1/mode-fix02/manifest-mode-fix02.json`；`test-reports/T08.dual-local-closure-r1-integrated.md`|
|T10.dual-aplus-scheduler|formal round0 integrated PASS；functional/engineering/system pass|post-acceptance 0|`T10.dual-aplus-scheduler/cmp-stall-fix01/static-closeout02/manifest-cmp-stall-fix01.json`；`test-reports/T10.dual-aplus-scheduler/r0/supplement02/T10.dual-aplus-scheduler-r0-integrated.md`|

准确SHA、唯一当前报告与历史FAIL的关系见 `candidate-binding-final.json`。T08 manifest SHA `38e0615341330aa5b8f1e0e1f9ecf4e169abbdc6bc4856912b9e4f929bdfcce3`；T10 manifest SHA `5db2b0ddf42c60426dd5a10a72614abf2bbe2306a3464be01474f7683e87f03b`。两个候选仍分别隔离，未合并、未迁生产或OpenCode活动候选。

## 完成与验证

T08闭合描述符stall身份保持、同拍外部AR/释放互斥、模式请求与发布同拍、真实读回期间持续新帧输入。原唯一测试者独立编译真实checked CSI/writer/CRC/sync/pin I2C闭包，14个fresh进程和112份数据对象检查通过；包含有效B释放误送A负对照。原r0 FAIL保留。I2C/sync旧部分由原测试者按72项源SHA、18参数和精确刺激绑定复用；变化的所有权/模式/重叠全部fresh。case16实际每路3个新SOF及1个其他槽pub落入AR至最后R窗口，保留2帧seq缺口，随后每路6good恢复。

T10完成真实A+ core/frame的双路调度、紧密RAW10 native DDR读、所有权/排空/LOCK/reset、双CMP持有与ACK及CMP全字段反压保持。原16个有效通过case覆盖几何/PREP、故障、full、持续公平、接口/容量/phase与2个有效负对照，122帧严格还原；最后一个未执行的原第20案例补齐4个同沿descriptor接纳/RAW释放及8帧全生命周期，总有效130帧。四行物理cycle3697/9134/14471/19344，释放覆盖A0/A1/B0/B1；完整身份、独立ownership和实际字节无失配。无DUT改动，因此补充仍属round0，未虚构r1；两份旧r0 FAIL和一次私有夹具编译失败保留。

规划最终只做报告、SHA/回执/记录静态复核，没有重复实验。T08的314项manifest绑定、81项独立编译源，T10的122项manifest绑定和各次精确编译来源及新旧wire字节一致；最终核对见 `final-closeout-audit.json`。两包均停止修改、活动命令0。

## 能力与未测边界

G2最终STA/物理CDC/资源未跑；G3/G4真实曝光同步、板级恢复、长稳/硬件吞吐not_run/awaiting_hardware。没有当前bit/CWC、板测或物理实现资格。T08小参数动态检查及默认1920×1080静态边界不证明全尺寸连续帧率。

T10实际全尺寸A/B各一帧：RAW2592000/content2592128/DMA2592768B、81024 native256bit字、518400个40bit组；TB100MHz服务48.461959/48.663180MB/s。full TB的CMP_CAP2594834（worst+128）是逻辑容量应力参数；默认8MiB和worst stored2594706仅完成静态/离线容量检查，字节数组不证明物理资源可实现。单核服务不能证明双路RAW155.52MB/s实时，RAW写+读最少311.04MB/s还未计其余开销。

RAW仍R10F v1 codec0的128B头紧密RAW10；CMP是A+精确zlib加sidecar身份，未通过改codec枚举宣称外层传输兼容，也未定义新的双路A1U1头。两条独立候选没有跑合并整机、RK或PCIe联调。

## 历史与主源记录

T08测试历史73调用/3compile/34case，其中当前r1为29调用/1compile/14case；实际修复1、原edges2次已满。开发累计142调用/7compile/44case，原r0调用超用保留，不追认合规。

T10测试累计69调用/4compile/20case：原45/2/19、supplement01 12/1/0、supplement02 12/1/1。稳定覆盖问题补充2/2、夹具编译失败根因尝试2/2、fairness2次均保留；原开发faults3/3，已知compile5/case16，完整开发calls仍未知。原额度/容量错误、缺失精确中断时刻、过期旧deadline与早期读取控制偏差保留。详 `budget-ledger-final.json`、`problem-ledger-final.json`，未靠改ID/改round/新run清账。

`workflow/tasks.json`仅追加本轮离线证据，保留并行工作及父T08/T10原state、blocker、硬件/board_chain/最新主run字段；单包记录在 `workflow/records/T08/20261025-180900-dual-local-closure.md` 和 `workflow/records/T10/20261025-180900-dual-aplus-scheduler.md`。更新结果见 `final-taskboard-update.json`。准确交接/未来恢复文本见 `handoff.md`；导航见 `delivery-index.md`。
