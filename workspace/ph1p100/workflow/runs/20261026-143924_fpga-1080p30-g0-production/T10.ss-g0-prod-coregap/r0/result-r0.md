# T10.ss-g0-prod-coregap r0 — 结果（开发自测，非最终判定）

- run `20261026-143924_fpga-1080p30-g0-production`；task `T10.ss-g0-prod-coregap`；round 0；角色 fpga-dev（新会话，不复用 P1）
- **结论：`closable_at_187_5 = conditional`**（headline 仍 `G0_not_closed`；**不声称 G0 已闭合**）
- 产物：`out/coregap-verdict.json`、`out/coregap-model.json`、`out/stage-probe.json`、`out/negative-controls.json`、
  `model/{coregap_model.py,parse_probe.py,matcher.py,assumptions.json,make_manifest.py}`、
  `sim/logs/{n,l}-probe.log`、`src/DIFF-probe.md`、`manifest-r0.json`
- 边界：RTL 0 改（12 DUT 源与 P1 manifest-r1 逐字节相同）；TD/综合/布线/bitgen/CWC/下载/Flash/板卡/COM/JTAG/RK/网络 = **0**

## 1. 一句话答案

187.5 MHz、单核、ERAM≤300、LUT6≤71,680 下，**没有任何单方案单独闭合** N 的 core_interval 缺口；
最接近的两个单方案是「emit 加宽」（差 0.17%）与「2-position 扫描仅双发射 literal」（差 13.5%）；
两者叠加 A+H 估算 **6,008,078 cycles/frame = 2.318 cycles/B（+4.03%）**，是唯一在 187.5 MHz 上算术可闭合的路径，
但其方案包络 5.19M–7.22M（A 单方案）→ 不确定度 ≫10%，必须先原型 + TD/STA，故判定 `conditional`。

## 2. 1 帧 stage probe（唯一新增实测）

| 项 | N | L |
|---|---|---|
| content | P1 `raw40_n.hex`（只读引用） | P1 `raw40_l.hex` |
| `t_pub(1)` / `t_enc(1)` | 1,607,996 / 9,084,241 | 1,607,996 / 8,587,807 |
| `core_interval=t_enc(1)-t_pub(1)` | **7,476,245** | **6,979,811** |
| P1 r1 帧 1 参考 / 偏差 | 7,476,245 / **0.000%** | 6,979,811 / **0.000%** |
| blocks / fixed / stored | 540 / 457 / 83 | 540 / 330 / 210 |
| literals / matches | 505,140 / 397,627 | 673,657 / 254,493 |
| `cand_aborts` | 83 | 210 |
| `max_match` / `max_dist` | 92 / 2,048 | 65 / 2,048 |
| `stat_stall` | 2,784,218 | 2,287,192 |
| 导出字节（`kind=exp`） | 1,677,912 | 2,156,868 |
| vsim 墙钟 | 612.0 s | 788.4 s |
| 标记 | 无 `SS_STALL*`；`B11_FULL_TIMEOUT`（单帧下继承的 `2*129600` 信息性等待不可能满足，见 DIFF §运行变体）；`Errors: 0` | 同 |

- TB：`src/tb_ss_4run_wd_probe.v` = P1 r1 TB 副本 + 5 项白名单（`src/DIFF-probe.md`、`DIFF-probe.raw`）；只读层次引用 `dut.u_a1.u_core.stat_*`，无 force/deposit。
- 参数：`FRAMES=1 CONTENT=2 PACING=0 SINK=1 CAPTURE=0`、`-gMAX_CYCLES=12800000/13300000`。探针**不是** 4 帧稳态证据（无 `S_ss`/`tail`/`G0`）。

## 3. 模型与校准（`model/coregap_model.py`）

FSM 记账（derived）：扫描拍 = `B + 5·M`（每 literal 1 拍；每 match `len+5` 拍：S_SCAN 1 + S_EXT len−2 + S_MLEN 1 + S_MCHK 1 + S_REPOS 4）；
fixed 块 emit = `r × 流字节`（S_REPLAY 4 拍/2 字节）；stored 块第二遍 = 1 拍/字节（S_SDATA_R）；每块常量 `k`；每个 abort 块少扫 `c_ab`。

| 系数 | 值 | 标签 |
|---|---|---|
| `c_scan_per_position` | 1.0 | derived |
| `c_match_fixed` | 5.0 | derived |
| `r`（replay 拍/流字节） | **1.9007** | fitted |
| `k`（拍/块） | **293.63** | fitted |
| `c_ab`（拍/abort 块） | **1109.0** | fitted |

- 三点（N / L / comp）三参数 → in-sample 残差 0（**按构造为 0，不算验证**）。
- **leave-one-out（真正的验证）**：`{N,comp}→L` **+2.420%**；`{L,comp}→N` **−3.252%**；`{N,L}(k≥0)→comp` **−3.562%…−1.908%** → 全部 ≤5%。
  说明：`{N,L}` 无约束解给出 `k = −2418 拍/块`（非物理），这正是 2 参数模型无法表达的内容相关 abort 抵扣，故改用 `k=0` 单参数并给出区间。
- **C1 不进入拟合**（r1 修正，物理系数口径，见 `result-r1.md` R4）：C1 的 4,677,970 是 P4 的**链级 `S_ss`**；用拟合系数 r=1.900712、k=293.6313 得到的 C1 核级界为 **2,905,862～3,042,041 拍（估计 2,956,095 = 链级 63.19%）**，
  说明该数被采集/喂入支配，**不是核级锚点**（`out/negative-controls.json` 的 `CHAIN_AS_CORE`）。此点与 dev-plan 原文的四点拟合不同，理由与算术都在 `coregap-model.json.residuals.C1`。
