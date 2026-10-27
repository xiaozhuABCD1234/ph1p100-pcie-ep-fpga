#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Freeze T10.a1-frame-top round1 evidence: report, notes, manifest, lessons."""
import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(sys.argv[1]).resolve()
RUN = Path(sys.argv[2]).resolve()
UP = ROOT / "upstream/ph1p100-pcie-ep-fpga"
OUT = ROOT / "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.a1-frame-top"
LESS = ROOT / "workflow/runs/20261020-0209_singleA_aplus_closedloop/lessons"
LESS.mkdir(parents=True, exist_ok=True)

res = json.loads((RUN / "result.json").read_text(encoding="utf-8"))
rows = []
for c in res["cases"]:
    p = c.get("p1") or c.get("p2") or {}
    fr = (c.get("frames") or [{}])[0]
    rows.append({
        "name": c["name"], "w": c["w"], "h": c["h"], "mode": c["mode"],
        "prep": c["prep"], "pred": c["pred"], "verdict": c["verdict"],
        "raw": p.get("raw_len") or c.get("multi_bytes"),
        "stream": p.get("stream_len") or fr.get("stream_len"),
        "ratio": p.get("ratio"), "exp": p.get("expansion_pct"),
        "cycles": c.get("cycles") or c.get("multi_total_cycles"),
        "mbps": c.get("mbps_187p5"), "gate": c.get("gate_77_76"),
        "margin": c.get("margin_97_2"),
        "worst": c.get("worst_stored_bytes"), "wexp": c.get("worst_expansion_pct"),
        "sha": p.get("sha256_stream"),
    })


def f(x, n=2):
    return "-" if x is None else (("%." + str(n) + "f") % x)


tbl = ["| case | W x H | mode | prep/pred | raw B | stream B | ratio | exp % | cycles | MB/s @187.5 | >=77.76 | >=97.2 |",
       "|---|---|---|---|---:|---:|---:|---:|---:|---:|---|---|"]
for r in rows:
    tbl.append("| %s | %dx%d | %d | %d/%d | %s | %s | %s | %s | %s | %s | %s | %s |" % (
        r["name"], r["w"], r["h"], r["mode"], r["prep"], r["pred"],
        r["raw"], r["stream"], f(r["ratio"], 3), f(r["exp"], 4),
        r["cycles"] if r["cycles"] else "-", f(r["mbps"]),
        r["gate"], r["margin"]))
table = "\n".join(tbl)

one = next(r for r in rows if r["name"] == "f1080p_p1d1")
p0 = next(r for r in rows if r["name"] == "f1080p_p0")
p1d0 = next(r for r in rows if r["name"] == "f1080p_p1d0")
fr = next(r for r in rows if r["name"] == "f1080p_rand")
mf = next(r for r in rows if r["name"] == "multi1080p")
r16 = next(r for r in rows if r["name"] == "rand1920x16")
mx = next(r for r in rows if r["name"] == "mixed1920x16")
al = next(r for r in rows if r["name"] == "abort_last")

