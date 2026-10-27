# parallel 轨道 TODO

> **2026-10-16主线接收：** 已按[整合记录M01-M11与候选O01-O08](../docs/DeepSeek独立检测与现行方案整合_2026-10-16.md)逐项取舍，后续项目状态统一维护在[workflow/tasks.json](../workflow/tasks.json)，本表保留独立轨道历史。18项软件回归与5项审计本次重跑通过；算法stub、BPR1封装适配及正式拒收的边界见整合记录，不将下面done理解成硬件主链已完成。

> 维护规则：每完成一项就改状态并写明证据路径。**先做能独立闭环、可自证的**，再挑依赖别人代码的。
> 状态：`done` / `doing` / `todo` / `blocked`
> 最近更新：2026-10-15（第二轮）

## A. 已完成

| ID | 任务 | 状态 | 证据 |
|---|---|---|---|
| A1 | TMDS 编码独立参考模型（DVI 1.0 8b/10b + DC 平衡 + 反解） | done | `evidence/tmds_reference_*/result.json` |
| A2 | 与 Project F 独立实现交叉核对（全 256 × 逐位） | done | 同上，mismatch=0 |
| A3 | 明文 `hdmi_tx_phy_wrapper` 4 lane 位序/独立性验证 + 负对照 | done | `D:/TD/work/csi2/_validation/tmds_phy_lanes_*` |
| A4 | 非压缩帧/元数据接口合同（128B 帧头/载荷/CRC/flags/DMA） | done | `docs/帧与元数据接口合同_2026-10-15.md` |
| A5 | 共享合成 RAW10 向量（packed/u16le + 逐字节锚点） | done | `evidence/frame_contract_20261015/` |
| A6 | 三算法软件金参考（灰度/高斯/前帧 CDF-min HE） | done | `docs/三算法软件金参考_2026-10-15.md` |
| A7 | 三算法共享向量（5 图样 + HE 两帧序列） | done | `evidence/image_algorithms_20261015/` |
| A8 | 现有 FPGA packer CRC 与帧合同一致性核对 | done | `checks/cross_consistency.py` |
| A9 | 闪点候选原因排查（15 项评估 + 分级） | done | `docs/闪点候选原因排查_2026-10-14.md` |
| A10 | `parallel/` 迁移与链接修复 | done | 4 runner 迁移后重跑 PASS |
| A11 | 统一回归入口 `run_all.py` | done | **11/11 PASS**，`evidence/run_all_*/summary.json` |
| A12 | PCIe C2H TLP 分包参考模型 + 检查器 + 负对照 | done | `evidence/tlp_pack_ref_20261015/tlp_plan.json` |
| A13 | RK 侧帧解码/灰度（与金参考逐像素一致） | done | `rk/frame_io.py` 自检 |
| A14 | RK 侧离线立体闭环（合成双目 + BM/SGBM + 误差） | done | `evidence/rk_offline_20261015/`（SGBM bad2=0.0%） |
| A15 | 双目标定入口模板 | done | `rk/stereo_calib_template.py`（无图错误路径已验证） |
| A16 | 跨模块一致性检查（相位/stride/位宽/CRC/色序） | done | `checks/cross_consistency.py` 全 PASS |
| A17 | 闪点码级压力向量（含每 lane 跳变密度/失衡） | done | `evidence/sparkle_stress_20261015/` |
| A18 | 本轮汇总文档 | done | `docs/并行轨道进展_2026-10-15.md` |
| A19 | 帧合同 .bin → RK 解码 → 立体 端到端闭环 | done | `rk/run_frame_to_stereo.py`（文件往返一致 + SGBM bad2=0.0%） |
| A20 | 只读复核 C1/C2/C3（含 F2 BPR1 边界） | done | `docs/只读复核_接口与语义_2026-10-15.md` |
| A21 | 回归扩到 12 项 | done | `run_all.py`：**12/12 PASS** |
| A22 | 三算法 RTL 测试台骨架 + 回放 stub + 负对照 | done | `algorithms/tb_image_algo_stream.sv`、`run_algo_tb.py`：normal PASS / mutant 被抓到 |
| A23 | 独立复核（DeepSeek V4 Pro 子代理）与逐条响应 | done | `docs/审核响应_2026-10-15.md` |
| A24 | 修复复核发现的 1 Critical + 4 Important | done | PCIe 单 DW BE/MPS DW；去马赛克保色夹取；消除恒真检查；parse_frame/--verify |
| A25 | 回归扩到 14 项（含 2 个 ModelSim） | done | `run_all.py --with-modelsim`：**14/14 PASS** |
| A26 | B3b 修复（对齐搜索窗口 bug）→ 位序获仿真背书 | done | `ROM_TB_PASS` 4 lane × 800 bit + mutant 被拒 |
| A27 | 总览 + 证据矩阵 + 优先级/止损 | done | `docs/总览_已完成与下一步_2026-10-15.md` |
| A28 | 方案对比矩阵（5 个决策点 + 开源参考） | done | `docs/方案对比矩阵_2026-10-15.md` |
| A29 | PCIe 首次联调固定块生成/校验工具 | done | `pcie/first_test_data.py`（5 图样 + 4 类负对照） |
| A30 | 真实 RAW dump 接入工具 | done | `rk/ingest_raw.py`（4 种格式 + 统计 + 预览 + 帧合同输出） |
| A31 | 回归扩到 18 项 | done | `run_all.py --with-modelsim`：**18/18 PASS** |
| A32 | **C 参考解码器** + 跨语言一致性（C vs Python 逐字节） | done | `rk/frame_decode.c`、`rk/run_c_cross_check.py`：两个向量 Y8 完全一致 + 坏帧被拒 |
| A33 | **PCIe 端到端软件通路**（块→TLP→主机重组→校验） | done | `pcie/run_e2e_soft_path.py`：4 正例 + 4 负例 + 乱序无害性断言，9/9 |
| A34 | **立体整条流水线自检**（标定→校正→匹配→深度，已知真值） | done | `rk/run_stereo_pipeline_check.py`：基线误差 0.02mm、深度误差 ≤0.62%、有效率 100% |
| A35 | **证据审计**（文档数字/链接 vs 实际产物） | done | `checks/evidence_audit.py`：5 项，**首跑即抓到 2 处真实漂移** |
| A36 | **接入手册**（FPGA 侧 / RK 侧 / 联调） | done | `docs/接入手册_2026-10-15.md` |
| A37 | 回归扩到 21 项 | done | `run_all.py --with-modelsim`：**21/21 PASS** |

