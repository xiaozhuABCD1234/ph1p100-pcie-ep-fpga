# T10.b12-r1-last — 用户摘要（规划冻结）

- 结论：补充审核已经给出 **R1 有效反例**：FIFO 拒收 7 组数据（含 LAST）后，释放背压，RAW store 仍停在 WRITE，
  后续两个好帧未恢复；坏帧没有发布，但槽没有归还。根因是源码只 `fifo_ovf_cnt++`，没有生成本帧 loss-abort。
- 本轮任务：`T10.b12-r1-last`（新包，父 T10 仍 blocked）。只修 R1：
  1. camera 侧任何 FIFO 拒收 → sticky abort 请求，FIFO 有空间就推 abort beat；
  2. A1 侧消费无主 stray beat，避免 abort beat 被堵在 FIFO 头；
  3. store 侧 abort 压过同拍 LAST/写，abort+begin 同拍释放旧槽并接收新帧。
- 验收：
  - 独立反例 T2：故障帧不发布、故障槽 FREE、`writer=0`、`raw_abort_cnt>=1`、`raw_drop>=1`；
    恢复源序列精确 `[11,1000,1001]`，两好帧四 CRC + 严格 zlib 全过；
  - 新增 T3 同拍 LAST+abort、T4 同拍 begin+abort、T5 中写复位、T6 满槽并发、T7 SOF 拒收变体；
  - P1 三黄金逐字节不变；v4 仍 225 B；三帧小几何仍 PASS；full 两帧 129600/enc=2/exported=2；b11 read 九例不回归。
- 构建：Routed 0 违例；WNS 目标 ≥+0.05。若只能 +0.015 且最差路径仍在 vendor DDR PHY，规划预裁决接受并记 caveat；
  <+0.015 或任何违例即停。1 bitgen + 1 CWC。
- 板级：FTDI 当前不在位。先预检：不在位 → `board=blocked`，0 下载、0 COM8、不重试；在位 → 先下载后开 COM8，
  1 次 SRAM、150 s，目标 `enc_frames/exported` 增量>0 且 ≥1 帧四 CRC+zlib。若仍 1176 停点，只用 v4 判 H2/H4，本包不修 DDR/PAXI。
- 预算：开发 120 min/60 calls；TD 3 会话、综合≤3、布线≤2、bitgen 1、CWC 1、下载 1；不写 Flash、不 PCIe/RK、不批量删除。
- 不需要用户输入；板级 blocked 是本包的合法完成条件。
