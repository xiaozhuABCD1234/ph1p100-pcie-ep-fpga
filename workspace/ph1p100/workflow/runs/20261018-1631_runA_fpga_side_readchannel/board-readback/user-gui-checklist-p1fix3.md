# user-gui-checklist-p1fix3.md — 现场用户操作清单（新候选 P1-fix3；只点两次 Instant Trigger）

> 本清单替代旧版 `user-gui-checklist.md`（旧版对应 bit `2385cded…`/CWC `fa24e258…`，已作废）。
> 新位流**已经由我们以 SRAM 方式下载到板上**（2026-10-19 00:41:42，`PRG-2014`、rc=0、28.36 s，仅 SRAM、未写 Flash）。
> 你只需：打开新 CWC → Watch → 点两次 **Instant Trigger**（间隔 ≥10 秒）→ 把 9 个数字原样发回。

## 0. 前置确认（不用动手）

- 板保持上电，**不要断电**（断电会清掉 SRAM 位流，需要重新下载）。
- TD 可以保持打开；若 ChipWatcher 还是旧的旧工程窗口，建议**关掉旧 ChipWatcher 窗口重开**（避免旧 CWC 混淆）。

## 1. 打开新 CWC（唯一正确的文件，别用旧的）

1. TD → **Tools → ChipWatcher**（或 Flow 栏 ChipWatcher 图标）。
2. 打开 CWC：
   `D:\anlogic\runa_p3\p1fix3_20261019_004115\compiled.cwc`
   （SHA256 `8D2998B96EF1763C14A1302118235A687488297CE496692B1F6CD95D76981026`，81,063 B）
3. 确认 **Bit File** 指向同目录：
   `D:\anlogic\runa_p3\p1fix3_20261019_004115\compiled.bit`
   （SHA256 `BFAFDF97FF78D6F6D2646FFC706542A0BBBB7E11869043BA754CF68A270813D0`，5,224,027 B）
   - 若 TD 询问是否下载位流：**允许**（必须是上面这个文件）；**绝不要**勾选/选择任何 Flash/Program Flash/efuse/SPI 选项；若弹写 Flash 提示 → 取消。
   - 若提示 `code mismatch` 或路径无效：**停**，截图/抄下原文发回，不要换文件。
4. 点 **Watch**；实例选 **`auto_created_cwc1`**。

## 2. 加入 9 个信号（应与上次相同）

5. **Add Signals** → 展开实例，勾选 9 个 32-bit 字（名字可能是 `dbg_bank_word0..8`，显示为 `dbg_mark$dbg_mark_word0[31:0]` … `word8[31:0]`）。
6. 触发条件留空；采样方式 **Instant Trigger**。

## 3. 只点两次 Instant Trigger（间隔 ≥10 秒）

7. 第 1 次点 **Instant Trigger**，等波形/数值出现；Value 列切 **Hex**，抄下 9 个 8 位十六进制值；记下时间（时:分:秒）。
8. **等 ≥10 秒**（看表，例如 00:50:10 → 00:50:25）再点第 2 次 **Instant Trigger**，同样抄 9 个值 + 时间。
9. 若出现 `Idle`、`Triggered: 0`、无波形：最多**再点 1 次** Instant Trigger；仍无 → 停，把界面原文发回，不要改设置、不要重烧。

## 4. 期望值（自检用；不符也请原样发回，不要估算）

| 字 | 期望 | 说明 |
|---|---|---|
| word0 | `50434946` | "FICP" 身份字（常量） |
| word1 | `31414B52` | "RKA1" |
| word2 | `00010000` | v1.0 |
| word3 | 任意（可能 `00000000`） | DDR 序号（无主机时可能静止，如实记录） |
| word4 | 任意 | DDR 基址（可能 0） |
| word5 | 任意（可能 `00000000`） | DDR 长度（可能 0） |
| word6 | 任意 | CSI 计数（可能 0） |
| word7 | 任意 | CSI 状态（可能 0） |
| word8 | **`00000021`** | CTRL 读回（bit0=1 使能、bit5=1 DDR 使能；bit6/7 应为 0） |

> 只要 word0/word1/word2 命中，就说明读通道修好了；word3–7 有 0 是正常的（没有 PCIe 主机时这些计数本就不动）。

## 5. 回报格式（照抄，勿换算/勿推断）

```
样本1 时间=HH:MM:SS
word0=0x________ word1=0x________ word2=0x________
word3=0x________ word4=0x________ word5=0x________
word6=0x________ word7=0x________ word8=0x________
样本2 时间=HH:MM:SS
word0=0x________ ... word8=0x________
界面异常原文：（如有，原样贴）
```

回报后保持板通电即可；如需恢复原状：断电 10 秒再上电（清除 SRAM），或由我们在后续轮重下旧位流（无 Flash 写入）。

## 6. 追加：一次"带时间"的重采（必要，最后一次）

上一轮的两组读数缺少触发时间，无法确认"间隔 ≥10 秒"，按冻结规则需要**再采一次有界样本**（最多两步）：

1. 在 ChipWatcher（实例 `auto_created_cwc1`、9 个信号已在）点一次 **Instant Trigger**，**在纸上/截图记下时间（时:分:秒）**，并抄下 9 个 Hex 值；
2. **等 ≥10 秒**（看表）再点一次 **Instant Trigger**，同样记时间、抄 9 个值；把两组（18 个值 + 2 个时间）一起发回。

预期与上次相同（`50434946 / 31414B52 / 00010000 / … / 00000021`）。若两次值不一致，也请原样发回，不要重试多次；其余设置不要改动。
