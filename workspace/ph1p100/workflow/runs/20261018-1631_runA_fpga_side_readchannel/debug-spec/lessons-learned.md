# lessons-learned.md — T11.runB-debug-spec（可复用根因/触发/修正/验证入口）

1. **A0：JTAG“无调试核读用户寄存器”无文本层证据**。触发：想找绕过调试核的读通道。核实：TD 6.2.2（`D:/downlaod`）与 TD 2026.2（`D:/anlogic/TD_Release_2026.2`）的 `*.{tcl,txt,md}` 均无 `JTAG_REG_ACCESS` 语义文档（仅命令名在 B1 命令表）。修正/规则：**禁止盲试**；读通道只用已证 CWC。验证入口：`debug-spec/cwc-flow.md` §1。
2. **ChipWatcher 产物必须经 `setup_debugger -prj`**。触发：单跑 `export_chipwatcher` → 空白波形（缺物理 ERAM 映射）。两安装均含该流：TD 2026.2 `scripts/DefaultFlow.tcl` L265-266；6.2.2 `scripts/DefaultFlow.tcl` L228-229。验证入口：`cwc-flow.md` §2。
3. **常量寄存器无法直接探针**：MAGIC/EXT_MAGIC/EXT_VERSION 是编译期参数 → 用只读字库/常量线承载；否则 CWC 采不到。验证入口：`probe-map.md` §2/§4。
4. **diag 选址先例与安全检索法**：非合同 diag 可继 0x120..0x12C 先例；候选段用 `registers.json` 十进制 offset 正则检索（无 ≥320 dword 占用）后暂定，P1 elaboration 复核 + 顺延规则兜底。验证入口：`probe-map.md` §2。
5. **CTRL(0x44) 复位默认全关**（enable/ddr_en/push_en/push_src 均 0）：不默认开启就无写者基线。debug 版最小开启只动 bit0/bit5；push/TX 面必须保持 0；且只在 debug 入口（不改 `00_all`）。验证入口：`enable-state.md`。
6. **记录 schema 的 channel enum 无 CWC 值**：需在 run 内声明扩展（`chipwatcher-jtag`）并保留兼容字段。验证入口：`readback-criteria.md` §3。
7. **BW 通道复用要点（引用 B1，避免重踩）**：bit 路径必须 ASCII；脚本相对路径 + 环境变量传参；`PRG-2014` + rc=0 + 28–40 s 为成功口径；旁路 `usb_open() failed` 不判败。验证入口：`board-runbook.md` §1。
