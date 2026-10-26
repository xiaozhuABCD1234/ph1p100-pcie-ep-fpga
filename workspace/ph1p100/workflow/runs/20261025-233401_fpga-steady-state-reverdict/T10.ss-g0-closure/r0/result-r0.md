# result-r0 — `T10.ss-g0-closure`（开发 r0）

- 任务：P3 G0-only 1080p30 收口；硬门槛 G0=77.76 MB/s / 6,250,000 cycles @187.5 MHz；G25 仅参考、不降档。
- 结论：**`G0_feasible_for_scope`**（comp 向量代理 + slot-free + fast sim sink + 行为 DDR + per-stream；`proxy_not_worst`）。
- 状态：`ready_for_test`；stopped_modifying=true；active_commands=0；无 TD/综合/布线/bitgen/板卡/COM/JTAG/RK。

## 1. 实际运行（全部为 4 帧全尺寸，除 v1 单帧复验）

| run | 配置 | 实际墙钟 | 结果 |
|---|---|---:|---|
| R0 | gradient / P1 sink 187.5 MHz / slot-free / .dec | 937.6 s | 逐值复现 P1：`t_exp(1)=6,766,454`、`t_exp(2)=11,443,989`、`S_ss=4,677,535`、`exp_bytes=160,136`、`cap_bytes=160,312`、`cycles=20,801,058`；`control_pass=true` |
| R1 | gradient / 2 GHz / slot-free | 1056.1 s | `S_ss=4,677,531`（−4）；tail 480,930→80,160；`L_cold=6,365,664` |
| R2 | gradient / 2 GHz / strict-serial | 1111.9 s | `S_ss=6,365,622.5`；overlap penalty 1,688,091.5（36.09%） |
| R3 | comp 代理 / 2 GHz / slot-free | 1316.5 s | `S_ss=5,928,286` → 81.9799 MB/s / 31.628 fps；G0 +5.427%；tail 1,697,820 恒定；无 drop/stall |
| v1 | comp 代理 / check-only（2M cycles 截断）/ 修正后 TB | 91 s | `SS_VEC_MATCH bad=0 checked=518400 drv_groups=518400`（只读自检；未导出，非 timing run） |
| R4 | comp / strict-serial | **未运行** | 90 min 仿真墙钟上限；serial comp 列用 `assumed=R3+(R2−R1)` |

累计全尺寸 vsim = 4（≤5）；累计仿真墙钟（含 v1 与被中止的两次 v1 试跑）≈86.8 min（≤90 min）。每次 `vsim` 2700 s 硬超时，实际均未触发。

## 2. 关键实测与算术（独立于报告可复算）

- R3：`S_23=5,928,283`、`S_34=5,928,289`、band 6 cycles（0.0001%）；`S_ss=5,928,286`；`C=4.86e8/S_ss=81.9799 MB/s`；`fps=31.628`；G0 margin +5.427%；`f_req_0=177.849 MHz`。
- R3 计数：`cap=4 enc=4 exported=4 read=518400`、`raw_drop=cmp_drop=dup=geom=err=wd=0`；`exp_bytes=3,395,456`（payload）、`cap_bytes=3,395,632`（payload+4×44 头）；每帧 stream 848,864 B。
- R3 tail：1,697,820×4 恒定（<0.5·S_ss），`sink_limited=false`；实测导出率 ≈93.8 MB/s（848,908 B / (1,697,820/187.5e6)）。
- 容量/tail 关系：sink 从 18.75 MB/s 提到 2 GHz 只改变 `L_cold`（6,766,434→6,365,664）与 tail（480,930→80,160），`S_ss` 几乎不变（4,677,535→4,677,531）——常数 tail 在帧间差中抵消。
- 口径：`S_ss=(S_23+S_34)/2`；`L_cold` 绝不当作 `S_ss`（负对照 NEG-02）。
- A2 冻结算术：`6,421,414−6,250,000=171,414` cycles（2.6694% of A2；2.859% of core 5,995,029.375）；`f_req_0=192.642 MHz`；`f_req_25=240.803 MHz`（参考）。
- 内容代理：`in.hex`（SHA `edbfdeae…f9849`）→ 逆 PREP/PRED → raw（SHA `9498c16c…585b`）→ DUT 正向变换；Python mismatch=0；R3 导出头 `raw_crc=3613527589`、`xform_crc=3038348232` 与期望逐值相等，`header_crc` 自洽。
- 代理局限：`proxy_not_worst`；A2（assumed 6,421,414）仍 −2.669%，A3（assumed）过；全内容 `not_proven`。
- sink：R3 payload 848,864 B/帧 → 25.47/33.95 MB/s@33.333/25 ms；冻结 raw 口径 2,594,750 B/帧 → 77.84/103.79 MB/s；实测导出率 ≈93.7 MB/s，tail 恒定，`sink_limited=false`。

## 3. 局部检查/可复现

- `python sim/prep_content.py`：`forward(inverse(tiled))==tiled`（0 mismatch），生成 `comp_raw.hex`/`comp_vec.hex`。
- `python sim/verify_inputs.py`：P1/P2/comp 向量 8 个保护输入 0 drift；12 个 DUT 源与 P1 manifest 0 mismatch。
- `python sim/run_g0.py compile|r0|r1|r2|r3|v1|reparse|analyze`：每步记录 argv/cwd/rc/秒/超时到 `sim/commands.jsonl`；work 库/INI/日志独占 `%TEMP%\opencode\ss-g0`。
- R0 控制是派生 TB 的机械证据：所有 P1 4 帧值逐值相等。

## 4. 未做/边界

- R4 未跑（预算），comp strict-serial 只是 `assumed`；不得声称“严格串行也过 G0”。
- 未做 TD/综合/布线/bitgen/CWC/下载/Flash/板卡/COM/JTAG/RK/PCIe；无真实 115200；无 DDR sustained/PAXI 争用；无自然图像/低照/噪声；双核共享 PAXI/Routed 时序 `unproven`。
- R3 原日志 `SS_VEC_MATCH bad=691132` 是修正前 TB 自检的分组差一 bug（TB-only），已在 `src/DIFF.md` §7 披露；修正后 v1 给出 bad=0，DUT 端到端 CRC 独立证明内容等价。
