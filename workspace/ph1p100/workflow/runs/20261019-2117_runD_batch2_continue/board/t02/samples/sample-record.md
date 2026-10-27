# T02 两样本记录（6 张原图 + 主转录，最终版）

- run：`20261019-2117_runD_batch2_continue`｜task：`T02.codex-singleA-board`
- 最终更新：2026-10-20 00:50 +08:00（采样时间 2026-10-19 23:50—23:53 +08:00）
- **证据形式（最终）**：6 张原图已落盘到 T1/T2（均为 PNG）+ `user-samples-01.md` 主转录 + 用户口述（`user-input-08.md`、`user-input-09.md`、`user-input-10.md`）；无 CSV/原始导出。
- **用户登记**：操作者=用户本人（未具名）；单 A 接线=没变；供电=没断（均为用户口述）。
- **T2 命名修正**：主已按用户明确要求完成三步重命名（`user-action-rename.md`、`user-input-10.md`）：`T2_cwc2_dhi_20261019_235228.png` 现为 cwc2 内容（87,607 B / `424E2F09…`）；`T2_cwc3_tl_20261019_235310.png` 现为 cwc3 内容（62,433 B / `680BFC05…`）；无 `TEMP` 残留；T1 与 T2 cwc1 未动。
- **本文件只记录事实，不判 PASS/FAIL；G3 仍 `not_run`，由 tester recovery03 独立核验。**

## 1. T1（2026-10-19）

### 1.1 cwc1 camera — 窗口 `Updated at 2026/10/19 23:50:29`

| 探针 | 值 |
|---|---|
| `source_bad` | `00000000` |
| `source_crc` | `00000000` |
| `source_geometry` | `089012DE` |
| `source_good` | `000081D6` |
| `source_header` | `00000000` |
| `source_injected` | `00000001` |
| `algo_gau_complete` | `000081D5` |
| `algo_gau_crc` | `9AA8FCAF` |
| `algo_he_complete` | `000081D5` |
| `algo_he_crc` | `0B5191DA` |
| `algo_identity` | `414C0101` |
| `algo_inbeats` | `02FDDD00` |
| `algo_overflow` | `00000000` |
| `algo_rejected` | `00000001` |
| `algo_y8_complete` | `000081D5` |
| `algo_y8_crc` | `0BB7AE1F` |

### 1.2 cwc2 DHI/DDR — 窗口 `Updated at 2026/10/19 23:51:31`

| 探针 | 值 |
|---|---|
| `cl_fail_count` | `00000000` |
| `cl_fault` | `00000000` |
| `cl_flags` | `8000000F` |
| `cl_base` | `00100000` |
| `cl_header_crc` | `2117BDF9` |
| `cl_identity` | `434C0101` |
| `cl_len` | `00279000` |
| `cl_pass_count` | `000085A6` |
| `cl_payload_crc` | `823DDD95` |
| `cl_recovery_count` | `00000001` |
| `cl_seq` | `000085A7` |
| `cl_session` | `00000000` |
| `cl_words` | `0009E400` |
| `cl_writer_bad` | `00000001` |
| `cl_writer_good` | `000085A6` |

### 1.3 cwc3 TL — 窗口 `Updated at 2026/10/19 23:51:59`

| 探针 | 值 |
|---|---|
| `dbg_mark_word0` | `50434946` |
| `dbg_mark_word1` | `31414B52` |
| `dbg_mark_word2` | `00010000` |
| `dbg_mark_word3` | `0000876D` |
| `dbg_mark_word4` | `00900000` |
| `dbg_mark_word5` | `00279000` |
| `dbg_mark_word6` | `6E000000` |
| `dbg_mark_word7` | `089012DE` |
| `dbg_mark_word8` | `00000021` |

## 2. T2（2026-10-19）

### 2.1 cwc1 camera — 窗口 `Updated at 2026/10/19 23:52:13`

| 探针 | 值 |
|---|---|
| `source_bad` | `00000000` |
| `source_crc` | `00000000` |
| `source_geometry` | `089012DE` |
| `source_good` | `00008830` |
| `source_header` | `00000000` |
| `source_injected` | `00000001` |
| `algo_gau_complete` | `0000882F` |
| `algo_gau_crc` | `E46BD939` |
| `algo_he_complete` | `0000882F` |
| `algo_he_crc` | `7A788A75` |
| `algo_identity` | `414C0101` |
| `algo_inbeats` | `353BC700` |
| `algo_overflow` | `00000000` |
| `algo_rejected` | `00000001` |
| `algo_y8_complete` | `0000882F` |
| `algo_y8_crc` | `F3DB3920` |

### 2.2 cwc2 DHI/DDR — 窗口 `Updated at 2026/10/19 23:52:28`

| 探针 | 值 |
|---|---|
| `cl_fail_count` | `00000000` |
| `cl_fault` | `00000000` |
| `cl_flags` | `8000000F` |
| `cl_base` | `00100000` |
| `cl_header_crc` | `654BE394` |
| `cl_identity` | `434C0101` |
| `cl_len` | `00279000` |
| `cl_pass_count` | `0000891C` |
| `cl_payload_crc` | `0A16C68B` |
| `cl_recovery_count` | `00000001` |
| `cl_seq` | `0000891D` |
| `cl_session` | `00000000` |
| `cl_words` | `0009E400` |
| `cl_writer_bad` | `00000001` |
| `cl_writer_good` | `0000891C` |

