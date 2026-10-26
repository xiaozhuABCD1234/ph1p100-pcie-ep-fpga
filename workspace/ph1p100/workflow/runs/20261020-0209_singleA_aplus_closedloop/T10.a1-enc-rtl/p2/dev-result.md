# T10.a1-enc-rtl — P2 开发结果（离线 RTL + 仿真）

状态：**ready_for_test**（本地 P2 回归 PASS；尚未经过独立综合测试者）
日期：2026-10-20｜run：`20261020-0209_singleA_aplus_closedloop`｜候选：纯新增 codec 文件
证据根：`workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.a1-enc-rtl/p2/`

## 1. 交付内容

| 类型 | 绝对路径 |
|---|---|
| RTL | `upstream/ph1p100-pcie-ep-fpga/rtl/ep_side/codec/a1_deflate_core.v` |
| TB | `upstream/ph1p100-pcie-ep-fpga/sim/tb/codec/tb_a1_deflate_core.v` |
| 用例生成 | `upstream/ph1p100-pcie-ep-fpga/tools/codec/a1_p2_gen.py` |
| 独立验证 | `upstream/ph1p100-pcie-ep-fpga/tools/codec/a1_p2_verify.py` |
| 回归入口 | `upstream/ph1p100-pcie-ep-fpga/tools/codec/run_p2.ps1` |
| 结果 | `p2/result.json`、`p2/result.md`、`p2/CANDIDATE-MANIFEST.json` |
| 日志 | `p2/logs/{vlog,gen,verify,exitcodes,run_p2.console}.log` |

## 2. 实现要点（与 format-v1 对齐）

- 输入：transform-domain 字节流，`in_sop` / `in_blk_end` / `in_stream_end` 分帧；块 ≤4800 B。
- 输出：标准 zlib 单成员，`0x78 0x9C` + DEFLATE（fixed `BTYPE=01` / stored `BTYPE=00`）+ 大端 Adler-32。
- **真实 LZ77**：1024 项 3 字节 hash（16-bit 块标签避免跨块陈旧命中）、块内 2048 B 窗口、greedy 3..258、单候选。实测解码 token 合计 **19,388 个 match、19,573 个 literal**；纯 literal 未被当作 LZ77。
- fixed-Huffman：RFC1951 标准 literal/length/distance 码表；code+extra 合并推入；LSB-first 位打包；每块 EOB。
- 块级 stored 回退：`stored_bits = 3 + align + 32 + 8*len`；候选位计数达到/超过 stored 即发 stored。为防止不可压缩块先做完整候选，增加**保守提前判定**：`cand_bits + 8*(剩余字节) >= stored_bits` 即回退（stored 永远合法，代价是可能放弃略优的 fixed）。该判定使随机块在约 80–100 B 后回退。
- 尾块/尾 bit：候选位流按块从 bit0 打包、回放时接入全局位累加器；最后一块后补零到字节边界，再写 Adler；`out_last` 只标最后字节。
- 反压：输入 ping-pong 双块（每块再复制一份供 current/ref 读）；输出 16×9 FIFO；`ready/valid` 全程握手。复位/`abort` 清块状态、位累加器、FIFO、块标志；`done` 不会在 abort/reset 后置位。
- 状态：`stat_blocks/fixed/stored/literals/matches/cand_aborts/stall/max_match/max_dist`。

## 3. 验证结果（同一候选、同一输入）

- 用例：13 个（6 个 P1 positive 小/中帧 + 7 个 P2 边界/吞吐），全部 `PASS`。
- 双解码：Python zlib 1.2.13 与 `a1_inflate_strict.py` **同时**解开；13/13 `mismatch=0`，`eof=True`，`unused_data==b''`。
- Bayer：6 个 P1 帧经 `a1_ref.inverse_frame` 还原，raw 逐字节 0 mismatch。
- 负例：80 项全部按预期拒绝（截断 1/2/5 B、坏 Adler、尾随字节、非法 dynamic BTYPE、坏 stored NLEN；zlib 同时失败）。
- 边界：`dist=2048,len=258` 命中（`stat_max_dist=2048`、`stat_max_match=258`）；`len=3,dist=4`；8×5 奇数 H 尾块；16×8 多块；4800 B 不可压缩 stored；1920×64 共 32 块。
- 真实 match 存在：fixed 块解码 matches >0（合计 19,388），非纯 literal。
- 反压/间隙：`p2_frame_16x8` 在 `BP=1` 与 `BP=1,GAP=1` 下均完整解码 0 mismatch。
- abort/reset：块中 abort 与块中同步复位后 `done=0`、`out_last=0`；输出被严格解析器以 `E_TRUNCATED` 拒绝，未发布完整帧。
- 编译：ModelSim `vlog 10.5b` — **Errors: 0, Warnings: 0**（`p2/logs/vlog.log`）。vsim 有 5 条 `$value$plusargs` 兼容性警告（工具 PLI 提示），不影响结果。

## 4. 服务率（仿真实测，非理论值）

条件：`out_ready=1`、输入无 gap、187.5 MHz、1920×64（32×4800 B = 153,600 B）。

| 用例 | cycles | cycles/B | MB/s | ≥77.76 | ≥97.2 |
|---|---:|---:|---:|---|---|
| 压缩友好 ramp | 330,023 | 2.149 | **87.27** | 是 | 否 |
| 不可压缩 LCG | 161,477 | 1.051 | **178.35** | 是 | 是 |

- 1080p RAW10 等效：2,592,000 B；87.27 MB/s → **29.70 ms/帧（33.7 fps）**，满足 30 fps（33.33 ms）但**未达** 97.2 MB/s 余量目标（26.67 ms）。
- 随机块走 stored，1 B/周期；fixed 路径为 tokenize（约 1 cycle/B）+ 候选回放（1 B/cycle）。上表是模块持续接受/输出字节的实测周期，不含 DDR/PCIe 或帧级 Bayer 开销；不等同于整机吞吐。

## 5. 复现

```powershell
powershell -ExecutionPolicy Bypass -File upstream/ph1p100-pcie-ep-fpga/tools/codec/run_p2.ps1
```

脚本：`subst X:`（中文路径）、`vlib/vlog`、逐用例 `vsim -c`（单 TB 300 s 上限）、独立验证、manifest。退出码与命令见 `p2/logs/exitcodes.txt`。

## 6. 非声明

- 全部输入为 **synthetic**；物理 Bayer 相位/真实 RAW 仍 unknown。
- 未上板、未接 PCIe/RK、未下载/Flash、未做 TD 综合/STA/G2（属 P4）。
- 未仿真完整 1080p 帧（P3）；本包只到模块级流。
- Verilator：本机 `verilator_bin.exe` 在此 shell 下以 `0xC0000139` 退出（DLL 入口问题），未取得 lint 结果；按计划以 `vlog Errors:0/Warnings:0` 作为编译门槛，**明确豁免 Verilator lint**。RTL 保持可综合风格；其中块缓冲使用组合读（P4 需按 ERAM 映射改为同步读流水）。
