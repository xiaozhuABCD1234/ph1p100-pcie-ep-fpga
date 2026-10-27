# T03.rk-align-freeze lessons

- 临时参考checkout可能落后于已核对Git对象；所有证据从精确commit的git archive取，不从mutable文件名推断版本。
- Windows恢复路径叠加run目录可超过MAX_PATH；首次失败保留，使用新的扩展路径恢复目录并逐项SHA校验，不能只看zip生成成功。
- host16B槽头结构、host hdr_bytes=128传输偏移和R10F128B头是三个量；CRC按有效内容与DMA尾零分层。+16每4KiB有一笔128B MWr跨界，+128只是对齐条件，还需容量/所有权。
- 工具新版本用绝对二进制+启动横幅/命令注册核实。旧DDR1333特定IP失败不能当全CLI不可用；可复用旧成功须限定范围。
- 设备枚举不是板测。FTDI双通道与蓝牙COM号不自动说明PH1P器件/JTAG/UART或RK通道。
- 有界worker只做给定头文件的文本转换，原型/偏移/位义仍由Codex独立验证；completed不等于验收通过。
