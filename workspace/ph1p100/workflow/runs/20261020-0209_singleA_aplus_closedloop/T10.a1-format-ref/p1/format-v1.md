# A+ v1 format freeze (`T10.a1-format-ref`)

状态：**P1 冻结草案，已由本任务参考实现与向量实现验证；test-only，不是生产合同。**
日期：2026-10-20｜run：`20261020-0209_singleA_aplus_closedloop`｜上位冻结：`fpga-design-guide.md` §1–§3、§7。
本文件只补全 guide 未写明、但 P2/P3 必须逐位一致的细节；与 guide 冲突处列出勘误，不静默改值。

## 0. 范围与非声明

- 本格式是 `T10.a1-*` 纯新增 codec 的**测试格式**，不分配 T03 生产枚举，不写入 R10F/DMA 生产路径。
- 所有 P1 向量是 **synthetic**。Bayer 图案/相位是**声明值**，不是物理实测；真实 RAW、真实压缩率、真实 ROI/相位仍 `unknown`/`blocked_awaiting_hardware`。
- 本文件不声称 RTL 已实现、不声称 G2/吞吐、不声称板上行为。

## 1. 输入契约（与 guide §1.1 一致）

- 像素：packed RAW10，5 B / 4 px。
  - `b0=P0[9:2]`、`b1=P1[9:2]`、`b2=P2[9:2]`、`b3=P3[9:2]`
  - `b4[1:0]=P0[1:0]`、`b4[3:2]=P1[1:0]`、`b4[5:4]=P2[1:0]`、`b4[7:6]=P3[1:0]`
- 帧几何：`W%4==0`、`H>=2`；`stride_bytes=W*5/4`；`raw_len=stride_bytes*H`。
- 目标几何 `W=1920,H=1080`：`stride=2400`、`raw_len=2,592,000`、`block_count=540`（见 §4 勘误）。
- 非法输入（负例，编码器必须拒绝）：`W%4!=0`、`H<2`、`len(raw)!=stride*H`、`pred_en=1 && prep_en=0`。
- 码流接口（供 P2/P3）：40 bit/拍 = 1 个 4px 组；`valid/ready` 反压；不得丢样或重复计数。

## 2. Bayer 变换（声明 RGGB phase=0）

### 2.1 2×2 四元组

对 ROI 原点 `(0,0)`：

| 平面 | 取样位置 | 2 行对内样本数 |
|---|---|---:|
| R | even x, even y | W/2 |
| G1 | odd x, even y | W/2 |
| G2 | even x, odd y | W/2 |
| B | odd x, odd y | W/2 |

- 平面顺序固定 `R, G1, G2, B`。
- **奇数 H 的尾块**只有 1 行（该行是 even y，因为块从 y=0 起每 2 行切分）：只含 `R, G1` 两个平面，各 W/2 样本，共 W 样本 → `stride_bytes` 字节。不得补造 G2/B，也不得把尾行当 odd row。
- `prep_en=0`：变换域字节 = 原始 packed 字节（逐字节直通）；`pred_en` 必须为 0。

### 2.2 预测（仅 `prep_en=1` 且 `pred_en=1`）

- 对每个平面、**每个 2 行块内**按扫描顺序（平面内 x 递增）做：
  `d[i] = (s[i] - s[i-1]) mod 1024`，`s[-1]=0`。
- 预测器在**每个块、每个平面**起点重置为 0；不跨块、不跨平面。
- 逆变换：`s[i] = (s[i-1] + d[i]) mod 1024`，同样每块每平面从 0 开始。
- 尾块只有 R/G1 两个平面，各自重置。

### 2.3 变换域字节打包（guide 未写明，本文件冻结）

- 将 2 行块内的平面样本按 `R, G1, G2, B` 顺序**首尾拼接**为一个连续样本序列（尾块为 `R, G1`）。
- 该连续序列按 §1 的 **5 B / 4 px** 规则重新打包；4 样本组可以跨平面边界，但**不得跨块边界**。
- 长度不变：2 行块 `2W` 样本 → `2W/4*5 = W*2.5 = 2*stride` 字节；尾块 `W` 样本 → `stride` 字节。因此 `xform_len == raw_len` 恒成立。
- `stored` 块保存的是变换域字节；逆变换在解码后、CRC 校验前执行。
- 参考实现：`tools/codec/a1_ref.py` 的 `bayer_forward_block` / `bayer_inverse_block`。

