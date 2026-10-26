# 用户输入 05（2026-10-19，原样保存）

## 用户原话

> [用户粘贴命令提示符全文] 分析吧

## 用户粘贴的完整输出（原样）

```
Microsoft Windows [版本 10.0.26200.9711]
(c) Microsoft Corporation。保留所有权利。

C:\Users\czz>tasklist | findstr /i hwserver
hwserver.exe                 74620 Console                    1      9,376 K
hwserver.exe                 37440 Console                    1         20 K

C:\Users\czz>taskkill /PID 45596 /F
错误: 没有找到进程 "45596"。

C:\Users\czz>
C:\Users\czz>cd /d D:\anlogic\runa_runC\20261019_192056

D:\anlogic\runa_runC\20261019_192056>D:\downlaod\bin\bw_commands_prompt.exe read_id_v5.bwcmd < NUL
RUN-1002 : start command "connect_cable -host_name 127.0.0.1:5555 -open"
RUN-1003 : finish command "connect_cable -host_name 127.0.0.1:5555 -open" in  0.017136s wall, 0.000000s user + 0.000000s system = 0.000000s CPU (n/a%)

RUN-1004 : used memory is 26 MB, reserved memory is 10 MB, peak memory is 26 MB
RUN-1002 : start command "read_device_id"
Anlogic hwserver v1.0c (g1deb3940) Build Date 2024-12-09 17:36:53
Initialize ftdi
PH1P100
RUN-1003 : finish command "read_device_id" in  0.025490s wall, 0.000000s user + 0.000000s system = 0.000000s CPU (n/a%)

RUN-1004 : used memory is 27 MB, reserved memory is 10 MB, peak memory is 27 MB
RUN-1002 : start command "connect_cable -close"
RUN-1003 : finish command "connect_cable -close" in  0.000459s wall, 0.000000s user + 0.000000s system = 0.000000s CPU (n/a%)

RUN-1004 : used memory is 27 MB, reserved memory is 10 MB, peak memory is 27 MB

bw >
D:\anlogic\runa_runC\20261019_192056>D:\downlaod\bin\bw_commands_prompt.exe download_v5.bwcmd < NULcd /d D:\anlogic\runa_runC\20261019_192056
系统找不到指定的文件。

D:\anlogic\runa_runC\20261019_192056>D:\downlaod\bin\bw_commands_prompt.exe read_id_v5.bwcmd < NUL
RUN-1002 : start command "connect_cable -host_name 127.0.0.1:5555 -open"
RUN-1003 : finish command "connect_cable -host_name 127.0.0.1:5555 -open" in  0.015578s wall, 0.000000s user + 0.000000s system = 0.000000s CPU (n/a%)

RUN-1004 : used memory is 26 MB, reserved memory is 10 MB, peak memory is 26 MB
RUN-1002 : start command "read_device_id"
Anlogic hwserver v1.0c (g1deb3940) Build Date 2024-12-09 17:36:53
Initialize ftdi
Use channel A
Open device vid=0x0403 pid=0x6042
PH1P100
RUN-1003 : finish command "read_device_id" in  0.028233s wall, 0.000000s user + 0.000000s system = 0.000000s CPU (n/a%)

RUN-1004 : used memory is 26 MB, reserved memory is 10 MB, peak memory is 26 MB
RUN-1002 : start command "connect_cable -close"
RUN-1003 : finish command "connect_cable -close" in  0.001493s wall, 0.000000s user + 0.000000s system = 0.000000s CPU (n/a%)

RUN-1004 : used memory is 27 MB, reserved memory is 10 MB, peak memory is 27 MB

bw >
D:\anlogic\runa_runC\20261019_192056>D:\downlaod\bin\bw_commands_prompt.exe download_v5.bwcmd < NUL
RUN-1002 : start command "connect_cable -host_name 127.0.0.1:5555 -open"
RUN-1003 : finish command "connect_cable -host_name 127.0.0.1:5555 -open" in  0.024659s wall, 0.015625s user + 0.000000s system = 0.015625s CPU (63.4%)

RUN-1004 : used memory is 26 MB, reserved memory is 10 MB, peak memory is 26 MB
RUN-1002 : start command "download -bit D:/anlogic/runa_runC/20261019_192056/compiled.bit -mode jtag -spd 7 -cable 0"
Anlogic hwserver v1.0c (g1deb3940) Build Date 2024-12-09 17:36:53
Initialize ftdi
Use channel A
Open device vid=0x0403 pid=0x6042
PRG-2014 : Chip validation success: PH1P100
Error @ mpsse.cpp:90 : usb_open() failed

0%   10   20   30   40   50   60   70   80   90   100%
|----|----|----|----|----|----|----|----|----|----|
***************************************************
RUN-1003 : finish command "download -bit D:/anlogic/runa_runC/20261019_192056/compiled.bit -mode jtag -spd 7 -cable 0" in 30.037585s wall, 1.312500s user + 0.265625s system = 1.578125s CPU (5.3%)

RUN-1004 : used memory is 27 MB, reserved memory is 12 MB, peak memory is 190 MB
RUN-1002 : start command "read_device_id"
PH1P100
RUN-1003 : finish command "read_device_id" in  0.032953s wall, 0.000000s user + 0.000000s system = 0.000000s CPU (n/a%)

RUN-1004 : used memory is 28 MB, reserved memory is 12 MB, peak memory is 190 MB
RUN-1002 : start command "connect_cable -close"
RUN-1003 : finish command "connect_cable -close" in  0.000096s wall, 0.000000s user + 0.000000s system = 0.000000s CPU (n/a%)

RUN-1004 : used memory is 28 MB, reserved memory is 12 MB, peak memory is 190 MB
```

## 主登记说明（主机械记录，非用户原话）

- 事实（机械比对清单 §2 判据）：`download_v5.bwcmd` 执行中 `PRG-2014 : Chip validation success: PH1P100` 出现、进度条到 100%、RUN-1003 finish 30.037585 s（≈28–40 s 区间）；`Error @ mpsse.cpp:90 : usb_open() failed` 属清单 §2 注明的“bw 自动拉起的第二实例”旁路提示，不单独判败；下载后 `read_device_id`=PH1P100。**据此机械记录为“预加载成功（待原开发复核并冻结 v6）”**。
- 过程小插曲：一条命令粘贴时与 `cd /d ...` 粘连，报“系统找不到指定的文件”（无副作用）；旧 PID 45596 已不在。
- 现 hwserver 进程：74620（用户控制台实例）+ 37440（bw 自动拉起实例，20 K）。
- 交原开发：复核并按清单判据记录预加载成功（操作者=用户、时间/时区、命令、时长 30.04 s、bit SHA 5B67A8F5…）、更新板载状态、冻结 v6（只追加）；随后交用户“可以点了”（§3 点两下）。
