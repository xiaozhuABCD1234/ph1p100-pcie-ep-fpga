# dev-notes.md — T11.runC-sim-campaign（P3）

## 1. TB 拆分与理由
- TB1（campaign）: 100 帧循环 + 坏帧注入。单 TB 自含，运行 ~5 s；小帧经参数化（P=64/128/256/512）但均 4KiB 对齐（frame_bytes=4096 -> words=1024），帧号进入 word3/载荷/word20，逐帧精确 CRC 比对（0 误判）；旧结果与当前结果因内容唯一而不可混淆（0 覆盖的直接证据）。
- TB2（1080p）: 与模块级场景同常量/同断言，改经集成 wrapper（tl 发布触发 -> dhi checker -> 读仲裁）全帧读回；与 TB1 分离，避免单 TB 超 5 min 且隔离 1080p 重场景。
- 未重跑模块级 legacy TB（tb_ddr_frame_readback_checker.v）：其 1080p 场景已由 TB2 以同常量/同断言在集成级覆盖；timeout/abort/param 类属 P1 既有模块级证据范围，本包调用预算内不重复（如测试轮需要可补跑，不影响本包判定）。

## 2. 关键契约口径（写入 TB 断言）
- status 字: [0]busy [1]done [2]magic [3]hdr [4]pay [5]len [15:8]err；优先级 abort>timeout>AXI>magic>length>hdr>pay。
- 期望值表（TB 实测一致）: 好帧 0x003E；magic 原始损坏（word0 破坏，头 CRC 随之失配）0x0132；magic 隔离（word0 破坏后重算头 CRC）0x013A；头 CRC 0x0236；载荷 CRC 0x032E；截断 len=64 0x0406/words=16；长度错 0x0406/words=1024；AXI SLVERR 0x053E。逐项 ok 位只在对应检查执行过才置位（截断/长度错不补假 PASS）。
- 幽灵发布（fi=70 busy 期间）: 契约=busy 重入丢弃（不重启不清进度）；TB 断言 runs 保持 71、hdr/pay 仍属第 70 帧。
- 结果字经 tl 域两级同步，采样需 done 后 ≥3 个 tl 边沿（TB 用 3—6 个）。

## 3. 过程记录（如实）
- 首次编译 2 处 TB 内笔误（o_hdr_crc/o_pay_crc 未声明）-> 修复后 vlog Errors:0；首次运行 B1/B3 断言口径错 2 处（B1 未计 word0 破坏对头 CRC 的连带失配；B3 破坏字越出 P=64 载荷范围）-> 修正断言（不涉 RTL/门槛）后 ALL PASS。以上均为开发内自纠，任务修复轮 0/3（round0 未开始）。
- 工件全部 UTF-8 no BOM 程序化写盘（PowerShell [IO.File]）；控制台中文乱码为输出捕获代码页现象（文件内码点正常，与 P1 §4 同结论）。
- 时间戳诚实登记：freeze 记录含实际写入时间（生成于 2026-10-19 19:0x，本地时区）。