### 2.3 cwc3 TL — 窗口 `Updated at 2026/10/19 23:53:10`

| 探针 | 值 |
|---|---|
| `dbg_mark_word0` | `50434946` |
| `dbg_mark_word1` | `31414B52` |
| `dbg_mark_word2` | `00010000` |
| `dbg_mark_word3` | `00008B2C` |
| `dbg_mark_word4` | `00100000` |
| `dbg_mark_word5` | `00279000` |
| `dbg_mark_word6` | `2D000000` |
| `dbg_mark_word7` | `089012DE` |
| `dbg_mark_word8` | `00000021` |

## 3. 对照冻结口径的事实清单（不判 PASS/FAIL）

### 3.1 匹配/一致项

- 身份：`algo_identity=414C0101`、`cl_identity=434C0101`，T1/T2 一致。
- `cl_len=00279000`（2,592,768）、`cl_words=0009E400`（648,192），T1/T2 一致。
- `cl_flags=8000000F`，T1/T2 一致；位义 `[31]=1,[3:0]=15,[15:8]=0`。
- `cl_fault=0`、`cl_fail_count=0`，T1/T2 一致。
- `cl_pass_count` `000085A6→0000891C`，`cl_writer_good` 同步递增（+886）。
- `cl_seq` `000085A7→0000891D`，两样本不同。
- `source_good` `000081D6→00008830`；`algo_gau/he/y8_complete` 均 `000081D5→0000882F`；`algo_inbeats` `02FDDD00→353BC700`；均递增。
- `algo_overflow=0`，T1/T2 一致。
- `source_geometry=089012DE`，T1/T2 一致；解码 `last_lines=0x0890=2192`、`last_wc=0x12DE=4830`；合规解释由 tester 裁定。
- 时间间隔（按内容/实例）：cwc1 104 s、cwc2 57 s、cwc3 71 s，均 ≥20 s。

### 3.2 偏差/观察项（交 tester）

- `cl_writer_bad=00000001`、`cl_recovery_count=00000001`、`source_injected=00000001`、`algo_rejected=00000001`：两样本均如此。
- `source_crc=0`、`source_header=0`：两样本均为 0。
- `cl_base=00100000`：两样本一致。
- `dbg_mark_word4 00900000→00100000`；`word6 6E000000→2D000000`；`word3 0000876D→00008B2C`。
- CRC 类两样本均不同（图像相关）。

### 3.3 证据局限（如实记录，非“未提供”矛盾）

- 操作者未具名（登记为“用户本人（未具名）”）；接线/供电仅为用户口述“没变/没断”。
- 无 CSV/原始导出；6 张原图为聊天截图另存。
- ROI X0/Y0/SKIP37、物理 Bayer 相位无直接探针/图像证据，`PHASE=3` 物理相位仍 `unknown`。

## 4. 最终 6 图核验（2026-10-20 00:50 +08:00，主完成 T2 重命名后）

- 6/6 文件名与内容映射一致，均为 PNG，无 TEMP 残留。
- T1（未动）：
  - `C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道\workflow\runs\20261019-2117_runD_batch2_continue\board\t02\samples\T1\T1_cwc1_camera_20261019_235029.png`，101386 B，`81825bba948592de5eeae4798028cd6fa273fc48bc1c32ecfaa4a178f3298945`
  - `C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道\workflow\runs\20261019-2117_runD_batch2_continue\board\t02\samples\T1\T1_cwc2_dhi_20261019_235131.png`，85322 B，`ff6daee0185d08e489afa6535d56789596486296977ba6685f1a0ec3582ab0f5`
  - `C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道\workflow\runs\20261019-2117_runD_batch2_continue\board\t02\samples\T1\T1_cwc3_tl_20261019_235159.png`，61237 B，`a4849b96643f0050aa9d5b87e7503769df161129a61ffa2ac690227615141569`
- T2（cwc2/cwc3 已按内容重命名）：
  - `C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道\workflow\runs\20261019-2117_runD_batch2_continue\board\t02\samples\T2\T2_cwc1_camera_20261019_235213.png`，103357 B，`102b355faaff8dd3e6895a761f8ef3c4b2e3445e29703c53d3e07028fc063e83`
  - `C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道\workflow\runs\20261019-2117_runD_batch2_continue\board\t02\samples\T2\T2_cwc2_dhi_20261019_235228.png`，87607 B，`424e2f09d8960e59e6e099fc5fd13ef9393bc92857c5bc404b5bbd640451cf12`
  - `C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道\workflow\runs\20261019-2117_runD_batch2_continue\board\t02\samples\T2\T2_cwc3_tl_20261019_235310.png`，62433 B，`680bfc0581b8be46b24a65706a4edcb36d7b2dc7088a4de4b1dc3ebff9bf2b69`
- 状态：`ready_for_test`；G3 仍 `not_run`，交 tester recovery03 独立核验；未判 PASS/FAIL。
