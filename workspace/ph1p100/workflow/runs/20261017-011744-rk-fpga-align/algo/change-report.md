# T09.rk-align-algo — change report（实现、语义冻结与真实状态）

本包实现赛题 R2 的三种四像素预处理**真实 RTL**（4px/beat 输入域，RAW10 `>>2` 到 8bit 域），
并组织成硬件并行小顶；从 Bayer 工作树（只读）带 provenance 引入既有灰度/高斯候选（见
`source-provenance.json`）。

> **本报告如实记录当前状态**（round1 修复轮结束）：G1 全部用例（core 逐样本含 4 个负对照、
> 两个模块级 TB、rate 吞吐）已通过，详见 §5/§6；G2 时序在 round1 对 HE 关键路径做了
> 有界流水后重构建，构建状态见 §7 与 `dev-result.json`。本报告不把未通过写成通过。

## 1. 冻结语义（与 `parallel/algorithms/image_algorithms_ref.py` 一致）

- **CFA 相位**：0=RGGB 1=BGGR 2=GRBG 3=GBRG（按接收像素/行顺序，沿用
  `fpga/csi2/src/mem/bayer565_capture.v`）。
- **输入打包**：4 个 RAW10 样本/拍，**lane 0（最左像素）= bit[9:0]**（与项目
  `csi_rx_10bit_unpack_checked.v` 的输出一致）。
- **去马赛克**：3x3 双线性，**保 CFA 奇偶的复制边界**（左邻列 0→列 1，右邻列 W-1→列 W-2，
  上行 0→行 1，下行 H-1→行 H-2；W=1/H=1 退化为中心）；平均半进位（`(a+b+1)>>1`、
  `(s+2)>>2`）；RAW10→RGB10→`>>2` 截断得 R8/G8/B8（**截断非舍入**，无 AWB/CCM）。
- **Y8**：`(77*R8+150*G8+29*B8+128)>>8`（由工作树 `rgb8_gray_stream.v` 4 份并行承担；
  round1 为 Fmax 加两拍流水——乘积寄存 + 和/移位后移一拍，语义不变，见 §4 第 12 条）。
- **高斯 3x3**：`[1 2 1;2 4 2;1 2 1]`，**普通复制边界**（左/右边界取中心列；上行 0 取行 0，
  下行 H-1 取行 H-1），单次舍入 `(sum+8)>>4`。注意：**与去马赛克的奇偶边界不同**——这是
  参考模型的分工（Y8 域高斯用 plain clamp），本包用 `PARITY_CLAMP` 参数区分。
- **CDF-min 前帧 HE**：当前帧用"最近一个完整有效前帧"的 LUT 输出；首帧恒等；坏帧不发布、
  保留旧 LUT；4 个直方图 bank（lane i→bank i，同拍同 bin 全部计数）；帧末合并后
  `LUT[v]=clamp(round((cdf[v]-cdf_min)*255/den))`（半进位），`den=npix-cdf_min`；
  `den=0`（常量帧）发布恒等 LUT；LUT 乒乓 bank、**帧间原子发布**。
- **边界/帧协议**：`s_eol` 必须恰在每行最后一拍、`s_eof` 恰在 (H-1,最后一拍)；`s_abort`、
  活动期内 `s_sof`、错位 sideband 或超长帧都会**中止帧**（状态复位、发出中止标记、不产生 eof）。
- **支持配置（冻结）**：W%4==0、8≤W≤MAX_WORDS*4（MAX_WORDS=512 → 2048）、2≤H≤2048。
  W=4/H=1 仅由软件参考覆盖（RTL 4px 路径不受支持，cfg 拒绝）。

## 2. 结构与并行组织

