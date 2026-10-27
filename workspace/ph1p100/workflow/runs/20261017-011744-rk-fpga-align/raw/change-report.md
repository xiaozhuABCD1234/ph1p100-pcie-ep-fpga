# T11.rk-align-raw 变更报告（round0）

范围：`fpga/csi2/pcie_integration/`（正式 RAW10→R10F 通路 + 仿真）、`tools/pcie_integration/`
（严格解析/样例生成/清单）与本 run `raw/`（候选、证据、RK 增量）。`backend/` 冻结包与
`fpga/csi2/src/csi` 原源**只读未动**；SDC/ADC 与 checked 三文件字节未变（见 §6 哈希）。

## 0. 一句话

把「8bit 灰度诊断帧 → DDR → 推帧」升级为**正式非压缩 RAW10 通路**：
checked CSI 4px → packed RAW10 → R10F v1（128B 头 + 三层 CRC + 640B 尾零）→ AXI 整帧写
DDR（`dma_bytes=2,592,768`）→ writing→complete→held_for_tx→released 所有权 → one-shot
发送 + 门铃；RK 侧交付**增量补丁**（修正 T07 草案解析布局 + 发布前严格解析 + 独立
`r10f_check` CLI）。几何按源参数写死但**未板证**，全部帧内容按 synthetic/diagnostic。

## 1. 交付物与改动（相对 T07 交付树）

| 文件 | 类别 | 要点 |
|---|---|---|
| `rtl/ep_side/ddr/cam_r10f_writer.v` | **新增**（T11 主体） | CSI 4px(40bit)→窗口裁剪→异步 FIFO→DDR 域拼 5B/组 packed RAW10（`P0[9:2]…P3[9:2]`+低 2bit `{P3,P2,P1,P0}`）→ 首遍头（CRC 字段 0）→ 载荷逐 4B 拍递推 CRC32 → 32 拍头 CRC 遍历 → 4B 部分写补 0x50/0x54/0x58 → 尾零补齐到 4KiB；good/abort/短行/超预算/axi_err 参与发布裁决；发布即锁块（prot_en），release toggle 解锁；`wr_status[0]`=已发布过帧；`wr_len=dma_bytes` |
| `rtl/ep_side/ddr/crc32_upd4.v` | 新增（生成物） | 1..4 字节/拍扁平 XOR 树 CRC-32（`tools/pcie_integration/gen_crc32_flat.py` 生成 + 4×20020 例自检） |
| `rtl/ep_side/ph1p_pcie_ep_top.v` | 修改 | A/B 两片 `cam_r10f_writer` 换接（原 8bit 写者不再例化、文件保留作参照）；`w_push_ddr_len`（=2,592,768）作为 pusher `frame_bytes`；A/B 发布/rel 四根 toggle/诊断分路（0xA0..0xAC / 0xE0..0xEC / 0x120..0x12C）；`DDR_CAP_BYTES=256MB` 沿用 |
| `sim/compile_checked.f` | 修改 | 加入 `cam_r10f_writer.v`（`crc32_upd4.v` 由其 `include`） |
| `sim/tb/tb_cam_r10f_writer.v` | 新增 | 写者 P0..P10：复位默认、4096B 冻结向量逐字节+三 CRC、换块、坏帧（abort/无 good/短行/无 FE 超时）、所有权（锁块/跳过/release）、复位隔离、FIFO 溢出、**1080p 81,024 拍/633+1 突发/尾零/头字段+CRC/抽拍** |
| `sim/tb/tb_t11_r10f_e2e.v` | 新增（本轮修通） | 真实 CSI 注入→checked wrapper→写者→假 DDR→pusher→独立 TL 监视器+host 模型；E0 未 ARM 0 TLP+E_NOT_ARM+release、E1/E2 两帧 one-shot+错/正 ACK+块释放、E3 长 wait 持稳+held 保护+held 期间新帧拒(8)+ACK、E4 held 未 ACK 复位隔离+新 session 全流程 |
| `sim/tb/tb_t11_csi_enable_corner.v` | 新增 | T07 遗留用例（functional r2 §6.1）：`I_enable` 包尾后 1 拍撤销 → abort/坏帧照常、crc_errors 少计 1（**回归钉**）、对照与恢复相位证明正常路径不受影响 |
| `tools/pcie_integration/r10f_strict.py` | 新增 | 离线严格校验/样例生成/selftest：与合同验收向量**逐字节一致**（SHA 相同）+ 全部 `frame_mutations` 负例 + session/几何不匹配拒绝 |
| `tools/pcie_integration/r10f_tools_consistency.py` | 新增 | Rust（rka1.rs）↔ Python 解析器字段偏移静态交叉核对（25/25 一致） |
| `tools/pcie_integration/gen_crc32_flat.py`、`gen_manifest_t11.py` | 新增 | CRC 树生成器（含自检）；T11 清单/来源生成（**不动 T07 的 gen_manifest.py**，保持其 SHA 可复算） |
| `raw/rk-driver-src/`（全树）+ `raw/patches/t11-rka1-r10f-fix.patch` | 新增（RK 增量） | §3：修正 `r10f` 布局、`frame_grab` 发布前严格解析、新增 `r10f_check`；对 T07 干净树 `git apply --check` 通过 |

