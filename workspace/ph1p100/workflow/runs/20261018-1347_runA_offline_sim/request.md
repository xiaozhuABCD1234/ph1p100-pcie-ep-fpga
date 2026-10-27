# 本轮需求（用户原话，原样保存）

## 用户原话

> OK按建议我确定可以授权，然后开始做，不过我要大概一小时后来，这一小时你先进行模拟验证部分，后面我会和你一起进行上板以及观察等验证

## 上下文（主登记，非用户原话）

- 上一条规划产出的开工前清单：workflow/runs/20261018-0001_merge_raw_into_upstream/user-precheck.md
  - §1.5 四个拍板默认值：A 仅 SRAM；B 用当前 bit `e81d353b…2b9a`；C 允许重启/复位；D 允许先 100 帧 + 10 分钟短稳。用户本次说“按建议我确定可以授权”，按默认值登记。
- 上一 run（已 finished）：workflow/runs/20261018-0001_merge_raw_into_upstream/
  - FPGA 原仓检出：upstream/ph1p100-pcie-ep-fpga，分支 codex/raw10-rka1，commit ab811c8f820c3ae6601507b54ec45a74c6607855（未推送）
  - 离线验收：G1（repo-merge/）、G2（repo-build/，bit e81d353b…），三份 r0 PASS 报告
  - RK 配套包：rk-package/
- 用户本轮明确约束：
  1. 现在先做**模拟验证部分**（约一小时内），不上板；
  2. 用户约一小时后回来，再一起进行上板与观察等验证；
  3. 上板授权按 user-precheck §1.5 默认值（仅 SRAM、当前 bit、可重启复位、100 帧+10 分钟短稳）。
- 原规划建议：后两步拆成两个 run；本 run 对应当前可离线推进的模拟验证切片，板上包留待用户在场时另起/续接。
