# T10.b10-b9-fix r1 说明（给用户）

## 这一轮做什么

r0 的离线修复是成功的：B9-01 状态包/帧出队互锁、B9-02 描述符队列越界/计数覆盖、B9-03 1080p 四槽地址重叠都已修好并通过针对性回归，P1 三黄金样例逐字节一致，R2/R3 也有结论（R1 与 3 连续真实帧仍 `not_covered`）。

但 r0 没能交付候选：TD 综合 3/3、布线 2/2 用尽，最后两份网表所用的源码里有一个开发期误删的 `wire [39:0] crop_pix`（变成 1 bit）缺陷；该缺陷在 P1 回归时被发现并修复，修复后 P1 三黄金复测一致，但**修复后的源码没有来得及再综合**。所以 r0 没有有效 bit/CWC，下载 0/2。

**r1 不再改 RTL**，只做三件事：

1. 用当前已修复源码**重建一次候选**：综合 1 次 + 布线 1 次 + 1 bitgen + 1 CWC；要求 Routed 0 违例、WNS ≥ +0.05 ns，bit/CWC/BID 与源码哈希绑定。
2. **上板一次**：COM8 关闭时先下载（第 1 次，累计 ≤2），下载成功并释放 FTDI 后再开 COM8 采 180 s；解析 v3 状态包，要求 `raw_pub`、`enc_frames`、`exported` 三者相对首包的增量都 >0；若有导出帧，按 44 B 头 + stream CRC + zlib 解码，至少 1 帧解出 1920×1080。
3. **可选**（板级证据落盘后、时间允许）：补 R1 丢 LAST 定向用例、3 连续真实帧用例（复用 `tb_p1_chain` 相机驱动）。这两项只作证据，不改候选、不重综合、不重下载。

## 怎么算通过

- **工程（硬门）**：布线 0 违例、SWNS ≥ +0.05 ns、TNS 0、hold/period 0；1 bitgen + 1 CWC 且 bit 与编译后调试 bit 字节一致；manifest 绑定真实哈希。
- **板级（主门）**：先下载后监听；≥2 个合法 v3 包；`raw_pub`/`enc_frames`/`exported` 增量均 >0；≥1 帧 44 B 头 + stream CRC + zlib 解码通过。
- **部分达成**（有状态包但增量不全或帧未解出）：记 ⚠，保留候选与证据，写明卡点，**不二次下载**。
- 静默（0 B）或下载失败：立即停，保留全部日志/原始流。

## 不做什么

不改 RTL/参数/SDC/引脚/端口；不动 44 B 帧头、流 CRC、zlib、UART 协议；不帧内插包；不写 Flash；不换板/改线/改电源/改相机；不第二次下载；父 T10 不置 done。

> 注意：`camera_a1_uart_top.v` 里 `// T10.b10 R1:` 注释是 r0 已回退尝试的历史注释，本候选**没有** R1 功能修复；r1 manifest 会如实写明，避免被误读为已覆盖 R1。

## 授权与预算

- 开发：90 分钟 / 50 次工具调用。
- TD：1 个会话 / 60 分钟；综合 1、布线 1、bitgen 1、CWC 1。
- 下载：1 次（累计 0/2 → 1/2）；Flash 0。
- 综合测试者：45 分钟 / 30 次调用；不重跑 TD、不下载。

## 交付文件

- 计划/口径：`dev-plan.md` §7（r1 冻结流程）、`handoff.md`、`fpga-design-guide.md`
- 派发：`dispatch.json`（r1 当前），r0 原件保留为 `dispatch-r0.json`
- r0 证据：`result-r0.md`、`lessons-r0.md`、`CANDIDATE-MANIFEST-b10-b9-fix-r0.json`
- r1 待回填：`CANDIDATE-MANIFEST-b10-b9-fix-r1.json`、`r0/artifact-hashes-r1.txt`、`r0/td/a1_board.{bit,cwc}`、`r0/board/captures_r1/**`、`result-r1.md`
- `final-summary.md` 当前为 **r1 已冻结、未收尾** 状态，测试者独立报告后再由原规划更新。
