# handoff — 20261027-055621_fpga-honly-td-and-ah（2026-10-27 10:10，冻结）

本 run 已收尾（`dispatch.status=finished`）。本文件给后续规划/新 run 的接手信息；详细数字见 `final-summary.md`、`dual-verdict.md`、各任务 `r*/result-*.md` 与测试报告。

---

## 1. 现在有什么（可用路径，全部只读）

### 1.1 唯一候选（临时状态）

| 文件 | SHA-256 | 字节 | 来源 |
|---|---|---:|---|
| `T10.ah-honly-synthfix/r0/changed-src/a1_deflate_core.v` | `d2960cfe0111b7b61aff281e3f16427834dda26107f37867d5c7c89ac346aad8` | 85,221 | synthfix（H-only r1 `8acd20b2…` + 复位合并 +4/−3 行） |
| `…/a1_frame_top.v` | `4afc26e246fbae4e32c5ab7e88dffb496048d10966c5ee42b290b3e71f60e30a` | 29,207 | 与 H-only r1 逐字节相同 |

- synthfix 冻结 manifest：`T10.ah-honly-synthfix/r0/manifest-r0.json` SHA `034777c5…5e510`（75 artifacts，测试者 PASS）。
- **状态 = provisional**：功能/性能 prototype gate 通过 + 可综合；**routed 实现资格 not_evaluated**。

### 1.2 证据包

| 内容 | 路径 | 关键 SHA / 数字 |
|---|---|---|
| H-only r1（4 帧 prototype gate） | `workflow/runs/20261026-231711_fpga-a-plus-h-prototype/T10.ah-honly/r1/**`（只读） | manifest `f752ae09…`；N4 6,196,749.5 / L4 5,834,940；`n-4f.frm b9cb5359…`、`n-4f.hdr c7fe281c…`、`l-4f.frm 8aad9099…`、`l-4f.hdr 864d2fba…` |
| A 的 kill 证据 | `T10.ah-a-plus-h-r2/r0/**` + `test-reports/T10.ah-a-plus-h-r2-r0-integrated.md` | manifest `59805d90…`；kill_verified |
| synthfix 证据 | `T10.ah-honly-synthfix/r0/**` + `test-reports/T10.ah-honly-synthfix-r0-integrated.md` | manifest `034777c5…`；PASS |
| TD r0（elaborate 拒绝） | `T10.ah-honly-td/r0/**` | manifest `75daa947…`；`HDL-8007` L673/L964 |
| **TD r1（综合成功 + 布线崩溃）** | `T10.ah-honly-td/r1/**` + `test-reports/T10.ah-honly-td-r1-integrated.md` | manifest `8325f230…`（83 artifacts）；gate DB `169d5937…` |
| 综合报告 | `T10.ah-honly-td/r1/reports/{synth-187.5.md,resources.md,critical-path-attribution.md,cdc-and-check-timing.md,routed-sta.md}` | WNS +0.029 / 0 of 4,969 / coverage 97.06% / ERAM 27 / IO 121 / slice 3,337 |
| 布线崩溃原始证据 | `T10.ah-honly-td/r1/td/run-route1/**`、`run-syn1/route_console.log` + `minidump-20261027-093503.dmp` / `-093540.dmp` | `import_db → Import ChipWatcher → coredump`，placement 之前 |
| 三轮裁决 | `r0-ruling.md`、`r1-ruling.md`、`r2-ruling.md`；本轮 `dual-verdict.md` | — |

### 1.3 工具/复现

- ModelSim Intel FPGA Edition 10.5b（`D:/intelFPGA/18.1/modelsim_ase/win32aloem`）；Python 3.11.5。
- TD `D:/anlogic/TD_Release_2026.2`（**6.2.3.210850**）；`td_commands_prompt.exe ./x.tcl`，cwd = run 目录，全部绝对路径。
- 盘符：本 run **未占用** `T:`（属 board-integration run）；`Y:` = 项目根。

---

## 2. 能说 / 不能说（不得越界）

**能说**：H-only 4 帧 prototype S_ss 达门槛且逐字节正确；synthfix 版可被 TD elaborate/综合，187.5 MHz **gate-level** 正余量 +0.029 ns、资源低；布线未完成的原因是 TD 6.2.3 ChipWatcher 导入崩溃（2 次、有 minidump）。

