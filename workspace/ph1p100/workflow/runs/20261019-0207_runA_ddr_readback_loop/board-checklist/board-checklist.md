# board-checklist.md — “回来点两下”上板清单（T11.runC-board-checklist，冻结）

- run：`20261019-0207_runA_ddr_readback_loop`（0207 线，Track A）｜候选：`T11.runC-build`（P2）新 debug 位流 + 配对 CWC（含新字 word9..15）
- 状态：**板载=新候选（bit `5B67A8F5…1D52` / CWC `8DDA54D4…664F`），可以点了** —— 2026-10-19 21:56:53 +08:00 用户按 §2 完成 SRAM 预加载（`PRG-2014` + 100% + 30.037585 s + 下载后 `read_device_id`=PH1P100；证据 `preload-record-v6.md`）。**SRAM 易失：采样前勿断电**；若断电，按 §2 重下（本任务下载 1/1 已用，需另轮/协调）。2026-10-19 22:13:15/22:13:45 有界重采两样本 C/D 均为完成态、间隔 30 s、全部冻结判据满足（C/D 与 A/B 见 `board-samples-01.md`/`board-samples-02.md`）→ 本包 **ready_for_test**。**G3 终判由综合测试者报告 + 原规划收尾判定（§8）**。
- 安全边界（全程）：**仅 SRAM**（`-mode jtag`）；零 Flash/efuse/SPI/svf；不改线/电源/相机；禁止 GUI 自动化（只能你本人点）；不推送；下载 ≤1 次、失败不重试。
- 板窗口与并行线（0212）**串行互斥**：下载前先确认窗口空闲；若板上是对方候选/不确定 → **停，不覆盖**，交用户/原规划协调。

## 0. 最小动作（30 秒版）

1. 板已断电/刚上电 → 先按 §2 重下本候选（一次 SRAM 下载，约 30–40 s）；板一直在电且没换过位流 → 直接第 2 步。
2. 打开 TD 2026.2 → ChipWatcher → 选本候选的 `compiled.cwc` → Watch → Add Signals：word0..15 → Instant Trigger；**等 ≥10 s** 再点一次。
3. 把两次的 **16 字十六进制原文 + 时间戳**（含时区）回传即可（§5 模板）。

## 1. 候选身份 / 板载现状

