# T02 ChipWatcher 详细操作文档（可直接照做）

> **中文路径打不开时用这个 ASCII 路径**：
> CWC：`D:\anlogic\runa_runD\t02_ascii_20261019_234035\t02_current.cwc`（SHA256 `b28e3d4ee476731b118da0b12c3bad8dcca1dadfbd9b7ae4dc418c4d225a74ce`）
> bit：`D:\anlogic\runa_runD\t02_ascii_20261019_234035\t02_current.bit`（SHA256 `b68c6e183e97eb0d465db77078f5049feca3a947fac51f99633621dd99b3f9bf`）
> 样本保存：`D:\anlogic\runa_runD\t02_ascii_20261019_234035\samples\T1` 与 `D:\anlogic\runa_runD\t02_ascii_20261019_234035\samples\T2`
> CWC 二进制扫描未发现内嵌中文/绝对路径引用；详见 `C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道\workflow\runs\20261019-2117_runD_batch2_continue\board\t02\recovery01\ascii-staging.md`。纯用户操作见 `C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道\workflow\runs\20261019-2117_runD_batch2_continue\board\t02\recovery01\user-actions-only.md`。

- run：`20261019-2117_runD_batch2_continue`｜任务：`T02.codex-singleA-board`
- 文档时间：2026-10-19 23:25 +08:00
- **当前状态**：板上已下载 **T02 候选** `b68c6e183e97eb0d465db77078f5049feca3a947fac51f99633621dd99b3f9bf`；下载证据 `PRG-2014 : Chip validation success: PH1P100`、29.43 s、进度 100%、rc=0；下载后 `read_device_id=PH1P100`。5555 唯一 LISTENING=PID **64540**；`td.exe` PID **45416** 不得关闭。**G3=`not_run`**，本文操作完成前不要判 PASS。
- **本轮边界**：只写文档；0 硬件动作、0 下载、0 GUI 点击、0 杀进程、0 Flash/efuse/SPI/svf、0 CLI readback、0 GUI 自动化、0 commit/push、0 批量删除。不要重复下载、不要换线、不要改传感器表/电源。

---

## 1. 所有相关文件的完整绝对路径与 SHA256

> 下列路径均可在资源管理器地址栏直接粘贴。SHA256 为本轮实际复算值（除标注“未复算”者）。你拍完截图后，也可用 `Get-FileHash -Algorithm SHA256 -LiteralPath "<完整路径>"` 复算。

### 1.1 T02 当前候选（**采样必须用这一组**）

| 文件 | 完整绝对路径 | SHA256 | 大小(B) |
|---|---|---|---|
| CWC（配对文件，ChipWatcher 打开它） | `C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道\workflow\runs\20261019-0212_codex_fpga_closedloop_b2\recovery01\B01\timing-continuation01\remaining-attempts01\candidate\current.cwc` | `b28e3d4ee476731b118da0b12c3bad8dcca1dadfbd9b7ae4dc418c4d225a74ce` | 312109 |
| bit（配对；不要重新下载） | `C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道\workflow\runs\20261019-0212_codex_fpga_closedloop_b2\recovery01\B01\timing-continuation01\remaining-attempts01\candidate\current.bit` | `b68c6e183e97eb0d465db77078f5049feca3a947fac51f99633621dd99b3f9bf` | 5224034 |
| BID | `C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道\workflow\runs\20261019-0212_codex_fpga_closedloop_b2\recovery01\B01\timing-continuation01\remaining-attempts01\candidate\current.bid` | `4dcdc26382f6b49e7ed9b95a40a1d57c05191c0130050812a74b853c16b38f33` | 188792 |
| probe map（40 探针定义） | `C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道\workflow\runs\20261019-0212_codex_fpga_closedloop_b2\recovery01\B01\timing-continuation01\remaining-attempts01\candidate\probe-map.json` | `96eb210bb0c55eed110b2a35a8ae0d3ccd3d8823c3d4286a635f9f9dd46d888a` | 238857 |
| manifest（699 项） | `C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道\workflow\runs\20261019-0212_codex_fpga_closedloop_b2\recovery01\B01\timing-continuation01\remaining-attempts01\candidate\manifest.json` | `c7a40897166467f2beafb096701dba9cf836e1007d77ae03d90009d06f80d757` | 255465 |

