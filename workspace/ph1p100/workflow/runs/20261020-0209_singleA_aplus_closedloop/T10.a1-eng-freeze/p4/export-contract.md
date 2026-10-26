# P4 非 PCIe 真实样例导出契约（离线，blocked）

- task_id: `T10.a1-eng-freeze`｜日期：2026-10-20｜性质：**契约草案，未导出任何真实样例**
- 结论：**当前无已确认的非 PCIe 导出路径**；真实 RAW 样例仍 `blocked_awaiting_hardware`。
- 本文件不声称已取得真实片段/整帧，也不把合成向量标成真实数据。

## 1. 现有路径审计（只读结论）

| 候选路径 | 现状 | 判定 |
|---|---|---|
| DDR 读回（现有 writer/reader） | 需要板窗与主机侧读回确认；本轮无板、无下载 | **blocked** |
| 调试字/状态寄存器 | 仅状态，非像素流；无确认的批量导出 | **不可用** |
| CWC（ChipWatcher） | 既有项已关闭；本轮未重新使能，且不适合整帧 | **blocked/closed** |
| UART | 无确认的可用 UART 导出通道 | **blocked** |
| PCIe | 本轮明确禁止 | **N/A** |
| Flash/SD | 本轮明确禁止 | **N/A** |

没有一条路径在本轮被实际打通；因此 `exported_samples = 0`。

## 2. 冻结样例容器（未来导出时使用）

一个样例 = **32 B `A1T1` test-only 记录头 + 精确 `stream_len` 字节 zlib 流**；头外必须另附元数据（因为 32 B 头不含 W/H 与 `stream_crc32`）。

### 2.1 记录头（小端，32 B）

| 偏移 | 字段 | 说明 |
|---:|---|---|
| 0x00 | magic `A1T1` | 4 B |
| 0x04 | version=1 | u16 |
| 0x06 | flags | bit0=`prep_en`, bit1=`pred_en`，其余 0 |
| 0x08 | raw_len | u32，原始 packed RAW10 字节数 |
| 0x0C | xform_len | u32，变换域字节数（恒等于 raw_len） |
| 0x10 | stream_len | u32，精确 zlib 字节数 |
| 0x14 | raw_crc32 | u32 |
| 0x18 | xform_crc32 | u32 |
| 0x1C | header_crc32 | 覆盖 `[0x00,0x1C)` |

### 2.2 头外元数据（JSON，必须与样例同目录）

```json
{
  "sample_id": "...",
  "source": "real_capture | synthetic",
  "candidate": {"a1_frame_top_sha256": "...", "a1_deflate_core_sha256": "..."},
  "geometry": {"W": 1920, "H": 1080, "stride_bytes": 2400},
  "flags": {"prep_en": 1, "pred_en": 1},
  "lengths": {"raw_len": 2592000, "xform_len": 2592000, "stream_len": 81707},
  "crc": {"raw_crc32": "...", "xform_crc32": "...", "stream_crc32": "..."},
  "capture": {"board": "...", "build_id": "...", "timestamp": "...", "transport": "..."},
  "notes": "..."
}
```

- `stream_crc32` 不在 32 B 头内，必须外置；宿主校验顺序：头 CRC → 记录长度 = 32 + `stream_len` → zlib/严格解析 → `stream_crc32` → `raw_crc32`/`xform_crc32` → Bayer 逆变换逐样本。
- 宿主解析器：`tools/codec/a1_sample_check.py`（P1 候选）。校验失败必须给稳定 reason code，不得“跳过 CRC 通过”。

## 3. 样例槽位 schema

```text
samples/
  <sample_id>/
    record.bin        # 32 B A1T1 + stream_len 字节 zlib
    meta.json         # 2.2 元数据
    record.sha256
```

- 每个样例只允许一个 zlib 成员；记录后不得有尾随字节。
- 片段优先：允许 `H` 为偶数的小片段（如 1920×16），但必须在 `meta.json` 标注 `H`，不得冒充 1080p 整帧。
- `source` 必须诚实标注 `real_capture` 或 `synthetic`；合成样例不得进入真实 profile 统计。

## 4. blocked 条件（全部满足才可执行）

1. 板窗与供电/相机/采集链路可用，且用户在场授权；
2. 确认一种非 PCIe 传输方式（DDR 读回 / UART / 其它）并验证其字节完整性；
3. 冻结同一候选（两个 RTL hash 与 `CANDIDATE-MANIFEST.json` 一致）；
4. 明确几何、ROI、Bayer 相位；相位未知时只能标 `declared RGGB phase=0`；
5. 采样方案（帧数、内容、反压、温度）事先冻结。

当前 1–5 均不满足，故本契约**未执行**。

## 5. 不声明

- 不声明已导出真实片段/整帧；
- 不声明真实 Bayer 相位、真实压缩率、真实 ROI；
- 不声明 DDR 读回或 UART 已可用；
- 不声明板上 CRC/吞吐。
