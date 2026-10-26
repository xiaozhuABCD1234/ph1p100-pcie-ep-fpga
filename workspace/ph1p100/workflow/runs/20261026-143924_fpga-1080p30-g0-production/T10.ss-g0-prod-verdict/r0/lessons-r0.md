# lessons — `T10.ss-g0-prod-verdict`（P4，0 sim）

## 可复用根因/触发/修正

1. **`tail_frac ≥ 50%` 不是 sink 约束的充分证据。**
   - 触发：P1 自然内容 L `tail_frac=61.72%`，旧规则直接判 `sink_limited`/`G0_not_proven`。
   - 修正：改用 sink 忙碌率 `busy=export_time/S_ss ≥ 0.95` 作为 `G0_not_proven` 阻断条件；`tail_frac` 仅保留为诊断旗标。L 实际 busy=61.72%、N=44.88%，均 <0.95 → `G0_not_closed`。
   - 证据入口：`p4-release-ruling.md` §2、`fpga-design-guide.md` §3、`out/evidence-binding.json`。
2. **“算术闭合”与“可交付闭合”必须分开写字段。**
   - A+H 6,008,078（+4.027%）只是 187.5 MHz 算术闭合；包络 45.034%、0 RTL/0 TD。用 `arithmetic_closure_at_187_5=true` + `g0_closure=false` + `implemented=false` 三个字段分开，避免被读成已实现。
3. **跨包合并必须整包复算 SHA，而不是只信 manifest 里的前缀。**
   - 本包对 P1/P2/P3 的 124 个 artifact 逐文件 sha256：0 mismatch（17,204,469 / 494,044 / 60,546 B）；P2 只绑 `manifest-r1`（`803d3efb…`），r0 文档被 OBS-8 原地覆盖、不可复现。
4. **构建脚本先做值断言，再写 JSON。**
   - 所有引用数值（`S_ss`、`busy`、A+H、H、包络、86.252、103.78824）在脚本里断言；任何上游漂移会直接失败而不是产出“半套判定”。
5. **0-sim 合并任务也要冻结命令与预算。**
   - `tools/build_verdict.py` 可重复、无时间戳；重跑后 `manifest-r0.json` 逐字节不变（首次冻结时验证；加入本 lessons 文件后重新冻结，最终 SHA 见 `manifest-r0.json`）。

## 本次过程偏差（需 tester 知悉）

- P4 dev 实际使用 **31 calls > 25**（超 6）：两次 build 脚本修正（RUN 路径、A+H 四舍五入断言）、新增本 lessons 文件与元数据一致性修订。**0 sim / 0 TD / 0 板卡 / 0 证据增量**，不影响任何判定或 D1–D10 数值，不追溯改判。
- 无其他偏差；未改 P1/P2/P3、未跑仿真、未使用网络。

## 下次注意

- 文档类包若需 lessons，应在首次 manifest 冻结前写入，避免二次重冻与预算超限。
- 引用 `p4-release-ruling.md` 的 45.034% 与 JSON `envelope_uncertainty_pct=45.0`（取整字段）时，写明两者关系（45.034% 由 3,970,580–7,223,675 计算）。
