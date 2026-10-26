# 需要用户决定：T10 G2 保持 ⚠ / 授权 r5 架构重排 / 转板级

日期：2026-10-20｜run：`20261020-0209_singleA_aplus_closedloop`｜task：`T10.a1-eng-freeze`

## 当前事实

- **G0/G1 PASS**：P2 13/13、P3 20/20、0 mismatch、`vlog 0/0`；1080p p1d1 103.892 MB/s；P2 comp 81.084 MB/s。
- **G2 FAIL**：r4 S1 WNS -2.107 ns / Fmax 134.409 MHz；S2 WNS **-2.446 ns**、TNS -183.480 ns、Fmax **128.551 MHz**、388/12,201 端点违例；两次综合均未 route。
- 无 Routed、无 bit/CWC、无 Flash/下载、未上板。
- 唯一候选：core `d76f77ed…1a0d`，frame `3c32803b…`，manifest `CANDIDATE-MANIFEST-r4.json`。
- r4 预算 2/2 综合、0/1 布线已用尽；**r4 FAIL，不自动开 r5**。

## 技术判断（规划，不写 RTL）

1. 局部补丁已接近极限：r0 84.7 → r1 109.3 → r2 109.6 → r3 129.8 → r4 S1 134.4 / S2 128.6 MHz。每轮拆掉一条 7–8 ns 路径，下一轮又暴露另一条（abort → htab → packer）。
2. r4 的 TNS 从 -417.972 改善到 -183.480、违例端点 508→388，结构在变好；但 S2 WNS 仍 -2.446 ns，新路径 `len_r → lval/ltot → left_shift → cstage/accw → cmem` 为 11 级 7.578 ns，距 5.333 ns 还差约 2.25 ns。
3. **建议架构级重排 candidate packer / 输出级**，而不是再做一条局部预取：长度/距离码与 extra bits 寄存化；`left_shift` 与 `cstage/accw` 拆 2 级；`cmem` 写数据前寄存；packer 与输出间加 4–8 项 skid/FIFO；块尾/abort/commit 控制与数据路分离。
4. **吞吐红线**：必须保持每符号 1 cycle，不能用“每符号多周期”FSM 换时序。当前 1.8047 cycles/B，77.76 MB/s 预算 2.4113 cycles/B，只有约 0.6 cycle/B 余量；2 cycle/符号会把 match-heavy 打到 77.76 以下。
5. **187.5 MHz 可行性**：资源不是限制（LUT ~11k / ERAM 4/300 / DSP 0），2 级流水 + 寄存输出有希望，但需 2–4 次综合迭代和每步吞吐复核，不能承诺一次成功。若 r5 后仍 >1 ns，需重新评估微架构（更宽并行 packer / 分离 match 与 packer 的弹性缓冲），而不是继续微调。规划不自行降频。

## 请选择

**A. 保持 ⚠，停止 G2 时序收敛（按现行规则最稳）**
- T10 记 3/4 PASS + 1 ⚠，不称完成；保留 r4 候选/证据。
- 转需求二/三板级前置（仍需板窗/真实 RAW/你的下载授权）。

**B. 授权 r5 架构级 packer/输出级重排**
- 建议预算：**3 会话 / ≤150 min**，综合 ≤3、布线 ≤1；同 187.5 MHz，不放宽、不 false path/multicycle、不 seed sweep。
- 需你原话明确：“授权 `T10.a1-eng-freeze` r5，TD 预算 3 会话/150 分钟”。
- 范围：只改 `a1_deflate_core.v`（必要时 `a1_frame_top.v` 纯流水适配）；不改协议/端口/帧语义/CRC/长度/abort/Bayer；每步复核 P2/P3 与 ≥77.76 MB/s。

**C. 只做离线架构方案/评审**
- 不写 RTL、不构建；输出 packer 流水/吞吐预算文档，供后续决策。

**D. 转板级需求二/三（仅在你到场且板窗可用时）**
- 注意：当前**没有 Routed A+ bit**，不能做 A+ 板上验证；只能先做基线采集/真实 RAW 导出前置。
- 最小前置：
  1. 板窗与你在场；供电、JTAG/下载器、相机/镜头、存储/导出介质可用。
  2. **一次明确的 SRAM 下载授权**（仅现有生产 B01 bit；不生成/不改 bit，不做 Flash/efuse/SPI/svf）。
  3. 非 PCIe 大块导出通道确认（UART/以太网/其他）及主机接收/校验脚本；无确认通道则导出仍 blocked。
  4. 真实 ROI X/Y/SKIP、物理 Bayer 相位、曝光/帧率确认；先片段后整帧，记录 CRC/长度/哈希。
- 本轮不派下载、不假设板窗。

## 恢复入口

- `dev-plan.md §14`
- `handoff.md §11`
- `final-summary.md §12`
- `T10.a1-eng-freeze/p4/result-r4.md`
- `T10.a1-eng-freeze/r4/reports/syn_gate_timing_s2.rpt`
- `T10.a1-eng-freeze/CANDIDATE-MANIFEST-r4.json`

未得到你的明确选择前，规划不派 r5、不再消耗 TD 会话、不下载、不上板。
