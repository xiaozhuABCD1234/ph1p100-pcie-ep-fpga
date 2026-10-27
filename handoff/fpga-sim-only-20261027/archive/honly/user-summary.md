# 用户短总结 — 20261027-055621_fpga-honly-td-and-ah

## 结论先说

两条线都做完了，但**都还差最后一步才闭环**：

| 线 | 结果 |
|---|---|
| **A+H（A 方案）** | **不采用**。A 把 zlib 输出改得不逐字节等价（N 每帧少 ~12 KB，头里 CRC 字节变成 X），而且 N4 只省 92,265 周期，没到 100k 的止损线。已独立复核确认（kill_verified），不再修。 |
| **H-only（不加 A）** | 功能上仍通过 4 帧原型门槛（N 6,196,749.5 / L 5,834,940，头逐字节相同）；修掉一个会让 TD 拒绝综合的多驱动问题后，**187.5 MHz 综合通过**：setup 余量 **+0.029 ns**、0 个违例端点、资源很低（ERAM 27/300、IO 121/286、slice 3,337/71,680）。**但布线没跑成**——TD 6.2.3 在导入它自己生成的库时反复崩溃（ChipWatcher 阶段，两次、有 dump），所以**没有布线后的时序结论**。 |

## 现在不能说的话

- 不能说 "H-only 已过 TD/STA" 或 "时序收敛"——布线结果不存在。
- 不能说 188.5 MHz 可用——那只是综合给的 gate 上界，布线后可能明显更低。
- 不能说 G0 整机通过——只是 4 帧原型门槛，且 N 侧余量只有 0.859%。
- 没有 bit、没有 CWC、没有上板、没有 RK/PCIe。

## 需要你定的下一步（二选一或都做）

**1）先把布线跑出来（推荐）**：开一个新 run，专门绕开 TD 的 ChipWatcher 崩溃（换导入方式/去掉 debug 负载/换或重装 TD/最小工程复现），拿到 routed STA。配额建议：TD 启动 ≤3、synth ≤1、route ≤2、**不 bitgen**。这是目前唯一缺失的关键事实。

**2）把 H-only 的改动迁移评审到新仓**：在 `D:/fpga/repos/ph1p100-pcie-ep-fpga` 的 `main` 上做**只读** diff 映射评审，出清单和风险；不写、不 commit、不 push（要真正落库需你单独授权）。

> 不建议在布线结果缺失时重开 A 或直接做 bitgen/上板。

## 启动文本

```
/fpga-orchestrator 执行：承接 20261027-055621_fpga-honly-td-and-ah 的 H-only 候选（core d2960cfe… / frame_top 4afc26e2…，synthfix manifest 034777c5…）。目标：绕过 TD 6.2.3 在 import_db→Import ChipWatcher 的 coredump，取得 routed DB + routed STA（187.5 MHz），必要时做 209.6 MHz analysis-only。门槛：routed WNS≥0、hold≥0、flow.status NUM_FEPS=0、ERAM+CWC≤300、slice≤71680、IO≤286，附 check_timing/CDC 与 ≥10 条路径归因。配额：TD 启动≤3、synth≤1、route≤2、bitgen≤0、analysis≤1、0 板卡/网络；先在最小工程复现崩溃再绕行；不得改 RTL/SDC/时钟/例外。证据与边界：D:\fpga\ph1p100\workflow\runs\20261027-055621_fpga-honly-td-and-ah\dual-verdict.md 与 handoff.md
```

只读复盘/追责：
```
恢复：D:\fpga\ph1p100\workflow\runs\20261027-055621_fpga-honly-td-and-ah；本轮目标：<目标>
```

## 文件入口

- 合并判定：`dual-verdict.md`
- 技术收尾：`final-summary.md`；接手信息：`handoff.md`
- 三轮裁决：`r0-ruling.md`（A 关账 + 首次租约）、`r1-ruling.md`（不可综合 → synthfix）、`r2-ruling.md`（TD r1 放行 + 租约 v2）
- 测试报告：`test-reports/T10.ah-a-plus-h-r2-r0-integrated.md`、`T10.ah-honly-synthfix-r0-integrated.md`、`T10.ah-honly-td-r1-integrated.md`
