# 用户回传的 ChipWatcher 采样（主机械转录，原图 6 张）

## 说明

- 用户消息原文：“看这几张图片分析吧，基本是按照要求去做的”
- 证据形式：聊天内 6 张 ChipWatcher 截图（未提供 CSV/原始导出）。以下数值为主按截图逐字转录，供开发/综合测试核对；若截图原文件另存，以截图为准。
- 截图时间戳取自各窗口右上角 `Updated at`。
- 图片顺序：图1 cwc1 T1；图2 cwc2 T1；图3 cwc3 T1；图4 cwc3 T2；图5 cwc2 T2；图6 cwc1 T2。

## T1

### cwc1 camera — 图1 — `Updated at 2026/10/19 23:50:29`

| 探针 | 值 |
|---|---|
| `source_bad[31:0]` | `00000000` |
| `source_crc[31:0]` | `00000000` |
| `source_geometry[31:0]` | `089012DE` |
| `source_good[31:0]` | `000081D6` |
| `source_header[31:0]` | `00000000` |
| `source_injected[31:0]` | `00000001` |
| `algo_gau_complete[31:0]` | `000081D5` |
| `algo_gau_crc[31:0]` | `9AA8FCAF` |
| `algo_he_complete[31:0]` | `000081D5` |
| `algo_he_crc[31:0]` | `0B5191DA` |
| `algo_identity[31:0]` | `414C0101` |
| `algo_inbeats[31:0]` | `02FDDD00` |
| `algo_overflow[31:0]` | `00000000` |
| `algo_rejected[31:0]` | `00000001` |
| `algo_y8_complete[31:0]` | `000081D5` |
| `algo_y8_crc[31:0]` | `0BB7AE1F` |

### cwc2 DHI/DDR — 图2 — `Updated at 2026/10/19 23:51:31`

| 探针 | 值 |
|---|---|
| `cl_fail_count[31:0]` | `00000000` |
| `cl_fault[31:0]` | `00000000` |
| `cl_flags[31:0]` | `8000000F` |
| `cl_base[31:0]` | `00100000` |
| `cl_header_crc[31:0]` | `2117BDF9` |
| `cl_identity[31:0]` | `434C0101` |
| `cl_len[31:0]` | `00279000` |
| `cl_pass_count[31:0]` | `000085A6` |
| `cl_payload_crc[31:0]` | `823DDD95` |
| `cl_recovery_count[31:0]` | `00000001` |
| `cl_seq[31:0]` | `000085A7` |
| `cl_session[31:0]` | `00000000` |
| `cl_words[31:0]` | `0009E400` |
| `cl_writer_bad[31:0]` | `00000001` |
| `cl_writer_good[31:0]` | `000085A6` |

### cwc3 TL — 图3 — `Updated at 2026/10/19 23:51:59`

| 探针 | 值 |
|---|---|
| `dbg_mark_word0[31:0]` | `50434946` |
| `dbg_mark_word1[31:0]` | `31414B52` |
| `dbg_mark_word2[31:0]` | `00010000` |
| `dbg_mark_word3[31:0]` | `0000876D` |
| `dbg_mark_word4[31:0]` | `00900000` |
| `dbg_mark_word5[31:0]` | `00279000` |
| `dbg_mark_word6[31:0]` | `6E000000` |
| `dbg_mark_word7[31:0]` | `089012DE` |
| `dbg_mark_word8[31:0]` | `00000021` |

## T2

### cwc1 camera — 图6 — `Updated at 2026/10/19 23:52:13`

