# dev-plan.md — 20261019-0207_runA_ddr_readback_loop（v1）

原规划者编写（2026-10-19，无人值守轮）。batch=1；1 主要可验收目标；4 正式包；两级（需求→工作包）；每任务新开发 + 一个综合测试者（独立于开发）。依据：本 run `request.md`（用户原话）、基线 run `20261018-1631_runA_fpga_side_readchannel`（dev-plan/handoff/final-summary/input-index/user-input-13/dispatch.json/test-reports）、`user-precheck.md` §7、`next-round-proposal.md`（A4）、master-plan MP07—11、基线 `debug-spec/probe-map.md`、checker RTL/TB 与其 dev-result；冻结接口见本 run `fpga-design-guide.md`。

**v1.1 更新（2026-10-19 02:32，P1 blocked → 去重裁定）**：`T11.runC-checker-integrate` 首轮返回 **blocked**（problem=`T11.runC-checker-integrate:INPUT_CONFLICT:worktree`，new_information=true；`checker-integrate/blocked-report.md`）：规划冻结后 02:23—02:31，并行 run `20261019-0212_codex_fpga_closedloop_b2`（Codex）在同一工作树持续写入（规划时点 4 路径 → 实况 7 M + 8 ??，与本包 write_scope 全量重叠、目标同为 DDR 读回校验集成）；开发**零上游写入**、未启动仿真/构建、未产生 manifest，**blocked 非 FAIL、修复轮 0/3、二轮复测不需要**。原规划只读核对 0212：其 `request.md` 含用户原话「**这个本来是opencode的任务，修改为codex试用**」，并明确 Track A=单A RAW→DDR 板级闭环（读回校验/几何/坏帧）+「回来点两下」清单（batch=2 授权；02:20 起 B01 活跃）。**去重裁定（CR-20261019-0207-01，冻结）**：①Track A（含本轮 N1—N5 闭环链）**唯一归属=0212 run**；本 run 不写共享工作树、不重复实现、不构建、不上板/不下载、不另建 worktree/分支；②本 run P1 **释放（release，不重派）**，P2—P4 保持 held；③恢复仅由**用户新指令**触发（A 关闭本 run 收尾为 superseded／B 保留为 Codex 试用回退／C 改做其他不冲突目标），默认=保留 parked、不派发、不消耗预算——见 `question-01.md`；④**冻结描述修订**：`input-index §2.2`/`dispatch.write_scope` 的「继承 4 路径 +46/−5」已失效（02:31 实况 7 M + 8 ??，HEAD 仍 `b0282d2a`），未来任何重派必须以当时工作树快照（status/diff 哈希）为准，不得绑定他人在途中间态。**本 run 未写入任何上游文件；板/位流未动。**

**v1.2 更新（2026-10-19 13:1x，重锚恢复：CR-20261019-0207-02）**：用户新输入（`user-input-01.md`）：“你现在在做的是一个trackA…我希望你重新锚定你们二者工作范围，互不影响并行推进进度吧”。原规划只读核对 0212 实况（`main-log.md`：B01/T08 两次 blocked→0254 交用户；12:56 用户“接着做…足够的尝试机会”；恢复01 已续派 B01 开发（120 calls/180 min、TD≤3），其 after-pass 指向 T02 板级；共享树 17 项在途、最新写入 02:45，HEAD 仍 `b0282d2a`）。**重锚裁定**：①**物理沙箱**：本线新建独立 worktree `upstream\ph1p100-pcie-ep-fpga-wt0207`（branch `opencode/runC-0207`，base `b0282d2a` + 基线 `debug-fix3` 4 路径 r3 diff 复现；核对 +46/−5、4 文件 SHA 与 debug-fix3 manifest 一致），为本线**唯一 RTL 写树**；共享树 `upstream\ph1p100-pcie-ep-fpga`（0212 在途）**只读**；②**本线范围=Track A 全链**（N1—N5，沙箱内独立候选）；不含 Track B/T09、不含 T08 同步（属 0212）；两线互不合并树/候选；③**共享资源串行**：TD 会话同机互斥（等待、不杀进程、不动对方目录）、板卡/下载单一窗口互斥（不覆盖对方刚下载候选）、CLI 读回仍永久关闭、读回走 GUI（用户在场可用）；④**“尽量合并构建”**：本线内部 N1+N3=一次构建（P2）；跨线默认不合并，如用户要统一单候选另行明确；⑤**batch 判定**：用户“batch=2”为致 Codex 派发原文，本线未获覆盖 → 保持 **BATCH_SIZE=1**；⑥**恢复**：P1 以新输入（独立 worktree）重派**新开发会话**（原 blocked 不耗修复轮、round0 未开始），P2—P4 维持 blocked-by-order；P1 dev 预算 ≤100 min/≤55 calls（含 worktree/r3 复现）；⑦与 0212 **无交接（纯规避）**；如需“一线 A、一线 B”硬分工需用户明确（Codex 侧需用户转达）。

