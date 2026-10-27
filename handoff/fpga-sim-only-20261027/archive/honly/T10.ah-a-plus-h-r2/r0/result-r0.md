# result-r0 — T10.ah-a-plus-h-r2（Line A：A+H 离线原型，仅 ModelSim）

**状态：KILL —— A 不采用（kill/partial）。** 冻结输入 = 本文件 + `manifest-r0.json`（`stopped_modifying=true`、`active_commands=0`、无本任务 vsim 进程）。

两条**互相独立**的 dev-plan §2.4 触发同时成立（任一条已足以 kill）：

1. **token 流不是逐字节等价**：A 的 `stream_len` 比 H-only r1 短（N f1 1,665,923 vs 1,677,912；L f1 2,153,391 vs 2,156,868），4/4 帧 `.frm`/`.hdr` 整文件 SHA 全部不等。
2. **N4 增益不足**：S_ss 6,104,484.5 → 相对 H-only r1 6,196,749.5 只省 **92,265** < 100,000。

回退：**H-only r1 仍是唯一候选**（`8acd20b2…b17b` / `4afc26e2…e30a`，manifest `f752ae09…`）。本任务全部产物为 append-only 新目录，未覆盖任何旧文件。

---

## 1. 冻结候选（`changed-src/`）

| 文件 | 字节 | SHA-256 | 说明 |
|---|---:|---|---|
| `a1_deflate_core.v` | 89,053 | `f3ee798fdaece79a56bcb462f471c11e3a856002e656615238d5753d31833adc` | A 版（2-position literal 扫描 + ≤16 bit 双符号 packer），改写自 H 的 `8acd20b2…` |
| `a1_frame_top.v` | 29,207 | `4afc26e246fbae4e32c5ab7e88dffb496048d10966c5ee42b290b3e71f60e30a` | **与 H-only r1 逐字节相同（未改）** |
| `tb_ss_4run_wd.v` | 29,468 | `d86456dddb0aaa72a55f605c04cb8f51e9bd201b5cc11980dff89eb9afcbce6b` | 冻结 TB 副本 |
| `tb_ss_4run_wd_probe.v` | 33,371 | `c8c19a176a5cd7e0ef0fa6835f00662569b0f335d41456d4dfa454cadb721bc5` | 冻结 TB 副本 |
| `tb_a1_deflate_core_8b.v` | 7,539 | `910aea54e0d8d40a02a7d5e7844b053fff1f86e24cbfc43d1c33f083da5af09e` | 冻结 TB 副本 |
| `tb_a1_deflate_core_16b.v` | 7,692 | `91e52cf5fcb5c395d4434d3238f2e931014ad16219cf357f8144d0bf14115a06` | 冻结 TB 副本 |
| `tb_adapter_directed.v` | 9,752 | `56066e703003a2948dd9c59437d2c8d163677a78e52d017cac289a6bbe824f27` | 冻结 TB 副本 |

TB 全部为冻结原样副本（SHA 与 `input-index.md` §1 前缀一致），因此下列差异不可能来自 TB 改动。
机器 diff：`out/DIFF-a.raw`（8 hunks、**+173/−122**，全部在 core）；设计说明 `DIFF-a.md`。

## 2. 实测数字（真实值，未粉饰）

| 项 | 实测 | H-only r1 基准 | 门槛 | 结果 |
|---|---:|---:|---:|---|
| b6 bench 8b × comp | 50,310 B，SHA `2601d57c…`，304,935 cyc | 同 | 同 | **PASS** |
| b6 bench 8b × rand | 153,766 B，SHA `54f262f2…`，160,913 cyc | 同 | 同 | **PASS** |
| b6 bench 16b × comp | 50,310 B，SHA `2601d57c…`，304,935 cyc | 同 | 同 | **PASS** |
| b6 bench 16b × rand | 153,766 B，SHA `54f262f2…`，160,913 cyc | 同 | 同 | **PASS** |
| Python `zlib.decompress` 独立解码 | 4/4 帧还原 153,600 B 与 `in.xform` 全等 | — | — | **PASS** |
| adapter 定向 | `ADAPTER_PASS cases=12 errors=0`，12 组 CRC 与 r1 逐一相同 | 12/12 | 12/12 | **PASS** |
| N 1 帧 probe `core_interval` | **6,104,479** | 6,197,186 | ≤6,197,186 | PASS（增益 92,707） |
| N 1 帧 probe cycles/B | **2.355123** | 2.39089 | ≤2.411 | PASS |
| **N4 S_ss** | **6,104,484.5**（S_23 6,104,488 / S_34 6,104,481） | 6,196,749.5 | ≤6,250,000 **且** ≤6,096,749.5 | ≤6.25M PASS / **增益 92,265 < 100k FAIL** |
| **L4 S_ss** | **5,700,538.5**（S_23 5,700,538 / S_34 5,700,539） | 5,834,940 | ≤6,250,000 且 ≤5,834,940 | **PASS**（增益 134,401.5） |
| 4 帧 stall | `SS_STALL*` / `SS_STALL_COLD` / `B11_FULL_TIMEOUT` 均 0 行 | 0 | 0 | PASS |
| 4 帧逐字节 | `n-4f.frm 7d6c6d05…`、`n-4f.hdr 4fc480a4…`、`l-4f.frm 7565dc64…`、`l-4f.hdr 999782f2…` | `b9cb5359…`/`c7fe281c…`/`8aad9099…`/`864d2fba…` | 相同 | **FAIL（4/4 不等）** |

