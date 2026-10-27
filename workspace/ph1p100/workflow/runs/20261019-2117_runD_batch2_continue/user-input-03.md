# 用户新输入（原样保存）

```text
Windows PowerShell
Copyright (C) Microsoft Corporation. All rights reserved.

PS C:\Users\czz> tasklist | findstr /i hwserver
hwserver.exe                 37440 Console                    1         20 K
hwserver.exe                 64540 Console                    1      9,972 K
PS C:\Users\czz> netstat -ano | findstr :5555
  TCP    0.0.0.0:5555           0.0.0.0:0              LISTENING       64540
PS C:\Users\czz> tasklist | findstr /i td.exe
td.exe                       45416 Console                    1     14,712 K
PS C:\Users\czz> 选 A：0207 采完，窗口给 T02 下载、
```

## 主机械登记（非用户原话）

- 收到时间：261019 2309（上海）。
- 用户原样提供了 `tasklist` / `netstat` / `td.exe` 的 PowerShell 输出，并明确选择 **A**。
- 原始输出事实：`hwserver.exe` 有两个 PID（37440、64540）；`5555` 唯一 `LISTENING` 为 PID 64540；`td.exe` 仅 PID 45416。
- 用户选择 A 的原文：“选 A：0207 采完，窗口给 T02 下载、”。
- 硬边界不变：仅 SRAM、不写 Flash、不推送、不接 PCIe/RK；禁止 GUI 自动化；禁止批量删除；不杀他人进程。
