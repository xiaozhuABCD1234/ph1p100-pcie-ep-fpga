# 独立源码资格核对

唯一审查输入manifest SHA256为46f2c893722f2ac27beb83c20fd7867ac952f7cd0a7ab025b3fbfb71f0a9218f。本文记录实际定向读取所完成的人工资格检查，不将未完成的自动qualification脚本称作通过。

- baseline/0155.al:71–86确选changed-src/a1_frame_top.v和a1_deflate_core.v，47–53选camera_a1_uart_top.v；顶层p2_a1_board_top。与旧0141.json changed_src_sha256人工逐项对照，codec/frame/camera分别为a91c2ed8…、0064607a…、acc1eff3…，完整SHA见冻结candidate-binding.json与integrity文件。该.al含厂商未转义的UsedInP&R文本，不能直接作为标准XML解析；原59条路径的闭包资格复用同输入T02独立报告，相关文件均重新校验。
- 0146.v:171–187、326–341、542–556明确最后字完成优先；0145.v:1022–1080的abort清控制状态而不重置blk_tag/不发起有效位sweep；598–643 sweep只受reset启动，1387每块16bit递增。F02确定性接口反例成立，F11仍是未证明可达的回绕风险。
- 0146.v:393–484的样本地址排列、奇数尾n_samp=W、按HALFW重置预测锚点，与测试者直接坐标oracle相符。0054.py:67–95和S05 inverse_xform实际消费者有几何和严格性缺陷。未使用开发a1_ref或其witness实现作为本测试oracle。
- 0145.v:488–495的stored成本、1322–1343分别维护queued offset和已消费obits，1388成本取obits，1668–1677末次入队后可直接S_WAIT，支持F04 evidence_gap；没有把抽象队列状态冒充真实RTL可达轨迹。
- 当前主副本0031.v为两级Gray，0029.v用两级EOF/abort延迟和直接广播；真实upstream副本0117.v为三级Gray，0116.v有RGB/分支队列和三级marker。0026/27/28与0113/14/15分别同SHA，Gray/top不同。报告对当前副本的静态结论与旧T09时序/资源证据有明确区分，旧T09不为当前副本签核。
- 0027.v:85实际PARITY_CLAMP=0；0023.v:220–251普通replicate与parity clamp定义不同。0031.v:25–63、0027.v:133–186、0028.v:97–114/232–274/309–327/395–429/473–533支持限定标量/静态F07；非恒定HE LUT有14相位×256=3584周期，常量den=0有短路，未把3584写成所有帧必耗。
- 0028.v:166–188、395–429显示HE仅核总beats/rows；严格行几何还依赖前级rowwin。0023.v:90–114支持错位/超长/重SOF拒帧。没有将软件同bin计数扩成任意stall/reset或畸形独立HE输入正确性证明。
- 0029.v:129–244广播、分支sink及0022.v:39–83队列有不同消费者和接受事件；不支持直接删除CRC/Adler、bank或obuf。0146.v:393–409/487–539给raw/xform/stream三套CRC不同更新边界，0054.py:67–95有对应消费者。
- 0256.v:1798–1809与0111.v证明独立CLOSEDLOOP_EN三算法诊断；b15未选该链。Gray/Y8、Bayer RAW10、A+、BPR1和R10F不能凭名字合并。0150.v:529–541固定PREP/PRED，630–720恢复和837–860描述符提交保持前包契约缺口。
- 0168.md:44–64只报告b15诊断SWNS+0.012ns、ERAM+CWC102/300、一次150秒观察和enc/exported=0；0140.md:35–47只支持另一候选内部STA+0.100ns、ERAM200/300、三级Gray及选定CDC范围。0277.csv与0285.md的C1/comp、slot-free、单核187.5MHz、93.75MB/s sink和C2 sink_limited限制均保留。manual-arithmetic.json独立重算四行容量，差值均0。

自动脚本失败处只影响辅助自动汇总，不改变已保存且断言通过的几何/取消/容量/独立码流证据。independent_semantics.py两次执行后停止，未第三次运行；independent_qualification.py两次执行后停止，未第三次运行。剩余来源资格由上述实际读取、旧同输入闭包复用、独立哈希及单独算术核对完成，不声称自动qualification完成。
