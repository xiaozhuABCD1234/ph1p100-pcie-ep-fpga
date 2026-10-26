# build-entry.md — T07.rk-align-backend 构建/复现入口

## 1. 仿真（G1 局部检查）

```powershell
# 项目根下；脚本会临时 subst 一个 ASCII 盘符给 ModelSim（中文路径会打不开），用完自动撤销
powershell -ExecutionPolicy Bypass -File tools/pcie_integration/run_sim.ps1 `
    -Tb <tb_module> -OutDir workflow/runs/20261017-011744-rk-fpga-align/backend/g1/msim/<name> `
    [-TbFiles tb/<file>.v] [-Defines MIPI_PHY_SIM_STUB]
```
五个 TB（都在 `fpga/csi2/pcie_integration/sim/tb/`）：

| TB（vsim 模块名） | TbFiles | 说明 |
|---|---|---|
| `tb_ddr_frame_pusher_rka1` | `tb/tb_ddr_frame_pusher_rka1.v` | 推帧安全门 + A/B 跨源 release + 1080p 长度边界 |
| `tb_ep_bar_win_rka1` | `tb/tb_ep_bar_win_rka1.v` | 寄存器合同（含 RKA1 扩展） |
| `tb_csi_checked` | `tb/tb_csi_checked.v` | checked CSI + 写者发布裁决/所有权（需 `-Defines MIPI_PHY_SIM_STUB`） |
| `tb_ddr_wr_arb` | `tb/tb_ddr_wr_arb_peer.v` | peer 原 arb TB 回归（**注意：文件叫 _peer，模块名仍是 `tb_ddr_wr_arb`**，`-Tb` 要填模块名） |
| `tb_csi_integrity_diff` | `tb/tb_csi_integrity_diff.v` | round2 差分 oracle：重构版 vs `tb/csi_rx_packet_integrity_ref.v`（只读原源的重命名副本，已进 `compile_checked.f`），逐拍比对 + 随机/边界流量 |

工具：`D:/intelFPGA/18.1/modelsim_ase/win32aloem/{vlog,vsim}.exe`（ModelSim 10.5b）。
日志：每个 OutDir 里 `vlog.log`（编译，含 Errors/Warnings 计数）、`vsim.log`（仿真 transcript）、
`vsim_stdout.log`、`commands.log`（完整命令行 + subst 映射）、`abs.f`（展开后的绝对路径清单）。

**入口稳健性（round3 修复，务必保持）**：

* `run_sim.ps1` / `run_td.ps1` 保存为 **UTF-8 with BOM**（`EF BB BF` 前置，内容其余逐字节不变）。
  原因：Windows PowerShell 5.1 在 ACP=936 下按 ANSI 解码**无 BOM 的 UTF-8**会"吞"换行——源 144 行
  在 PS 视图只剩 136 行，`$doPath`/`$tclDst` 语句会被并进上一行中文注释，脚本在写 `run.do`/复制 tcl 前
  以 `WriteAllLines 空路径名是非法的` 中止（r2 functional FAIL 的唯一原因，详见 `change-report.md` §10.1）。
  **改这两个文件时必须保留 BOM**（或改注释为纯 ASCII / 统一 CRLF，但需重跑本节的复核）。
* **判据看产物，不看进程退出码**：`-File` 下该 .NET 异常类中止的退出码也是 0。合格 = 三个产物齐备：
  `vlog.log` 末行 `Errors: 0` + `run.do` 存在 + `vsim.log` 有完成标记（`ALL PASS` 等）。
* 本机已按文档化命令原样复核（PS 5.1/ACP 936）：五个 TB 全链通过（`backend/g1/msim/r3_*`，含 `run.do`/`vsim exit=0`）；
  入口负对照（修复前失败留痕）`backend/g1/msim/r3_entry_before_fix/`；oracle 负对照（隔离树注入 M1）
  `backend/g1/msim/r3_neg_m1/`（`FAIL: 507 mismatches`）。
