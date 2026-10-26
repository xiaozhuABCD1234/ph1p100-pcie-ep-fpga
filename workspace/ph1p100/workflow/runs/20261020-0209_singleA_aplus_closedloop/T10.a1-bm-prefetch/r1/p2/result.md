# T10.a1-enc-rtl / P2 verification

鍒ゅ畾: **PASS** (synthetic, offline RTL simulation)

| case | blocks | stream B | zlib | strict | mismatch | pass |
|---|---:|---:|---|---|---:|---|
| p1_p_8x4_flat_prep0_pred0 | 2 | 24 | True | True | 0 | True |
| p1_p_8x4_grad_prep1_pred0 | 2 | 47 | True | True | 0 | True |
| p1_p_8x4_grad_prep1_pred1 | 2 | 42 | True | True | 0 | True |
| p1_p_1920x4_repeat_prep0_pred0 | 2 | 183 | True | True | 0 | True |
| p1_p_1920x4_repeat_prep1_pred1 | 2 | 228 | True | True | 0 | True |
| p1_p_32x5_tail_prep1_pred1 | 3 | 94 | True | True | 0 | True |
| p2_random_4800 | 1 | 4811 | True | True | 0 | True |
| p2_dist2048_len258 | 1 | 62 | True | True | 0 | True |
| p2_len3_dist4 | 1 | 3009 | True | True | 0 | True |
| p2_frame_8x5_tail | 3 | 62 | True | True | 0 | True |
| p2_frame_16x8 | 4 | 100 | True | True | 0 | True |
| p2_perf_1920x64_comp | 32 | 50310 | True | True | 0 | True |
| p2_perf_1920x64_rand | 32 | 153766 | True | True | 0 | True |

## Negative cases

