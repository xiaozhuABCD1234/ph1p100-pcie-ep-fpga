# fpga-design-guide.md — 20261019-0207_runA_ddr_readback_loop

原规划者冻结（2026-10-19，无人值守轮）。本文件=本任务数据/接口/参数/工作目录/构建入口与现有约束的冻结值；只冻结相关项，其余引用原文件（冲突时以本文件冻结值为准；未列项沿用既有工程约定）。
背景技能：[fpga-design-guide/SKILL.md](../../../.agents/skills/fpga-design-guide/SKILL.md)；有界规则：[work-limits.md](../../../.agents/skills/fpga-orchestrator/references/work-limits.md)。基线冻结：[基线 run fpga-design-guide](../../20261018-1631_runA_fpga_side_readchannel/fpga-design-guide.md)（其 §1/§2/§4/§5/§6/§7 除本文件更新处外继续有效）。

> **v1.1 更新（2026-10-19，重锚 CR-20261019-0207-02）**：本任务 RTL 工作树改为**本线独立 worktree** `upstream\ph1p100-pcie-ep-fpga-wt0207`（branch `opencode/runC-0207`；base `b0282d2a` + 基线 `debug-fix3` 的 4 路径 r3 diff 复现）；共享树 `upstream\ph1p100-pcie-ep-fpga` 归并行 run 0212（本线只读）。§1—§7 其余契约不变。

## 1. 任务数据与范围（冻结）

- **唯一主要目标**：DDR 读回校验集成闭环候选——checker 接入调试候选（含几何/相位离线核对与条件回填）、一次构建冻结新 bit/CWC、坏帧/100 帧仿真证据、"回来点两下"上板清单齐备。
- **非目标（本轮不做）**：PCIe/RK/三算法接入；Flash/持久化；UART；消费级长稳 G4；word6 归因；生产 DBG-off 路径的 checker 常驻；CWC CLI 读回复活（永久关闭，仅保留 SRAM 下载能力）。
- **上游工作树**：`upstream/ph1p100-pcie-ep-fpga`（分支 `codex/raw10-rka1`；HEAD `b0282d2a…`；**继承 4 路径未提交 r3 改动**，见 input-index §2.2）。
- **行为基线（protected）**：生产 DBG-off 行为、生产 SDC `constraints/ph1p_pcie_case_ep.sdc` 语义、`00_all`（非 debug）默认、PCIe 硬核/IP、DDR 写者(`cam_r10f_writer`/`cam_ddr_writer`)/推帧(`ddr_frame_pusher`)既有语义、旧候选 bit 与全部既有证据/run。

## 2. DDR 读回校验集成契约（冻结；N1）

1. **模块本体**：`rtl/ep_side/ddr/ddr_frame_readback_checker.v` 端口/编码契约（文件头 §一）视为冻结接口；仅允许契约兼容的最小调整（如为接入所需的参数化），任何偏离必须在 `candidate.diff` + dev-notes 记录并新增对应 TB 证据。不得无证据改变判定语义（ok 位/err_code/超时/重入）。
2. **集成位置**：实例化于 `ph1p_pcie_ep_top.v` 的 DDR 读主侧，时钟=`dhi_clk`（100 MHz）；AXI4 读口接入既有 DDR 读仲裁结构，风格对齐 `ddr_frame_pusher` 的读主。
3. **仲裁与所有权**：checker 读口优先级≤写者/推帧（不得饿死、不得阻塞写者提交或推帧；不得修改既有仲裁语义）；除新增本读口外，不改任何主机可见行为；**不向主机/PCIe 发起任何动作**。
4. **触发（冻结）**：**逐好帧自动校验**——每次 `DDR_SEQ_A` 递增（新帧发布）触发一次：锁存当拍 `DDR_BASE_A[28:0]`（须 32B 对齐）与 `DDR_LEN_A` 作为 base/frame_bytes，单拍 `start`；同一时刻只允许一个检查（busy 重入由模块契约拒绝，不重启、不清进度）。复位必须**不依赖 PCIe 链路**（沿用 issue-02 修复口径：无主机可读、可运行）；若发布边沿与字段更新存在竞态，允许按同域最坏情形用“稳定一拍后采样”处理，但必须在 TB 覆盖并记录。
5. **DBG 归属（冻结）**：checker 集成仅在 **debug 构建（DBG=1 通道）** 活动；生产 DBG-off 路径不新增活动逻辑、行为与 r3（HEAD+继承改动）等价（编译/源码级证明 + 既有 8 TB 全 PASS）。理由：不扰动已验证生产主线，风险最小；生产常驻是后续主题。

