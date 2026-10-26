import pathlib

R0 = pathlib.Path(r"D:/fpga/ph1p100/workflow/runs/20261025-233401_fpga-steady-state-reverdict/T10.ss-g0-closure/r0")


def patch(path, pairs):
    p = pathlib.Path(path)
    t = p.read_text(encoding="utf-8")
    for old, new in pairs:
        if t.count(old) != 1:
            raise SystemExit("PATCH FAIL %s count=%d for %r" % (p.name, t.count(old), old[:90]))
        t = t.replace(old, new)
    p.write_text(t, encoding="utf-8", newline="\n")
    print("patched", p.name)


patch(R0 / "sim" / "run_g0.py", [
    ('"pacing/sink = slot-free (overlapped) + fast sim sink (measured export ~93.8 MB/s); "',
     '"pacing/sink = slot-free (overlapped) + measured 93.75 MB/s sim sink (proxy not limited; "\n'
     '             "raw band still needs >=77.84 MB/s for G0 / >=103.79 MB/s at 25 ms, not_proven); "'),
])

p = R0 / "g0-closure.md"
t = p.read_text(encoding="utf-8")
old5 = """4. **TB 自检**：修正后 TB 的 `v1` check-only 复跑（2,000,000 cycles 截断，尚未导出）打印 `SS_VEC_MATCH bad=0 checked=518400 drv_groups=518400`；该检查只读 `tap_pix/raw_mem/vec_mem`，不驱动任何 DUT 信号，故对 R3 的时序/事件无影响。
   - R3 原日志的 `bad=691132` 是修正前 TB 自检每 3 个样本分组一次的差一 bug（TB-only、只读；见 `src/DIFF.md` §7），不是内容错误。"""
new5 = """4. **TB 自检（round1，同一 run）**：G0 run 已用冻结 TB `a565c6f2…` 重跑（`r3_frozen`），同一日志打印帧 1 `SS_VEC_MATCH bad=0 checked=518400 drv_groups=518400`、末行 `bad=0 checked=518400 drv_groups=2073600`；该检查只读 `tap_pix/raw_mem/vec_mem`，不驱动 DUT。
   - 旧 TB 的 r3 日志 `bad=691132` 是修正前自检每 3 个样本分组一次的差一 bug（TB-only），其 timing 与 r3_frozen 逐值相同（5,928,286 / 1,697,820 / 27,020,950），但**不再作为 G0 绑定证据**；旧 TB 已归档 `src/legacy/tb_ss_g0_89948303.v`。"""
if t.count(old5) != 1:
    raise SystemExit("g0 §5 count=%d" % t.count(old5))
t = t.replace(old5, new5)

old2 = "| R4 | comp 代理 | strict-serial | 2 GHz | 否 | — | — | — | — | **未运行（预算上限）**，serial 列用 `assumed = R3 + (R2−R1)` |"
new2 = "| R4 | comp 代理 | strict-serial | 2 GHz | 否 | — | — | — | — | **未运行**（触发已满足 R2−R1=36.09%>1%，90-min 墙钟到顶）；serial 列只用 `assumed = R3 + (R2−R1) = 7,616,377.5` |"
if t.count(old2) != 1:
    raise SystemExit("g0 R4 row count=%d" % t.count(old2))
t = t.replace(old2, new2)

old9 = "`out/runs.csv`、`out/runs.json`、`out/g0-table.csv`、`out/gap-menu.csv`、`out/sink-needs.csv`、`out/g0-verdict.json`、`out/content-proxy.json`、`out/content-proxy.md`、`out/negative-controls.json`；`input-verified.json`、`src/DIFF.md`、`src/tb_ss_g0.v`、`sim/{run_g0.py,prep_content.py,verify_inputs.py,freeze.py}`、`sim/logs/*`、`sim/caps/*`、`result-r0.md`、`lessons.md`、`manifest-r0.json`。"
new9 = "`out/runs.csv`、`out/runs.json`、`out/g0-table.csv`、`out/gap-menu.csv`、`out/sink-needs.csv`、`out/g0-verdict.json`、`out/content-proxy.json`、`out/content-proxy.md`、`out/negative-controls.json`、`out/check-outputs.json`；`input-verified.json`、`src/DIFF.md`、`src/tb_ss_g0.v`、`src/legacy/tb_ss_g0_89948303.v`、`sim/{run_g0.py,prep_content.py,verify_inputs.py,freeze.py,check_outputs.py}`、`sim/logs/*`、`sim/caps/*`、`result-r0.md`、`result-r1.md`、`lessons.md`、`manifest-r0.json`、`manifest-r1.json`。"
if t.count(old9) != 1:
    raise SystemExit("g0 §9 count=%d" % t.count(old9))
t = t.replace(old9, new9)

t += """
## 10. round1 修订（2026-10-26；权威 scope）

- **TB 绑定**：G0 关键 run 已用冻结 TB `a565c6f2…` 重跑 `r3_frozen`（`sim/logs/r3_frozen.log`、`sim/caps/r3_frozen.{stats,hdr,evt}`）；同一 run `SS_VEC_MATCH bad=0 checked=518400 drv_groups=518400`（帧 1）/`2073600`（末行）。`S_ss=5,928,286`（±0.5% 内逐值相同）、band [5,928,283, 5,928,289]、计数/header CRC 全部重核；旧 TB `89948303…` 归档 `src/legacy/tb_ss_g0_89948303.v`，仅 R0–R2 timing 依 D1 复用。
- **scope（权威）**：comp 向量代理（transform-domain ramp 按 2 行块 `b mod 32` 平铺、`848,864 B/帧`、`proxy_not_worst`、单内容）/ **slot-free（overlapped）** / **实测 93.75 MB/s sim sink**（对本 proxy 不限速：tail 1,697,820 = 28.6% < 50%；**raw band 生产需求仍 ≥77.84 MB/s（G0）/ ≥103.79 MB/s（25 ms/tail 稳健），`not_proven`**）/ 行为 256-bit PAXI（无 MC/刷新/争用）/ 单核单路 / 187.5 MHz。**不外推**自然图像/全内容/双路/板级/真实 DDR/PCIe/RK；G2–G4 `not_applicable`。
- **R4**：`not_run`（触发条件已满足，90-min 墙钟到顶）；comp strict-serial 只写 `assumed = 7,616,377.5`（63.810 MB/s，G0 −17.94%），不得称 strict-serial 过 G0；headline 只覆盖 slot-free。
- **G25**：仅参考列，不降档；**A1 overlapped 取 R1 4,677,531**（P1 4,677,535 −4 cycles，0.0001%）。
- **headline**：`G0_feasible_for_scope` 为**临时**结论，待同一综合测试者对 `manifest-r1.json` + `r3_frozen` 复测后正式成立；若复测 `S_ss>6.25M` → `G0_not_closed`，`bad>0`/无法绑定 → `G0_not_proven`。
- **元数据修正**：`out/content-proxy.json` 的 `in.meta` 已修为 raw 330 B / `E98C9A1C…`；DIFF §4 sink 改 2 clk_a1/B≈93.75 MB/s、§5 `%02x`、§1 WD 12M、F5–F9 均按 D2 修正。
"""
p.write_text(t, encoding="utf-8", newline="\n")
print("patched g0-closure + appended round1")