### 1.2 本轮证据/清单（只读；用于核对，不要改）

| 文件 | 完整绝对路径 | SHA256 | 大小(B) |
|---|---|---|---|
| 最终上板清单 | `C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道\workflow\runs\20261019-2117_runD_batch2_continue\board\t02\board-checklist-final.md` | `00203239c48dc9d054fd6c9dbd25e858cda18ee19dd5cc7a064736ac4d9d7cbf` | 5806 |
| 用户证据/Phase A+B | `C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道\workflow\runs\20261019-2117_runD_batch2_continue\board\t02\recovery01\user-evidence-03.md` | `fbaca100b64b12d9c22c08eba30d16f15a1d1f26deb5d5e3c910ae6f5ff35795` | 4165 |
| 租约（已下载状态） | `C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道\workflow\runs\20261019-2117_runD_batch2_continue\board\t02\recovery01\lease-recovery03.json` | `9dd7ccb84964264e01c767d0762941f5c24a169426ba53756e29c5e1c1e131d7` | 3236 |
| 恢复 manifest | `C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道\workflow\runs\20261019-2117_runD_batch2_continue\board\t02\recovery01\manifest-recovery03.json` | `221d2fefabd95eeaede7da53644a5e9451987ffb1bfb716597be795120ab71e3` | 6814 |

### 1.3 冻结参考文档（只读）

| 文件 | 完整绝对路径 | SHA256 |
|---|---|---|
| 两次采样旧清单 | `C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道\workflow\runs\20261019-0212_codex_fpga_closedloop_b2\board\t02\two-capture-checklist.md` | `c45795c3fc4311edc0b8c79dd3a1730c6915f82d3b62216838b01d5ca7dfc9ee` |
| 40 探针参考 | `C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道\workflow\runs\20261019-0212_codex_fpga_closedloop_b2\board\t02\probe-reference.md` | `015c8ed192a91f9ff8820f79468af342e749cecfe1f7a14c3877f07edad2ee12` |
| 旧上板 runbook | `C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道\workflow\runs\20261018-1631_runA_fpga_side_readchannel\debug-spec\board-runbook.md` | `bf06579127288985e9f719698ba69f8f075dd4836e69a133cbce6127c8c30898` |

### 1.4 回退候选（只保留入口，不自动执行）

| 候选 | 文件 | 完整绝对路径 | SHA256 |
|---|---|---|---|
| 0207 bit | bit | `D:\anlogic\runa_runC\20261019_192056\compiled.bit` | `5b67a8f5925327ba9d0442d9e4228fcfd254c80a2f86d921ceda70ecae111d52`（现场直接哈希 MATCH） |
| 0207 CWC（冻结 prestage） | CWC | `C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道\workflow\runs\20261019-0207_runA_ddr_readback_loop\board-checklist\candidate-manifest-v8.json` 中 `prestage.files_core` 记录的 `compiled.cwc`（143,444 B） | `8dda54d4efa8e6be728a6ebb34686f25de90a36b039eda6f831dfb9c346c664f`；**现场 `D:\anlogic\runa_runC\20261019_192056\compiled.cwc` 直接哈希为 `2362a86e3b8720649757979e08cd6fca5ba9bee8732576cafce32f264c751755`（667,892 B），与冻结值不一致，标“待现场核对”，不得用错 CWC** |
| 基线 bit | bit | `C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道\workflow\runs\20261018-1631_runA_fpga_side_readchannel\debug-fix3\prj\ph1p_pcie_integration_Runs\phy_1\cw\compiled.bit` | `bfafdf97ff78d6f6d2646ffc706542a0bbbb7e11869043ba754cf68a270813d0` |
| 基线 CWC | CWC | `C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道\workflow\runs\20261018-1631_runA_fpga_side_readchannel\debug-fix3\prj\ph1p_pcie_integration_Runs\phy_1\cw\compiled.cwc` | `8d2998b96ef1763c14a1302118235a687488297ce496692b1f6cd95d76981026` |

> TD 可执行文件：`D:\anlogic\TD_Release_2026.2\bin\td.exe`，版本 `TD_Release_2026.2`；本轮未复算其 SHA（仅 GUI 使用，非候选输入）。当前已运行 PID 45416，**不要关闭、不要新开第二个 TD 去下载**。