| 探针 | 值 |
|---|---|
| `source_bad[31:0]` | `00000000` |
| `source_crc[31:0]` | `00000000` |
| `source_geometry[31:0]` | `089012DE` |
| `source_good[31:0]` | `00008830` |
| `source_header[31:0]` | `00000000` |
| `source_injected[31:0]` | `00000001` |
| `algo_gau_complete[31:0]` | `0000882F` |
| `algo_gau_crc[31:0]` | `E46BD939` |
| `algo_he_complete[31:0]` | `0000882F` |
| `algo_he_crc[31:0]` | `7A788A75` |
| `algo_identity[31:0]` | `414C0101` |
| `algo_inbeats[31:0]` | `353BC700` |
| `algo_overflow[31:0]` | `00000000` |
| `algo_rejected[31:0]` | `00000001` |
| `algo_y8_complete[31:0]` | `0000882F` |
| `algo_y8_crc[31:0]` | `F3DB3920` |

### cwc2 DHI/DDR — 图5 — `Updated at 2026/10/19 23:52:28`

| 探针 | 值 |
|---|---|
| `cl_fail_count[31:0]` | `00000000` |
| `cl_fault[31:0]` | `00000000` |
| `cl_flags[31:0]` | `8000000F` |
| `cl_base[31:0]` | `00100000` |
| `cl_header_crc[31:0]` | `654BE394` |
| `cl_identity[31:0]` | `434C0101` |
| `cl_len[31:0]` | `00279000` |
| `cl_pass_count[31:0]` | `0000891C` |
| `cl_payload_crc[31:0]` | `0A16C68B` |
| `cl_recovery_count[31:0]` | `00000001` |
| `cl_seq[31:0]` | `0000891D` |
| `cl_session[31:0]` | `00000000` |
| `cl_words[31:0]` | `0009E400` |
| `cl_writer_bad[31:0]` | `00000001` |
| `cl_writer_good[31:0]` | `0000891C` |

### cwc3 TL — 图4 — `Updated at 2026/10/19 23:53:10`

| 探针 | 值 |
|---|---|
| `dbg_mark_word0[31:0]` | `50434946` |
| `dbg_mark_word1[31:0]` | `31414B52` |
| `dbg_mark_word2[31:0]` | `00010000` |
| `dbg_mark_word3[31:0]` | `00008B2C` |
| `dbg_mark_word4[31:0]` | `00100000` |
| `dbg_mark_word5[31:0]` | `00279000` |
| `dbg_mark_word6[31:0]` | `2D000000` |
| `dbg_mark_word7[31:0]` | `089012DE` |
| `dbg_mark_word8[31:0]` | `00000021` |

## 机械观察（仅转录核对，不判 PASS/FAIL）

- 身份：`algo_identity=414C0101`、`cl_identity=434C0101`、`word0/1/2=50434946/31414B52/00010000`，两样本一致。
- 长度/字数：`cl_len=00279000`、`cl_words=0009E400`，两样本一致。
- `cl_flags=8000000F`，两样本一致。
- `cl_fault=0`、`cl_fail_count=0`；`cl_pass_count` `000085A6→0000891C`、`cl_writer_good` 同步递增；`cl_seq` `000085A7→0000891D` 不同。
- `cl_writer_bad=00000001`、`cl_recovery_count=00000001`、`source_injected=00000001`、`algo_rejected=00000001`：两样本均如此，需测试者对照“内部 abort/恢复”口径判定。
- `word4` `00900000→00100000`；`word6` `6E000000→2D000000`；需测试者对照 probe map/候选语义判定。
- `source_geometry=089012DE` 两样本一致；`source_crc=0`、`source_header=0`；`algo_overflow=0`。
- `source_good` `000081D6→00008830`；`algo_*_complete` `000081D5→0000882F`；`algo_inbeats` `02FDDD00→353BC700`；均递增。
- CRC：`algo_gau_crc`、`algo_he_crc`、`algo_y8_crc`、`cl_header_crc`、`cl_payload_crc` 两样本均不同（随图像变化）。
- 时间间隔（按窗口 `Updated at`）：cwc1 104 s、cwc2 57 s、cwc3 71 s，均 ≥20 s。
- 证据形式：聊天截图转录；无 CSV/原始导出。截图文件若未另存，报告需如实注明证据形式。
