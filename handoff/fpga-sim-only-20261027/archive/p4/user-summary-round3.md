# 阶段说明（2026-10-27 05:20）— INT.P4 round3 决策与板级承接

> 这不是最终收尾报告；最终结果与数字以 `handoff.md` / `final-summary.md` / 测试报告为准。

## 1. 当前事实
- INT.P4 round2 综合验收：**functional=pass、system=pass（G5 通过）、engineering=fail（G2 时序）**。
- G2 实测：**112 个违例端点 / 16770**，**WNS −0.637ns / TNS −69.776ns**；hold=0、IO 42/286、ERAM+CWC 39/300、资源在器件内、无未驱动 DUT 输入；route/bit/CWC/下载/Flash 均为 0。
- 相对 r1（330 端点 / −1.549ns / −271.427ns）已明显收敛；最差路径已从 ready 链转到 `algo_rowwin3` 行缓冲读路径（`u_gau/u_row/rb0_reg`，`u_front` 有同构副本）。
- TD 综合额度：round2 3/3、任务终身 6/6 用尽；第 4 次必须由规划书面授权。

## 2. 本轮决策
- **派发 round3（最后一次实际修复，repair #3/3）**，只修 G2：在集成目录新增 `algo_rowwin3_p4.v` 派生变体，把行缓冲读地址/使能做成寄存器边界，并按同一固定延迟对齐数据窗口与标记，使 token 序列、sof/eol/eof/abort、帧调度完全不变。
- 允许新增 `gray8_gaussian3x3_stream_p4.v` 等最少派生文件；**不改 `fpga/csi2/src/img/**` 原地、不改 b20/upstream、不加 CDC/异步 FIFO、不改时钟/约束**。
- **书面追加 TD 综合额度：round3 额外 ≤3 次，任务终身 ≤9 次**（依据用户"正常防死循环的 5 倍额度"原话，仍低于默认上限的 5 倍；不自动续期）。每次综合必须源集不同且有等价仿真证据，禁止同 netlist 重跑或只用属性实验。
- 布线 ≤1 次且仅在 G2 通过时；bitgen/CWC/下载/Flash 仍为 0。

## 3. 若 round3 仍失败
- INT.P4 保留 **⚠ 未通过**：functional=pass、system=pass、G2 fail（写真实数字）；**不会把 ⚠ 写成 PASS**，也不会写"时序已收敛/上板通过"。
- **板级集成线可以在 ⚠ 下继续**，但必须：交接首段注明"承接自 ⚠ INT.P4（G2 fail）"、把行缓冲读路径列为已知带出风险、板级 bit 用真实顶层独立计时并单独签核、若带违例做 bring-up bit 必须明确标注、TD/板卡/下载额度与 P4 分开冻结。
- 若 round3 通过：P4 记 PASS（仍附 G3/G4 not_run、HE 停顿敏感性、RK 待联调、IO 未约束等差距），route/bit 仍不冒充板级结论。

## 4. 板级集成工作线（本 run 不派发）
- 用户原话已原样记录在 `dev-plan.md` §9：P4 验收后沿同一工作线继续板级集成，复用已通 A/B 工程，接入真实相机/DDR/PCIe，补齐板级顶层、时钟复位/CDC、引脚约束、构建入口，完成整机 bit；下一目标是**先 B 后 A** 的真实单路压缩帧 PCIe 完整导出；推进度为先，长稳与非阻塞优化后置。
- 它**不是第 5 个包**，不改变本 run 的 1 目标/4 包计数；P4 收尾后由原规划作为**后续 run** 准备计划、额度与启动文本。
- 权威两仓：FPGA `xiaozhuABCD1234/ph1p100-pcie-ep-fpga`、RK `xiaozhuABCD1234/ph1p100-pcie-ep-driver`（本地 checkout 分别在 `D:/fpga/repos/` 下）；本 run 不提交/推送/fork。
