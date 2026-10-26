# T02 ASCII 暂存记录

- 时间：2026-10-19 23:40 +08:00
- 源目录：`C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道\workflow\runs\20261019-0212_codex_fpga_closedloop_b2\recovery01\B01\timing-continuation01\remaining-attempts01\candidate`
- **ASCII 主目录**：`D:\anlogic\runa_runD\t02_ascii_20261019_234035`
- 新建、未覆盖；未删除、未修改任何源文件。

## 1. 文件副本与 SHA256（源=副本，全部 MATCH）

| 副本（完整绝对路径） | SHA256 | 大小(B) | 源 SHA MATCH |
|---|---|---|---|
| `D:\anlogic\runa_runD\t02_ascii_20261019_234035\current.cwc` | `b28e3d4ee476731b118da0b12c3bad8dcca1dadfbd9b7ae4dc418c4d225a74ce` | 312109 | 是 |
| `D:\anlogic\runa_runD\t02_ascii_20261019_234035\current.bit` | `b68c6e183e97eb0d465db77078f5049feca3a947fac51f99633621dd99b3f9bf` | 5224034 | 是 |
| `D:\anlogic\runa_runD\t02_ascii_20261019_234035\current.bid` | `4dcdc26382f6b49e7ed9b95a40a1d57c05191c0130050812a74b853c16b38f33` | 188792 | 是 |
| `D:\anlogic\runa_runD\t02_ascii_20261019_234035\probe-map.json` | `96eb210bb0c55eed110b2a35a8ae0d3ccd3d8823c3d4286a635f9f9dd46d888a` | 238857 | 是 |
| `D:\anlogic\runa_runD\t02_ascii_20261019_234035\manifest.json` | `c7a40897166467f2beafb096701dba9cf836e1007d77ae03d90009d06f80d757` | 255465 | 是 |
| `D:\anlogic\runa_runD\t02_ascii_20261019_234035\t02_current.cwc` | `b28e3d4ee476731b118da0b12c3bad8dcca1dadfbd9b7ae4dc418c4d225a74ce` | 312109 | 是 |
| `D:\anlogic\runa_runD\t02_ascii_20261019_234035\t02_current.bit` | `b68c6e183e97eb0d465db77078f5049feca3a947fac51f99633621dd99b3f9bf` | 5224034 | 是 |
| `D:\anlogic\runa_runD\t02_ascii_20261019_234035\t02_current.bid` | `4dcdc26382f6b49e7ed9b95a40a1d57c05191c0130050812a74b853c16b38f33` | 188792 | 是 |
| `D:\anlogic\runa_runD\t02_ascii_20261019_234035\t02_probe-map.json` | `96eb210bb0c55eed110b2a35a8ae0d3ccd3d8823c3d4286a635f9f9dd46d888a` | 238857 | 是 |
| `D:\anlogic\runa_runD\t02_ascii_20261019_234035\t02_manifest.json` | `c7a40897166467f2beafb096701dba9cf836e1007d77ae03d90009d06f80d757` | 255465 | 是 |

## 2. CWC 内嵌路径/非 ASCII 扫描（只读，未修改）

扫描对象：`D:\anlogic\runa_runD\t02_ascii_20261019_234035\t02_current.cwc`（312,109 B）。

- 非 ASCII 字节（>0x7F）：**0 个**。
- 可打印 ASCII 路径串（含 `:\`、`:/` 或以 `\\` 开头，长度 ≥5）：**0 个**。
- UTF-16LE 路径关键词 `C:\`、`D:\`、`workflow`、`20261019`、`current.cwc`：**均未命中**。
- UTF-8 中文路径关键词（桌面/实验室/竞赛/嵌入式/创新设计赛道/current.cwc）：**均未命中**。
- 结论：**CWC 未内嵌中文绝对路径或非 ASCII 引用**；此前打不开更可能来自“打开时所在目录路径含中文”，不是 CWC 内容。使用上述纯 ASCII 目录/文件名副本应可打开。若仍打不开，按用户清单第 8 条停并截图，不要再重下。

## 3. 其它

- 已建样本目录：`D:\anlogic\runa_runD\t02_ascii_20261019_234035\samples\T1`、`D:\anlogic\runa_runD\t02_ascii_20261019_234035\samples\T2`。
- 另有同 SHA 的 C: 备份目录 `C:\t02_ascii_root\t02_ascii_20261019_234017`（当时 D:\anlogic\runa_runD 尚未创建）；本清单统一使用 D: 主目录。未删除该备份。
- 本轮 0 下载、0 Flash/efuse/SPI/svf、0 CLI readback、0 GUI 自动化、0 杀进程、0 commit/push。

## 4. 2026-10-19 23:45 目录整理（ChipWatcher 警告“only one bit file”）

- 用户打开 ASCII CWC 时收到：`please ensure that there is only one bit file in the directory: D:\anlogic\runa_runD\t02_ascii_20261019_234035`。
- 处理方式：**移动，不删除、不覆盖**。
- 移入 `D:\anlogic\runa_runD\t02_ascii_20261019_234035\_extras\current.bit`：移动前/后 SHA 均为 `b68c6e183e97eb0d465db77078f5049feca3a947fac51f99633621dd99b3f9bf`，5224034 B。
- 移入 `D:\anlogic\runa_runD\t02_ascii_20261019_234035\_extras\current.cwc`：移动前/后 SHA 均为 `b28e3d4ee476731b118da0b12c3bad8dcca1dadfbd9b7ae4dc418c4d225a74ce`，312109 B。
- `_extras` 当前仅这两个文件；根目录 `.bit` 数量=1、`.cwc` 数量=1。
- 根目录唯一 bit：`D:\anlogic\runa_runD\t02_ascii_20261019_234035\t02_current.bit`，SHA `b68c6e183e97eb0d465db77078f5049feca3a947fac51f99633621dd99b3f9bf`。
- 根目录唯一 CWC：`D:\anlogic\runa_runD\t02_ascii_20261019_234035\t02_current.cwc`，SHA `b28e3d4ee476731b118da0b12c3bad8dcca1dadfbd9b7ae4dc418c4d225a74ce`。
- 根目录其余文件未动：`current.bid`、`manifest.json`、`probe-map.json`、`t02_current.bid`、`t02_manifest.json`、`t02_probe-map.json`；`samples\T1`、`samples\T2` 仍在。
- 下一步：警告框点 OK，重新打开根目录唯一 CWC；若再报错，截图发主，不再重下。
