# T10.a1-frame-top — round1 dev result (PASS, G0/G1; F1–F5 addressed)

- task_id: `T10.a1-frame-top` (P3)｜round: **r1**（第 1 轮实际修复）
- 判定：**PASS**（20/20 用例；所有整帧逐样本 0 mismatch；坏帧 0 commit/0 eop；0 端口/越界警告）
- 日期：2026-10-20｜run：`20261020-0209_singleA_aplus_closedloop`
- 候选：新 manifest `C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道\workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.a1-frame-top\CANDIDATE-MANIFEST.json`（新候选，不复用 r0 manifest）
- 性质：**synthetic**；声明 RGGB phase-0；未上板、未接 PCIe/RK、未下载/Flash、无 TD/G2

## 1. r0 必改项处置（逐条）

| 项 | 处置 | 证据 |
|---|---|---|
| **F1** abort 时末字 pending 仍置 `out_last` | `out_last = svalid && slast && !killed`；新增 mode 7：先跑干净帧，再在末字 pending 时 abort，然后释放并跑第三帧 | `abort_last`：`pending_last=1`、`last_after_abort=0`、`last_after_release=0`、`commit_after_abort=0`、`commit_after_release=0`，p3 恢复帧 commit 且解码 0 mismatch |
| **F2** 9 个 core `stat_*` 悬空 | 全部连接到 frame-top 内部观测 wire（未改 P2 核） | 全 20 例 `vsim-3017/3722` 计数 **0**；`vlog` 0/0、`vlog -lint` 0/0 |
| **F3** `smem` 越界/ time-0 X 索引 | 去掉组合阵列读，改**寄存读 + 2 级预取**（rd_issue/rd_en/dq_r），索引夹紧 | 全 20 例 `vsim-8233` 计数 **0**；1080p 复跑 0 越界 |
| **F4** 非法几何/配置未测 | 新增 `W%4!=0`（18x4）、`H<2`（20x1）、`2*stride>4800`（1924x4）、`pred_en=1&&prep_en=0`（20x5）；`I_DEAD` 策略=**仅复位恢复** | mode 8 两轮（复位前后）均 abort、0 commit、busy=0；mode 9 非法帧 abort→复位→合法帧 commit 且解码 0 mismatch |
| **F5** 1080p 交叉覆盖/不可压缩 | 新增 1080p prep0/pred0、1080p prep1/pred0、1080p 全不可压缩、1920x16 mixed fixed→stored | 见下表；`f1080p_rand` 流长 **2,594,706 B** = 冻结最坏上界（540 块 × +5 B + 6 B） |
| **F6** 吞吐口径 | 新增连续 2 帧 1080p 与全不可压缩 1080p 实测 | `multi1080p` 2 帧合计 9,355,687 cycles；不把 97.2 当保证值 |
| 接口风险：配置未在 sof 锁存 | 新增 `prep_r/pred_r`，sof 时锁存，输入/编码全用锁存值 | 全用例通过；模式 9 验证 prep/pred 交叉 |
| 提交后第二帧死锁（新发现） | P2 核末块后 `enc_busy` 不复位（P2 单流未暴露）；在帧 top 提交后发 1 拍 `core_flush`（即 core abort）清核，**未改 P2 核** | `multi1080p` 第 2 帧、`abort_last` 第 3 帧均 commit；P2 核文件未变（manifest 记录 hash） |

## 2. 整帧结果（DUT 输出 → zlib 1.2.13 + 独立严格解析器 → Bayer 逆变换）

