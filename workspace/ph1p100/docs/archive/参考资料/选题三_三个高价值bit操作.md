# D1 步骤 3 · 三个高价值 bit 的操作与现象

> 对应文件：`D:\TD\work\bits\07_rgb2hdmi_out.bit`、`09_ddr3_ddrmc_cal_x32_1066mbps.bit`、`12_pcie_gen2x2.bit`
> 对应源码：`D:\TD\work\peripheral\` 下同名目录

---

## ① `07_rgb2hdmi_out.bit` —— HDMI 输出测试

### 它在做什么
FPGA 内部用 **测试图样发生器（TPG）** 造一幅 **1080P@60Hz** 的画面，通过 **HDMI 发射器**送到显示器。

```
uitpg.v(测试图样) → rgb2hdmi.v → HDMI TX(LVDS) → HDMI 线 → 显示器
                        ↑
                   uivtc.v(视频时序)  +  ui_pll(像素时钟)
```

### 接线
**HDMI 线**：F9P 的 HDMI 口 → 显示器 / 电视

### 现象（官方说明）
显示器出现画面，**分辨率 1080P，帧率 60Hz**（一般是彩条/测试图）

### 引脚（工程 `fpga_pin.adc` 原文）
| 信号 | FPGA 脚 | 电平 |
|---|---|---|
| `O_hdmi_tx_p[0..2]` | B15 / B21 / C22 | `LVDS33_E` |
| `O_hdmi_clk_p` | C18 | `LVDS33_E` |

### ⭐ 对我们项目
**这就是 D10「单路出图」要用的显示通道**。附带一份官方应用笔记（**必看**）：
```
D:\TD\work\peripheral\07_rgb2hdmi_out\uisrc\06_doc\APUG058_HDMI Transmitter Over Lvds.pdf
```
源码里 **`uitpg.v` / `uivtc.v` / `ui_pll`** 三个 IP 都可以直接搬到 `csi2` 工程里用。

---

## ② `09_ddr3_ddrmc_cal_x32_1066mbps.bit` —— DDR3 校准与读写测试

### 它在做什么
例化 TD 的 **DDR3 控制器（DDRMC，x32 @1066Mbps）**，做：
**PLL 锁定 → PHY 校准 → 用 PRBS 数据流写入 DDR → 读回比对**

```
data_gen.v(产生数据) → paxi → DDRMC(x32,1066Mbps) → DDR3 颗粒
                                    ↑
                        data_check.v(读回比对)  +  ph1p_ddrmc_mtest.v(主控)
