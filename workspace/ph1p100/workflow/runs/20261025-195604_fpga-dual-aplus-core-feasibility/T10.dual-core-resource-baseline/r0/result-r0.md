# T10.dual-core-resource-baseline r0 — 开发结果（round1 修复后）

- run：`20261025-195604_fpga-dual-aplus-core-feasibility`；任务：`T10.dual-core-resource-baseline`（P1）
- 角色：fpga-dev（离线）；日期：2026-10-25；轮次：round1（同任务实际修复，未改门槛/范围）
- 状态：**ready_for_test**（本文件定稿后由 `mk_manifest.py` 生成最终 `manifest-r0.json`；SHA 记录在 `logs/mk_manifest.out.txt`，生成后不再修改任何文件）
- 结论不变：单核 Routed 102+85=187/300；双核 `marginal` 146+85=231/300（余 69，23.0%），`conservative` 204+85=289/300（余 11，3.67%，conditional）；双核时序 **unproven**。
- 工具：**TD 0、综合 0、布线 0、bitgen 0、CWC 0、下载 0、板卡 0、ModelSim 0**；Python 3.11.5。

## 1. round0 FAIL 的三项修复

### F1 marginal LUT6/LUT4/headroom 少计（functional/G1）

- 根因：TD 的 `#lut6` 恒等式为 `with-luts(logic) + with-adder(ripple) + dram lut + shifter lut`，三源顶层精确成立（b6 18,743 / b10 19,695 / b11 19,882）。r0 的 marginal 只加了 logic 3,793，漏了 ripple 2,077 与 DRAM_LUT 144。
- 修复：`LUT6_total = 19,695 + 3,793 + 2,077 + 144 = 25,709`；`LUT4_equiv_upper = 51,418`；`LUT6_headroom = 45,971`；`LUT4_headroom = 77,606`。只算 logic 的 23,488/46,976 保留为新列 `LUT6_logic_only_lower`，明确标注“下界，不作拟合值”。
- 同步：`gen_baseline.py`、`dual-core-budget.csv`、`resource-baseline.md` §4/§4.1、`check_tables.py`（新增 TD 恒等式检查与 `LUT6_logic_only_lower` 校验）。marginal_2ddr 行同步为 25,709（与 marginal 同 fabric，仅 DDR 控制器数不同）。
- ERAM 231/289、headroom、`fit_300`/`fit_210_logic` 均未变；3 个负对照仍全部被拒绝。

### F2 最终 manifest 与 freeze 日志不绑定（engineering）

- 根因：round0 最后两次 `mk_manifest.py` 运行中，日志由 Tee 在 manifest 之后/之前写入，且最终 manifest 不是被 `commands.jsonl` 记录的那次运行产生。
- 修复：`mk_manifest.py` 改为**一次运行内完成**：校验交付物与 T2 6/6 PASS → 追加本次 freeze 记录到 `commands.jsonl` → 哈希 15 个 artifacts → 写 `manifest-r0.json` → 计算 manifest SHA → 写 `logs/mk_manifest.out.txt`（UTF-8，含 `sha256=<最终 manifest>`）→ 打印相同内容。日志本身从 artifacts 排除，避免自引用；`commands.jsonl` 记录本次运行（seq 10）。
- 结果：`logs/mk_manifest.out.txt` 的 `sha256=` 与最终 `manifest-r0.json` 逐一相等；15/15 artifacts、27/27 inputs 重新绑定；`stopped_modifying=true`、`active_commands=0`。

### F3 第二路 camera/CSI 清单（system）

- 根因：r0 报告写 `u_camera` “已含 A/B 两路 CSI RX”，但 routed 层次只有 `u_csi_a`，没有 `u_csi_b`。
- 修复：`resource-table.csv` 的 `u_camera` 行 notes 与 `resource-baseline.md` §4.2/§4.3 明确写：routed 只有 `u_csi_a`；`u_csi_b` 在源码例化但无 routed 资源，第二路完整 CSI **未实现/未计入 marginal**。若需要，marginal 加 773 logic/340 ripple/1,474 seq/0 ERAM → LUT6 26,822、LUT4 上界 53,644、REG 35,815、SLICE 约 32,083，ERAM/headroom/fit 不变。
- 另：b11 行注明 `WNS_ns=+0.015` 是**全局/`ddr_user` 200 MHz 域**，`clk_a1` 187.5 MHz 域为 **+0.059**，不当作 A+ 域结论。

## 2. 修复后的关键值

| 项 | marginal | conservative | 器件/额度 |
|---|---:|---:|---:|
| ERAM 逻辑 | 146 | 204 | 300 总 / 210 额度 |
| DRAMHARDCON（算一次） | 85 | 85 | — |
| ERAM 合计 | **231**（余 69，23.0%） | **289**（余 11，3.67%） | 300 |
| LUT6（TD 恒等式） | **25,709**（35.87%） | 39,390（54.95%） | 71,680 |
| LUT6 logic-only 下界（不作拟合） | 23,488 | 39,390 | 71,680 |
| LUT4 上界（2×LUT6） | **51,418**（39.85%） | 78,780（61.06%） | 129,024 |
| REG / DFF | 34,341 | 56,008 | 143,360 |
| SLICE | 30,733（assumed 比例） | 48,736 | 71,680 |
| DSP / PLL | 0 / 4 | 0 / 8 | 220 / 12 |
| fit_300 / fit_210 | pass / pass | conditional / pass | — |
| 双 DDR 变体 | 316 fail | 374 fail | 300 |

