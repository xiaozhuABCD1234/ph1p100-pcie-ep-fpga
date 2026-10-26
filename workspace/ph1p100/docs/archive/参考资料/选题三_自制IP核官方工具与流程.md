# 安路官方「自制 IP 核」工具与流程

> 结论：**安路 TD 有完整的 IP 打包工具链**，和 Vivado 的 `Create and Package New IP` 一一对应。
> 本机**工具和手册都有**，不用去官网找。

---

## 1. 工具对照表

| Vivado | 安路 TD | 本机路径 |
|---|---|---|
| **Create and Package New IP**（IP 打包） | **Module Packager（`mpack`）** | 工具：`D:\downlaod\bin\mpack.exe`（17.4 MB）<br>手册：`D:\downlaod\Doc\SWUG\SWUG507_Module_Packager_User_Guide.pdf`（12 页） |
| **IP Integrator / Block Design** | **Design Integrator（DI）** | 工具：`D:\downlaod\bin\design_integrator.exe`（13 MB）<br>手册：`D:\downlaod\Doc\SWUG\SWUG501_Design_Integrator_User_Guide.pdf`（30 页） |
| **IP Catalog** | IP Catalog（同一个名字） | `D:\downlaod\ip\depot\Catalog.xml` |
| **IP Repository**（IP 仓库） | **Add IP Depot** | 见 §4 |

> **`mpack` 是安路开放给用户的工具**，是内部 `IP Packager` 的**简化版**。
> - `Module Packager` 打的 IP → 显示在 IP Catalog 的 **`User IP`** 分类
> - 内部 `IP Packager` 的 → 显示在 **`Primitive IP` / `Soft IP`** 分类

---

## 2. 三种"用 RTL 的方式"（SWUG507 图1）

| # | 方式 | 说明 |
|---|---|---|
| ① | **直接在 TD 加 RTL 源文件** | 最简单，不需要打包 |
| ② | **在 IP Catalog 例化单个 IP** | 可在 IP 页面改配置，**IP 间连接要手动写** |
| ③ | **用 Design Integrator 例化多个 IP** | 可在 IP 页面改配置，**能自动生成 IP 间连接的 RTL** |

---

## 3. Module Packager 打包流程（SWUG507 §2）

### 3.1 新建 mpack 工程
TD 菜单 → **`Tools` → `Module Packager`**
→ 在 mpack 里 **`File` → `Create Project`**
→ ① 选 **mpack 工作空间目录**（= 将来的 **IP 仓库目录**）
→ ② 填 **IP 名称**（会新建同名子目录）
→ **`Finish`**
→ 看到 IP 名称 + 版本号（Version Identifier 页面）

### 3.2 导入 RTL
- 点 `FileSets` 下的 **`<IP名>_files`** 子页面
- 右侧空白处**右键 → `Add File`** → 选 RTL 文件
- 在 **`top module name`** 输入框填 IP 的 module 名
- 正确的话，`ports` 子页面能看到该 module 的**所有端口**

### 3.3 检查参数和端口
- 对照 RTL 核对参数/端口是否一致，不一致按错误信息改
- ⚠️ RTL 里的**十六进制参数会自动转成十进制**显示；例化页面**只能填十进制**（仅整数参数；字符串/浮点不受影响）

### 3.4 绑定 bus（IP 里有总线时）
- `businterfaces` → **`Add`** → 填 **bus 名称 / 类型 / 方向（master/slave）**
- 在 bus 子页面的 `portMaps` 里，为每个 **logicPort**（总线协议定义的端口）选对应的 **physicalPort**（RTL 端口）
- ⚠️ **clock 和 reset 不用绑**（可以单独绑成 clock / reset 总线）
- ⚠️ **无法自动绑定，必须手动**
- bus 命名建议 `S_AXI_LITE` 这种格式

### 3.5 保存
**`File` → `Save Project`**

### 3.6 改已打包的 IP
选 `.pack` 文件重新打开 → 改 → 再 `Save Project`

---

## 4. 设置 IP 仓库路径（SWUG507 §3）

1. TD 菜单 → **`Tools` → `IP Catalog`**
2. 在 IP Catalog 页面选 **`User IP`** → **右键 → `Add IP Depot`**
3. 选 §3.1 里那个**工作空间目录**
4. 之后该仓库下**所有 IP 都会显示在 IP Catalog 里**，用法和系统 IP **完全一样**

**注意**：
- DI 里会**自动同步** IP Catalog 的仓库路径，不用再设
- **IP 仓库路径 = 包含很多 IP 的目录**（不是单个 IP 的目录）→ **可以直接打包发给别人用**

