# 收帧写者卡死定位（2026-10-27 板测记录，进行中）

## 现象

T07/RKA1 单引擎位流上板后，两路 R10F 写者（A/B，同一个 `cam_r10f_writer` 模块）会出现
**一路正常发布、另一路永久卡死**，而且被卡住的那一路会用「整帧补零」的方式空转，
再把共享的 DDR 写口占掉一半：

| 观察点 | 正常那路 | 卡死那路 |
| --- | --- | --- |
| `0xA0/0xE0` DDR_FRAME_SEQ | 单调 +1 | 冻结 |
| `0xA8/0xE8` DDR_STATUS | valid=1、err=0 | valid=0、busy=1、err=1 |
| 写者诊断 `0xF0/0x180` = {beats_last, wcnt_last} | beats=整帧、wcnt=518400（0xE900 截 16 位） | beats=整帧、wcnt=**1023**（0x3FF） |
| 判定快照 `0xF4/0x184` | 0x20（pub_ok） | 0x7（p_bad + 无 EOF + 组数不符） |

`wcnt_last = 1023` 恰好是 payload 异步 FIFO 的深度（2^10 − 1）：像素组塞满 FIFO 后
又不再被取走，整帧走 10ms 停滞超时兜底 → 补零到 `DMA_BYTES` → 判定坏 → 立刻开下一帧，
于是该路 100% 忙、把 DDR 写口分走一半（另一路的帧率也被拖到一半）。

## 已经排掉的

1. **不是相机数据坏**：把 B 写者的像素输入临时改成 A 相机那一路（同一份已知正常的
   `w_a_pixel/valid`），B 写者仍然一模一样地卡死（`wcnt=1023`、`verdict=0x7`），
   而同一份数据进 A 写者正常。→ 问题在这片写者实例/它的 AXI 通路，不在 MIPI/传感器。
2. **不是 IDELAY tap**：B 路 tap 从 0 扫到 63（`0xD4`），`B_seq` 始终为 0。
3. **不是仲裁公平性本身**：`0x178` 采样显示 grant 在 A/B 之间轮转（106/94），
   `busy_a` 约一半时间有效、`busy_b` 100% 有效。
4. **补充一个真实的隐患并已修**：payload 异步 FIFO 的写指针在相机域（`rst_cam_all`，
   含 `!alive_c2` 掉时钟检测），读指针原来只认 `rst_ddr`；相机侧一复位就永久失配。
   现在把 `rst_cam_all` 同步到 DDR 域并把读指针一并归零。**这条没有消除上面的卡死**
   （修后 B 仍 `verdict=0x7`），但失配隐患本身是真的。

## 关键线索：卡死态只能靠「重新 arm」清掉

对 `CTRL[5]`（ddr_en）做一次 关→开，B 路当场恢复：

```
before      : ctrl=0x61 A=0x663 B=0x0    arb=0x3
ddr_en=0 3s : ctrl=0x41 A=0x664 B=0x0    arb=0x4  B_vd=0x7
ddr_en=1 6s : A=0x664 B=0x5d  B_vd=0x20  B_wcnt=0x3c80e900   ← 整帧组数对上了
ddr_en=1 12s: A=0x664 B=0xbb  B_vd=0x20                       ← 约 15.7 fps
```

也就是说写者的 AXI 状态机被卡在一个「非 IDLE 且不再前进」的态（采样时多为 `A_W`，
即已经发出 AW、在等写数据通道的 wready），而 `axi_busy = a_st != A_IDLE` 一直是 1，
仲裁器按「被授权者 busy 就保持」的规则把端口压在这一路，另一路的突发永远排不进来。
只有 `arm` 掉一次把状态机拉回 IDLE 才能解。

## 下一步（按信息量排序）

1. 用 `ph1p_pcie_ep_top_dbg` + ChipWatcher 抓卡死瞬间的 `a_st / m_axi_awvalid /
   m_axi_wready / m_axi_bvalid / arb.sel`（探针字库 0x140..0x160 已就位），确认是
   「AW 被接受但 wready 不再来」还是「grant 在自己身上而 awvalid 丢了」。
2. 若是仲裁器保留授权把端口压死：把 `busy` 的语义从「状态机非 IDLE」收紧到
   「有未完成的 AXI 事务（awvalid/wvalid/bready 之一，且跨过 A_W→A_B 的那一拍）」，
   或给仲裁器加「授权方连续 64K 拍没有 awvalid/wvalid/bready 就换手」的看门狗。
3. 若是 DDR 从机侧卡住（AW 已收但 wready 不再来）：在写者 `A_AW`/`A_W` 加超时兜底 ——
   但 `A_W` 中途放弃会留下「从机等着没发完的突发」，必须先确认 DDR IP 的复位/丢弃语义。
4. 临时可用的现场恢复手段：`pci_bar 0 0x44 0x41` → `pci_bar 0 0x44 0x61`
   （掉一次 ddr_en），或者重下位流。

## 复现与观测命令

```bash
# 两路发布号 / 判定 / 写者诊断
for a in 0xA0 0xA8 0xE0 0xE8 0xF0 0xF4 0x180 0x184 0x178; do
  printf '%s ' $a; /root/tools/pci_bar 0 $a | tail -1; done
# 现场恢复
/root/tools/pci_bar 0 0x44 0x41; sleep 3; /root/tools/pci_bar 0 0x44 0x61
```