- 若补第二路完整 CSI：marginal LUT6 26,822、REG 35,815、SLICE 约 32,083，ERAM 231 不变，仍 pass/pass（本表主栏不含该项，报告中已明确）。

## 3. 实际执行的命令（完整见 `commands.jsonl`）

| # | 命令（cwd） | exit | 结果 |
|---|---|---:|---|
| 7 | `python gen_baseline.py`（本 `r0/`） | 0 | `P1_GEN_OK`：27 输入/11 断言/0 mismatch；64 资源行；4 预算行；marginal LUT6 25,709 |
| 8 | `python check_tables.py`（本 `r0/`） | 0 | **6/6 PASS**：输入 0 漂移；64 行与报告一致；TD LUT6 恒等式；ERAM 闭合 102/102×3；两栏算术；3/3 负对照命中 |
| 9 | `python .../test-reports/T10.dual-core-resource-baseline/independent_verify.py`（项目根，只读） | **1** | T1（round0 原脚本，未修改）：`budget_marginal`、`budget_marginal_2ddr`、`artifact_hash`、`manifest_log_stale` |
| 10 | `python mk_manifest.py`（本 `r0/`） | 0 | 最终 freeze：15 artifacts / 27 inputs / 10 commands；日志记录最终 manifest SHA |

- `artifact_hash` / `manifest_log_stale` 是**运行顺序效应**：T1 在最终 manifest 生成前运行，读到的是 round0 manifest；seq 10 重新冻结后应消失。
- `budget_marginal` / `budget_marginal_2ddr` 是 **T1 脚本自身的 round0 期望值**：其 line 335 对 marginal 和 marginal_2ddr 硬编码 `LUT6_dev=23,488`，而 F1 要求 25,709，且同一脚本 line 363 又要求 25,709——两者互斥。T1 数据层其余检查（顶层、层次、synth、ERAM、fit、输入、负对照）未报其他 fail item。**需测试者在 r1 更新 T1 的期望 tuple 后复测**；本任务未修改 test-reports（无写权限）。

## 4. 局部检查覆盖

`check_tables.py` 不 import 生成器，独立重解析三份 routed/synth 报告：

1. 27 输入逐个重算 SHA/bytes，0 漂移；b6 core/manifest 硬断言。
2. 64 行资源表逐项比对（3 routed 顶层 + 3 synth 顶层 + 58 层次行）；synth 行不得携带 routed-only 字段。
3. **TD LUT6 恒等式**：三源 `#lut6 = with-luts + with-adder + dram lut + shifter lut` 精确成立。
4. 层次闭合：ERAM/DRAM_LUT/PLL/DSP 精确；logic/ripple/seq 顶层粘合残留 <2%。
5. 双核预算：两栏唯一；`ERAM_total = logic + 85×ddr_controllers`；headroom/210/fit；LUT6 分母 71,680、LUT4 分母 129,024 不混算；marginal 用 TD 恒等式（25,709），logic-only 下界列 = 23,488；marginal_2ddr 与 marginal 的 LUT6/REG/SLICE 一致；conservative 2×；2DDR 变体 374 fail。
6. 3 个负对照：`STAGE_MIX_SYNTH_IN_FIT`、`MISSING_DRAMHARDCON`、`MISSING_TWO_COLUMN_BUDGET` 全部命中。

## 5. 未测 / 边界（不变）

- 双核 Routed 时序/布局/拥塞/时钟树：**unproven**，无构建；不得由单核 +0.103 外推。
- 生产（去 CWC 30 ERAM）后的真实 ERAM：未重跑；只用 Routed 102。
- 精确 LUT4：TD 不报告；只有 2×LUT6 上界。
- 第二路完整 CSI、第二路 FIFO 的 ERAM 映射：**未实现/未计入**，报告已给补算值。
- SLICE 30,733 是比例外推（assumed）。
- 双路 1080p30 服务率/DDR/丢帧属 P2；板级/RK/曝光同步不在本包。

## 6. G 层（不变）

| G | 判定 | 依据 |
|---|---|---|
| G0 | pass | 27 输入 SHA/bytes；b6 core/manifest 硬断言；0 mismatch/0 drift |
| G1 | pass | 资源表可复算、TD LUT6 恒等式、层次闭合、两栏算术、3 负对照 |
| G2 | not_applicable | 无综合/布线/候选；synth 仅检查点 |
| G3 | not_applicable | 无 bitgen/CWC |
| G4 | not_applicable | 无下载/板卡 |

## 7. 边界与回退

- 只写本任务 `T10.dual-core-resource-baseline/r0/**`；未改 protected、b11/T08/T10、`workflow/tasks.json`、`docs/**`。
- 未运行 TD/综合/布线/bitgen/CWC/下载/板卡/RK；未批量删除；round0 失败记录保留在 `commands.jsonl` 与本文 §3。
- 回退：停止采用本 r0；保留全部证据；不改生产。
