# T02 上板清单 — 单 A RAW→DDR 板级闭环（本 run 未下载）

run：`20261019-2117_runD_batch2_continue`｜任务：`T02.codex-singleA-board`｜冻结时间：2026-10-19 21:32 +08:00
当前状态：**awaiting_hardware**（本 run 唯一一次只读 `read_device_id` 未取得 `PH1P100`，0 次 download；板上加载状态未知）。**不得**把本清单当 G3 PASS；没有两次真实样本就没有 T02 闭环。

## 1. 候选身份（已复算 MATCH，冻结）

| 项 | 绝对路径 | SHA256 |
|---|---|---|
| manifest（699 项） | `C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道\workflow\runs\20261019-0212_codex_fpga_closedloop_b2\recovery01\B01\timing-continuation01\remaining-attempts01\candidate\manifest.json` | `c7a40897166467f2beafb096701dba9cf836e1007d77ae03d90009d06f80d757` |
| bit | 同目录 `current.bit` | `b68c6e183e97eb0d465db77078f5049feca3a947fac51f99633621dd99b3f9bf` |
| CWC | 同目录 `current.cwc` | `b28e3d4ee476731b118da0b12c3bad8dcca1dadfbd9b7ae4dc418c4d225a74ce` |
| BID | 同目录 `current.bid` | `4dcdc26382f6b49e7ed9b95a40a1d57c05191c0130050812a74b853c16b38f33` |
| probe map | 同目录 `probe-map.json` | `96eb210bb0c55eed110b2a35a8ae0d3ccd3d8823c3d4286a635f9f9dd46d888a`（40 探针，3 个采样时钟域） |

生产构建 6/6 已封顶：**禁止第 7 次生产构建**；本轮未构建、未重跑 T06/T09 仿真。下载入口语义沿用 0212 `run_sram.py` / `download_sram.tcl`（connect → read_device_id → download -mode jtag → close）。

## 2. 当前板载与现场事实（截至 21:32）

- 本 run：0 次 download，0 次 CLI 读回，0 次 Flash/efuse/SPI/svf；板上候选**未知/未被本 run 改变**。
- 本 run 只读探测：`bw.exe read_id.tcl` 两次均 60 s 超时、stdout/stderr 为空、无器件行（见 `board/sram/20261019_213000/probe-result.json`）。
- 并行 0207 线最新 `board-checklist/preload-record-v4.md`（21:23）：0 次 download；其 21:20 `read_device_id` 报 `PRG-8000 ERROR: transfer failed`（27.1 s）；状态 `awaiting_user_gui`。本 run 不覆盖、不借用其候选，也不代替其结论。
- 进程快照：`td.exe` PID 45416 与 `hwserver.exe` PID 45596（5555）均存活，未触碰；无 `td_commands_prompt`/`run_td`/`run_build`/download 活跃进程。租约见 `board/board-window-lease.json`（已释放，不阻塞 0207）。
- 结论：**先做物理检查**（板电源/指示灯、DDR 校准完成、USB/JTAG 线插稳、必要时换线换口），再由**新的、明确授权的一轮**重新执行板窗检查与一次 ≤180 s SRAM 下载；本 run 不自动重试、不等待。

## 3. 用户“回来点两下”步骤（仅在责任开发报告本次 SRAM 下载成功后执行）

1. **确认下载成功**：责任开发须已记录 `read_device_id=PH1P100`、rc=0、`PRG-2014 Chip validation success: PH1P100`、100%、单次 ≤180 s、SHA 无漂移。未成功就不要打开/点击 ChipWatcher，先按 §6 异常分流。
2. **打开唯一配对 CWC**：`...\candidate\current.cwc`（SHA `b28e3d4e…4ce`）。不要另点 GUI 下载、不要换线、不要改传感器表/电源。
3. **第 1 时刻（T1）**：在 ChipWatcher 对 `auto_created_cwc1`（camera 域）和 `auto_created_cwc2`（DHI/DDR 域）**分别** Instant Trigger；各保存完整 32 位原始数值/原始导出文件；截图须能读完字段；记录实例名、操作者、采样时间。
4. **等待 ≥20 s**，保持接线/供电不变，做第 2 时刻（T2）同样两次 Instant Trigger，另存原始值+截图+时间戳。
5. camera 侧至少保留：`source_good/bad/crc/header/geometry/injected`、`algo_identity`、三路 `complete/CRC`、`overflow/rejected`；DHI 侧保留全部 `cl_*`（含 `cl_identity/seq/session/base/len/words/flags/header_crc/payload_crc/pass_count/fail_count/writer_good/writer_bad/recovery_count/fault`）。**16 字/40 探针的完整原值**不得只抄结论；能整实例导出就导出。
6. 两次采样是**两个不同 seq** 的完整帧；camera 与 DHI 是不同时钟域的独立实例，**不得**拼成“跨域原子快照”。把原文/清晰截图 + “操作者、采样时间、单 A 接线/供电是否变化”一起返回；判定由后续责任角色完成。

