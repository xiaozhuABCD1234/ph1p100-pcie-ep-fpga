# dev-result.md — T11.runA-bringup-kit（离线工具包）

- run: `20261018-1347_runA_offline_sim`；任务: `T11.runA-bringup-kit`；角色: fpga-dev（新建子会话，未派生）
- 操作者: fpga-dev 子会话（opencode；session id 未向子代理暴露）；宿主: Windows PC（用户 czz）
- 状态: **ready_for_test**（离线包完成并自检通过；不触硬件、不新增 G3/G4）
- 时间: 2026-10-18（上海时区）；耗时约 15 min；工具调用约 25 次（冻结 ≤25；含 1 次命令拼装错误后的有证据重跑，见 §6）

## 1. 交付物（两处）

A. 上游仓新增（本地 commit，不推送；分支 `codex/raw10-rka1`，父提交 `ab811c8f820c3ae6601507b54ec45a74c6607855`）：
`upstream/ph1p100-pcie-ep-fpga/tools/bringup/`
- `parse_dump.py`（dump/通道解析 + 判定，退出码 0/1/2 fail-closed）
- `expected_rules.json`（17 条期望规则，每条含来源）
- `registers-plan.md`（全表 + B1 实测命令模板 + 不可用项标注）
- `run_record.schema.json`（run-record 冻结 schema）
- `runbook.md`（操作流程、安全边界、用户在场项、四条恢复选项）
- `README.md`（用法、依赖、dry-run 矩阵、CRC/长度复算命令与期望）
- `fixtures/`：`dump-positive.txt`、`neg-magic.txt`、`neg-len.txt`、`neg-reserved.txt`、`neg-malformed.txt`、`neg-missing.txt`、`neg-empty.txt`、`neg-channel-flash.log`

B. run 证据：`workflow/runs/20261018-1347_runA_offline_sim/bringup-kit/`
- `dryrun.log`（9 个用例的实际命令输出/退出码 + 复算 + 确定性）
- `records/`（正/负 run-record.json、r10f_strict check JSON、通道 record）
- `fixtures/b1-real-05-sram-download-retry.log`、`fixtures/b1-real-channel.log`（B1 真实日志只读副本，SHA 与源一致）
- `candidate-manifest.json`、`candidate.diff`、`dev-result.md`、`dev-notes.md`、`lessons-learned.md`

## 2. dry-run 实测矩阵（TOTAL_CASE_MISMATCH=0）

| 用例 | 期望退出码 | 实测 | 摘要 |
|---|---|---|---|
| 正夹具（合成 1080p 快照） | 0 | 0 | pass=17 fail=0 blocked=0 |
| neg-magic（0x040 错） | 1 | 1 | R01 fail |
| neg-len（0x0AC 错） | 1 | 1 | R05 fail |
| neg-reserved（0x114 保留位非零） | 1 | 1 | R13 fail |
| neg-malformed（非法 hex） | 2 | 2 | 拒收，不写 record |
| neg-missing（缺读数） | 1 | 1 | blocked=14（缺失即 BLOCKED，不 PASS） |
| neg-empty（空输入） | 2 | 2 | 拒收 |
| B1 真实日志（channel 模式） | 0 | 0 | pass=3（器件 ID / SRAM 下载 / 无 flash 文本） |
| neg-channel-flash | 1 | 1 | CH03 fail |

确定性：同一输入+固定 `--timestamp` 两次输出字节一致（`DETERMINISM_OK=True`）。
编码：kit 文件全 ASCII；record 为无 BOM ASCII JSON；非法编码/非法行 → 退出码 2。

## 3. CRC/长度复算（阈值要求）

- `r10f_strict.py check <r10f-1080p-synthetic.dma> --json-out ...`：实测字段 `sha256=646ebaed…`、`size=2592768`、`ok=true`、`header_crc_calc=108710859`、`payload_crc_calc=3491449518`、`marker=R10F_STRICT_OK`，与 `check-1080p.json` 逐项一致（首跑时 PowerShell `ConvertFrom-Json` 因工具输出中的 Windows 反斜杠路径报错，改用 Python 字段比对并记录于 dryrun.log；不改被复用工具）。
- `gen_crc32_flat.py --selfcheck-only`：exit=0（poly `0xEDB88320` 自检）。
- 长度复算：128 + 2,592,000 + 640 = 2,592,768（`LENGTH_RECOMPUTE_OK=True`）。

## 4. JTAG 寄存器语义文档级初核（≤10 调用，无硬件）

- 检索范围：`upstream/.../doc/**`、`docs/**`、`tools/**`、`README.md`；TD 安装目录（`D:\anload\…` 与 `D:\anlogic\TD_Release_2026.2`）的文本类文档；B1 `logs/03-bw-command-list.txt`。
- 结果：`JTAG_REG_ACCESS`、`JTAG_REG_ACCESS_VEC`、`JTAG_AXIS_APB_ACCESS` 仅作为**命令名**出现在命令表（B1 log 03 第 5-7 行）；仓库与 TD 文本文档中**无参数/读写语义文档**；候选 bit 无 CWC/调试核。按 dev-plan §3.3 步骤 5 规则记 **不可用**，未调用 bw、未盲试、未做任何硬件动作。
- 未发现“无需调试核的只读用户寄存器路径”文档证据，故**无可交原规划派发的只读补充建议**（保留 dev-plan §9 选项 (c) 给用户/原厂确认）。

## 5. 边界与一致性

- 写范围：仅 `tools/bringup/**`（本地 commit，不推送）+ run `bringup-kit/**`；未改 rtl/constraints/sim/docs/protocol/tools/pcie_integration、B1 证据、其他 run、`workflow/tasks.json`。
- 无硬件动作、无网络、无批量删除、无绝对路径写入脚本（脚本内只用 `__file__` 相对定位规则文件）。
- 复用只读：`r10f_strict.py`、`gen_crc32_flat.py`、contract、B1 日志（副本 SHA 与源一致）。
- 离线包完成**不**把父硬件任务（T11.runA-board-selfcheck 等）置 done；B1 保持 blocked 接受、B2 保持 awaiting_conditions。

## 6. 已做 / 未做 / 预算

已做：工具包与夹具、9 用例 dry-run、确定性复验、CRC/长度复算、schema 键校验、B1 日志副本与 channel 判定、JTAG 文档初核、manifest/diff。
未做（范围外或条件缺）：任何板级读寄存器（读通道缺失）；不新增 bit/不构建（G2 not_applicable）；不做长稳；不推送。
预算：≈25 次工具调用（冻结 ≤25）、约 15 min（冻结 15）。首跑 dry-run 因 `python <args>` 未含脚本路径而失败（自身拼装错误），修正后重跑当次全部用例，属有证据纠正；其余调用为读输入、写 6 个 kit 文件、跑 dry-run、写 3 个 run 文档与 commit/manifest。

## 7. G 层与复测元数据

- G0（输入/基线冻结）：继承（父提交与 bit 身份未变）= pass。
- G1（离线工具 dry-run）：pass（见 §2/§3）。
- G2：not_applicable（不构建）；G3/G4：not_run（不触硬件）。
- 复测关注：正/负夹具独立重跑与退出码、≥8 条规则来源抽验（共 17 条）、合成件复算复跑、编码/确定性、写范围与回退。
- 回退：反转本轮本地 commit（`git revert`/reset 到父提交）或丢弃 `tools/bringup/`；run 证据保留只读。
