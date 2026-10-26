# RK 侧修改清单（T11.rk-align-raw 交付：在 T07 补丁之上的**增量**）

目标仓库：`https://github.com/xiaozhuABCD1234/ph1p100-pcie-ep-driver`，冻结提交
`a0215c5a2fcb95bfc867a4768d4831d68edf64a2`。
**本包不写 peer 仓库、不安装、不推送、不发消息**；只交付离线可复核的增量。

## 0. 为什么必须打这个增量（重要）

T07 交付的 `app/rs/src/rka1.rs::r10f` 是**草案布局**，与正式 R10F v1 / 冻结合同
（`contract/acceptance-vectors.json`、`references/local-inputs/parallel/frame/frame_contract.py`、
T11 写者 RTL）**不一致**，会拒绝 FPGA 实际输出的每一帧：

| 项 | T07 草案（错） | 正式布局（T11 修正后） |
|---|---|---|
| magic | `0x52463052`（字节 "R0FR"） | `0x46303152`（字节 "R10F"） |
| version | 0x04 处 u16 == 0 | 0x04 主=1 / 0x06 次=0 |
| header_bytes | 未检查 | 0x08 == 128 |
| format/codec | format 0x06 / codec 0x08 | format 0x0B == 0；codec 0x0C(u32) == 0 |
| valid_bits/packing | 0x0A / 0x0C | 0x2A == 10 / 0x2B == 0 |
| width/height/stride | 0x18 / 0x1A / 0x1C | 0x1C / 0x1E / 0x20 |
| raw/payload 长度 | 0x20 / 0x24 | 0x2C / 0x30 |
| flags / reserved | 未看 | 0x4C（只允许 0/2；BAD|PARTIAL|OVERSIZE 拒）；0x5C..0x7F 必须 0 |
| sessions/seq | session 0x60 / seq 0x64（**不存在**） | session 0x10 / seq 0x14 |
| payload_crc32 字段 | 0x5C（**错**，那是 reserved） | 0x54 |
| header_crc32 | 0x58 ✓ | 0x58 ✓（0x58..0x5B 清 0 后覆盖 128B）✓ |

⇒ 修正后与 Python 对照实现（`tools/pcie_integration/r10f_strict.py`）逐字段一致，并有静态
交叉核对（`tools/pcie_integration/r10f_tools_consistency.py`，25/25 字段一致）。

## 1. 增量补丁内容（相对 T07 交付树的 `backend/rk-driver-src`）

补丁：`raw/patches/t11-rka1-r10f-fix.patch`（`git apply -p1`；离线 apply-check 通过，
见 `raw/patches/apply-check-stat.txt`）；打补丁后的完整体：`raw/rk-driver-src/`。

| # | 文件 | 改动 |
|---|---|---|
| 1 | `app/rs/src/rka1.rs` | `r10f` 模块按上表修正字段布局；补齐 version/header_bytes/format/codec/valid_bits/packing/几何自洽/flags/reserved/raw==payload CRC 等严格检查；`R10fHeader` 增加 camera_id/mode_id/roi/bayer/block_count/flags/raw_crc32 字段 |
| 2 | `app/rs/src/bin/frame_grab.rs` | 槽内容以 "R10F" 开头时，**发布前**做严格解析（`r10f::parse`），失败即以退出码 5 拒绝；成功打印 session/seq/几何/CRC 摘要。⚠ PGM 输出对 R10F 是 packed RAW10 原始字节（非灰度像素），仅供留证/复算 |
| 3 | `app/rs/src/bin/r10f_check.rs` | 新增离线严格校验 CLI：`r10f_check <文件> [--session 0x… --width W --height H]`，退出码 0/1/2/5；可直接对 `dd` 出来的槽内容 dump 跑（与 Python 工具/合同向量同判据） |

## 2. 应用顺序与校验（RK 操作者）

```bash
# 在精确 peer 快照（a0215c5）上：
git apply -p1 --check backend/patches/rka1-driver.patch   # T07 主补丁
git apply -p1         backend/patches/rka1-driver.patch
git apply -p1 --check raw/patches/t11-rka1-r10f-fix.patch  # T11 增量
git apply -p1         raw/patches/t11-rka1-r10f-fix.patch
# 或者：直接用 raw/rk-driver-src/（= 已含两补丁的完整体）逐文件复核
```

编译/加载仍是 T07 清单 §4 的条件（KDIR、交叉工具链、cargo）；**本包未编译/未安装**。

## 3. 语义要点（与 T07 一致、增量不改的部分）

* **默认不发**：CTRL push 位不产生 DMA；必须 `ARM_ONE_SHOT`。
* **一帧一授权**：ARM 前置条件包含「DDR 源已有发布过的完整帧」且 pusher 只 claim
  **ARM 之后新发布**的帧 —— 所以正确操作序是「先让写者发布过一帧 → ARM → 等下一帧
  发布 → 发送 → held」。首次 ARM 在任何帧发布之前会被拒（这是设计，不是故障）。
* **严格解析通过才 ACK**：三 CRC（raw/payload/header）+ 长度 + 尾零 + session 全过，
  再 `ACK_RELEASE(seq=门铃值, session)`；错 ACK 不释放。
* **CANCEL 不截半包**；held 期间源继续出帧会被拒（0xC8 错误码 8）且该块保持保护。
* **T11 帧内容**：1920×1080，stride 2400B，raw=payload=2,592,000B，头 128B，
  content=2,592,128B，dma_bytes=2,592,768B（633×4KiB），尾 640B 全 0，
  MWr 20,256 笔 + 1 笔单 DW 门铃；`flags=2`（ROI 裁减，本包起写者按此置位）。

## 4. 仍未在 RK 侧闭环的（如实登记，交 RK 操作者/后续增量）

* `frame_grab` 仍是「取一帧→写文件」诊断工具；**ARM→等 held→严格解析→ACK→再 ARM**
  的完整循环尚未接进该工具（`Rka1::arm/ack/cancel` 封装已在库里，可组合；接入需
  control 节点 fd 与命令行扩展）。
* 驱动/内核编译、insmod、设备枚举、实收 100 帧 + 10min 短稳：均不在本包（G3/G4 留板测包）。
