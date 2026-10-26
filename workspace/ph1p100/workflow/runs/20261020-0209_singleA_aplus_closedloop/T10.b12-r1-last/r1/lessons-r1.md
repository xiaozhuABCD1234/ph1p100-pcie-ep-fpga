# T10.b12-r1-last r1 — lessons

## 从已布线 DB 出 bit/CWC（可复用套路）

1. **r0 布线 DB 可以安全复用**：`open_project ./a1_board.al` + `import_db ./a1_board_Runs/phy_1/a1_board_pr.db`
   + `update_timing -mode final` 即可在**不重跑综合/布线**的前提下拿到 final STA 并 bitgen。
   本轮实测 bitgen 约 40 s、CWC 约 20 s，总耗时 ~25 min（含读材料/写文档），无需后台等待。
2. **工具门槛 ≠ 计划门槛**：`02_bitgen.tcl` 只拒绝 `sw<0 || hw<0 || pw<0` 或异常端点；
   **+0.003 这种“正但很薄”的值会被工具放行**。dev-plan 的 +0.015/+0.05 是人类裁决，必须在脚本外判，
   否则“工具成功”会被误读成“门槛通过”。本包 r0 正确地停在门槛外，r1 在用户书面裁决后才出 bit。
3. **BID 不要单独再跑一次 bitgen**：`02_bitgen.tcl` 里已经有 `export_bid a1_board_inst.bid`，
   BID 与 bit 同会话、同 DB 导出，天然配对；为拿 BID 再 bitgen 会直接击穿 “bitgen 1 次” 预算。
4. **`compiled.bit == 父 bit` 是 CWC 的唯一硬判据**：`03_cwc.tcl` 用二进制比较 `a1_board.bit` 与 `cw/compiled.bit`，
   CWC 同理。本轮两次都逐字节相同（`9180DB8C…` / `FFB88419…`），说明 `setup_debugger` 在这套工程上不会改 bit；
   一旦不相等必须停，不能“先下载看看”。

## 冻结/记账陷阱

5. **TD `open_project` 会重写 `.al`**：25,142 B → 25,072 B（59 个 `<File Path>` 一个不少，RTL/SDC/ADC 未变）。
   b11 r0 也发生过（→ 25,184 B，已登记）。若 manifest 冻结了 `.al` 哈希，**必须在打开前备份**，
   或干脆把 TD 工程目录复制/junction 到新轮次再打开；否则 r0 的 `.al` 哈希无法复验。
   补救方式（本轮采用）：manifest 同时绑定**实质输入**（布线 DB、SDC、ADC、RTL 9 文件）的哈希，并单独冻结打开后的 `.al`。
6. **薄余量必须机器可读**：manifest 里放 `acceptance.timing_caveat = thin_margin_+0.003`、
   `acceptance.scope = diagnostic candidate only / not production / not board sign-off`，
   result 里再用人话写一遍“生产版需补流水”。只写在 result 正文，下游脚本/汇总会漏。
7. **配对冻结**：bit 与 CWC 是一次 bitgen+CWC 的产物，`compiled.bit/cwc` 与父文件同哈希；
   若后续任何重跑，必须整对重出，禁止拿旧 CWC 配新 bit。

## 板级

8. **FTDI 预检成本极低（<30 s），且board=blocked 是合法完成**：本 run 已连续三轮 `0403:6042` 不在位
   （只有 COM3/COM4）。预检一次即可写 blocked、0 下载、0 COM8、不重试；不要为了“也许插上了”反复探测，
   也不要先开 COM8 再发现没设备。
9. **没上板就不要借 r0 的仿真 PASS 说硬件有效**：result 必须显式写“无板级证据、不宣称 R1 在硬件上有效”，
   并把 1176 读停点继续留在 H2/H4，不与 R1 结论混写。

## 流程

10. **r1 不新增仿真时，证据绑定要写清**：综合测试者若复用 r0 的 PASS，必须在 r1 manifest 里按哈希绑定
    `r0/changed-src/**` 与 `r0/sim/**`；不能把 r0 输入下的 PASS 当作 r1 输入下的 PASS（本轮 RTL 未变，
    所以可以绑定，但要写成显式动作而不是默认）。
11. **预算记账**：本轮 2 条 TD 命令、~20 次工具调用、~25 min；`T:` 仍指向 r0/td 才能复用 DB，
    不要为了“整洁”把 DB 复制到 r1 再跑——复制 32 MB DB 只会引入路径/权限问题。