| case | W x H | mode | prep/pred | raw B | stream B | ratio | exp % | cycles | MB/s @187.5 | >=77.76 | >=97.2 |
|---|---|---|---|---:|---:|---:|---:|---:|---:|---|---|
| f1080p_p1d1 | 1920x1080 | 0 | 1/1 | 2592000 | 81707 | 31.723 | -96.8477 | 4677841 | 103.89 | True | True |
| f1080p_p1d0 | 1920x1080 | 0 | 1/0 | 2592000 | 2566969 | 1.010 | -0.9657 | 4807468 | 101.09 | True | True |
| f1080p_p0 | 1920x1080 | 0 | 0/0 | 2592000 | 2587584 | 1.002 | -0.1704 | 4719302 | 102.98 | True | True |
| f1080p_rand | 1920x1080 | 0 | 1/1 | 2592000 | 2594706 | 0.999 | 0.1044 | 4678532 | 103.88 | True | True |
| odd20x5_p1d1 | 20x5 | 0 | 1/1 | 125 | 107 | 1.168 | -14.4000 | 532 | 44.06 | False | False |
| odd20x5_p1d0 | 20x5 | 0 | 1/0 | 125 | 136 | 0.919 | 8.8000 | 511 | 45.87 | False | False |
| bypass12x6 | 12x6 | 0 | 0/0 | 90 | 106 | 0.849 | 17.7778 | 371 | 45.49 | False | False |
| rand1920x16 | 1920x16 | 0 | 1/1 | 38400 | 38446 | 0.999 | 0.1198 | 80999 | 88.89 | True | False |
| mixed1920x16 | 1920x16 | 0 | 1/1 | 38400 | 19827 | 1.937 | -48.3672 | 80984 | 88.91 | True | False |
| multi1080p | 1920x1080 | 6 | 1/1 | 5184000 | 81707 | - | - | 9355687 | 103.89 | True | True |
| abort_recover | 20x5 | 1 | 1/1 | 125 | 98 | 1.276 | -21.6000 | - | - | None | None |
| reset_recover | 20x5 | 2 | 1/1 | 125 | 98 | 1.276 | -21.6000 | - | - | None | None |
| proto_recover | 20x5 | 3 | 1/1 | 125 | 98 | 1.276 | -21.6000 | - | - | None | None |
| bp20x5 | 20x5 | 5 | 1/1 | 125 | 107 | 1.168 | -14.4000 | 532 | 44.06 | False | False |
| stall_abort | 1920x16 | 4 | 1/1 | 38400 | 928 | 41.379 | -97.5833 | - | - | None | None |
| abort_last | 20x5 | 7 | 1/1 | 125 | 107 | 1.168 | -14.4000 | - | - | None | None |
| neg_wmod4 | 18x4 | 8 | 1/1 | None | None | - | - | - | - | None | None |
| neg_h1 | 20x1 | 8 | 1/1 | None | None | - | - | - | - | None | None |
| neg_oversize | 1924x4 | 8 | 1/1 | None | None | - | - | - | - | None | None |
| neg_pred0prep0 | 20x5 | 9 | 0/1 | 125 | 142 | 0.880 | 13.6000 | - | - | None | None |

- 9 条 committed 流 + 2 帧 multi + 3 条恢复流全部双解 0 mismatch、逐样本 0 mismatch、`stream_len` 精确、无尾随字节。
- 1080p 四种配置：prep1/pred1 81707 B（ratio 31.72）、prep1/pred0 2566969 B、prep0/pred0 2587584 B、全随机 2594706 B。
- 全不可压缩帧命中冻结最坏上界 2594706 B（= 2,592,000 + 540×5 + 6），逐块 stored，独立解码 0 mismatch。
- `mixed1920x16`：gradient 4 块 + 随机 4 块，stream 19827 B，覆盖 fixed→stored 混合。
- 奇数行/非 16 对齐：20x5（尾块 1 行）、12x6；A/B 与 pred 开关均 0 mismatch。
- 背压：`bp20x5` 与 `odd20x5_p1d1` 流逐字节一致（`bp_equivalence=True`）。

## 3. 吞吐（真实仿真周期，内容相关，不保证 97.2）

| 场景 | cycles | cycles/B | MB/s @187.5 | 结论 |
|---|---:|---:|---:|---|
| 1080p prep1/pred1（单帧） | 4677841 | 1.8047 | 103.89 | ≥77.76 ✅；≥97.2（本帧） |
| 1080p 连续 2 帧（聚合） | 9355687 | 1.8047 | 103.89 | 连续服务率与单帧一致 |
| 1080p prep1/pred0 | 4807468 | 1.8547 | 101.09 | ≥77.76 ✅ |
| 1080p prep0/pred0 | 4719302 | 1.8207 | 102.98 | ≥77.76 ✅ |
| 1080p 全不可压缩（stored） | 4678532 | 1.8050 | 103.88 | ≥77.76 ✅ |
| 1920x16 随机（8 块） | 80999 | 2.1093 | 88.89 | ≥77.76 ✅；<97.2（小帧固定开销） |
| 1920x16 mixed | 80984 | 2.1090 | 88.91 | ≥77.76 ✅ |

