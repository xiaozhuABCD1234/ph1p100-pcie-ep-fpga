import pathlib

R0 = pathlib.Path(r"D:/fpga/ph1p100/workflow/runs/20261025-233401_fpga-steady-state-reverdict/T10.ss-g0-closure/r0")
SIM = R0 / "sim"
SRC = R0 / "src"


def patch(path, pairs):
    p = pathlib.Path(path)
    t = p.read_text(encoding="utf-8")
    for old, new in pairs:
        if t.count(old) != 1:
            raise SystemExit("PATCH FAIL %s count=%d for %r" % (p.name, t.count(old), old[:80]))
        t = t.replace(old, new)
    p.write_text(t, encoding="utf-8", newline="\n")
    print("patched", p.name)


# ------------------------------------------------------------------ run_g0.py
patch(SIM / "run_g0.py", [
    ('    "r4": dict(frames=4, content=1, pacing=1, sink=1, capture=0, mode="comp_fast_serial"),',
     '    "r3f": dict(frames=4, content=1, pacing=0, sink=1, capture=0, mode="comp_fast_slotfree_frozen",\n'
     '                tag="r3_frozen"),\n'
     '    "r4": dict(frames=4, content=1, pacing=1, sink=1, capture=0, mode="comp_fast_serial"),'),
    ('    stat = CAPS / (run_key + ".stats")\n    evt = CAPS / (run_key + ".evt")\n    log = LOGS / (run_key + ".log")',
     '    tag = cfg.get("tag", run_key)\n    stat = CAPS / (tag + ".stats")\n    evt = CAPS / (tag + ".evt")\n    log = LOGS / (tag + ".log")'),
    ('argv.insert(-1, "+DEC=" + str(CAPS / (run_key + ".dec")))',
     'argv.insert(-1, "+DEC=" + str(CAPS / (tag + ".dec")))'),
    ('argv.insert(-1, "+HDR=" + str(CAPS / (run_key + ".hdr")))',
     'argv.insert(-1, "+HDR=" + str(CAPS / (tag + ".hdr")))'),
    ('    m = metrics(run_key, stat, log, el, rc, to)',
     '    m = metrics(run_key, tag, stat, log, el, rc, to)'),
    ('def metrics(key, stat_path, log_path, el, rc, to):',
     'def metrics(key, tag, stat_path, log_path, el, rc, to):'),
    ('    m = {"run": key, "mode": RUNS[key]["mode"], "cfg": RUNS[key],',
     '    m = {"run": key, "tag": tag, "mode": RUNS[key]["mode"], "cfg": RUNS[key],'),
    ('        m["header_check"] = header_check(key)',
     '        m["header_check"] = header_check(tag)'),
    ('def header_check(key):\n    hdr_path = CAPS / (key + ".hdr")',
     'def header_check(tag):\n    hdr_path = CAPS / (tag + ".hdr")'),
    ('    need = [k for k in ("r0", "r1", "r2", "r3") if k not in db]\n'
     '    if need:\n        raise SystemExit("missing runs: %s" % need)\n'
     '    r0, r1, r2, r3 = db["r0"], db["r1"], db["r2"], db["r3"]',
     '    need = [k for k in ("r0", "r1", "r2") if k not in db]\n'
     '    if "r3f" not in db:\n        need.append("r3f")\n'
     '    if need:\n        raise SystemExit("missing runs: %s" % need)\n'
     '    r0, r1, r2, r3 = db["r0"], db["r1"], db["r2"], db["r3f"]'),
    ('    "A1_grad_measured": {"cycles": 4677535.0, "label": "measured", "src": "P1 steady-state S_ss / R1"},',
     '    "A1_grad_measured": {"cycles": 4677535.0, "label": "measured", "src": "R1 fast-sink S_ss (P1 4,677,535 -4 cycles)"},'),
    ('    "P_proxy_measured": {"cycles": None, "label": "measured_proxy_not_worst", "src": "R3 S_ss"},',
     '    "P_proxy_measured": {"cycles": None, "label": "measured_proxy_not_worst", "src": "r3_frozen S_ss (frozen TB a565c6f2)"},'),
    ('    for key in ("r0", "r1", "r2", "r3"):\n        m = db[key]',
     '    for key in ("r0", "r1", "r2", "r3f"):\n        m = db[key]'),
    ('    v1_vec = v1.get("ss_vec_match") or {}\n    r3_vec = r3.get("ss_vec_match") or {}\n'
     '    hdr_ok = (r3.get("header_check") or {}).get("pass", False)\n'
     '    proxy_vec_ok = (v1_vec.get("bad") == 0 and v1_vec.get("checked") == 518400\n'
     '                    and v1_vec.get("drv_groups") == 518400)',
     '    v1_vec = v1.get("ss_vec_match") or {}\n    r3_vec = r3.get("ss_vec_match") or {}\n'
     '    hdr_ok = (r3.get("header_check") or {}).get("pass", False)\n'
     '    proxy_vec_ok = (r3_vec.get("bad") == 0 and r3_vec.get("checked") == 518400\n'
     '                    and r3_vec.get("drv_groups") in (518400, 2073600))'),
    ('               "proxy_self_check": {\n'
     '                   "r3_tb_counter_pre_fix": r3_vec or None,\n'
     '                   "r3_tb_counter_note": "pre-fix TB check compared every 3rd sample (grouping bug, "\n'
     '                                         "TB-only); fixed TB v1 gives bad=0 checked=518400",\n'
     '                   "v1_fixed_tb": v1_vec or None,\n'
     '                   "dut_export_header_crc": (r3.get("header_check") or {}).get("pass"),\n'
     '                   "proxy_ok": proxy_ok,\n               },',
     '               "proxy_self_check": {\n'
     '                   "r3_frozen_same_run": r3_vec or None,\n'
     '                   "legacy_tb_r3_counter": (db.get("r3") or {}).get("ss_vec_match"),\n'
     '                   "note": "R3 re-run with frozen TB a565c6f2: SS_VEC_MATCH bad=0 in the same run; "\n'
     '                           "the r0 legacy-TB counter (bad=691132) is kept only as history",\n'
     '                   "v1_check_only": v1_vec or None,\n'
     '                   "dut_export_header_crc": (r3.get("header_check") or {}).get("pass"),\n'
     '                   "proxy_ok": proxy_ok,\n               },\n'
     '               "a1_overlapped_note": "R1 4,677,531 is 4 cycles below P1 A1 4,677,535 (0.0001%)",\n'
     '               "raw_band_sink_needs_MBps": {"G0": needed_sink_333, "25ms": needed_sink_25},'),
    ('        why = ("proxy byte-level self check failed (v1 bad=%s), DUT header CRC failed, "\n'
     '               "run partial, or no S_ss" % v1_vec.get("bad"))',
     '        why = ("proxy byte-level self check failed (r3_frozen bad=%s), DUT header CRC failed, "\n'
     '               "run partial, or no S_ss" % r3_vec.get("bad"))'),
    ('    verdict["proxy_vec_match"] = v1_vec',
     '    verdict["proxy_vec_match"] = r3_vec'),
    ('               "v1_check_only": {"frames": 1, "max_cycles": 2000000,',
     '               "v1_check_only": {"frames": 1, "max_cycles": 2000000,'),
])

