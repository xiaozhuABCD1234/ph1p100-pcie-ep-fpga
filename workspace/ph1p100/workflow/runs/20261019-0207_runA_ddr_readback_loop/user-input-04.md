# 用户输入 04（2026-10-19，原样保存）

## 用户原话

> [用户截图] 看下这样可以吗

（注：用户随消息附 1 张命令提示符截图；原图在会话中，以下为主机械转录。）

## 截图转录（主机械转录，非用户原话）

```
D:\anlogic\runa_runC\20261019_192056>cd /d D:\anlogic\runa_runC\20261019_192056

D:\anlogic\runa_runC\20261019_192056>cmd /c "D:\downlaod\bin\bw_commands_prompt.exe preload_fixed.bwcmd < NUL"
RUN-1002 : start command "connect_cable -host_name 127.0.0.1:5555 -open"
RUN-1003 : finish command "connect_cable -host_name 127.0.0.1:5555 -open" in 0.0158643s wall, 0.0000000s user + 0.015625s system = 0.015625s CPU (98.5%)
RUN-1004 : used memory is 26 MB, reserved memory is 10 MB, peak memory is 26 MB
（回显行路径呈乱码：…una_runC???61019_192056compiled.bit -mode jtag -spd 7 -cable 0"）
PRG-8000 ERROR: File path: ?1019_192056compiled.bit invalid, please modify to correct English path
（同类回显行再出现一次 + RUN-1004）
bw >
D:\anlogic\runa_runC\20261019_192056>Anlogic hwserver v1.0c (gldeb3940) Build Date 2024-12-09 17:36:53
Initialize ftdi
Use channel A
Open device vid=0x0403 pid=0x6042
Enable mpsse
Requested jtag tck: 1 MHz
Actual jtag tck: 1 MHz
Use remote bitbang protocol
Start remote bitbang server at :5555
Speed: 0.00 kbps|
```

## 主登记说明（主机械记录，非用户原话）

- 事实：用户按清单 §2 跑了 `preload_fixed.bwcmd`；`connect_cable` 成功；`download` 因路径被解析成乱码报 PRG-8000（**未发生实际写入**）；随后用户在同一窗口启动 hwserver，FTDI 设备成功打开（vid=0x0403 pid=0x6042、MPSSE、1 MHz、5555），该 hwserver 现由用户控制台持有。
- 处置：交原开发诊断 .bwcmd 路径解析/编码问题，修正脚本或由开发经现有 5555 hwserver 重试（**不得结束用户 hwserver**）；实际下载仍 ≤1 次/≤5 min、零 Flash、不推送。
- bw 日志：`D:\anlogic\runa_runC\20261019_192056\log\bw_*.log`（本次尝试应已生成）。
