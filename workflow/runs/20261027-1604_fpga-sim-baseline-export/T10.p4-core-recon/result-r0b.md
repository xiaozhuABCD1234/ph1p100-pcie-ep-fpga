# T10.p4-core-recon · round 0 attempt2 结果（状态：**ready_for_test**）

- task_id：`T10.p4-core-recon`；run：`20261027-1604_fpga-sim-baseline-export`；round0 attempt2（实际修复轮次仍为 0）
- 候选：`P4.core-recon-r0`，**RTL 未改动**：14 份 `rtl/*.v` 的 SHA256 与 `manifest-r0.json` 首检/尾检各一次全部相等（0 mismatch）
- 冻结 manifest：`manifest-r0b.json`（本 revision 全量 SHA256；声明 RTL 与 `manifest-r0.json` 全等）
- 依据：`planner-decision-r0b.md`、`plan.md` §4.3/§4.5、`fpga-design-guide.md` §3.1
- 边界：本机只做 RTL 仿真/编译/参考模型；G2（综合/STA）、G3（位流/上板）、G4（长稳/双路）`not_run`。结论仅"仿真内等价"，不代表真实 PCIe、最终时序或双路实时。

## 1. 本次实际执行

入口：`sim/run_sim_r0b.ps1`（单次调用：`vlib` → `vlog` 14 RTL + 1 TB → 4 次 `vsim -c` → 参考模型比对；FAIL 回非零）。编译库/transcript 在 `%TEMP%\fpga_t10_p4core_r0b_<时间戳>`，交付目录只留文本。

**驱动基线**：`tb/tb_p4_equiv_golden.v` = r2 `tb_img_algo_equiv_p4.v`（SHA256 `1350d75ce690477bfc7dace7d10160018b293d935917281f7c25b3026b8a639f`，逐字节相同）**原样移植**，仅增加一个只读观测抽头（`dump_tok`：把已记录的 token 写文本），帧控制/激励/3 DUT 同拍序列/LFSR ready 一行未改。契约：W=64、H=48、4px/beat、768 beat/帧、帧 0/1 good、帧 2 在第 200 beat 有意 `s_abort` 且无 `eof`。

| 运行 | 模式 | `CHECK_REF_NEW` | TB 判定 | `EQUIV_COUNTS`(dut0/dut1/dut2) | cyc |
|---|---|---|---|---|---|
| `tokens_sm0_t0` | SEEDMODE=0（LFSR 75% ready） | **PASS** | **PASS** | 1720/1703/1720 ×3 全等 | 11583 |
| `tokens_sm1_t0` | SEEDMODE=1（另一 LFSR 组） | **PASS** | **PASS** | 同上 | 11863 |
| `tokens_sm2_t0` | SEEDMODE=2（**常 ready**） | **PASS** | **PASS** | 同上 | 11031 |
| `tokens_sm0_t1` | SEEDMODE=0 复跑（E4） | **PASS** | **PASS** | 同上 | 11583 |

编译：`vlog` **0 error**；唯一 warning 为 `vlog-2083`（`algo_rowwin3_p4.v:19` 既有格式 CR），属冻结源原状，未改动。

## 2. 逐条判据（plan §4.3 修正版）

**F1 灰度逐像素 / F2 高斯逐像素（G1）**：参考模型 `model/compare_p4b.py` 从同一 synthetic 激励独立重算 Bayer 去马赛克 → Y8 → 3×3 高斯。

| 模式 | DUT | y8 compared/mismatch | gau compared/mismatch |
|---|---|---|---|
| sm0 | base / candidate | 6144 / **0** | 6144 / **0** |
| sm1 | base / candidate | 6144 / **0** | 6144 / **0** |
| sm2 | base / candidate | 6144 / **0** | 6144 / **0** |

`compared == expected_pixels(=64×48×2=6144)`、`mismatch == 0`，标记（sof/eol/eof）不一致数 0。

**F3 token/帧标记（修正后语义）**：每个 DUT/流在 3 种模式下均满足
- good 帧内 abort 标记 = **0**；
- 有意 abort 帧恰好产生 **1** 个 abort 标记（`abort_markers_total=1`），位置与 base 参考完全一致（见 F5a 全序列相等）；
- 有意 abort 帧的部分像素是参考帧 2 的前缀：y8 183 token（732 像素）比较 mismatch=0，gau 166 token（664 像素）mismatch=0；`sof/eol/eof` 计数与契约一致（每 good 帧 1 sof / 48 eol / 1 eof）。

**F4 正常流**：两 good 帧全帧输出（每帧 768 token），token 顺序与参考模型逐项一致（上表 6144/6144 覆盖）。