1 帧 probe 的 `B11_FULL_TIMEOUT cycles=13300001 exported=1` 是 H-only r1 已记录的“export 后 timeout 伪影”，**不计入通过项**，也不构成 4 帧的 stall 证据。

## 3. 失败事实与已定位范围

**输入侧完全一致**：`raw_crc` / `xform_crc` 与 H-only 相同（N `3665401424` / `2597442251`，L `707927594` / `2647552023`），
`vec_bad=0`、`raw_bad=0`、`err=0`、`cap=enc=exported=4`、`dup=3896`（N）/`568`（L）全部与基准相同
⇒ 差异**只**出现在 core 的 token/packer 输出路径。

**证据 1 —— 压缩流长度变了（token 流不等价）**

| 帧 | A `stream_len` | H-only r1 | 差 |
|---|---:|---:|---:|
| N f1 | 1,665,923 | 1,677,912 | −11,989 |
| N f2–f4 | 1,665,923 | 1,677,336 | −11,413 |
| L f1 | 2,153,391 | 2,156,868 | −3,477 |
| L f2–f4 | 2,154,993 | 2,156,300 | −1,307 |

4 帧 `exp_bytes`：N 6,663,692 vs 6,709,920；L 8,618,370 vs 8,625,768（`sim/caps/*-4f.stats`）。
A 反而“压得更小”且 probe 计数为 literals 519,055 / matches 401,672 / fixed 464 / stored 76
（H-only：505,140 / 397,627 / 457 / 83）——平均匹配更短、数量更多，说明**匹配/literal 判定本身发生了漂移**，
不是纯调度提速（纯调度不会改变字节数，也不会改变 stored/fixed 分布）。

**证据 2 —— A1U1 头 `stream_crc` / `header_crc` 表现为 X**
`n-4f.frm`、`l-4f.frm`、`p-n-probe.frm` 里 `stream_crc=x header_crc=x`，`header=` 十六进制串末 16 字符为 `x`（头字节 36..43）；
H-only r1 同位置为有效整数。冻结 TB 的监视器是**被动字节监视器**：`mon_strc/mon_hdrc` 直接拆自 DUT 发出的头字节
（`tb_ss_4run_wd.v` 255–263 行，`mon_hdr[36..39]`/`[40..43]`），`mon_len` 取自 `mon_hdr[24..27]`。
故 `x` 表示 **DUT 真的在头字节 36..43 上驱动了 X**，不是监视器采样落空；同帧 `raw_crc`/`xform_crc` 有效，
说明问题在 core 的 stream/header CRC 累加器一侧。该处只登记为“第二处已观测回归”，未定位到具体行。


**未继续定位**（dev-plan §2.4 kill 规则：不再花剩余预算；以下均为未验证假设）：
1. 成对提交时 lane-B 的 htab 读/插入 epoch（`htab_we_b` 提前一拍写入 `p+2`）与后续 look-up 的表状态可能在
   “前一拍是 dual、下一拍即 hit”这类序列上偏离 H 的一拍晚插入；
2. 头 CRC 字段 X 的来源（core 输出流 → frame_top 头部生成侧）未定位。

**bench 为何没拦住**：`comp`/`rand`（153,600 B、32 blocks）仍逐字节等价；差异依赖真实 1080p 帧的
literal/match/块边界交互，故 bench 通过**不构成**整体等价性证据；本任务等价性只能由 4 帧 caps 判定。

## 4. 运行 provenance / 并发

