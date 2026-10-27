# ChipWatcher 详细操作指南（TD 的在线逻辑分析仪）

> 来源：米联客《安路 FPGA 课程基础篇》第 04 章（p78–p88）+ 官方例程 `D:\TD\work\course\04_use_ChipWatcher\`
> ChipWatcher ≈ **Vivado 的 ILA**（在线逻辑分析仪）。**D5 起调 MIPI 全靠它。**

---

## 0. 例程在干什么（先看懂再动手）

`D:\TD\work\course\04_use_ChipWatcher\` 是一个**最小可触发**的例子：

```
I_sysclk(50MHz) → ui_pll(PLL) → clk0(200MHz) → 26 位计数器 cnt → 2 位 LED
                                    │
                            ui_cwc (ChipWatcher IP)
                              探针：probe0 = pll_lock  (1 bit)
                                    probe1 = O_up_led  (2 bit)
                                    probe2 = cnt       (26 bit)
                              采样时钟 = clk0 (200MHz)
```

| 项目 | 值 |
|---|---|
| 器件 | `PH1P100SBG484` / Speed -3 |
| 顶层 | `pll_test` |
| ChipWatcher IP 名 | `ui_cwc` |
| 探针数 | **3** |
| 采样深度 | **1024** |
| 采样时钟 | `clk0`（**200MHz**！PLL 从 50MHz 倍频） |

源码（`uisrc\01_rtl\pll_test.v`）关键片段：
```verilog
ui_cwc ui_cwc(
    .probe0 (pll_lock),   // 1 bit
    .probe1 (O_up_led),   // 2 bit
    .probe2 (cnt),        // 26 bit
    .clk    (clk0)        // 采样时钟
);
```

---

## 1. 完整流程（7 步）

### 第 1 步：确保工程**已经编译过至少一次**
（ChipWatcher 要在已编译工程上加）

### 第 2 步：加 ChipWatcher IP
1. 菜单 **`Tools` → `IP Catalog`**
2. 选 **`Debug`** 分类下的 **`ChipWatcher`**
3. **双击** → 弹 **`Setup Exporting Options`** → 选 IP 路径 + IP Name → **`Ok`**

### 第 3 步：配置参数
**General Options 页：**

| 参数 | 范围 / 默认 | 说明 |
|---|---|---|
| **Number of Probes** | 1~256，默认 **1** | 探针个数 |
| **Sample Data Depth** | 128~65536，默认 **1024** | 采样深度，**越大越费 RAM** |
| **Input Pipe Stages** | 0~6，默认 **0** | 输入寄存级数；**时序不收敛时加大** |
| **Output Pipe Stages** | 0~6，默认 **0** | 输出寄存级数；同上 |

**Probe 页（每个探针一项）：**

| 参数 | 范围 / 默认 | 说明 |
|---|---|---|
| **Probe Width** | 1~1024，默认 1 | 探针位宽，**要和 RTL 信号位宽一致** |
| **Data Enable** | 默认 ✔ | 数据采集使能 |
| **Trigger Enable** | 默认 ✔ | 触发使能 —— ⚠️ **只有勾了的才出现在触发信号列表里** |

4. 全部设完 → **`Ok`** → IP 生成完成

### 第 4 步：在 RTL 里例化
生成的 IP 模块名 = 你填的 **IP Name**（例程里是 `ui_cwc`），端口是 `probe0..probeN` + `clk`：
```verilog
ui_cwc ui_cwc(
    .probe0 (你的信号1),
    .probe1 (你的信号2),
    .probe2 (你的信号3),
    .clk    (你的采样时钟)     // ← 选一个稳定的时钟
);
```

### 第 5 步：**重新编译**（必须）
**`Generate Bitstream`** —— 加了新 IP 必须重新跑 综合+PnR+bitgen

### 第 6 步：进入 Watch 界面 + 下载
1. 打开 **ChipWatcher 界面** → 点上方 **`Watch`** 按钮
2. 界面分两块：**上面 = 下载窗口**，**下面 = 波形观察窗口**
3. 接好 JTAG、板子上电
4. **下载 bit** —— ⚠️ **必须是含 ChipWatcher 的那个 bit**，否则触发报错
5. 看底部进度条到 **100%**

### 第 7 步：加信号 → 设触发 → 触发 → 看波形
1. **加观察信号**：在 `Name` 窗口**右键 → `Add Signals`**（或工具栏 `Add Signals`），从列表库里选
   - 默认打开时列表是**空的**，必须手动加
2. **加触发信号**：在触发条件设置区（右侧）**右键 → `Add Triggers`**
3. **设触发条件**（见 §3）
4. **点触发** → 看波形

---

## 2. 触发设置区参数

| 参数 | 说明 |
|---|---|
| **Number of windows** | 波形触发窗口个数，1~Sample Depth，默认 1（多个窗口 = 多次触发在同一界面分窗显示） |
| **Window of depth** | 窗口采样深度，默认 = 例化时的采样深度 |
| **Trigger Position in window** | 触发位置，0~Sample Depth-1（设为中间可看到"触发前"的波形） |
| **Trigger Condition** | `Basic AND`（所有条件都满足才触发）/ `Basic OR`（任一满足即触发） |

---

## 3. 触发条件怎么设

| 信号类型 | 可设条件 |
|---|---|
| **单 bit** | `don't care`（不关心，默认）/ `high` / `low` / `rising edge` / `falling edge` / `edge`（双沿） |
| **多 bit** | 设 **`Operators`**（运算符）+ **`Trigger Condition`**（比较值）；也支持 `edge` |

