# 这一轮做完了什么（用户版）

- 目标：不接 PCIe 主机，只在板子上临时装一版“调试位流”，把板子内部的身份、帧序号、CSI 统计读出来。
- 做了什么：新做调试位流 → 发现/修复 PCIe 链路复位把探针“按住”的问题 → 重新构建 → 新位流用 SRAM 下载到板子（不写 Flash）→ 你在 ChipWatcher 里点了两次 Instant Trigger。
- 结果：**读通道通了**。身份 `FICP / RKA1 / v1.0` 命中，CTRL=`00000021`，帧序号在约 19 秒里前进了 300 帧，CSI good 从 190 涨到 234（bad/hdr/crc 都是 0）。
- 口径：这算 **Tier-1 通过**；G3 记 **partial（部分通过）**，因为 CSI good 在更早的样本对里有过不单调，长稳（G4）也没测。没有把“读到了”写成“全部通过”。
- 之前试过的命令行自动读回：4 次尝试（含 ASCII 路径、同一会话下载）都没拿到样本，已经停止；**以后只走 GUI 两样本**。
- 安全：全程只写 SRAM（掉电即消失），零 Flash、未改线/电源/相机、未推送。
- 你现在**不需要做任何操作**。板子保持现状即可；如果想恢复原状，断电 10 秒再上电（会清掉临时位流），或让我们重下旧位流（约半分钟）。
- 还缺：CSI good 的稳定性归因、长时间稳定、PCIe 主机侧（RKA1/端到端/RK）、三算法接入。

详细证据：`final-summary.md`、`handoff.md`、`test-reports/T11.runB-board-readback-r1-integrated.md`、`board-readback/candidate-manifest.json`（v11）。
