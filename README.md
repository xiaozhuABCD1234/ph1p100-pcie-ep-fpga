# 2026-embedded-chip-fpga-ph1p100

米联客 **MLK-F9P**（安路 Anlogic **PH1P100SBG484**）**PCIe Gen2×2 例程**。

原为 `02_fpga_start` 的 pll_test 骨架，现改为 PCIe 例程
（来源：`11_例程/11_3_高速接口与PCIe/12_pcie_gen2x2/`，原属 `02_peripheral_demo.zip`）。
旧骨架已挪到 `_old_pll_test_skeleton/`（不需要可直接删）。

教程：`06_入门与开发教程/03_米联客-安路FPGA开发板演示demo教程.pdf` 第 **144–148 页**（12 PCIE-EP 测试）。
官方参考设计：`doc/APUG081_安路科技PH1P系列FPGA PCIE RC对接EP参考设计.docx`。

## 目录结构

```
2026-embedded-chip-fpga-ph1p100/
├── prj/
│   ├── case_ep/                    # EP 模式工程（★ 对本开发板，器件 PH1P100SBG484）
│   │   ├── ph1p_pcie_ep_top.al               # ← TD 打开它
│   │   ├── ph1p_pcie_ep_top_compress.bit     # 预编译位流，可直接烧
│   │   ├── constraints/  (.adc / .sdc)
│   │   └── al_ip/        (pcie_ep_core / pcie_pll_ep / ram)
│   └── case_rc/                    # RC 模式工程（器件 PH1P100SBG676，属另一块 RC 参考板）
│       ├── ph1p_pcie_rc_top.al
│       ├── constraints/
│       └── al_ip/        (pcie_rc_core / pcie_pll_rc / Comp_inst)
├── rtl/
│   ├── ep_side/      # EP 侧 RTL（top / engine / int_handle / ubus_bridge）
│   ├── rc_side/      # RC 侧 RTL（含 pcie_prbs、si5344_5345）
│   └── common/       # 公共（PCIE_REG_TABLE、TLP_FMT_TYPE、ubus2pcie_apb、uart/…）
├── sim_do/           # 仿真：modelsim/sim.do、vcs/makefile、tb/
├── driver/
│   └── ph1p_pcie_driver/
│       ├── anlogic_pcie_drv/   # 内核驱动（.c/.h + Makefile）
│       └── anlogic_pcie_app/   # 用户态：pci_bar.c、devmem2
└── doc/              # APUG081 参考设计.docx、uart_cmd_file_pcie.txt
```

工程入口（.al）已把内部绝对路径改成当前目录；源文件用相对路径（`../../rtl/...`、`al_ip/...`），
已逐条核对，**引用文件 0 缺失**。

## 上手三步（对本开发板，EP 模式）

1. **烧 EP 位流 → 重启 PC → 建链**
   把 `prj/case_ep/ph1p_pcie_ep_top_compress.bit` 用 TD 下载到板子（或先重编再烧），
   板子插到主机的 PCIe 槽，重启主机，Linux 下 `lspci -s 01:00.0 -vvv` 应看到 **Gen2×2**，
   BAR0/2/4 各 1MB、BAR1 为 IO 256B。
   （烧录步骤见 `anlogic-td-fpga` 技能 / TD BitWriter：Cable = AL-LINK-FT(Local Host)，Local port=5555。）

2. **编译随板驱动**
   ```
   cd driver/ph1p_pcie_driver/anlogic_pcie_drv && make && insmod anlogic_pci.ko
   ```
   （`.ko` 是编译产物，未收录，需自行 `make`。中断测试只能用 `driver/int` 那份驱动。）

3. **用户态读写 BAR**
   ```
   cd ../anlogic_pcie_app && gcc pci_bar.c -o pci_bar
   ./pci_bar 0 0x0                 # 读 BAR0 偏移 0
   ./pci_bar 0 0x0 0x12345678      # 写
   ```

UART 命令脚本：`doc/uart_cmd_file_pcie.txt`（可经板载串口下发校验/测试命令）。

## 在 TD 里编译工程

- 打开 `prj/case_ep/ph1p_pcie_ep_top.al` → 一键编译（syn_1 + phy_1）→ Generate Bitstream。
- RC 工程 `prj/case_rc/ph1p_pcie_rc_top.al` 器件是 PH1P100SBG676，不是本板（F9P 是 SBG484）；
  它是 PCIe RC 侧参考设计，除非你有对接的 RC 板，否则用不到。
- 编译产物（`*_Runs/`、`.db`）未收录，首次打开需重新编译；`al_ip/` 内 IP 设计文件已保留，可再生成。

## 备注

- `driver.zip`、`driver/ph1p_pcie_driver.zip` 是原包自带的驱动打包文件，保留原样。
- 驱动目录里残留了部分内核模块构建中间物（`.mod`、`Module.symvers`、`modules.order` 等），
  重新 `make` 即可覆盖。
- 引脚约束在 `prj/*/constraints/*.adc`，时序在 `*.sdc`；引脚定义可查板卡的 `03_管脚定义表/PCIEx2-管脚定义表.xlsx`。