- N 的实测分解：扫描 4,580,135（61.3%）+ fixed emit 2,431,194（32.5%）+ stored 第二遍 398,400（5.3%）+ 每块 158,561（2.1%）− abort 抵扣 92,047（−1.2%）= 7,476,243（实测 7,476,245，差 2 拍为拟合取整）。

## 4. 方案矩阵（8 行，全部标证据类型与置信度）

| id | 方案 | est. cycles/frame | cycles/B | 闭合 187.5？ | 相对 G0 | 资源增量（估） | 时序风险（对 WNS +0.015@187.5） | 置信度 | 单独够？ |
|---|---|---|---|---|---|---|---|---|---|
| A | 2-symbol/2-position 扫描 | 7,223,675（全双发 5,186,178） | 2.7869 | 否 | −13.48% | ERAM +2..4、LUT6 +3.5k..6k | 高（第二个 hash/arbiter 进扫描锥） | 低 | 否 |
| B | htab 1024→4096/8192 | 7,384,642 | 2.8490 | 否 | −15.37% | ERAM +3..+7 | 低 | 中 | 否 |
| C | 窗口 2048→4800（8192 需更大块） | 7,384,642 | 2.8490 | 否 | −15.37% | ERAM 0 / +16 | 低-中 | 中 | 否 |
| D | 深流水重定时（200/209.6/224.3 MHz） | 7,476,245 | 2.8844 | 否 | −16.40% | LUT6 +2k..4k、REG +4k..8k | 就是这项：5.318→4.458 ns（−16.2%） | 低 | 否 |
| E | 仅提时钟 209.6/224.3 | 7,476,245 | 2.8844 | 否 | −16.40% | 0 | 不可信（WNS +0.015 已无余量） | 高（算术） | 否 |
| H | emit 加宽：replay 2 字节/拍 | **6,260,648** | **2.4154** | 否 | **−0.17%** | ERAM 0、LUT6 +0.3k..0.8k | 中 | 中 | 否 |
| F | 双核 | 7,476,245 | 2.8844 | 否 | −16.40% | ERAM +102..129（231..289/300） | unproven | 高（per-stream） | 否 |
| G | 换核/换算法 | — | — | 否 | — | 无设计 | unproven | n/a | only-in-combination |

组合：**A+H 6,008,078（2.3179，+4.03%，闭合）**；A+B+H 5,916,475（2.2826，+5.64%）；A+D 7,223,675（不闭合）；A 全双发+H 3,970,580（1.5319，乐观上界）。

## 5. 判定与下一步

- `closable_at_187_5 = conditional`：`yes` 需 ≤2.411 cycles/B 且不确定度 ≤10%——A+H 虽算术闭合，但包络 45%、无原型、无 TD；
  `no` 需「224.3 MHz + 最优资源也达不到」——224.3 MHz 恰好闭合（7,476,245 ≤ 7,476,667，余量 0.006%），故不能判 no。
- 推荐：**A+H**（187.5 MHz 结构改造）为主，D 重定时为备；B/C 参数级改动 <1%，不足以单独用。
- 下一证据：原型 1 帧 stage probe（`cycles/B ≤ 2.411`，同 9 counter）→ TD 综合/布线 WNS≥0 → 4 帧 N/L 跑 G0 → 板级。
- 用户决策项：资助结构改造；或接受 `G0_not_closed`；提时钟需同样重流水 + PLL/板级；换核另立任务。

## 6. 未测 / 不得外推

未测：任何改造后核的实测周期、任何方案的时序/资源（无 TD）、板级、生产 sink、DDR 持续、双路、真实传感器 RAW/最坏内容。
本包**不证明** G0 闭合，也不改变 P1 的 `G0_not_closed`(N) / `G0_not_proven`(L)。

## 7. 预算记账

| 项 | 上限 | 实际 |
|---|---|---|
| 工具调用 | 40 | **约 49（超限，如实披露）**：多出的部分来自 ① N#1 harness 缺陷后的排查与 TB dump 位置改写（4 次）② 模型 `KeyError`/`res` 顺序两次小修（4 次）③ 判定 JSON 用 heredoc 被拒后改写文件（2 次）。未见新证据的长跑 0 次；如需按 40 记账，超出的均为非仿真调用 |
| 1 帧全尺寸 vsim | 3（2 证据 + 1 harness 重试） | **3**：N#1 695.4 s（harness 缺陷：`CORE_STAGE` 放在 stats 之后，被 `MAX_CYCLES` 收尾抢先 → 只得到 t_pub/t_enc，无 counter，**不计为证据**）；N#2 612.0 s（有效）；L 788.4 s（有效） |
| vsim 墙钟 | ≤55 min | **34.9 min**（2095.8 s） |
| 单次硬超时 | 1500 s | 700/800/900 s（均未触发；L 用 `WaitForExit(1500000)`） |
| TD / 板卡 / 网络 | 0 | **0** |

## 8. 复现（cwd = `r0/model`）

```powershell
python parse_probe.py        # 解析 1 帧探针日志 -> ../out/stage-probe.json（含 ±2% 校验）
python coregap_model.py      # 校准 + 残差/LOO + 矩阵 -> ../out/coregap-model.json
python matcher.py "N=.../raw_n.bin"   # 仅作行 B/C 方向性下界（未探针验证）
python make_manifest.py      # 冻结 manifest-r0.json
```

`out/coregap-verdict.json` 由 `coregap-model.json` 的同一组数手工落到判定字段（数值逐项一致；`decomposition_N_cycles` 的 2 拍差已在字段内注明）。