## B. 待办

| ID | 任务 | 状态 | 说明 / 退出证据 |
|---|---|---|---|
| B1 | 三算法 RTL 测试台骨架（向量驱动，DUT 端口契约已给出） | done | `algorithms/tb_image_algo_stream.sv`；把编译列表里的回放 stub 换成真实 RTL 即可 |
| B2 | HDMI 已知色端到端记录模板 | done | `tmds/known_color_record.py` + `docs/HDMI已知色端到端记录模板_2026-10-15.md`；含 DC 平衡"历史相关"自证 |
| B3 | 闪点受控实验 ROM 方案 + RTL + 生成器 | done | `experiments/gen_rom.py`（自检 PASS）、`tmds_pattern_rom.v`、`docs/闪点受控实验_ROM方案_2026-10-15.md` |
| B3b | ROM→wrapper 串行位序仿真验证 | **done** | `run_tmds_pattern_rom.py` → `ROM_TB_PASS`（4 lane × 800 bit）+ mutant 被拒。根因是我方 TB 的对齐搜索窗口太小（≤200，真值 211）；已改为 8× 过采样 + 8 相位 + 正确搜索窗口。**位序结论获仿真背书** |
| B5 | 宽/高=1、`raw10_to_u16` 的 width%4 校验 | done | 三算法与 RK 各加退化尺寸用例；`raw10_to_u16` 对 width%4/非正尺寸报错 |
| B6 | 固定证据目录的证据版本字段 | done | `parallel/meta.py`：`generated_utc` + 脚本 SHA256 写入各 `result.json`/`summary.json` |

## C. 只读检查（不改别人文件，只出报告）

| ID | 任务 | 状态 | 说明 |
|---|---|---|---|
| C1 | 审阅预览/白平衡链的舍入与边界一致性 | done | 舍入约定一致；采样率（4×4→2×2）是风险；见复核报告 |
| C2 | 审阅 `ddr_frame_store` 所有权与丢帧语义 | done | 预览"替换 READY"无序号缺口，传输队列需另写契约 |
| C3 | 复核 F2（BPR1）与帧合同的字段边界 | done | **互补不冲突**；`payload_bytes` 内外层语义冲突必须统一 |

## D. 记录/归档

| ID | 任务 | 状态 |
|---|---|---|
| D1 | `README.md` 轨道入口 | done |
| D2 | 本 TODO | done |
| D3 | 子代理独立审核 | **两轮均完成**：①`general`（1 Critical + 4 Important + 12 Minor）②**DeepSeek V4 Pro**（0 Critical + 1 Important + 4 Minor）。两轮全部逐条响应于 `docs/审核响应_2026-10-15.md` |
