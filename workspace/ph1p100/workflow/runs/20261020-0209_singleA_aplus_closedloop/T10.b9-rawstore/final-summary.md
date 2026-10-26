# T10.b9-rawstore 收尾总结

> 状态：**已冻结、尚未执行**（2026-10-25 规划完成）。本文件在执行与综合测试返回后由原规划者补填"实际完成/未完成、唯一候选与 manifest、独立报告结论、真实样例、比率/资源/STA、上板缺项"。此刻不得当作 PASS 证据。

## 1. 冻结时的既定事实

- b8 板级：crop 全通（3300 整帧、`crop_groups=3300×518,400`、`geom_err=0`、`short=0`），`raw_pub` OR 恒 `0x2`（早期 2 帧后冻结），`raw_drop/cmp_drop/errors/enc_frames/exported/read_words=0`。
- 格式核对：480 beat/行、129,600 字/帧、2,592,000 B 全部整除，slot 容量与基址不重叠 → 排除"帧长/打包不匹配"。
- 静态已证实 4 个缺陷：F1 abort 过不了 CDC；F2 无空 slot 整帧冻结 + FIFO 静默丢数；F3 P2 读引擎 AF 弹出与 AR 握手解耦；F4 raw store `ddr_ready` 硬接 1。

## 2. 交付清单（执行后逐项填实）

| 项 | 要求 | 结果 |
|---|---|---|
| 状态包 v3 | ver=3、len=177、43 字段、单拍快照 | 待填 |
| F1–F4 | 修复 + 仿真可证 | 待填 |
| G1 仿真 | 全尺寸 2 帧 + 4 负例 + v3 快照 + P1 三黄金 | 待填 |
| G2 工程 | Routed 0 违例、WNS≥+0.05、TNS 0、hold 0；1 bitgen + 1 CWC | 待填 |
| G3 板级 | 1 次下载、90 s、四选一判定、三目标 | 待填 |
| 解码 | exported>0 时 44 B 头 + CRC + zlib | 待填 |
| 候选 | manifest + hashes 唯一 | 待填 |
| 独立报告 | 综合测试者按同一 manifest | 待填 |

## 3. 判定与轮数台账

- round0 首次验收：待填
- 同任务真实 FAIL 续原开发/原综合测试，最多三轮实际修复：待填
- 三维结果（functional/engineering/system）与 dimension=integrated：待填

## 4. 下一次准确启动/恢复文本

- 执行：`/fpga-orchestrator 执行：继续 T10.b9-rawstore（按 dispatch.json 派 fpga-dev）`
- 恢复（若会话失效）：`/fpga-orchestrator 恢复：D:\fpga\ph1p100\workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.b9-rawstore；本轮目标：<目标>`

## 5. 剩余主题

1. 若四选一判为 A/B（DDR 读通路）：下一轮独立冻结 PAXI 读时序/读超时看门狗与 slot 回收。
2. 若判为 C 且卡 `a1_busy`：查 A+ 帧顶启动条件与压缩使能。
3. 导出带宽：115200 下 2.6 MB 整帧传输偏长，后续单列评估。