---

## 2. 操作前 30 秒核对（只读，不改任何东西）

在 PowerShell 或命令提示符执行：

```bat
tasklist | findstr /i hwserver
netstat -ano | findstr :5555
tasklist | findstr /i td.exe
```

应看到：

- `hwserver.exe` 有两行：37440（旧残留，**不要关**）与 64540（持 FTDI、监听 5555）。
- `netstat` 只有一行 `0.0.0.0:5555 ... LISTENING 64540`。
- `td.exe` 只有 45416。

若 5555 不是 64540 或出现两个 LISTENING：**停**，不要点 ChipWatcher，先把界面截图发主。不要杀进程、不要重下。

可选复核 CWC/bit 哈希（PowerShell，逐条粘贴）：

```powershell
Get-FileHash -Algorithm SHA256 -LiteralPath "C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道\workflow\runs\20261019-0212_codex_fpga_closedloop_b2\recovery01\B01\timing-continuation01\remaining-attempts01\candidate\current.cwc"
Get-FileHash -Algorithm SHA256 -LiteralPath "C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道\workflow\runs\20261019-0212_codex_fpga_closedloop_b2\recovery01\B01\timing-continuation01\remaining-attempts01\candidate\current.bit"
```

应分别得到 `b28e3d4e…a74ce` 与 `b68c6e18…3f9bf`（完整值见 §1.1）。不一致 → 停，不要采样。

---

## 3. ChipWatcher 逐步操作（T1/T2）

> 说明：TD 2026.2 的菜单文字/按钮位置可能因窗口布局不同而略有差异；下文以既有 runbook 的“TD → ChipWatcher → 选择同源 CWC → Watch → Add Signals → Instant Trigger”为依据。**若你的界面与本文不同，以实际界面为准并截图**，不要凭猜测点“下载/Program/Flash”类按钮。

### 3.1 打开 ChipWatcher 并加载 CWC

1. 切到已运行的 TD 2026.2（`td.exe` PID 45416）。**不要**点“Download/Program/Flash”，也不要新建工程去下载。
2. 在 TD 菜单/工具栏找到 **ChipWatcher**（可能在 `Tools`、`View` 或 `Window` 菜单下；也可能有独立图标）。点开。
3. 在 ChipWatcher 窗口点 **Open / Load / 选择 CWC**（以实际按钮名为准），在文件选择框粘贴并选中：
   `C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道\workflow\runs\20261019-0212_codex_fpga_closedloop_b2\recovery01\B01\timing-continuation01\remaining-attempts01\candidate\current.cwc`
4. 如果弹窗要求选择配对的 bit 文件，选：
   `C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道\workflow\runs\20261019-0212_codex_fpga_closedloop_b2\recovery01\B01\timing-continuation01\remaining-attempts01\candidate\current.bit`
   **只选文件，不要点下载/烧写**。若它要求“先下载才能 Watch”，**停**，截图发主；不要用它重新下载（板上已经是同一候选）。
5. 加载成功后，实例列表/下拉框应出现三个实例：
   - `auto_created_cwc1`（camera 域，时钟 `u_top/g_closedloop$u_algo/clk`）
   - `auto_created_cwc2`（DHI/DDR 域，时钟 `u_top/u_ddr3_mc_0/ph1p_ddrmc_wrapper/dhi_clk`）
   - `auto_created_cwc3`（TL 域，时钟 `u_top/u_uart/u_uart_cdc/core_clk`）
   若只看到一个实例，用实例下拉框切换；若三个都没有，截图并停。

### 3.2 确认实例与探针（不要跨实例混加）

- `auto_created_cwc1` 只加 16 个 camera 探针（`u_top/g_closedloop$...`）。
- `auto_created_cwc2` 只加 15 个 DHI 探针（`u_top/g_closedloop$u_readback/...`）。
- `auto_created_cwc3` 只加 9 个 TL 探针（`u_top/u_pcie_ep_engine/.../dbg_mark_word0..8`）。
- 三个实例的时钟不同，**不是一个原子快照**；同一实例内才算同时。不要把它们合并成一个“总快照”。

### 3.3 加信号并设置触发

对每个实例重复：