未改动：`rtl/checked/*`（三文件哈希与 T07 manifest 完全一致）、`constraints/*`（哈希一致）、
`al_ip/*`、`rtl/ep_side/ddr/ddr_frame_pusher.v`、`cam_ddr_writer.v`（保留作参照）、
`backend/**`、`fpga/csi2/src/csi/**`。

> 说明：`sim/tb/tb_t11_dbg1.v` 是原实例定位写者流控时的**临时调试台**（无 ALL PASS 判定），
> 保留在树中作过程留痕；它列在 manifest 的 test_inputs 里只为"冻结=可复核"，不属于 G1 证据集。

## 2. R10F v1 与非压缩语义（与冻结合同逐字段一致）

* 头 128B（小端）：magic "R10F" / version 1.0 / header_bytes=128 / camera_id / format=0 /
  codec=0 / session(0x10) / capture_seq(0x14) / mode_id(0x18) / width(0x1C) / height(0x1E) /
  stride(0x20) / roi_x/roi_y(0x24/0x26) / bayer_phase/dir(0x28/0x29) / valid_bits=10(0x2A) /
  packing=0(0x2B) / raw_bytes(0x2C) / payload_bytes(0x30) / block_count=1(0x34) /
  exposure/gain(0x38/0x3C)=0 / sof_timestamp(0x40)=0 / timestamp_hz(0x48)=0 /
  **flags(0x4C)** / raw_crc32(0x50) / payload_crc32(0x54) / header_crc32(0x58) / reserved 0x5C..0x7F=0。
* **flags=2（CROPPED）**：`FLAGS_VAL = (X0!=0 || Y0!=0) ? 2 : 0`（与合同 1080p 样例
  `flags=2`、小几何样例 `flags=0` 一致；本包修正了原先恒 0 的行为，见 lessons L4）。
* 三层长度：raw=payload=stride×H=2,592,000B；content=128+payload=2,592,128B；
  dma_bytes=ceil(content/4096)·4096=**2,592,768B**；尾 640B 全 0（不计入任何 CRC）。
* CRC32 IEEE reflected poly 0xEDB88320、init/final 全 1；raw 与 payload 同值（非压缩），
  覆盖 packed 有效载荷；header_crc32 清 0x58..0x5B 后覆盖 128B。
* 发送：`frame_bytes=dma_bytes`；1080p ⇒ 20,256 笔 128B MWr + 1 笔单 DW 门铃、
  633 个 4KiB DDR 读突发；数据在前、门铃在后、无 RO（沿用 T07 冻结语义）。

## 3. 所有权 / one-shot / RK 增量（与 T07 契约的关系）

* 写者：`writing→complete→held_for_tx→released`；发布即保护（prot_en 下），release
  toggle（每块一根）解锁；坏帧照写不发布序号（pusher 只看序号）；reset 隔离旧会话。
* pusher：**未改**（T07 r3 候选同一份字节）；语义回顾：ARM 校验含「已发布过的完整帧」，
  claim 只认 ARM 后新发布帧；ACK 必须 (session,seq) 匹配；CANCEL 不截半包。
* RK 增量（§0 表 + `raw/rk-change-list.md`）：`rka1.rs::r10f` 草案布局 → 正式布局
  （magic "R0FR"→"R10F"、version/format/codec/valid_bits/packing/几何/长度/CRC/reserved/flags
  全部按合同），`frame_grab` 发布前严格解析（失败退出码 5），新增 `r10f_check` CLI；
  离线 `git apply --check` 通过，**未编译/未安装**（RK 条件见清单 §2）。