## 4. 冻结期望值（G3 口径）

- 身份：`cl_identity=0x434c0101`，`algo_identity=0x414c0101`。
- 两帧均：`words=648192`，`len=2592768`，`flags[31]=1`，`flags[3:0]=15`，`flags[15:8]=0`，`fault=0`，`pass_count` 持续推进；magic/header_crc/payload_crc/length 四类 ok 全真，错误计数 0；`seq` 两个不同。
- 几何：`source_geometry={last_lines[15:0], last_wc[15:0]}`（高 16 位源行数、低 16 位源 RAW 字节数）；源模式/ROI 期望 `X960/Y540/W1920/H1080/SKIP37`。必须解释实际输出合规依据，不得把源几何误当 ROI 尺寸，不得改数字凑 PASS。
- 相位：最终候选 `PHASE=3`；物理 Bayer 相位仍未证，计数/颜色观感不能代替；无有效配置/标定/真实图样依据时保持 `unknown`。
- 坏帧/恢复：一次**内部 abort** 必须 `source_injected=1`，`writer_bad` 及拒发布路径成立，随后 `cl_recovery_count>=1`，且首个合法 good 帧完整通过 checker；旧 pending 帧不算恢复。内部 abort ≠ 物理 CSI CRC 故障。
- 短窗 ≥20 s；G4 10 分钟/热/长稳/性能本轮不测、不外推。

## 5. 回退

- 旧回退 pair（只作入口，**不自动执行**）：bit `bfafdf97ff78d6f6d2646ffc706542a0bbbb7e11869043ba754cf68a270813d0`、CWC `8d2998b96ef1763c14a1302118235a687488297ce496692b1f6cd95d76981026`，位于基线 run `workflow\runs\20261018-1631_runA_fpga_side_readchannel\debug-fix3\prj\ph1p_pcie_integration_Runs\phy_1\cw\compiled.bit|compiled.cwc`。
- 若板已断电或状态不明：不要自动电源循环；先做 §2 物理检查；如需重新加载，由新的授权轮次执行一次 SRAM 重下（≈30–40 s），仍须 read_device_id=PH1P100 且零 Flash。

## 6. 异常分流（任一即停，保留原样）

1. 身份非 `PH1P100`、`PRG-8000/PRG-2014` 失败、connect/close 超时 → 停，保存原始日志，不重试、不换线、不杀他人进程，返回 `awaiting_hardware`。
2. 下载后 DDR 校准异常、读不到完整帧、`fault/error` 非零、`cl_identity/algo_identity` 不符 → 停，保存当前截图/原值，不靠反复点击或重下冲淡失败。
3. 两帧 `words/len/seq/flags` 不满足 → 记录实际原值，判 G3 不通过；最多再补 2 组须由责任角色给出明确缺项与触发目标（总 3 组）。
4. 出现 GUI 弹窗/软件失败 → 保留可见状态并截图，注明时间；禁止 GUI 自动化。
5. 任何情况下：零 Flash/efuse/SPI/svf、零 CLI 读回、不接 PCIe/RK、不推送、不 commit。

## 7. G 层口径

- G0/G1/G2：继承 B01 同 manifest 的 r0 PASS（699 项身份未漂移）。
- G3：`not_run / awaiting_hardware`（本 run 无样本）；**preload/清单不等于两样本，不判 PASS**。
- G4：`not_run`（用户后放）。