```
 RAW10 4px/beat + sof/eol/eof/abort
        |
        v
 bayer_raw10_demosaic4        3 个 RAW10 行 bank + 2 个行窗口读取器（algo_rowwin3/algo_rowwin_reader）
        |  4 x RGB8 lane
        v
 4 x rgb8_gray_stream（工作树候选，逐字节引入）      → Y8 4px 流（= 灰度结果）
        |
        +------------------+------------------+
        v                  v                  v
   y8 输出缓冲        高斯分支               HE 分支
   (algo_obuf)   gray8_gaussian3x3_stream  gray8_he_cdfmin_frame
                 3 个 Y8 行 bank           4 bank 直方图 + 乒乓 CDF-min LUT
                 + 2 个读取器               + 合并/除法/LUT 生成/清零状态机
                 + 核运算流水               + 输出缓冲(algo_obuf)
                 + 输出缓冲(algo_obuf)
```

- **三路并行**：共享前端（去马赛克+Y8）后，三条输出分支是**独立算术流水**，正常帧内每拍
  各产出一拍；无串行复用。每个输出端口各有 8 深弹性缓冲（`algo_obuf`），使端口
  ready/valid 握手合法（见 §4）并在短停顿下解耦。
- **共享流的转移条件**：`y8_xfer = g0_valid && (y8_fifo_ready && gau_s_ready && he_s_ready)`
  ——同一拍要么三个消费者全接收、要么整体停顿（单输入流设计，不丢拍不重复）。
  某一分支的内部停顿（如 HE 帧末计算）会经此条件向共享流回压，**这是已冻结的设计属性**，
  不是串行化：三路算术单元始终独立、并行。
- **行窗口机制**（`algo_rowwin3`，前端与高斯共用）：3 个行 bank，写入 bank 按行
  W(r)=0,2,1 循环，两个扫描读取器同序旋转，保证每 bank 每拍至多一次访问；生产行 y 在输入行
  y+1 流入时装配（末行后固定冲刷 m+1 拍）；事件驱动（每个接收拍或冲刷拍），输入停顿即整体
  冻结。读取器在事件拍发出地址并在**事件之间保持该地址**，使不规则事件（gap/停顿）下同步读
  数据不失效。

## 3. 接口与参数冻结（顶层 `img_algo_parallel_top`）

| 端口组 | 语义 |
|---|---|
| `clk/rst_n` | 单时钟域；异步低有效复位 |
| `cfg_valid/cfg_ready/cfg_width/cfg_height/cfg_phase/cfg_error` | 一次锁存；非法几何（W%4≠0、W<8、W>2048、H<2、H>2048）→ `cfg_error=1` 且不收帧 |
| `s_valid/s_ready/s_data[39:0]/s_sof/s_eol/s_eof/s_abort` | 4px RAW10 输入；`s_ready` 低即整体停顿（保持 data/sideband）；`s_abort` 随拍有效 |
| `y8_*/gau_*/he_*` | 三路 4px Y8 输出，各自 `valid/ready/data[31:0]/sof/eol/eof/abort`；数据与 sideband 同拍；停顿保持 |
| `st_frames_good/st_frames_abort/st_he_published/st_he_rejected/st_gau_abort` | 16bit 计数器（每 RESET 清零） |
| `he_lut_addr/he_lut_data` | HE 活动 LUT 只读监视口（1 拍延迟） |

- 中止语义：中止帧**不产生 eof**；三个端口各发出**一次** `*_abort` 标记（一个 valid=1 的
  控制条目，经输出缓冲后在端口呈现为 `valid=0, abort=1` 的一拍事件），标记位置在"中止前已
  接收数据拍"之后、下一帧数据之前。
- HE 帧末（合并 259 拍 + LUT 256×14 拍 + 清零 256 拍，≤~4.2k 拍）期间其输入 `s_ready=0`
  → 共享流回压；复位后先做一次 256 拍 bank 清零再收帧（仿真/上电都从确定状态开始）。

## 4. 本轮发现并修复的真实缺陷（可复用）

1. **输入打包方向**：窗口装配最初按 MSB-first 假设，与项目 `csi_rx_10bit_unpack_checked.v`
   的 lane0=[9:0] 约定相反 → 逐样本全错。修正为 lane0=LSB（`asm40/asm32`）。
