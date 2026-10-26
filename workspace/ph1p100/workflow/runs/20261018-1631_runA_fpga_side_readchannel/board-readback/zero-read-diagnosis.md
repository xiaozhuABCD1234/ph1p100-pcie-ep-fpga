# zero-read-diagnosis.md — ChipWatcher 9 字全零的根因诊断（T11.runB-board-readback）

- 输入：`user-input-08.md`（用户 GUI 实读，2026-10-18 23:43:39 +08:00；Status=Idle、Triggered:1、9 字全 `0x00000000`、波形 115–140 全零、触发位置 127/1024、Bit File=`D:\anlogic\runa_p3\ascii_20261018_232333\compiled.bit` SHA `2385CDED…1873`）
- 性质：**只读离线诊断**（本轮未触硬件、未启动 TD、未下载、未联网）
- 一句话结论：**用户操作无误；全零是探针所在 `tl_clk_user` 域被 `tl_rst_user` 持续复位所致——没有 PCIe 链路时该复位不会释放，9 个快照寄存器保持复位值 0。GUI 重试无用，需要设计侧修复（重建位流），交原规划决定。**

## 1. 用户操作核对（结论：无误）

| 清单项 | 用户实际 | 结论 |
|---|---|---|
| 打开同源 `compiled.cwc` / Bit File 指向同 SHA 位流 | Bit File=`ascii_.../compiled.bit`（`2385CDED…1873`） | 正确 |
| Watch 实例 `auto_created_cwc1` | 实例正确 | 正确 |
| Add Signals 选 9 个 `dbg_bank_word0..8` | 9 行齐全（`dbg_mark$dbg_mark_word0..8[31:0]`） | 正确 |
| Instant Trigger 一次 | `Triggered: 1`、Status=Idle | 正确（触发已发生） |
| Value 列读十六进制 | Value 列全 `..00000000`；波形窗口 115–140 | 正确（读数有效，只是全零） |
| ≥2 样本 | 仅 1 次 | 未完成，但**由全零触发的停止规则优先**：首样本即全零，无需第二样本（见 §3 H1） |

> 结论：无需让用户“改操作”，问题不在操作层。

## 2. 证据链（RTL/流程，只读）

1. **探针本体**（`upstream/ph1p100-pcie-ep-fpga/rtl/ep_side/img/ep_bar_win.v` L464–499）：
   ```
   if (DBG_CTRL_DEFAULT_EN) begin : g_dbg_mark
     (* MARK_DEBUG="true" *) reg [31:0] dbg_mark_word0..8;
     always @(posedge clk or posedge rst) begin
       if (rst)   dbg_mark_wordN <= 32'd0;              // ← 复位值全 0
       else       dbg_mark_wordN <= dbg_bank_wordN;     // 1 拍快照
     end
   end
   ```
   其中 word0=MAGIC、word1=MAGIC_RKA1、word2=VERSION_RKA1 是**常量**（L439–441）——常量字的快照仍为 0，说明寄存器**从未离开复位态**，而不是“信号恰好为 0”。
2. **域归属**：`rtl/ep_side/pcie_ep_engine.v` L397–399 例化 `u_ep_bar_win(.clk(tl_clk_user), .rst(tl_rst_user))` → 9 个寄存器在 `tl_clk_user` 域、异步复位。
3. **`tl_rst_user` 的产生**（`rtl/common/ph1p_pcie_rst_sync.v`，例化于 `ph1p_pcie_ep_top.v` L506–509，`LTSSM_VAULE=5'h10`=L0）：
   - 只有当 `pl_link_up_dly==1 && tl_ltssm_dly==5'h10` 持续到 `rst_dly[10]=1` 才释放；
   - `rst_sync = rst_d2`，在条件不满足时**恒为 1（持续复位）**。
4. **本测试场景无 PCIe 主机**（本轮口径：严格 FPGA 侧、不验证 PCIe）：LTSSM 无法进入 L0 → `pl_link_up`/LTSSM 条件永不满足 → **`tl_rst_user` 常有效**。
5. **采样时钟仍在跑**：`tl_clk_user` 由 `pcie_pll_ep`（`.refclk(sys_clk)`，板载时钟）产生（`ph1p_pcie_ep_top.v` L472–477），不依赖主机 refclk → ChipWatcher 的调试时钟/触发逻辑可工作（所以 `Triggered: 1`），但它采到的是被复位钉死的 0。
6. **CWC 侧**：`compiled.cwc`/`compiled.bit` 配对与 SHA 正确；`config_chipwatcher`、`compile chipwatcher successfully!`（CLI 轮）与 GUI `Triggered:1` 都表明调试链本身可用——问题不在编译/映射。

## 3. 假设排序（按证据强度）

| # | 假设 | 证据 | 结论 |
|---|---|---|---|
| **H1** | **探针域被 `tl_rst_user` 持续复位（无 PCIe 链路）→ 9 字恒 0** | 常量字也为 0；`rst` 条件=L0 且未接主机；采样时钟独立于复位 | **最可能（采用）** |
| H2 | CWC 采样时钟与探针域不一致（XML 标注 `u_uart/u_uart_cdc/core_clk` 16 ns vs 注释 `tl_clk_user`） | 两者频率同为 ~62.5 MHz/16 ns；无法离线区分是否同一网络；即便不一致也只会产生“不可靠”而非“恒定全零” | 次要；建议在修复时**显式绑定**探针时钟 |
| H3 | 触发窗口/位置导致只看复位前窗口 | 触发位置 127、窗口 115–140；若寄存器曾更新过，MAGIC 常量快照应为非零 | 可排除（重触发/改位置也不会出数） |
| H4 | 用户操作错误 | 9 信号、触发、取值列均正确 | 排除 |
| H5 | 位流/CWC 不配对、SHA 不符 | Bit File SHA 与冻结候选一致；CLI 轮同 SHA 下载成功 | 排除 |

## 4. 下一步（裁定建议，交原规划）

**结论：这是设计/探针域问题，不再让用户做 GUI 重试。** 候选修复（任一，均需**重建位流** → 属新任务/新候选，不在本包内自行执行）：

- **R1（推荐，最小改动）**：把“身份/版本/CTRL 状态”等**与链路无关**的字从 `tl_clk_user` 域复制到**自由运行域**（如 `sys_clk`/UART `core_clk` 域）的快照寄存器上，并对该域做 `mark_debug`；DDR/CSI 计数类字保留原域（无链路时本就不会更新）。
- **R2**：若必须整组同域，则给 debug 快照专门使用**自由运行时钟**（不经过 `tl_rst_user` 复位——用专门的 power-on reset），使身份字在任何链路状态下可读。
- **R3（口径备选）**：把“读身份字”从本轮 G3 验收中拆出，改为“需 PCIe 链路/主机在场”才验收（属口径变更，需用户/规划批准，不得自行改判据）。
- 修复后**必须重建 + 重跑 G2 + 重出 CWC/bit 候选**，并由原规划按有界规则派发；本开发**不自行构建、不下载、不重烧**。
- 若规划选择先做**零成本判别**（仅确认 H2）：可在新位流里显式把 debug hub 绑定到探针同域时钟，但仍属重建范畴。

## 5. 安全与残留

- 本轮零硬件动作、零下载、零 Flash/efuse/SPI/svf、未改线/电源/相机、未联网、未启动 TD；板保持上电（SRAM 内为 23:34 下载的同 SHA debug 位流）。
- 用户可保持现状、无需再做任何点击；若要恢复原状：断电 10 s 上电（或重下旧 bit `e81d353b…`）。