* **round3 复核（新修复实例）**：原 round3 实例上游请求超限失效后，主重建新修复实例接续（write_scope 不变）。
  独立复跑证据在 `backend/g1/msim/r3v_*`（五个 TB 原样复跑全 PASS；M1 完整复跑含 `mutation.json`；
  修复前入口失败复现 + AST 语义校验），与 `r3_*` 一致；manifest 重生成**逐字节相同**（`68f9f4d0…`，
  自检 232/0）。详见 `change-report.md` §10.5。
* `.tcl`（TD 的 Tcl 按字节解析）与 `.py`（Python 3 默认 UTF-8）不受该缺陷影响，未做编码改动。

## 2. 综合 / 布局布线（G2）

```powershell
# 实际入口 = **单会话** create → syn → phy → save_best_bits（英文说明：TD 的 create_project
# 才会把 device_name/package_name 放进会话；另开会话 open_project 再 launch 会得到空的
# settings.cfg，子流程报 can't read "device_name"）
powershell -ExecutionPolicy Bypass -File tools/pcie_integration/run_td.ps1 -Stage 00_all
# 01_create / 02_syn / 03_phy 三个**分阶段脚本仅作参考**（分步预算/复跑参考）：
#   实测在另一个会话里 open_project+launch 会丢设备变量（PRJ-8001/PRJ-8806 类报错），
#   所以不要把它们当作默认入口。
```
TD：`D:/anlogic/TD_Release_2026.2/bin/td_commands_prompt.exe`（Release_2026.2 / Build 6.2.3.210850）。
脚本在 `tools/pcie_integration/td/`，运行时复制进工程目录并把 `R:/` 前缀替换成临时 subst 盘符。

约定（与 peer 原脚本的差别）：
* **不执行** `download_sram.tcl`，不下载、不写 Flash、不 reset/clean 任何旧工程；
* `create_project ph1p_pcie_integration ./ -family PH1 -device PH1P100SBG484 -speed 3`，
  `top_module ph1p_pcie_ep_top`；
* IP 用 `al_ip/` 下**匹配版本**的 xml（pcie_ep_core / pcie_pll_ep / ram / ddr3_mc_0），
  生成物随 xml 一起进工程；不跨 PCIe 版本拼接。

## 3. RK 补丁（离线）

```bash
# 对精确 peer 快照（a0215c5）的新副本：
git apply -p1 --check  backend/patches/rka1-driver.patch     # 应 exit 0
git apply -p1          backend/patches/rka1-driver.patch     # 打上
# 反向：git apply -R -p1 backend/patches/rka1-driver.patch
```
补丁本体：`backend/patches/rka1-driver.patch`（含新文件 `src/anlogic_pci_rka1.c`、`app/rs/src/rka1.rs`）。
内核编译需要真实 RK 内核树/交叉工具链（**本环境无**，未编译；见 rk-change-list.md 的依赖清单）。

## 4. 清单/来源

```bash
python tools/pcie_integration/gen_manifest.py --root <项目根>
# → backend/source-provenance.json（逐文件 sha256 + peer 原样/本包修改/本包新增/本地复制）
# → backend/candidate-manifest.json（冻结候选：生产输入 + 脚本 + TB + 构建产物；含 path_base/volatile_excluded）
# → backend/manifest-selfcheck.json（生成后逐条复算：本轮期望 0 不一致）
```
round1 起 `build_artifacts` **排除易变日志**（`commands.log`、`td_*.log`、`*.logw`、`abs.f`、
`run.do`、`vsim_stdout.log`）——它们每次调用都会追加/重写，纳入清单会让冻结后的任何一次运行
破坏基础哈希（round0 F3）。规则与理由写在 manifest 的 `volatile_excluded` 里；
候选身份由 bit/DB/报告/稳定日志承担。