## 3. 调试读回字扩展（冻结；N1 的实现结果、P2/P4 的消费对象）

- **保留既有 9 字**（0x140..0x160，word0..8）位置与读值不变；新字**追加**在 word8 之后。
- **地址规则**：自 `0x164` 起连续 dword 偏移顺延；写入前用 `docs/protocol/rka1-r10f-v1/contract/registers.json` 复核无冲突；冲突则顺延到下一连续未占用段（沿用 probe-map §2.4 规则），记 diff。

| 字 | 偏移 | 名称 | 位域/语义（冻结） |
|---|---|---|---|
| word9 | 0x164 | CHECK_STATUS | `[0]=busy [1]=done(粘滞) [2]=magic_ok [3]=hdr_crc_ok [4]=payload_crc_ok [5]=length_ok [15:8]=err_code [31:16]=0`（值以 dhi 域两级同步进 `tl_clk_user` 快照） |
| word10 | 0x168 | CHECK_WORDS_READ | checker `words_read`（已处理 32bit 字数；1080p 满帧期望 `0x0009E400`=648,192） |
| word11 | 0x16C | CHECK_HDR_CRC32 | 重算头 CRC32（末值） |
| word12 | 0x170 | CHECK_PAYLOAD_CRC32 | 重算载荷 CRC32（末值） |
| word13 | 0x174 | CHECK_RUNS | `done` 上升沿计数（每完成一次校验 +1；≥1 且随发布推进） |
| word14..19 | 0x178..0x18C | CHECK_SMP0..5（**可选**） | checker 抽样端口；容量/位宽不足时可整组降级省略，**优先保留 smp1=head[20]/smp2=head[21]（存储 CRC 对照自证）**，其次 smp0/smp4/smp5；降级记 diff |

- **CDC**：新字按 `csi_diag_a` 先例（两级同步的同域快照）进入 `ep_bar_win` 的只读调试字库并挂 `MARK_DEBUG` 快照组；**无副作用**（不驱动任何控制/总线/外发路径）；既有字读 mux 行为不变（default 仍 `32'hDEAD_BEEF`）。
- **CWC 探针**：扩展现有 debug 入口（`tools/pcie_integration/td/00_all_debug.tcl`）使新字进入探针组；由 TD 真实流程重新生成 `cw/compiled.cwc`；实例名/探针名以 TD 实际生成为准（基线 `auto_created_cwc1`）；probe-map 更新写本 run（不覆盖基线 `debug-spec/`）。
- **容量降级**：单实例容纳不下时允许同域第二实例（probe-map 既有降级路径）；**不得改 A 组判据**。

## 4. 几何/相位回填规则（冻结；N3）

- **证据源（仅限）**：基线 run P3 两样本读数（word5/word7/word6）+ RTL 自洽规则（`cam_ddr_writer.v` L106 标定式）+ `registers-plan`/MP07/08 口径。今晚**无新板测**。
- **动作分级**：
  1. 一致→在 `geometry-audit.md` 给出逐项一致性结论（W/H/X0/Y0/SKIP_ROWS/stride/phase/帧长），不改 RTL；
  2. 可推得确定新值（推导链完整、影响面明确）→改参数 + 同步更新受影响 TB/预期表 + 重跑 G1，全部记 `candidate.diff`；
  3. 证据不足（如 last_lines=2192 vs 标定式 37+2160=2197 的差异无法定论）→**保持原值**、标注 diagnostic/待板证，列入上板清单的追加观察项。
- **禁止**：无推导链“猜测回填”；为凑读数硬改 H/SKIP_ROWS/phase；改参数后不重跑 G1；把未板证值写成已板证。
- 产出：本 run `checker-integrate/geometry-audit.md`（含证据引用与结论分级）；回填结论同时写 dev-notes 供 P4 清单引用。

## 5. 仿真约定（沿用基线）

