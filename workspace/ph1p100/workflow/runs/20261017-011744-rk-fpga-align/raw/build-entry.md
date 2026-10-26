# build-entry.md — T11.rk-align-raw 可复现入口（冻结输入）

本文件记录**实际使用**的入口与命令；所有命令从项目根执行。工具版本：TD Release 2026.2
（`td_commands_prompt.exe`，实测 6.2.3.210850 / Tcl 8.6.17）、ModelSim ASE 10.5b
（`D:\intelFPGA\18.1\modelsim_ase\win32aloem`）。

> `tools/pcie_integration/*.ps1` 的 **UTF-8 BOM 是功能性要求**（T07 round3 修复：
> PS 5.1/ACP=936 下无 BOM 会吞换行导致入口中止）。编辑必须保留。

## 1. G1（ModelSim，真实 RTL）

统一入口：

```powershell
powershell -ExecutionPolicy Bypass -File tools/pcie_integration/run_sim.ps1 `
  -Tb <顶层TB模块名> `
  -OutDir workflow/runs/20261017-011744-rk-fpga-align/raw/g1/msim/<evid> `
  -TbFiles <相对 fpga/csi2/pcie_integration/sim 的 TB 文件> `
  -Defines MIPI_PHY_SIM_STUB
```

本包实际跑过的（证据目录 → TB）：

| 证据目录（raw/g1/msim/） | TB | 说明 |
|---|---|---|
| `p1_writer_v4` | `tb_cam_r10f_writer` | 写者 P0..P10（冻结向量、坏帧、所有权、复位、溢出、1080p 边界；v3 为同一输入的标签修正前运行，保留） |
| `p2_e2e_v6` | `tb_t11_r10f_e2e` | 小几何全链路 E0..E4（CSI→写者→DDR→pusher→host 模型/TL 监视） |
| `p3_enable` | `tb_t11_csi_enable_corner` | T07 遗留：`I_enable` 包尾后 1 拍撤销角落（诊断计数回归钉） |
| `r_t07_pusher` | `tb_ddr_frame_pusher_rka1` | T07 回归（安全门/容量/超时/长 stall/完整 1080p 20,256 MWr） |
| `r_t07_diff` | `tb_csi_integrity_diff` | T07 差分 oracle 回归（680 拍 0 失配） |
| `r_t07_checked` | `tb_csi_checked` | T07 checked wrapper 回归 |
| `r_t07_bar` | `tb_ep_bar_win_rka1` | T07 寄存器面回归 |
| `r_t07_arb` | `tb_ddr_wr_arb` | T07 A/B AXI 仲裁回归 |
| `neg_m1_pack_order` | `tb_t11_r10f_e2e` + `tb_cam_r10f_writer`（隔离树） | 可重放负对照（M1：packed 低 2bit 顺序换反 → 两 TB 均 FAIL） |

编译清单：`fpga/csi2/pcie_integration/sim/compile_checked.f`（含 `cam_r10f_writer.v`；
`crc32_upd4.v` 由写者 `include`，不单独编译）。TB 由 `-TbFiles` 追加。

## 2. G2（TD 单会话：syn + phy + bit）

```powershell
powershell -ExecutionPolicy Bypass -File tools/pcie_integration/run_td.ps1 `
  -Stage 00_all `
  -OutDir workflow/runs/20261017-011744-rk-fpga-align/raw/candidate/prj
```

* 入口 `tools/pcie_integration/td/00_all.tcl`（单会话；`01/02/03` 分阶段脚本仅参考，
  TD 分阶段会丢 `device_name/package_name`）。
* 不执行 `download_sram.tcl`、不下载、不写 Flash、不 reset/clean 任何既有工程。
* 中文路径由 `run_td.ps1` 自动临时 subst（用完撤销；`R:` 由脚本替换为目标根）。
* 判据（engineering 复测）：同一最终 DB（`phy_1/*.db` 与报告）`Routed`、
  setup≥0/STNS0/hold≥0、资源≤器件、bit 与 DB 同源 SHA。

## 3. 离线工具（Python 3，stdlib）

```bash
python tools/pcie_integration/r10f_strict.py selftest          # 复算合同验收向量+全部负例
python tools/pcie_integration/r10f_strict.py gen --preset 1080p --out <file>
python tools/pcie_integration/r10f_strict.py check <file> --session 0x20261017
python tools/pcie_integration/r10f_tools_consistency.py        # Rust/Python 解析器字段偏移交叉核对
python tools/pcie_integration/gen_manifest_t11.py --root <项目根>   # 重生成 raw 清单+自检
```

## 4. RK 增量（只离线校验，不写 peer 仓库）

```bash
git apply -p1 --check raw/patches/t11-rka1-r10f-fix.patch     # 基线 = backend/rk-driver-src
```

记录见 `raw/patches/apply-check-stat.txt`；完整体树 `raw/rk-driver-src/`。
