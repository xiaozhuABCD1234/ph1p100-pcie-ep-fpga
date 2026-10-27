# dev-notes — T01.tool-E1（DDR1333 候选派生 + 1600ctl 控制派生）

- 角色：fpga-dev（E1）；日期：2026-10-17；run：`workflow/runs/20261017_153201_T01_ddr1333_integration/`
- 依据：`dev-plan.md` §4.1（断言 1–8）、`fpga-design-guide.md` §2/§4/§5。**本批不做任何构建**（综合/route/STA 属 E2）。
- 状态：**ready-for-test**（脚本与两候选已冻结；冻结后仅做只读核验，无后续修改）。

## 产物

| 产物 | 路径 | SHA256（摘要） |
|---|---|---|
| 准备脚本（仓库，新建） | `tools/td/prepare_rgb565_ddr1333.py`（26,237 B） | `a37cb9cd…`（frozen 拷贝同字节） |
| 1333 候选 | `D:\TD\work\csi2\prj\camera_rgb565_ddr1333_20261017_160741` | `input_manifest.json` `ffcb5231…`（221 项）；`ddr1333_overlay.json` `f6deec4f…`；共 223 文件（221+manifest+overlay） |
| 1600ctl 控制候选 | `D:\TD\work\csi2\prj\camera_rgb565_ddr1600ctl_20261017_160741` | `input_manifest.json` `a8505cd4…`（221 项）；`ddr1333_overlay.json` `ca85c2a5…` |
| 证据 JSON | `docs/evidence/ddr1333_integration_20261017.json` | 完整 SHA 见该文件 |
| 运行日志（本目录） | `dev-notes-E1-run-ddr1333.log` / `dev-notes-E1-run-control.log` | 实际 stdout 全文 |

## 运行记录（实际命令/退出码）

- 默认模式第 1 次尝试（16:07 前）在 A5 处因脚本自身 bug 中止：`BASE/IP_PREFIX+'ddrmc_x32.v'` 路径拼接优先级错误（`TypeError`）。断言先于 `mkdir` 的设计生效——**未创建任何目录/文件**（无部分产物）。修复该 4 处表达式后重跑。
- 默认模式第 2 次（16:08:47–16:09:05）：A1–A9 全 PASS，exit 0，产出 1333 候选。
- 控制模式（16:09:05–16:09:20）：A1–A9 全 PASS，exit 0，产出 1600ctl 候选。
- 命令：`& 'C:\Program Files\Python311\python.exe' -X utf8 -B <repo>\tools\td\prepare_rgb565_ddr1333.py [--control] --timestamp 20261017_160741`（`-B` 避免写 `__pycache__`；`--timestamp` 用于两候选配对命名）。stdout 见两个 `.log`。

## 断言结果（dev-plan §4.1 断言 1–8 + 结果自检，全 PASS）

| 组 | 内容 | 结果 |
|---|---|---|
| A1 | 002820 manifest `8f8e4efe`（220 项）+ bit `4d591c31` 复算；逐项 SHA 全过 | PASS |
| A2 | run1 `candidate_manifest.json` `d71057f3` / 64 项逐项 SHA+size 复算；run2 镜像 `9b3e5d00`（+diff `579be12a`、semantic `9b30df65`）仅登记**不复制**（单源） | PASS |
| A3 | 新闭包 11 个关键锚（xml/v/wrapper/.params/.m_params/Design/src adc+sdc/三日志）+ 引导 `input_pins.adc` `f0904238` + boot `.al` `ef721c4d`（旁证）复算 | PASS |
| A4 | `.params`：1333.00 / DDR3-1333J / CWL7 / tCK1500；`.m_params`：CL10 / PLL0 FBK80+REFDIV3 / PLL1 166.7 | PASS |
| A5 | `ddrmc_x32.v` 端口 53 行新旧**完全一致**；wrapper 更名（模块 `ddrmc_x32_ph1p_ddrmc_wrapper`、含 `MC0_DDR3_1333J`）；例化名 `ph1p_ddrmc_wrapper` 保持；`.tCK(1500)`（旧 `.tCK(1250)`）；src/adc 17 条 `set_ipinst_assignment` 前缀均 `ph1p_ddrmc_wrapper/ph1p_ddrmc_top/` | PASS |
| A6 | xml 文件表 52 项 52/52 在磁盘存在（无悬空）；磁盘 61 = 52 + 9 项允许外件（**逐项有内部引用**，见下"偏差"）；`fileset_mis.f` incdir 与两 `.vh` 的 include 引用实证 | PASS |
| A7 | 60 同名文件机器核算：**33 逐字节一致 / 27 不同**（与 guide §2 清单精确一致）；旧 wrapper 移除 / 新 wrapper 加入各 1；日志 adc=changed、drc=**same**、proc=changed | PASS |
| A8 | 6.2.3 工具锚复算：CLI `2629e474` / td `fa2a5ac6` / IpTool `5b0654aa` / arch `939ec294` / license `dc19fee6` | PASS |
| A9 | 候选冻结：写 frozen 脚本前后计数 220→**221**；manifest 不含 manifest/overlay 自身；范围外 156 项逐字节=002820、33 一致项零漂移、27 变更项=run1、旧 wrapper 不存在 | PASS |