```

### 现象（官方说明）
| LED | 含义 |
|---|---|
| LED1 | **亮灭** = DDR PLL 时钟在工作 |
| LED2 | **微亮** = 读写间隔有效（读写分时，所以是微亮） |
| LED3 | **灭** = 没有错误 ✅ |
| LED4 | **亮** = 校准完成 ✅ |

**更精确的判据（用 ChipWatcher 看）**：`cwc` 一直触发、**`mtest_his_err` 为低**、`paxi_rdata` 一直跳变 → DDR 读写正常；`mtest_his_err` 为高 = 出错。

> LED1~3 引脚：**E21 / D21 / E22**（`ap115v2.adc` 原文）

### ⭐ 对我们项目
**这是 D10 帧缓存的前置验证**。而且源码里带了现成的调试资产：
- **已经配好的 ChipWatcher 配置**：`prj_td\ready_for_test\compiled.cwc` ⭐
- **测试逻辑可直接复用**：`prj_src\rtl\mtest\{data_gen.v, data_check.v, prbs_gen.v, ph1p_ddrmc_mtest.v}`
- **完整 DDR3 约束**：`golden_adc\ap115v2_ddr3_x32.adc` + `prj_src\adc\ap115v2.adc`
- 还有 Modelsim / VCS 两个仿真工程

---

## ③ `12_pcie_gen2x2.bit` —— PCIe 测试（我们最关心）

### 它在做什么
FPGA 做 **PCIe Endpoint（EP）**，配置成 **Gen2 × 2**，使能 **多个 BAR**，
主机（RC）通过 **配置读写 / 内存读写 / IO 读写 / PRBS 校验** 全面测试链路。

### 官方测试步骤（《开机测试》p22-p23 原文）
1. 下载 `12_pcie_gen2x2.bit`（EP 位流）
2. **板卡上电加载位流后 → 重启主机**（进 Linux）
3. 进系统后：
   ```bash
   lspci                          # 找设备，预期 bus 号 01:00.0
   lspci -s 01:00.0 -vvv          # 看详细能力
   ```

### 现象（官方说明）
`lspci` 能看到 **`01:00.0`**；链接状态为 **Gen2 x2**；使能 4 个 BAR：
| BAR | 类型 | 大小 |
|---|---|---|
| BAR0 | memory | 1 MB |
| BAR1 | **IO** | 256 B |
| BAR2 | memory | 1 MB |
| BAR4 | memory | 1 MB |

### ⭐ 对我们项目：**这就是关口③，今天就能验**

**对应到你的 OrangePi 方案**：
1. 下载 `12_pcie_gen2x2.bit` 到 F9P
2. F9P 金手指 → **M.2 转 PCIe 槽转接卡** → OrangePi 5 Max 的 M.2 M-key
3. F9P **自己 12V 供电**，两板共地
4. **先给 OrangePi 上电**，再给 F9P 上电（或按官方：加载位流后重启主机）
5. OrangePi 上 `lspci -nn` → **看有没有出现 `01:00.x` 或未知设备**

✅ 出现 = **物理层 + 转接卡通**；❌ 没有 → 查 REFCLK / PERST# / 共地 / 供电

### ⭐⭐⭐ 附带的大宝藏（源码目录 `peripheral\12_pcie_gen2x2\`）

| 资产 | 路径 | 价值 |
|---|---|---|
| **52 条 UART 测试命令全集** | `doc\uart_cmd_file_pcie.txt` | ⭐⭐⭐ 含 BAR 配置、MEMWR/MEMRD、**PRBS 注错**、IOW/IOR、复位 EP/RC、legacy_int 检测 |
| **官方参考设计文档** | `doc\APUG081_米联客科技PH1P系列FPGA PCIE RC对接EP参考设计.docx` | ⭐⭐⭐ |
| **官方 Linux 驱动源码** | `driver\ph1p_pcie_driver\{anlogic_pcie_drv, anlogic_pcie_app}` | ⭐⭐⭐ D19 直接用/改 |
| **EP 完整工程** | `prj\case_ep\ph1p_pcie_ep_top.al` | ⭐⭐⭐ |
| **RC 工程** | `prj\case_rc\ph1p_pcie_rc_top.al` | ⭐⭐ |
| **TLP 引擎 RTL** | `rtl\ep_side\pcie_ep_engine.v` | ⭐⭐⭐ |
| **中断处理 RTL** | `rtl\ep_side\pcie_ep_int_handle.v` | ⭐⭐ |
| 寄存器表 / TLP 类型 / BDF | `rtl\common\{PCIE_REG_TABLE.v, TLP_FMT_TYPE.v, BDF.v}` | ⭐⭐ |
| 仿真环境 | `sim_do\modelsim\sim.do`、`sim_do\vcs\makefile`、`sim_do\tb\` | ⭐⭐ |

> **命令协议格式**（从 `uart_cmd_file_pcie.txt` 看出）：串口发 `41 42 43 44 45 46`（"ABCDEF"）+ `FF` + 命令字 + 数据。
> 例如 `memwr`：先开使能 → 设低地址 → 设高地址 → 设长度 → 设模式 → 写数据 → 启动 → 回读状态。

**⇒ 这一份把 codex 说的 P0「PCIe IP 不是 DMA，要自己写 TLP/BAR/MSI」的风险砍掉大半。**

---

## 三个 bit 一句话总结

| bit | 作用 | 对我们的用处 |
|---|---|---|
| `07_rgb2hdmi_out` | HDMI 1080p60 彩条 | ⭐⭐ D10 出图通道 + `APUG058` 应用笔记 |
| `09_ddr3_...` | DDR3 校准 + PRBS 读写 | ⭐⭐⭐ D10 帧缓存 + 现成 ChipWatcher 配置 |
| `12_pcie_gen2x2` | PCIe Gen2x2 EP | ⭐⭐⭐ **关口③，今天就验** + 52 条测试命令 + 官方驱动 + TLP 引擎 |