**不能说**：H-only 已过 TD/STA、时序收敛、routed WNS/hold、真实 Fmax、G0 整机闭合、1080p30 生产吞吐、位流/板级/CWC/RK/PCIe、A+H 不可行。

---

## 3. 剩下什么（下一包，需用户授权）

**A. TD 布线绕行包（推荐，需新 TD 配额）**
- 目的：拿到 routed DB → routed STA，补齐唯一缺失事实。
- 建议配额：TD 启动 ≤3、synth ≤1（如需重建 DB，必须写明与 r1 的区别）、route ≤2、**bitgen 0**、analysis ≤1、≤60 calls/180 min、0 板卡。
- 允许尝试（每项记录参数差异）：① 排除 ChipWatcher/debug 负载后重新生成/导入；② 改导入方式（`open_project` 后直接 `launch_runs phy_1`，不先 `import_db`）；③ 换 TD 版本/重装；④ 2 文件 + wrapper 的最小工程复现崩溃再绕行。
- 门槛：routed WNS≥0、hold≥0、`NUM_FEPS=0`、ERAM+CWC≤300、slice≤71,680、IO≤286、coverage/check_timing/CDC、≥10 路径归因；209.6 仅 analysis-only。
- 失败出口：记 `implementation not evaluated (tool defect)`，候选仍 provisional。

**B. 新权威仓 H-only diff 迁移评审（只读）**
- 目标仓库：`D:/fpga/repos/ph1p100-pcie-ep-fpga`（`main`），只读评审 `rtl/ep_side/codec/` 与 H-only/synthfix 的差异，产出映射清单与适配建议。
- **不写入、不 commit、不 push**；落库需用户单独授权。

**不建议**：routed STA 缺失时重开 A、加宽 A、直接 bitgen/板上板。

---

## 4. 保护与回退

- 只读保护：本 run 全部任务目录（证据已冻结）、`20261026-231711_fpga-a-plus-h-prototype/**`、`20261026-2138_fpga-integrated-delivery/**`、`20261026-143924_...`、`20261026-144617_...`、`T10.b18/b19/b20/**`、`fpga/csi2/src/**`、`upstream/**`、`tools/td/**`、`workflow/tasks.json`、`docs/**`、`.agents/**`、`D:/TD/**`、`D:/fpga/repos/**`（除用户授权的新评审目录）。
- 回退：功能口径可回退到 H-only r1（`f752ae09…`）的 4 帧 prototype 结论；可综合性回退到 synthfix（`034777c5…`）。两者均有完整 manifest，不依赖叙述。
- 删除：一次只删一个明确路径文件；批量删除需用户手动处理。

---

## 5. 恢复 / 新 run 文本

**恢复本 run（只读复盘/追责）：**
```
恢复：D:\fpga\ph1p100\workflow\runs\20261027-055621_fpga-honly-td-and-ah；本轮目标：<目标>
```

**新 TD 布线绕行 run（建议）：**
```
/fpga-orchestrator 执行：承接 20261027-055621_fpga-honly-td-and-ah 的 H-only 候选（core d2960cfe… / frame_top 4afc26e2…，synthfix manifest 034777c5…）。目标：绕过 TD 6.2.3 在 import_db→Import ChipWatcher 的 coredump，取得 routed DB + routed STA（187.5 MHz），必要时做 209.6 MHz analysis-only。门槛：routed WNS≥0、hold≥0、flow.status NUM_FEPS=0、ERAM+CWC≤300、slice≤71680、IO≤286，附 check_timing/CDC 与 ≥10 条路径归因。配额：TD 启动≤3、synth≤1、route≤2、bitgen≤0、analysis≤1、0 板卡/网络；先在最小工程复现崩溃再绕行；不得改 RTL/SDC/时钟/例外。证据与边界：D:\fpga\ph1p100\workflow\runs\20261027-055621_fpga-honly-td-and-ah\dual-verdict.md 与 handoff.md
```

**新仓迁移评审 run（只读，不 push）：**
```
/fpga-orchestrator 执行：对 D:\fpga\repos\ph1p100-pcie-ep-fpga（main）做只读 diff 映射评审，比较 rtl/ep_side/codec/ 与 H-only/synthfix 候选（d2960cfe… / 4afc26e2…），产出迁移清单与适配风险；0 TD、0 改写、0 commit/push。
```