---

## 5. ⚠️ 四个硬限制（**对我们的 MIPI IP 很关键**）

| # | 限制 | 对 `mipi_csi_2`（17 个文件）的影响 |
|---|---|---|
| 1 | **仅支持 Verilog** | ✅ 我们的就是 .v |
| 2 | **仅支持单个 RTL 文件**（多文件要**手动合并成一个文件**） | ❌ **17 个文件必须合并**（可写脚本 `cat` 拼接） |
| 3 | **不支持添加约束文件** | ⚠️ 引脚(`.adc`)/时序(`.sdc`)要**单独放工程 constraints**，不能进 IP |
| 4 | 参数只支持 `parameter` 形式 | ✅ 我们的 `parameter DEVICE`、`S2P_RATIO` 都合规 |

---

## 6. 对赛题第 1 项的建议（「完成 MIPI CSI 图像传感器 FPGA 驱动 IP 核」）

### 结论：**要打包，但不要现在打包**

| 阶段 | 做法 | 理由 |
|---|---|---|
| **D5–D9（先跑通）** | **直接用 ① 方式（普通 RTL 源文件）** | 还在调 IDELAY / 字节对齐，**不要引入打包这个额外变量** |
| **D13 之后（单路出图了）** | 再打包成 IP | 此时 RTL 已稳定 |
| 打包时 | 写个脚本把 `src\mipi\*.v` **合并成一个 `.v`** → mpack 打包 → 起名 `mlk_mipi_csi_rx` | 绕开"仅单文件"限制 |
| 例化 | 从 IP Catalog 的 **`User IP`** 分类例化；**两路相机 = 例化两次**（改参数即可） | 这也是打包的**实际收益** |

### 打包的**收益**（答辩加分点）
1. IP Catalog 里能搜到 → 显得正式
2. **两路相机例化两次**，参数化配置（lane 数等）
3. 可以**导出成 IP 仓库分享**（说明书原文："可以直接分享给其他用户使用"）
4. 答辩时能证明「**自研 IP 核**」而不是"抄了个 RTL"

### ⚠️ 但也要知道
- 赛题的「IP 核」**不一定非要用 mpack 打包** —— 一个可复用、参数化的 RTL 模块也叫 IP 核
- **打包不增加功能**，只增加"形式感"和"复用便利"
- 所以：**功能优先，打包其次**

---

## 7. 还有一条重要提醒：**`mpack` 不等于"能写出软 D-PHY"**

`mpack` 只是**打包工具**，它**不会帮你产生软 D-PHY 的逻辑**。
- 软 D-PHY 的 **RTL 还是要从 AFC03(PH1A90) 的明文工程移植**（`mipi_csi_2\` 17 个文件）
- `mpack` 只负责**把移植好的 RTL 包成 IP**

---

## 8. 本机相关文件一览

| 文件 | 路径 | 用途 |
|---|---|---|
| Module Packager 工具 | `D:\downlaod\bin\mpack.exe` | IP 打包 |
| **SWUG507 手册** | `D:\downlaod\Doc\SWUG\SWUG507_Module_Packager_User_Guide.pdf` | ⭐ IP 打包教程（12 页） |
| Design Integrator 工具 | `D:\downlaod\bin\design_integrator.exe` | 多 IP 图形化连线 |
| **SWUG501 手册** | `D:\downlaod\Doc\SWUG\SWUG501_Design_Integrator_User_Guide.pdf` | DI 教程（30 页） |
| IP 工具 | `D:\downlaod\bin\IpTool.exe` | 官方 IP 配置向导 |
| IP 仓库（官方） | `D:\downlaod\ip\depot\` | 官方 IP + `Catalog.xml` |
| 原语手册 | `D:\downlaod\Doc\UG1310_PH1P_Libraries_Guide_for_HDL_Designs.pdf` | 写 RTL 必查 |
| TD 全局手册 | `D:\downlaod\Doc\TD_User_Guide_V6.2.pdf` | 例化 IP 见手册 |

---

## 9. 你给的那个 uisrc 链接

`https://www.uisrc.com/forum.php?mod=forumdisplay&fid=352...` = **米联客论坛「资料下载」版块**，
页面标题「资料下载 FPGA+AI数字世界」。**抓到的页面没有帖子清单**（需要登录 / 内容是 JS 加载）。

**建议**：直接在米联客论坛搜 **`Module Packager`** 或 **「IP 核」**，或去 `https://www.uisrc.com/f-download.html`
（软件下载页）。不过**安路官方的 SWUG507 已经够用**，本地就有。