- 门槛 77.76 MB/s 对全部 1080p 配置与 1920x16 stored/mixed 成立。
- 97.2 MB/s 仅在**整帧 1080p** 上成立（101–104 MB/s）；小帧（16 行）为 88.9 MB/s，受固定开销主导。
- **不把 97.2 当作跨内容/跨几何保证值**；所有数字均为 187.5 MHz 目标时钟下的仿真周期换算，非 STA/板上实测。

## 4. 坏帧/复位/提交语义

- `abort`、帧中 `in_sof`、输出停摆后 abort：均 `frame_commit=0`、`out_last=0`、`frame_abort=1`；已发布未消费字保持稳定（`stab_err=0`）。
- 末字 pending abort（F1）：释放后该字以 `out_last=0` 被消费，`frame_commit=0`，后续新帧正常提交/解码。
- 复位：同步复位清状态；`reset_recover` 第 2 帧 commit/解码；`I_DEAD` 非法帧即使复位后再次非法输入仍 0 commit（无残留提交）。
- 提交后 1 拍 `core_flush` 清 P2 核残留 `enc_busy`，第二帧起正常；P2 核源文件未修改。

## 5. 工程/静态

- ModelSim ASE 10.5b：`vlog` **0 error/0 warning**；`vlog -lint` **0/0**。
- 全 20 例 vsim 日志：`vsim-3017/3722/8233` 合计 **0**。
- RTL 无 `initial/real/time/force/#delay/$fopen`；单时钟、同步低有效复位；无 TB 构造。
- 组合阵列读已移除（favor ERAM/时序）；P4 仍需 G2 实测。
- Verilator：本机 `0xC0000139`，**not_run**（ModelSim 等价路径）。
- TD/STA/资源/CDC/G2：**not_run**（P4；入口：将 `a1_frame_top.v`+`a1_deflate_core.v` 加入 `p4/td/**` 小顶工程）。
- 全包回归一次完成；单次仿真 ≤300 s；1080p 单帧约 35 s。

## 6. 未宣称

- 无板级、无真实 RAW/真实 Bayer 相位、无 PCIe/RK、无 G2/STA/CDC、无双路/长稳。
- 97.2 MB/s 仅对被测整帧 1080p 配置成立，不是通用保证。

## 7. 复测清单

```json
{
  "required_dimensions": ["functional", "engineering", "system"],
  "required_checks": [
    "F1: mode 7 abort_last — pending_last=1, out_last=0 after abort and after release, commit=0, next frame commits and decodes 0 mismatch",
    "F2: zero vsim-3017/3722 in all 20 case logs; vlog 0/0; vlog -lint 0/0",
    "F3: zero vsim-8233 in all 20 case logs incl. 1080p",
    "F4: neg_wmod4/neg_h1/neg_oversize/neg_pred0prep0 — abort, 0 commit, reset-only I_DEAD policy; mode 9 valid recovery",
    "F5: f1080p_p0/f1080p_p1d0/f1080p_rand/mixed1920x16 — independent double decode 0 mismatch",
    "F6: multi1080p 2-frame aggregate and full 1080p stored throughput from actual cycles; 97.2 not a guarantee",
    "manifest re-hash over the new candidate; independent verifier must not import candidate tools"
  ],
  "report_paths": [
    "C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道\workflow\runs\20261020-0209_singleA_aplus_closedloop\test-reports\T10.a1-frame-top-r1-integrated.md",
    "C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道\workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.a1-frame-top\p3\result.json",
    "C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道\workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.a1-frame-top\CANDIDATE-MANIFEST.json"
  ],
  "input_status": "synthetic only; real RAW/Bayer phase/board/export remain blocked/awaiting_hardware",
  "reuse_decision_paths": [
    "r0 manifest and r0 p3 results are INVALID for this candidate (F1-F5 changed RTL/TB/coverage)",
    "reuse only within the r1 manifest: same candidate + same generated inputs",
    "P2 core regression binding remains valid only because a1_deflate_core.v is unchanged (hash in manifest)"
  ]
}
```
