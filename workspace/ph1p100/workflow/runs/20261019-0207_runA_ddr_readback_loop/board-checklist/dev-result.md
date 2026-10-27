# dev-result.md — T11.runC-board-checklist（P4，round0）

- run：`20261019-0207_runA_ddr_readback_loop`｜角色：fpga-dev（opencode 子会话，0207 线 P4）｜时间：2026-10-19 19:0x–19:3x +08:00
- 状态：**awaiting_user_gui**（清单/证据已冻结；G3 待用户“回来点两下”）
- 冻结 manifest：`board-checklist\candidate-manifest.json`

## 1. 交付内容

| # | 产物 | 说明 |
|---|---|---|
| 1 | `evidence-index.md` | 哈希链证据索引：RTL diff → P1 manifest → P2 manifest → bit/CWC/BID → P3 manifest → test-reports；**56 项复算 0 不一致、0 缺失** |
| 2 | `hash-chain-recompute.txt` | 逐项 `MATCH|组|路径|SHA256|字节` 原始日志（含 P2 manifest 完整 SHA、worktree HEAD/status、diff apply rc、暂存 SHA） |
| 3 | `recompute-hash-chain.ps1` | 可复跑复算脚本（只读冻结件；若暂存目录已存在则 `STAGE_COLLISION_NO_COPY` 不覆盖） |
| 4 | `board-checklist.md` | “回来点两下”清单：板载现状只读检查、可选 SRAM 预加载（≤1 次/≤5 min）、GUI 16 字步骤、冻结预期值（逐字取自 `build\hardware-ready.md` §2 / `board_expected`）、异常分流、两分支、G3 tier 口径 |
| 5 | `rollback.md` | 回退文档更新：新旧候选并列（SHA/路径/字数）、重下旧 bit/断电/丢弃产物、禁用项 |
| 6 | 暂存物料（D:，未下载） | `D:\anlogic\runa_runC\20261019_192056\`：`compiled.bit`、`compiled.cwc`（SHA 复核 MATCH）、`preload.bwcmd`（未执行）、`staging-record.txt` |

## 2. 局部检查（实际命令/结果）

- 复算：`powershell -NoProfile -ExecutionPolicy Bypass -File workflow\runs\20261019-0207_runA_ddr_readback_loop\board-checklist\recompute-hash-chain.ps1`
  - `SUMMARY total=56 mismatch=0 missing=0`；分组：P1 5 + P2 19 + P3 19 + worktree 9 + P3 新 TB 2 + 旧候选保护 2。
  - worktree：HEAD `b0282d2a…` 未变；与 P3 冻结一致的 6 M + 4 ??（本包只写 run 目录与 D: 暂存，不写 worktree、不 commit/push）。
  - diff：`git apply --check --cached`（HEAD→index）rc=0、`--reverse`（worktree→HEAD）rc=0；8 个 `diff --git`、2 个新文件、NUL=0、UTF-8 无替换字符。
  - bit/CWC 暂存副本 SHA：`5B67A8F5…1D52` / `8DDA54D4…664F` 均 MATCH；源文件 `phy_1\…bit` 与 `cw\compiled.bit` 逐字节相同。
  - 旧候选保护：`bfafdf97…`（bit）/`8d2998b9…`（CWC）SHA256 复算不变。
- 文档一致性自检：`board-checklist.md` 的预期值逐项取自 `build\hardware-ready.md` §2（该文件 SHA `1dbb8136…` 已在 56 项内复算 MATCH）；字表偏移/位域取自 `checker-integrate` P1 manifest 的 `g0.words_map`；tier 结构对齐基线 `readback-criteria.md`；G3 判定权明确留给综合测试者+原规划。

## 3. 未执行项（如实登记）

1. **可选 SRAM 预加载未执行**：按互斥规则下载前须由在场用户确认板窗空闲；本包运行期间（19:14 起）并行线 0212 在本机运行 TD 构建（`recovery01/B01/timing-continuation01/remaining-attempts01/scripts/run_build.py` 进程活跃），且无法在预算内获得在场确认 → 不占用板窗/USB、不下载。暂存物料 + `preload.bwcmd` 已备好（零覆盖），清单 §2 覆盖“回来先重下”分支。
2. **未执行任何连线/只读设备查询**：未 `connect_cable`、未 `read_device_id`、未 `download`；零 flash/efuse/SPI/svf。板载现状 = unknown，清单 §1 给出回来后第一步只读检查。
3. **用户 GUI 点击未发生**：返回 `awaiting_user_gui`；两样本读数/时间戳待用户回传（清单 §3/§5）。
4. G3 判定 not_run；G2 继承 P2 PASS（本包不复算）；G4 not_run。

## 4. protected 审计 / 边界

- 未写：worktree（HEAD 未变，状态同 P3）、共享树 `upstream\ph1p100-pcie-ep-fpga`（0212 写域）、P1/P2/P3 冻结件、基线 run、旧候选、`workflow\tasks.json`、TD 安装目录。
- 未动既有 `td`（PID 45416）/`hwserver`（PID 49924）实例；未新建 hwserver；未启动 TD/BW；无 GUI 自动化。
- 写入仅：run `board-checklist\**`（本包产物）与 `D:\anlogic\runa_runC\20261019_192056\**`（新建/复制，零覆盖、零删除）。
- 无 commit、无 push；无批量删除。

## 5. 回退

- 丢弃 run `board-checklist\**` 与 D: 暂存目录即可（默认不删；确需删除按根 AGENTS 单文件路径或交用户）。
- 板上如需恢复：按 `rollback.md` §2 重下旧 bit（SRAM，≈30–40 s）或断电；不写 Flash。

## 6. dev-notes（允许清单 / 理由 / 备注，合并本节）

- **允许清单（写入范围）**：`workflow\runs\20261019-0207_…\board-checklist\**`（证据索引、清单、回退文档、复算脚本/日志、manifest、本文件、lessons）；`D:\anlogic\runa_runC\20261019_192056\**`（新建/复制：bit/CWC 暂存、`preload.bwcmd`、`staging-record.txt`）。
- **理由**：P4 为文档+证据包，唯一新增物理动作为可选 SRAM 预加载；所有冻结读数以 P1/P2/P3 manifest 为准，不重建、不重算构建/仿真。预加载为“尽力而为”，未获窗口确认即不做，清单兜底。
- **过程登记**：
  - 首次哈希脚本内联执行因 `Encoding::GetEncoding` 重载写法错误中止（**未产生任何哈希/暂存副作用**，仅创建空暂存目录）；改写为可复跑脚本 `recompute-hash-chain.ps1` 后完整通过（空目录被复用、零覆盖）。如实计入调用预算。
  - 控制台中文乱码为输出代码页现象（文件本体 UTF-8 正常），同 P1/P3 观察。
  - 尽力保持在冻结预算内（≤30 calls / ≤45 min，含一次脚本自纠重跑与静止等待）；因预算边界未追加硬件尝试，属主动有界停止而非证据缺失。

## 7. lessons（指针）

见 `lessons.md`。
