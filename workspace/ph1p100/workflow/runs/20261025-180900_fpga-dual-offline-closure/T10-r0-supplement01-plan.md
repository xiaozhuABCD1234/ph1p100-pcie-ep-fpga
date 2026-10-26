# T10 r0同输入覆盖补充01

原唯一测试者 `/root/fpga_tester_dual_scheduler_180900` 返回正式r0 FAIL+LIMIT_REACHED。规划已读正式报告、复用决定、私有冻结输入、两次编译快照、计数与故障判据。唯一未完成门槛是descriptor接纳与RAW release握手在同一上升沿的显式命中，以及完整身份/所有权的独立scoreboard。目前不是已发现的新RTL缺陷，不启动开发、不虚构实际修复1。T08已收口PASS保持。

## 问题身份与已知证据

规范稳定problem_id：`T10.dual-aplus-scheduler:LIMIT_REACHED:descriptor-release-same-edge-coverage`，reason_code=LIMIT_REACHED，new_information=true。缺失字段由本规划依据真实报告补齐，原始不完整blocked返回保留。证据为原r0报告及 `T10-r0-supplement01-audit.json`；resume_input为 `T10-r0-supplement01-input.md`。

该根因是独立覆盖缺口，不同于开发原CMP stall缺陷、故障metadata截断或外部容量错误；不会改那些稳定ID/次数。有限原责任角色补充机会本次1/2；失败或外部错误仍回原规划，不自动第二次派发。原scope内必要离线验收已获原始两包交付和“接着做”授权；45 calls/2compile是规划执行窗口，用户没有将该数值设为总授权限制。本次冻结小窗口用于同输入缺口，不请求重复权限，不扩硬件或新功能。

唯一DUT manifest仍 `T10.dual-aplus-scheduler/cmp-stall-fix01/static-closeout02/manifest-cmp-stall-fix01.json`，SHA256 `5db2b0ddf42c60426dd5a10a72614abf2bbe2306a3464be01474f7683e87f03b`。core/frame/scheduler三文件不变。原19case中16通过、2有效负对照、1保留的fairness构造失败；纠正producer后的第二次fairness已通过，无第三次。既有通过的122帧与完整几何/PREP、fault、full、CMP/接口/容量/phase及负对照证据只在同DUT/精确私有编译来源下复用，不再跑完整套件。

两次编译的私有TB曾变化，compile1快照的旧path对应当前保留的 `*-compile1.sv` 字节拷贝，不能拿当前compile2 TB SHA反写compile1。interface初始oracle把reset取消的READY CMP误当已呈现，旧result-v1/traceback保留；同一仿真重解析后真实4帧通过。新补充不重新解释失败为不存在。首四次有限读取没hard timeout和首次receipt精确时刻缺失的程序偏差也保留，后续落实真实timeout。

## 最小有界执行

只续原唯一综合测试者，同模型；最多16保守工具调用/20分钟、1次compile、**1个case进程**。原45/45调用、2/2compile及19/20case不清零；新工具与compile明确另列有限补充账，累计最大61调用/3compile；case只用原尚余第20个，不新增第21个。编译1次仅为新私有TB/monitor，DUT完全不变。没有额外compile或case重试自动授权；任何失败/预算不足如实返回，由原规划处理。

开工按真实收到续接记录start/deadline(+20分钟)，旧首次01:09保守起点/02:09deadline与真实45calls停止保留，不倒改。单读搜60秒、compile/小矩阵case300秒，TB另有watchdog，必须可安全终止自己进程树。写域仅 `test-reports/T10.dual-aplus-scheduler/r0/supplement01/**`，所有旧r0文件及开发候选只读。不能运行会写旧O/cwd/deadline的原runner；可读取/复制后适配到新域。

一个小几何有限矩阵即可：合法free ingress身份与实际释放身份不同，安排release反压后解除，使descriptor valid/ready和rel valid/ready在同一个posedge真实同时为1。覆盖A/B及两slot（可用4行同时覆盖跨camera和同camera不同slot），不要求busy原slot必须同拍重新可接纳。不能force DUT owned/state/rel/core信号。独立scoreboard在采样同沿列完整两份身份和ownership before/after，并继续实际读/编码/CMP/ACK验证新旧帧，无误释放/覆盖/重复/丢失；仅分别命中两个握手或仅PASS字符串无效。

## round与正式报告

无实现变更，仍formal round0、post_acceptance实际修复0，不能命名r1。原根目录r0 integrated FAIL文件及SHA完全保留。补充完成后在新域只生成一份**当前有效的完整round0综合报告**，basename仍 `T10.dual-aplus-scheduler-r0-integrated.md`，并写canonical-report.json指向它、引用旧FAIL的路径/SHA/历史性质。旧报告是本轮先前blocked返回的不可变快照，不作为另一当前独立视角；当前单一综合结论由同一原测试者把有效同输入旧证据和新补充覆盖重新汇总，不能只给一页场景PASS代替三维整体验收。

新报告首行唯一PASS/FAIL；只有缺口实际闭合且输入无漂移、原必要证据均有效时才能PASS。报告明确复用依据、原报告FAIL、全部旧错误/计数、当前增量和真实累计；G2/3/4仍not_run/awaiting_hardware，不升级父硬件状态。原开发faults始终3/3，新补充不跑fault套件、不修改manifest、不读写T08。所有返回交原规划，未获得独立PASS前不收口整个run。