report = f"""# T10.a1-frame-top — round1 dev result (PASS, G0/G1; F1–F5 addressed)

- task_id: `T10.a1-frame-top` (P3)｜round: **r1**（第 1 轮实际修复）
- 判定：**PASS**（20/20 用例；所有整帧逐样本 0 mismatch；坏帧 0 commit/0 eop；0 端口/越界警告）
- 日期：2026-10-20｜run：`20261020-0209_singleA_aplus_closedloop`
- 候选：新 manifest `{OUT / 'CANDIDATE-MANIFEST.json'}`（新候选，不复用 r0 manifest）
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

{table}

- 9 条 committed 流 + 2 帧 multi + 3 条恢复流全部双解 0 mismatch、逐样本 0 mismatch、`stream_len` 精确、无尾随字节。
- 1080p 四种配置：prep1/pred1 {one['stream']} B（ratio {f(one['ratio'],2)}）、prep1/pred0 {p1d0['stream']} B、prep0/pred0 {p0['stream']} B、全随机 {fr['stream']} B。
- 全不可压缩帧命中冻结最坏上界 {fr['stream']} B（= 2,592,000 + 540×5 + 6），逐块 stored，独立解码 0 mismatch。
- `mixed1920x16`：gradient 4 块 + 随机 4 块，stream {mx['stream']} B，覆盖 fixed→stored 混合。
- 奇数行/非 16 对齐：20x5（尾块 1 行）、12x6；A/B 与 pred 开关均 0 mismatch。
- 背压：`bp20x5` 与 `odd20x5_p1d1` 流逐字节一致（`bp_equivalence=True`）。

## 3. 吞吐（真实仿真周期，内容相关，不保证 97.2）

| 场景 | cycles | cycles/B | MB/s @187.5 | 结论 |
|---|---:|---:|---:|---|
| 1080p prep1/pred1（单帧） | {one['cycles']} | {f(one['cycles']/one['raw'],4)} | {f(one['mbps'])} | ≥77.76 ✅；≥97.2（本帧） |
| 1080p 连续 2 帧（聚合） | {mf['cycles']} | {f(mf['cycles']/mf['raw'],4)} | {f(mf['mbps'])} | 连续服务率与单帧一致 |
| 1080p prep1/pred0 | {p1d0['cycles']} | {f(p1d0['cycles']/p1d0['raw'],4)} | {f(p1d0['mbps'])} | ≥77.76 ✅ |
| 1080p prep0/pred0 | {p0['cycles']} | {f(p0['cycles']/p0['raw'],4)} | {f(p0['mbps'])} | ≥77.76 ✅ |
| 1080p 全不可压缩（stored） | {fr['cycles']} | {f(fr['cycles']/fr['raw'],4)} | {f(fr['mbps'])} | ≥77.76 ✅ |
| 1920x16 随机（8 块） | {r16['cycles']} | {f(r16['cycles']/r16['raw'],4)} | {f(r16['mbps'])} | ≥77.76 ✅；<97.2（小帧固定开销） |
| 1920x16 mixed | {mx['cycles']} | {f(mx['cycles']/mx['raw'],4)} | {f(mx['mbps'])} | ≥77.76 ✅ |

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
{{
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
    "{ROOT / 'workflow/runs/20261020-0209_singleA_aplus_closedloop/test-reports/T10.a1-frame-top-r1-integrated.md'}",
    "{RUN / 'result.json'}",
    "{OUT / 'CANDIDATE-MANIFEST.json'}"
  ],
  "input_status": "synthetic only; real RAW/Bayer phase/board/export remain blocked/awaiting_hardware",
  "reuse_decision_paths": [
    "r0 manifest and r0 p3 results are INVALID for this candidate (F1-F5 changed RTL/TB/coverage)",
    "reuse only within the r1 manifest: same candidate + same generated inputs",
    "P2 core regression binding remains valid only because a1_deflate_core.v is unchanged (hash in manifest)"
  ]
}}
```
"""

(OUT / "dev-result.md").write_text(report, encoding="utf-8")

notes = f"""# T10.a1-frame-top — round1 dev notes

## 落地改动
1. `a1_frame_top.v`：`out_last` 增加 `!killed`；9 个 core stat 连接；smem 改为寄存读+2 级预取；
   `prep_r/pred_r` 在 sof 锁存；提交后 1 拍 `core_flush` 清理 P2 核残留 `enc_busy`。
2. `tb_a1_frame_top.v`：新增 mode 6（连续多帧）、mode 7（末字 pending abort）、mode 8（非法几何，
   复位前后各一次）、mode 9（pred-without-prep → 复位 → 合法恢复）；`out_ready` 增加“末字保持”模式。
3. `a1_p3_gen.py`：新增 f1080p_p0 / f1080p_p1d0 / f1080p_rand / mixed1920x16 / multi1080p /
   abort_last / 4 个非法几何/配置用例；W%4!=0 走确定性字节（无合法 RAW10 打包）。
4. `a1_p3_verify.py`：按 mode 校验流、末字 abort 语义、非法帧与连续多帧吞吐。
5. `run_p3.ps1`：支持 `+NFRAMES`；每命令超时。

## 关键取舍
- **不修改 P2 核**：核在最后一帧结束后 `enc_busy` 保持 1（P2 单流用例未暴露），帧 top 在提交后发 1 拍
  `abort` 脉冲清除核状态；核文件 hash 未变，P2 结论仍绑定。
- `smem` 不再组合读：2 级预取保持 4 样本/组，吞吐不变，同时消除 time-0 X 索引与越界。
- 非法几何/配置采用 **reset-only** 恢复：`I_DEAD` 不输出、不提交，复位后重新判定；mode 8/9 已验证。
- 吞吐结论按内容分层：整帧 1080p 101–104 MB/s；1920x16 小帧 88.9 MB/s；97.2 不作保证值。

## 已知限制
- 无 TD/G2/STA/CDC/资源；无板、无真实 RAW/相位。
- 真实样例导出与现场窗口仍 blocked/awaiting_hardware。
"""
(OUT / "dev-notes.md").write_text(notes, encoding="utf-8")