1. 选中实例（例如 `auto_created_cwc1`）。
2. 点 **Add Signals / Add Probes / Watch**（以实际按钮为准）。
3. 在信号树中展开完整层次，勾选该实例的探针（完整名见 §5 的 40 行表；可整实例全选，避免漏项）。若列表只显示短名，用搜索框粘贴完整名（如 `u_top/g_closedloop$source_good[31:0]`）。
4. **触发列表留空**（不要设条件触发）；点 **Instant Trigger**（立即触发）。
5. 等待状态变为 `Triggered` / `Done` / `Captured`（以实际界面为准）。若显示 `Idle` 或 `Triggered=0`：
   - 这是“无数据”，不是“通过”。
   - 可在同一 T1 时刻再点 **一次** Instant Trigger（最多再 1 次），并记录两次尝试时间与截图。
   - 仍无数据 → 停，保存界面截图，发主；**不要重复下载、不要换线、不要重启 TD**。
6. 在 Value/波形列表读取每个探针的 **完整 32 位十六进制原值**（如 `0x434C0101`）。不要只抄十进制或截断。
7. 若界面有 **Export / Save As / Copy Value**，优先导出 CSV/TXT；同时截图。若没有导出，截图必须包含实例名、探针名、数值列、窗口时间（若显示）。

### 3.4 T1：三个实例分别 Instant Trigger

顺序建议：`auto_created_cwc1` → `auto_created_cwc2` → `auto_created_cwc3`。每切一个实例都要重新 Add/Watch 该实例的探针，再点 Instant Trigger。记录**每个实例**的触发时间（精确到秒），不要只记一个总时间。

T1 截图/导出保存到（建议目录，若不存在请新建）：