## 3. 外层包装与 DEFLATE 子集

- 唯一外层：**zlib（RFC1950）单成员**。
- 头固定 `CMF=0x78`、`FLG=0x9C`（`FLEVEL=2`、`FDICT=0`、`FCHECK=28`；`(0x78<<8|0x9C)%31==0`）。
- 尾：Adler-32（对**变换域全部字节**，big-endian 4 B）。
- DEFLATE 只允许：
  - `BTYPE=00` stored；
  - `BTYPE=01` fixed Huffman；
  - `BTYPE=10` dynamic **不支持**，严格解析器以 `E_BAD_BTYPE_DYNAMIC` 拒绝；
  - `BTYPE=11` 保留，`E_BAD_BTYPE_RESERVED`。
- fixed 码表使用 RFC1951 §3.2.6 标准表；literal/length 与 distance 码均按标准 canonical 码，Huffman 码 MSB-first 写入 LSB-first 位流。
- length/distance 表使用 RFC1951 标准表；distance 限制 `1..2048`，length 限制 `3..258`。
- `BFINAL=1` 只允许出现在最后一块；最后一块结束后，位流补齐到字节边界，**补位必须为 0**（`E_BAD_PADDING`），随后写 4 B Adler，流必须在此结束（无尾随字节）。
- 每个块至少产生 1 个 literal 或 match，再以 `EOB(256)` 结束；空块不作为本格式的合法块（stored `LEN=0` 允许解析但不用于本编码器）。

## 4. 块粒度、LZ77 与 stored 回退

- **1 个 DEFLATE block = 1 个 2 行对**：
  - 正常块 `2*stride = 4,800 B`（1920 宽）；
  - `H` 为奇数时最后一块 `stride = 2,400 B`；
  - 不跨块引用历史，块开始清 hash/窗口。
- LZ77（编码器）：
  - 窗口 **2,048 B（块内）**；`distance=1..2048`；
  - `length=3..258`，greedy 最长匹配；
  - 3 字节 hash 表 ≥1024 项（参考实现 4096 项）+ 单候选；匹配不得越过当前块边界；
  - 允许找不到匹配就发 literal；**纯 literal 流不声称实现了 LZ77**（判定看实际 match 计数）。
- **stored 回退判定**（逐块）：
  1. 先生成 fixed-Huffman 候选（含 3 bit 块头与 EOB）；
  2. 计算 stored 成本：`3 + pad_to_byte + 32 + 8*block_bytes`，其中 `pad_to_byte` 取决于该块起始时位流的 bit 偏移；
  3. 若 `fixed_bits >= stored_bits`，发 stored，否则发 fixed；
  4. stored 的 `LEN` 为块实际字节数（≤4,800），`NLEN=~LEN & 0xFFFF`；块头后按 RFC1951 对齐，`BFINAL` 保持在块头。
- 最坏膨胀（1080p）：
  - 540 块 × 5 B 块开销 + 2 B zlib 头 + 4 B Adler = **2,594,706 B**；
  - 相对 2,592,000 B 为 **+2,706 B（+0.1044%）**；
  - 该值是容量上界，不是实测压缩率；不含 test-only 记录头。

### 4.1 勘误（与 guide §2 的算术冲突）

`fpga-design-guide.md` §2 写“1080p 270 块，理论最坏 2,592,000+1,350+6=2,593,356 B”，但同一文件 §2 又规定“1 block = 1 个 2 行对”，§3 写“block_count（1080p=540）”。1080/2=540，故：

- **冻结：540 块**；
- **冻结最坏 stored 长度：2,594,706 B**；
- guide §2 的 `270`/`1,350`/`2,593,356` 是算术笔误，P4 容量检查不得引用该值。
- 该差异为 1,350 B（0.0521% of raw），不改变“每块最多原长+5 B”的块级上界。