## 4. G1（ModelSim 真实 RTL，证据在 raw/g1/msim/）

| 判据 | 证据目录 | 结果 |
|---|---|---|
| 小几何端到端（生成→打包→成帧→DDR→pusher→host 模型）逐字节+CRC | `p2_e2e_v6` | **ALL PASS**（E0..E4，0 错） |
| 完整 1080p 长度边界（写者侧 81,024 拍/633+1 突发/尾 640B 零/头+CRC） | `p1_writer_v4`（P10；v3=同一输入标签修正前运行） | **ALL PASS** |
| 完整 1080p 长度边界（推帧侧 20,256 MWr + 633 突发 + 门铃） | `r_t07_pusher`（PHASE10，BIG_BYTES=2,592,768） | **ALL PASS**（T07 回归复跑） |
| 坏帧拒绝（EOF abort/短行/无 good/无 FE 超时） | `p1_writer_v4`（P3..P6） | **ALL PASS** |
| RAW 尾/边界（尾零、抽拍、4KiB 突发规则） | `p1_writer_v4`（P1/P2/P10） | **ALL PASS** |
| capacity 高位/溢出/负例矩阵/长 stall/超时（沿用 T07 安全门） | `r_t07_pusher` | **ALL PASS**（20387 TLPs） |
| 慢消费 held（E3 长 wait 逐拍持稳 + held 保护 + 新帧拒） | `p2_e2e_v6`（E3）+ `r_t07_pusher` | **ALL PASS** |
| reset 旧会话隔离 | `p2_e2e_v6`（E4）+ `p1_writer_v4`（P8） | **ALL PASS** |
| T07 遗留：`I_enable` 包尾 1 拍撤销（诊断计数级） | `p3_enable` | **ALL PASS**（钉：crc 少计 1、abort 照发） |
| checked 差分 oracle / wrapper / 寄存器面 / 仲裁 回归 | `r_t07_diff`/`r_t07_checked`/`r_t07_bar`/`r_t07_arb` | **ALL PASS** |
| **可重放负对照**（M1：packed 低 2bit 顺序换反，隔离树） | `neg_m1_pack_order` | e2e **FAIL**（host/CRC 不符）+ 写者 TB **FAIL**（P1/P2/P10 冻结向量不符） |
| 顶层例化/精化（含生产 RTL，IP 用桩） | 所有 TB 的 vlog | 编译 0 错（真实 IP 精化由 TD 覆盖，见 §5） |

独立 oracle：TL 监视器（F0/FF/F8、4DW 地址、Length/BE、地址递增、门铃在数据后、wait 持稳）、
host 内容模型（头按 seq/session 参数化 + 两层独立 CRC 复算）、像素/打包模型均在 TB 内独立实现，
不调用 DUT helper。日志含命令/退出码：`raw/g1/msim/*/commands.log`。

## 5. G2（TD 同一最终 DB）—— **达标**

命令 `run_td.ps1 -Stage 00_all -OutDir raw/candidate/prj`（单会话 syn+phy+bit；
`td exit 0` + `PRJ-1406`/`PRJ-1424` + 完成标记 `T07_ALL_DONE`（共享入口脚本的文本，沿用）；
phy 墙钟 418 s；TD 重建 **1 次**（允许 ≤2））。

| 项 | 值 | 判据 |
|---|---|---|
| 最终 STA | `phy_1/final_timing.rpt`：Generated Sat Oct 17 09:41:30 2026 / **Routed** / Both corners / CRPR on / STA cov 95.46% | — |
| **Setup** | **SWNS = +0.115 ns，STNS = 0.000 ns（0 violated endpoints / 18,724）** | ✓ |
| Hold | HWNS +0.020 ns / HTNS 0.000 | ✓ |
| 相机字节域 | clk2 `cam_a_byte_clk` **+0.115**（R-Period 5.217 ns）；clk3 `cam_b_byte_clk` **+0.150**（5.182 ns） | 回归门槛 ✓ |
| 最差路径 | `u_csi_a/u_gear_box/O_word_out_reg[3].clk → u_cam_r10f_writer/f_mem_syn_65.csa[2]`：4.503 ns（net 67%）、逻辑级 4、Budget 5.332 | 余量 +0.115 ns |
| 资源 | LUT6 21.76%（15,599/71,680）、ERAM **136/300**（FIFO20K=0）、均 ≤ 器件 | ✓ |
| 位流 | `phy_1/ph1p_pcie_integration.bit` 5,224,023 B，SHA `14b32037…5686b`（= `best_result/`；与同次 `pr.db`/`place.db`/报告同源） | ✓ |

