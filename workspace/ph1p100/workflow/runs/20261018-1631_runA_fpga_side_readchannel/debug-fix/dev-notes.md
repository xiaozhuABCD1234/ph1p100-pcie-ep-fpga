# dev-notes — T11.runB-debug-rtl P1-fix2（CWC 多片几何等效校验；0 构建）

- 任务/角色：同 task_id 续修（fpga-dev，原会话）；日期 2026-10-18；run debug-fix（不重建、不改 CWC/bit/RTL/约束）。
- 裁定依据：dev-plan v1.7（② 书面等效校验）；冻结判据=宽度和/逐片≤BID logic_width/无缺口无重叠/address·data 偏移连续/depth=1024/working mode 逐片一致/288 bit 全覆盖映射表/默认模式仍拒多片/≥4 负例拒收。

## 1. 事实核对（先核实、后实现）
- 真实件：auto_created_cwc1，logic_eram width=288（数据位）depth=1024，15 个 phy_eram；BID 151 条 INST_*（rid/wid 十六进制大小写不同，按数值化键匹配），15 片全部命中。
- 关键新信息：BID 记录的 RAM 逻辑宽=**289**（逐片 logic_width=289），片宽 20×14 + 9 = **289**，data_offset 连续铺满 [0,289)；即 **288 数据位 + 1 个 TD 状态尾位**。故"宽度和=288"在真实件上应表述为"数据位 288/288 全覆盖 + 1 状态尾位"；已按 fail-closed 规则显式建模（尾位 ≤1，超出即拒）。
- 逐片字段核对：address_offset=0、num_section=1、address_step=1、depth=1024（BID logic_depth=1024）、bytes_in_per_section=1、section_size=289；working mode 逐片与 BID 一致（address_step=1、ECC disable、super_wide disable；9 位片物理为 10×2048，其余 20×1024，均与各自 BID working_mode 一致）。

## 2. 实现（仅工具/夹具）
- `tools/td/check_chipwatcher_readback.py`：新增 `--multipiece`（fail-closed 多片覆盖）与 `--map-out`；**默认严格模式逐字保留**（同一 `_check_common`，退出码 0/1 不变）。
- `tools/td/tests/run_validator_tests.py`：9 例回归夹具（真实件两模式、单段合成正例两模式、5 负例：缺口/重叠/宽度超限/工作模式不一致/错 RID）。

## 3. 结果（`debug-fix/validator-tests/summary.json`）
- 真实件：`--multipiece` **accepted**，15 片、288/288 数据覆盖、status_bits=1；strict 仍 **rejected**（BID width mismatch，防回归）。
- 单段合成正例：两模式均 accepted。
- 负例 5/5 拒收（各自预期理由见 summary）。
- **9/9 PASS**；映射表 `debug-fix/cwc-multipiece-map.json`（bits=289：288 data + 1 status，逐 bit→片/偏移）。

## 4. 冻结与边界
- commit：root repo `27c596b01cd961dfa9d0850e4fbf879fe249de90`（2 files/360+/22-，未推送）；upstream 3 路径仍 worktree-only（BLOCKED_PENDING）。
- 未重建、未启 TD、未触硬件、未用网络；CWC/bit/RTL/约束哈希未变（bit 2385cded…、cwc fa24e258…、bid 71330f16…）。
- 回退：`git revert` 该工具 commit（或单文件恢复）+ 丢弃 validator-tests/map 记录；候选与位流不受影响。