**v1.3 更新（2026-10-19，P1 PASS r1 → P2 派发）**：`T11.runC-checker-integrate` **PASS round1**（integrated；报告 `test-reports/T11.runC-checker-integrate-r1-integrated.md`；r0 FAIL→r1 修复 1 轮，原 blocked 不计轮）：functional/engineering/system 全 PASS；manifest r1 `68AB235E…`（9,368 B，`repair_round=1`）13/13 复算 0 不一致；candidate.diff r1 `5907B38F…8CB2`/59,091 B（8 diff 头+2 新文件、UTF-8/NUL=0、干净 base 双向 apply=0、施加后 8/8 文件 git blob 与在途 worktree 全等）；G0/G1=pass，G2/G3/G4=not_run。候选=wt0207（branch `opencode/runC-0207`、HEAD `b0282d2a`、worktree-only 6 M+2 ??、diff numstat 240/30）。非阻塞观察（报告 §4，供 P2/P4）：diff 含 2 个追加分隔 CR 字节、1 处既有 trailing-whitespace 警告（cosmetic）、两个新文件行尾不对称（跨 checkout 用 git blob 核对）、控制台中文乱码=输出捕获现象。→ **派发 P2 `T11.runC-build`（本次派发；batch=1）**：wt0207 单会话 `00_all_debug`（≤30 min×≤2）→ 会同判据 → CWC 重生成（含新字探针）+ `check_chipwatcher_readback.py --multipiece` 0 失败 → G2（阈值不放宽；与 r3 基线对比）→ 候选冻结（bit/CWC/BID/rollback/hardware-ready/上板预期值表；8 文件登记 SHA256+git blob）。**TD 窗口与 0212 串行互斥（本次新增协议）**：启动前进程检查；仅活跃构建会话才等待（每 2–3 min 复查、累计 ≤10 min）；占用→blocked 非 FAIL；既有夜间 GUI/线缆实例（`td` PID 45416、`hwserver` PID 49924）保持不动。不下载/不触硬件/零 Flash。P2 dev ≤60 min/≤30 calls（等待计入）；tester ≤20 min/≤25 calls。

**v1.4 更新（2026-10-19，P2 PASS r0 → P3 派发）**：`T11.runC-build` **PASS round0**（首次通过、0 修复轮；integrated；报告 `test-reports/T11.runC-build-r0-integrated.md`）：functional=pass（PRJ-1406/1424/T07_ALL_DONE、exit=0、Routed；CWC 16 视图/512+512/26 pieces、multipiece 独立复跑 rc=0、strict 仍拒多片；字表 word9..15 可追；上板预期值表齐）；engineering=pass（manifest `0F67D299…6919`（16,523 B）29/29 复算 0 不一致；P1→P2 绑定 9/9 + diff `5907B38F…` 全等；SWNS 0.104/STNS 0/HWNS 0.020/HTNS 0、0 违例；LUT 26.12%/reg 18.52%/ERAM 54.00%；r3 对比 0.134→0.104、chk.timing 24/24 逐行一致；bit/CWC/BID 同源配对）；system=pass（未下载/零 Flash、`D:\anlogic\runa_runC` 未建、旧候选未动、夜间 td/hwserver 未扰、工作树 6 M+2 ?? 未变）。候选：bit `5B67A8F5…1D52`（5,224,027 B）/CWC `8DDA54D4…664F`（143,444 B）/BID `A068E42E…F1DB`；G0/G2=pass、G3=not_run（待用户点两下）。非阻塞观察（§3）：dev 31/30 calls 超用已登记（重算 supersede、未影响证据；不据此判 FAIL）、`generated_at` 名义 15:36 vs mtime 15:17:48、校验输出 UTF-16LE、git blob clean-filter 口径。→ **派发 P3 `T11.runC-sim-campaign`（本次派发；batch=1）**：wt0207 仅新增/扩展 `sim/tb/**`（必要时 `sim/compile_checked.f` 追加行并记录；不改 RTL/约束/构建入口；P2 冻结件只读）——①100 帧连续循环（小尺寸可参数化帧；0 误判/0 覆盖）；②坏帧注入 ≥5 类（整帧拒发、无发布/无部分帧、err_code/ok 位符合契约）；③1080p 满帧读回保持 PASS；④口径：`run_sim.ps1`、单 TB ≤5 min、整组 ≤15 min、vlog Errors:0 + ALL PASS；与 P1 冻结 RTL 哈希同源（9/9 未变声明）；⑤冻结本包 manifest（P2 冻结件只读、bit 绑定不变）。P3 dev ≤75 min/≤40 calls；tester ≤30 min/≤30 calls。若仿真发现需改 RTL → 停，交原规划走 P1 修复轮（不混包）。

