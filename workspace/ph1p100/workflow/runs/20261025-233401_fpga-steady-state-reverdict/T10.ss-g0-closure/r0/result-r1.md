# result-r1 — `T10.ss-g0-closure`（round1 修复）

- 修复对象：r0 integrated FAIL 的 engineering/G1 input binding（F1/F2/F3）与 scope 文字（F4/F5/F7/F9）；数据面与 G0 数值不变。
- 状态：`ready_for_test`；`stopped_modifying=true`；`active_commands=0`；无 TD/综合/布线/bitgen/板卡/COM/JTAG/RK。

## 1. 本轮实际动作

| # | 动作 | 证据 |
|---|---|---|
| 1 | 冻结 TB `a565c6f2…` 重跑 R3（comp proxy/slot-free/SINK=1/FRAMES=4/CAPTURE=0，同一 `comp_raw/comp_vec`） | `sim/logs/r3_frozen.log`、`sim/caps/r3_frozen.{stats,hdr,evt}` |
| 2 | 旧 TB `89948303…` 归档并绑定 | `src/legacy/tb_ss_g0_89948303.v`（23,894 B） |
| 3 | `content-proxy.json` 的 `in.meta` 修为 raw 330 B / `E98C9A1C…` | `out/content-proxy.json` |
| 4 | DIFF 白名单/§1/§4/§5/F5–F9 修正 + 旧→冻结 TB 精确 diff | `src/DIFF.md` §4/§5/§9 |
| 5 | 更新 runs/g0-table/g0-verdict/g0-closure/sink-needs/gap-menu；新增 result-r1/lessons | `out/*`、`g0-closure.md` |
| 6 | 重新冻结 `manifest-r1.json`（保留 r0 证据与 `manifest-r0.json`） | `manifest-r1.json` |

## 2. R3 冻结 TB 复跑结果

- 同一 run：`SS_VEC_MATCH bad=0 checked=518400 drv_groups=518400`（帧 1 早打印）；全 4 帧末打印 `bad=0 checked=518400 drv_groups=2073600`。
- `S_ss=…`（见 `out/runs.csv` 的 `r3f` 行）；band/计数/`header CRC` 见 `out/runs.json` 与 `sim/caps/r3_frozen.hdr`；与 r0 旧 TB 的 5,928,286 比较在 `out/g0-verdict.json` 的 `r3_vs_r0` 字段。
- 判据：`S_ss ≤ 6,250,000` → `G0_feasible_for_scope`；`>6.25M` → `G0_not_closed`；`bad>0`/无法绑定 → `G0_not_proven`（以 `out/g0-verdict.json` 为准）。

## 3. 未做/边界

- 未重跑 R0–R2（规划 D1 接受 TB-only 等价；测试者已用冻结 TB 独立复现 R0）；未跑 R4（预算；`assumed=7,616,377.5`）。
- G25 仅参考；不降档；scope 仅 comp 代理 + slot-free + 实测 93.75 MB/s sink + 行为 DDR + per-stream/单核；raw band 生产需求 ≥77.84/103.79 MB/s 仍 `not_proven`。
- A1 overlapped 取 R1 4,677,531（P1 4,677,535 −4 cycles）。