2. **高斯边界规则**：初版把去马赛克的"保奇偶 clamp"用到 Y8 高斯上 → 边界像素与参考不符。
   增加 `PARITY_CLAMP` 参数（去马赛克=1，高斯=0）。
3. **读取器跨事件数据失效**：同步 RAM 读地址随读取器寄存器前进，事件间（gap/停顿）读数据被
   "推测读"覆盖 → 不规则事件下窗口错误。改为"事件拍发地址、事件间保持"。
4. **共享流重复/丢失拍**：输出缓冲初版按 `w_valid || w_abort` 推入（held 标记被反复推入），
   且分支 s_valid 未与全局转移条件对齐 → 重复/丢失。改为 `w_valid && !full` 且
   `s_valid = y8_xfer`。
5. **FIFO 指针/条目宽度**：AW=4 与 DEPTH=8 不匹配（越界读）、条目 36bit 声明 37bit
   （abort 位被零扩展掉）→ 修正 AW=3、`[DW+3:0]`。
6. **HE 直方图读数据未赋值**（`rd_r` 悬空）→ 计数全 X。改为直接用读端口数据 + 旁路。
7. **HE 上电未清 bank** → 首帧计数 X。复位后进入 ST_CLEAR（256 拍）。
8. **HE `ab_pend` 多驱动**（ModelSim 容忍、**TD 综合报 HDL-8007**）→ 合并为单 always。
9. **TB/向量侧**：cfg 握手时序、段指针复位、跨几何组 DRAIN 屏障、`12'd4096` 12bit 截断为 0
   等（细节见 lessons-learned.md）。

### round1 修复轮新增（G1 根因定位 + G2 时序流水）

10. **中止标记在分支 IDLE 态被静默丢弃**（round0 遗留 16 条 mismatch 的真根因）：分支
    `prod_abort` 原只在 `state == ST_ACTIVE` 时产生。对"前帧正常结束后、本帧在首个输出行
    之前就被中止"的帧，前端不产生任何生产拍 → 分支从未打开该帧 → 标记到达时分支在 IDLE
    → 标记被丢 → 下游检查器停在 prefix 段并把下一帧数据当本帧消费（现象与观测完全一致：
    branch1/2 错、branch0 对）。修正：`marker_evt = accept && s_abort` **恒**产生输出标记，
    `abort_evt`（状态复位/计数）保持状态门控；HE 同样改为 `mk_evt` 恒转发（`mk_d` 随数据
    流水逐拍推进，替代原来的 2 级 `ab_pend/ab_st1` 链，避免与数据拍错位）。
11. **标记条目携带 stale sideband**：标记拍未加载 `p_sof/p_eol/p_eof`（沿用上一生产拍值），
    下游 rowwin 的 `abort_restart = abort_evt && s_sof` 把标记当**帧重启** → 多出伪标记。
    修正：demosaic / gaussian / HE 三处在标记拍把 sideband 显式清 0。
12. **HE 关键路径有界流水（Fmax）**：TD 报最差 -3.870ns，路径为 ERAM clk2q → 32bit 减 →
    DSP 乘 → 32bit 加 → `rem`，以及 4-bank 和 → 32bit 累加 → `cdf_min`。修正（语义不变）：
    合并 pass 先寄存 `hsum_r`（写入顺延一个地址，`mrg_a` 跑到 257）；LUTGEN 相位扩为
    0..4（ERAM 输出再寄存 `cdf_v`、差值 `cdf_d`、乘积 `num_r`、`rem` 各占一拍）+ 除法用
    预移位寄存器 `den_s`（替代 `den32 << i_r` 变量移位）。LUT 生成 256×14 拍。
13. **两个模块级 TB 的采样/初始化竞态**：gray TB 的 `reg m_ready = 0` 与 `always @*` 冲突
    → `m_ready` 永远 0 → 驱动侧死等（首向量超时的真根因）；gauss TB 检查器在 negedge
    采样而 DUT 在 posedge 消费 → 输出整体错位一位。修正：初始化值与 always 首值一致、
    检查器统一 posedge 采样。