| 项 | 冻结值 |
|---|---|
| bit | `5B67A8F5925327BA9D0442D9E4228FCFD254C80A2F86D921CEDA70ECAE111D52`（5,224,027 B；`phy_1\ph1p_pcie_integration.bit` 与 `cw\compiled.bit` 逐字节相同） |
| CWC | `8DDA54D4EFA8E6BE728A6EBB34686F25DE90A36B039EDA6F831DFB9C346C664F`（143,444 B；实例 `auto_created_cwc1`，16 view nodes / 512+512，26 pieces） |
| BID | `A068E42E50B2D9D9CED1AE85F9CFA9E272BBCE99AE83192CA7FC930AF9ECF1DB`（151,492 B） |
| 原位置 | `workflow\runs\20261019-0207_runA_ddr_readback_loop\build\prj\ph1p_pcie_integration_Runs\phy_1\`（`ph1p_pcie_integration.bit`、`cw\compiled.cwc`） |
| 暂存副本 | `D:\anlogic\runa_runC\20261019_192056\`（`compiled.bit` / `compiled.cwc` / `preload.bwcmd` / `staging-record.txt`；SHA 已复核 MATCH；**新建、零覆盖**） |

**本轮板载现状 = 未查（unknown）**：本包开发未执行 `connect_cable`/`read_device_id`/`download`——按互斥规则下载前须由在场用户确认板窗空闲，且 19:14 起并行线（0212）在本机运行 TD 构建；本轮不冒险占用板窗/USB。回来时先做下面的**只读**检查（不读回、不改板）：

```
connect_cable -host_name 127.0.0.1:5555 -open
read_device_id          # 期望 PH1P100；不符 → 停（查线/上电），不重试
connect_cable -close
```

- `read_device_id=PH1P100` 只证明芯片与线缆通，不证明板上是哪个候选；候选身份由 word0/1/2 与 word9..15 是否出现（§4）判定。
- 若 5555 端口已有 hwserver（TD GUI 自带，PID 每次可能不同）→ 直接 `connect_cable`，**不要再起第二个**；没有时用基线参数起一个并在用后释放：`D:\downlaod\bin\hwserver.exe -r -s 5555 -f 12 -v -w 5556 -i 0`。
- 同一 5555 只应有一个**已持有 FTDI** 的 hwserver（控制台打印 `Open device vid=0x0403 pid=0x6042`）。若出现 `Error @ mpsse.cpp:90 : usb_open() failed`，先由用户关掉未持有 FTDI 的重复实例/窗口（勿结束 `td.exe` 45416），再重试本节只读检查。

## 2. 可选 SRAM 预加载（“回来先重下”分支；≤1 次 / ≤5 min）

前提：**你在场并确认板窗口空闲**（板上不能是并行线刚下载的候选；不确定 → 不做，交原规划）。命令脚本已备好（修正版，未成功执行）：

```
cd /d D:\anlogic\runa_runC\20261019_192056
D:\downlaod\bin\bw_commands_prompt.exe read_id_v5.bwcmd < NUL
D:\downlaod\bin\bw_commands_prompt.exe download_v5.bwcmd < NUL
```

（第一条期望 `PH1P100`；第二条期望 `PRG-2014 : Chip validation success: PH1P100` + 100% + rc=0，≈28–40 s；失败不重试。）

`download_v5.bwcmd` 内容（逐行；**路径必须用正斜杠**——BW 会把 `\` 当转义符，反斜杠路径会报 `PRG-8000 File path invalid`，已实测）：
```
connect_cable -host_name 127.0.0.1:5555 -open
download -bit D:/anlogic/runa_runC/20261019_192056/compiled.bit -mode jtag -spd 7 -cable 0
read_device_id
connect_cable -close
```

- 判据：`download` rc=0 + `PRG-2014 : Chip validation success: PH1P100` + 进度 100% + 时长 ≈28–40 s；旁路 `usb_open() failed` 提示不单独判败（bw 自动拉起的第二实例提示）。
- 记录：操作者、时间（含时区）、命令、rc、时长、日志路径（`<cwd>\log\bw_*.log`）、bit SHA（`5B67A8F5…`）；回填 §5 附注行。
- **失败/板未上电/USB 错/超 5 min → 停止，不重试**；保留原文交原规划。本清单本身即“回来先重下”的兜底（旧候选仍可回退，§7）。
- 若已有 hwserver 占用 5555 → 跳过 hwserver 启动，直接跑 `connect_cable…` 部分；用后按基线释放新会话。
- 严格禁止：`-mode flash`/`-mode spi`、efuse、svf、任何未知命令；命中即停。

## 3. 用户 GUI 步骤（唯一读回路径；CLI 读回永久关闭）

1. 打开 TD 2026.2 → **ChipWatcher**。
2. 选择与下载 bit **同源配对**的 `compiled.cwc`（`D:\anlogic\runa_runC\20261019_192056\compiled.cwc`；或 run `build\...\phy_1\cw\compiled.cwc`）；若 GUI 要求 Bit File，指向同目录 `compiled.bit`（SHA 与 §1 一致，不得换 bit）。
3. **Watch** → **Add Signals**：加入 16 个字 `word0..word15`（以 TD 实际生成的 16 个 view node 为准；实例 `auto_created_cwc1`）。
4. 触发列表**留空**；点一次 **Instant Trigger** → 从波形/Value 列表读 16 字**原文**（十六进制原样）。
5. **间隔 ≥10 s**，再点一次 Instant Trigger → 再读 16 字。
6. 回传两次原文 + 每样本时间戳（含时区）+ 操作者 + CWC 实例名 + 任何界面告警原文（§5）。
- 禁止 GUI 自动化；只由你本人点击。`Idle`/`Triggered=0`/无波形 → 保留界面原文，最多再试 2 次 Instant Trigger；仍无 → 记录交原规划（**不判硬件故障、不盲试 CLI 读回**）。
- 非原子告示：同一 CWC 实例内信号视为同时；跨时刻/跨实例分开记录，禁止合并成一次“原子快照”。

## 4. 冻结预期值（逐字取自 `build\hardware-ready.md` §2 / manifest `board_expected`）

| 字（探针） | 寄存器偏移 | 期望值 / 行为 |
|---|---|---|
| word0 / 1 / 2（身份/长度/CTRL） | 0x040 / 0x118 / 0x11C | 同基线命中（`50434946` / `31414B52` / `00010000`；CTRL 以 GUI 实读为准） |
| word3（DDR_SEQ_A） | 0x0A0 | 推进 |
| word4 / word5 | 0x0A4 / 0x0AC | 基线参考：`00900000`（128 B 对齐）/ `00279000`（=2,592,768） |
| word6（CSI_DIAG_A） | 0x120 | good 增长（相机活）；bad/hdr/crc=0 |
| word7（CSI_DIAG_A2） | 0x124 | 基线参考：`089012DE`（last_lines=2192 / last_wc=4830） |
| word8（CTRL） | 0x044 | 基线参考：`00000021`（bit0=1、bit5=1、bit4=0、bit6=0、bit7=0、[31:9]=0） |
| word9（CHECK_STATUS） | 0x164 | 稳态 `0x3E`；恰逢校验中可采样到 `0x01`（可解释，重采一次为准） |
| word10（CHECK_WORDS_READ） | 0x168 | `0x0009E400`（648,192；1080p 满帧） |
| word11（CHECK_HDR_CRC32） | 0x16C | 原文记录（重算头 CRC32 末值） |
| word12（CHECK_PAYLOAD_CRC32） | 0x170 | 原文记录（重算载荷 CRC32 末值） |
| word13（CHECK_RUNS） | 0x174 | ≥1，且增量≈word3 增量 |
| word14（CHECK_SMP1=head[20]） | 0x178 | = head[20]（存储 CRC 对照；与 word11 对照） |
| word15（CHECK_SMP2=head[21]） | 0x17C | = head[21]（存储 CRC 对照；与 word12 对照） |

- 备注：新 CWC 为 16 字（word0..15）；新字为**首测**，无历史基线，按上表与两样本自洽性判断；GUI Watch 列表以 TD 实际 16 节点为准。
- 基线两样本参考（旧候选 bfafdf97）：word3 `B1BE→B2EA`(+300)、word6 `BE000000→EA000000`（good 190→234）——只作“推进/增长”的对照，不作为本候选门槛。

## 5. 读数记录模板（每样本一行；原文十六进制；回传即可）

| # | 时间（含时区） | w0 | w1 | w2 | w3 | w4 | w5 | w6 | w7 | w8 | w9 | w10 | w11 | w12 | w13 | w14 | w15 | 备注 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |
| 2 |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |

附注行：操作者 / 下载 rc / 时长 / PRG-2014 / bit SHA256 / `compiled.cwc` SHA256 / CWC 实例名 / 日志路径 / 失败界面原文。

## 6. 异常分流（按现象→动作，不现场改判据）

| 现象 | 判定 | 动作 |
|---|---|---|
| `read_device_id` ≠ `PH1P100` 或 USB 报错 | 未连接 | 停：查线/上电；不重试、不盲试命令 |
| word0/1/2 不中（如 `DEADBEEF`/全 0） | 非本候选或未配置 | 按 §2 重下本候选 → 重采；仍不中 → 回退重下旧 bit（§7）并交原规划 |
| **word8（CTRL）bit6/7=1** | **断电清 SRAM 指示** | 走“板已断电”分支：先按 §2 重下，再采集 |
| DDR 校准异常（黑屏四灯齐报、D37 灭） | 校准失败 | 用户物理**断电 10 s** → 上电 → 重下同 bit（≤5 min/次）→ 记录时间与结果 |
| GUI `Idle`/`Triggered=0`/无波形 | 读回未出数 | 保留界面原文；≤2 次 Instant Trigger 重试；仍无 → 记录交原规划 |
| word9=`0x01`（校验中） | busy 采样 | 重采一次；连续两次均 `0x01` → 记录并交原规划（可解释，不判失败） |
| 身份对但 word10/word13 不符 | 数据异常 | **原文记录**，不现场改判据；交综合测试者/原规划（可能相机未出帧/尺寸变化，不能排除读回问题） |
| 板上像是并行线（0212）候选 / 不确定 | 窗口占用 | **停，不覆盖**；交用户/原规划协调 |

## 7. 回退（详见 `rollback.md`）

- 本候选回退 = 重下旧 bit（SRAM 易失，≈30–40 s）：板载基线 `bfafdf97…`、回退候选 `e81d353b…2b9a`；旧文件原位保留，不复制、不覆盖。
- 需要“彻底清空” → 物理断电（SRAM 位流即失）；**不写 Flash**。
- 任一步失败：保留日志/界面原文，停止修改，交原规划。

## 8. G3 tier 判定口径（最终判定不在此清单）

- **Tier-1（硬门槛）**：word0=`0x50434946`、word1=`0x31414B52`、word2=`0x00010000` 三字全中 + ≥1 组计数可复读（两样本一致或可解释）。任一不符 = Tier-1 FAIL。
- **Tier-2（基线/采集）**：word3 单调不减且 ≥1；word4 非零且 **128 B 对齐**（低 7 位=0）；word5=`2,592,768`；word6 good 增长（单 A）；bad/hdr/crc=0。
- **本候选新增字（Tier-2 补充/诊断）**：word9 稳态 `0x3E`；word10=`648,192`；word13≥1 且增量≈word3 增量；word11/12 原文；word14/15=head[20]/head[21] 对照。
- 采样：≥2 样本、间隔 ≥10 s；每样本 16 字原文。跨域说明：0x120/0x124 经两级同步进 `tl_clk_user`，跨域瞬间可能差一拍——属可解释差异，须原文记录。
- **判定权**：本清单只给口径与记录格式；**最终 G3 由综合测试者报告 + 原规划收尾判定；开发/本清单不自行宣布 PASS 或 FAIL**。未点击/未回传 = G3 not_run。

## 9. 审计清单（判读前逐条核对）

- [ ] 仅 SRAM：命令审计零 flash/efuse/SPI/svf；下载 ≤1 次、≤5 min、无重试
- [ ] 未改线/电源/相机；物理操作均由用户执行并记录
- [ ] bit/CWC 配对与 SHA 记录完整（`5B67A8F5…` / `8DDA54D4…`）；每条读数绑定通道（CWC 实例）/时间/操作者/输入 SHA
- [ ] ≥2 样本、间隔 ≥10 s；16 字原文；非原子告示在案
- [ ] 回退路径已记录（或已重下旧 bit）；板上 SRAM 现状留给用户决定是否断电
- [ ] 并行线互斥：下载前已确认窗口空闲；未覆盖对方候选
