# 第 22 章 DMA 与完成语义

> 传输篇第 2 章：数据面通道（第 21 章）已定之后，本章回答"**谁能写、什么时候算完成、出错怎么退**"——授权、完成、回收三件事。帧内容的字节格式见第 23 章；帧槽在 DDR 侧的所有权见第 12 章。
> 事实标记：【本项目事实】可追溯到项目文件路径；【通用原理】来自公认外部资料；【设计候选】【待验证】【未决】表示尚未实现/未板验/未拍板。

## 10 分钟速读卡

- **本质一句话**：DMA 的难点从来不是"搬得快"，而是"**什么时候可以搬、搬到哪、什么时候算数、错了怎么退**"——地址授权、完成可见性、缓冲回收三件事。
- **为什么重要**：没有授权，一个错误地址就是踩主机内存；没有完成语义，主机不知道数据是否可读；回收错了，就会覆盖还没消费的帧。
- **本项目怎么用**：**one-shot 授权模型**——主机 ARM（授权一帧）→ 推完置 held → 主机严格核验（三层 CRC/长度/尾零/session）→ ACK 释放 → 再 ARM；控制字 CTRL 冻结值 `0x61`（B 路 `0x161`）。
- **一个记忆锚**：**"一帧一签"**——不是订阅制（交一次钱天天送），而是每帧都要重新下单（ARM）、签收（ACK）后才送下一帧。

## 本章要回答的问题

1. 主机为什么必须先"授权"（DMA 地址 / 容量 / 生命周期）？
2. one-shot 流程 ARM → held → ACK → 再 ARM 的每一步在防什么？
3. "完成可见性"指什么？门铃之后数据真的可读吗？
4. CANCEL / 超时 / 复位之后，怎么恢复？
5. CTRL `0x61` 与 `0x161`、session 的直觉是什么？
6. 为什么"慢消费者"应该被背压，而不是被覆盖？

## 直觉：快递代收点

主机＝收件人，FPGA＝快递员：

- **授权（ARM）**＝收件人先说"放这个储物柜，就一格的量"；快递员才有权投递。**不授权，投递（push）位开着也不发**。
- **完成（held）**＝快递员把包裹放下、挂上"已送达"牌；在此之前收件人不能假定柜子里有东西。
- **核验与签收（ACK）**＝收件人开箱核验（清点/查损）后才签字；**没签字，快递员不会往这个柜子再送**——这就是背压。
- **取消（CANCEL）**＝中途叫停：可以停下，但**不会把一个残缺包裹冒充成"已送达"**。

## 原理：授权 → 完成 → 释放

### ① 授权：主机给"可写区"，EP 不写死地址

- 主机（驱动）用内核 DMA API 分配收帧缓冲，给 FPGA：`dma_addr`、容量、会话号；FPGA 侧校验地址宽度与容量，**越界拒绝并置 `OVERSIZE`**（`../../parallel/docs/帧与元数据接口合同_2026-10-15.md` §6）。
- **槽（slot）布局**：槽头 16B `{seq,len,flags,rsvd}`；槽区 `stride=PAGE_ALIGN(16+slot_bytes)`；mailbox 64B 页。RKA1 约定把槽头区扩展为 **128B**（16B 结构体＋112B 零 pad）——R10F 帧从槽内偏移 **+128B** 开始（`../../workflow/runs/20261017-011744-rk-fpga-align/backend/rk-change-list.md` §1 #2/#5）。
- **CTRL 的直觉**：`ARM_BITS = enable|ddr_en|push_en = 0x61`（A 路）；B 路加 `CAM_B=0x100` → `0x161`；bit4 保留（写 0/读 0）。**置 push 位≠开始推**——真正开闸的是 `ARM_ONE_SHOT`（rk-change-list §1 #1、§2；decision-register M2e）。

### ② 完成：held 与门铃

- 一帧推完后，FPGA 置 `TX_STATUS.bit2=held`：代表"这一帧已放好、且源缓冲被锁住"；同时一笔门铃（单 DW）已写入 mailbox（第 21 章）。
- **held 期间 FPGA 锁住对应 DDR 源块**，直到收到释放事件——所以**慢消费不会覆盖**；**不 ACK 就再也不会有新帧进这个槽**——这是**背压，不是卡死**（rk-change-list §2）。
- **完成可见性**【通用原理】：Posted MWr 的写入到达次序有保证，且本项目映射为 Normal-NC（非缓存）——数据落 DRAM 后 CPU/用户态**直读可见**；若将来改为 cacheable 映射，**必须补 `dma_sync_single_for_cpu()`**（评估 §1.2 / §5 R7）。门铃不是 MSI 中断——本项目**靠轮询**（评估 §2.2 第 5 条）。