报告与逐项约束解释：`raw/g2/README.md`（`TMST-7700` SEVERE 5 与 T07 同类：2 无根时钟网 +
3 local clock，非 setup 违例）。报告与 bit 同源 SHA 记录在 `raw/candidate-manifest.json`
的 `build_artifacts`（清单 SHA `aab0cc08…6975`，243 条自检 0 不一致）。**未放宽 SDC、未加
multicycle/max_delay、未改 187.5 MHz 或相机速率前提**（SDC/ADC 与 T07 同一 SHA，见 §6）。

## 6. 冻结边界与哈希（RTL 冻结时点）

* `constraints/ph1p_pcie_case_ep.sdc` = `3f999c44…c13a`（与 T07 manifest 同值，**未放宽**）；
  `.adc` = `67831295…5c98`（同值）。
* `rtl/checked/csi_rx_packet_integrity.v` = `50b4c77b…e6c60`；`csi_rx_10bit_unpack_checked.v`
  = `9b5421c5…5a12`；`crc16_upd4.v` = `20520d04…841f`（三者与 T07 manifest 同值）。
* 本包新增/修改文件与最终 bit 的 SHA 由 `raw/candidate-manifest.json`（自检 0 不一致）承担。

## 7. 未测边界与已知限制（不当作已验证）

* **真实相机几何/相位未板证**：W/H/X0/Y0/SKIP_ROWS/BAYER_PHASE 均为「按源标定写入的参数」
  占位（顶层默认 1920×1080 / x=960 / 有效图 y=540 / SKIP 37 / phase 0）；一切帧内容按
  synthetic/diagnostic 对待；板测用 0x120..0x12C 复核后回填参数再重跑 G1/G2。
* 仿真只到包层输入（serdes PHY 由 `MIPI_PHY_SIM_STUB` 旁路）；PHY/对齐原语由 TD 与板测覆盖。
* RK 侧：未编译/未安装/未运行（本机无 cargo/KERNEL 树）；增量补丁只做离线 apply 校验与
  静态交叉核对；「ARM→held→解析→ACK→再 ARM」整环仍是 RK 操作者要接的步骤（清单 §4）。
* `I_enable` 包尾撤销角落仍会少计 1 个 crc_errors（T07 已知、仅诊断计数；T11 只补用例不改 RTL
  —— 改它要动 frozen checked 源并破坏差分 oracle 的参照，收益/风险不划算）。
* 本包不操作硬件、不下载、不写 Flash、不发外部消息；G3/G4 留 `T07.rk-align-board`，
  组合版交付留 `T11.rk-align-release`。

## 8. 回退与边界

* 全部改动在新目录/既有 T11 树内：换回 T07 候选树 + `backend/candidate/prj` 的 bit
  `0943cb36…8b0a` 即回到 T07 r3 状态；旧主线与 002820 bit 未受影响。
* RK 侧：不应用 T11 增量时，T07 草案解析会拒掉所有正式帧（fail closed）；回退 =
  `git apply -R` 两条补丁，或直接用 `backend/rk-driver-src`。
* T07 manifest 的 `production_inputs` 引用同一棵树，T11 修改后其 SHA 已变 ——
  T07 manifest 只作历史冻结记录；**当前唯一有效清单是 `raw/candidate-manifest.json`**。

## 9. 交接补记（本实例接手「执行一半」的 T11）

原开发会话在上游请求超限前已完成：写者/CRC 生成器/两个 TB（写者 TB 已 ALL PASS；e2e 首版
FAIL 15 错）、顶层换接、compile 清单。本实例接手后（同任务、同 write_scope、未改 backend）：
①定位并修复 e2e TB 的读从机地址错位（L1）与相位语义（L2/L3）；②补 T07 遗留 enable 角落 TB；
③按合同修正 flags（L4）；④写严格解析工具 + 样例（与合同向量逐字节一致）；
⑤RK 增量补丁 + apply-check + 静态交叉核对；⑥跑全量 G1（含 T07 回归与负对照）；⑦G2 重建；
⑧清单/来源/文档/证据。原会话的失败证据（`p2_e2e`、`p2_dbg*`、`p1_writer`）保留未删。