## 5. 长度与 CRC 域

| 名称 | 覆盖 | 宽度 | 产生方 |
|---|---|---:|---|
| `raw_len` | 原始 packed RAW10 字节数 | 32 | 帧级 top |
| `raw_crc32` | 原始 packed RAW10 字节 | 32 | 帧级 top |
| `xform_len` | Bayer 变换域字节数（恒等于 raw_len） | 32 | 帧级 top |
| `xform_crc32` | 变换域字节 | 32 | 帧级 top |
| `stream_len` | 精确 zlib 字节流长度（含 2 B 头 + 4 B Adler） | 32 | 帧级 top |
| `stream_crc32` | 精确 zlib 字节流 | 32 | 帧级 top（**不在 32 B 测试头内**，见 §6） |
| `zlib_adler32` | 变换域字节 | 32 | 编码器尾 |
| `block_count` | 完成的 2 行块数（1080p=540） | 32 | 帧级 top |

- CRC32：IEEE reflected `0xEDB88320`，init/final 取反，与 `r10f_strict.py` / `crc32_upd4.v` 口径一致。
- `stream_len` 必须精确；独立解码器必须恰好消费 `stream_len` 字节，`unused_data` 为空。
- **`stream_crc32` 缺口（诚实记录）**：guide §7 的 32 B 测试头没有 `stream_crc32` 字段（32 B 已排满），也没有 W/H。P1 不擅自扩头；P4 的样例导出契约必须把 `stream_crc32`、W/H、`prep_en/pred_en` 放在记录外的元数据中。P1 的完整性由 zlib/严格解析器 + Adler + raw/xform CRC 覆盖。

## 6. Test-only 32 B 记录头（`A1T1` v1）

小端，紧接 zlib 流：

| 偏移 | 字段 | 类型/值 |
|---:|---|---|
| 0x00 | magic | `A1T1` |
| 0x04 | version | u16 = 1 |
| 0x06 | flags | u16：bit0=`prep_en`，bit1=`pred_en`，bit2..15 保留必须 0 |
| 0x08 | raw_len | u32 |
| 0x0C | xform_len | u32 |
| 0x10 | stream_len | u32 |
| 0x14 | raw_crc32 | u32 |
| 0x18 | xform_crc32 | u32 |
| 0x1C | header_crc32 | u32 |

- **header CRC 覆盖范围冻结为 `[0x00,0x1C)` 共 28 B**；`0x1C..0x1F` 字段本身不参与计算。guide 的括注“计算时本字段置 0”按“该字段不参与/视为不存在”解释（该字段不在所列范围内，置 0 不影响 28 B 结果）。这是一处措辞歧义，不是数据冲突。
- 记录后必须恰好是 `stream_len` 字节；多/少都是负例（`E_STREAM_LEN_MISMATCH`）。
- 该头**不得**进入生产 R10F/DMA 路径，不占 T03 枚举。

## 7. 严格解析器规则与稳定 reason code

`tools/codec/a1_inflate_strict.py` 不调用 zlib、不调用 `a1_ref.py` 的编码/解析核心；只解析 zlib 头、stored/fixed、Adler、尾随与长度。reason code：

| code | 触发 |
|---|---|
| `E_TRUNCATED` | 位/字节不足 |
| `E_BAD_ZLIB_HEADER` | CM/CMF 非法、FCHECK 失败 |
| `E_FDICT_SET` | FDICT=1（本格式禁止） |
| `E_BAD_BTYPE_DYNAMIC` | BTYPE=10（子集不支持） |
| `E_BAD_BTYPE_RESERVED` | BTYPE=11 |
| `E_BAD_STORED_NLEN` | `LEN ^ 0xFFFF != NLEN` |
| `E_BAD_STORED_LEN` | stored `LEN>4800` |
| `E_BAD_PADDING` | 块头/流尾补位非 0 |
| `E_INVALID_HUFFMAN_CODE` | fixed 码无匹配 |
| `E_BAD_LENGTH_CODE` | 符号 286/287 |
| `E_BAD_DISTANCE_CODE` | distance 符号 30/31 |
| `E_BAD_DISTANCE` | distance > 当前输出长度 |
| `E_DISTANCE_WINDOW` | distance > 2048 |
| `E_BAD_ADLER` | Adler 不匹配 |
| `E_LENGTH_MISMATCH` | 解码长度 != 期望 `xform_len` |
| `E_TRAILING_BYTES` | Adler 后仍有字节 |
| `E_OUTPUT_LIMIT` | 输出超过解析器上限 |

