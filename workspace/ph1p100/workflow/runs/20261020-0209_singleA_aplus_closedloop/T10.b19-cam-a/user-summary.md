# T10.b19-cam-a 规划小结（2026-10-26）

**结论：A 相机试跑包已冻结，状态 ready，等新开发执行；本轮没有写 RTL、没有仿真、没有构建、没有下载。**
无需你补充信息（`needs_user_input=false`），父任务 T10 仍未完成。

## 为什么这样切

b18 已经用 **B 相机**跑通完整真实帧：1920x1080、`raw_len=2,592,000`、`stream_len=2,594,706`、
四 CRC + zlib 全过，`exported=1 / enc=2`，`ar=r=rlast=340,767`，`timeout/retry/giveup=0`，
`sysstat` bit12=1。证据在 `T10.b18-b17-b/r0/board/captures_full/`。

A 上次在 b13 是 `pix_beats=0`，但那个比特流没有 PAXI 读修复、也没有重试，不能据此判 A 坏。
所以本轮用**最便宜的决定性试验**：b18 的 11 个源文件原样保留，只把 `CAM_SEL` 从 1 改成 0，
其他 PAXI x8/mask=0/retry/R1/v6/B 代码都不动。

## 冻结要点

- 唯一 RTL 改动：`p2_a1_board_top.v` 第 97 行 `localparam CAM_SEL = 1'b0;`；其余 10 个文件、
  SDC、ADC 与 b18 逐字节相同（哈希写进 dispatch）。
- 两个相机核仍都实例化，只切换选择分支；B 代码保留（不选通），SDC 同时约束 A/B 字节时钟。
- 仿真必须过：A 几何全链 `2,117,472 / 2,192 / 1 / raw_len 2,592,000 / enc=1 / exported=1 /
  四 CRC+zlib`；16 字原生读回；P1 三黄金逐字节；丢 1 个 R 重试；v6 273 B/6/67，
  **bit12=0、bit20=0、lane sticky=4'hF**；真实顶层 stub 证明 A 签名进 `u_a1`。
- 构建：Routed 0 违例，WNS 目标 ≥+0.05；+0.003~+0.05 只能算诊断候选并记 caveat，
  <+0.003 或任何违例即停；1 次 bitgen + 1 次 CWC，不复用 b18 的 bit/CWC。
- 上板：先确认 FTDI/COM8，**先下载（仅 1 次）**，随后按一次板载复位 R14（`sys_rst_n`）做
  **复位对齐**（重启两个相机核、计数归零），再开 COM8 **300 秒**。300 秒是因为最坏 stored 帧
  2,594,706 B 在 115200 下要约 **225 s**，150 秒会截断。
- 判定：bit12=0；v6 273/6/67、`bad_xor=0`；A 的 pix/line/frame >0；enc/exported >0；
  至少 1 帧四 CRC+zlib；timeout/retry/giveup 不增长。
- **若 A 仍无像素**（pix/line/frame 全 0）：保留 300 秒原始采集和 v6 状态，判
  `blocked_A_no_pixels`，结论归 A 前端/硬件；不再重建、不再下第二个比特流、不再补采。
  若现场无法按复位键，记录 `reset_pulse=no`，缺帧按 blocked 处理，不判 A 坏。

## 预算

开发 90 min / 50 calls；TD 2 会话、综合 ≤2、布线 ≤1、bitgen 1、CWC 1、下载 1、Flash 0；
综合测试者 45 min / 30 calls。三轮实际修复只用于同一候选的真实失败。

## 入口

`workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b19-cam-a/`
（`dispatch.json`、`dev-plan.md`、`handoff.md`、`input-index.md`、`fpga-design-guide.md`）。
