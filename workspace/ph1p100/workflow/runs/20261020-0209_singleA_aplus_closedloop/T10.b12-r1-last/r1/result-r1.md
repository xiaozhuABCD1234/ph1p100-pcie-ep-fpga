# T10.b12-r1-last r1 — 诊断候选冻结（1 bitgen + 1 CWC，未改 RTL/SDC）

- run：`20261020-0209_singleA_aplus_closedloop`；任务 **T10.b12-r1-last**（批大小 1，r1 轮）；父任务 T10 **保持 blocked**
- 状态：**诊断候选已冻结**；`timing_caveat=thin_margin_+0.003`；板级 **blocked**（FTDI `0403:6042` 不在位，0 下载 / 0 COM8 / 不重试）
- 一句话结论：r0 的功能修复（R1 丢 LAST / 孤儿 writer）在仿真与布线层面已闭合，本轮用 **r0 已布线 DB** 生成 **1 次 bitgen + 1 次 CWC**，
  bitgen 内 final STA 复核 **SWNS +0.003 / HWNS +0.020 / Period +2.200 / 0 违例（25697 端点）**；
  用户已裁决 **接受 +0.003（0 违例）作为诊断候选**，`compiled.bit/cwc` 与父文件逐字节一致，可随时 SRAM 下载；**未上板，不宣称硬件结论**。

## 1. 本轮做了什么 / 没做什么

| 项 | 本轮 |
|---|---|
| RTL | **0 改动**（bitgen 直接消费 `r0/changed-src/**`，9 个哈希与 r0 manifest 一致） |
| SDC / ADC / 引脚 / 时钟 / UART_DIV / 板级约束 | **0 改动**（`p2_board.sdc`、`board_p2.adc` 与 b11 r0 逐字节相同） |
| 综合 / 布线 | **0 次**（复用 r0 的 `phy_1/a1_board_pr.db`，未重跑） |
| bitgen | **1 次**，成功 |
| CWC | **1 次**，成功，且 `cw/compiled.bit` 与父 bit 逐字节相同 |
| 下载 / Flash | **0 / 0** |
| 新增仿真 | 无（功能证据沿用 r0，见 §8 绑定方式） |

## 2. 产物与哈希（SHA-256）

| 产物 | 路径（run 内） | 字节 | SHA-256 |
|---|---|---|---|
| bit | `r1/td/a1_board.bit` | 5,224,022 | `9180DB8C13751CA34179E6CF3DE73DB178F259546565AFDD1CFFDAB3702F8CD3` |
| BID | `r1/td/a1_board_inst.bid` | 96,813 | `96D8A5DFF7C938BE571480B9F8A80EA893CC31B5CCE19402807A9BB3299E4A32` |
| CWC | `r1/td/a1_board.cwc` | 110,168 | `FFB88419D3A0A18A686EF0DCFD161DD0E4B719319AFC4D6B103FBF46EB47C9A0` |
| `cw/compiled.bit` | `r1/td/cw/compiled.bit` | 5,224,022 | `9180DB8C…2F8CD3`（= 父 bit） |
| `cw/compiled.cwc` | `r1/td/cw/compiled.cwc` | 110,168 | `FFB88419…B47C9A0`（= 父 CWC） |
| 布线 DB（输入） | `r0/td/a1_board_Runs/phy_1/a1_board_pr.db` | 32,099,888 | `FAAA8EB9D813F9DAAEEF6DAC4A944282CFCDAF58FE5F59116CED1203FA090471` |
| final STA 报告 | `r1/td/candidate_timing.rpt` | 5,726,989 | `7FEC697615B3A12A0867C58EB0FA3D716908E15B509E74589412FC50AA06BECD` |
| bitgen 日志 | `r1/td/bitgen_console_b12_r1.log` | 48,284 | `12E9F79C14DD61862CFFFF7CDD4DCBCEF95DE650F8F9968714250B68F4D0162B` |
| CWC 日志 | `r1/td/cwc_console_b12_r1.log` | 306,806 | `81EBF0CF4F347C864A8783F51B41A5F2B79E6123BC6E7D13DC182561E82BA726` |

- `BIT_IDENTICAL=1`、`CWC_IDENTICAL=1`：`02_bitgen.tcl` 写出父 bit 后，`03_cwc.tcl` 用 `setup_debugger` 生成的 `cw/compiled.bit`
  与父 bit **逐字节相同**（脚本内 `if {$parent_bit ne $debug_bit} { error ... }` 已通过），CWC 同理。
- BID 由 `02_bitgen.tcl` 内 `export_bid a1_board_inst.bid` 在同一会话导出（未额外加一次 bitgen）。
- b11 r0 的对照值：bit `7EF0E9BE…B810AA7`、CWC `08AD62F4…D86A52` —— **不同是预期的**（b12 含 R1 修复）。

