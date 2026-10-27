# handoff — `T10.ss-g0-prod-verdict`（P4，run `20261026-143924_fpga-1080p30-g0-production`）

- 来源角色：fpga-dev（新开发会话，未复用 P1/P2/P3）；状态：**ready_for_test**（未自判验收）
- headline：**`G0_not_closed`**；证据：**0 sim / 0 TD / 0 板卡 / 0 网络**
- 本包只合并 P1 r1b + P2 r1 + P3 r0，并显式写入 `sink_limited` 澄清；**未重写上游任何文件**

## 1. 冻结候选

- 候选根：`D:\fpga\ph1p100\workflow\runs\20261026-143924_fpga-1080p30-g0-production\T10.ss-g0-prod-verdict\r0`
- manifest：`manifest-r0.json`（全 artifact、`stopped_modifying=true`、`active_commands=0`、`evidence_rounds` 全 0）
- 主产物：
  - `g0-production-verdict.json`（headline/scope/six statements/per-class/rejection list）
  - `out/evidence-binding.json`（三 manifest 全 artifact SHA 复算 + 字段来源指针）
  - `result-r0.md`、`handoff.md`、`final-summary.md`、`user-summary.md`
  - `tools/build_verdict.py`（确定性构建/复核）、`commands.jsonl`

## 2. 上游输入（只读；tester 必须用同一份）

| 包 | 验收 | manifest | SHA-256（前 8） | artifacts |
|---|---|---|---|---:|
| P1 `T10.ss-g0-prod-content` | PASS r1b | `T10.ss-g0-prod-content/r0/manifest-r1.json` | `e306ed42` | 70 |
| P2 `T10.ss-g0-prod-coregap` | PASS r1 | `T10.ss-g0-prod-coregap/r0/manifest-r1.json` | `803d3efb` | 49 |
| P3 `T10.ss-g0-prod-sink` | PASS r0 | `T10.ss-g0-prod-sink/r0/manifest-r0.json` | `de8a5cff` | 5 |

- P1 关键：`out/content-verdict-r1.json`（`b92f84b5…`）、`result-r1.md`、`test-reports/T10.ss-g0-prod-content-r1b-integrated.md`。
- P2 关键：`out/coregap-verdict.json`、`out/coregap-model.json`、`result-r1.md`、`test-reports/T10.ss-g0-prod-coregap-r1-integrated.md`；**必须绑 r1**（r0 文档已被 OBS-8 原地覆盖）。
- P3 关键：`out/sink-headroom.json`、`result-r0.md`、`test-reports/T10.ss-g0-prod-sink-r0-integrated.md`。
- 规划口径：`p4-release-ruling.md`、`fpga-design-guide.md` §3/§8、`dev-plan.md` §4。

## 3. 复测清单（交新综合测试者，round0）

- `required_dimensions`: `integrated`
- `required_checks`: D1–D10（dev-plan §4 / ruling §3.5）。重点：
  - D2 headline=`G0_not_closed`；D3 六条数值/来源；D9 `sink_limited` 澄清 + L 重分类 + 不改写声明；
  - D7 P2 绑 r1；D8 无 G0 闭合/A+H 已实现表述；D10 0 sim/0 TD/写范围/哈希稳定。
- 独立复核入口（0 sim）：
  1. 重算三 manifest 的 124 个 artifact SHA（`out/evidence-binding.json` 已给全值）；
  2. 用 `content-verdict-r1.json` 独立复算 `S_ss/tail_frac/busy/margin_G0`；
  3. 用 `coregap-verdict.json` 复核 A+H/H/包络/`conditional`；
  4. 用 `sink-headroom.json` 复核 86.252<93.75、103.788 缺口 10.7075%；
  5. 校验本包 `manifest-r0.json` 全 artifact SHA 与 `stopped_modifying/active_commands/evidence_rounds`。
- 报告路径（由 tester 写）：`test-reports/T10.ss-g0-prod-verdict-r0-integrated.md`
- `input_status`: `frozen`；`reuse_decision_paths`: 上述三 manifest + 本包 `manifest-r0.json`（不拼旧 PASS）
- 禁止：重跑全尺寸、TD/板卡、改写 P1/P2/P3、把 A+H 写成已实现/G0 闭合、用 G25 主推降档。

## 4. 待用户决定（P4 不主推降档）

1. 投入 core 结构改版（A+H：2-position scan + 2 B/cycle replay）→ 原型 + TD + 板级 + 4 帧复测；
2. 换核/换算法（独立任务与预算）；
3. 接受 `G0_not_closed` 边界（仅声明内容/scope）；
4. 降档需用户**明确**授权，本包不预设。

## 5. 恢复入口

```text
Codex:    $fpga-orchestrator 恢复：D:\fpga\ph1p100\workflow\runs\20261026-143924_fpga-1080p30-g0-production；本轮目标：<目标>
OpenCode: /fpga-orchestrator 恢复：D:\fpga\ph1p100\workflow\runs\20261026-143924_fpga-1080p30-g0-production；本轮目标：<目标>
```

- 收尾：P4 PASS 后由**原规划**复核 `handoff/final-summary/user-summary` 并写收尾记录；本 run 不再开新包。
