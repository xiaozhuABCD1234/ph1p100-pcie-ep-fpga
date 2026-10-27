# fpga-design-guide.md — T10 A+ v1 设计冻结（本轮）

日期：2026-10-20｜run：`20261020-0209_singleA_aplus_closedloop`｜性质：规划冻结，未开发、未构建、未上板。
适用范围：本轮 4 个包（P1—P4）。冲突时以本文件冻结值为准；未列项沿用上游现有工程约定。

## 0. 本轮唯一候选与边界

- **候选**：`T10.a1-*` 纯新增 codec 源码集（上游受控写树内新目录），**不是** B01 生产候选，**不是** T11 冻结输入。
- **不重写/不接入**：三算法、相机/CSI、DDR writer、pusher、PCIe、RK。生产 B01 候选 `b68c6e18…f9bf` 只读，不被覆盖。
- **不分配** T03 生产枚举、不改 `R10F` 合同、不改 `docs/protocol/**`。本轮外层测试记录头（§7）明确为 **test-only / non-production**。
- **不宣称**：真实 Bayer 相位、真实图集压缩率、单A 实际链路、双路 155.52 MB/s、G3/G4。

## 1. 输入契约（冻结）

### 1.1 像素与打包
- 输入为 **packed RAW10，5 B / 4 px**，与 `csi_rx_10bit_unpack.v`、`cam_r10f_writer.v` 合同一致：
  - `b0=P0[9:2]`，`b1=P1[9:2]`，`b2=P2[9:2]`，`b3=P3[9:2]`，
  - `b4={P3[1:0],P2[1:0],P1[1:0],P0[1:0]}`（`b4[1:0]=P0` 低位，依此类推）。
- 码流接口按 **40 bit/拍 = 1 个 4px 组**（`{b4,b3,b2,b1,b0}` 由低到高或等价字段），`valid/ready` 反压。
- 目标几何：`W=1920, H=1080`，`W%4==0`；`stride_bytes=W*5/4=2400`；帧长 `2,592,000 B`。参数化支持 `W%4==0`、任意 `H` 的测试小帧；`W%4!=0` 或 `H<2` 属非法输入（测试负例）。

### 1.2 Bayer 约定（声明值，非物理实测）
- 假定图案 **RGGB，phase=0 于 ROI 原点**；物理相位仍为 **unknown**（2117 T02 未取得直接证据）。所有 A/B 结论仅对“声明相位”的合成向量成立。
- 2×2 四元组：`R=(even x, even y)`，`G1=(odd x, even y)`，`G2=(even x, odd y)`，`B=(odd x, odd y)`。
- **相位重排（每 2 行对）**：输出 4 个平面，顺序 `R, G1, G2, B`；每平面 `W/2` 个样本，拼接后总样本数不变。逆变换按同一映射写回。
- **可选同色预测**：对每个平面按扫描顺序做 `d[i]=(s[i]-s[i-1]) mod 1024`，`s[-1]=0`；逆变换为模 1024 累加。A/B 开关：`prep_en`（0=直通，1=重排）、`pred_en`（仅 `prep_en=1` 有效）。
- **逆变换后**才计算原始图像 CRC；`stored` 块保存的是**变换域字节**，不是原始字节。

## 2. 标准流与块（冻结）

- **唯一外层包装：zlib（RFC1950）单成员**。`CMF=0x78`、`FLG=0x9C`（`FLEVEL=2`、`FDICT=0`、FCHECK 合法）、尾部 Adler-32（对**变换域**全部字节，big-endian 写入）。
- **DEFLATE 子集**：`BTYPE=01`（fixed Huffman）与 `BTYPE=00`（stored）；**不做 dynamic（BTYPE=10）**。literal 与真实 match 必须并存；纯 literal 不得称已实现 LZ77。
- **块粒度：1 个 DEFLATE block = 1 个 2 行对**（目标几何 `4,800 B`；`H` 为奇数时尾块 `2,400 B`；不跨块引用）。
  - 选此粒度的理由：与 Bayer 2 行对缓冲天然对齐；块缓存/候选缓存可落在现有 ERAM 余量内（见 §6）；stored 回退边界清晰。
  - 每块 `BFINAL=0`，最后一拍 `BFINAL=1`；zlib 尾 Adler 在最后一个 DEFLATE block 结束后按字节对齐写入。
