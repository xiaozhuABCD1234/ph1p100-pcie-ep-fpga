# dev-notes.md — T11.runB-debug-spec 开发说明（离线方案冻结包）

- run: `20261018-1631_runA_fpga_side_readchannel`；任务: `T11.runB-debug-spec`；开发: fpga-dev 子会话（opencode），2026-10-18。
- 状态：收束后停止修改；候选冻结 = `debug-spec/` 5 份文档 + `candidate.diff` + `candidate-manifest.json`。

## 1. 范围与边界（遵守情况）

- 写入范围：仅 `workflow/runs/20261018-1631_runA_fpga_side_readchannel/debug-spec/**`。
- 上游仓 `upstream/ph1p100-pcie-ep-fpga` **零写入**（收尾核对 `git status --porcelain` 与 HEAD，结果录于 `candidate-manifest.json` 的 `upstream_repo` 字段）。
- **未启动 TD、未调用 bw/hwserver、未连板、未启仿真、未用网络**；`D:/TD`、`D:/downlaod`、`D:/anlogic`、`D:\TD\work\csi2` 仅只读引用。
- 未删除任何文件；未改 `workflow/tasks.json`、`docs/**`、既有 run/证据。

## 2. 产出文件

| 文件 | 内容 |
|---|---|
| `cwc-flow.md` | A0 手段核实（JTAG 无调试核只读路径 = 无文档证据，禁止盲试）+ CWC 工具链可行性/判定条件（setup_debugger、compiled.cwc、校验器、回退触发） |
| `probe-map.md` | CWC 实例决策（1 实例、tl_clk_user、288 bit）+ 调试字库 BAR0 地址表 0x140..0x160 + 探针表（层次名的 P1 复核要求）+ 降级直探清单 |
| `enable-state.md` | CTRL(0x44) 复位默认（全关）+ debug-only 最小默认开启草案（只动 bit0/bit5）+ 板上核验判据 |
| `readback-criteria.md` | 规则绑定（R01—R17 适用项）+ Tier-1/Tier-2 判定 + 采样/非原子/跨域要求 + `run_record.schema` 记录模板（channel 扩展声明 `chipwatcher-jtag`） |
| `board-runbook.md` | P3 下载/读回步骤、ASCII 路径与 hwserver 参数、≥2 样本/≥10 s、失败保留、DDR 校准断电 10 s SOP、回退、记录表、审计清单 |

## 3. 关键决策（冻结）

1. 读回载体：1 个 CWC 实例 + 调试字库 `dbg_bank`（9 字 = 8 个 A 组字 + CTRL 读回字）；常量字（MAGIC/EXT_MAGIC/EXT_VERSION）经字库承载以便同实例采样。
2. 字库 BAR0 表 0x140..0x160（非合同 diag，先例 0x120..0x12C）；选址经 `contract/registers.json` 只读检索无冲突；保留“顺延 + candidate diff”规则。
3. 使能：默认未开采集/写存 → 允许 debug-only 最小开启（仅 `ctrl_enable`/`ctrl_ddr_en`），主机面（push/TX）一律保持关闭。
4. B 组（DDR_STATUS/PUSH/CAM_DROP）按条件加装（默认第二同域实例），不并入 A 组样本。
5. 判据与阈值不新造：全部绑定 registers-plan / expected_rules / dev-plan §5；旧 bit 并列不混拼。

## 4. 局部检查（本包实际执行）

- 收尾执行：上游 `git status --porcelain` 零写入核对、上游 HEAD 记录、7 份文件 SHA256、判据锚点抽验（0x50434946 / 0x31414B52 / 0x00010000 / 2,592,768 / 0xFFFFFE10 / 字库地址 0x140/0x15C/0x160）。
- 结果与命令元数据：录于 `candidate-manifest.json` 的 `checks` / `upstream_repo` 字段；`candidate.diff` 覆盖 5 份候选文档（dev-notes/lessons 为过程记录，SHA 亦在 manifest 中）。
- 未执行：TD/仿真/板测（本包禁止）；未核 PDF/二进制文档（见 `cwc-flow.md` §1 限制）。

## 5. 未测边界与开放项（交 P1/P2/P3）

- P1：elaboration/仿真复核探针层次名与 CWC 容量（字库 288 bit 是否单实例可行的最终判定）；`img_frame_src`/顶层对 `ctrl_enable`/`ctrl_ddr_en` 的门控复核；字库选址最终定案。
- P2：`setup_debugger` 在 TD 2026.2 的实跑 + `check_chipwatcher_readback.py` 0 失败 + bit/CWC 配对 SHA。
- P3：按 runbook 执行；Tier-1/Tier-2 按 criteria 判定；DDR 校准异常由用户断电处理。
- 本包不构成任何硬件或构建结论（G1/G2/G3 not_run）。

## 6. 回退

- 回退 = 丢弃 `debug-spec/` 整个目录即可（无上游写入、无硬件动作、无 bit 变更）。