- 入口：`run_sim.ps1 -Tb <tb> -OutDir <dir> -TbFiles tb/<file>.v`；既有回归统一 `-Defines MIPI_PHY_SIM_STUB`；判定=`vlog Errors:0` + `vsim ALL PASS`。
- 时限：单 TB ≤5 min；整组（新 TB 集+8 TB）≤15 min；超出拆多次运行并如实记录。
- 100 帧循环仿真允许用小尺寸可参数化帧以控制时长（几何由 TB 参数给出，不得改生产默认参数）；另保留 1080p 满帧场景。
- 坏帧注入类别（≥5）：magic 错、头 CRC 错、载荷 CRC 错、截断/短帧、长度错、（可选）AXI 响应错/超时/abort；期望=整帧拒发（无发布、无部分帧、无缓冲覆盖），err_code/ok 位与模块契约一致且不产生假 PASS。

## 6. 构建、CWC、位流与上板预期（冻结；P2/P4 消费）

- 构建：debug 入口 `00_all_debug`（生产 `00_all` 不动）；单会话 ≤30 min、**最多 2 次**（第 2 次须有新证据/参数纠正并记录理由）；会同判据=`td_00_all.log` 含 `PRJ-1406`+`PRJ-1424`+`T07_ALL_DONE`、`commands.log stage=… exit=0`、`final_timing.rpt Confidence=Routed`。
- G2 门槛（不放宽）：SWNS/STNS/HWNS≥0（记数值）、0 违例、资源在器件内；CWC 经 `setup_debugger` 重新生成 + `check_chipwatcher_readback.py --multipiece` **0 失败**（strict 默认仍拒绝多片）；bit/CWC 同源配对，分别记 SHA。
- 候选并列：新 bit/CWC 为新候选（新 manifest/diff），与 `bfafdf97…`（当前板载）、`2385cded…`、`e81d353b…` 并列，不混拼、不覆盖；回退=重下旧 bit（SRAM 易失，≈30–40 s）。
- **上板预期（供 P4“回来点两下”清单冻结）**：身份/长度/CTRL 同基线命中；word3 推进；word6 good 增长（相机活）；新字稳态期望 `word9=0x3E`（恰逢校验中可采样到 `0x01`，可解释，重采一次为准）、`word10=0x0009E400`、`word13≥1` 且增量≈word3 增量；word11/12 原文记录（与 word14/15 存储 CRC 对照若保留）。
- 板级安全（全程）：仅 SRAM；零 flash/efuse/SPI/svf 命令；不推送；不改线/电源/相机；禁止 GUI 自动化；单命令 ≤60 s（下载 ≤5 min、≤1 次，仅 P4 可选预加载）。

## 7. 证据、manifest 与回退（冻结）

- 每包：`candidate-manifest.json`（新文件逐项 SHA256、0 不一致）、`dev-result.md`、`dev-notes`（含允许清单与理由）、`lessons.md`（开发写）。
- 绑定：bit/CWC/BID/timing/area/diff/manifest 同链；`commit` 允许本地提交（不推送）；worktree-only 冻结可接受（≤1 次尝试，权限拒绝即停，记 manifest `commit_status`）。
- protected 审计：旧候选 bit/既有 run/证据只读；`workflow/tasks.json` 本轮不写（收尾由原规划）。
- 回退：P1=`git revert`/丢弃新增文件；P2=删本包产物（不删旧候选）+重下旧 bit；P4=清单含断电清 SRAM/重下旧 bit。**全程不批量删除**（根 AGENTS）。

## 8. 已冻结 / 待确认 / 不适用（本轮）

- **已冻结**：§2 集成/触发/仲裁/DBG 归属；§3 新字地址与位域（含降级规则）；§4 回填分级与禁止项；§5 仿真入口/时限/坏帧类别；§6 构建/CWC/G2/上板预期/安全；§7 证据与回退。
- **待确认（由开发在包内定，不阻塞）**：TB 命名与拆分；smp 子集取舍；第二实例是否触发；发布边沿采样细节；CWC 实例/探针实际名；可推得的几何新值是否存在（§4 分级 2/3）。
- **不适用（本轮）**：PCIe/主机寄存器读；UART；Flash；GUI 自动化；G3/G4 判定（G3 待用户回来点两下；G4 后置）。
- **综合测试三维边界（一个综合测试者，独立于开发）**：
  - functional=新 TB/回归全 PASS、字表↔checker 输出逐一可追、仿真相位期望与计数一致、几何结论的证据链可复核；
  - engineering=编译/端口/时钟/CDC 规范、diff 允许清单、G2 数值与时限、CWC multipiece 0 失败、manifest 0 不一致、路径/命名规则；
  - system=DBG-off 等价、protected 审计、零硬件（P4 预加载除外）、零 Flash/不推送、旧候选并列、回退链与证据绑定（含操作者/时间/命令/退出码）。
