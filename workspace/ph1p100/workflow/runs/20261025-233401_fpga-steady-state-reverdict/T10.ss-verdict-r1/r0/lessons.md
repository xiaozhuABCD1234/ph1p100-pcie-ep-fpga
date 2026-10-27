# lessons：`T10.ss-verdict-r1` r0（稳态锚点复核 / 双 gate 判定 / 内容包络）

只记可复用的根因、触发条件、修正方式与验证入口。

## 1. 冷启动延迟当吞吐（最大单点错误）

- 根因：把单帧冷启动完成时间（`t_exp(1)-t_rst`）当作每帧服务时间。b6 `6,421,414` → `29.199 fps` 看似“实测”，实际含 44.66% startup。
- 触发：只有单帧统计、没有事件时间戳；或把 `stats.cycles/FRAMES` 当帧间隔（还含 2,000-cycle drain）。
- 修正：必须分离 `L_cold` 与 `S_ss=(S_23+S_34)/2`；额外用 `startup_pct>15%` 作“是否可当吞吐”的自动跳闸判据。
- 验证入口：`model/test_calc.py` 中 A1/A2 容量与 margin 断言；`check_outputs.py` 断言 1080p 行 `chain_anchor_id=A1_grad_ss`；NC1。

## 2. 0% 与 25% 必须分两个 gate

- 根因：把“25% 设计裕量未达”写成 `infeasible`，吞掉“nominal 已过”。
- 触发：单一 `margin<0` 阈值 + 单一 `gate_status` 字段。
- 修正：`G0`（0%）与 `G25`（1.25×）分列；`below_25 → conditional`；`claim_status` 与行 verdict 分离，行 verdict 不得被用来升级 claim。
- 验证入口：`classify_row()` 的 V2/V4 顺序 + NC2 + `check_outputs.py` 的 gate 不塌缩断言。

## 3. 行 verdict 与 claim（内容）结论分离

- 根因：想用一个词概括“单内容实测过、保守内容不过”。
- 修正：行 verdict 只表达该行在其锚点上的算术+资源/时序；`claim_status` 与 headline 单独表达内容包络。A1.G0≠A2.G0 时必须 `not_proven`。
- 验证入口：`headline_1080p30()` 的四个分支 + `test_calc` 的 headline 断言 + `check_outputs` 的“报告 headline”检查。

## 4. A2≡A4 的定义循环

- 根因：`overhead := 6,421,414 − 5,995,029.375`，再用它造 A2，于是 A2 与 A4 只差 0.375 cycle，却被当成两条独立证据。
- 修正：A2 仅标 `assumed`；报告中强制披露“同值来自定义”；overhead 只用于档位差，不当作独立实测。
- 验证入口：`check_outputs.py` 的 `A2−A4=0.375` 断言 + 报告 §3.1 强制披露。

## 5. sim fast sink / 真实 UART / 常数导出尾巴

- 根因：把 TB 的 `UART_DIV=1`（18.75 MB/s）当生产路径；把导出成本无条件从 `S_ss` 扣除。
- 修正：`export_tail(k)=t_exp−t_enc` 逐帧核对；恒定且 <0.5·`S_ss` → 在帧间差中抵消，不扣减（`C_excl_export=C_ss`）；只有随 k 增长才 `sink_limited=true`；`transport=not_proven`；真实 115200 用 11,520 B/s 显式算 3.475 s / 225.235 s。
- 验证入口：UART 的一组 `test_calc` 断言 + NC4 + `check_outputs` 的 `sink_limited=false`/`export_tail` 检查。

## 6. DDR 峰值口径

- 根因：直接沿用 6,400（@1600）而平台是 1333；文档里的 1.2/2.33/3.4 GB/s 又不能用 `data_rate×width/8` 复现。
- 修正：主线 5,332、回退 6,400 双列；显式公式；文档差异单列“不采用”；平均在峰值内 ≠ sustained 达标。
- 验证入口：NC3 + `check_outputs` 的双列/效率断言（15.1732/18.9665 与 12.6412/15.8014）。

## 7. 内容基一致性决定推荐

- 根因：把单内容实测锚点（grad）与其他几何的 comp 外推翻倍比较，会让 1080p 靠“有利内容”抢到主推荐。
- 修正：主推荐/备选与比较对象同内容基（comp-affine）；1080p 单列 `measured-content only / not_proven_all_content`；只有 A2 也过 G25 才允许 1080p 上位。
- 验证入口：`recommendations()` 只在 `affine_comp_tier` 里选主推荐 + `check_outputs` 的“推荐唯一/极大/内容基”断言。

## 8. legacy 逐字节回归是最便宜的“只改规则”证明

- 做法：把 P2 `calc.py`/`rules.json`/`frozen-inputs.json` 逐字节复制到 `inputs/legacy/`，先校验 SHA，再用它重算并对比冻结 CSV。
- 本次结果：43 行 **byte-identical**、129 行 0 mismatch。这样任何数值变化都可归因到规则/输入，而不是“实现漂移”。
- 验证入口：`model/regress_legacy.py` + `out/legacy-regression.json`。

## 9. 生成式报告 + 独立检查器的坑

- CSV 打印精度（cycles `.3f`、MB/s `.6f`、% `.4f`）必须与检查容差对齐，否则“算法正确但检查失败”。
- Python `%` 模板里字面百分号要写 `%%`；只对“实际做了 % 格式化”的字符串生效，漏一处就输出 `%%`（本次加了 `"%%" in line` 的生成期守卫）。
- 共享格式化函数（`fmt_pct/fmt_num/fmt_cyc`）让“报告数值”与“检查期望值”不会漂移；但检查器必须用自己的算术重算，不能调用生成函数求值。
- 验证入口：`render_report.py` 的 `UNFORMATTED-PERCENT LINES` 守卫 + `check_outputs.py` 的 key-figure 行匹配。

## 10. 预算教训

- 纯模型+7 张 CSV+生成式报告+独立检查器，实际约 58 次工具调用，超过冻结的 35。主要消耗在“列名/精度/模板转义”的迭代。
- 下次同类任务：先冻结 CSV 列名与检查容差表（一页），再写生成器；先跑 `gen_tables` 自检列完整性，再写报告模板；把负对照与边界测试放在模型里（一次跑完），检查器只做跨文件一致性。
