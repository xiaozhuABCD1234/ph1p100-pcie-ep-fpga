# P1 result — `T10.a1-format-ref`

判定：**P1 PASS（软件/格式层）**。范围仅限 P1：输入 profile、A+ v1 格式冻结、独立参考/严格解析、合成向量正负例。**不含 RTL、G2、吞吐、真实 RAW、板上行为。**

- 日期：2026-10-20
- run：`20261020-0209_singleA_aplus_closedloop`
- 候选：`T10.a1-*` 纯新增 codec 源码集（test-only，非生产候选）
- 最终命令与退出码：
  - `python a1_vectors.py --out <task>/p1/vectors` → **exit 0**，日志 `p1/logs/run-vectors.log`
  - `python a1_p1_verify.py --vectors <task>/p1/vectors --report <task>/p1/verify-report.json` → **exit 0**，日志 `p1/logs/run-verify.log`
- 机器可读结果：`p1/verify-report.json`；向量索引：`p1/vectors/vectors.json`；冻结清单：`../CANDIDATE-MANIFEST.json`

## 1. 核心结果

`ROUNDTRIP_PASS mismatch=0 positives=9 negatives=17 three_way=9`

- 9 个正例全部通过；**raw 逐字节回环 mismatch=0**。
- 9/9 同时由三层得到一致的变换域字节：
  1. 编码模型 `a1_ref.py`；
  2. 独立严格解析器 `a1_inflate_strict.py`（不 import `a1_ref`、不调用 zlib）；
  3. Python `zlib` 1.2.13（标准解码器，要求 `eof=True`、`unused_data==b''`、`unconsumed_tail==b''`）。
- 17 个负例全部按预期稳定 reason code 拒绝；流级负例同时被 zlib 拒绝（尾随字节例外：zlib 解出内容但 `unused_data` 非空）。
- 1080p 随机不可压缩帧的码流长度 = **2,594,706 B**，与冻结最坏上界逐字节一致；540 块全部走 stored。
- 1080p 纹理帧 540 块全部走 fixed，`block_count=540`，`BFINAL` 只在最后一块，尾 bit 偏移 5。

## 2. 正例明细

| 向量 | W×H | prep/pred | raw B | stream B | ratio raw/stream | blocks (fixed/stored) | tail bit | max len/dist |
|---|---|---:|---:|---:|---:|---|---:|---|
| `p_8x4_flat_prep0_pred0` | 8×4 | 0/0 | 40 | 22 | 1.8182 | 2 (2/0) | 0 | 12/5 |
| `p_8x4_grad_prep1_pred0` | 8×4 | 1/0 | 40 | 47 | 0.8511 | 2 (2/0) | 2 | 3/9 |
| `p_8x4_grad_prep1_pred1` | 8×4 | 1/1 | 40 | 42 | 0.9524 | 2 (2/0) | 1 | 3/5 |
| `p_1920x4_repeat_prep0_pred0` | 1920×4 | 0/0 | 9,600 | 128 | 75.0000 | 2 (2/0) | 2 | 258/20 |
| `p_1920x4_repeat_prep1_pred1` | 1920×4 | 1/1 | 9,600 | 170 | 56.4706 | 2 (2/0) | 0 | 258/1220 |
| `p_32x5_tail_prep1_pred1` | 32×5 | 1/1 | 200 | 101 | 1.9802 | 3 (3/0) | 4 | 16/60 |
| `p_1920x1080_texture_prep1_pred1` | 1920×1080 | 1/1 | 2,592,000 | 101,566 | 25.5204 | 540 (540/0) | 5 | 258/2000 |
| `p_1920x1080_random_prep0_pred0` | 1920×1080 | 0/0 | 2,592,000 | 2,594,706 | 0.9990 | 540 (0/540) | 0 | 3/2025 |
| `p_tokens_boundary` | stream-only | — | out 2,319 | — | — | 1 fixed | 2 | 258/2048 |

- `p_tokens_boundary`：2,048 个 literal + 3 个显式 match，覆盖 `length=3/258`、`distance=1/2048`、非字节对齐尾；zlib 与严格解析器输出逐字节一致。
- `p_32x5_tail_prep1_pred1`：H=5 的尾块为单行（R,G1），3 块长度 80/80/40 B，证明尾块不补成两行。
- 所有向量的 `raw_crc32`、`xform_crc32`、`stream_crc32`、文件 SHA256 均在 `p1/vectors/vectors.json`；manifest 逐文件复算。

