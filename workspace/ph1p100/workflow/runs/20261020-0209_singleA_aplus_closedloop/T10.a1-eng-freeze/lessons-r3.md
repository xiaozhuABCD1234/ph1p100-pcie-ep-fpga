# T10.a1-eng-freeze r3 lessons

1. **TD tcl 不能带 UTF-8 BOM**：Windows PowerShell 5.1 `Set-Content -Encoding utf8` 会写 BOM，TD Tcl 报 `invalid command name "锘?"`。用 ASCII 或 `UTF8Encoding($false)`；这是工具/流程错误，不是设计失败。
2. **P2 TB 的 plusarg 路径有长度上限**：路径过长时 `$value$plusargs` 会从左侧截断（表现为 `:\workflow\...`），只影响 p1 长 case 名。回归时给 run 目录单独 `subst W:` 缩短路径，不要误判为候选 mismatch。
3. **每 match 增加一个状态会打穿 77.76 MB/s**：S_MCHK 作为 S_MLEN→S_MDIST 的第三个 cycle 时，match-heavy 的 P2 comp 从 81.08 降到 76.93 MB/s。正确做法是让 S_MCHK 直接承担原 S_MDIST 的距离发射+abort 判断，保持 match 2 cycle。
4. **Adler-32 的每字节双 modulo 是长路径**：把输入字节寄存后做宽累加（a 22-bit / b 35-bit），块末 3 cycle 折叠 `2^16≡15、2^32≡225 (mod 65521)`，可完全移出 5.333 ns 路径，且吞吐损失 <0.1%。
5. **S2 剩余瓶颈是 hash 表预取**：`raddr → bm_a 异步读 → hash3 → htab_rd_addr (fanout 1025) → htab 读 → htab_rvalid` 仍 7.643 ns。下一轮必须在“不增加扫描 cycle”的前提下预取 bm/htab 地址；局部再拆 abort 链已无收益。
6. **收敛轨迹**：r2 -3.792 ns / 109.589 MHz → r3 S1 -2.853 / 122.160 → r3 S2 -2.374 / 129.752。方向正确，但离 187.5 MHz 仍差约 2.37 ns；r3 已用满 2 次综合、0 次布线，应由规划决定是否开 r4 及新预算。