- **块级 stored 回退**：同一块先生成 fixed-Huffman 候选；若候选位数 ≥ stored 位数（含对齐成本），改发 stored。`LEN` 为块实际字节数（≤4,800），`NLEN=~LEN`；stored 头按 RFC1951 对齐规则补齐到下一字节边界。
- **LZ77 参数**：窗口 **2,048 B**（块内），`distance=1..2048`，`length=3..258`，greedy 最长匹配；3 字节 hash 表（≥1024 项）+ 单候选链；每块开始清历史。允许“未找到匹配就发 literal”。
- **最坏膨胀**：每块最多 `原长+5 B`（stored）。1080p 为 540 块（2 行/块），理论最坏 `2,592,000+540×5+6(zlib)=2,594,706 B`（+0.1044%），不含外层测试记录头；P3 r1 已用全 stored 合成帧逐字节命中该上界，但仍只对合成输入成立。

## 3. 长度与 CRC 域（冻结，分别命名）

| 名称 | 覆盖 | 产生方 |
|---|---|---|
| `raw_len` / `raw_crc32` | 原始 packed RAW10 字节（2,592,000 B） | 帧级 top |
| `xform_len` / `xform_crc32` | Bayer 变换域字节（与 raw 等长） | 帧级 top |
| `stream_len` / `stream_crc32` | 精确 zlib 字节流（含 2B 头 + Adler 4B） | 帧级 top |
| `zlib_adler32` | 变换域字节，RFC1950 定义 | 编码器尾 |
| `block_count` | 已完成的 2 行块数（1080p=540） | 帧级 top |

- CRC32：IEEE reflected poly `0xEDB88320`，init/final 取反，与 `crc32_upd4.v` / `r10f_strict.py` 口径一致。
- `stream_len` 必须精确到字节；独立解码器必须 **恰好消费** `stream_len` 且无尾随字节（`unused_data` 为空）。

## 4. 数据流与时序

```
40bit(4px) -> [帧级 top] -> Bayer 2行对缓冲(4,800B)
            -> 重排/可选预测 -> 变换域块(4,800B)
            -> LZ77 候选 -> fixed-Huffman 位打包(候选<=5,404B) / stored 比较
            -> zlib 流输出(valid/ready) + 长度/CRC 计数
```

- 目标时钟 **187.5 MHz**（与 T09 同域）；输入服务率门槛见 §6。
- 反压：输入 `ready` 可被块缓冲/编码器拉低；输出 `ready` 由下游决定；不得丢样本、不得重复计数。
- 复位：同步复位优先（`rst_n`），复位清块内状态、位打包器、CRC、块计数；**不产生半帧成功标志**。
- `abort`：立即终止当前帧，清未完成块；输出侧仅以 `frame_commit=0` 结束，`eop` 不得置位；下一次 `sof` 前不得复用旧块。

## 5. 接口（小顶，冻结语义）

- 输入：`in_pix[39:0]`, `in_valid`, `in_ready`, `in_sof`；`in_pix` 为 §1.1 的 5B 组。
- 配置：`prep_en`, `pred_en`, `abort`（每帧仅 sof 时采样，运行中 abort 例外立即生效）。
- 输出：`out_data[31:0]`, `out_valid`, `out_ready`, `out_keep[3:0]`, `out_last`（仅帧最后一字节），`frame_commit`（整帧成功时最后一拍置 1），`frame_abort`（失败/中止置 1）。
- 状态（测试/后续集成观察，不分配生产枚举）：`st_raw_len`, `st_xform_len`, `st_stream_len`, `st_raw_crc`, `st_xform_crc`, `st_stream_crc`, `st_blocks`, `st_stall_cycles`, `st_busy`。
- 输出字节序：zlib 流按生成顺序，32-bit 字内低字节先出（`keep` 标有效字节）；最后字允许部分有效。