14. **负对照判定与锚点**：变异判定原要求 `exit != 0`，但 TB 以 `$finish` 结束、退出码恒 0
    → 判据改为"无 PASS 标记 + 出现指定 mismatch + 无仿真错误"；`gray_clamp` 锚点随 RTL
    修复漂移，已同步；另补 `runs` 图案（长同值）使 `he_samebin` 变异可被捕获。

## 5. G1 证据（ModelSim 真实 RTL，独立软件模型）

- 独立 oracle：`tools/algo/oracle_algo.py`（与 `parallel/algorithms/image_algorithms_ref.py`
  交叉自检 10/10 PASS：demosaic/y8/gaussian/hist4/cdf-min/HeLut 序列）。
- 向量：`algo/vectors/algo_core.vec`（24 场景：4 相位、8x2/8x3/12x4/16x5/20x2 几何、
  ramp/random/constant/black/white/checker/impulse/extreme/runs 图案、abort/bad-eof/over-length/
  sof-restart 坏帧、帧内 GAP/STALL 停顿、复位分段）＋`algo_core.lut.hex`（最终 LUT 期望）。
- runner：`tools/algo/run_g1.py`（复制冻结源到 ASCII subst 工作目录、可选负对照变异、记录
  命令/退出码/日志 SHA/标记；原文件 SHA 前后校验）。
- 覆盖（core 运行实测）：三路并发产出计数（all3=53、ge2=136 拍三路/两路同拍有效）、
  停顿保持校验（hold=6）、输入 gap=10、stall=28、6 个坏帧标记（markers 6/6/6）、
  HE 发布/拒绝计数（frames=2/1）、LUT 读回与 oracle 期望逐字节一致（dump SHA 相同）。

## 6. G1 结果（round1 修复后，全部通过）

| 用例 | 结果 | 关键覆盖 |
|---|---|---|
| `core`（逐样本三路 + 负对照基座） | **PASS** | 24 场景全部逐样本一致；all3=53/ge2=136；hold=6；stalls=28；gaps=10；markers 6/6/6；LUT 读回 SHA 与 oracle 相同 |
| `core` 变异 `gray_round` | **PASS（负对照成立）** | 拒绝：branch 0 首帧 idx=0 数据 mismatch |
| `core` 变异 `gray_clamp` | **PASS（负对照成立）** | 拒绝：branch 0 边界列 idx=0 mismatch |
| `core` 变异 `gau_round` | **PASS（负对照成立）** | 拒绝：branch 1 idx=0 起 mismatch |
| `core` 变异 `he_samebin` | **PASS（负对照成立）** | 拒绝：branch 2 多帧后 mismatch（`runs` 图案暴露丢计数） |
| `gray`（工作树候选模块级） | **PASS** | accepted=307/emitted=306、stalls=41、gaps=12、resets=1、hold=41 |
| `gauss_frame`（工作树候选模块级） | **PASS** | frames=12、pixels 334/311、stalls=138、resets=2、非法配置拒绝=2 |
| `rate`（1920x1080 x2 连续流） | **PASS** | 每帧 518400 拍；cyc_f0=519370 / cyc_f1=519942 / settled=1040120 → 1.0032 拍/帧拍（≈748 Mpx/s @187.5MHz）；all3=1035832 |

- round0 遗留的 16 条 mismatch 已全部消除，根因与修正见 §4 第 10/11 条。
- 负对照均为**可重放**：`run_g1.py --case core --mutation <name>` 复现同一拒绝（含 mismatch 采样）。

## 7. G2 构建（TD 6.2.3，模块级小顶）——round1 达标

- 小顶：`img_algo_parallel_top`（真实并行组织）+ 薄 pin 级包装 `img_algo_top_g2.v`
  （顶端口 ~285 > 器件 286 IO，独立构建需包装；包装内为固定 64x8 phase0 cfg 与计数器
  合成输入、三路输出串行折叠，仅作综合/STA/资源载体，**不下载**）。