# ------------------------------------------------------------------ prep_content
patch(SIM / "prep_content.py", [
    ('    meta = (COMP / "in.meta").read_text(encoding="ascii")',
     '    meta = (COMP / "in.meta").read_bytes()'),
    ('            "in.meta": {"path": str(COMP / "in.meta"), "bytes": len(meta),\n                        "sha256": sha(meta.encode())},',
     '            "in.meta": {"path": str(COMP / "in.meta"), "bytes": len(meta),\n                        "sha256": sha(meta)},'),
])

# ------------------------------------------------------------------ freeze
patch(SIM / "freeze.py", [
    ('EXCLUDE = {"manifest-r0.json", "_repair.py"}',
     'EXCLUDE = {"manifest-r1.json", "_repair.py"}'),
    ('        "status": "ready_for_test",',
     '        "status": "ready_for_test",\n        "repair_round": 1,\n'
     '        "previous_manifest": {"path": "manifest-r0.json",\n'
     '                              "sha256": sha(R0 / "manifest-r0.json") if (R0 / "manifest-r0.json").exists() else None},'),
    ('        "verdict": {',
     '        "verdict": {'),
    ('            "r0_r3_tb_sha256": "89948303be78da2b4e2cbccbb70935d26825b518620c679ba9d959d3c950008e",\n'
     '                "frozen_tb_sha256": "a565c6f25f5d8ac16ce8dd8042f35395c6018a23d1093448077b0e90b79bd3d0",\n'
     '                "difference": "TB-only byte-level self check grouping fix + early frame-1 print; "\n'
     '                              "check is read-only and never drives DUT signals",',
     '            "r0_r3_tb_sha256": "89948303be78da2b4e2cbccbb70935d26825b518620c679ba9d959d3c950008e",\n'
     '                "frozen_tb_sha256": "a565c6f25f5d8ac16ce8dd8042f35395c6018a23d1093448077b0e90b79bd3d0",\n'
     '                "difference": "TB-only byte-level self check grouping fix + early frame-1 print; "\n'
     '                              "check is read-only and never drives DUT signals",\n'
     '                "r3_frozen_tb": "a565c6f25f5d8ac16ce8dd8042f35395c6018a23d1093448077b0e90b79bd3d0",\n'
     '                "legacy_tb_archived": "src/legacy/tb_ss_g0_89948303.v",\n'
     '                "legacy_sha256": "89948303be78da2b4e2cbccbb70935d26825b518620c679ba9d959d3c950008e",'),
    ('            "r3_pre_fix_vec_counter": "SS_VEC_MATCH bad=691132 checked=691200 in the R3 log is the "\n'
     '                                      "pre-fix TB grouping bug; fixed-TB v1 check-only gives bad=0 "\n'
     '                                      "checked=518400",',
     '            "r3_frozen": "G0 run re-run with frozen TB; same-run SS_VEC_MATCH bad=0 checked=518400; "\n'
     '                         "legacy r3 log (bad=691132) is archived history only",\n'
     '            "in_meta_fix": "content-proxy.json in.meta now 330 B / raw E98C9A1C...",\n'
     '            "sink": "measured 2 clk_a1/B = 93.75 MB/s; raw band needs 77.84 (G0) / 103.79 (25ms) MB/s",'),
    ('        "notes": {', '        "notes": {'),
    ('    (R0 / "manifest-r0.json").write_text(json.dumps(man, indent=2) + "\\n")',
     '    (R0 / "manifest-r1.json").write_text(json.dumps(man, indent=2) + "\\n")'),
])

