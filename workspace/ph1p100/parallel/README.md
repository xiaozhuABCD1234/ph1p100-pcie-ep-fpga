# parallel/ — 并行轨道（非 Codex 主线的独立工作）

> **2026-10-16主线接收状态：** 已完成[对照、采用与未来候选登记](../docs/DeepSeek独立检测与现行方案整合_2026-10-16.md)，本目录继续保留原始出处。18项软件检查与5项证据审计本次复跑通过；3项ModelSim为原有证据。R10F目前只支持非压缩参考，BPR1接入还缺adapter及正式拒收；算法测试台仍使用回放stub。以下10-15结论涉及“与FPGA一致”时仅能按实际软件参考或源码静态核对理解，不能作RTL/板验结论。

> 建立：2026-10-15。**本目录是独立于 Codex 主线/其他 worktree 的一条并行轨道**，集中存放软件参考模型、接口合同、共享向量与证据，便于 Codex 对照评审或与主线合并。
> 纪律：不改动 `tools/`、`docs/`、`fpga/` 下他人正在改的文件；只在本目录新增/维护自己的产物。所有结论标注证据等级，未验证的写"未验证"。

## 一条命令跑完全部自检

```powershell
python parallel/run_all.py                  # 18 项，纯软件
python parallel/run_all.py --with-modelsim  # 21 项，追加 3 个 ModelSim 项

python parallel/checks/evidence_audit.py    # 元检查：文档数字/链接 vs 实际产物
```

> `evidence_audit` **刻意不放进 `run_all`**：它要核对 `run_all` 的项数与最近一次结果，
> 放进去会形成循环依赖。

## 先看这两份（总览与决策）

- [总览：已完成、证据边界与优先级](docs/总览_已完成与下一步_2026-10-15.md)
- [方案对比矩阵（含开源参考）](docs/方案对比矩阵_2026-10-15.md)

（`--with-modelsim` 追加：`tmds.physlanes`、`algo.rtl_tb`、`b3.rom_serial`。需要 ModelSim 与 `D:/downlaod/sim_release/ph1p` 的厂商模型。）

## 目录结构

```text
parallel/
├─ README.md            本文件：入口、状态、如何运行
├─ TODO.md              任务清单与状态
├─ run_all.py           统一回归
├─ docs/                方案与记录（相对链接以本目录为基准）
├─ tmds/                TMDS 编码独立参考模型 + 明文 wrapper/lane 验证
├─ frame/               非压缩帧/元数据接口合同 + 共享 RAW10 向量
├─ algorithms/          三算法（灰度/高斯/前帧 CDF-min HE）金参考 + RTL 测试台
├─ pcie/                PCIe C2H TLP 分包参考模型
├─ rk/                  RK 侧离线可运行起点（解码 → 立体）
├─ checks/              跨模块一致性检查
├─ analysis/            闪点码级压力向量
├─ bin/                 二进制向量（备用）
└─ evidence/            运行证据
```

## 交付物与状态

| 项 | 文件 | 状态 | 证据 |
|---|---|---|---|
| TMDS 编码参考模型 | `tmds/tmds_ref.py` | 自检 PASS | `evidence/tmds_reference_*/` |
| 与 Project F 独立实现逐位核对 | `tmds/run_tmds_reference.py` | 0 处不一致（bias=0、数据期、全 256 值） | 同上 |
| 明文 wrapper 4 lane 位序 + 负对照 | `tmds/tb_hdmi_phy_lanes.sv`、`tmds/run_tmds_phy_lanes.py` | 3 相位 PASS + mutant 被拒（需 ModelSim） | `D:/TD/work/csi2/_validation/tmds_phy_lanes_*` |
| 非压缩帧/元数据接口合同 | `frame/frame_contract.py` | 自检 PASS（含畸形帧与篡改检出） | `evidence/frame_contract_20261015/` |
| 三算法金参考 | `algorithms/image_algorithms_ref.py` | 自检 PASS | `evidence/image_algorithms_20261015/` |
| 三算法 RTL 测试台（向量驱动） | `algorithms/tb_image_algo_stream.sv`、`run_algo_tb.py` | normal PASS + mutant 被精确抓到（需 ModelSim） | `D:/TD/work/csi2/_validation/algo_tb_*` |
| PCIe C2H TLP 分包 | `pcie/tlp_pack_ref.py` | 自检 PASS（含单 DW BE 规则、MPS DW 口径、两个负对照） | `evidence/tlp_pack_ref_20261015/` |
| RK 帧解码/灰度 | `rk/frame_io.py` | 与金参考**四相位逐像素一致** | 自检 |
| RK 离线立体 | `rk/run_rk_offline.py` | 合成双目 SGBM bad2=0.0% | `evidence/rk_offline_20261015/` |
| 帧合同 .bin → 立体 端到端 | `rk/run_frame_to_stereo.py` | 文件往返一致 + 立体结果一致 | `evidence/frame_to_stereo_20261015/` |
| 双目标定入口 | `rk/stereo_calib_template.py` | 需实拍图；无图错误路径已验证 | — |
| 跨模块一致性 | `checks/cross_consistency.py` | 全 PASS（含对 RTL 注释的真实核对） | — |
| 闪点码级压力向量 | `analysis/sparkle_stress.py` | 带真实断言（码往返/图样敏感性/失衡有界） | `evidence/sparkle_stress_20261015/` |
| HDMI 已知色记录模板 | `tmds/known_color_record.py` | 8 色 × 4 拍期望码 CSV + DC 平衡历史自证 | `evidence/hdmi_known_color_20261015/` |
| 闪点受控实验（ROM→wrapper） | `experiments/tmds_pattern_rom.v`、`gen_rom.py`、`run_tmds_pattern_rom.py` | **`ROM_TB_PASS`**：4 lane × 800 bit 逐位一致 + mutant 被拒 → 位序结论获仿真背书（需 ModelSim） | `D:/TD/work/csi2/_validation/rom_tb_*` |
| 独立复核与响应 | `docs/审核响应_2026-10-15.md` | 1 Critical + 4 Important 已修 | — |
| 证据版本字段 | `meta.py` | 各 `result.json`/`summary.json` 带 `generated_utc` + 脚本 SHA256 | — |

## 关键结论（供主线参考）

1. **帧合同可在 RK 等价实现**：numpy 路径与纯 Python 金参考四相位逐像素一致；两侧对不上就是实现差异。
2. **F2 的 BPR1 与我的 128B 传输头互补不冲突**，但两层都有 `payload_bytes` 且含义不同（外层含 32B 填充、内层不含）——必须统一，详见 `docs/只读复核_接口与语义_2026-10-15.md`。
3. **`ddr_frame_store` 撑不起传输队列**：预览用"新帧替换旧 READY"且不记录序号缺口；传输队列需另写五态所有权契约。
4. **闪点物理层压力主要来自跳变密度**（0xAA/0x55 交替 ≈0.50，项目参考色条仅 ≈0.157）；TMDS 的 DC 平衡把串行失衡压住，码级上无法制造大失衡。

## 边界

- 全部为**软件参考/合同/测试与证据**，不是 RTL、不是实拍结果、未与队友冻结。
- 不替代 Codex 已产出的设计、位流或板测记录；冲突时以证据更强的一方为准。
- `docs/方案审核与优化方向_对比开源_2026-10-15.md` 留在原 `docs/`（Codex 复核文档引用它），其余本轨文档在 `parallel/docs/`。
