# T08 离线包收束与 T10 顺序派发

日期2026-10-24，原规划者 `/root/fpga_planner_sim_221529`；本文件是冻结计划的状态增补，不改原验收门槛或已测输入。

## T08.sync-production-sim 实际结果

round0 综合 **PASS**，实际修复0轮。原开发 `/root/fpga_dev_sync_221529`；一个独立综合测试者 `/root/fpga_tester_sync_221529`。报告 `test-reports/T08.sync-production-sim-r0-integrated.md`，manifest `T08.sync-production-sim/manifest-r0.json`，SHA256=`6d9d980566997b74945066a8b015308962dcb58cd525ce868ef5837a0b482838`。规划已阅读详细报告及复用决定，三维均pass，G0/G1 pass，G2 not_run，G3/G4/G5 not_applicable。

实际独立验收：一次重新编译、六场景逐一运行（clean/NACK/missing/global-reset/restart/pending-reset）和角色写值反例。正常/故障恢复场景每路至少连续三帧正确，restart为前后各三帧；14笔I2C、busy/ACK、清理/重新warmup、整帧门控、RAW字节/帧身份/CRC/地址/单次发布均通过。测试者另以响应camera关联、源帧反推和逐bit CRC判据检查，并拒绝角色写值、路身份变异。302项候选、6项规划控制、4工具及108保护输入前后零漂移；无开发/历史PASS复用。

工程与证明边界保持原计划：同步overlay只存在于本run，没有写回生产、TD实现或板级曝光同步/长稳。旧小顶G2不继承，本包PASS不把父T08置done，也不声称板上P2 A+候选包含本overlay。仿真小几何8×2、DDR环境模型，不是1080p吞吐/电气证据。

开发预算实账 `T08.sync-production-sim/execution-budget.json`：50/60 native calls、2/2全量编译，各最终case共两次或一次（pending-reset一次）；第二次编译新增pending-reset分支后重新绑定全部case；原始启动失败保留，未入设计。独立测试实际一次compile、七次vsim、无失败重试；本次主转回未带精确测试调用/墙钟累计，不编造。实际修复轮=0、problem补充机会=0；原预算/历史次数保留。

## T10.a1-recovery-sim 本次派发

原计划的第二包，无技术依赖尚待满足，冻结 `inputs/a1-r5/` 可直接使用，ready。batch=1，新开发、新的一个综合测试者，不复用T08角色。用户范围、四个语义步骤、五类case、所有恢复/CRC/计数/epoch门槛、受保护路径全部沿原dev-plan和guide，不扩大目标。

开发≤45 calls/60分钟；测试≤40 calls/45分钟；读取/搜索实际60s，编译/每case实际300s；每case独立进程和cycle watchdog。同失败命令最多首次+一次新证据重试，搜索≤3轮，连续两轮无进展主动blocked；首轮round0、最多三轮实际修复仅限TB/model/checker允许写域。

真实固定r5的8项RTL只读。若精确命中故障但DUT无法恢复，保留失败与定位证据、停止，交规划；禁止自动修RTL或放宽门槛，禁止把已知r5 comp吞吐缺口并入本轮。reset计数清零和旧响应epoch必须按guide分别观察；MODE3/4旧标签不算覆盖。

新机械派发文件 `dispatch-t10-r0.json`。原 `dispatch.json`、原dev-plan/guide/index/control manifest保持字节不变，避免漂移已验T08的规划绑定。T10新manifest须绑定实际新dispatch与本状态增补；不能只绑定历史T08 dispatch。

## 回退与后续

T08开发候选及测试证据停止修改，T10只写自身目录，测试只写自身test-reports。生产/旧run/活动板候选/共享盘符全部保留。统一tasks.json留待第二包结果明确后读取最新版本最小追加相关证据，父T08/T10硬件状态不升级；本次状态已记入各T任务record，不另立全局板。

本run仍1/2正式包离线验收完成、1/2待执行；非本轮主题仍是生产迁入G2/真实曝光同步、若发现的r5 RTL恢复修复、已有吞吐缺口。它们不自动续做。
