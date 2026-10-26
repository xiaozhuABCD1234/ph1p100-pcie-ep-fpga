# T10.a1-enc-rtl — 开发备注 / 允许清单

## 写域

仅新增：
- `upstream/ph1p100-pcie-ep-fpga/rtl/ep_side/codec/a1_deflate_core.v`
- `upstream/ph1p100-pcie-ep-fpga/sim/tb/codec/tb_a1_deflate_core.v`
- `upstream/ph1p100-pcie-ep-fpga/tools/codec/{a1_p2_gen.py,a1_p2_verify.py,run_p2.ps1,a1_p2_manifest.py}`
- `workflow/runs/.../T10.a1-enc-rtl/p2/**`、`workflow/runs/.../lessons/T10.a1-enc-rtl-lessons.md`

未修改任何既有 RTL/TB/工具、未动生产 `.al`/`build.tcl`/约束/旧 run；未下载、未 Flash、未接 PCIe/RK。

## 接口（P3 交接）

```
a1_deflate_core (
  clk, rst_n, abort,
  in_valid/in_ready/in_data[7:0],
  in_sop, in_blk_end, in_stream_end,
  out_valid/out_ready/out_data[7:0]/out_last,
  done, busy,
  stat_blocks, stat_fixed, stat_stored, stat_literals, stat_matches,
  stat_cand_aborts, stat_stall, stat_max_match, stat_max_dist)
```

- 1 块 = 1 个 2 行对（≤4800 B）；输入必须按 `in_sop` 起流、每块末拍 `in_blk_end`、整帧末拍 `in_stream_end`。
- 输出为完整 zlib 单成员（含 2 B 头与 4 B Adler）；`out_last` 只在最后字节；`done` 单周期脉冲。
- `abort`/`rst_n` 立即丢弃未完成块；`done` 与 `out_last` 均不置位。P3 的 `frame_commit` 必须由 top 依据 `done && !abort && !overflow` 生成，不能只看 `out_last`。

## 验证范围与缺口

- 覆盖：13 正向用例、80 负例、输入/输出反压、块中 abort、块中复位、不可压缩 stored、dist=2048/len=258、len=3、奇数 H 尾块、多块、尾 bit。
- **未覆盖**：完整 1080p 整帧（P3）、TD 综合/资源/时序（P4）、真实板级、真实 RAW、物理 Bayer 相位。
- 吞吐只在模块级、`out_ready=1`、无输入 gap 下测量；不能外推为整机 77.76 MB/s 已达成。P4 必须复测。
- comp 用例 87.27 MB/s 仅比 77.76 门槛高约 12%，未达 97.2 余量目标；若要提高，需并行化 tokenize/回放或更宽输出，不在本包扩围。

## 工具事实与豁免

- `vlog`/`vsim`：ModelSim ASE 10.5b（`D:\intelFPGA\18.1\modelsim_ase\win32aloem`），中文路径用 `subst X:`。
- `vlog`：Errors 0 / Warnings 0。`vsim`：5 条 `$value$plusargs` 警告（仍正确解析 plusargs）。
- **Verilator 豁免**：`D:\MSYS2\mingw64\bin\verilator_bin.exe` 在本机 shell 下启动即 `0xC0000139`（entry point / DLL），`verilator` perl wrapper 亦因 `ulimit` 调用失败；未取得 lint 输出。按计划以 vlog 为编译门槛，不伪称 Verilator 通过。
- 未安装 iverilog；未用。

## 已知 RTL 实现取舍

1. 块缓冲 `bm_a/bm_b` 使用组合读（async read），便于 P2 功能闭合；P4 映射 ERAM 时应改为同步读 + 两拍预取，语义不变但需重测。
2. 匹配搜索只在访问到的位置写 hash（跳过 match 内部位置），仍是真实 greedy LZ77，压缩率略低于逐位置插入的 P1 参考；不要求与参考逐字节相同。
3. 提前回退使用 `cand_bits + 8*remaining >= stored_bits` 的保守判定；只会更早选 stored，不产生非法流。
4. 候选固定码流从块内 bit0 打包，回放接入全局位累加器，因此跨块位偏移连续；最后一块才补零。
5. `stat_literals/matches` 是候选生成期计数，若提前回退会包含被丢弃的候选 token；判定真实 match 应使用严格解析器的 `matches`（本报告用的是后者）。

## 关键修复记录（本包内）

- 窗口同步读时序错误：`cq/fq` 改为组合寻址后修复（REPOS/PRE 后首字节错误）。
- `len_extra_val` 对 len 3..10 下溢，污染后续位；已修并加 `cp_value/op_value` 位掩码。
- 尾部残余位未写入候选 RAM，导致输出 `xx`；增加 EODONE2 残位刷新。
- 块缓冲地址只取 12 bit，4800 B 块高 704 B 覆盖低地址；改为 13-bit offset + bank（16384 深度）。
- stored 数据路径两状态/字节 → 单状态/字节，随机吞吐 91.4→178.35 MB/s。
- 负例 dynamic BTYPE 位操作由 BTYPE=11 修正为 BTYPE=10。

## 命令/退出码

见 `p2/logs/exitcodes.txt`：gen=0、vlog=0、19 次 vsim=0、verify 由 `result.json` 判定 PASS。
单 TB 超时 300 s；包级回归实际 <2 min（远低于 15 min 上限）。
