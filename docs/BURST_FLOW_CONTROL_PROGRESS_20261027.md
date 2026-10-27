# 突发级流控：施工进度与踩坑记录（2026-10-27 第三轮）

目标：把 `cam_r10f_writer` 从「整帧独占 DDR 写口」改成「按突发分时」，让 A/B 两路同时出帧。
根因与完整修法见 [DDR_ARBITER_ANALYSIS_20261027.md](DDR_ARBITER_ANALYSIS_20261027.md)。
本轮把这条修法推进到「整帧基本写满、只差 4 个组」，但**还没上板跑通**，代码已回退，
板上仍是「帧级轮转 + 坏帧自愈」那版。

## 三次上板的结果（同一套 gating，逐次修正）

| 版本 | 现象 | 诊断字 `wcnt_last` | verdict |
| --- | --- | --- | --- |
| v1 只有 mid_frame 门槛 | 两路 0 帧 | 1023（FIFO 满，几乎没写） | 0x7 |
| v2 + `need_first` 帧首无条件放行 | 两路 0 帧，数据多一点 | 14727（≈30 行） | 0x7 |
| v3 帧首只发 4 拍（`AWLEN_FIRST=8'd3`）+ `burst_beats = awlen+1` | 两路 0 帧，但**整帧基本写满** | **59644**（≈ 518400 mod 65536，差 4 组） | **0x4**（只剩组数不符） |
| v3b 再给 `burst_beats` 加 `min(beats_left)` | 综合报错 `index 16 out of range`（`BTL_CW=17` 对 8 位 `cur_awlen1` 位选）→ 改宽后又撞上编译目录被并发构建弄坏（`phy_1/settings.cfg` 丢失） | — | — |

结论：**v3 已经证明思路对**（`p_bad=0`、`p_eof_seen=1`、beats 整帧齐），只剩最后一笔的拍数算错，
少写 4 个组（20 B）导致组数判定不过。

## 关键教训（下次直接照做）

1. **帧首那一笔必须只发 4 拍**（128B 头）。发 128 拍的话，这笔要开着等 ROI 起始行
   （`Y0+SKIP_ROWS = 540+37 = 577` 行，4K 下 9~18ms），期间 `axi_busy=1`，
   仲裁器按「被授权者忙就保持」把端口压死，另一路照样饿死。
2. **等数据期间 `tmo` 不能计数**（加 `&& !mid_frame`），否则 ROI 前的空白本身就能把帧判超时。
3. `burst_beats` 改成按「当前这笔的 awlen」算之后，**必须对 `beats_left` 取 min**
   （`cur_beats_x = zero_extend(cur_awlen1)`，`burst_beats = min(beats_left, cur_beats_x)`），
   否则最后一笔会多算、`next_beats` 下溢 —— v3 的「少 4 组」就是这里。
   位宽：`BTL_CW = clogb2(DMA_BEATS) = 17`，不能拿 8 位的 `awlen+1` 直接位选。
4. `self_flush` 必须同时清 `mid_frame`/`need_first`，否则会停在 `A_IDLE` 等一个永远不来的
   `burst_ok`（`S_SYNC` 会一直把 FIFO 抽干，占用永远涨不到门槛）。
5. **不要同时跑两个 TD 构建**：本轮两次构建撞同一个 `ph1p_pcie_ep_top_Runs/`，
   第二次的 `phy_1/settings.cfg` 直接丢了，TD 卡在「wait_run」十几分钟不退出。

## 下一轮的执行顺序

1. 按上面 1~4 写好补丁（重点是第 3 条的 min 与位宽），先**单路**编译上板：
   把 `w_cam_ddr_want_a/b` 都接死一路（另一路不 arm），确认 `wcnt=518400`、`verdict=0x20`。
2. 单路通过后再开两路、并**去掉帧级轮转**（`w_cam_ddr_want_a/b` 都直接接 `img_ddr_en`），
   量两路各约 15 fps（端口占用估算 1.3%）。
3. 通过后删除轮转 stopgap 与本节临时调试字，把结论并进 `BOARD_TEST_20261027.md`。

## 当前板上状态（已验证）

- 位流：帧级轮转 + 坏帧自愈（`fpga` HEAD `57611168`/后续文档提交），20:16 构建，`PRG-2014` 通过。
- A 路 15.6~15.7 fps 稳定、`verdict=0x20`、`wcnt=0xE900`（整帧）；B 路空闲干净（`verdict=0x0`）。
- 取帧校验：`r10f_strict.py check` → **R10F_STRICT_OK**，sha256 `afb15c02265cefb5f994a343736e247c5e6b5ad53639f3a302ae54ed0a2df8c7`。
## 第四轮补充（2026-10-27 晚）

- **v4（加了 `burst_beats = min(beats_left, awlen+1)` 与位宽修正）**：上板结果与 v3 完全一样 ——
  两路 0 帧、`verdict=0x4`、`wcnt=0xE8FC=59644`（518400 − 4）。所以「少 4 组」**不是**最后一笔
  拍数算错，另有来源。
- 最有说服力的假设：加了突发门槛后 FIFO 长期贴满（阈值 827 / 深度 1024），
  末段 `wfull` 会把最后几个组丢掉（`push_blocked` / `drop_cnt`），于是 `pay_written` 停在
  2591980，整帧差 4 组。验证方法：把 `drop_cnt/ovf_cnt`（现在是 `dbg_anomaly`，只出一位）
  或 `pay_written` 接到 0x188/0x18C 这类空闲只读字上，直接看丢了多少。
- 顺手试了 **`FIFO_AW 10 → 11`**（把 5KB 缓冲加倍）：TD **两次段错误**（exit 139）都没出位流，
  已回退。下次要么换更大 ERAM 配置并确认 `f_wr` 位宽没溢出，要么先只降门槛（`BURST_GROUPS`
  从 827 降到 ~600）看丢组是否消失。

## 环境教训（本轮又踩一次）

- **烧写的读回校验会失败**：本轮一次 `bw.sh` 虽然打印 `PRG-2014`，但紧接着
  `PRG-1000 recv timeout` / `PRG-9507 read = 0xFFFFFFD0 ref = 0x01`，位流其实没落上，
  板子重启后 `lspci` 直接看不到 `1edb:abcd`。**判据要看完整日志里没有 PRG-1000/9507**，
  只看 PRG-2014 不够；失败就 `pkill -x hwserver` 后重烧一次（第二次成功）。