`C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道\workflow\runs\20261019-2117_runD_batch2_continue\board\t02\samples\T1\`

建议文件名（把 `YYYYMMDD_HHMMSS` 换成实际时间）：

- `T1_cwc1_camera_YYYYMMDD_HHMMSS.png`（或 `.csv`）
- `T1_cwc2_dhi_YYYYMMDD_HHMMSS.png`（或 `.csv`）
- `T1_cwc3_tl_YYYYMMDD_HHMMSS.png`（或 `.csv`）

### 3.5 等待 ≥20 s，再 T2

从**最后一个 T1 Instant Trigger** 完成时刻起，保持接线/供电不变，等待 **至少 20 秒**（建议 25 秒，用手机/系统时钟计时）。然后按 §3.3—§3.4 对三个实例分别再做一次 Instant Trigger，保存到：

`C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道\workflow\runs\20261019-2117_runD_batch2_continue\board\t02\samples\T2\`

文件名：

- `T2_cwc1_camera_YYYYMMDD_HHMMSS.png`（或 `.csv`）
- `T2_cwc2_dhi_YYYYMMDD_HHMMSS.png`（或 `.csv`）
- `T2_cwc3_tl_YYYYMMDD_HHMMSS.png`（或 `.csv`）

### 3.6 记录操作者/接线/供电

在回传模板里写：操作者、日期/时区、T1/T2 实际时间与间隔秒数、单 A 接线是否动过、供电是否动过、TD 是否弹窗/报错。**没有变化也要写“未变”**。

---

## 4. 16 个关键字段（历史“16 字”模板；先填这张，再填 §5 全表）

> 说明：本候选 `probe-map.json` 实际是 **40 个 32 位探针**（cwc1 16 + cwc2 15 + cwc3 9）。历史“16 字”是回传模板，不是 CWC 里只有 16 个信号。下面 16 个是最关键字段；即使只回传 16 字，也请把 §5 的 40 项整实例导出/截图，避免缺项。

| # | 字段 | 实例 | 期望/范围 | T1 实际 | T2 实际 | 备注 |
|---|---|---|---|---|---|---|
| 1 | `cl_identity` | cwc2 | `0x434C0101` |  |  | 身份不符即停 |
| 2 | `cl_seq` | cwc2 | 两个不同 seq |  |  | T1/T2 不应相同 |
| 3 | `cl_session` | cwc2 | 记录原值 |  |  | 同组内可解释 |
| 4 | `cl_base` | cwc2 | 记录原值（DDR 基址） |  |  | 不猜 |
| 5 | `cl_len` | cwc2 | `2592768`（`0x00279000`） |  |  | 两帧均一致 |
| 6 | `cl_words` | cwc2 | `648192`（`0x0009E400`） |  |  | 两帧均一致 |
| 7 | `cl_flags` | cwc2 | `[31]=1,[3:0]=15,[15:8]=0` |  |  | 记录完整 hex |
| 8 | `cl_header_crc` | cwc2 | 记录原值 |  |  | 随图像变化 |
| 9 | `cl_payload_crc` | cwc2 | 记录原值 |  |  | 随图像变化 |
| 10 | `cl_pass_count` | cwc2 | 持续推进 |  |  | 记录增量 |
| 11 | `cl_fail_count` | cwc2 | `0` |  |  | 非零即停/记录 |
| 12 | `cl_fault` | cwc2 | `0` |  |  | 非零即停 |
| 13 | `cl_writer_good` | cwc2 | 推进/增加 |  |  | 与 pass 对照 |
| 14 | `cl_writer_bad` | cwc2 | 基线 0；内部 abort 后 >0 |  |  | 记录场景 |
| 15 | `cl_recovery_count` | cwc2 | 基线 0；abort 后 `>=1` |  |  | 首个 good 完整通过 |
| 16 | `algo_identity` | cwc1 | `0x414C0101` |  |  | 身份不符即停 |

---

## 5. 40 个 32 位探针完整表（T1/T2 留空给你填）

> 完整探针名来自冻结 `probe-map.json` 与 `probe-reference.md`。填表时写 **完整 32 位 hex 原值**；无法确认的映射/期望已标“待现场核对”，不要猜。`auto_created_cwc3` 的 9 个 `dbg_mark_word` 在冻结材料中没有给出固定期望值，只记录原值。

### 5.1 `auto_created_cwc1`（camera 域，16 项；时钟 `u_top/g_closedloop$u_algo/clk`）

| # | 完整探针名 | 期望/范围 | T1 实际 | T2 实际 | 备注 |
|---|---|---|---|---|---|
| 1 | `u_top/g_closedloop$source_bad[31:0]` | 基线可 0；内部 abort 后 >0 |  |  | 记录场景 |
| 2 | `u_top/g_closedloop$source_crc[31:0]` | 记录原值；随图像变化 |  |  | 不比较常数 |
| 3 | `u_top/g_closedloop$source_geometry[31:0]` | 解码 `{last_lines[15:0],last_wc[15:0]}`；高 16 源行数、低 16 源 RAW 字节；**不是 ROI 尺寸** |  |  | 记录原值+解码 |
| 4 | `u_top/g_closedloop$source_good[31:0]` | 持续推进/增加 |  |  | 与 bad 对照 |
| 5 | `u_top/g_closedloop$source_header[31:0]` | 记录原值（header 末值） |  |  | 不猜 |
| 6 | `u_top/g_closedloop$source_injected[31:0]` | 基线 0；内部 abort 时应为 1 |  |  | 记录场景 |
| 7 | `u_top/g_closedloop$u_algo/algo_gau_complete[31:0]` | 推进/非零 |  |  | 与 gau_crc 配对 |
| 8 | `u_top/g_closedloop$u_algo/algo_gau_crc[31:0]` | 记录原值 |  |  | 随图像变化 |
| 9 | `u_top/g_closedloop$u_algo/algo_he_complete[31:0]` | 推进/非零 |  |  | 与 he_crc 配对 |
| 10 | `u_top/g_closedloop$u_algo/algo_he_crc[31:0]` | 记录原值 |  |  | 随图像变化 |
| 11 | `u_top/g_closedloop$u_algo/algo_identity[31:0]` | `0x414C0101` |  |  | 身份不符即停 |
| 12 | `u_top/g_closedloop$u_algo/algo_inbeats[31:0]` | 记录/推进 |  |  | 记录原值 |
| 13 | `u_top/g_closedloop$u_algo/algo_overflow[31:0]` | 期望 0；>0 记录并停下判定 |  |  | 非零异常 |
| 14 | `u_top/g_closedloop$u_algo/algo_rejected[31:0]` | 期望 0（非注入场景）；>0 记录 |  |  | 非零异常 |
| 15 | `u_top/g_closedloop$u_algo/algo_y8_complete[31:0]` | 推进/非零 |  |  | 与 y8_crc 配对 |
| 16 | `u_top/g_closedloop$u_algo/algo_y8_crc[31:0]` | 记录原值 |  |  | 随图像变化 |

### 5.2 `auto_created_cwc2`（DHI/DDR 域，15 项；时钟 `u_top/u_ddr3_mc_0/ph1p_ddrmc_wrapper/dhi_clk`）

| # | 完整探针名 | 期望/范围 | T1 实际 | T2 实际 | 备注 |
|---|---|---|---|---|---|
| 17 | `u_top/g_closedloop$u_readback/cl_base[31:0]` | 记录原值（DDR 基址） |  |  | 不猜 |
| 18 | `u_top/g_closedloop$u_readback/cl_fail_count[31:0]` | `0` |  |  | 非零即停 |
| 19 | `u_top/g_closedloop$u_readback/cl_fault[31:0]` | `0` |  |  | 非零即停 |
| 20 | `u_top/g_closedloop$u_readback/cl_flags[31:0]` | `[31]=1,[3:0]=15,[15:8]=0` |  |  | 记录完整 hex |
| 21 | `u_top/g_closedloop$u_readback/cl_header_crc[31:0]` | 记录原值 |  |  | 随图像变化 |
| 22 | `u_top/g_closedloop$u_readback/cl_identity[31:0]` | `0x434C0101` |  |  | 身份不符即停 |
| 23 | `u_top/g_closedloop$u_readback/cl_len[31:0]` | `2592768`（`0x00279000`） |  |  | 两帧一致 |
| 24 | `u_top/g_closedloop$u_readback/cl_pass_count[31:0]` | 持续推进 |  |  | 记录增量 |
| 25 | `u_top/g_closedloop$u_readback/cl_payload_crc[31:0]` | 记录原值 |  |  | 随图像变化 |
| 26 | `u_top/g_closedloop$u_readback/cl_recovery_count[31:0]` | 基线 0；abort 后 >=1 |  |  | 首个 good 完整通过 |
| 27 | `u_top/g_closedloop$u_readback/cl_seq[31:0]` | T1/T2 两个不同 seq |  |  | 相同即异常 |
| 28 | `u_top/g_closedloop$u_readback/cl_session[31:0]` | 记录原值 |  |  | 同组内可解释 |
| 29 | `u_top/g_closedloop$u_readback/cl_words[31:0]` | `648192`（`0x0009E400`） |  |  | 两帧一致 |
| 30 | `u_top/g_closedloop$u_readback/cl_writer_bad[31:0]` | 基线 0；内部 abort 后 >0 |  |  | 记录场景 |
| 31 | `u_top/g_closedloop$u_readback/cl_writer_good[31:0]` | 推进/增加 |  |  | 与 pass 对照 |

### 5.3 `auto_created_cwc3`（TL 域，9 项；时钟 `u_top/u_uart/u_uart_cdc/core_clk`）

| # | 完整探针名 | 期望/范围 | T1 实际 | T2 实际 | 备注 |
|---|---|---|---|---|---|
| 32 | `u_top/u_pcie_ep_engine/u_ep_bar_win/g_dbg_mark$dbg_mark_word0[31:0]` | 记录原值；固定映射/期望待现场核对 |  |  | 不要猜 |
| 33 | `u_top/u_pcie_ep_engine/u_ep_bar_win/g_dbg_mark$dbg_mark_word1[31:0]` | 记录原值；待现场核对 |  |  | 不要猜 |
| 34 | `u_top/u_pcie_ep_engine/u_ep_bar_win/g_dbg_mark$dbg_mark_word2[31:0]` | 记录原值；待现场核对 |  |  | 不要猜 |
| 35 | `u_top/u_pcie_ep_engine/u_ep_bar_win/g_dbg_mark$dbg_mark_word3[31:0]` | 记录原值；待现场核对 |  |  | 不要猜 |
| 36 | `u_top/u_pcie_ep_engine/u_ep_bar_win/g_dbg_mark$dbg_mark_word4[31:0]` | 记录原值；待现场核对 |  |  | 不要猜 |
| 37 | `u_top/u_pcie_ep_engine/u_ep_bar_win/g_dbg_mark$dbg_mark_word5[31:0]` | 记录原值；待现场核对 |  |  | 不要猜 |
| 38 | `u_top/u_pcie_ep_engine/u_ep_bar_win/g_dbg_mark$dbg_mark_word6[31:0]` | 记录原值；待现场核对 |  |  | 不要猜 |
| 39 | `u_top/u_pcie_ep_engine/u_ep_bar_win/g_dbg_mark$dbg_mark_word7[31:0]` | 记录原值；待现场核对 |  |  | 不要猜 |
| 40 | `u_top/u_pcie_ep_engine/u_ep_bar_win/g_dbg_mark$dbg_mark_word8[31:0]` | 记录原值；待现场核对 |  |  | 不要猜 |

---

## 6. 可直接复制回传的模板

把下面整段复制到聊天/文档，填完发回。未知项写 `未读到`，不要编造；失败也照实写。

```text
【T02 ChipWatcher 采样回传】
操作者：
日期/时区：2026-10-19 (UTC+08:00)
板卡：PH1P100 / T02 候选 b68c6e183e97eb0d465db77078f5049feca3a947fac51f99633621dd99b3f9bf
单 A 接线是否变化：
供电是否变化：
TD 是否弹窗/报错：
T1 组开始时间（cwc1 第一次 Instant Trigger）：
T1 组最后触发时间（cwc3）：
T2 组开始时间：
T1→T2 间隔（秒，需 ≥20）：
截图/导出文件完整路径：
  T1_cwc1:
  T1_cwc2:
  T1_cwc3:
  T2_cwc1:
  T2_cwc2:
  T2_cwc3:

===== T1 原值（完整 32 位 hex）=====
cwc1.source_bad=0x
cwc1.source_crc=0x
cwc1.source_geometry=0x            # 另写解码：last_lines=        last_wc=
cwc1.source_good=0x
cwc1.source_header=0x
cwc1.source_injected=0x
cwc1.algo_gau_complete=0x
cwc1.algo_gau_crc=0x
cwc1.algo_he_complete=0x
cwc1.algo_he_crc=0x
cwc1.algo_identity=0x
cwc1.algo_inbeats=0x
cwc1.algo_overflow=0x
cwc1.algo_rejected=0x
cwc1.algo_y8_complete=0x
cwc1.algo_y8_crc=0x
cwc2.cl_base=0x
cwc2.cl_fail_count=0x
cwc2.cl_fault=0x
cwc2.cl_flags=0x
cwc2.cl_header_crc=0x
cwc2.cl_identity=0x
cwc2.cl_len=0x
cwc2.cl_pass_count=0x
cwc2.cl_payload_crc=0x
cwc2.cl_recovery_count=0x
cwc2.cl_seq=0x
cwc2.cl_session=0x
cwc2.cl_words=0x
cwc2.cl_writer_bad=0x
cwc2.cl_writer_good=0x
cwc3.dbg_mark_word0=0x
cwc3.dbg_mark_word1=0x
cwc3.dbg_mark_word2=0x
cwc3.dbg_mark_word3=0x
cwc3.dbg_mark_word4=0x
cwc3.dbg_mark_word5=0x
cwc3.dbg_mark_word6=0x
cwc3.dbg_mark_word7=0x
cwc3.dbg_mark_word8=0x