## 3. 负例明细（17/17 拒绝）

| 类别 | 负例 | 期望/实际 reason |
|---|---|---|
| 流截断 | `n_trunc_last_byte`, `n_trunc_mid` | `E_TRUNCATED`（zlib: incomplete） |
| 坏 Adler | `n_bad_adler` | `E_BAD_ADLER`（zlib: error） |
| 尾随字节 | `n_trailing_byte` | `E_TRAILING_BYTES`（zlib: unused_data） |
| stored NLEN | `n_bad_stored_nlen` | `E_BAD_STORED_NLEN`（zlib: error） |
| 非法 BTYPE | `n_btype_dynamic` | `E_BAD_BTYPE_DYNAMIC`（zlib: incomplete） |
| 距离越界 | `n_bad_distance` | `E_BAD_DISTANCE`（zlib: error） |
| 非法 length 码 | `n_bad_length_code` | `E_BAD_LENGTH_CODE`（zlib: error） |
| 非法 distance 码 | `n_bad_distance_code` | `E_BAD_DISTANCE_CODE`（zlib: error） |
| 记录截断 | `n_record_truncated` | `E_RECORD_TRUNCATED` |
| magic/version/flags | `n_bad_magic`, `n_bad_version`, `n_bad_flags` | 对应 `E_BAD_*` |
| 头 CRC | `n_bad_header_crc` | `E_BAD_HEADER_CRC` |
| 坏 stream_len | `n_bad_stream_len` | `E_STREAM_LEN_MISMATCH` |
| 坏 raw/xform CRC | `n_bad_raw_crc`, `n_bad_xform_crc` | `E_BAD_RAW_CRC` / `E_BAD_XFORM_CRC` |

说明：坏 stream/raw/xform CRC 三个负例在改字段后**重新计算了头 CRC**，确保拒绝原因落在目标字段，而不是提前被头 CRC 拦截。

## 4. A/B 开关与比率（仅声明相位、仅合成）

- `1920×4` 重复图案：`prep=0` ratio 75.00；`prep=1,pred=1` ratio 56.47。该小帧上 A/B 重排+预测**降低**了压缩率（重排打散了原始字节重复）；这不能外推到真实 Bayer 图像。
- `8×4` 梯度：`prep=1,pred=0` ratio 0.851；`prep=1,pred=1` ratio 0.952。预测在极小帧上同样未获益。
- `1920×1080` 合成纹理：ratio 25.52；这是**生成器纹理**，不是真实图集，不得写入真实压缩率。
- 不可压缩：ratio 0.9990，膨胀 +2,706 B（+0.1044%），等于冻结最坏上界。
- 结论只支持：格式/回退/边界正确；**不支持**任何真实 Bayer 收益结论。

## 5. 格式冻结要点（详见 `format-v1.md`）

- zlib `0x78 0x9C` + Adler；只允许 stored/fixed；块 = 1 个 2 行对；1080p 540 块。
- Bayer 声明 RGGB phase=0，平面 `R,G1,G2,B`；变换域连续 4 样本组按 5B/4px 重打包，组可跨平面、不跨块；预测每块每平面重置。
- 窗口 2048、length 3..258、greedy、单候选、块内历史。
- 测试头 32 B：`A1T1` v1；header CRC 覆盖 `[0x00,0x1C)`。
- 勘误：guide §2 的 `270 块 / 2,593,356 B` 与 §2 块定义和 §3 `540` 冲突；冻结为 **540 块 / 2,594,706 B**。
- 缺口：32 B 测试头无 `stream_crc32`、无 W/H；P4 导出契约必须在记录外携带，P1 不扩头。

## 6. 未做 / 不可宣称

- 未写 RTL、未跑 ModelSim/Verilator、未做 G1 RTL 门槛。
- 未做 G2/STA/资源、未做持续服务率；这些属于 P2–P4。
- 未取得真实 RAW、真实 ROI/相位、非 PCIe 导出；**无任何板上或真实图像证据**。
- 未修改生产顶层/三算法/DDR writer/PCIe/RK；未下载、未写 Flash、未推送。
- 本结果不能用于宣称需求二/三完成，也不能把合成 ratio 当真实压缩率。