记录层（`tools/codec/a1_sample_check.py`）：

| code | 触发 |
|---|---|
| `E_RECORD_TRUNCATED` | 记录 <32 B |
| `E_BAD_MAGIC` / `E_BAD_VERSION` / `E_BAD_FLAGS` | 头字段非法 |
| `E_BAD_HEADER_CRC` | 头 CRC 不符 |
| `E_STREAM_LEN_MISMATCH` | 记录总长 != 32+`stream_len` |
| `E_BAD_RAW_LEN` / `E_BAD_XFORM_LEN` | 长度与 W/H 或彼此不符 |
| `E_BAD_XFORM_CRC` / `E_BAD_RAW_CRC` | 变换域/原始 CRC 不符 |
| `E_BAD_GEOMETRY` | W/H 非法或 prep 几何不支持 |

## 8. 参考实现与独立性

三层，互不复用解析核心：

1. **编码模型** `tools/codec/a1_ref.py`：packed RAW10 ↔ 样本、Bayer 正/逆变换、LZ77 + fixed Huffman + stored 选择、zlib 封装、32 B 记录生成。不调用 zlib 做压缩。
2. **独立严格解析器** `tools/codec/a1_inflate_strict.py`：自实现 zlib/DEFLATE 子集解析与 Adler；不 import `a1_ref`，不调用 zlib。
3. **第三方标准解码器**：Python `zlib`（1.2.13），用 `decompressobj` 并要求 `eof=True`、`unused_data==b''`、`unconsumed_tail==b''`。

`tools/codec/a1_sample_check.py` 负责记录层校验，内部使用 (2) 解析、(1) 逆变换；zlib 仍由验证脚本独立调用。验证脚本 `tools/codec/a1_p1_verify.py` 要求三者输出逐字节一致、raw 逐字节回环。

## 9. P2/P3 交接要点

- P2 的 RTL 输出必须是本文件的 zlib 流；**不要求与参考编码器逐字节相同**（匹配搜索可不同），但必须能被 zlib 与严格解析器同时解开，且满足块粒度、位序、stored 规则、补零、无尾随。
- P3 的帧级 top 必须输出 `raw_len/xform_len/stream_len/raw_crc/xform_crc/stream_crc/block_count`，其中 1080p `block_count=540`；`out_last` 仅最后一字节，`frame_commit` 仅在整帧成功最后一拍。
- `prep_en=0` 必须逐字节直通；`pred_en=1` 仅在 `prep_en=1` 时合法。
- 奇数 H 尾块按 §2.1/§2.3 的单行处理，不得补成两行。
- 容量上界用 §4 的 **2,594,706 B**，不用 guide §2 的 2,593,356 B。

## 10. 已知歧义/勘误清单

1. guide §2 `270 块 / 1,350 B / 2,593,356 B` ↔ §2 块定义与 §3 `540`：冻结 540 / 2,594,706 B。
2. guide §7 header CRC 范围与“字段置 0”措辞：冻结覆盖 `[0x00,0x1C)`；字段自身不参与。
3. guide 未指定变换域样本的字节打包：冻结为“平面拼接后的连续 4 样本组、5 B/4 px”，组可跨平面、不跨块。
4. guide 未指定预测器跨块行为：冻结为每块每平面重置 `s[-1]=0`。
5. 测试头无 W/H 与 `stream_crc32`：P1 不扩头；P4 导出契约必须在记录外携带。
6. input profile 中 2192 vs 2160+37 的 5 行差异仍为 `conflict`，与本格式无关，不猜。
7. 物理 Bayer 相位/ROI 仍 `unknown`；本格式的 RGGB phase=0 仅为声明值。