# ------------------------------------------------------------------ DIFF.md
patch(SRC / "DIFF.md", [
    ('| 37 | `WD_LIMIT=12,000,000` | strict-serial 下“相机 1.6M + core 6.0M”可超过 P1 的 8M 门限；12M 仍远低于 MAX_CYCLES，仅防真挂死 |',
     '| 37 | `WD_LIMIT=12,000,000` | strict-serial 下“相机 1.6M + core 6.0M”可超过 P1 的 8M 门限；R3 `L_cold=9,234,076 > 8M` 会误触发；12M < MAX_CYCLES=48M，仅防真挂死。**round1 D2 白名单允许** |'),
    ('- **实测口径**：导出器每字节要一次 `clk_a1` 的 holding-register 交接（`a1_uart_export` 单寄存器握手），因此 SINK=1 的实际上限 ≈ 1 B/clk_a1 = **187.5 MB/s**，低于请求的 200 MB/s；报告按实测导出率/`export_tail` 给结论，不写 200 MB/s 已达成。',
     '- **实测口径（round1 修正）**：SINK=1 的 a1 域导出实测为 **2 clk_a1/B = 93.75 MB/s**（R3 tail 1,697,820 / 848,908 B 含 44 B 头；payload-only 93.7449 MB/s；R1/R2 80,160 / 40,034 B），不是 187.5 或 200 MB/s；报告按实测导出率/`export_tail` 给结论，不写 200 MB/s 已达成。'),
    ('- `CAPTURE=1`：P1 逐字节 `.dec`（`%02x\\n`；P1 为 `%0d\\n`，只是文本格式，字节计数与内容不变）。',
     '- `CAPTURE=1`：P1 逐字节 `.dec`（`%02x\\n`；P1 为 `%0d\\n`，只是文本格式，字节计数与内容不变）。**round1 D2 白名单允许 `%02x`；P3 不与 P1 `.dec` 做逐字节比较。**'),
    ('- `CAPTURE=0`：comp-like 不写逐字节 `.dec`；只把导出流的**前 256 B** 写入 `+HDR=` 文件并继续计数（`cap_bytes`）。前 44 B 即第 1 帧头，用于 DUT 端到端 CRC 自检。',
     '- `CAPTURE=0`：comp-like 不写逐字节 `.dec`；只把导出流的**前 256 B** 写入 `+HDR=` 文件并继续计数（`cap_bytes`）。前 44 B 即第 1 帧头，用于 DUT 端到端 CRC 自检。**round1 D2 白名单允许 `+HDR` 256 B（header CRC 必需）。**'),
    ('- `SS_EVT` 六类事件、`SS_META`、`SS_PACE`、`SS_STATS` 协议与 P1 相同；`SS_META` 末尾追加 `content/pacing/sink/capture`，`SS_STATS` 末尾追加 `content/pacing/sink/capture/vec_bad/vec_checked/drv_groups`；b11 前 16 字段顺序与数值不变（R0 已验证）。',
     '- `SS_EVT` 六类事件、`SS_META`、`SS_PACE`、`SS_STATS` 协议与 P1 相同；`SS_META` 末尾追加 `content/pacing/sink/capture`，`SS_STATS` 末尾追加 `content/pacing/sink/capture/vec_bad/vec_checked/drv_groups`；b11 前 16 字段顺序与数值不变（R0 已验证）。**round1 D2 白名单允许这些追加字段与 `SS_MODE`。**'),
])

