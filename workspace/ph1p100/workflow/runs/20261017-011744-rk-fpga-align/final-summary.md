# run 20261017-011744-rk-fpga-align 阶段总结（规划者，2026-10-17）

## 通过统计（首次/修复1/2/3轮）

- **T03.rk-align-freeze**：round0 首次三维全 PASS（0 修复轮）；首包 manifest `9662167a…77c5`（冻结保持）。
- **T07.rk-align-backend**：round0 FAIL → 修复①（F1/F2/F3）→ 修复②（G2 本域时序重构达标）→ 修复③（tool-only：入口 BOM 修复+文档更正）→ **r3 三维同候选 PASS（实际修复 3/3 轮用尽，第 3 轮通过）**。
- **T11.rk-align-raw**：**round0 首次三维同候选全 PASS（0 修复轮）**；开发返回经文件机械恢复（完成消息未送达，dev-result.json 为返回载体，静默 4.5h 零写入，冻结成立）；三维测试者均为新实例。
- **T11.rk-align-base**：round0 FAIL（functional/system）→ 修复① → 修复②（**r2 三维同候选全 PASS，实际修复 2/3 轮**；manifest `ff079ffa…c069`，26 条自检 0 不一致）；全部修复为文档/记录级，env_check.ps1/清单/受保护树/既有证据 SHA 零改动。
- **T09.rk-align-algo**：round0 blocked（G1 16 mismatch / G2 -3.870ns）→ 修复轮1 → **integrated 综合测试 PASS（三维全过；实际修复 1 轮；G3/G4 not_run=范围外；G5 未完成）**；setup SWNS +0.059ns/STNS 0/0 违例、hold +0.020ns、Fmax 189.609MHz；manifest `2195641a…a5f8`（36/36 无漂移）。
- ⚠未通过：无。**暂停中：await_user_sync**（T10 及后续不派发，等用户统一进度；恢复入口见 dispatch.json next_action.resume_entry）。

## 当前有效候选（T11.rk-align-raw，取代 T07 候选）

- manifest：`raw/candidate-manifest.json` SHA256=`aab0cc08ef0134d5fcb18b25e0b70c43e9af1d577513ca2996dc46f22de76975`（243 条自检 0 不一致）。
- 位流：`raw/candidate/prj/ph1p_pcie_integration_Runs/phy_1/ph1p_pcie_integration.bit` SHA256=`14b32037eb0b4aff4f9ea1f61b75160c11ff9381e23f11563f97ecaf5bf5686b`（与 best_result 同源）。
- G2：SWNS +0.115 ns / STNS 0.000 / 0 违例端点、hold +0.020 ns、Routed、ERAM 136/300；相机字节域余量薄（任何 RTL/约束改动须重跑 G2 且该域 setup≥0）。
- 新增：正式 RAW10→R10F 写者、三层 CRC、640B 尾零、one-shot/所有权链；G1 含 e2e/写者/对抗探针/负对照；严格解析工具 `tools/pcie_integration/r10f_strict.py`。
- 几何/相位为占位（synthetic/diagnostic）：板测读 0x120..0x12C/0xA0..0xAC 回填后重跑 G1/G2。
- T07 r3 候选（manifest `68f9f4d0…4275`、bit `0943cb36…8b0a`）保留为历史与回退。

## RK 侧交付（两版叠加）

- `backend/rk-change-list.md` + `backend/patches/rka1-driver.patch`（T07 基线）；`raw/rk-change-list.md` + `raw/patches/t11-rka1-r10f-fix.patch`（T11 增量，修正解析布局+发布前严格解析+r10f_check CLI）；`backend/rk-driver-src/`、`raw/rk-driver-src/`。均离线 apply-check 通过；**未在 RK 编译/安装**（缺 KDIR/交叉工具链/cargo）。

## 比赛要求对齐（user-feedback-05）

- R1 CSI 采集：已覆盖（离线仿真）/待板验；R2 三种算法：T09 排队（验收含真实并行硬件证据）；R3 已定（user-feedback-06）：LZ77 基线 + Bayer 自有优化混合路线（T10 范围更新；BPR1 转拓展；字面合规满足）；R4 PCIe 已通 + 新增 `T11.rk-align-compress-int`（压缩帧传输集成）；R5 NPU 属 RK 队友（T05/T12）；R6 量化数据（帧率/延迟/资源/压缩率/推理耗时）留板测与发布汇总。
- 场景级数值（60fps、压缩率≥30%、延迟<50ms、2h 长稳、同步<1ms）为场景/拓展口径，非基础统一门槛；首个 1080p30 里程碑不变；最终口径需组织方确认（Q-RULE-2/3 开放）。

## 未测边界与待条件

- G3—G5 未做；板测包 `T07.rk-align-board` 条件=JTAG/BW 窗口 + RK 可达（BDF/内核/PAGE_SIZE/MPS/IOMMU）+已打 T07/T11 补丁的驱动。
- RK 编译 not_run；真实几何/相位待板证；双路/60fps/长稳为后续目标。
- 残留（不影响判定）：F5-r3（`backend/g2/README.md` §6 旧绑定句）、`raw/g2/README.md` §2 clk1 笔误、RTL 头注释陈旧、`g1/crc16_upd4.generated.v` 标注、仓库根 `run2.do`、`R:` subst 残留映射、T11-raw r0 engineering §6『全库检索无+5.058来源』（实际来源=`final_timing.rpt` tl_clk_user 路径组 L2076-2081；已按仅登记处置，不改写历史报告）；T09 r1 观察：D1 he_samebin 冻结负对照锚点漂移（测试自有适配对照拒绝成立，不影响判定）、D2–D4 文档记账陈旧项（change-report §5/§6 数字、actual-commands manifest_sha256 早期值、dev-result 负对照申报；随下次触碰更正）。

## 角色实例与合规核对

- planner：`/root/fpga_planner_rk_align` → `ses_eba025958ffenOiSFeq1XsVCQQ`（恢复+收尾；G2 决策由临时实例 `ses_eb95ca92…`，范围合规）。
- T07 链：dev 原 `ses_eb9ff4ea…` → r3 `ses_eb90ba403…`；functional `ses_eb98c6b7…`→`ses_eb933249…`；engineering `ses_eb98c6b6…`→`ses_eb92ce12…`；system 全程。
- T11 链：dev `ses_eb8a8f1f5…`（文件恢复；重复实例已登记关闭）；三测试 `ses_eb77afd4*`（新实例）。
- 均同冻结输入、登记映射、不假称 resume；未发现越权或跨任务复用。

## 下一入口

- 队列（batch=1，**暂停中**）：【await_user_sync】→ T10.rk-align-codec（LZ77 基线+Bayer 自有优化）→ T11.rk-align-opt → T11.rk-align-compress-int → T07.rk-align-board（条件）→ T11.rk-align-release（含 R6 量化汇总）；恢复入口见 dispatch.json next_action.resume_entry（用户说“继续”后由本 run 规划者续接）。
- 终点（user-feedback-07）：本轮最终目标=双路同步成功（T08）；RK 深度/NPU 不进行（T12/T05 相应部分关闭/排除，不置 done）。
- 父任务：T03 待双方签收；T07 待真实主机 DMA；T11 待压缩与端到端——均不置 done。
