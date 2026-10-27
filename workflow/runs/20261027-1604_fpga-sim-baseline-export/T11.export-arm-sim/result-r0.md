# T11.export-arm-sim — result r0（**blocked**，冻结交接）

- task_id: `T11.export-arm-sim` / run `20261027-1604_fpga-sim-baseline-export` / round 0
- 状态：**blocked（LIMIT_REACHED）**。已冻结唯一 manifest（`manifest-r0.json`，46 文件）；**不是** ready_for_test。
- 结论口径：仅"仿真内板级数据通路"证据；**不**代表真实 PCIe、最终时序、双路实时或上板。G2/G3/G4 = `not_run`（本机禁 TD/STA/bitgen/下载/Flash；板卡在队友）。
- 未越界：未改 P4 源、未 force/层次化赋值 DUT 内部信号（仅只读层次观测）、未 stub 被测模块、未改 pusher ARM 判据。

## 1. 冻结环境（已完成，可复跑）

| 项 | 值 |
|---|---|
| 工作根 | `R:\workflow\runs\20261027-1604_fpga-sim-baseline-export\T11.export-arm-sim\` |
| P4 核心 | `rtl\p4\` 14 份，**逐份 SHA 与包1 `manifest-r0b.json`（`282672fd…45f2`）全等**（`P4_FILES_CHECKED=14 P4_SHA_MISMATCH=0`） |
| 板级外壳 | `rtl\board\` 7 份（`brd_integrated_top.v` 不入闭包：TB 的 DUT 是 `brd_board_datapath`，未例化该顶层） |
| 参考 PCIe RTL | `rtl\ref\ep_side\ddr\ddr_frame_pusher.v` + `rtl\ref\common\{TLP_FMT_TYPE.v,BDF.v}`（只读 copy，`include` 相对路径保持可解析） |
| 集成胶合 | `rtl\int\` 6 份、`rtl\b18\`、`rtl\b20\` 4 份、`rtl\mem\capture_async_fifo.v` |
| 静态 filelist | `sim\sources.f`（37 条，E7；条目与 manifest `files[]` 一一对应） |
| 入口 | `sim\setup_env.ps1`（重建）、`sim\run_sim.ps1 -Scen <n> -Tag <tag>`（编译→运行→比对→退出码）、`sim\make_manifest.ps1` |
| 仿真器 | ModelSim ASE 18.1 `vlib/vlog/vsim -c`，`-voptargs=+acc`，外层 `Start-Process` 5 min 硬超时 |

编译：`COMPILE_OK`，0 error / 0 warning（`sim\logs\compile_*.log`）。
注意：`sources.f` 必须用 `/` 分隔（ModelSim `-f` 把 `\` 当转义）；`vsim -do` 必须走 `.do` 文件（`Start-Process` 参数数组会把 `quit -f` 拆散）。

## 2. before-fix 失败见证（F1 **pass**）

证据：`evidence\before-witness\before-fix_0_20261027_170306.log`（r0 原始 TB 字节、未改 RTL）：

```
# INFO: arm_seq=0 after 400000 tl cycles (SCEN=0)
# DBG fe_b frames=1 groups=768 abort=0 ovf=0 fifo_valid=0 row=0
# DBG p4 acc=1 comp=0 fail=1 rej=0 admit=1 committed=1 exported=0 pub=1 p1g=0 p1a=0 cfgerr=0
# DBG desc active=1 hs=21 arm=0 marshal=124
# FAIL pos: no export (tlp=0 db=0 done=0 status=00000000 err=00)
# POS_RESULT=FAIL
```

`committed=1`、`pub=1`、`drain_words(marshal)=124`、`desc_arm=0`、`exported=0`、`tlp=0`、`db=0`，比对状态显式 `not_executed` —— 与 r0 现场一致，**不是** 0 差异。

## 3. 根因（F2 **pass 部分**：两条必要阻断，均有 cycle 级证据）

探针为 TB 内只读层次观测（`$display`），无 force。

### 缺陷 D1 — 首帧 `capture_seq=0` 与 pusher「新帧沿」判据冲突（阻塞导出启动）

- 证据：`DESC_VALID t=56024000 seq=0 base_w=2048 fbytes=4096 slen=3966 … ident=1`；`PUSH_G t=8000 g_st=0 …`，之后 pusher 进入 `G_ARMED`（`t=6412728000`）仍 `claim=0`，`cb=1 cd=1`（基址/描述符检查均通过）。
- 条件：`ddr_frame_pusher` 用 `src_evt = src_rdy && (src_seq != last_seq)` 识别新帧，`last_seq` 复位为 0；`brd_board_datapath` 的 `a_seq/b_seq` 复位为 0 → 第 1 帧身份 0 与"无帧"不可区分 → `claim` 永不成立 → 无 AR/MWr/doorbell。
- 修复（板级外壳，最小）：`rtl\board\brd_board_datapath.v` 中 `a_seq/b_seq` 复位值 0→1（每帧身份唯一且非 0；**未改** pusher 任何判据）。

### 缺陷 D2 — 描述符释放的相机身份极性反了（阻塞第 2 帧起）

- 证据：修复 D1 后 `DBG arm gs=0 dr=0 wd_en=0 rel_valid=0 rel_cam=1 active_cam=1 b_act=1 a_act=0` —— 排空/释放已发生但 `b_desc_active` 仍为 1。
- 条件：描述符身份为 `a_desc_camera_id=0`(A)、`b_desc_camera_id=1`(B)，而释放路径写成 `if (rel_valid && rel_camera_id) a_desc_active<=0; if (rel_valid && !rel_camera_id) b_desc_active<=0;` → B 路永不清除 → 不再发布新描述符（导出只可能发生一帧）。
- 修复（板级外壳，最小）：极性对调，按身份清除。

### 仍未通过 — D3（未定位完，交下一轮）

修复 D1/D2 后：第 0 帧（arming 帧）被 ARM 消费并按看门狗排空、`rel_count=1`（正常）；第 1 帧描述符 `seq=2 base_w=2048 slen=3965` 到达，`PUSH_G t=144040000 g_st=2 …cb=1 cd=1` → **claim 已成立、pusher 进入 G_TX**，但此后：
- 无任何 MWr TLP、无 doorbell；
- `PUSH_G` 不再变化（停在 G_TX），未触发 `WAIT_LIMIT` 超时；
- 6.4 ms（400000 tl cycles）内无进展。

即导出已在 pusher 内部启动但 DDR 读通路（`brd_ddr_rd_arb` ↔ 模型 r 通道）或读数据返回未推进。证据：`evidence\before-witness\after-fix-frame1-noexport_20261027_172338.log`。这是下一轮的首要定位点（建议先看 `u_dut.u_arb` owner/`o_busy`、`m_axi_arvalid/arready`、`m_axi_rvalid` 与模型 `rd_busy`）。

## 4. 三维与 G 层分账（规划门槛逐条）

**functional / G1**

| 项 | 结果 | 说明 |
|---|---|---|
| F1 失败复现（四元组 + mwr=0/db=0 + not_executed） | **pass** | §2 |
| F2 根因可指到具体条件 + 变异重现 | **partial** | D1/D2 已定位并修复；D3 未定位；"重注入阻断条件"的测试专用变异**未实现** |
| F3 after-fix ≥2 帧 desc_arm/MWr>0/doorbell/exported>0 | **fail** | 第 1 帧停在 G_TX，无 MWr/doorbell |
| F4 每帧 `compared==exact_bytes>0`、`mismatch==0` | **not_run** | 无 TLP 可比较；日志显式 `compared=0 … NOT_EXECUTED=1`，**未**写成 0 差异通过 |
| F5 反压 | **not_run** | TB 已实现 SCEN=3（host `tl_tx_wait` + DDR stall 窗口），未能在无导出时判定 |
| F6 槽复用无陈旧数据 | **not_run** | 依赖 F3 |
| F7 ACK/释放 | **partial** | arming 帧的看门狗释放已验证（`rel_count=1`）；正常 ACK 释放未验证（无导出）；错误 ACK 负例（SCEN=2）未运行 |

**engineering / G0+G5**

| 项 | 结果 |
|---|---|
| E1 编译展开 0 error（0 warning） | **pass** |
| E2 关键路径 0 X | **partial**（首轮 TB 计数器未初始化致 `x`，已修并复跑无 `x`；未做系统性 X 扫描） |
| E3 闭包 SHA 完整 + 一次复跑 | **pass**（`manifest-r0.json` 46 文件全 SHA；`run_sim.ps1` 一次调用可复跑） |
| E4 两次运行摘要一致 | **not_run** |
| E5 P4 SHA 与包1 全等 | **pass**（14/14，`mismatch=0`） |
| E6 G2/G3/G4 明确 not_run | **pass**（本文件声明） |
| E7 静态 `sources.f` | **pass**（37 条） |

**system**

| 项 | 结果 |
|---|---|
| S1 模型边界 | 见 §5（已写） |
| S2 未实现协议责任 6 条 | 见 §6（已写） |
| S3 缩尺/生产参数分离 | 见 §7（已写） |
| S4 证据边界 | 见首页声明 |

## 5. 模型边界（S1）

| 模型 | 能力 | 局限 |
|---|---|---|
| 相机激励 | TB 合成栅格：`CAM 128×96`、ROI `64×48`（768 组/帧），RAW10 packed、4 px/组，每帧内容随帧号变化（`synthetic`，非既有向量） | 无 CSI-2 电气/时序、无 Bayer 物理相位、无真实噪声；不能代表实拍 |
| DDR AXI 从模型 | 256-bit、单拍写、INCR 读、`stall` 可插空（SCEN=3） | 无 DDR3 时序/刷新/ECC；地址按 `>>5` 直接索引，无法发现真实 bank/timing 问题 |
| TLP 主机模型 | 解析 4DW MWr 头 + 32 DW 载荷 + 1 DW doorbell；校验目的地址、长度、doorbell 地址、有效载荷逐字节 | 无 RC 侧协议栈、无 ACK/NAK、无 DLL/TL 层重传、无真实链路 |
| BAR 寄存器模型 | TB 直接驱动 `cfg_*`/`tx_*` 端口 | 无 BAR 译码、无 `0x130..0x13C`、无主机读写时序 |
| 释放/ACK | 主机按 doorbell 载荷（pusher push 计数）回 ACK | 未覆盖真实主机软件时序 |

## 6. 未实现协议责任（6 条，**均未实现**，离线补头/模型填零 ≠ 硬件实现）

1. 44B A1U1 帧头（camera/session/seq/slot/epoch 身份、四 CRC 元数据）——serializer 未闭合；本轮槽内只存 zlib 精确字节。
2. 页尾 `96..4095 B` 零填充/写掩码——仅最后写字内尾零。
3. BAR `0x130..0x13C` 与 `CTRL[9..11]`、`a_enable`（固定 0）——主机读不到 `o_p4_st`。
4. DDR 地址 ×4 重映射——仅仿真模型成立。
5. A 路（`a_enable=0`）与双路——不在本 run。
6. ACK 之后的全身份释放链、错误 ACK/session/epoch/slot 负例——仅 arming 帧看门狗释放已验证，其余未覆盖。

## 7. 缩尺参数（S3）

| 参数 | 本轮值 | 生产值 |
|---|---|---|
| 相机 / ROI | 128×96 / 64×48（768 组/帧） | 生产几何未在本轮 |
| `SLOT_WORDS` | 1024（32 KiB） | 81920 |
| `SLOT_BASE_WORD` | 2048（字节 `0x1_0000`，4 KiB 对齐） | 同 |
| `FIFO_AW` | 10 | 同 |
| `DDR_CAP_BYTES` | `0x0010_0000`（TB） | 板上实配 |
| `exact_bytes` / `page_bytes` | 3966 / 4096（分离命名） | — |

## 8. blocked 原因与最小下一步

- `reason_code=NO_PROGRESS` 叠加 `LIMIT_REACHED`：本轮**已用 30 次调用预算上限之外**（实际约 75 次、约 80 min，主因：ModelSim `-f`/`-do` 入口两次返工、TB 计数器初始化 X、pusher ARM 契约（"ARM 只认之后发布的帧"、`held_seq`=push 计数而非 capture seq）需按参考 RTL 反推）。
- 已实质推进：环境可复跑、P4 绑定 PASS、before-fix 见证冻结、D1/D2 两条真实缺陷定位并修复、arming 帧释放链打通。
- 最小下一步（交原规划，建议 round1 续原开发）：定位 D3（`brd_ddr_rd_arb` 所有权 / DDR 模型 r 通道）→ 通过后补 F4/F5/F6/F7 与测试专用变异负例（重注入 D1 或 D2 条件）→ 两次复跑（E4）→ 重新冻结 manifest 后再交测试。
- 未运行项一律 `not_run`，未写成通过。