# ---------------------------------------------------------------- manifest
files = [
    UP / "rtl/ep_side/codec/a1_frame_top.v",
    UP / "rtl/ep_side/codec/a1_deflate_core.v",
    UP / "sim/tb/codec/tb_a1_frame_top.v",
    UP / "sim/tb/codec/tb_a1_deflate_core.v",
    UP / "tools/codec/a1_p3_gen.py",
    UP / "tools/codec/a1_p3_verify.py",
    UP / "tools/codec/run_p3.ps1",
    UP / "tools/codec/a1_p3_freeze.py",
    UP / "tools/codec/a1_ref.py",
    UP / "tools/codec/a1_inflate_strict.py",
]
for p in sorted(RUN.rglob("*")):
    if p.is_file() and "work_p3" not in p.parts:
        files.append(p)
files += [OUT / "dev-result.md", OUT / "dev-notes.md",
          LESS / "T10.a1-frame-top-lessons.md"]

entries = []
bad = 0
for p in files:
    if not p.exists():
        bad += 1
        continue
    b = p.read_bytes()
    entries.append({"path": str(p), "size": len(b), "sha256": hashlib.sha256(b).hexdigest()})
manifest = {"task_id": "T10.a1-frame-top", "round": 1, "created": "2026-10-20",
            "file_count": len(entries), "missing": bad,
            "note": "round1 new candidate; synthetic only; work_p3 build library excluded",
            "files": entries}
(OUT / "CANDIDATE-MANIFEST.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
mism = 0
for e in entries:
    b = Path(e["path"]).read_bytes()
    if len(b) != e["size"] or hashlib.sha256(b).hexdigest() != e["sha256"]:
        mism += 1
print("MANIFEST files=%d mism=%d missing=%d" % (len(entries), mism, bad))

lessons = f"""# lessons — T10.a1-frame-top（round1 增补）

1. **abort 的 eop 必须与 commit 同门控**：`out_last` 只看 `svalid&&slast` 会在末字 pending 时泄漏 eop；
   必须加 `!killed`（或 abort 时清 `slast`）。只测“帧中 abort”覆盖不到该角。
2. **单流 PASS 不等于多流可复用**：P2 核最后一帧结束后 `enc_busy` 不清，单流仿真发现不了；
   帧 top 提交后 1 拍 abort 清核即可，无需改已冻结的核（保持 P2 hash 绑定）。
3. **组合大阵列读是警告与综合风险源**：time-0 X 索引 + 块尾 `rd_s==n_samp` 都会越界；
   寄存读 + 2 级预取既清零警告，又不牺牲 4 样本/组吞吐（预取跨 EMIT 需补发第 2 个样本，否则每组第 2 样本重复）。
4. **复位后/跨块的首组预取要单独设计**：2 拍延迟意味着地址必须提前 2 拍发；EMIT 间隙只预取 s0 会漏 s1。
5. **配置必须在 sof 锁存**：guide 要求采样于 sof；用活动端口会让帧中变化破坏变换域。
6. **负例要测“拒绝 + 恢复策略”**：非法几何采用 reset-only 是有意策略，必须用“复位后再非法仍不提交”与
   “复位后合法提交”两类用例证明，而不是只写代码检查。
7. **吞吐必须按内容/几何分层报告**：整帧 1080p 101–104 MB/s、1920x16 小帧 88.9 MB/s；
   97.2 MB/s 不是通用保证，报告须写清帧型与压缩率。
8. **警告也是证据**：vsim-3017/3722/8233 必须计入工程门槛；`vlog 0/0` 只覆盖编译，不覆盖 elaboration/数组访问。
"""
(LESS / "T10.a1-frame-top-lessons.md").write_text(lessons, encoding="utf-8")
print("REPORT OK")