### ③ 释放：ACK 必须"对得上号"

- `ACK_RELEASE` **必须匹配 held 的 (session, seq)**；**错误 ACK 不覆盖 held 槽**；释放后**必须重新 ARM** 才会接收下一帧（rk-change-list §2）。
- 用户态**先严格解析**（第 23 章：magic/version/format/codec/几何/**三层长度/三 CRC/尾零全 0/session 匹配**），核对通过才 ACK——"先核验再签收"（rk-change-list §1 #6/#7）。
- **CANCEL 的三个"不"**：不截半包、不发成功门铃、不加成功序号；等 `TX_STATUS` 的 busy/draining/held/armed 全清之后，才允许释放/复用收帧内存（rk-change-list §2）。

### 数字与寄存器速查

```text
CTRL  : 0x44，ARM_BITS=0x61（A）｜0x161（B）｜bit4 保留
RKA1  : 0x118 EXT_MAGIC / 0x11C EXT_VERSION（探针，fail closed）
状态  : 0x114（bit2=held）｜0xC8 错误码｜0xCC 上帧 MWr 数
错误码: 0 正常｜1 无目标｜2 wait 超时｜3 AXI 非 OKAY｜4 无门铃
布局  : 槽头 16B＋112B pad=128B；cap≥2,592,768B；slot_bytes 必须 4KiB 倍数
时限  : 主机 wait≤600000ms；FPGA 两笔间 Tx 等待超时≈0xFFFF 拍≈1.05ms
门铃  : 目标=phys+mb_off+32，单 DW（LastDWBE=0）
```

### 恢复：超时、取消与复位

- **失败处理纪律**：每次失败读 `0xC8`/`0x114` 记录错误码，再决定动作（rk-change-list §5）。
- **链路 down / PERST（复位）**：BAR 读回全 F → 需要**重新枚举**；`ANLOGIC_IOCLINKRETRIG` 提供重触发（评估 §4.9）。
- **不做自动重试**：超时不等于"重发就好"；先看错误码与状态，再走 CANCEL/重 ARM 的既定路径（rk-change-list §5 反例清单）。

## 硬件实现视角：谁负责哪一段

- **FPGA 侧**：推帧引擎（数据＋门铃）＋held/armed 状态机＋错误码；推帧走 TL 用户口最低优先权（第 21 章）。
- **驱动侧**：扩展探测（EXT_MAGIC/EXT_VERSION，**fail closed**：不匹配就不授权、只留采集/诊断）；授权配置（CAP/SESSION，**活动期拒改**）；one-shot ARM；严格解析后 ACK；`disarm` 先 CANCEL 再关模式位；PUSHCFG 限制在授权缓冲内（rk-change-list §1 #3/#5）。
- **ABI 纪律**：ioctl 旧编号/结构体**只增不改**；`hdr_bytes` 由 ioctl 返回（=128），用户态**必须用它**（rk-change-list §3）。
- **边界**：该驱动补丁**只做了离线 `git apply --check` 与静态复核**——**未编译、未安装、未加载**；编译依赖真实 RK3588 内核树与交叉工具链，必须由 RK 操作者提供（rk-change-list §4）。

## 与本项目方案的对应

| 结论 | 依据 |
|---|---|
| 授权式 DMA：主机给地址/容量，EP 不写死物理地址；越界置 OVERSIZE | `../../parallel/docs/帧与元数据接口合同_2026-10-15.md` §6 |
| one-shot：ARM→held→核验→ACK→再 ARM；不匹配 ACK 不释放 | `../../workflow/runs/20261017-011744-rk-fpga-align/backend/rk-change-list.md` §2 |
| CTRL 冻结 `0x61`（A）/`0x161`（B）；bit4 保留；RKA1 探针 fail closed | rk-change-list §1；decision-register M2e |
| CANCEL 不截半包、不发成功门铃、不加序号；清零后才可复用 | rk-change-list §2 |
| 槽头区 128B、R10F 从 +128B 开始、门铃在 mailbox 页 +32 | rk-change-list §1 #2/#5 |
| 完成可见性：Posted 顺序＋Normal-NC 直读；改 cacheable 须 dma_sync | 评估 §4.7/§5 R7（`../../workflow/runs/20261016_2110_pcie_unified_path/pcie-unified-path-assessment.md`） |
| 失败读 `0xC8`/`0x114`；PERST 后重枚举；IOCLINKRETRIG 重触发 | rk-change-list §5；评估 §4.9 |
| 补丁状态：离线 apply 通过、**未编译/未加载**；联调前确认 M2d/M2e 两项 | rk-change-list §4；decision-register M2d/M2e |
| **证据边界**：全部为合同/补丁/评估级；无 RK 环境编译、无联调、无长稳；"完成语义"尚未在真实链路上整帧验证 | rk-change-list §4；评估 §9 边界声明 |

## 决策点与判决框架

**决策点：缓冲消费模型选"自动连推＋定长覆盖"还是"one-shot 授权＋核验后释放"？**

| 选项 | 内容 | 代价/收益 |
|---|---|---|
| A. 自动连推＋定长覆盖（旧路径） | 写 CTRL 后连续推帧，新帧覆盖旧帧 | 实现简单；**慢消费者被覆盖、无核验机会**——旧行为已删 |
| B. one-shot 授权＋核验后释放（现行） | 一帧一授权；held 锁定；核验通过才 ACK | 每帧多几次寄存器交互；换来**所有权明确、错误可退、可背压**——**已选** |

- **权衡维度**：数据安全（覆盖风险）、核验机会、实现复杂度、吞吐（交互开销 vs 帧率预算 30fps/路，余量充足）。
- **当前选择**：**B**——T03 冻结合同（peer `2a4b253`/driver `a0215c5`）＋T07 rk-align-backend 补丁（`../../workflow/runs/20261017-011744-rk-fpga-align/closeout-T03-r0.md`；变更清单见 rk-change-list）。**判据在场**：默认不发、错 ACK 不释放、CANCEL 三不等。
- **何时应重开（改判触发）**：①长稳阶段需要更细的回收/多槽语义；②双路轮换语义落地（M2a：单引擎＋轮换为默认，第二引擎为优化候选）；③联调暴露背压影响帧率或门铃可见性问题。

## 常见误区

- **"CTRL 置了 push 位就会推帧"**：默认不发——push 位只是模式开关，必须 **ARM** 才会产生一帧传输（rk-change-list §2）。**正确做法**：把"ARM 成功"作为传输开始的可观察标志。
- **"ACK 发出去就释放了"**：必须匹配 held 的 (session, seq)；**错误 ACK 不覆盖 held 槽**。**正确做法**：ACK 前先读状态、带上正确序号。
- **"主机一直不 ACK 会死锁"**：这是**背压**——不再有帧进该槽，但链路/其他功能不受影响；恢复＝按规核验或 CANCEL。**正确做法**：把背压纳入最坏服务率预算。
- **"门铃就是中断"**：本项目无 MSI，门铃=内存写＋轮询；把轮询周期算进完成延迟。**正确做法**：延迟预算里显式包含轮询间隔。
- **"超时就重发"**：不得自动重试；先读 `0xC8`/`0x114` 分类（无目标/超时/AXI 错/无门铃），再走对应恢复路径。**正确做法**：每个错误码有明确的下一步。
- **"错误码是摆设"**：`0xC8` 的取值直接决定恢复路径；不读错误码的"重试"是盲试。**正确做法**：每次失败先记录 `0xC8` 错误码与 `0x114` 状态，再按对应动作处理（联调反例清单，rk-change-list §5）。

## 自测题

<details><summary>1. 写出 one-shot 完整五步（含核验）。</summary>

①configure(cap≥2,592,768B, session≠0) → ②ARM → ③等 held（0x114.bit2）→ ④严格解析（三层 CRC/长度/尾零/session）→ ⑤ack(seq=门铃值, session) → 再 ARM。依据 rk-change-list §5。
</details>

<details><summary>2. 为什么 FPGA 不写死物理地址、要先"授权"？</summary>

设备不知道主机内存布局；主机（内核 DMA API）才掌握合法缓冲。授权=给地址与容量，FPGA 校验越界即拒（OVERSIZE）——防止乱写主机内存（合同 §6）。
</details>

<details><summary>3. CANCEL 做哪三个"不"？什么时候才能复用内存？</summary>

不截半包、不发成功门铃、不加成功序号；等 busy/draining/held/armed 全清后才可释放/复用（rk-change-list §2）。
</details>

<details><summary>4. held 期间锁住源 DDR 块，好处是什么？代价是什么？</summary>

好处：慢消费不会覆盖未消费帧；代价：不 ACK 就不会有新帧（背压）——这是"用背压换安全"的明示选择（rk-change-list §2）。
</details>

<details><summary>5. `dst=phys+128` 修的什么问题？为什么是 128 而不是 4KiB？</summary>

修 4KiB 跨界规则（第 21 章）：槽像素区起点 128B 对齐后，128B 递增的 MWr 数学上不再跨 4KiB 边界；128B 同时满足 TLP 对齐与槽头区扩展（16B 结构体＋112B pad）（评估 §5 R1；rk-change-list §1）。
</details>

<details><summary>6. 错误码 `0xC8` 的四个非零值各对应什么动作起点？</summary>

1=无目标（检查 0xB0/0xB4 目标寄存器）、2=wait 超时（查链路/流控/对端就绪）、3=AXI 非 OKAY（查 DDR 侧读源）、4=无门铃（查门铃地址/写通道）。每次失败先读数再动作（评估 §4.9；rk-change-list §5）。
</details>

## 延伸资源

| 标题 | 类型 | 语言 | 体量 | 推荐理由 | 链接 | 核验状态 | 备用检索词 |
|---|---|---|---|---|---|---|---|
| Direct memory access（维基百科，英文） | 文档 | 英文 | 约 5 千字 | DMA 概念/通道/与 CPU 的关系，本章的通用底座 | [en.wikipedia](https://en.wikipedia.org/wiki/Direct_memory_access) | 在线核验通过 2026-10-17 | DMA 原理 图解 |
| Dynamic DMA mapping using the generic device（Linux 内核文档） | 文档 | 英文 | 长条目 | 权威对照：dma_addr/生命周期/同步 API 就是本项目"授权"的现实来源 | [docs.kernel.org](https://docs.kernel.org/core-api/dma-api.html) | 在线核验通过 2026-10-17 | Linux DMA API dma_sync |
| Memory barrier（维基百科，英文） | 文档 | 英文 | 约 5 千字 | 理解"完成可见性"为何依赖内存顺序与屏障 | [en.wikipedia](https://en.wikipedia.org/wiki/Memory_barrier) | 在线核验通过 2026-10-17 | 内存屏障 原理 |
| DMA（维基百科，中文，消歧义入口页） | 文档 | 中文 | 短 | 中文入口：经此进入"直接记忆体存取"等条目（落地为消歧义页，见核验说明） | [zh.wikipedia](https://zh.wikipedia.org/wiki/DMA) | 在线核验通过 2026-10-17（消歧义页） | 直接记忆体存取 维基 |

> 核验说明：4 条均以实际网络请求核验（2026-10-17）；其中 zh/DMA 落地为消歧义页（可正常访问，需再点入"直接内存访问"条目），已如实标注。首轮批量请求遇间歇网络错误，按"首次＋1 次有据重试"完成。全部记录见本 run `link-check-KB6.json`。B 站视频检索未返回可提取链接，未列视频行；检索词见"备用检索词"列。

## 术语增量

| 术语（中英） | 一句白话 | 首次出现章号 |
|---|---|---|
| 授权（authorization / ARM） | 主机允许 FPGA 向指定缓冲写入一帧的动作 | 22 |
| one-shot | 一次授权只完成一帧，释放后需重新授权 | 22 |
| held | 完成状态位：帧已放好且源缓冲被锁定 | 22 |
| ACK_RELEASE | 主机核验后"签收"并释放槽的动作（须匹配 session+seq） | 22 |
| CANCEL | 中止动作：不产生半包/成功标志，清零后方可复用 | 22 |
| 完成可见性（completion visibility） | 主机何时可以确定数据已可读 | 22 |
| 背压（backpressure） | 未签收则不再送新帧：慢消费的安全化处理 | 22 |
| 会话（session） | 一次联合启动的会话号，用于配对与防串扰 | 22 |
| RKA1 | 本项目对队友驱动的扩展组（探针/授权/one-shot/ACK/CANCEL） | 22 |

## 版本记录

| 版本 | 日期 | 变更 |
|---|---|---|
| 初稿 r0 | 2026-10-17 | KB6：以"授权→完成→释放"三段讲 one-shot 语义；冻结 CTRL 0x61/0x161、RKA1 探针、CANCEL 三不、错误码恢复；资源 4 条在线核验（1 条消歧义页注记）。 |