**v1.5 更新（2026-10-19，P3 PASS r0 → P4 派发）**：`T11.runC-sim-campaign` **PASS round0**（首次通过、0 修复轮；integrated；报告 `test-reports/T11.runC-sim-campaign-r0-integrated.md`）：functional=pass（TB1 `tb_ddr_readback_campaign` 2 s、TB2 `tb_ddr_readback_1080p` 19 s 独立复跑 ALL PASS/Errors:0；自建负对照被正确拒绝 errors=201；100 帧计数、第 70 帧 busy 幽灵发布、坏帧 6 类 8 检查逐项与 RTL 契约一致；1080p words=648,192/runs=1，与模块级 legacy 同常量同断言不降门槛）；engineering=pass（9/9 候选哈希与 P1 全等（零 RTL 改动）；两新 TB sha256+git blob 与 manifest 全等；manifest `01938ebb…af72`（17,323 B）9 项工件 9/9 MATCH；单 TB ≤5 min、组 ≤15 min；`run_sim.ps1` 三连复跑 rc=0）；system=pass（P1/P2 冻结件只读未动、共享树近 3 h 零写入、零 commit/零 push、`D:\anlogic\runa_runC` 未建=零 TD/硬件/Flash）。G0/G1=pass；G2=not_run（P2 已单独 PASS，本包不复算）、G3=not_run（待用户点两下）、G4=not_run。无 retest、无复用豁免；worktree 现 6 M+4 ??（P1 2 文件 + P3 2 TB）。非阻塞观察（报告 §4）：开发自纠 3 处（TB 内）、freeze-verify.txt 重建修正计数行（证据本体无损）、2 次平台空响应（无副作用）、未重跑 legacy TB（理由成立）、TB 白盒等待手法。→ **派发 P4 `T11.runC-board-checklist`（最后一包；本次派发；batch=1）**：证据索引（哈希链 0 不一致）+“回来点两下”清单（板载现状记录；可选 SRAM 预加载 `D:\anlogic\runa_runC\<ts>\` 新建/复制零覆盖、≤1 次/≤5 min；用户 GUI 步骤与**冻结预期值**（逐字取自 `build\hardware-ready.md`）；异常分流/回退两分支；G3 tier 判定口径）+ 回退文档 + 本包 manifest。**板窗口与 0212 串行互斥**（下载前由在场用户确认窗口空闲；对方候选在板→停不覆盖；既有 td/hwserver 不干扰）。用户在场：预加载后可等待用户点击（≤15 min、计入预算）；未点击→返回 awaiting_user_gui（清单已冻结）。P4 dev ≤45 min/≤30 calls；tester ≤20 min/≤25 calls（核证据/文档，不重跑硬件）。

**v1.6 更新（2026-10-19，P4 awaiting_user_gui → 板窗/预加载续接）**：`T11.runC-board-checklist` 首次返回 **awaiting_user_gui**（非 FAIL；开发会话 `ses_eac212196ffeIw4XAwHxkcEZu6`）：清单/证据已冻结——manifest `d5c25421…1364`（12,180 B；freeze-verify 24 项 BAD=0）、`board-checklist\{evidence-index.md, board-checklist.md, rollback.md, dev-result.md, lessons.md, hash-chain-recompute.txt（56 项 MATCH）, recompute-hash-chain.ps1, freeze-verify.txt}`；哈希链 56/0 不一致（P1 5+P2 19+P3 19+worktree 9+P3 TB 2+旧候选保护 2）；diff 双向 apply rc=0；worktree HEAD `b0282d2a`、6 M+4 ??；旧候选 `bfafdf97…`/`8d2998b9…` 不变。**可选 SRAM 预加载未执行**（19:14 起 0212 在本机跑 TD 构建）：暂存 `D:\anlogic\runa_runC\20261019_192056\`（bit `5B67A8F5…`/CWC `8DDA54D4…` 均 MATCH）+ `preload.bwcmd` 已备未执行；未 connect_cable/read_device_id/download；零 Flash/零 GUI 自动化/零 commit/零 push；td 45416/hwserver 49924 未动；预算 30/30 calls、≈35 min（含 1 次脚本自纠，无副作用）。**处置**：①**不先派 tester r0**（P4 未 ready_for_test；预加载/两样本会更新 manifest；待完整包冻结后一次 r0，避免两份报告与输入漂移）；②续原 P4 开发（同 task/session，≤20 min/≤20 calls）做“板窗机械检查（无活跃 TD 构建会话；夜间 td/hwserver 不算；检测到 0212 候选在板→停）+ SRAM 预加载（≤1 次/≤5 min/零 Flash）+ 更新板载状态/冻结 v2 + 交清单”，返回 awaiting_user_gui；窗口确认按 **CR-02 修订**改为可审查机械检查（理由：0212 当前派发禁止自动下载；子会话无法直接向用户确认；安全边界不变）；③主转达用户“点两下”步骤与冻结预期值；用户两样本回传后续原 P4 开发记录+冻结（或用户明确不点则就冻结 v1），再交一次 tester r0；④G3 仍 not_run，最终由 tester 报告+原规划收尾判定。恢复入口见 dispatch `resume_plan`。

**v1.7 更新（2026-10-19，P4 PASS r0 → run finished）**：`T11.runC-board-checklist` **PASS round0**（首次、0 修复；integrated；报告 `test-reports/T11.runC-board-checklist-r0-integrated.md`）：functional=pass（A/B/C/D 转录逐字 0 差异；**G3=Tier-1 PASS + Tier-2 PASS**：身份三字四样本全中、word3 单调 `3216→3818→15293→15764`、word13 完成态=word3（B=word3−1 可解释）、word4 BASE0/BASE1 轮换有 RTL 直接源、word5=2,592,768、word6 good 模 256 四样本自洽且坏计数 0、word9=`0x3E`、word10=648,192、word11/12 非零、word14=word15=word12；C/D 间隔 30 s）；engineering=pass（manifest v8 `3594bb40…`（13,682 B）独立复算一致、14/14 工件 SHA 全等、freeze-verify 55/0、哈希链 56 MATCH、bit/CWC MATCH；G0=pass、G1/G2 继承 pass）；system=pass（预加载 `-mode jtag`、PRG-2014、100%、30.037585 s、下载后 PH1P100；下载 1/1、零 flash/efuse/SPI/svf；旧候选并列、回退完整；G4=not_run）。非阻塞（报告 §5）：开发报告 B 样本 hdr/pay 两位读反（tester 已更正、结论不变）；manifest v8 `generated_at` 与 mtime 不一致；§4 来源措辞建议；word4 直接源应为 `cam_ddr_writer.v`；tester 实际 ≈31 次调用超冻结 ≤25（已如实登记、不影响结论）。**run 终态=finished**：4 包全部 PASS（P1 r1；P2/P3/P4 r0）；首次通过 3/4；⚠未通过 0；G3=Tier-1+Tier-2 PASS、G4=not_run；父 T11 不置 done；`workflow/tasks.json` 本轮未写。终版文件：`final-summary.md`、`handoff.md`、`user-summary.md`、`dispatch.json`（finished）。

## 0. 本轮目标、合并裁定与 done 口径

- **主要可验收目标（1 个）**：**DDR 读回校验集成闭环候选**——checker 接入调试候选（含几何/相位离线核对与条件回填）、一次构建冻结新 bit/CWC、坏帧/100 帧仿真证据、“回来点两下”上板清单齐备。
- **N1—N5 → 4 包合并裁定（规划裁定 + 用户提示）**：用户提示“若规划认为 N1/N3 可合并成一次构建会更省时间”。裁定：
  - N1（checker 集成）与 N3（几何回填）**合并为一个 RTL 包**（`T11.runC-checker-integrate`）：两者同为 RTL 增量、共享一次 G1/构建/冻结；不合并则 5 步超 4 包上限。
  - 最终 4 包：P1=checker 集成+几何回填（N1+N3）→ P2=一次构建+G2+候选冻结（N2）→ P3=坏帧/100 帧仿真（N4）→ P4=证据索引+上板清单（N5）。
  - **BATCH_SIZE 仍=1**（非合批）；正式任务总数 4、每任务新开发+新综合测试者、修复轮分账均不变。
- **本次范围 done vs 父 T11**：本轮 done=N1—N5 依序收束（P1—P4 全 PASS 或如实登记 ⚠/blocked）；**G3（身份/checker 字上板实测）待用户回来点两下后判定，本轮 not_run**；G4 后置；**父 T11 不置 done**。
- **用户明确口径**：进度优先、稳定性/优化后放；仅 SRAM、不写 Flash、不推送；不接 PCIe/RK/三算法。

## 1. 安全与边界（全程）

- 板上仅 SRAM（P4 可选预加载 ≤1 次）；零 Flash/efuse/SPI/svf；不改线/电源/相机；禁止 GUI 自动化；不推送远端；根 AGENTS 禁止批量删除（本 run 不删文件）；`workflow/tasks.json` 本轮不写；其他工作树/`parallel/**`/`D:\TD\work\csi2` 只读。
- 无人值守：各角色按冻结预算自停，超限/外部阻塞 → blocked 备条件，不空转、不自动扩预算/扩权。

## 2. 工作包总表

| 顺序 | task_id | 问题/产物 | 工作树/允许写路径 | 依赖 | functional 验收 | engineering 验收 | system 验收 | 必要 G 层 | 状态 | 下一动作 |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | `T11.runC-checker-integrate` | checker 接入 debug 候选 + 新调试字 + 几何回填核对：可构建 RTL 增量 + TB/回归 + 冻结 manifest | `upstream/ph1p100-pcie-ep-fpga`（`rtl/ep_side/ddr/**`、`rtl/ep_side/**` 调试/字库块、`rtl/ep_side/debug/**`、`sim/tb/**`、`sim/compile_checked.f` 追加行、`tools/pcie_integration/td/00_all_debug.tcl`、`constraints/ph1p_pcie_case_ep_dbg.sdc` 仅必要时）；本地 commit 或 worktree-only；run `checker-integrate/**` | 无（离线；继承 r3 worktree） | 新 TB（字等价/触发/重入/负例）+ 既有 8 TB 全 ALL PASS；`geometry-audit.md` 分级结论与证据一致 | 编译 0 error；diff 允许清单；新字地址无冲突；manifest 0 不一致；CWC 探针表更新可核 | DBG-off 等价（生产路径无新活动逻辑）；零硬件；protected 审计；不删旧候选 | G0/G1 | **PASS（r1，integrated）** | 无（manifest `68AB235E…`；diff `5907B38F…`） |
| 2 | `T11.runC-build` | 一次 debug 构建：新 bit+CWC+G2 报告+候选冻结（与旧候选并列） | run `build/**`（构建输出指到 run 内）；上游仅 P1 已冻结文件（不额外改 RTL） | 1 PASS | 会同判据齐（PRJ-1406/1424/T07_ALL_DONE、exit=0）；CWC 含新字且校验 0 失败；上板预期值表齐 | Routed；SWNS/STNS/HWNS≥0、0 违例、资源在器件内；单会话 ≤30 min（≤2 次）；manifest/哈希齐 | 未下载（除 P4）、未写 Flash；产物并列不覆盖；回退=删本包产物 | G0/G2（G1 继承） | **PASS（r0，integrated）** | 无（manifest `0F67D299…`；bit `5B67A8F5…`） |
| 3 | `T11.runC-sim-campaign` | 坏帧/100 帧仿真战役：集成级 100 帧连续 + 坏帧注入 ≥5 类 + 1080p 满帧回归 | `upstream/…/sim/tb/**`（仅新增 TB）；run `sim-campaign/**`；**不改 RTL/约束/构建入口** | 1（RTL 冻结）；顺序在 2 后（batch=1 不并行） | 100 帧 0 误判/0 覆盖；坏帧全部拒发（无发布/无部分帧）；ALL PASS；与 P1 冻结 RTL 同哈希 | 单 TB ≤5 min、整组 ≤15 min；日志/命令/退出码/哈希齐；可复跑入口 | 证据绑定当前 manifest；protected 审计（未动 RTL/冻结物）；零硬件 | G1（仿真证据） | **PASS（r0，integrated）** | 无（manifest `01938ebb…`） |
| 4 | `T11.runC-board-checklist` | 证据索引+哈希链 + “回来点两下”上板清单 + 回退文档 + 可选 SRAM 预加载 | run `board-checklist/**`；`D:\anlogic\runa_runC\<ts>\`（仅新建/复制，零覆盖）；板上仅 SRAM（≤1 次下载） | 2、3 PASS；P4 可选预加载另需 P2 冻结件 | 清单语义/期望值与冻结读数一致；两分支（板载在/已断电）步骤可执行；预加载记录（如执行）：rc/PRG-2014/时长/SHA | 证据索引逐项 SHA 可复算；命名/入口规范；manifest 0 不一致 | 仅 SRAM/零 Flash/≤1 次/失败不阻塞；旧候选并列；回退链完整 | G0 | **PASS（r0，integrated）**；G3=Tier-1+Tier-2 pass | 无（run 收尾） |

## 3. 详细工作包

### 3.1 P1 `T11.runC-checker-integrate`（离线 RTL；N1+N3 合并）

**主要可观察结果**：可构建的 checker-集成调试候选增量（RTL+TB+入口+字表）+ 回归证据 + 几何核对结论 + 冻结 manifest。

- **允许写范围**：`upstream/ph1p100-pcie-ep-fpga`：`rtl/ep_side/ddr/**`、`rtl/ep_side/ph1p_pcie_ep_top.v`、`rtl/ep_side/pcie_ep_engine.v`、`rtl/ep_side/img/ep_bar_win.v`（仅调试字库块）、`rtl/ep_side/debug/**`、`sim/tb/**`、`sim/compile_checked.f`（仅追加行）、`tools/pcie_integration/td/00_all_debug.tcl`、`constraints/ph1p_pcie_case_ep_dbg.sdc`（仅当确需；语义等价）；本地 commit（不推送）或 worktree-only 冻结；run `checker-integrate/**`。
- **protected**：生产 SDC `ph1p_pcie_case_ep.sdc`、`00_all` 默认行为、`build.tcl`/`run_td.ps1` 默认、DDR 写者/推帧既有语义、PCIe 硬核/IP、旧 bit（`bfafdf97…`/`2385cded…`/`e81d353b…`/`AFFC4396…`）、基线 run 全部证据、`workflow/tasks.json`、`D:\anlogic\TD_Release_2026.2` 安装目录。
- **语义步骤（≤5）**：
  1. 按 guide §2 实现 checker 集成（dhi 域接入读仲裁、逐帧自动触发、复位不依赖链路、TB 覆盖发布边沿/基址变化/重入）；
  2. 按 guide §3 实现新调试字（两级同步快照 + 字库/mux 追加 + MARK_DEBUG 探针扩展），TB 证明逐位等价与既有 9 字不变；
  3. 几何/相位离线核对与分级回填（guide §4；证据不足保持原值并标 diagnostic）；
  4. 新 TB 全 PASS + 既有 8 TB 回归全 PASS（`MIPI_PHY_SIM_STUB`；单 TB ≤5 min、整组 ≤15 min）；
  5. 冻结：`candidate.diff`（HEAD→当前，含继承 r3 改动与本次新增，逐项允许清单）、`candidate-manifest.json`（0 不一致）、`geometry-audit.md`、dev-result/dev-notes/lessons、（可选落地）本地 commit。
- **综合测试三维对象**：functional=独立重跑新 TB（含测试者自建负例）+ 抽验 8 TB；字表↔checker 端口逐字可追；几何结论证据链复核。engineering=编译/端口/CDC 规范、diff 允许清单、地址无冲突、manifest 复算。system=DBG-off 等价、protected 审计、零硬件、旧候选未动、回退（revert/丢弃新增）。
- **必要 G 层**：G0（输入/口径/字表冻结）、G1（TB+回归）；G2/G3 not_run（不构建、不触硬件）。
- **工具与超时**：ModelSim（`MSIM_BIN=D:\intelFPGA\18.1\modelsim_ase\win32aloem`）、git、python（哈希）；读/搜 60 s；不用 TD/不触硬件。
- **停止条件/回退**：集成需改生产语义或扩范围 → blocked 交原规划；连续 2 循环无进展 → NO_PROGRESS；预算耗尽 → LIMIT_REACHED；回退=`git revert`/丢弃新增文件（不删旧候选）。
- **预算（冻结，含理由）**：dev **≤90 min / ≤50 calls**（理由：集成 RTL+CDC+字库扩展+新 TB+8 TB 回归≈3 min 仿真+几何核对+冻结；基线同类包曾用 59 calls）。tester **≤30 min / ≤30 calls**（独立重跑/复算）。

### 3.2 P2 `T11.runC-build`（离线构建；N2）

**主要可观察结果**：新 debug 候选位流 + 配对 `compiled.cwc`（含新字）+ G2 报告 + 冻结 manifest/上板预期值表（与旧候选并列）。

- **允许写范围**：run `build/**`；上游仅限 P1 已冻结文件（**本包不改 RTL**）；构建输出/临时目录指向 run 内。
- **protected**：P1 冻结 diff/manifest（只读）；`00_all` 默认；旧候选文件原位；TD 安装目录。
- **语义步骤（≤5）**：
  1. 单会话构建 `00_all_debug`（≤30 min；**最多 2 次**，第 2 次须有新证据/参数纠正并记录理由）；
  2. 会同判据核验（PRJ-1406/1424/T07_ALL_DONE、exit=0、`final_timing.rpt=Routed`）；
  3. CWC 重新生成（含新字探针）+ `check_chipwatcher_readback.py --multipiece` 0 失败（strict 保持拒多片）；
  4. G2：全域 SWNS/STNS/HWNS≥0（记数值）、0 违例、资源在器件内；与 r3 基线对比表；
  5. 候选冻结：manifest（bit/CWC/BID/timing/area/diff/rollback）、`hardware-ready.md`、上板预期值表（guide §6）。
- **综合测试三维对象**：functional=构建判据+bit/CWC/字表三者可追；engineering=STA/资源/时限/CWC 映射/路径规则/manifest 0 不一致；system=未下载未写 Flash、产物并列、回退=删产物+重下旧 bit。
- **必要 G 层**：G0/G2（G1 继承 P1）；G3 not_run。
- **工具与超时**：TD 2026.2、`run_td.ps1`；单会话 wrapper ≤30 min；禁用下载/bw/flash。
- **停止条件/回退**：2 次构建仍失败/时序不收敛/CWC 校验失败 → blocked，不放宽门槛；回退=删本包产物（旧候选不受影响）。
- **预算（冻结，含理由）**：dev **≤60 min / ≤30 calls**（理由：含构建等待与报告；构建 ≤30 min×2 上限）；tester **≤20 min / ≤25 calls**（冻结/哈希/绑定核对，不重建、不触硬件）。

### 3.3 P3 `T11.runC-sim-campaign`（离线仿真；N4）

**主要可观察结果**：集成级坏帧/100 帧仿真证据——100 帧连续循环 0 误判、坏帧注入 ≥5 类全部拒发、1080p 满帧场景保持 PASS。

- **允许写范围**：`upstream/…/sim/tb/**`（仅新增/扩展 TB，不改 RTL/约束/构建入口）；run `sim-campaign/**`（日志、判据、manifest、dev-result）。**不动 P1 冻结 RTL**；若仿真发现需改 RTL → 停，交原规划走 P1 修复轮（round1）。
- **protected**：P1/P2 冻结件（RTL diff、bit、CWC、manifest）只读；生产 TB 既有语义；旧候选。
- **语义步骤（≤5）**：
  1. 集成级 100 帧连续 TB（小尺寸可参数化帧循环：发布→校验→计数一致，0 误判/0 覆盖）；
  2. 坏帧注入 ≥5 类（magic/头 CRC/载荷 CRC/截断短帧/长度错；可选 AXI 错/超时/abort）：整帧拒发、无发布、无部分帧、err_code/ok 位符合契约；
  3. 1080p 满帧读回场景保持 PASS（复用/扩展 P1 场景，断言不改门槛）；
  4. 运行记录：单 TB ≤5 min、整组 ≤15 min；`vlog Errors:0` + `vsim ALL PASS`；与 P1 冻结 RTL 哈希核对同源；
  5. 冻结：本包 manifest（TB/日志/哈希）、dev-result/dev-notes/lessons。
- **综合测试三维对象**：functional=独立重跑/抽验仿真、计数与拒发统计复核；engineering=时限/日志/命令/退出码/哈希、可复跑入口；system=未改 RTL、protected 审计、零硬件、证据绑定当前 manifest。
- **必要 G 层**：G1（仿真证据）；G2/G3 not_run。
- **工具与超时**：ModelSim；单 TB ≤5 min、整组 ≤15 min。
- **停止条件/回退**：需改 RTL/扩范围 → blocked（交原规划，不自行修）；连续 2 循环无进展 → NO_PROGRESS；回退=丢弃本包新增 TB/记录（不删既有）。
- **预算（冻结，含理由）**：dev **≤75 min / ≤40 calls**（理由：TB 编写+多次仿真+冻结）；tester **≤30 min / ≤30 calls**（含独立复跑/复算）。

### 3.4 P4 `T11.runC-board-checklist`（文档+可选预加载；N5）

**主要可观察结果**：“回来点两下”上板包——证据索引（哈希链）、`board-checklist.md`（含期望值/异常/回退/两分支）、回退文档，以及（可选、尽力而为）新候选 SRAM 预加载记录。

- **允许写范围**：run `board-checklist/**`；`D:\anlogic\runa_runC\<YYYYMMDD_HHMMSS>\`（仅新建/复制 paired `compiled.bit`/`compiled.cwc`+脚本/日志；零覆盖、零删除；不改 TD 安装）；板上仅 SRAM（≤1 次下载）。
- **protected**：P1/P2/P3 冻结件与全部旧证据只读；旧 bit 原位；相机/线/电源（用户域）。
- **语义步骤（≤5）**：
  1. 证据索引：RTL diff→manifest→bit/CWC SHA→G2/仿真/报告逐项哈希链复算（0 不一致）；
  2. `board-checklist.md`：用户动作最少化（开 TD GUI→`compiled.cwc`→Watch→Instant Trigger ×2、≥10 s→回传原文），冻结期望值（guide §6）、异常分流与回退（断电清 SRAM/重下旧 bit）、两分支（板载在/已断电→先重下）；
  3. 回退/恢复文档更新（新旧候选并列、命令、SHA、≈时长）；
  4. 可选 SRAM 预加载（仅 P2/P3 PASS 后）：SHA 复核→ASCII 暂存→hwserver/connect_cable/read_device_id=PH1P100→`download -mode jtag` ≤1 次→记录 rc/PRG-2014/时长；失败/板不在/USB 错 → **不重试**，清单兜底；
  5. 冻结：本包 manifest、dev-result、清单最终版（供收尾原规划原样转发）。
- **综合测试三维对象**：functional=清单语义/期望值与冻结读数一致、步骤可执行性（两分支）复核；engineering=证据索引哈希可复算、命名/入口规范；system=仅 SRAM/零 Flash/≤1 次/失败不阻塞、旧候选并列、回退链完整、（如执行）预加载审计零 flash 命中。
- **必要 G 层**：G0（文档/证据一致性）；G1/G2 继承；G3 not_run（待用户点击）。
- **工具与超时**：文档+哈希工具；可选 TD/BW+hwserver（单命令 ≤60 s、下载 ≤5 min）；不改线/电源/相机。
- **停止条件/回退**：预加载失败即停、不重试；证据链不一致 → blocked 交原规划；不做 GUI 自动化、不盲试未知命令。
- **预算（冻结，含理由）**：dev **≤45 min / ≤30 calls**（含证据索引+清单+可选 1 次下载）；tester **≤20 min / ≤25 calls**。

## 4. 综合测试者安排（独立于开发）

- 每任务新开发 + 一个新综合测试者；同任务修复才续原 ID；每任务每轮一份 `test-reports/<task_id>-r<round>-integrated.md`（首行唯一判定标题；dimension=integrated，覆盖 functional/engineering/system + G 层）。
- 离线包：独立重跑 TB/仿真（含自建负例）、抽验判据来源、哈希/diff/manifest 复算、命令审计；不要求硬件。P4：只核证据/文档/（如执行）预加载记录，**不重跑硬件**。
- 不得把未绑定当前 manifest 的读数记 PASS；失败与受影响项必须复测；未影响证据由同一测试者绑定新 manifest 并写复用依据。

## 5. 统一阈值（冻结）

| 门槛 | 值 |
|---|---|
| 回归 | 既有 8 TB + 新 TB 全 `*** ALL PASS ***`（vlog Errors:0；`MIPI_PHY_SIM_STUB`；单 TB ≤5 min、整组 ≤15 min） |
| 构建 | 会同判据齐 + exit=0 + Routed + 全域 SWNS≥0/hold≥0 + 资源在器件内 + 无新违例；单会话 ≤30 min×≤2 |
| CWC | `setup_debugger` 产物齐 + `check_chipwatcher_readback.py --multipiece` 0 失败 + bit/CWC 同源配对；strict 默认仍拒多片 |
| 集成 | DBG-off 等价；新字逐位=checker 输出；既有 9 字读值/位置不变；新字地址无冲突 |
| 几何 | 一致→结论；可推得→改参数+重跑 G1+记 diff；证据不足→保持原值+diagnostic（禁止猜测回填） |
| 仿真 | 100 帧 0 误判/0 覆盖；坏帧 ≥5 类全拒（无发布/无部分帧） |
| 板安全（如预加载） | 仅 SRAM；flash/efuse/SPI/svf 零命中；≤1 次；未改线/电源/相机；无 GUI 自动化 |
| protected/diff | 除允许清单与记录在案追加行外逐字节相等；旧候选/旧证据未动 |
| manifest | 0 不一致；所有新文件/日志可复算 SHA256 |
| 上板期望（供清单冻结） | 身份/长度/CTRL 同基线；word3 推进；word6 good 增长；`word9=0x3E`（校验中可采 `0x01`，重采一次）`word10=0x0009E400` `word13≥1` 且增量≈word3 增量 |

## 6. 预算、停止与回退（本轮无人值守冻结）

- 角色默认自停：每角色每次派发 ≤30 calls、规划 15 min/开发与测试 45 min；**本 run 各包冻结值（覆盖理由见 §3 各包）**：P1 dev 90 min/50 calls、tester 30/30；P2 dev 60/30、tester 20/25；P3 dev 75/40、tester 30/30；P4 dev 45/30、tester 20/25。角色不得自行扩预算。
- 命令 deadline：读/搜 60 s；单 TB ≤5 min、整组 ≤15 min；TD 单会话 ≤30 min；下载 ≤5 min；单命令 ≤60 s。
- 停止：缺工具/资料/授权/设备 → blocked（不空转）；连续 2 循环无新进展 → NO_PROGRESS；预算耗尽 → LIMIT_REACHED；构建 2 次失败/时序不收敛/CWC 校验失败 → blocked；不改门槛求 PASS；外部错误不自动重试/扩权。
- 修复分账：round0 首次验收；同任务真实 FAIL 续原开发/原测试，round1—3 最多三轮实际修复；三轮后仍 FAIL 保留 ⚠、由原规划在本轮边界内决定独立后续包；blocked 不计修复轮。
- 顺序裁剪：时间不足从尾部裁（P4→P3→P2）；被裁/阻塞包如实登记、不降门槛、不自动续做。
- 回退：P1=`git revert`/丢弃新增；P2=删本包产物+重下旧 bit；P3=丢弃新增 TB/记录；P4=清单含断电清 SRAM/重下旧 bit。全程遵守单文件删除禁令（默认不删）。

## 7. 后续主题（≤3，不自动续做）

1. 用户回来“点两下”→ 上板两样本读回与 G3 判定（含新 checker 字；沿用 GUI 唯一路径；word6 归因/短稳按用户决定后置或纳入）。
2. checker 生产路径（DBG-off 常驻）+ PCIe/RK 主机侧寄存器暴露与端到端（需主机授权，另 run）。
3. 真实几何/相位完整板证（MP07/08 补测：OB/起点/镜像/phase）+ RK/三算法接入（另轮）。

## 8. 本轮 done 口径与用户配合

- **本轮 done**=P1—P4 依序收束（全 PASS；或如实登记 ⚠/blocked 与恢复入口）；G3 待用户点击后判；父 T11 不置 done。
- **用户配合最小集（终态）**：今晚无需任何操作。回来时按 P4 `board-checklist.md`“点两下”（若板已断电则先花一次命令重下，约 30–40 s）；报告路径与期望值以该清单为准。