**F5 反压（三分量，修正后）**
- (a) 同 ready 模式 base vs candidate **全序列相等**：y8 1720 token / gau 1703 token，`mismatch=0`（sm0/sm1/sm2 各一次）。
- (b) 同模式内无丢/重/乱序：DUT token 计数 = 1536 good + 部分帧 + 1 marker（y8 1720、gau 1703），与参考模型计数逐项相等；好帧像素精确（F1/F2）。
- (c) 跨 ready 模式：base 差异 = candidate 差异 = **0**（y8/gau 各 3 组模式对），候选未大于 base。
- 说明：r2 TB 已明示 frozen HE/高斯对 stall 模式敏感；本候选在三种模式下未观察到跨模式差异。

**E1** 编译展开 0 error。**E2** 关键路径无 X/Z：TB 用 `!==` 逐 token 比较（X 会判不等）且全部 dump 词法解析为合法 hex，未出现 X/Z。**E3** 闭包完整：14 RTL + TB + 模型 + 入口脚本，全部 SHA 记录；入口从干净临时 `work/` 一次复跑成功。**E4** 两次运行摘要一致：sm0 两次 dump 的 y8/gau 序列逐 token 相同（1720/1703 compared，0 mismatch）。**E5** 综合/STA/资源/CDC = `not_applicable`（本机禁 TD；不引用 r2/r3 时序结论）。

**S1** 缩尺参数：W=64、H=48、phase=0(RGGB)、MAX_WORDS=512、frame=768 beat、4px/beat、clk 5.333ns（仅仿真比例），与生产参数区分，已写入 `manifest-r0b.json`。
**S2** 未实现协议责任：44B A1U1 头、页尾零填充/写掩码、BAR `0x130..0x13C`/`CTRL[9..11]`、DDR ×4 重映射、A 路/双路、ACK 后身份释放链——均未实现，本轮不声称。
**S3** 候选来源可追溯：每份 RTL 的原路径 + SHA + 是否漂移源见 `manifest-r0b.json`（`bayer_raw10_demosaic4_p4`、`img_algo_parallel_top_p4` 为漂移源，SHA `a5c40734…`/`e420685c…`，**非** r2 字节）。

## 3. 判据独立性

- **差分判据（主）**：base = r2 冻结字节 `img_algo_parallel_top`(`7f1e0544…`) + `bayer_raw10_demosaic4`(`138e7124…`)，与候选在同 stimulus、同 ready 模式下 token 全序列相等（含 marker/sof/eol/eof/abort）。该判据不含本人重写语义。
- **参考模型（金标准）**：`compare_p4.py` 语义重算（Bayer 去马赛克含 CFA 奇偶钳位、Y=(77R+150G+29B+128)>>8、高斯 3×3 权重 [1 2 1;2 4 2;1 2 1] 与 `(sum+8)>>4`、高斯边界为 plain replicate）。
- **变异负对照**：对候选 y8 token 200 的 lane1 注入 +1 LSB → 同一比较器报 `mismatch=1`、`detected=1`。
- **残余风险（如实登记）**：参考模型由本任务按冻结模块文档语义重算；若模型与规格同错，差分判据无法发现。该风险由"r2 冻结基座逐 token 相等"与"变异负对照"共同限制，但**未**被完全排除。

## 4. 模型/激励边界

- 激励 **synthetic**（非相机数据）：`px(b,k)=(37b+211k+13*(b>>5)+5)&0x3FF`，b 为跨帧全局 beat 序号。
- 缩尺几何；无相机时序、无 DDR/PCIe 模型参与（本包只到 P4 算法核心输出）。
- 帧 2 为**有意** abort 帧（r2 契约），其部分输出只作前缀一致性检查，不计入 6144 像素金标准。

## 5. 产物

- 新：`tb/tb_p4_equiv_golden.v`、`model/compare_p4b.py`、`sim/run_sim_r0b.ps1`、
  `evidence/{pixel-compare,abort-semantics,f5-ready-pattern,e4-repro,negative-mutation}.json`、
  `sim/logs/r0b_{vlib,compile}.log`、`sim/logs/r0b_sim_tokens_sm{0,1,2}_t{0,1}.log`、
  `sim/logs/tokens_sm{0,1,2}_t{0}.txt`、`sim/logs/tokens_sm0_t1.txt`、`result-r0b.md`、`manifest-r0b.json`
- 保留原字节（未改）：`manifest-r0.json`、`result-r0.md`、`tb/tb_p4_core_golden.v`、`model/compare_p4.py`、`sim/run_sim.ps1`、`sim/logs/*bp0*`、`evidence/closure-sha.txt`、`rtl/*`（14 份）

## 6. 合规

只写本任务工作根；未修改 `handoff/**`、`rtl/`（工作根内也未改）、其他 run、`D:\fpga\ph1p100\**`、`workflow/tasks.json`；无 `git commit/push`；无批量删除；无 TD/布线/STA/bitgen/CWC/COM/JTAG/下载/Flash。