## 3. 时序（bitgen 内 `update_timing -mode final` 复核）

| 项 | 值 |
|---|---|
| Routed SWNS / STNS | **+0.003 ns / 0.000** |
| Routed HWNS / HTNS | **+0.020 ns / 0.000** |
| Period Check WNS | **+2.200 ns** |
| 违例端点 / 总端点 | **0 / 25697** |
| 综合 SWNS | +0.121 |
| 资源 | slice 18370、reg 19539、**ERAM 72**（+CWC ≤ 300） |
| 最差 setup 路径 | `u_a1/u_a1/u_core/len_r_reg[6]_syn_2.clk → u_a1/u_a1/u_core/add9_syn_221.fci`（冻结 A+ 核心进位链） |
| 布线运行次数 / 一致性 | 2 次，两次逐位一致（r0） |

### 3.1 裁决（用户已选，r1 照此冻结）

- dev-plan §6 硬门槛 **+0.015 ns**，实测 **+0.003 ns**，差 **0.012 ns**；最差路径在**冻结的 A+ 核心**，
  不在 vendor DDR PHY、不在 R1 改动、不在 v4 观测路径，故 §6 的“只减观测”精简不适用。
- **用户裁决：接受 +0.003（0 违例）作为诊断候选**，`timing_caveat=thin_margin_+0.003`；
  本 bit/CWC **只能作为诊断/验证候选**，**不是生产签核**，也不是板级签核。
- **最终生产版必须补流水**（针对 A+ 核心 `len_r_reg → add9` 进位链，目标把 Routed WNS 拉回 ≥ +0.05 ns）；
  流水改动不在本包范围内，本包不改 RTL。

## 4. 板级（条件执行 → blocked）

- 预检（未打开 COM8、未下载）：`Get-PnpDevice -PresentOnly` 查 `VID_0403` / FTDI / Serial → **无任何 FTDI 设备**；
  串口只有 `COM3,COM4`（板载/蓝牙），**无 COM8**；`VID_0403&PID_6042` **不在位**。
- 结论：`board=blocked`、`board_blocked_reason=FTDI_0403:6042_absent`、**下载 0 次、COM8 打开 0 次、Flash 0 次、不重试**。
- 证据：`r1/board/ftdi-preflight.log`（含原始查询输出与 `FTDI_PRESENT=0 / COM8_PRESENT=0 / DOWNLOADS=0`）。
- 因此：**本轮不宣称“R1 修复在硬件上有效”**，也不对 1176 读停点新增任何结论（仍为 H2/H4，本包不修 DDR/PAXI）。

## 5. 命令与预算

- 环境：`powershell -NoProfile -File tools\td\td_env.ps1 -TdDir ...\T10.b12-r1-last\r0\td -Force` → `T:` = r0/td（含已布线 DB）、`Y:` = 项目根。
- bitgen：`td_commands_prompt.exe 02_bitgen.tcl`（cwd=`T:`）→ 退出 0，`P2_BITGEN_STA_SETUP=0.003/0.000 HOLD=0.020/0.000 PERIOD=2.200`、
  `P2_CANDIDATE_BIT_GENERATED_NO_DOWNLOAD`。
- CWC：`td_commands_prompt.exe 03_cwc.tcl`（cwd=`T:`）→ 退出 0，`P2_MATCHING_CWC_EXPORTED_NO_DOWNLOAD`，`compiled.bit == a1_board.bit`。
- TD 会话：2 次命令（同一 `T:` 映射，1 bitgen + 1 CWC；预算 bitgen 1 / CWC 1）；综合 0、布线 0、下载 0、Flash 0。
- 本轮工具调用约 20 次（预算 30）、用时约 25 分钟（预算 45）。

## 6. 冻结与一处必须说明的偏差

- **冻结**：`CANDIDATE-MANIFEST-b12-r1-last-r1.json`（run 根）、`r1/artifact-hashes.txt`、`r1/result-r1.md`、`r1/lessons-r1.md`、
  `r1/td/**`（bit/BID/CWC/compiled/final STA 报告/日志/项目描述符）、`r1/board/ftdi-preflight.log`。
- **偏差（工具行为，非人工修改）**：TD 在 `open_project` 时会**重写项目描述符** `a1_board.al`
  （25,142 B → 25,072 B；59 个 `<File Path>` 条目一个不少，RTL/SDC/ADC 内容未变）。
  同类现象在 b11 r0 也发生过（其 `.al` 被本包 bitgen 重写为 25,184 B，并已登记在 b11 manifest）。
  - 影响：r0 manifest 里 `a1_board.al` 的哈希是**打开前**状态，本轮无法逐字节复原该文件（run 目录未入 git，无备份）。
  - 处理：r1 manifest **同时登记** `r0/td/...pr.db`、`p2_board.sdc`、`board_p2.adc`、r0 routed 报告等**实质输入**的哈希，
    并冻结打开后的 `r1/td/a1_board.al`；RTL（9 个 changed-src）、SDC、ADC 三个实质输入哈希全部与 r0/b11 **逐字节一致**。
  - 该偏差不影响 bit/CWC 的可复现性判据：布线 DB + RTL + SDC + ADC 均已按哈希绑定。

