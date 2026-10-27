# RK 侧必须修改清单（T07.rk-align-backend 交付）

目标仓库：`https://github.com/xiaozhuABCD1234/ph1p100-pcie-ep-driver`，冻结提交
`a0215c5a2fcb95bfc867a4768d4831d68edf64a2`。
交付形式：`backend/patches/rka1-driver.patch`（对上述精确快照 `git apply -p1` 通过，
`--check` 与真实 apply 都已在本 run 离线验证；reverse 用 `git apply -R -p1`）。

配套的完整体（补丁打上后的树，便于逐文件复核）：`backend/rk-driver-src/`。
**本包未在 RK 机器上编译/安装/加载**：编译依赖真实内核树与交叉工具链（见 §4）。

## 1. 必须改（逐条与 contract/rk-required-changes.md 对应）

| # | 位置（补丁后） | 必须改的内容 |
|---|---|---|
| 1 | `include/anlogic_pci_ioctl.h` | `ANLOGIC_CTRL_ARM_BITS = enable|ddr_en|push_en = 0x61`（去掉旧 bit4），新增 `ANLOGIC_CTRL_CAM_B = 0x100` 与 `ANLOGIC_CTRL_ARM_BITS_B = 0x161`；bit4 标注保留（写 0/读 0）；`ANLOGIC_BAR_LINK_WIN_END = 0x130` |
| 2 | 同上 | 新 ABI 常量：`ANLOGIC_FRAME_HDR_BYTES=128`（16B 结构体 + 112B 零 pad，**结构体布局不变**）、`RAW_BYTES=PAYLOAD_BYTES=2592000`、`DMA_BYTES=2592768`、`TAIL_PAD=640`、默认 1920x1080、默认单槽 |
| 3 | 新文件 `src/anlogic_pci_rka1.c`（+ `.h` 声明、Makefile 加一行） | 扩展探测（EXT_MAGIC/EXT_VERSION，fail closed）、授权配置（CAP/SESSION，活动期拒改）、one-shot ARM、ACK_RELEASE（必须匹配 held(session,seq)）、CANCEL（等 busy/draining 清零）、新 ioctl 15 `ANLOGIC_IOCRKA1` |
| 4 | `src/anlogic_pci_frame.c` | hdr_bytes=128；slot_bytes 默认 DMA_BYTES 且必须 4KiB 整数倍；**非法参数返回错误，不再静默夹紧**；`slots != 1` 拒绝；分配/清零 + mailbox 几何按新常量 |
| 5 | `src/anlogic_pci_link.c` | 先 `rka1_probe`（失败=不授权、只留采集/诊断）；写 CAP/SESSION；`dst = phys + 128`、`db = phys + mb_off + 32`；CTRL 只写模式位；随后 `ARM_ONE_SHOT`；`PUSHCFG` 限制在授权缓冲内且活动期拒绝；`disarm` 先 CANCEL 再关模式位 |
| 6 | `app/rs/src/rka1.rs`（新）+ `lib.rs` 挂模块 | 严格 R10F 解析（magic/version/format/codec0/valid_bits10/packing0/几何/三层长度/三 CRC/尾零全 0/session 匹配）+ ARM/ACK/CANCEL 封装 |
| 7 | `app/rs/src/bin/frame_grab.rs` | 槽 `len` 必须等于约定的 dma_bytes，**不再夹紧后当成功**；搬运前用 rka1.rs 的严格解析；核对通过再 ACK（session+seq），然后才 ARM 下一帧 |

## 2. 语义要点（写进你们的 driver README/commit message）

* **默认不发**：CTRL 置 push 位**不会**产生任何 DMA；必须 ARM。
* **一帧一授权**：ARM 成功后最多完成一帧；完成后 `TX_STATUS.bit2=held`，不匹配 ACK 不释放；
  释放后必须**重新 ARM**。用户态核对（三 CRC + 长度 + 尾零）通过才能 ACK。
* **错误 ACK 不覆盖 held 槽**；**CANCEL 不截半包**、不发成功门铃、不加成功序号，
  等 `TX_STATUS` 的 busy/draining/held/armed 全清才可释放/复用收帧内存。
* **来源缓冲**：FPGA 在 held 期间锁住对应 DDR 块（release 事件才解锁），
  所以「慢消费」不会覆盖；但这也意味着**不 ACK 就再也不会有新帧进入该槽**（背压，不是卡死）。
* **旧行为已删**：0x108 的 W1 语义（单 bit 才有效）、0x71 旧 ARM 掩码、按「写 CTRL 自动连续推帧」的老路径
  都不存在；旧驱动配本候选会读到 `EXT_MAGIC=RKA1` 但 `ARM_BITS` 判定与窗口不匹配 —— 请按本清单改。

## 3. ioctl 结构改动情况（ABI）

* **旧结构体/编号一个都没动**（`anlogic_ioc_bar/_bulk/_frame/_frame_wait/_link_status/_link_retrig/_push_cfg`）。
* 新增 `struct anlogic_ioc_rka1` + `ANLOGIC_IOCRKA1 = _IOWR('x', 15, ...)`（新编号）。
* 槽头仍是 16 字节四 u32；`hdr_bytes` 由 ioctl 返回（=128），用户态**必须用它**。

## 4. 编译/运行依赖（本环境没有，必须由 RK 操作者提供）

* 真实 RK3588 内核头/构建树（`KDIR`）与交叉工具链（`ARCH=arm64 CROSS_COMPILE=...`）
* Rust（用户态）：`cargo` 工具链 + `app/rs/Cargo.toml` 现有配置
* 运行时事实：设备 BDF、内核版本、`getconf PAGE_SIZE`（4KiB 假设在布局里）、
  PCIe MPS 协商值、DMA mask / IOMMU 状态
* 本包只做离线 `apply --check` + 静态复核；**未编译、未安装、未加载**。

## 5. 验证建议（打完补丁之后）

1. `git apply -p1 --check` 先过；再在干净树上打上并编译内核模块（编译不过请把完整报错发回）。
2. `rka1 probe`（如果你们有工具）或直接读 0x118/0x11C 确认 RKA1；不匹配就停下（fail closed）。
3. 单帧流程：configure(cap>=2592768, session≠0) → arm → 等 held（0x114.bit2）→ 严格解析 →
   `ack(seq=门铃值, session)` → 再 arm；每次失败都读 0xC8/0x114 记错。
4. 反例：错误 seq/session 的 ACK（必须不释放）、held 期间拔链/超时（必须不新发）、
   CANCEL（必须补完已开包、无成功门铃、序号不加）。
