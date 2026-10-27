# INT.P4 集成协议（同一候选；r1 修复后，2026-10-27）

## r3 接口/语义增量（2026-10-27）

- **端口/参数/单位不变**：`algo_rowwin3_p4` 与 `algo_rowwin3` 端口逐一相同；`gray8_gaussian3x3_stream_p4`、
  `bayer_raw10_demosaic4_p4`、`img_algo_parallel_top_p4` 同理。A1U1 vs R10F、RAW vs Y8 的分离不变。
- **唯一语义增量**：两个 rowwin 实例的 `prod_valid/prod_*` 与 `win_*` 整体后移 **固定 +1 clk**（读地址/银行打拍 + 描述符/流侧同步延拍）；
  `s_ready = rst_n && cfg_ok && en && (state != ST_FLUSH)` 逐字不变，接收率与反压契约不变；sof/eol/eof/abort 标记、
  生产槽数、flush 顺序、中止/重启规则不变。停顿（en=0）时延迟组整体冻结，下一 en=1 拍消费一次，不丢不重。
- **帧调度**：写口 bank 轮转、读口 bank 选择、`asm40/asm32` clamp 规则、`pe/f_cycle` 产生时刻均未改。
- **既有差距**：`gray8_he_cdfmin_frame.v` 对停顿形态敏感（同一基础 RTL、仅换 ready 种子即 48–99 处差异）；
  因此“语义不变”只在同激励+同 ready 形态下声明，任意背压下的 HE 像素唯一性仍未定义（`img/**` 只读，未修）。
- 单 `clk`（5.333ns）、异步低有效 `rst_n`；无 CDC/异步 FIFO/时钟改动/时序例外。


## 1. 顶层与数据通路

`fpga/csi2/src/integrated_delivery/integrated_delivery_top.v` 是唯一集成顶层，单 `clk`/`rst_n`：

```
capture A/B (40bit RAW10 x4 + sof/eol/eof/abort)
  -> 帧粒度源选路（由 P3 授予的描述符决定 active_cam）
  -> integrated_input_processing_top (INT.P1 r1 → r1.1)
       |- pk_*  packed RAW10 字节流（5B/4px） -> A+ 入口
       `- m_*   选中监视流（mode1/2/3=Y8/高斯/HE，mode0/4=原始 4x10bit）
  -> a1_frame_top (b20 r0 只读候选): zlib 流 (32bit)
  -> a1_ddr_slot_store (MODE=1, b20 r0): 两槽 256bit 压缩帧存储
  -> a1_ddr_arb2 (b20 r0) m1 -> 顶层单一原生 256bit DDR 端口（m0 保留未用）
  -> aplus_pcie_egress_adapter (INT.P2 r0): 描述符/有效长度/尾拍/完成/释放
  -> PCIe 后端描述符面 (desc_*)