## 6. 工程预算（冻结）

- 器件 `PH1P100SBG484 -3`；现有生产资源参考 LUT 28,349/71,680、ERAM 200/300、DSP 14/220（B01 r0 报告），本轮只做 codec 小顶，不声称整机余量。
- 本轮 codec 预算估计（规划值，以 G2 实测替换）：块输入 4,800 B + 候选 5,404 B + 2 行对缓冲 ~4,800 B ≈ 15 KB ≈ 30 ERAM；LUT 估计 +6k~10k。若 G2 超器件或时序不收敛，按 §8 停止，不靠删门槛过关。
- **TD 构建预算：最多 3 次会话**（首次 + 最多 2 次有新增证据的纠正），每次 ≤30 min，总 ≤90 min；**生产集成构建 0 次**；**下载 0 次**。每次会话必须记录命令、退出码、日志、`final_timing.rpt` Confidence。
- G2 门槛：`exit=0`、`Routed`、SWNS/STNS/HWNS≥0（记数值）、0 违例、资源在器件内、无宽泛 false path。
- 服务率：仿真统计**持续接受输入字节/周期**，换算 187.5 MHz 下 MB/s；门槛单A `≥77.76 MB/s`，余量目标 `97.2 MB/s`；双路 `155.52 MB/s` 只记录差距。

## 7. 测试记录头（test-only，非生产合同）

用于 TB/主机把“流 + 长度 + CRC + 开关”绑定为一个可复核样本，共 32 B 小端：

| 偏移 | 字段 |
|---:|---|
| 0x00 | magic `A1T1` |
| 0x04 | version=1, flags[0]=prep_en, flags[1]=pred_en |
| 0x08 | raw_len |
| 0x0C | xform_len |
| 0x10 | stream_len |
| 0x14 | raw_crc32 |
| 0x18 | xform_crc32 |
| 0x1C | header_crc32（0x00..0x1B，计算时本字段置 0） |

- 该头**不得**写入生产 R10F/DMA 路径，不占 T03 枚举；后续由 T03/T11 合同替换。
- 负例：截断（少 1..N 字节）、坏 `stream_len`、坏 raw/xform CRC、非零尾随字节、坏 stored `NLEN`、非法 `BTYPE=10`，独立解码器必须拒绝并给稳定 reason code。

## 8. 停止 / 回退条件

- P1 若无法在“独立解码器 + 自研解析器”两层都通过，停止后续包，保留格式草案与负例，交规划。
- P2 若 DUT 输出不能被 zlib 与自研解析器**同时**解开（0 mismatch），不得进入 P3；禁止用“同一宽松解析器两层调用”凑独立。
- P3 若任一块出现半帧 `eop/commit`、反压丢样、或 A/B 任一模式 mismatch，停止并保留失败向量。
- P4 若 3 次 TD 会话后仍非 Routed / WNS<0 / 超资源，或吞吐 <77.76 MB/s，判 **FAIL/blocked**，保留测量与日志；不得改门槛、不得用理论带宽替代。
- 回退：删除本轮新增 codec 目录与 run 产物即可（不批量删、不动旧候选/旧 run）；生产 B01 bit 不受影响。

## 9. 不适用 / 后置

- G3 上板、G4 长稳/热态、C（Rice/逐块 DEFLATE）、真实双路、PCIe/RK、Flash、发布材料：本轮 **N/A 或后置**，不因本文件通过而变成完成。
- 真实 RAW 样例与物理 Bayer 相位：**blocked/awaiting_hardware**（无导出路径、无板窗、无用户在场）；本轮只用合成向量，报告必须标注 `synthetic`。
