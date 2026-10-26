# T10.b8-crop-geom r0 — lessons（只记可复用的根因/触发/修正/验证入口）

## L1 根因：默认参数与实际 tap 几何不一致，是第一行就整帧丢弃

- **触发**：`a1_raw_crop` 默认 `CAM_W=3840` → `CG=960`；真实 IMX415 tap 每行 966 beat。
- **表现**：第一帧第一条 `new_line` 校验 965? 否 —— 966≠960 立刻 `st_geom_err+1`、`active<=0`；
  因 `active=0` 后续行不再校验，所以**每帧恰好 1 次** geom_err，`crop_groups` 恒 0。
- **验证入口**：`r0/board/derive_geometry.py` 用冻结的 `parse_status_v2.parse()` 复算 b7 包 0–12：
  `lines/frame=789120/360=2192.000000`、`beats-966*lines=23 (<966，采样瞬时残行)`、
  `geom_err delta=360=帧数`。改参数后同一脚本应给 3864/2192/972/556。
- **修正**：只改 4 个默认值 + `initial`/generate 参数合同；不改端口/时序/计数器。
- **不要**把“相机停流”和“crop 仍错”混为一谈：b7 从包 13 起相机域计数全 0，是板级停流。

## L2 复用“生产模块”前先看 build 文件表，不要按文件名猜

- `01_build.tcl` 实际编译的是 `csi_rx_packet_integrity.v` + `csi_rx_10bit_unpack_checked.v`；
  `fpga/csi2/prj/camera_peer/.../csi_rx_10bit_unpack.v`（vendor 原版）**不在**候选里。
- 顺手做的 vendor 对照仿真（`logs/sim_pipe_vendor_unpack.log`）显示 vendor `csi_rx_10bit_unpack`
  在 5 B 组跨 32-bit 字边界时字节序错误（`{I_data_in[15:0], r_bytes_int[23:0]}` 等分支把
  新字节顺序拼反）。所以“真实流水”必须按 build 文件表选 `*_checked` 对，否则会得到与候选无关的 FAIL。
- 结论：**仿真对象 = 候选实际编译的模块**；文件名带 "production" 不代表在候选里。

## L3 tap beat 布局与 `a1_frame_top` 文档字段序不一致（遗留风险，b8 未改）

- `csi_rx_10bit_unpack_checked` 输出 `{p3,p2,p1,p0}`（4×10 bit，p0 在 [9:0]）；
  `a1_frame_top.v` 头注释写 `in_pix[7:0]=b0 … [39:32]=b4`（5 字节 RAW10 组布局，P1 TB 用的那种）。
- crop 只做 40-bit 透传，几何不受影响；但压缩/导出的“字节含义”可能不是文档顺序。
- 处理：b8 不改冻结帧格式，只登记为 finding F2；后续若做图像质量验收，先用同一 group 同时喂
  两种布局，比较导出 raw 的字节序，再决定由谁对齐。

## L4 ModelSim 驱动脚本的坑

- `vsim -l <log>` 与 `subprocess.stdout=<同一个 log>` 同时写同一个文件 → log 变 0 字节，
  误判“没有输出”。修正：stdout 写 `<log>.out`，`-l` 只给 vsim。
- work lib / 输出路径放短临时目录（`C:\Users\czz\AppData\Local\Temp\opencode\b8`），
  再把 caps 拷回包里；包路径 >128 字符时 ModelSim 的 `-l` 会失败。
- P1 回归必须**重新编译整棵 DUT**（新 work lib）；直接复用 b7 的 `simwork` 会静默跑旧 crop。

## L5 TCL 文件的 BOM 会让 TD 直接死在第一行

- `Set-Content -Encoding utf8`（PowerShell 5.1）写 UTF-8 **BOM**；TD 报
  `invalid command name "锘?"` 后退出（exit 0！），看日志才知道根本没跑。
- 修正：`[System.IO.File]::WriteAllText($p,$t,(New-Object System.Text.UTF8Encoding($false)))`，
  并检查首字节（`#` = 35）。**退出码 0 不代表 TCL 跑成功**，必须看 console log。

## L6 盘符/会话残留

- 开工时 `T:` 仍指向 b7 的 `r0/td`，且有 2026-10-24 17:43 的孤儿 `td_commands_prompt`
  （`./01b_route_only.tcl`）活着。`td_env.ps1` 拒绝覆盖；确认 b7 已收尾后加 `-Force` 重映射，
  并在 caveat 记录孤儿进程未处理。
- 建议：每个任务开工先 `Get-PSDrive T` + `Get-Process td_commands_prompt`，再决定是否 `-Force`。

## L7 参考模型与 TB 必须逐字节对齐，而不是“计数器对得上”

- `tb_crop_geom_real` 与 `make_ref_geom.py` 第一版只差一处：TB 的 `p3` 用 `line+grp[3:0]`，
  Python 用完整 `grp`，导致每 5 字节错 1 字节（5,184,000 B 里 1,036,800 个差异），
  而 beats/sof/last/geom 全部 PASS。只有 SHA256 对比能抓到。
- 修正：把图案公式写进两处注释 + 文档，参考模型由同一公式生成后 **SHA256 必须相等**；
  TB 同时做逐拍 `out_pix !== exp_pix` 比对（`data_err`）作为第二道。
- 复用：任何“逐字节”验收都要有独立参考文件 SHA，不要只信 testbench 自比较。

## L8 参数合同：仿真断言 + 综合可失败的硬约束

- `initial` 断言用 `` `ifdef SIMULATION `` 包住，TD 不会看到 `$finish`；
  真正的硬约束用 `generate` 例化一个不存在的模块名，参数非法时仿真和综合都会 elaboration 失败。
- 这样既满足“仅仿真断言”的计划要求，又不会拿唯一一次综合去赌 `initial` 的兼容性。

## L9 行关闭时机（本次实测无需额外打拍）

- 真实流水里行尾最后一组来自 CRC 字之前的最后一个 payload 字：`packet_integrity` 先寄存 1 拍，
  `unpack_checked` 再 2 拍，下一行 `in_line` 至少在 header+1 拍，且中间还有 CRC 字/包间隔。
- `tb_crop_pipe_real` 实测 `line_in→首 beat=5`、`最后 payload 字→末 beat=3`（1 拍 handler + 2 拍 unpack），
  与下一行 `in_line` 无重叠，因此 crop 不需要额外的“1 拍行关闭”寄存器（保持输出流不变）。

## L10 TD 控制台日志是 UTF-16LE（带 NUL）

- `build_console_b8.log` / `bitgen_console_b8.log` 里有大量 `\0`（29357 个 NUL / 432 行），按 UTF-8 读会得到乱码，
  `regexp`/`in` 全部失配，manifest 里 syn/routed 变 null、bitgen_ok 变 False。
- 修正：读日志先看 NUL 比例，>1/8 按 `utf-16` 解码；或用 PowerShell `Get-Content`（会自动识别）。
- 教训：**“报告字段抓不到”先怀疑编码，不要怀疑构建没跑**。