**Status 状态机**（界面顶部）：
```
Idle(空闲) → Wait for trigger(等触发) → Reading data(读数据) → Finished(完成)
```

---

## 4. ⚠️ 六个必须知道的坑

| # | 坑 | 后果 | 对策 |
|---|---|---|---|
| 1 | **忘了重新编译** | bit 里没有 ChipWatcher → 触发报错 | 加完 IP 一定重新 `Generate Bitstream` |
| 2 | **下载了不含 ChipWatcher 的 bit** | 无法触发 | 用 Watch 界面下载，确认 bit 是新生成的 |
| 3 | **探针信号没勾 `Trigger Enable`** | 该信号**不出现在触发列表** | 例化时勾上 |
| 4 | **探针位宽和 RTL 不一致** | 综合报错或数据错 | 位宽必须一致 |
| 5 | **探针太多 / 采样深度太大** | **吃 RAM、可能 PnR 失败** | 只探必要信号；深度先 1024 |
| 6 | **加了 ChipWatcher 后时序不收敛** | PnR 失败或 WNS 变差 | 加大 **Input/Output Pipe Stages**（0→1→2） |

**还有一个"物理"限制**（后面调 MIPI 会踩）：
> **ChipWatcher 探不到几百 MHz 的原始高速信号** —— 它受采样时钟限制。
> 调 MIPI 时要探**寄存后/降速后**的信号（比如 `O_l0_rx_data[7:0]` 而不是原始的 `I_data_hs_p`）。

---

## 5. 🎯 现在你就这么做（3 步）

### 第 1 步：跑通官方例程（20 分钟）
1. TD → **`File` → `Open Project`** → 选
   ```
   D:\TD\work\course\04_use_ChipWatcher\fpga_prj.al
   ```
2. 直接 **`Generate Bitstream`**（工程已编译过，会重新跑一遍）
3. 打开 **ChipWatcher → Watch** → 下载
4. **加 3 个信号**：`probe0`(pll_lock)、`probe1`(O_up_led)、`probe2`(cnt)
5. **设触发**：比如 `probe0 (pll_lock)` = `rising edge`
6. **点触发** → 看 Status 走 `Wait for trigger` → `Finished` → 看波形

### 第 2 步：练三种触发（10 分钟）
| 练习 | 怎么设 |
|---|---|
| **单 bit 边沿** | `probe0 (pll_lock)` = `rising edge` |
| **单 bit 电平** | `probe1 (O_up_led)` = `high` |
| **多 bit 比较** | `probe2 (cnt)` 的 `Operators` 选 `==`，值填某个十进制数 |

> 体会一下：**触发位置**设为采样深度的一半 → 能看到触发**之前**的波形

### 第 3 步：搞清楚一件事（5 分钟）
打开 `uisrc\01_rtl\pll_test.v`，看**探针是怎么接的**、**采样时钟是谁** —— 这就是以后给 MIPI 加探针的模板。

---

## 6. 为 D5–D9 调 MIPI 做的准备（提前想清楚）

调 MIPI 时你会用到这样的探针组合：

| 探针 | 信号 | 位宽 | 看什么 |
|---|---|---|---|
| probe0 | `O_l0_rx_data` | 8 | lane0 解出来的字节 |
| probe1 | `i_l0_idelay_value` | 6 | 当前 IDELAY 档位 |
| probe2 | `O_delay_data_val` | 1 | 延迟数据有效 |
| probe3 | `O_dbg_best_len` | 6 | eye 扫描最佳长度 |
| probe4 | `O_csi_frame_start` | 1 | 帧起始 |
| 采样时钟 | **`I_byte_clk`**（字节时钟，不是 MIPI 的 HS 时钟！） | | |

**关键**：**采样时钟要选"慢"的那个**（字节时钟/像素时钟），不是 MIPI 的高速时钟。

---

## 7. 本机相关文件

| 文件 | 路径 |
|---|---|
| 例程工程 | `D:\TD\work\course\04_use_ChipWatcher\fpga_prj.al` |
| 例程 RTL | `D:\TD\work\course\04_use_ChipWatcher\uisrc\01_rtl\pll_test.v` |
| ChipWatcher IP | `D:\TD\work\course\04_use_ChipWatcher\al_ip\ui_cwc\` |
| ⭐ **官方教程** | `D:\TD\03_F9P_CA05_PH1P50_PH1P100\V2026\HW-MLK-F9P-CA05-PH1P100\03_demo\3_0_ex_book_all\3_1_01_米联客-安路 FPGA 课程基础篇.pdf` 的 **P78–P88** |
| 官方调试手册 | `D:\downlaod\Doc\SWUG\SWUG111_Debug_Tools_User_Guide.pdf` |
| DDR3 现成 .cwc 参考 | `D:\TD\work\peripheral\09_ddr3_ddrmc_cal_x32_1066mbps\prj_td\ready_for_test\compiled.cwc` |