| case | expected | got | pass |
|---|---|---|---|
| p1_p_8x4_flat_prep0_pred0/truncate_1 | E_TRUNCATED | E_TRUNCATED | True |
| p1_p_8x4_flat_prep0_pred0/truncate_2 | E_TRUNCATED | E_TRUNCATED | True |
| p1_p_8x4_flat_prep0_pred0/truncate_5 | E_TRUNCATED | E_TRUNCATED | True |
| p1_p_8x4_flat_prep0_pred0/bad_adler | E_BAD_ADLER | E_BAD_ADLER | True |
| p1_p_8x4_flat_prep0_pred0/trailing_byte | E_TRAILING_BYTES | E_TRAILING_BYTES | True |
| p1_p_8x4_flat_prep0_pred0/dynamic_btype | E_BAD_BTYPE_DYNAMIC | E_BAD_BTYPE_DYNAMIC | True |
| p1_p_8x4_grad_prep1_pred0/truncate_1 | E_TRUNCATED | E_TRUNCATED | True |
| p1_p_8x4_grad_prep1_pred0/truncate_2 | E_TRUNCATED | E_TRUNCATED | True |
| p1_p_8x4_grad_prep1_pred0/truncate_5 | E_TRUNCATED | E_TRUNCATED | True |
| p1_p_8x4_grad_prep1_pred0/bad_adler | E_BAD_ADLER | E_BAD_ADLER | True |
| p1_p_8x4_grad_prep1_pred0/trailing_byte | E_TRAILING_BYTES | E_TRAILING_BYTES | True |
| p1_p_8x4_grad_prep1_pred0/dynamic_btype | E_BAD_BTYPE_DYNAMIC | E_BAD_BTYPE_DYNAMIC | True |
| p1_p_8x4_grad_prep1_pred1/truncate_1 | E_TRUNCATED | E_TRUNCATED | True |
| p1_p_8x4_grad_prep1_pred1/truncate_2 | E_TRUNCATED | E_TRUNCATED | True |
| p1_p_8x4_grad_prep1_pred1/truncate_5 | E_TRUNCATED | E_TRUNCATED | True |
| p1_p_8x4_grad_prep1_pred1/bad_adler | E_BAD_ADLER | E_BAD_ADLER | True |
| p1_p_8x4_grad_prep1_pred1/trailing_byte | E_TRAILING_BYTES | E_TRAILING_BYTES | True |
| p1_p_8x4_grad_prep1_pred1/dynamic_btype | E_BAD_BTYPE_DYNAMIC | E_BAD_BTYPE_DYNAMIC | True |
| p1_p_1920x4_repeat_prep0_pred0/truncate_1 | E_TRUNCATED | E_TRUNCATED | True |
| p1_p_1920x4_repeat_prep0_pred0/truncate_2 | E_TRUNCATED | E_TRUNCATED | True |
| p1_p_1920x4_repeat_prep0_pred0/truncate_5 | E_TRUNCATED | E_TRUNCATED | True |
| p1_p_1920x4_repeat_prep0_pred0/bad_adler | E_BAD_ADLER | E_BAD_ADLER | True |
| p1_p_1920x4_repeat_prep0_pred0/trailing_byte | E_TRAILING_BYTES | E_TRAILING_BYTES | True |
| p1_p_1920x4_repeat_prep0_pred0/dynamic_btype | E_BAD_BTYPE_DYNAMIC | E_BAD_BTYPE_DYNAMIC | True |
| p1_p_1920x4_repeat_prep1_pred1/truncate_1 | E_TRUNCATED | E_TRUNCATED | True |
| p1_p_1920x4_repeat_prep1_pred1/truncate_2 | E_TRUNCATED | E_TRUNCATED | True |
| p1_p_1920x4_repeat_prep1_pred1/truncate_5 | E_TRUNCATED | E_TRUNCATED | True |
| p1_p_1920x4_repeat_prep1_pred1/bad_adler | E_BAD_ADLER | E_BAD_ADLER | True |
| p1_p_1920x4_repeat_prep1_pred1/trailing_byte | E_TRAILING_BYTES | E_TRAILING_BYTES | True |
| p1_p_1920x4_repeat_prep1_pred1/dynamic_btype | E_BAD_BTYPE_DYNAMIC | E_BAD_BTYPE_DYNAMIC | True |
| p1_p_32x5_tail_prep1_pred1/truncate_1 | E_TRUNCATED | E_TRUNCATED | True |
| p1_p_32x5_tail_prep1_pred1/truncate_2 | E_TRUNCATED | E_TRUNCATED | True |
| p1_p_32x5_tail_prep1_pred1/truncate_5 | E_TRUNCATED | E_TRUNCATED | True |
| p1_p_32x5_tail_prep1_pred1/bad_adler | E_BAD_ADLER | E_BAD_ADLER | True |
| p1_p_32x5_tail_prep1_pred1/trailing_byte | E_TRAILING_BYTES | E_TRAILING_BYTES | True |
| p1_p_32x5_tail_prep1_pred1/dynamic_btype | E_BAD_BTYPE_DYNAMIC | E_BAD_BTYPE_DYNAMIC | True |
| p2_random_4800/truncate_1 | E_TRUNCATED | E_TRUNCATED | True |
| p2_random_4800/truncate_2 | E_TRUNCATED | E_TRUNCATED | True |
| p2_random_4800/truncate_5 | E_TRUNCATED | E_TRUNCATED | True |
| p2_random_4800/bad_adler | E_BAD_ADLER | E_BAD_ADLER | True |
| p2_random_4800/trailing_byte | E_TRAILING_BYTES | E_TRAILING_BYTES | True |
| p2_random_4800/dynamic_btype | E_BAD_BTYPE_DYNAMIC | E_BAD_BTYPE_DYNAMIC | True |
| p2_random_4800/bad_stored_nlen | E_BAD_STORED_NLEN | E_BAD_STORED_NLEN | True |
| p2_dist2048_len258/truncate_1 | E_TRUNCATED | E_TRUNCATED | True |
| p2_dist2048_len258/truncate_2 | E_TRUNCATED | E_TRUNCATED | True |
| p2_dist2048_len258/truncate_5 | E_TRUNCATED | E_TRUNCATED | True |
| p2_dist2048_len258/bad_adler | E_BAD_ADLER | E_BAD_ADLER | True |
| p2_dist2048_len258/trailing_byte | E_TRAILING_BYTES | E_TRAILING_BYTES | True |
| p2_dist2048_len258/dynamic_btype | E_BAD_BTYPE_DYNAMIC | E_BAD_BTYPE_DYNAMIC | True |
| p2_len3_dist4/truncate_1 | E_TRUNCATED | E_TRUNCATED | True |
| p2_len3_dist4/truncate_2 | E_TRUNCATED | E_TRUNCATED | True |
| p2_len3_dist4/truncate_5 | E_TRUNCATED | E_TRUNCATED | True |
| p2_len3_dist4/bad_adler | E_BAD_ADLER | E_BAD_ADLER | True |
| p2_len3_dist4/trailing_byte | E_TRAILING_BYTES | E_TRAILING_BYTES | True |
| p2_len3_dist4/dynamic_btype | E_BAD_BTYPE_DYNAMIC | E_BAD_BTYPE_DYNAMIC | True |
| p2_frame_8x5_tail/truncate_1 | E_TRUNCATED | E_TRUNCATED | True |
| p2_frame_8x5_tail/truncate_2 | E_TRUNCATED | E_TRUNCATED | True |
| p2_frame_8x5_tail/truncate_5 | E_TRUNCATED | E_TRUNCATED | True |
| p2_frame_8x5_tail/bad_adler | E_BAD_ADLER | E_BAD_ADLER | True |
| p2_frame_8x5_tail/trailing_byte | E_TRAILING_BYTES | E_TRAILING_BYTES | True |
| p2_frame_8x5_tail/dynamic_btype | E_BAD_BTYPE_DYNAMIC | E_BAD_BTYPE_DYNAMIC | True |
| p2_frame_16x8/truncate_1 | E_TRUNCATED | E_TRUNCATED | True |
| p2_frame_16x8/truncate_2 | E_TRUNCATED | E_TRUNCATED | True |
| p2_frame_16x8/truncate_5 | E_TRUNCATED | E_TRUNCATED | True |
| p2_frame_16x8/bad_adler | E_BAD_ADLER | E_BAD_ADLER | True |
| p2_frame_16x8/trailing_byte | E_TRAILING_BYTES | E_TRAILING_BYTES | True |
| p2_frame_16x8/dynamic_btype | E_BAD_BTYPE_DYNAMIC | E_BAD_BTYPE_DYNAMIC | True |
| p2_perf_1920x64_comp/truncate_1 | E_TRUNCATED | E_TRUNCATED | True |
| p2_perf_1920x64_comp/truncate_2 | E_TRUNCATED | E_TRUNCATED | True |
| p2_perf_1920x64_comp/truncate_5 | E_TRUNCATED | E_TRUNCATED | True |
| p2_perf_1920x64_comp/bad_adler | E_BAD_ADLER | E_BAD_ADLER | True |
| p2_perf_1920x64_comp/trailing_byte | E_TRAILING_BYTES | E_TRAILING_BYTES | True |
| p2_perf_1920x64_comp/dynamic_btype | E_BAD_BTYPE_DYNAMIC | E_BAD_BTYPE_DYNAMIC | True |
| p2_perf_1920x64_rand/truncate_1 | E_TRUNCATED | E_TRUNCATED | True |
| p2_perf_1920x64_rand/truncate_2 | E_TRUNCATED | E_TRUNCATED | True |
| p2_perf_1920x64_rand/truncate_5 | E_TRUNCATED | E_TRUNCATED | True |
| p2_perf_1920x64_rand/bad_adler | E_BAD_ADLER | E_BAD_ADLER | True |
| p2_perf_1920x64_rand/trailing_byte | E_TRAILING_BYTES | E_TRAILING_BYTES | True |
| p2_perf_1920x64_rand/dynamic_btype | E_BAD_BTYPE_DYNAMIC | E_BAD_BTYPE_DYNAMIC | True |
| p2_perf_1920x64_rand/bad_stored_nlen | E_BAD_STORED_NLEN | E_BAD_STORED_NLEN | True |

## Backpressure / abort / reset

| run | result |
|---|---|
| p2_frame_16x8_bp | PASS |
| p2_frame_16x8_gapbp | PASS |
| abort_midblock | PASS |
| reset_midblock | PASS |

## Throughput (simulation cycles, out_ready=1, 187.5 MHz)

| case | bytes | cycles | cycles/B | MB/s | >=77.76 | >=97.2 |
|---|---:|---:|---:|---:|---|---|
| p2_perf_1920x64_comp | 153600 | 355261 | 2.313 | 81.07 | True | False |
| p2_perf_1920x64_rand | 153600 | 161479 | 1.051 | 178.35 | True | True |

token totals (decoded): {"fixed_blocks": 54, "stored_blocks": 33, "literals": 20805, "matches": 20552}

Note: all inputs are synthetic; no board, PCIe/RK, Flash or download.
