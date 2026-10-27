### 判定：FAIL

- task_id: INT.P1
- dimension: integrated
- round: 0
- candidate_root: fpga/csi2/src/integrated_delivery
- manifest_path: D:\fpga\ph1p100\workflow\runs\20261026-2138_fpga-integrated-delivery\INT.P1-r0-manifest.json
- manifest_sha256: (run-local manifest, sha256 not separately recorded; production/test input hashes verified below)
- 工具版本: Python 3.11.5; ModelSim Intel FPGA Edition vlog/vsim 10.5b; TD/板卡未调用

## 1. 范围与 G 层

- 规划冻结适用项：functional/engineering/system 均为必须；G0,G1,G2 必须；G3/G4 本轮不适用（无板卡窗口/下载）；G5 部分。
- 本包 RTL/时钟/IP/存储/地址/板上行为相关，要求真实 DUT、最终 STA/CDC/资源与候选绑定、真实硬件恢复/稳定性/性能。本轮无板窗，G3/G4 记 not_run/not_applicable + awaiting_hardware。
- 时序门槛：clk_a1 WNS/TNS≥0、hold≥0、0 违例；资源在器件内；ERAM+CWC≤300（本轮未执行综合，记未测）。

## 2. 输入与漂移检查

- manifest production_inputs 全部哈希一致：frame_good_publish_cancel.v, integrated_input_processing_top.v, raw10_sample_vector_to_packed.v, tb_raw10_packer.v。
- manifest test_input_entries 全部哈希一致：golden_input_processing.json, verify_report.json。
- 未发现输入漂移；测试期间未修改生产文件。

## 3. Functional 结果：fail

通过项：
- `python tools/integrated_delivery/raw10_pack.py`：exit 0，输出 `RAW10_PACK PASS`（10000 随机向量 roundtrip bad=0；direct 4x10 vector != packed）。
- `python tools/integrated_delivery/verify_input_processing.py`：exit 0，输出 `INT.P1_VERIFY PASS`（pack roundtrip ok=true；gray/gauss/he len=192；HE 第二帧使用第一帧 LUT；direct vector != packed）。
- `python parallel/algorithms/image_algorithms_ref.py --selftest`：exit 0，输出 `IMG_ALGO PASS`（22 项）。
- 独立 ModelSim TB `tb_raw10_packer_strong.v`（200 随机向量，Python oracle 期望字）：编译 exit 0，仿真 exit 0，输出 `TB_RAW10_PACK_STRONG PASS`。
- 独立 ModelSim TB `tb_frame_good_publish_cancel.v`（修正副本，3 个场景：正常发布、abort 与 suffix 同拍优先取消、缺 CRC 取消）：编译 exit 0，仿真 exit 0，输出 `TB_FRAME_GOOD_PUBLISH_CANCEL PASS`。
- 修正副本 smoke `tb_integrated_top_smoke.v`（RAW 模式路由、packed 输出）：编译 exit 0，仿真 exit 0，输出 `TB_INTEGRATED_TOP_SMOKE PASS`。
- 修正副本 `tb_integrated_gray.v`（灰度模式 16x12 ramp，首拍 `0x03020100`）：编译 exit 0，仿真 exit 0，输出 `TB_INTEGRATED_GRAY PASS`（m_valid_count=5）。

失败/缺陷：
- D1：`fpga/csi2/src/integrated_delivery/frame_good_publish_cancel.v` 第 119 行 `if (crc_latched || crc_ok) && (fe_latched || fe_ok)` 缺少外层括号，ModelSim vlog 报 `vlog-13069 near "&&": syntax error`。生产 RTL 不能编译。
- D2：`fpga/csi2/src/integrated_delivery/integrated_input_processing_top.v` 第 126 行使用 `raw_mode`，但 `wire raw_mode` 声明在第 141 行，导致隐式 wire 与显式声明冲突（`vlog-2388 'raw_mode' already declared`）。生产 RTL 不能编译。
- D3：`frame_good_publish_cancel` 模块在候选中没有任何实例化位置，不能证明好帧发布/取消事务已接入顶层。
- D4：候选自带 `tb_raw10_packer.v` 第 28 行存在 `40'h... ? 0 : 0` 非法 ternary 语法，ModelSim 编译失败；且原 TB 只检查 sideband，未检查 packed 数据。该文件列入 manifest，影响工程可复现性。
- D5：`integrated_input_processing_top` 未连接 `st_he_published`、`st_he_rejected`、`st_gau_abort`，ModelSim 给出 missing-port 警告（功能不一定失败，但集成不完整）。

## 4. Engineering 结果：fail

- 生产 RTL 编译：`vlog` 编译 candidate 目录下 RTL，exit code 1，错误 6（D1/D2/D4）。
- 修正副本编译/仿真全部通过，说明逻辑在语法修正后可运行，但生产候选本身不可构建。
- G2（综合、最终 STA、约束覆盖、CDC/复位、资源）未执行：因生产 RTL 不能编译，未启动 TD 综合；G2 记 fail/not_run，非 PASS。
- Manifest/candidate 绑定：哈希一致；但 manifest tool_inputs 包含 `__pycache__/raw10_pack.cpython-311.pyc`，候选完整性建议清理或明确为生成物。

## 5. System 结果：not_run / blocked

- G3 上板功能：not_run + awaiting_hardware（无板卡窗口/下载授权）。
- G4 长稳/性能：not_run + awaiting_hardware（本轮后置，仅记录差距）。
- G5 集成/发布：部分；生产候选不可编译，发布材料未完成。
- corrected-copy smoke 显示 RAW/灰度模式路由和 packed 输出在仿真中通过，但不能替代生产候选系统验收。

## 6. 未测项与下一步

- 未执行：TD 综合/STA/CDC/资源、真实 DUT 全帧长时间仿真、板测下载/恢复/300s 稳定性/性能。
- 下一动作：开发修复 D1-D5，重新冻结 manifest 后由同一综合测试者复测失败项与受影响项。

## 7. 维度汇总

- functional: fail
- engineering: fail
- system: not_run (G3/G4 not_applicable/awaiting_hardware; production compile blocker)
- G0: pass
- G1: fail (production DUT compile blocker; corrected-copy checks pass)
- G2: fail (compile failure; synthesis not run)
- G3: not_run/not_applicable (awaiting_hardware)
- G4: not_run/not_applicable (awaiting_hardware)
- G5: partial/not_run