## 7. 未测边界与风险

- **薄余量**：+0.003 ns（约 0.08% 周期）只对**这一份布局布线**成立；温度/电压/同批次器件都未做 margin 验证，
  因此只能作诊断候选；生产版必须补流水（见 §3.1）。
- **无板级证据**：FTDI 不在位，0 下载；R1 的硬件行为（LAST 丢失后好帧恢复）仍只有仿真证据。
- 1176 读响应停点仍是 H2/H4（r0 的 read 九例全过，只说明 A1 侧与 bridge 模型无缺陷），本包未触碰、未猜修。
- r0 的功能证据是缩小几何 + 行为 DDR 模型；不证明满速/512 深 FIFO 下的触发概率。
- 本 bit 与 CWC **配对**（compiled 与父文件逐字节一致），若后续重跑 bitgen 必须同时重跑 CWC，不可混用。

## 8. 复测清单（交综合测试者）

- required_dimensions：`engineering`、`system`（功能维度沿用 r0，但必须**重新绑定 r1 manifest**）
- required_checks：
  1. 哈希自洽：`r1/td/a1_board.bit`、`a1_board_inst.bid`、`a1_board.cwc`、`cw/compiled.bit`、`cw/compiled.cwc`
     与 `CANDIDATE-MANIFEST-b12-r1-last-r1.json` / `r1/artifact-hashes.txt` 一致；`compiled.bit == a1_board.bit`、`compiled.cwc == a1_board.cwc`。
  2. 输入未变：`r0/changed-src/**` 9 个哈希 = r0 manifest（RTL 0 改动）；`p2_board.sdc`、`board_p2.adc` = b11 r0 哈希。
  3. bitgen 仅 1 次：`r1/td/bitgen_console_b12_r1.log` 中 1 条 `bitgen -bit`；CWC 仅 1 次：`cwc_console_b12_r1.log` 中 1 条 `setup_debugger`；
     两日志无 `P2_BITGEN_ERROR` / `P2_CWC_EXPORT_ERROR`。
  4. final STA：`candidate_timing.rpt` 的 `SWNS: 0.003` / `HWNS: 0.020` / `Period Check WNS: 2.200` / `0 Viol Endpoints`，
     与本 result 和 r0 `routed_*` 报告一致。
  5. 板级：`r1/board/ftdi-preflight.log` 中 `FTDI_PRESENT=0`、`DOWNLOADS=0`、`COM8_OPENED=0`；不得据此宣称板级通过。
  6. 口径复核：manifest 的 `acceptance.timing_caveat == "thin_margin_+0.003"`，且 `acceptance.scope` 明示“诊断候选、非生产/非板级签核”。
- report_paths：`r1/result-r1.md`、`CANDIDATE-MANIFEST-b12-r1-last-r1.json`、`r1/artifact-hashes.txt`、
  `r1/td/candidate_timing.rpt`、`r1/td/bitgen_console_b12_r1.log`、`r1/td/cwc_console_b12_r1.log`、`r1/board/ftdi-preflight.log`
- input_status：**changed**（相对 r0：新增 bit/BID/CWC/compiled + 冻结 manifest；RTL/SDC 不变）
- reuse_decision_paths：`r0/**`（功能与布线证据，只读）、`r0/sim/indep/**`（冻结反例 TB/检查器）
- 绑定说明：r1 **没有新增功能证据**；综合测试者若要用 r0 的仿真 PASS，必须在 r1 manifest 中按哈希绑定 r0 的
  `changed-src/**` 与 `r0/sim/**`，不得把 r0 的 PASS 直接当作 r1 输入的 PASS。

## 9. 恢复/后续文本

> 诊断候选 `T10.b12-r1-last` r1 已冻结：bit `9180DB8C…`、BID `96D8A5DF…`、CWC `FFB88419…`（compiled 与父文件逐字节一致），
> `timing_caveat=thin_margin_+0.003`（SWNS +0.003 / HWNS +0.020 / Period +2.200 / 0 违例），板级 blocked（FTDI 0403:6042 不在位，0 下载）。
> 后续：① 生产版补流水把 WNS 拉回 ≥ +0.05；② FTDI 到位时用**同一 bit** 做 1 次 SRAM 下载 + COM8 150 s 的 v4/frame 验证；③ 不得混用其它 bit 的 CWC。