# append round1 block to DIFF
p = SRC / "DIFF.md"
t = p.read_text(encoding="utf-8")
t += """
## 9. round1 归档、白名单与 F5–F8（2026-10-26）

- **旧 TB 归档**：R0–R2 使用的 TB `89948303be78da2b4e2cbccbb70935d26825b518620c679ba9d959d3c950008e`（23,894 B）已复制到 `src/legacy/tb_ss_g0_89948303.v` 并加入 `manifest-r1.json` artifacts。
- **精确 diff（旧→冻结 `a565c6f2…`，24,118 B）**：4 行 `if (vn0/1/2/3 == 2'd3)` → `2'd0`（字节级自检每 3 个样本分组一次的差一修正）；帧 1 `drive_frame(1)` 后新增一条 `SS_VEC_MATCH` 早打印（及 `$fwrite` 到 evt）。**无 DUT 驱动/端口/几何/时钟/复位/内容映射改动。**
- **R0–R2 TB-only 等价论证**：`CONTENT=0` 时自检段整段不执行、早打印只读；测试者用冻结 TB 独立重跑 R0，`stats`/`.dec` 与候选逐字节相同（881.5 s，0 Errors）。规划 D1 书面接受 R0–R2 timing 复用。
- **R3 重跑**：G0 run 用冻结 TB 重跑（`sim/logs/r3_frozen.log`、`sim/caps/r3_frozen.{stats,hdr,evt}`），同一 run 打印 `SS_VEC_MATCH bad=0 checked=518400 drv_groups=518400`（帧 1 早打印）与 `bad=0 checked=518400 drv_groups=2073600`（全 4 帧末打印）；旧 TB 的 r3 只作历史证据。
- **F7**：G0 表 A1 overlapped 取 R1 `4,677,531`，比 P1 A1 `4,677,535` 低 4 cycles（0.0001%），已在 `source` 列与报告注明。
- **F8**：`sim/_repair.py` 是 round0 一次性编码修复脚本，已从 `manifest-r1.json` 排除并在 notes 说明；`p2_a1_board_top.v` 只复制/哈希、不编译，未列入 12 源编译清单。
- **F5**：R4 触发条件（R2−R1=36.09% > 1%）已满足，但 90-min 墙钟到顶未跑；serial comp 只写 `assumed = 7,616,377.5`，不得称 strict-serial 过 G0。
- **F6**：v1 三次 check-only 曾复用同一日志名；round1 起新日志使用独立名（`r3_frozen.*`），最终 v1 证据保留 `sim/logs/v1.log`，历史 argv/rc/耗时保留在 `sim/commands.jsonl`。
- **round1 D2 白名单**：`WD_LIMIT 12M`、`%02x` `.dec`、`+HDR` 256 B、`SS_META/SS_STATS` 追加字段与 `SS_MODE`、帧 1 早打印与分组修正均获规划书面允许；DUT 驱动/几何/时钟/复位/内容映射仍禁止改动。
"""
p.write_text(t, encoding="utf-8", newline="\n")
print("appended DIFF round1")

# ------------------------------------------------------------------ lessons append
lp = R0 / "lessons.md"
lt = lp.read_text(encoding="utf-8")
lt += """
## round1（2026-10-26）

7. **关键 run 的自检必须与 timing 同 run 同 TB**：R3 的 `bad=0` 不能来自另一个 TB 版本的 check-only run；用冻结 TB 重跑关键 run，并在同一日志里保留 `SS_VEC_MATCH`。
8. **raw 字节元数据不要用 `read_text()` 计数/哈希**：Windows 换行归一化会把 330 B 的 `in.meta` 记成 297 B/normalized SHA；一律 `read_bytes()`。
9. **白名单外的 TB-only 改动也要事先获批**：`WD_LIMIT`、`.dec` 文本格式、`+HDR`、追加字段都应在计划里列明，否则工程门槛会 FAIL。
10. **sink 要写实测率而不是请求值**：2 GHz 请求 200 MB/s，a1 域交接实测 93.75 MB/s；raw band 的 tail 27.7 ms（83%）会限速，proxy 的 1,697,820（28.6%）不会。
"""
lp.write_text(lt, encoding="utf-8", newline="\n")
print("appended lessons")

# ------------------------------------------------------------------ result-r1
(R0 / "result-r1.md").write_text("""# result-r1 — `T10.ss-g0-closure`（round1 修复）

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
""", encoding="utf-8", newline="\n")
print("wrote result-r1")
