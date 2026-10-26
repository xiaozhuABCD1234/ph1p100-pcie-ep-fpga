# run notes — T01.board_and_tmst7700 / G（TMST-7700 最小调查）

- 日期：2026-10-17；角色：fpga-dev；状态：done（只读调查）
- 产物：`docs/TMST-7700最小调查_2026-10-17.md`、`docs/evidence/tmst7700_20261017.json`
- 本目录辅助脚本（只读检索，未触碰候选/证据）：
  - `tools_g_scan_bytes.ps1`（二进制多模式逐字节扫描，ASCII/UTF-16LE/BE）
  - `tools_g_pdf_search.py` / `tools_g_pdf_pages.py`（PyMuPDF 文本层检索/页提取）

## 关键命令与结论（摘要）

1. 原文：两候选 `native_route.txt` 各 3 条 TMST-7700（1/4/4），行号 1333=1371/2068/2177、ctl=1498/2230/2339；`td_*.log` 同行号同内容。tee 日志仅尾部各 1 条。
2. 定义：6.2.3 `SWUG117` PDF p43 附录：`TMST-7700 = check_timing report 中发现 severity 为 HIGH 的问题`；`TD_User_Guide_V6.2` p214 §9.3.7.2 同义；6.2.2 安装 User Guide p206 亦已收录（文档先行）。
3. 检查本体：`SWUG201` §3.3 Check Timing Report（约束完整性/合理性问题，Severity 列 HIGH=影响较大）；`SWUG105` §4.10.8 `check_timing`（14 类默认检查项；可 `-file` 导出）。
4. 引擎差异：6.2.3 `run.exe`（DFB1FE1B…）DRC 家族表含 `TMST`、有 `SEVERE timing constraint` 模板与 `Timing Status Checker` 阶段名；6.2.2 `run.exe`（BFE702E3…）三者皆无（字面 `TMST-7700` 在两代安装资源中均不存在，运行期组装）。
5. 6.2.2 对照：4 候选 `native_route.txt` TMST=0、无 "Timing Status Checker" 阶段、DRC 行 16/候选（SLATR-1038×10、RTCLK-5078/5079）；002820 六个 `td_*.log` 复核=0 → 同阶段静默（未跑该检查）。
6. SDC：三工程 `timing.sdc` 逐字节相同（`0C32C5F7…`），无 input/output delay；与告警出现无因果关系。
7. 判定：分类=**新严格性检查（工具版本行为）**；bit 有效性无直接影响；STA 主结果不推翻；4 条明细未枚举=已知边界（建议另批 `check_timing -file` 只读枚举）。

## G-2 续接（2026-10-17 晚，明细枚举；只读、候选零写入）

- 对象：1333 `csi_checked_debug_pr.db`（post-route；bitgen 同 checkpoint）+ place 对照 `csi_checked_place.db`；
- 方式：整目录拷贝到 `%TEMP%\opencode\tmst7700_detail_20261017\prj_1333_copy`（312 文件/123.5MB），仅拷贝内 `.al` 做 Path 归一化；`import_device → open_project → import_db → update_timing -mode final → check_timing -file -verbose [→ report_drc -file]`；两会话 exit 0（32.3s/16.7s）；
- 复现：`report_drc` 得到 `TMST-7700#1 … 4 SEVERE`（与候选 route 日志一致），并同现 CLKST-8015#1、RTCLK-5078#1；
- 明细（HIGH）：clock_definition=3（local clocks：`config_inst.cwc_tck_o`/`mclk27`/`mipi_a_byte_clk`）+ pll=1（`pclkx5` 742.400024 vs 742.500000）+ dummy_node=3（BANKREF/HR_PAD/LSLICE 组）；no_clock/组合环/无效约束/生成时钟失联=0；
- 计数对账：flow place=1=pll；route=4=clock(3)+pll(1)；dummy_node 不计入 flow 计数；
- 结论：**可结案，建议关闭 M5.7**（无 SDC/waiver/RTL 改动 ⇒ 无复测清单）；`mipi_a_byte_clk` local 属性↔0.230ns 最薄裕量属 M5.5 窗口；pclkx5 取整差异 0.0135% 记观察；
- 候选零写入证明：pre/post 快照（312 文件）逐字节相同，快照文件 SHA 同为 `016D89C9…`；
- 产物（run 目录）：`tmst7700_detail_1333.rpt`（`4710AA01…`）、`..._place.rpt`（`99C7FC5B…`）、`tmst7700_drc_1333.txt`（`9649D296…`）、两运行日志、两 tcl、两快照。