===== T2 原值（完整 32 位 hex）=====
cwc1.source_bad=0x
cwc1.source_crc=0x
cwc1.source_geometry=0x            # 另写解码：last_lines=        last_wc=
cwc1.source_good=0x
cwc1.source_header=0x
cwc1.source_injected=0x
cwc1.algo_gau_complete=0x
cwc1.algo_gau_crc=0x
cwc1.algo_he_complete=0x
cwc1.algo_he_crc=0x
cwc1.algo_identity=0x
cwc1.algo_inbeats=0x
cwc1.algo_overflow=0x
cwc1.algo_rejected=0x
cwc1.algo_y8_complete=0x
cwc1.algo_y8_crc=0x
cwc2.cl_base=0x
cwc2.cl_fail_count=0x
cwc2.cl_fault=0x
cwc2.cl_flags=0x
cwc2.cl_header_crc=0x
cwc2.cl_identity=0x
cwc2.cl_len=0x
cwc2.cl_pass_count=0x
cwc2.cl_payload_crc=0x
cwc2.cl_recovery_count=0x
cwc2.cl_seq=0x
cwc2.cl_session=0x
cwc2.cl_words=0x
cwc2.cl_writer_bad=0x
cwc2.cl_writer_good=0x
cwc3.dbg_mark_word0=0x
cwc3.dbg_mark_word1=0x
cwc3.dbg_mark_word2=0x
cwc3.dbg_mark_word3=0x
cwc3.dbg_mark_word4=0x
cwc3.dbg_mark_word5=0x
cwc3.dbg_mark_word6=0x
cwc3.dbg_mark_word7=0x
cwc3.dbg_mark_word8=0x

