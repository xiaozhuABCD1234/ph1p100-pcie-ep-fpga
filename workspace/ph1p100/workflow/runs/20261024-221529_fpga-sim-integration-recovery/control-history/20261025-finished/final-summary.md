# 本轮阶段收束：一项独立通过，一项被固定DUT缺陷阻塞

> 2026-10-25 后续状态更正：既有“接着做”已授权原目标所需的可逆隔离修复，无需再次确认。第三包 `T10.a1-uart-descriptor-fix` 已ready，当前派发为 `dispatch-dq-fix-r0.json`，具体当前门槛/权限见 `planner-amendment-authorized-dq-fix.md`。下文“待用户确认”和提案TD/G2要求为历史记录，已被取代；本轮TD/bit/下载/Flash仍0。原T08 PASS/T10 blocked及全部计数保留，本次规划澄清机会1、实际修复不增加。

日期2026-10-25。原用户两个仿真目标保持；不是全部完成。新用户“接着做”及额度恢复已用于续原规划，无重试额度错误或另建替代角色。无RTL修复、生产合并、硬件操作或测试者补派。

|正式包|实际结果|候选/报告|G层与边界|
|---|---|---|---|
|T08.sync-production-sim|round0 integrated PASS；实际修复0；三维均pass|manifest `T08.sync-production-sim/manifest-r0.json` SHA `6d9d980566997b74945066a8b015308962dcb58cd525ce868ef5837a0b482838`；`test-reports/T08.sync-production-sim-r0-integrated.md`|G0/G1 pass；G2 not_run；G3/4/5 N/A。隔离生产RAW顶层overlay、真实I2C/双路writer；非生产迁入/曝光同步/板验|
|T10.a1-recovery-sim|开发blocked；clean checker FAIL；未派tester；实际修复0|`manifest-r0.json`、`dev-report-r0.md`、`defect-evidence.json`、`relay-metadata.json`均在同名任务目录|G0局部输入核对/编译完成；G1未满足，故障4case not_run；G2 not_run，G3/4/5 N/A。不能写独立综合FAIL/PASS，因为综合验收未发生|
|T10.a1-uart-descriptor-fix|第三正式包提案，blocked_scope_authorization，未派发|`repair-scope-proposal.md`|新增/改变只读DUT范围待确认；计入3/4，无新全局T任务或层级|

T08真实样例：clean/NACK/missing/global-reset/restart/pending-reset六case独立重跑，每路至少连续3完整帧，restart前后各3；角色写值反例有效，独立camera关联/源帧/逐bit CRC判据通过。302候选文件、6规划控制、4工具、108保护输入零漂移。详见独立报告，不复用旧输入PASS。

T10真实样例：clean输入种子1000..1003，cap/raw_pub/enc各4，正确完整输出仅2；前两包各73B（总146B），严格zlib/四CRC/像素均正确。第三包offset146开始，offset151为X；总1097 token，exported2、drop/geom/error/duplicate均0。两项dq数组用两位索引第三次访问2，静态与动态症状一致；同拍push/pop的count双赋值为相邻潜在问题，仅静态发现。完整原始错误保存，不把exit0/TB CASE_PASS当真通过。四种故障未运行，不以准备分支充覆盖。

未产生本轮压缩比/吞吐、容量上限、资源或STA实测；T08仅8×2 RAW20B仿真，T10 baseline同几何，前两包也不构成收益统计。旧77.76MB/s缺口、旧P2薄裕量STA及其bit身份只作旧证据，不与本轮混拼。G2整机、真实曝光/上板恢复/长稳/性能/发布仍未完成。

预算/轮数：T08开发50/60调用、2/2compile；独立测试1compile、7vsim、无失败重试，精确测试调用/墙钟未在返回中完整提供，不编造。T10开发21/45调用、1/2compile、1次clean真实仿真、1次设计载入前路径失败后有新证据纠正；四fault仿真各0，实际修复0，problem补充0。前两次文件读取未带显式60s包装但各约1s，开发已登记偏差；后续均实际有界。额度失败为原规划返回失败，不计实现修复；恢复不清零历史。

下一步是用户确认具体单文件隔离修复提案；当前不执行第三包。确认后原规划按本run恢复，第三包独立开发/综合测试后，续原T10开发并对changed输入完整复测，恢复几何/命中定义按提案冻结；原任务不改名、不移run绕限。

生产/板候选/TD/共享盘符/其他工作树未改变、无删除/Flash/下载/外部消息/监控。回退无需恢复任何生产文件，保留本run全部日志和overlay。剩余主题最多3项：①本提案队列修复及原恢复仿真；②同步overlay生产迁入完整G2和真实曝光同步；③既有吞吐缺口（本轮不修）。父T08/T10不置done。