- 约束：`tools/algo/td/img_algo_top.sdc`（`create_clock algo_clk 5.333ns` = 集成的 187.5MHz
  字节域目标；**未改动主工程 SDC**）；`img_algo_top.adc` 仅钉 clk/rst_n/2 输出。
- 构建入口：`tools/algo/run_td_algo.ps1` + `tools/algo/td/00_all.tcl`（单会话 00_all，
  不下载/不写 Flash）。round1 重建序列：`smalltop-r0d`（基线 -3.870ns）→ `smalltop-r1a`
  （HE 合并/LUTGEN 流水，-1.208ns）→ `smalltop-r1b`（直方图写流水 + gray 两拍流水，
  **达标**）。
- **最终构建 `algo/g2/smalltop-r1b/`**（同一最终 DB，PRJ-1406 phy_1 finished + PRJ-1424
  saved as best result + T09_ALGO_ALL_DONE）：

| 指标 | 实测 | 判据 |
|---|---|---|
| setup（SWNS / STNS / 违规端点） | **+0.059ns / 0.000ns / 0** | ≥0 / =0 / 0 |
| hold（HWNS / HTNS） | **+0.020ns / 0.000ns** | ≥0 |
| Fmax（intra algo_clk） | **189.609MHz**（Min Period 5.274ns） | ≥187.5MHz 目标 |
| Routed | 是（route flow 完成，bit 保存） | Routed |
| 资源 | LUT6 2858/71680 (3.99%)、Slice 2946/71680 (4.11%)、reg 1831/143360、
ERAM 5/300、DSP 8/220、IO 6/286 | ≤器件 |
| bit / 报告同源 | 同一 run 目录同一构建：`ph1p_algo_smalltop.bit` SHA256
`C8E62E94…AF56`、`final_timing.rpt` SHA256 `332852B7…9937`、`ph1p_algo_smalltop_phy.area`
SHA256 `851AEF3B…D15C` | 同源 |

- 关键路径修复（语义不变，见 §4 第 12 条）：HE 合并 pass 的 4-bank 和先寄存、写入顺延三个
  地址；LUTGEN 相位 0..4 把 ERAM 输出/差值/乘积/加法各占一拍，除法用预移位 `den_s`；
  直方图写数据/地址/使能寄存（写比读晚两拍，bypass 改为两拍同 bin 补偿）；`rgb8_gray_stream`
  乘积寄存 + 和/移位后移一拍（顶层 eof/abort 延迟同步两拍）。
- 小顶 bit 为模块级载体，**不代表**主工程最终候选；G3/G4 板测未做。

## 8. 吞吐预算与实测（按 4px/beat，头/报文另计）

- 设计：连续服务 4 px/拍；187.5MHz 字节域 → 750 Mpx/s 原始处理能力。
- **实测**（`g1/msim/rate-*`，1920x1080 x2 连续流，ModelSim 真实 RTL）：
  - 每帧 518400 拍；`cyc_f0=519370`、`cyc_f1=519942`、`settled_cyc=1040120`
    → **1.0032 拍/帧拍**（含 HE 帧末计算回压），即 ≈0.997 拍/拍 ≈ **748 Mpx/s**（187.5MHz）。
  - 三路并发计数 `all3=1035832`（约 99.9% 的拍三路同时有效），三路 beats 数均等于
    帧数 x 每帧拍数。
- 1080p30 单路 62.2 Mpx/s（≈8.3% 占用）、双路 124.4 Mpx/s（≈16.6%）；1080p60 双路
  248.8 Mpx/s（≈33%）。行内无气泡；帧末 HE 计算 ~4.1k 拍，占 1080p30 帧间隔（~33ms）
  的 <0.02%。

## 9. 未测边界与限制

- W=4/H=1、W>2048、H>2048：RTL 拒绝（cfg_error），仅软件参考覆盖。
- 真实相机几何/相位/坏帧：合成/参数化输入；真实板验留 T07/T11 板测包（G3/G4 未做）。
- G2 的 bit 为模块级小顶载体，**不代表**主工程最终候选。
