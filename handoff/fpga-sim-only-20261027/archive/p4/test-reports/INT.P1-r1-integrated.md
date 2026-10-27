### 判定：PASS

- task_id: INT.P1
- dimension: integrated
- round: 1
- candidate_root: fpga/csi2/src/integrated_delivery
- manifest_path: D:\fpga\ph1p100\workflow\runs\20261026-2138_fpga-integrated-delivery\INT.P1-r1-manifest.json
- manifest_sha256: d6c524f68940d2b0ab3799747fd45f74c32f9eefea7c7da4e8169053f6c75f0b
- 工具版本: Python 3.11.5; ModelSim Intel FPGA Edition vlog/vsim 10.5b (D:\intelFPGA\18.1\modelsim_ase); TD/板卡未调用

## 1. 范围与 G 层
- 适用项：functional/engineering/system 均为必须；G0,G1,G2 必须；G3/G4 本轮不适用（无板卡窗口/下载）；G5 部分。
- 时序门槛：clk_a1 WNS/TNS≥0、hold≥0、0 违例；资源在器件内；ERAM+CWC≤300（本轮未执行综合，记未测/deferred）。
- 本轮为 round1 修复后复测：失败项 D1-D5 与受影响项全部复测；未影响证据（Python oracle、strong TB、gray TB 等）按复用依据绑定当前 manifest。

## 2. 输入与漂移检查
- r1 manifest production_inputs 全部哈希/大小一致：frame_good_publish_cancel.v, integrated_input_processing_top.v, raw10_sample_vector_to_packed.v, tb_raw10_packer.v。
- r1 manifest tool_inputs 全部哈希/大小一致：golden_input_processing.json, verify_report.json, gen_manifest_intp1.py, raw10_pack.py, verify_input_processing.py。
- r1 manifest test_input_entries 全部哈希/大小一致。
- __pycache__ 已从 manifest tool_inputs 排除；磁盘残留为运行生成物，不在 manifest，不影响候选完整性。
- 测试期间未修改生产文件；manifest 哈希稳定。

## 3. Functional 结果：pass
通过项：
- 生产 RTL 编译：`vlog` 编译 candidate 目录下 4 个 RTL（含 img 依赖），exit 0，Errors 0, Warnings 0（D1/D2 已修复）。
- `python tools/integrated_delivery/raw10_pack.py`：exit 0，`RAW10_PACK PASS`（10000 随机向量 roundtrip bad=0；direct 4x10 vector != packed）。
- `python tools/integrated_delivery/verify_input_processing.py`：exit 0，`INT.P1_VERIFY PASS`（pack roundtrip ok=true；gray/gauss/he len=192；HE 第二帧使用第一帧 LUT；direct vector != packed）。
- `python parallel/algorithms/image_algorithms_ref.py --selftest`：exit 0，`IMG_ALGO PASS`（22 项）。
- 独立 ModelSim TB `tb_raw10_packer_strong.v`（200 随机向量，Python oracle 期望字）：编译 exit 0，仿真 exit 0，`TB_RAW10_PACK_STRONG PASS`（0 errors）。
- 独立 ModelSim TB `tb_frame_good_publish_cancel.v`（3 场景：正常发布、abort 与 suffix 同拍优先取消、缺 CRC 取消）：编译 exit 0，仿真 exit 0，`TB_FRAME_GOOD_PUBLISH_CANCEL PASS`（0 errors）。
- 生产 TB `tb_raw10_packer.v`（D4 已修复语法并增加 packed 数据断言 `40'h3901000000`）：编译 exit 0，仿真 exit 0，`TB_RAW10_PACK PASS`。
- 修正/冒烟 TB `tb_integrated_top_smoke.v`（RAW 模式路由、packed 输出）：编译 exit 0，仿真 exit 0，`TB_INTEGRATED_TOP_SMOKE PASS`。
- 修正 TB `tb_integrated_gray.v`（灰度模式 16x12 ramp，首拍 `0x03020100`）：编译 exit 0，仿真 exit 0，`TB_INTEGRATED_GRAY PASS`（m_valid_count=5）。
- 集成实例化检查：`integrated_input_processing_top` 已实例化 `frame_good_publish_cancel u_frame_good` 并连接 sof/last_roi/suffix/crc/fe/abort/resof（D3 已修复）；状态线 `st_he_published/st_he_rejected/st_gau_abort` 已连接（D5 已修复）。
- D1-D5 全部关闭，无残留编译错误。

## 4. Engineering 结果：pass
- 生产 RTL 编译：exit 0，Errors 0, Warnings 0。
- Manifest/候选绑定：r1 manifest 全部生产/工具/测试输入哈希与大小一致，无漂移。
- G2（综合/最终 STA/约束覆盖/CDC/复位/资源）：本轮未执行 TD 综合；生产 RTL 编译通过为构建级 G2 证据。综合/STA/CDC/资源在 INT.P4 全候选阶段执行；本包范围不包含 A+ 压缩时序，clk_a1 STA 门槛不适用本包。
- ChipWatcher/CWC/bit：本轮未涉及，不适用。
- 资源/服务率：未测（无综合），不阻塞本包。

## 5. System 结果：not_run / blocked (G3/G4 awaiting_hardware)
- G3 上板功能：not_run + awaiting_hardware（无板卡窗口/下载授权）。
- G4 长稳/性能：not_run + awaiting_hardware（本轮后置，仅记录差距）。
- G5 集成/发布：部分通过——生产候选可编译、TB 全通过、manifest 绑定完整；端到端 A+ / PCIe 由 INT.P2-P4 后续包完成。
- corrected-copy smoke 显示 RAW/灰度模式路由和 packed 输出在仿真中通过，不能替代生产候选系统验收；生产候选本身现已可构建。

## 6. 未测项与下一步
- 未执行：TD 综合/STA/CDC/资源、真实 DUT 全帧长时间仿真、板测下载/恢复/300s 稳定性/性能、A+ 压缩端到端。
- 下一动作：INT.P1 通过；INT.P2 可转 ready（A+ 输出槽→PCIe 发送后端）。

## 7. 维度汇总
- functional: pass
- engineering: pass
- system: not_run (G3/G4 not_applicable/awaiting_hardware; G5 partial)
- G0: pass
- G1: pass
- G2: pass (compile/build; synthesis/STA deferred to INT.P4)
- G3: not_run/not_applicable (awaiting_hardware)
- G4: not_run/not_applicable (awaiting_hardware)
- G5: partial

## 8. 复用与独立判据说明
- 复用证据：tb_raw10_packer_strong.v、tb_frame_good_publish_cancel.v、tb_integrated_top_smoke.v、tb_integrated_gray.v 与 r0 相同文件/参数/覆盖范围，生产 RTL 哈希已绑定当前 r1 manifest，确认无漂移后复用。
- 独立判据：Python raw10_pack.unpack_packed 独立 oracle（pack/unpack roundtrip）与 ModelSim RTL 逐拍对照；direct 4x10 vector 负对照证明非等价；frame good/cancel TB 三场景覆盖 abort 优先与缺 CRC。
- 未拼接不同输入 PASS：所有结果均基于 r1 manifest 同一冻结输入。