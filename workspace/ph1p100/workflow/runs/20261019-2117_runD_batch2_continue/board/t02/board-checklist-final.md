# T02 最终上板清单（当前板载 = T02 候选 `b68c6e18…`）

run：`20261019-2117_runD_batch2_continue`｜任务：`T02.codex-singleA-board`｜冻结时间：2026-10-19 23:16 +08:00
当前状态：**两样本已回传（聊天截图，T1/T2 各三实例），待 tester r0 独立核验；G3 仍 `not_run`。** 板上是 T02 候选，不是 0207 候选；0207 回退信息见 §5。
样本记录：`C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道\workflow\runs\20261019-2117_runD_batch2_continue\board\t02\samples\sample-record.md` 与 `C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道\workflow\runs\20261019-2117_runD_batch2_continue\board\t02\samples\sample-record.json`；证据仅聊天截图 6 张，无 CSV/原始导出，截图未落盘。

## 1. 候选身份（下载前复算 MATCH）

| 项 | 绝对路径 | SHA256 |
|---|---|---|
| manifest（699 项） | `C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道\workflow\runs\20261019-0212_codex_fpga_closedloop_b2\recovery01\B01\timing-continuation01\remaining-attempts01\candidate\manifest.json` | `c7a40897166467f2beafb096701dba9cf836e1007d77ae03d90009d06f80d757` |
| bit | 同目录 `current.bit`（暂存副本：`C:\Users\czz\AppData\Local\Temp\opencode\t02_phaseb_20261019_231409\current.bit`） | `b68c6e183e97eb0d465db77078f5049feca3a947fac51f99633621dd99b3f9bf` |
| CWC | 同目录 `current.cwc`（暂存副本同目录） | `b28e3d4ee476731b118da0b12c3bad8dcca1dadfbd9b7ae4dc418c4d225a74ce` |
| BID | 同目录 `current.bid` | `4dcdc26382f6b49e7ed9b95a40a1d57c05191c0130050812a74b853c16b38f33` |
| probe map | 同目录 `probe-map.json`（40 探针） | `96eb210bb0c55eed110b2a35a8ae0d3ccd3d8823c3d4286a635f9f9dd46d888a` |

- 下载证据：`board/sram/20261019_231429/`；`PRG-2014 : Chip validation success: PH1P100`；29.43 s；进度 100%；rc=0；下载后 `read_device_id=PH1P100`（`board/sram/20261019_231516/`）。
- Server：5555 唯一 PID 64540（`D:\downlaod\bin\hwserver.exe -r -f 1 -s 5555`）；`td.exe` 45416 未触碰。

## 2. 用户现在只需点两次（T1/T2，间隔 ≥20 s）

1. 打开唯一配对 CWC：`...\candidate\current.cwc`（SHA `b28e3d4e…4ce`）；不要另点下载、不要换线、不要改传感器表/电源。
2. **T1**：在 ChipWatcher 对 `auto_created_cwc1`（camera）与 `auto_created_cwc2`（DHI/DDR）分别 Instant Trigger；各保存完整 32 位原值/原始导出；截图需能读完字段；记录实例、操作者、时间。
3. 保持接线/供电不变，**等待 ≥20 s**。
4. **T2**：同样分别 Instant Trigger，另存原值+截图+时间戳。
5. 回传：两组原文/清晰截图 + 操作者 + 采样时间 + 单 A 接线/供电是否变化。camera 保留 `source_good/bad/crc/header/geometry/injected`、`algo_identity`、三路 `complete/CRC`、`overflow/rejected`；DHI 保留全部 `cl_*`（含 `cl_identity/seq/session/base/len/words/flags/header_crc/payload_crc/pass_count/fail_count/writer_good/writer_bad/recovery_count/fault`）。16 字/40 探针完整原值，不只抄结论。
6. camera 与 DHI 是不同时钟域独立实例，**不得**宣称跨域原子同一时刻。

## 3. 冻结期望值（G3 口径，判定由后续责任角色完成）

- `cl_identity=0x434c0101`，`algo_identity=0x414c0101`。
- 两帧均：`words=648192`，`len=2592768`，`flags[31]=1`，`flags[3:0]=15`，`flags[15:8]=0`，`fault=0`，`pass_count` 持续推进；magic/header_crc/payload_crc/length 四 ok 全真、错误计数 0；`seq` 两个不同。
- 几何：`source_geometry={last_lines[15:0], last_wc[15:0]}`（高 16 位源行数、低 16 位源 RAW 字节数）；源模式/ROI 期望 `X960/Y540/W1920/H1080/SKIP37`。必须解释实际输出合规依据，不得把源几何误当 ROI 尺寸，不得改数字凑 PASS。
- 相位：最终候选 `PHASE=3`；物理 Bayer 相位未证，计数/颜色观感不能代替；无有效配置/标定/真实图样依据时保持 `unknown`。
- 坏帧/恢复：一次内部 abort 必须 `source_injected=1`，`writer_bad` 及拒发布路径成立，随后 `cl_recovery_count>=1`，首个合法 good 帧完整通过 checker；旧 pending 帧不算恢复。内部 abort ≠ 物理 CSI CRC 故障。
- 短窗 ≥20 s；G4 10 分钟/热/长稳/性能本轮不测、不外推。

## 4. 异常分流（任一即停，保留原样）

1. 身份非 `PH1P100`、`PRG-8000/PRG-2014` 失败、connect/close 超时 → 停，保存原始日志，不重试、不换线、不杀进程，报主/原规划。
2. DDR 校准异常、读不到完整帧、`fault/error` 非零、`cl_identity/algo_identity` 不符 → 停，保存截图/原值，不靠反复点击或重下冲淡失败。
3. 两帧 `words/len/seq/flags` 不满足 → 记录实际原值，G3 不通过；最多再补 2 组须由责任角色给出明确缺项与触发目标（总 3 组）。
4. GUI 弹窗/软件失败 → 保留可见状态并截图，注明时间；禁止 GUI 自动化。
5. 任何情况下：零 Flash/efuse/SPI/svf、零 CLI 读回、不接 PCIe/RK、不推送、不 commit。

## 5. 回退信息（仅保留入口，不自动执行）

- **0207 候选**：bit `5B67A8F5925327BA9D0442D9E4228FCFD254C80A2F86D921CEDA70ECAE111D52`（`D:/anlogic/runa_runC/20261019_192056/compiled.bit`，现场直接哈希 MATCH）；CWC 以 0207 `candidate-manifest-v8.json` 的 prestage 副本 `8DDA54D4EFA8E6BE728A6EBB34686F25DE90A36B039EDA6F831DFB9C346C664F` 为准（现场 `compiled.cwc` 直接哈希为 `2362a86e…`，与 v6 文字不一致，疑为另存/时间戳变化；不用于 T02 判定）。
- **基线候选**：bit `bfafdf97ff78d6f6d2646ffc706542a0bbbb7e11869043ba754cf68a270813d0` / CWC `8d2998b96ef1763c14a1302118235a687488297ce496692b1f6cd95d76981026`，位于 `workflow\runs\20261018-1631_runA_fpga_side_readchannel\debug-fix3\prj\ph1p_pcie_integration_Runs\phy_1\cw\compiled.bit|compiled.cwc`。
- 回退由用户按清单执行；不自动电源循环、不自动重下。

## 6. G 层口径

- G0/G1/G2：继承 B01 同 manifest（699 项未漂移）。
- G3：`not_run`（本文件创建时尚无两次样本）；**preload/下载成功不等于 G3 PASS**。
- G4：`not_run`（用户后放）。
