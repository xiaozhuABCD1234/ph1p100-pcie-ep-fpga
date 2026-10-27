### 判定：PASS

## 1. 基本信息
- task_id: INT.P2
- dimension: integrated
- round: 0
- run_id: 20261026-2138_fpga-integrated-delivery
- 输出目录: D:\fpga\ph1p100\workflow\runs\20261026-2138_fpga-integrated-delivery
- 实际工作树/候选根: D:\fpga\ph1p100\fpga\csi2\src\integrated_delivery
- 冻结 manifest: D:\fpga\ph1p100\workflow\runs\20261026-2138_fpga-integrated-delivery\INT.P2-r0-manifest.json
- manifest SHA256: b5073d559fb054b558ae58c9f5487717a8c4e3106339359ada7f8f9ab42ea110
- 候选文件:
  - fpga/csi2/src/integrated_delivery/aplus_pcie_egress_adapter.v (sha256 39301dc7598faaa3df5fb81748f53a82e9e346618c99ed766f442817f85ea71c)
  - fpga/csi2/src/integrated_delivery/tb_aplus_pcie_egress_adapter.v (sha256 30b069d6d2813fbffb4799f1aaab2484187aa20bdf725c6a24ca81127af8f896)
- 工具版本:
  - ModelSim (Intel FPGA Edition) vlog/vsim 10.5b (2016.10)
  - Python 3.11.5

## 2. 任务范围与规划冻结适用项
- 范围: A+ 压缩输出槽 → PCIe 发送后端描述符/长度/尾拍/完成/释放贯通；A1U1 与 R10F 关系；RAW 接收入口保留；RK 可复现样例与解码工具；RK 联调标待联调。
- 必要 G 层 (dev-plan): G0, G1, G2。G2 综合/STA 在本包标记延后至 INT.P4（manifest notes: "G2 synthesis/STA deferred to INT.P4"）。
- G3/G4: 本轮不适用（无板卡窗口/下载），记 not_run/not_applicable + awaiting_hardware。
- G5: 集成/发布部分延后至 INT.P4；本包仅做接口/材料/候选唯一性检查。

## 3. 三维检查清单与结果

### 3.1 functional
- RTL 编译 (vlog): 0 errors / 0 warnings — PASS
- 开发 TB `tb_aplus_pcie_egress_adapter`: TB_APLUS_PCIE_EGRESS_ADAPTER PASS — PASS
- 独立边界 TB `tb_independent_edge`: TB_INDEPENDENT_EDGE PASS (描述符非法拒绝、错误路径释放、held ACK 匹配/拒绝、取消) — PASS
- A1U1 解码工具 `a1u1_decode.py`: A1U1_DECODE OK (header CRC、stream CRC、zlib、尾部零填充、对齐) — PASS
- 独立 A1U1 校验 `independent_a1u1_check.py`: INDEPENDENT_A1U1_PASS + 全部 6 项变异拒绝 + 样例可复现 (hash 一致) — PASS
- A1U1 vs R10F 关系文档 `INT.P2-a1u1-r10f-relationship.md`: 分离、RAW 入口保留、src_sel=0 (DDR) — PASS
- 真实 PCIe 传输: 未进行 (RK 在队友处) — not_run + awaiting_hardware (blocked)

### 3.2 engineering
- 工作树/manifest/SHA 核对: 全部 production_inputs 与 tool_inputs 哈希匹配 — PASS
- 工具版本记录: ModelSim 10.5b, Python 3.11.5 — PASS
- G0 接口/单位: ALIGN_BYTES=4096、SLOT_BYTES=4096、dst 128B 对齐、db 4B 对齐、MPS code ≤5 — PASS
- G1 仿真/正反向/边界/恢复/反压: 开发 TB + 独立边界 TB 覆盖 — PASS
- G2 综合/STA/CDC/资源: 延后至 INT.P4 — not_run (awaiting INT.P4)
- 候选唯一性/回退: manifest SHA 绑定 — PASS

