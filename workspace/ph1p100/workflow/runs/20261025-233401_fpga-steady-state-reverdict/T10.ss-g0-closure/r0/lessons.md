# lessons — `T10.ss-g0-closure`（可复用根因/触发/修正/验证入口）

1. **冻结向量是 transform-domain，不是 raw**
   - 现象：直接把 comp `in.hex` 当像素注入，链上 `PREP_EN=PRED_EN=1` 会再做一次差分，核看到的不是该向量，cycles/B 与锚点无关。
   - 修正：用 P1 格式模型 `a1_ref.inverse_frame(tiled,1920,1080,1,1)` 逆变换成 packed RAW10；DUT 正向变换还原。
   - 验证：`prep_content.py` 的 `forward(inverse(tiled))==tiled`；R3 导出帧头 `raw_crc/xform_crc` 与 Python 期望逐值相等（DUT 自证）。
   - 复用：任何“把 core-only 向量喂进链”的任务先确认域与 PREP/PRED 配置。

2. **TB 自检的分组计数差一**
   - 现象：`vn = vn + 1; if (vn == 3)` 在第 3 个样本触发，导致每平面 320 而非 240 组、`checked=691,200`、比对错位（R3 日志 `bad=691132`）。
   - 修正：2-bit 计数器自然回绕，比较 `vn == 0`（每 4 个样本一次）。
   - 验证：`v1` check-only 复跑 `SS_VEC_MATCH bad=0 checked=518400`；该检查只读，不驱动 DUT。
   - 复用：分组计数器一律“自增后判回绕”或 3-bit 判 4；不要用位宽=组长的计数器判满值。

3. **P1 继承的 `B11_FULL_READ_DONE` 等待（2×129600）**
   - 现象：`FRAMES=1` 时 `st_read` 永远到不了 259,200，initial 块等到 `MAX_CYCLES` 才写 stats；若 `MAX_CYCLES` 恰为等待上限，always 块的 timeout 先 `$finish`，stats/末行标记全部丢失。
   - 修正：check-only run 用较小的 `MAX_CYCLES` 并在帧 1 后早打印自检结果；不要为 1 帧 run 改统计门槛。
   - 复用：派生 TB 的“信息性等待”在少帧模式下可能变成实际超时；少帧 run 必须核对等待条件。

4. **长仿真不要用后台 shell**
   - 现象：后台启动的 vsim 在 shell 返回后看起来 CPU 0、日志停更（实际是子进程树/统计口径问题；本次误判后 kill 了仍在运行的 v1）。
   - 修正：单次全尺寸 `vsim` 用前台调用 + 显式 2700 s 超时；只在能确认进程存活时后台化。
   - 复用：ModelSim 长跑只以前台 + `-l` 日志 + 固定超时为默认。

5. **PowerShell 改写 UTF-8 源文件会毁编码**
   - 现象：`Get-Content -Raw` + `Set-Content` 把 UTF-8 中文按 ANSI 解码/回写，Python 文件出现 `SyntaxError`。
   - 修正：源码编辑只用 edit/write 工具；必须脚本改写时以 `open(...,'rb')`/`'wb'` 处理字节。
   - 复用：任何含非 ASCII 的脚本不要经 PowerShell 文本管道重写。

6. **口径结论**
   - sink 从 18.75 MB/s 提到 2 GHz 只改变 `L_cold` 与 tail，不改变 `S_ss`（常数 tail 在帧间差抵消）；`L_cold` 不能当吞吐。
   - strict-serial 代价 36.09%（R2−R1），G0 的通过依赖 slot-free 交叠；不得用 serial 冒充 overlap。
   - A2（assumed）仍 −2.67%，实测 comp 代理 +5.43%：假设外推不是实测上界，报告必须并列。

## round1（2026-10-26）

7. **关键 run 的自检必须与 timing 同 run 同 TB**：R3 的 `bad=0` 不能来自另一个 TB 版本的 check-only run；用冻结 TB 重跑关键 run，并在同一日志里保留 `SS_VEC_MATCH`。
8. **raw 字节元数据不要用 `read_text()` 计数/哈希**：Windows 换行归一化会把 330 B 的 `in.meta` 记成 297 B/normalized SHA；一律 `read_bytes()`。
9. **白名单外的 TB-only 改动也要事先获批**：`WD_LIMIT`、`.dec` 文本格式、`+HDR`、追加字段都应在计划里列明，否则工程门槛会 FAIL。
10. **sink 要写实测率而不是请求值**：2 GHz 请求 200 MB/s，a1 域交接实测 93.75 MB/s；raw band 的 tail 27.7 ms（83%）会限速，proxy 的 1,697,820（28.6%）不会。