```

并行身份（`desc_camera_id/desc_slot_id/desc_epoch/desc_capture_seq`）与 `dual_channel_capture_scheduler`（INT.P3 r1）负责 A/B 身份、`a_enable` 门控、B 优先/轮转、全字段 release 匹配。

## 2. 时钟/复位

- 单 `clk` 域，目标 187.5MHz（5.333ns），异步低有效 `rst_n`；**未新增 CDC/异步 FIFO**。
- 无 false_path / multicycle / 降频；SDC 仅一条 `create_clock`（`tools/integrated_delivery/td/integrated_core.sdc`）。

## 3. 流控与所有权（r1 修订）

### 3.1 单拍双消费者握手（r1 修复 F1/F3）

一个捕获拍同时被两个消费者需要：**选中监视通路**（raw 模式下是监视口本身；处理模式下是三算法共享流）与 **A+ packed 入口**。r1 的强制合同：

- 每个消费者的 valid 只在**对方当拍能接收**时给出：
  - A+ 入口：`pk_valid = s_valid && mon_side_ready`
  - 算法入口：`algo_s_valid = s_valid && pk_ready && !raw_mode`
  - raw 监视口：`m_valid = s_valid && pk_ready`
- 捕获转移判据 `s_ready = mon_side_ready && pk_ready`；因此一拍只被转移一次，任何一侧反压都不会让另一侧"多消费"被源保持的同一拍。
- `mon_side_ready`：raw 模式 = `m_ready`；处理模式 = 算法共享流 `algo_s_ready`。
- 三算法中**只有当前 mode 选中的那一路**可以把反压加回共享流；未选中的 gau/he/y8 输出 `ready=1` 排空，不再因其 8 深输出缓冲占满而卡死共享流（r0 mode1 Y8 监视流 0 拍的根因）。

### 3.2 帧完整性守卫（r1 修复 F1 的"未完整帧不得成功提交"）

- 顶层按 `pk_accept` 统计每帧**实际转移**的 packed 拍数，并要求 EOF 恰好一次、拍数恰好 `W*H/4`。
- 判定在 EOF 拍锁存（`int_ok_r`），`store.wr_last = core_out_last && int_ok_r`：不完整的帧**永远不会**给 store 尾拍，因此不会被发布成 READY/被 P2 领取。
- 若 A+ 仍以自身计数收帧（`core_commit`）而判定不成立，顶层走失败路径：`wr_abort` 丢弃写槽、`rel_status=1` 立即释放描述符，不计入 committed、不产生 `desc_arm`、不 export。
- `GS_RUN` 另有 0x0400_0000 拍（≈341ms @187.5MHz）无进展看门狗：给 A+ 发一拍 abort 并按失败释放，避免源丢 EOF 时把 A+ 与槽存储永久钉死。

### 3.3 描述符/发布/释放

- 一帧端到端流水深度=1：仅当 store 有空槽、无 READY 槽、adapter 空闲、无 drain、A+ 空闲时才接纳一个捕获描述符。
- `wr_begin` 在 GS_BEGIN 握手；A+ 最后一字写入同拍 store 发布 READY；发布事件锁存 id/长度/槽基址后给 P2 一个 `slot_ready` 脉冲。
- host ACK（session,seq 匹配）→ adapter `slot_release` → 顶层 `rd_open` 排空该槽（`drain_data/drain_accept` 可观测）→ `rd_close` 释放 → 同拍向 P3 发全字段 release。
- abort：捕获 abort → A+ `frame_abort` 上升沿 → store `wr_abort` 释放写槽（不发布）→ 立即以 status=1 释放描述符。
- 非授予通道 `s_ready` 恒 0（捕获窗口反压模型）；真实自由运行双相机需要每通道暂存（本包未实现，见 result 差距）。

### 3.4 格式分离

A+ 入口恒为 packed RAW10；`m_*` 监视流按 `cfg_mode` 选路（0/4=原始 4x10bit，1=Y8，2=高斯，3=HE）。两种格式不混用，`m_is_raw` 明确标识。

## 4. A1U1 与 R10F

- A1U1：44B 头（magic 'A1U1'、version=1、flags{6'b0,pred,prep}、header_len=44、frame_id、W、H、raw_len、xform_len、stream_len、raw_crc、xform_crc、stream_crc、header_crc）+ zlib payload；header_crc 覆盖 0..39 字节。
- 传输长度 `desc_frame_bytes` = align_up(stream_len, 4096)；槽内只存精确 stream 字节，尾部由发送方零填充。
- R10F（128B 非压缩参考草案）与本通路分离，RAW 接收入口未被修改。

## 5. 命名（长度/CRC 不混用）

raw_len（W*H*10/8）≠ xform_len（进 A+ 核字节，prep=0 时相等）≠ stream_len（zlib 字节）≠ frame_bytes（4KiB 对齐传输长）。

## 6. 边界（不得当成通过）

本协议只在 RTL 仿真中验证；真实 PCIe 传输（RK 联调）、A 路上板、bit/Flash 均为 not_run。TD 综合已完成，但 clk 187.5MHz setup 时序未收敛（r2：WNS −0.637ns / TNS −69.776ns / 112 违例端点，见 result-r2），故 G2 未通过、未布线。

## 7. r2 变更（时序/握手边界，语义不变）

- **P1 算法支路弹性级**：`integrated_input_processing_top.v` 在 `img_algo_parallel_top_p4` 前加 2 拍
  弹性级（`int_p4_elastic_beats`），捕获侧看到的 `algo_s_ready` 是该级的寄存器"未满"。§3.1 的
  单拍双消费者合同保持：一次捕获拍仍要求 A+ 入口与该级同拍可接纳，且只被转移一次；算法侧不再与
  A+ 侧同拍耦合，帧时序只是被拉长。
- **派生变体（仅时序）**：`bayer_raw10_demosaic4_p4.v`（模块输出改 2 拍弹性级，`pipe_en` 不再组合
  依赖 `m_ready`）、`img_algo_parallel_top_p4.v`（实例化前者 + 在 4 路灰度流与 3 个输出消费者之间
  加 2 拍弹性级）。端口、单位、选路、`sof/eol/eof/abort` 约定、全或全无共享流规则均不变；可观测
  延迟增加 0..~4 拍，数据顺序与标记不变（`tb_img_algo_equiv_p4.v`，`+SEEDMODE=0/1/2`，
  `CHECK_REF_NEW PASS`）。`fpga/csi2/src/img/**` 未改。
- **模式/RAW 语义**：`m_is_raw`、`raw_mode`、未选中算法 `ready=1` 排空、失败帧路径均未改。
- **既有差距**：`gray8_he_cdfmin_frame` 的直方图/映射对停顿形态敏感（同一基础 RTL、仅 ready 序列
  不同即产生 48–99 处差异，`equiv_seedmode*.log` 的 `CONTROL_REF_REF2` 行）。本包未修（`img/**`
  只读），不作为"语义等价"的通过依据。