### 3.3 system
- 顶层连接: adapter 为描述符/控制脉冲桥，不实例化 ddr_frame_pusher；板级连线留待集成 — partial (interface defined, wiring pending)
- 时钟/复位域: 单时钟 RTL，复位初始化完整 — PASS (RTL level)
- 地址映射/数据通路连续性: src_sel=0 (DDR 压缩槽)、frame_bytes 4KiB 对齐、stream_len 精确、尾部零填充 — PASS
- 生产路径影响: RAW (R10F) 入口未被本包修改 — PASS
- 板级 (下载/复位/恢复/稳定性/性能): 无板卡窗口 — not_run + awaiting_hardware
- 发布/交接: manifest、解码工具、样例、关系文档齐全 — PASS

## 4. G 层结果
| G 层 | 结果 | 说明 |
|---|---|---|
| G0 | pass | 接口/单位/参数冻结与 RTL 一致 |
| G1 | pass | 仿真正反向/边界/恢复/反压 |
| G2 | not_run | 综合/STA/CDC/资源延后至 INT.P4 |
| G3 | not_run / not_applicable | 无板卡窗口/下载，awaiting_hardware |
| G4 | not_run / not_applicable | 长稳/性能后置，awaiting_hardware |
| G5 | partial | 接口/材料/候选唯一性完成；完整集成延后 |

## 5. 实际执行命令与退出码
1. `vlog aplus_pcie_egress_adapter.v tb_aplus_pcie_egress_adapter.v` (ModelSim 10.5b) — exit 0, 0 errors/0 warnings
2. `vsim -c -do "run -all; quit" tb_aplus_pcie_egress_adapter` — exit 0, TB_APLUS_PCIE_EGRESS_ADAPTER PASS
3. `python a1u1_decode.py evidence/a1u1_sample.a1u1 4096` — exit 0, A1U1_DECODE OK
4. `python independent_a1u1_check.py` — exit 0, INDEPENDENT_A1U1_PASS + 6 mutations rejected + reproducible hash match
5. `vlog ... tb_independent_edge.v` + `vsim ... tb_independent_edge` — exit 0, TB_INDEPENDENT_EDGE PASS
6. manifest hash 校验脚本 — 全部 match, 无漂移

工作目录:
- RTL: D:\fpga\ph1p100\fpga\csi2\src\integrated_delivery
- 仿真: D:\fpga\ph1p100\workflow\runs\20261026-2138_fpga-integrated-delivery\test-reports\INT.P2\devtb_run 与 .../INT.P2 (work)

## 6. 独立复现与判据
- 与开发不同的判据 1: 独立边界 TB (tb_independent_edge.v) 覆盖非法描述符拒绝、pcie_err 释放、held bad/good ACK、取消、TX 错误；发现目标缺陷能力: 能检出描述符校验遗漏、ACK 匹配错误、释放缺失。
- 与开发不同的判据 2: 独立 A1U1 解析 (independent_a1u1_check.py) 重新计算 header/stream/xform/raw CRC、zlib 长度、尾部零填充、对齐尺寸，并做 6 项变异负对照；全部拒绝。
- 样例可复现: 重新生成 a1u1_sample.a1u1 哈希一致 (0cbba9a65fbfe06eee52201146c5eb362a60493c849a536aadaeab0f1fb8a8df)。

## 7. 缺陷与触发条件
- 本轮未发现 RTL/工具缺陷。
- 已知外部阻塞: RK 真实 PCIe 传输未联调 (RK 在队友处)；文件回放/接口仿真不等于真实 PCIe 通过，已标待联调。
- 已知延后项: G2 综合/STA/CDC/资源 (INT.P4)；板级 G3/G4。

## 8. 输入漂移检查
- 测试前后 manifest 及全部 production_inputs/tool_inputs 哈希一致，无漂移。
- 未拼接不同输入 PASS。

## 9. 未测项与下一动作
- 未测: 真实 PCIe 传输 (RK)、G2 综合/STA、板级 G3/G4。
- 下一动作: 待 RK 联调完成后执行真实传输验证；G2 在 INT.P4 统一完成。

## 10. 回退入口
- 保留 b18/b19/b20 及历史候选/manifest；本包候选可按 manifest SHA 回退。

## blocked
- RK 真实 PCIe 传输 pending (待联调) — awaiting_hardware

## retest (for return)
- required_dimensions: functional, engineering, system
- required_checks: rtl_compile, tb_sim, a1u1_decode, independent_edge_tb, independent_a1u1_check
- report_paths: test-reports/INT.P2-r0-integrated.md
- input_status: same
- reuse_decision_paths: INT.P2-r0-manifest.json