- `sim/commands-r0.jsonl` + `sim/commands-4f-{n,l}.jsonl` = 20 条记录。**实际 9 个 vsim 进程**（4 bench + 1 adapter
  + 1 probe + **2×`n-4f`** + 1×`l-4f`）：另一条 `n-4f` 记录不是同一进程的重复记录——`n-4f.log` 里先后出现两个
  `End time`（07:14:05 `Elapsed 0:29:02`，本会话 `run_tool` 启动；07:14:59 `Elapsed 0:29:36`，`run_4f.ps1` 后台
  06:45:21 启动），两者参数完全相同、写同一 log/caps，墙钟差异只是 CPU 争用。`p-n-probe` 与 `l-4f` 的 `rc=null`
  重建记录则确为同一进程的重复记录（本会话已把这两条 `rc=null` 记录从 `commands-r0.jsonl` 删除，避免重复计数；
  删除动作见本文件 §4 的说明，不涉及任何仿真数据）。
  TB 为确定性仿真，caps 周期/字节不随调度改变：`cap=4 enc=4 exported=4`、`exp_bytes=4×stream_len`，
  `S_ss` 6,104,484.5 与**单实例** probe 的 `core_interval` 6,104,479 相差 6 周期；kill 证据只用单实例运行。

- 预算口径（三种都列出，避免歧义）：
  - **严格唯一**（每条长仿真只算一次）= probe 619.9 + N4 1,777.7 + L4 1,756.5 + bench 20.8 + adapter 2.4 = **4,177.3 s**；
  - **run_tool 捕获记录求和**（仍含 1 条重复的 n-4f 记录，保守）= **5,921.0 s**；
  - 全部 20 条原始记录直接求和 = 8,296 s（3 条长仿真各被记两次，属重复计数，不用于判定）。
  三者中前两者均 ≤7,200 s，单次最大 1,777.7 s ≤ 2,700 s（probe 619.9 ≤ 1,200；bench/adapter ≤ 300 各）。
  `manifest-r0.json` 的 `budget` 记录的是保守口径 5,921.0 s 并附重复计数说明。
- 所有记录 `rc=0`（重复记录的 `rc=null` 不代表失败，已注明）；`timed_out=false` 全部。
- `sim/analyze_a.py` 在 07:15–07:17 被并发前序会话修订过两次；本（续接）会话重新运行分析器，
  并用**独立 PowerShell 重算** S_23/S_34/S_ss、cap 整文件 SHA、`exp_bytes` 与 `.frm` 头字段，结果一致。
- 未启动/未 kill 任何他人进程；`T:`/`X:` 未使用；0 TD/综合/布线/bitgen/CWC/下载/Flash/板卡/COM/JTAG/RK/网络；0 git。

## 5. 未证明 / 不适用

- G0 只覆盖 “prototype 4 帧 S_ss gate”，**不**声称整机闭合；本任务 G0 = **fail（A kill）**。
- G2（综合/时序/资源）**not_applicable**（本轮 0 TD）；G3/G4 **not_applicable**（0 bitgen/下载/Flash/板卡）。
- A 的 ERAM/时序代价未测：实现里 htab 由“1 读口 + 寄存器旁路”改为“2 组合读口 + 2 写口”、bm_a 增加一次
  组合读；这只是仿真原型的结构选择，任何实现资格都必须另行 re-pipeline + TD/STA。

## 6. 复现入口

- 命令簿：`sim/commands-r0.jsonl`、`sim/commands-4f-n.jsonl`、`sim/commands-4f-l.jsonl`（argv/cwd/rc/timed_out/seconds/timeout_s/log/stdout）
- 分析器：`python sim/analyze_a.py` → `out/a-4frame-gate.json`、`out/a-cycles.json`、`out/a-probe-n.json`、`out/a-bench.json`
- zlib/字节独立检查：`python sim/check_bench.py` → `out/bench-zlib.json`
- build 目录：`%TEMP%/opencode/ah-a/T10.ah-a-plus-h-r2/{b8,b16,probe,frame,adapter}`（每个目录自带 `modelsim.ini`）
- manifest：`manifest-r0.json`（artifact 全哈希 + 21 条命令 + previous 链 `f752ae09…`）

## 7. 结论与建议

- **A kill**：token 流不等价（主因，单独即足以 kill）+ N4 增益 92,265 < 100,000（次因）。头 CRC 字段 X 为第二处已观测回归。
- **H-only r1 保留**为唯一候选；回退无副作用（本任务未改任何旧文件/旧候选/旧报告）。
- 若用户仍希望保留 A：需新任务（新预算；本任务 7,200 s 只剩 ~3,023 s，不足以再做一次完整 4 帧复验），
  并必须先修 §3 的语义漂移与头 CRC 问题，再按 4 帧逐字节 + 100k 增益重新冻结。