备注（异常/缺项/内部 abort 场景）：
```

---

## 7. 异常分流（任一即停，保留原样）

1. **身份/下载层**：`read_device_id` 非 `PH1P100`、`PRG-8000`、connect/close 超时 → 停；保存 ChipWatcher/控制台原文截图；不重试、不换线、不杀进程、不重下。报主/原规划。
2. **DDR 校准异常**：板卡黑屏四灯齐报、`D37` 灭/校准未完成 → 停；用户物理断电 10 s 再上电（用户操作）；因 SRAM 易失，需由**新的授权轮次**重新 SRAM 下载；本轮不自动重下、不自动电源循环。
3. **字段不符**：`cl_identity`/`algo_identity` 不符、`fault/error` 非零、`cl_len/cl_words` 不符、`cl_fail_count>0` → 停；保存当前原值与截图；不靠反复点击/重下冲淡失败；记录实际值，改数字凑 PASS 禁止。
4. **GUI 异常**：ChipWatcher 打不开、CWC 加载失败、实例缺失、Instant Trigger 无波形、软件弹窗/崩溃 → 保存界面原文截图，注明时间；最多在同 T1 时刻重试一次 Instant Trigger；仍失败即停，交主/原规划。**禁止 GUI 自动化/脚本点击**。
5. **不要做**：不要重复下载、不要点 Flash/Program、不要换线、不要改传感器表/电源、不要启动第二个 hwserver、不要杀 `td.exe` 45416 或 `hwserver` 64540、不要 CLI 读回。

---

## 8. 回退入口（完整路径；不自动执行）

- **0207 候选 bit**：`D:\anlogic\runa_runC\20261019_192056\compiled.bit`，SHA `5b67a8f5925327ba9d0442d9e4228fcfd254c80a2f86d921ceda70ecae111d52`。
- **0207 候选 CWC（冻结 prestage）**：见 `C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道\workflow\runs\20261019-0207_runA_ddr_readback_loop\board-checklist\candidate-manifest-v8.json` 的 `prestage.files_core`；冻结 SHA `8dda54d4efa8e6be728a6ebb34686f25de90a36b039eda6f831dfb9c346c664f`（143,444 B）。**现场 `D:\anlogic\runa_runC\20261019_192056\compiled.cwc` 直接哈希为 `2362a86e3b8720649757979e08cd6fca5ba9bee8732576cafce32f264c751755`（667,892 B），与冻结值不一致，标“待现场核对”，不要用错 CWC。**
- **基线候选 bit**：`C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道\workflow\runs\20261018-1631_runA_fpga_side_readchannel\debug-fix3\prj\ph1p_pcie_integration_Runs\phy_1\cw\compiled.bit`，SHA `bfafdf97ff78d6f6d2646ffc706542a0bbbb7e11869043ba754cf68a270813d0`。
- **基线候选 CWC**：`C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道\workflow\runs\20261018-1631_runA_fpga_side_readchannel\debug-fix3\prj\ph1p_pcie_integration_Runs\phy_1\cw\compiled.cwc`，SHA `8d2998b96ef1763c14a1302118235a687488297ce496692b1f6cd95d76981026`。
- 回退由用户按清单执行；不自动重下、不自动电源循环。SRAM 易失：断电即失，恢复需重下（另轮授权）。

---

## 9. 边界（全程）

仅 SRAM；**0 Flash/efuse/SPI/svf**；0 CLI readback；0 GUI 自动化；不推送；不接 PCIe/RK；不 commit/push；不批量删除；不杀 `td.exe` 45416 或持 FTDI 的 `hwserver` 64540；不覆盖 0207/B01/T02 冻结文件。**G3 仍未 PASS**：两次样本回传后，由原 batch 综合测试者独立核验；preload/下载成功不等于 G3 PASS。
