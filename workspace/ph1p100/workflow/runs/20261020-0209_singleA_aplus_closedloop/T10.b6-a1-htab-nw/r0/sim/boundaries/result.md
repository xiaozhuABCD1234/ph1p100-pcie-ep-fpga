# Exploratory FPGA integration boundary simulation

Status: PASS_EXPLORATORY

Frozen b6 DUT sources checked against manifest SHA256 before snapshot/compile.
Tool: ModelSim Intel FPGA 10.5b. Independent absolute-path work library and modelsim.ini.
No existing script executed; only newly authored runner/do file with no delete operations.

## odd8x3

```json
{
  "name": "odd8x3",
  "mode": 0,
  "cam_w": 16,
  "cam_h": 8,
  "roi_x": 4,
  "roi_y": 2,
  "w": 8,
  "h": 3,
  "first_deflate_btype": 1,
  "stored_first_block": false,
  "decoded": {
    "magic": 827666753,
    "version": 1,
    "flags": 3,
    "header_len": 44,
    "frame_id": 1,
    "width": 8,
    "height": 3,
    "raw_len": 30,
    "xform_len": 30,
    "stream_len": 28,
    "raw_crc": 1049334108,
    "xform_crc": 3754274248,
    "stream_crc": 2998920377,
    "header_crc": 3236421213,
    "prep": 1,
    "pred": 1,
    "header_crc_ok": true,
    "stream_crc_ok": true,
    "zlib_ok": true,
    "xform_len_ok": true,
    "xform_crc_ok": true,
    "raw_len_ok": true,
    "raw_crc_ok": true,
    "stream_sha256": "bbf918fa93f6066afbe45f82eea0ba931a6365235b0be91c11fa6a900809d8be",
    "xform_sha256": "52fc5d9093b534591a4efc9c2495e46dec71d41cb9960b9e02950bfb55d0f179",
    "raw_sha256": "33595ce37492fb7d35bbda5454b0cd39f498c49c85a96d647f6d0c066143277f",
    "worstcase_ok": true,
    "dir": "D:\\fpga\\ph1p100\\workflow\\runs\\20261020-0209_singleA_aplus_closedloop\\T10.b6-a1-htab-nw\\r0\\sim\\boundaries\\odd8x3_decoded\\frame_001"
  },
  "expected_raw_sha256": "33595ce37492fb7d35bbda5454b0cd39f498c49c85a96d647f6d0c066143277f",
  "expected_xform_sha256": "52fc5d9093b534591a4efc9c2495e46dec71d41cb9960b9e02950bfb55d0f179",
  "stats": {
    "mode": 0,
    "cap": 1,
    "enc": 1,
    "exported": 1,
    "exp_bytes": 28,
    "raw_pub": 1,
    "raw_drop": 0,
    "cmp_drop": 0,
    "geom": 0,
    "err": 0,
    "cap_bytes": 72,
    "cycles": 3875,
    "read_words": 2,
    "dup_words": 0
  },
  "capture_bytes": 72,
  "capture_sha256": "c02c1200afa74c3de380410e5dc715fe56ccdfe4f8df9440710ca3dd767f54c5",
  "trailing_bytes": 0,
  "checks": {
    "tb_done": true,
    "no_timeout": true,
    "one_frame": true,
    "no_half_frame": true,
    "captured_length": true,
    "one_export": true,
    "raw_pub": true,
    "cap_enc": true,
    "no_drop_geom_errors": true,
    "header_crc_ok": true,
    "stream_crc_ok": true,
    "xform_crc_ok": true,
    "raw_crc_ok": true,
    "zlib_ok": true,
    "raw_len_ok": true,
    "xform_len_ok": true,
    "worstcase_ok": true,
    "raw_exact": true,
    "xform_exact": true,
    "header_geometry": true,
    "export_bytes": true,
    "stream_length": true,
    "read_words": true
  },
  "status": "PASS"
}
```

## random64x8

```json
{
  "name": "random64x8",
  "mode": 1,
  "cam_w": 80,
  "cam_h": 16,
  "roi_x": 4,
  "roi_y": 2,
  "w": 64,
  "h": 8,
  "first_deflate_btype": 0,
  "stored_first_block": true,
  "decoded": {
    "magic": 827666753,
    "version": 1,
    "flags": 3,
    "header_len": 44,
    "frame_id": 1,
    "width": 64,
    "height": 8,
    "raw_len": 640,
    "xform_len": 640,
    "stream_len": 666,
    "raw_crc": 2044571025,
    "xform_crc": 1762974722,
    "stream_crc": 4255632186,
    "header_crc": 1446503189,
    "prep": 1,
    "pred": 1,
    "header_crc_ok": true,
    "stream_crc_ok": true,
    "zlib_ok": true,
    "xform_len_ok": true,
    "xform_crc_ok": true,
    "raw_len_ok": true,
    "raw_crc_ok": true,
    "stream_sha256": "01a172d538a292a5cb34520748b28307513a81391de82a4d21abbaf0058c94f9",
    "xform_sha256": "196d7c62d885325618fe09f13c6c2eef751cbb55f4ea5117bb7c330bd6d74865",
    "raw_sha256": "c619e96f1a1ef76c6dcc5fa3d548b6620c96a264dc29baffb586ae2c372e8a62",
    "worstcase_ok": true,
    "dir": "D:\\fpga\\ph1p100\\workflow\\runs\\20261020-0209_singleA_aplus_closedloop\\T10.b6-a1-htab-nw\\r0\\sim\\boundaries\\random64x8_decoded\\frame_001"
  },
  "expected_raw_sha256": "c619e96f1a1ef76c6dcc5fa3d548b6620c96a264dc29baffb586ae2c372e8a62",
  "expected_xform_sha256": "196d7c62d885325618fe09f13c6c2eef751cbb55f4ea5117bb7c330bd6d74865",
  "stats": {
    "mode": 1,
    "cap": 1,
    "enc": 1,
    "exported": 1,
    "exp_bytes": 666,
    "raw_pub": 1,
    "raw_drop": 0,
    "cmp_drop": 0,
    "geom": 0,
    "err": 0,
    "cap_bytes": 710,
    "cycles": 6935,
    "read_words": 32,
    "dup_words": 0
  },
  "capture_bytes": 710,
  "capture_sha256": "c562aa2318dae6b3c15c004bbfcd4f3c14ec9ac1c22e5f094f2646f8e67f644a",
  "trailing_bytes": 0,
  "checks": {
    "tb_done": true,
    "no_timeout": true,
    "one_frame": true,
    "no_half_frame": true,
    "captured_length": true,
    "one_export": true,
    "raw_pub": true,
    "cap_enc": true,
    "no_drop_geom_errors": true,
    "header_crc_ok": true,
    "stream_crc_ok": true,
    "xform_crc_ok": true,
    "raw_crc_ok": true,
    "zlib_ok": true,
    "raw_len_ok": true,
    "xform_len_ok": true,
    "worstcase_ok": true,
    "raw_exact": true,
    "xform_exact": true,
    "header_geometry": true,
    "export_bytes": true,
    "stream_length": true,
    "read_words": true,
    "stored_fallback_observed": true
  },
  "status": "PASS"
}
```

## Limits

- MODE3/4 not exercised: original TB has no independent branch.
- Write-in-progress reset recovery not executed within bounded scope.
- No TD, bitstream, board download, RK work, or production RTL changes.

See result.json for exact source SHA256 and commands; all evidence is under this output directory.