# T10.ss-g0-prod-coregap r1 — 文档重冻（同一开发会话；0 sim）

- run `20261026-143924_fpga-1080p30-g0-production`；task `T10.ss-g0-prod-coregap`；round **r1（repair_round=1，文档级重冻）**
- 依据：P2 r0 综合报告（PASS，7 条非阻断 OBS）+ `p2-obs-ruling.md` §2 重冻清单
- **不改**：模型算术（r/k/c_ab）、8 行矩阵、A+H = 6,008,078 / 2.3179 c/B、包络 45.034%、`closable_at_187_5=conditional`、G0 headline
- **0 sim**：无探针重跑、无 vsim、无 TD/综合/布线/bitgen/CWC/下载/Flash/板卡/COM/JTAG/RK/网络、无批量删除

## 1. R1–R8 执行

| # | 对象 | 实际改动 | 结果 |
|---|---|---|---|
| R1 | `src/DIFF-probe.raw`、`src/DIFF-probe.md` | 用**最终** `tb_ss_4run_wd_probe.v`（SHA `d2aa6cc0…`，未改）重跑 `git diff --no-index --unified=2` → **54 行 / 3 hunk / +32 −0**，SHA256 `066f8fd22d293f7e0ca4963abf5cfcb7710e3f3b113df19130c934c21d07f6cd`；`.md` 的行数/hunk/生成说明与白名单第 4 项（8 拍事件式 dump）已对齐；并注明测试者 `--unified=3` 副本为 60 行 / 3 hunk、hunk 内容逐行相同 | 关闭 OBS-1 |
| R2 | `out/coregap-model.json` 行 H `note` | 改为 “→ 6,260,648 cycles (2.4154 cycles/B), i.e. −0.17% against the 6,250,000 gate … still short”；全文件已无 “6.63M / 6.2%” | 关闭 OBS-2 |
| R3 | `model/assumptions.json` | 增列 `c_ab = 1109.0`（`assumed(fitted)`，附三点联立方程：N/L/comp 三式）；新增 `label_taxonomy` 把 `fitted` 映射为 `assumed(fitted)`（冻结词汇仍 measured/derived/assumed）；写明 **in-sample=0 是构造性、不是验证**；把 r0 的 `aborted_scan_credit=0.0` 列入 `superseded` | 关闭 OBS-3 |
| R4 | `out/coregap-model.json → residuals.C1`、`out/coregap-verdict.json`、`result-r0.md §3` | C1 改用**物理系数**：2,905,862（M=0）～3,042,041（M ≤ stream/3），估计 2,956,095 = **链级 63.19%**；删除 r0 的核级界与非物理 `k=−2418` 依据（该 k 只保留在 LOO 里用于解释第三参数存在，并注明**不用于 C1/矩阵**）；结论句保留 `not_applicable_core_level` | 关闭 OBS-4 |
| R5 | `out/coregap-model.json` 行 B/C | `delta_scan=-0.02×scan` 标注 `assumed`（**不是** matcher 结果）；保留 matcher 未探针验证、hbits 10→12/13 <0.1%、窗口 2048→4800 仅 0.54%(N)/0.20%(L) literals 的证据；B/C 仍为“否” | 关闭 OBS-6 |
| R6 | `out/coregap-model.json → anchors.{N,L}.probe_vs_p1_pct` | 参照物统一为 **P1 r1 帧 1 `core_interval`**（N 0.000% / L 0.000%）；4 帧稳态 `S_ss` 对照改列 `probe_vs_p1_ss_pct`（N 0.0134% / L −0.1022%）并注明口径不同、仅参考 | 关闭 OBS-7 |
| R7 | 本文件 + `manifest-r1.json` notes | 登记 **OBS-5 过程偏差**：r0 开发工具调用 ≈49 > 40，无仿真增量（全尺寸 1 帧仍 3/3、vsim 34.93 min）、无门禁影响、不追溯改判 | 已登记 |
| R8 | `manifest-r1.json` | `repair_round=1`、`previous_manifest=manifest-r0.json`（`97d7b1955b1df0bde45e9305d80a8aa703ea1365009d407f0d5d71d58dc6cc15`）、全 artifact 重哈希、`stopped_modifying=true`、`active_commands=0`、`evidence_rounds` 全 0 sim | 已冻结 |

## 2. 未变项（逐值复核）

| 项 | 值 |
|---|---|
| r / k / c_ab | 1.9007 / 293.63 / 1109.0 |
| 探针 | N 7,476,245、L 6,979,811（r0 实测，未重跑） |
| 矩阵 | A 7,223,675、B/C 7,384,642、D/E/F/G 7,476,245、H 6,260,648 |
| 组合 | A+H **6,008,078（2.3179 c/B，+4.03%）**、A+B+H 5,916,475、A_full+H 3,970,580（乐观上界） |
| 包络 | 7,223,675 / 3,970,580 → **45.0%** |
| 判定 | `closable_at_187_5 = conditional`；headline `G0_not_closed` |

## 3. 边界

本重冻**不新增任何证据**，不改变任何结论；不证明 G0 闭合，不做 TD/板卡。改造后核的实测周期、任何方案时序/资源、生产 sink/DDR/板级/双路/传感器 RAW 仍未测。

## 4. 复现（0 sim）

```powershell
python model/patch_r1.py              # r0 -> r1 报告层补丁（锚点缺失会 assert 失败）
python model/finalize_r1.py           # 重生成 coregap-model.json + 校验不变量 + 重写 verdict/assumptions/DIFF/本文件 + manifest-r1
```

## 5. 预算

| 项 | 上限 | 实际 |
|---|---|---|
| 工具调用（r1） | 15 | 见主会话记账（≤15） |
| 墙钟 | 30 min | ≤30 min |
| 仿真 / TD / 板卡 / 网络 | 0 / 0 / 0 / 0 | **0 / 0 / 0 / 0** |
| 探针（P2 累计） | ≤3 | 3（r0，未新增） |