## 与计划的两处偏差（如实记录，不掩盖；均已机器核算+留证）

1. **差异条目 31 vs 计划字面 32**：dev-plan §4.1.7(d) 预估 "27+3 日志+1 移+1 增=32"；实测 `vendor/ip/ddrmc_x32_drc_check.log` 新旧**逐字节相同**（`75721975…`，工具 DRC 输出确定），实际 31 条。变化集合仍 ⊆ 64 文件替换范围、范围外 0 差异——断言效力不变。
2. **xml 闭包外件 9 项 vs 计划字面 5 项**：实测磁盘比 xml 文件表多 9 项 = 计划所列 5 项元数据（Design/DesignConfiguration/.params/.m_params/.ports）**+ 4 项**：`ddrmc_x32.xml` 自身、`sim/fileset/fileset_mis.f`（仿真 fileset，声明 incdir）、`src/rtl/include/ph1p_mis_define.vh` 与 `src/rtl/phy/include/ph1p_ddrphy_board_delay.vh`（被 `mc0_alc_mc_top_all.enc.sv` / `ph1p_ddrphy_wrapper.v` / `ph1p_ddrphy_fast_init_wrapper.v` include）。脚本改为 **exact-9 等值断言**（强于字面子集），偏差与理由入 overlay `closure_extras_deviation`。

## 未做/边界（如实）

- 无 build/route/STA/bitgen、无 GUI、无任何硬件动作；E2 才构建。
- **runner 骨架未预置**：dev-plan §4.2 将 `tools/td/run_rgb565_ddr1333.py` 明确划归 E2 新写（继承 `run_rgb565_native.py` 断言下限并扩展）；E1 不引入未测代码以免产生"断言下限"歧义。派发注记允许"可含 runner 骨架"为可选项，未选。
- `.params` 中 `PH1P_IO_ASSIGN` 仍指 run1 引导目录 `input_pins.adc`（`F0904238…`）——**保留原样**（生成溯源；实际构建引脚=闭包 `src/adc` + `board.adc`）。
- 002820 零漂移：运行后复算 manifest `8f8e4efe` / bit `4d591c31` 未变；`_validation` 目录只读引用（脚本仅读）。
- 本批未改 `timing.sdc` / `board.adc` / 任何 RTL（候选内 .v 与 002820/run1 逐字节对应，机器断言）。

## 测试者复现入口（系统维度廉价复跑）

```powershell
& 'C:\Program Files\Python311\python.exe' -X utf8 -B `
  'C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道\tools\td\prepare_rgb565_ddr1333.py' `
  --timestamp <新时间戳>          # 或 --control；绝不覆盖既有目录
```

- 功能复核点：`input_manifest.json` 221 项逐项 SHA；`ddr1333_overlay.json` 的 `changes`（29）/`removed`（1）/`added`/`diff_accounting`/`unchanged_guards`/`closure_extras`。
- 工程复核点：002820/run1/run2 锚复算零漂移；候选目录名含新时间戳且 `exist_ok=False`；仓库脚本 SHA = 两候选内 frozen 脚本 SHA（`a37cb9cd…`）。
- 系统复核点：本 notes + 证据 JSON 与磁盘一致；E2 消费入口=`input_manifest.json`+`ddr1333_overlay.json`（build/route tcl 由派生自带，无需重写）。
