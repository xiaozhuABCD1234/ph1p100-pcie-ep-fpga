# T10.b18-b17-b 规划小结（2026-10-26）

**结论：合并包已冻结，状态 ready，等新开发执行；本轮没有写 RTL、没有仿真、没有构建、没有下载。**
无需你补充信息（`needs_user_input=false`），父任务 T10 仍未完成。

## 为什么合并

- b14 r1：B 相机在板上已确认活着（4,470 帧、1080p30、pix/line/crop 全对、`CAM_SEL` 在 bit12=1、
  Routed +0.110/0 违例），但**没有 PAXI 读修复**，所以每帧 timeout/retry/giveup，`enc/exported=0`。
- b17 r0：PAXI 原生修复离线全 PASS（16 字读回 16/16、地址 0/8/16…、`wstrb=0`、两整帧四 CRC+zlib、
  P1 三黄金、v6 273 B），Routed +0.002（偏薄），但用的是只有 A 路的顶，且 r1 上板时 FTDI 不在位。

两条链路都是同一个 b13 源头，缺陷互相独立，所以本轮直接把两者合成**一个候选**：b17 做基线，
只把 b14 的 B tap / `CAM_SEL=1` / B 字节时钟 SDC 叠上去。

## 冻结要点

- 唯一合并文件是 `p2_a1_board_top.v`（8 处改动，另有 C01–C18 一致性检查）；核用 b14 的（带 B 输出），
  PAXI/v6/重试三个文件保持 b17 原样，其余 6 个文件两边本来就逐字节相同。
- 状态包仍是 v6（273 B/67 字段），所选相机记录在 `cam_sysstat` 的 **bit12**（曾有 bit20 的错说法，已纠正）。
- SDC 用 b14 r1 那份（含 `mipi_b_byte_clk`，divide_by 4）；ADC 不变。
- 仿真必须过：B 几何全链 2,117,472 / 2,192 / 1 / 2,592,000 / enc=1 / exported=1 / 四 CRC+zlib；
  16 字原生读回；P1 三黄金；丢 1 个 R 的重试；v6 结构 + bit12=1。
- 构建：0 违例、WNS 目标 ≥+0.05（+0.003~+0.05 只能算诊断候选并记 caveat，<+0.003 或任何违例即停），
  1 次 bitgen + 1 次 CWC。
- 上板：先确认 FTDI/COM8，再**先下载、后开 COM8** 150 s；要求 timeout/retry/giveup 增量为 0、
  enc/exported > 0、至少 1 帧四 CRC+zlib。若还是 giveup，就保留 v6 里的失败 AR 地址并停下，
  不再下第二个比特流。
- 预算：开发 120 min / 60 calls；TD 3 会话、综合 ≤3、布线 ≤2、bitgen 1、CWC 1、下载 1、Flash 0。

## 入口

`workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b18-b17-b/`
（`dispatch.json`、`dev-plan.md`、`merge-spec.md`、`handoff.md`、`final-summary.md`、`input-index.md`、
`fpga-design-guide.md`）。
