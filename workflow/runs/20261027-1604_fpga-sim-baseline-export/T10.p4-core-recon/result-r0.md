# T10.p4-core-recon · round 0 结果（状态：**blocked**，未达验收门槛）

- task_id：`T10.p4-core-recon`；run：`20261027-1604_fpga-sim-baseline-export`；round：0
- 候选：`P4.core-recon-r0`（新候选，**不**沿用 r2 PASS）
- 工作根（唯一可写）：`D:\fpga\repos\ph1p100-pcie-ep-fpga\workflow\runs\20261027-1604_fpga-sim-baseline-export\T10.p4-core-recon\`
- 冻结 manifest：同目录 `manifest-r0.json`（全量 SHA256）
- 本机边界：只做 RTL 仿真/编译/参考模型/静态核对；**无** TD 综合、布局布线、STA、bitgen、CWC、COM/JTAG、下载、Flash。G2/G3/G4 = `not_run`。
- 结论口径：以下仅为仿真内结果，**不**代表真实 PCIe、最终时序或双路实时。

## 1. 缺失源查找（有界，负结果）

搜索根：`D:\fpga\repos\ph1p100-pcie-ep-fpga`、`D:\fpga\ph1p100`、`D:\fpga\archive`；命令 `dir /s /b <root>\<name>` + `Get-FileHash -Algorithm SHA256`。

| 文件 | 期望（r2 manifest） | 全部命中 | 判定 |
|---|---|---|---|
| `bayer_raw10_demosaic4_p4.v` | `4e108dd86ac84465a52e21b8db3c0102238fc35e7dc152432efd5052cecea339` | 3 处，均为 `a5c40734…047bb`（= r3 绑定/漂移值） | **无精确副本** |
| `img_algo_parallel_top_p4.v` | `1cb8262a598f94fb2837152249edaa130c2945592f7d2f4020821e4266fc400f` | 3 处，均为 `e420685c…ea33c`（= r3 绑定/漂移值） | **无精确副本** |

`D:\fpga\archive` 下两份均 NOHIT。故按 `fpga-design-guide.md` §2.1 规则 **分支 2** 建立新候选；漂移副本**不**被称作 r2。

## 2. 候选闭包（14 份 RTL，逐份 SHA 见 `evidence/closure-sha.txt` / `manifest-r0.json`）

| 逻辑文件 | 来源 | SHA256（前 8） | 性质 |
|---|---|---|---|
| `bayer_raw10_demosaic4_p4.v` | `handoff/…/inputs/p4/fpga/csi2/src/integrated_delivery/` | `a5c40734` | 漂移源（r3 绑定值，**非** r2 字节） |
| `img_algo_parallel_top_p4.v` | 同上 | `e420685c` | 漂移源（r3 绑定值，**非** r2 字节） |
| `algo_rowwin3_p4.v` | `inputs/p4/workflow/runs/20261026-2138_…/INT.P4/r2-timing-experiment/` | `f3f345ed` | r2 时序实验副本，SHA 匹配 |
| `gray8_gaussian3x3_stream_p4.v` | 同上 | `158aae4d` | r2 时序实验副本，SHA 匹配 |
| `algo_obuf.v` | `inputs/p4/fpga/csi2/src/img/` | `07404282` | r2 冻结 img 源，SHA 匹配 |
| `algo_rowwin3.v` | 同上 | `46a6ceb1` | r2 冻结 img 源 |
| `algo_rowwin_reader.v` | 同上 | `bbd3f9d3` | r2 冻结 img 源 |
| `bayer_raw10_demosaic4.v` | 同上 | `138e7124` | r2 冻结 img 源（差分对照 DUT 的基座） |
| `gray8_gaussian3x3_frame.v` | 同上 | `d5b14c59` | r2 冻结 img 源 |
| `gray8_gaussian3x3_stream.v` | 同上 | `c358174f` | r2 冻结 img 源 |
| `gray8_he_cdfmin_frame.v` | 同上 | `df84b8a4` | r2 冻结 img 源 |
| `img_algo_parallel_top.v` | 同上 | `7f1e0544` | r2 冻结 img 源（差分对照 DUT，r2 G1 功能 PASS 的同一字节） |
| `img_algo_top_g2.v` | 同上 | `5ecc66d9` | r2 冻结 img 源 |
| `rgb8_gray_stream.v` | 同上 | `1a64fa21` | r2 冻结 img 源 |

已知风险（按指南显式继承）：该组合 = 漂移 `bayer/top` + r3 派生的 `rowwin/gaussian`，**必须**逐项复测；r3 “语义 FAIL” 结论不得引用为已排除。

## 3. 本轮实际执行与结果

入口：`sim/run_sim.ps1`（一次调用：`vlib` → `vlog` 14 RTL + 1 TB → `vsim -c` 两种 ready 模式 → Python 参考模型比对；失败回非零）。编译/仿真在 `%TEMP%` 下进行，交付目录不含 `work/`、`*.wlf`、`*.qdb`。

| 步骤 | 命令/工具 | 结果 |
|---|---|---|
| 编译 | `vlog -quiet -work work <14 rtl + tb>`（ModelSim ASE 18.1 / vlog 10.5b） | **0 error**；1 条 warning `vlog-2083`（`algo_rowwin3_p4.v:19` 源码中的孤立 CR，非功能） |
| 仿真 BP=0 | `vsim -c -do "run -all; quit -f" tb_p4_core_golden +BP=0` | **TB FAIL**：`y8=782 gau=768 good_b=1 good_p=1 abt_b=1 abt_p=1 hepub=0 gauabt=1 xerr=0 abt_ev=4 cyc=2217 diff=5` |
| 仿真 BP=1 | 同上 `+BP=1` | `not_run`（脚本在 BP=0 失败后按设计退出，未继续） |
| 参考模型比对 | `python model/compare_p4.py` | `not_run`（同上，未产生可比对数据） |

### 3.1 观测到的缺陷（TB 侧，非候选判定）

token dump（`sim/logs/tokens_bp0.txt`）的形态：

- y8：`sof` → 13 个数据 token → 又一个 `sof` → 767 个数据 token（其中 48 个 eol，**无 eof**）；
- 两个 abort 标记（`abt_ev=4` = 2 次 abort × y8/gau 两路），`sim_bp0.log` 记录 `NOTE p4 abort marker cycle=271 / 274`；
- 冻结基座 `img_algo_parallel_top`（r2 同一字节）给出**完全相同**的 `good=1 / abort=1`，且与候选 `diff=5`（token 计数不等 → 元素比较无法进行）。

**判读**：基线（r2 已验收字节）与本候选同时 abort ⇒ 现象指向**本 TB 的帧控制契约**（`s_sof/s_eol/s_eof` 与 DUT 期望的相位），**不能**据此判候选功能失败，也**不能**据此判候选通过。故本轮不给 F1–F5 的 PASS/FAIL 结论，记 `not_run`。

### 3.2 门槛逐项

| 项 | 结果 |
|---|---|
| F1 灰度逐像素 `compared==expected_pixels` 且 `mismatch==0` | `not_run`（无有效帧数据） |
| F2 高斯逐像素 | `not_run` |
| F3 token/帧标记（`abort==0`） | **fail**（观测到 2 次 abort 标记、缺失 eof） |
| F4 正常流 | `fail`（BP=0 下帧即被中止） |
| F5 反压 | `not_run` |
| E1 编译展开 0 error | `pass`（1 条 CR/LF warning，来源文件既有格式） |
| E2 关键路径 0 X | `pass`（已产出 token 的 `xerr=0`），覆盖面不完整 |
| E3 闭包 SHA 完整、入口可复跑 | `pass`（14 份 RTL 与期望 SHA 全部一致；入口可一次复跑） |
| E4 两次运行摘要一致 | `not_run`（未达可比较状态） |
| E5 综合/STA/资源/CDC | `not_applicable`（本机禁 TD） |
| S1/S2/S3 | 部分：参数与来源已写入本文件/manifest；未实现协议清单见 §4 |

## 4. 未实现协议责任（不冒充实现）

1. 44B A1U1 帧头（camera/session/seq/slot/epoch 身份与四 CRC）——未实现。
2. 页尾 96..4095B 零填充/写掩码——未证明。
3. BAR `0x130..0x13C`、`CTRL[9..11]`、`a_enable`——未实现（本任务不涉及）。
4. DDR 地址 ×4 重映射——仅 P2 仿真模型；本轮不涉及。
5. A 路与双路——不在本 run。
6. ACK 后身份释放链、错误 ACK/session/epoch/slot 负例——不在本轮。

## 5. 模型/激励边界

- 激励为 **synthetic**：`px(b,k) = (37b + 211k + 13*(b>>5) + 5) & 0x3FF`，`W=64 H=48 phase=0(RGGB)`，2 帧 good，无 abort 帧；4 像素/beat，lane0 = bits[9:0]。
- 缩尺：`W=64`、`H=48`、`MAX_WORDS=512`（生产几何不同）。
- 参考模型 `model/compare_p4.py` 为独立重算（Bayer 去马赛克 → Y8 → 3×3 高斯），并内置 1-LSB 变异负对照；本轮**未执行**。
- 差分判据：以 r2 冻结字节的 `img_algo_parallel_top`（`7f1e0544…`）为第二意见，与候选同 stimulus/同 ready 逐 token 比较。

## 6. 阻塞与最小下一步

- 阻塞类别：`NO_PROGRESS`（帧控制契约未定位；同时已用满/超出本次派发 30 次工具调用默认预算，超出部分=冻结本文件与 manifest 的收尾动作）。
- 缺项：可复现的帧控制驱动（`s_sof/s_eol/s_eof` 与本候选 DUT 的对齐），导致 F1/F2/F4/F5 无有效数据。
- 恢复路径（不改本轮结论、不引用旧 PASS）：
  1. 直接复用 r2 已跑通的等价 TB `handoff/…/inputs/p4/fpga/csi2/src/integrated_delivery/tb_img_algo_equiv_p4.v`（SHA `1350d75c…`，r2 `CHECK_REF_NEW PASS`）作为驱动/判据基线，先跑通 base-vs-candidate 差分，再接本 `compare_p4.py` 做逐像素金标准比对；
  2. 若沿用本 TB，先隔离差异：单 DUT + 仅 base 配置复跑同一 stimulus；再逐项对齐（`s_valid` 门控、双 DUT 同步接受、`he_ready` 常 1、帧数 2 vs 2 good+1 abort）；
  3. 定位后重跑 `sim/run_sim.ps1`（含 BP=1），再冻结新 manifest。
- 回退：若定位为“必须换源组合”，按 `plan.md` §4.4 回原规划重新冻结，开发不自行换组合。

## 7. 只读与合规

- 未修改 `handoff/**`、`rtl/`、`al_ip/`、`constraints/`、`tools/`、`workspace/**`、其他 run、`D:\fpga\ph1p100\**`、`workflow/tasks.json`；未 `git commit/push`；未批量删除；未启动任何 TD/板级动作。
- 全部新产物仅落在本任务工作根。
